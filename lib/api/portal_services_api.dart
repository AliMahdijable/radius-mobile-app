import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «خدماتنا» (١٦ نوفمبر ٢٠٢٦ — المالك: «اضف ميزه ثانيه بالتطبيق والويب وهي خدماتنا او تطبيقاتنا حقل اسم وحقل رابط التطبيق
/// وحقل صورة التطبيق النظام يضغطها قدر الامكان بحيث بالعرض تطلع صور التطبيق واسمه بالنقر ع التطبيق يوديهم للرابط»).
///
/// تطبيقات الوكيل وصفحاته — يراها مشتركوه في «وكيلي» بتطبيق MyServices ويفتحون الرابط بنقرة. الخادم server/portalServices.js
/// (1c052aa): `GET/POST /api/v2/portal/services` · `PUT …/order` · `PUT/DELETE …/:id`. القراءة لكلّ مستخدمي الحساب، والكتابة
/// بـ`settings.edit`. الصورة يضغطها التطبيق قبل الرفع ([prepareServiceIcon] — مربّعٌ 256 بكسل)، والخادم يفحص بايتاتها (≤ 300 ك.ب).
class PortalService {
  const PortalService({required this.id, required this.name, required this.url, this.image});

  final int id;
  final String name;
  final String url;

  /// عنوان الصورة المطلق على خادمنا (يحمل بصمتها) أو null.
  final String? image;

  String get initial {
    final s = name.trim();
    return s.isEmpty ? '•' : String.fromCharCode(s.runes.first).toUpperCase();
  }

  /// المضيف وحده بلا www — للقائمة.
  String get host {
    final h = Uri.tryParse(url)?.host ?? '';
    return h.isEmpty ? url : h.replaceFirst(RegExp(r'^www\.'), '');
  }

  static PortalService? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = int.tryParse('${raw['id']}');
    final name = (raw['name'] ?? '').toString().trim();
    final url = (raw['url'] ?? '').toString().trim();
    if (id == null || name.isEmpty || url.isEmpty) return null;
    final img = (raw['image'] ?? '').toString().trim();
    return PortalService(
      id: id,
      name: name,
      url: url,
      image: img.isEmpty ? null : (img.startsWith('/') ? '${ApiClient.baseUrl}$img' : img),
    );
  }
}

enum ServicesLoad { ok, unavailable, failed, denied }

/// صورةٌ جاهزة للرفع: بايتاتها ونوعها.
class ServiceImage {
  const ServiceImage(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

typedef ServiceWrite = ({bool ok, PortalService? service, bool denied, String? message});

class PortalServicesApi {
  PortalServicesApi._();

  static const path = '/api/v2/portal/services';

  /// حدّ الخادم (يرسله مع القائمة؛ هذا لما قبل وصولها).
  static const defaultLimit = 12;
  static const nameMax = 40;

  static Future<({ServicesLoad state, List<PortalService> services, int limit})> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path);
      final b = r.data;
      if (r.statusCode == 403) return (state: ServicesLoad.denied, services: const <PortalService>[], limit: defaultLimit);
      if (r.statusCode != 200 || b?['success'] != true) {
        return (state: ServicesLoad.failed, services: const <PortalService>[], limit: defaultLimit);
      }
      final limit = int.tryParse('${b?['limit']}') ?? defaultLimit;
      if (b?['available'] == false) return (state: ServicesLoad.unavailable, services: const <PortalService>[], limit: limit);
      return (state: ServicesLoad.ok, services: _servicesOf(b?['services']), limit: limit);
    } catch (e) {
      _log('list', e);
      return (state: ServicesLoad.failed, services: const <PortalService>[], limit: defaultLimit);
    }
  }

  static Future<ServiceWrite> create({required String name, required String url, ServiceImage? image}) =>
      _write(() => ApiClient.dio.post<Map<String, dynamic>>(path, data: {
            'name': name,
            'url': url,
            if (image != null) 'image': image.dataUrl,
          }));

  /// [image]: null = كما هي · [ServiceImage] = جديدة · [removeImage] = حذفها.
  static Future<ServiceWrite> update(int id, {String? name, String? url, ServiceImage? image, bool removeImage = false}) =>
      _write(() => ApiClient.dio.put<Map<String, dynamic>>('$path/$id', data: {
            if (name != null) 'name': name,
            if (url != null) 'url': url,
            if (image != null) 'image': image.dataUrl else if (removeImage) 'image': null,
          }));

  static Future<({bool ok, bool denied, String? message})> remove(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>('$path/$id');
      if (r.statusCode == 200 && r.data?['success'] == true) return (ok: true, denied: false, message: null);
      return (ok: false, denied: r.statusCode == 403, message: _refusal(r));
    } catch (e) {
      _log('remove', e);
      return (ok: false, denied: false, message: null);
    }
  }

  static Future<({List<PortalService>? services, bool denied, String? message})> order(List<int> ids) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('$path/order', data: {'ids': ids});
      if (r.statusCode == 200 && r.data?['success'] == true) {
        return (services: _servicesOf(r.data?['services']), denied: false, message: null);
      }
      return (services: null, denied: r.statusCode == 403, message: _refusal(r));
    } catch (e) {
      _log('order', e);
      return (services: null, denied: false, message: null);
    }
  }

  static Future<ServiceWrite> _write(Future<Response<Map<String, dynamic>>> Function() send) async {
    try {
      final r = await send();
      final b = r.data;
      if ((r.statusCode == 200 || r.statusCode == 201) && b?['success'] == true) {
        return (ok: true, service: PortalService.fromJson(b?['service']), denied: false, message: null);
      }
      return (ok: false, service: null, denied: r.statusCode == 403, message: _refusal(r));
    } catch (e) {
      _log('write', e);
      return (ok: false, service: null, denied: false, message: null);
    }
  }

  static List<PortalService> _servicesOf(Object? raw) {
    if (raw is! List) return const [];
    return [for (final x in raw) if (PortalService.fromJson(x) case final s?) s];
  }
}

String? _refusal(Response<Map<String, dynamic>> r) {
  final m = r.data?['message'];
  if (m is! String) return null;
  final t = m.trim();
  return t.isNotEmpty && RegExp(r'[؀-ۿ]').hasMatch(t) ? t : null;
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[PortalServicesApi] $tag: $e');
}
