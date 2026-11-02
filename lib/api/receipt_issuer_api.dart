import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'receipt_settings_api.dart';

/// «أصدره» على الوصل باسمٍ يختاره المدير لنفسه ولموظّفيه (٢ نوفمبر — المالك: «المدراء كلها تجي admin@ وبدون اسم، نريد يطبع اسم
/// عربي يخصّصه المدير بالطباعة، وكذلك اسم عربي للموظّف»؛ الخادم server/receiptIssuer.js):
///   GET /api/v2/receipt-settings/issuer-names ⇒ {owner, owner_default, max, employees: [{id, username, full_name, active, name}]}
///   PUT … {owner?, employees?: {id: name|null}} — بصلاحيّة «قوالب الطباعة»؛ الفارغ يعيد السلوك السابق.
class IssuerEmployee {
  const IssuerEmployee({required this.id, required this.username, this.fullName, this.active = true, this.name});
  final int id;
  final String username;
  final String? fullName;
  final bool active;
  final String? name;

  /// كما يُعرف في قائمة الموظّفين.
  String get label => (fullName ?? '').trim().isNotEmpty ? fullName!.trim() : username;
}

class IssuerNames {
  const IssuerNames({this.owner, this.ownerDefault, this.max = 40, this.employees = const []});
  final String? owner;
  final String? ownerDefault;
  final int max;
  final List<IssuerEmployee> employees;

  static String? _s(Object? v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static IssuerNames? fromJson(Object? d) {
    if (d is! Map) return null;
    final list = d['employees'] is List ? (d['employees'] as List).whereType<Map>() : const <Map>[];
    return IssuerNames(
      owner: _s(d['owner']),
      ownerDefault: _s(d['owner_default']),
      max: int.tryParse('${d['max'] ?? ''}') ?? 40,
      employees: [
        for (final e in list)
          if (int.tryParse('${e['id']}') != null)
            IssuerEmployee(
              id: int.parse('${e['id']}'),
              username: _s(e['username']) ?? '#${e['id']}',
              fullName: _s(e['full_name']),
              active: e['active'] != false,
              name: _s(e['name']),
            ),
      ],
    );
  }
}

class ReceiptIssuerApi {
  ReceiptIssuerApi._();

  static const _path = '/api/v2/receipt-settings/issuer-names';

  static String _err(Object? b, String fallback) => b is Map && (b['message']?.toString().trim().isNotEmpty ?? false) ? b['message'].toString() : fallback;

  /// (data, error) — خادمٌ أقدم ⇒ error.
  static Future<({IssuerNames? data, String? error})> load() async {
    try {
      final r = await ApiClient.dio.get<dynamic>(_path);
      final b = r.data;
      final d = b is Map && b['success'] == true ? IssuerNames.fromJson(b['data']) : null;
      if (d == null && r.statusCode == 404) return (data: null, error: 'تحتاج تحديث الخادم');
      if (d == null && r.statusCode == 403) return (data: null, error: 'لا صلاحيّة لتعديل قوالب الطباعة');
      return d == null ? (data: null, error: _err(b, 'تعذّرت قراءة الأسماء')) : (data: d, error: null);
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 issuer-names GET: ${e.response?.statusCode}');
      final st = e.response?.statusCode;
      return (data: null, error: st == 404 ? 'تحتاج تحديث الخادم' : st == 403 ? 'لا صلاحيّة لتعديل قوالب الطباعة' : _err(e.response?.data, 'تعذّر الاتّصال — أعد المحاولة'));
    } catch (_) {
      return (data: null, error: 'تعذّر الاتّصال — أعد المحاولة');
    }
  }

  /// يحفظ [owner] (null = لا تغيير، '' = يُمحى) و[employees] (id ⇒ الاسم، '' يمحو) ⇒ (data, error).
  static Future<({IssuerNames? data, String? error})> save({String? owner, Map<int, String>? employees}) async {
    try {
      final r = await ApiClient.dio.put<dynamic>(_path, data: {
        if (owner != null) 'owner': owner,
        if (employees != null) 'employees': {for (final e in employees.entries) '${e.key}': e.value},
      });
      final b = r.data;
      final d = b is Map && b['success'] == true ? IssuerNames.fromJson(b['data']) : null;
      if (d != null) unawaited(ReceiptSettingsApi.fetch(force: true)); // الطباعة التالية تقرأ الاسم الجديد
      return d == null ? (data: null, error: _err(b, 'تعذّر الحفظ')) : (data: d, error: null);
    } on DioException catch (e) {
      final st = e.response?.statusCode;
      return (data: null, error: st == 403 ? 'لا صلاحيّة لتعديل قوالب الطباعة' : _err(e.response?.data, 'تعذّر الحفظ — أعد المحاولة'));
    } catch (_) {
      return (data: null, error: 'تعذّر الحفظ — أعد المحاولة');
    }
  }
}
