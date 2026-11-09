import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/merged_company.dart';
import '../models/network_device.dart';
import '../services/merged_mode.dart';
import 'api_client.dart';
import 'company_route.dart';

/// قائمة أجهزة شركةٍ واحدة في «كل الشركات».
class MergedDevicesPart {
  const MergedDevicesPart({required this.company, this.devices, this.error, this.open = false});

  final MergedCompany company;

  /// null = تعذّرت قائمتها — لا تُعرض «لا أجهزة» ولا تُعدّ صفراً.
  final List<NetworkDevice>? devices;

  /// نصّ الخادم العربيّ للتعذّر (أو نصٌّ يسمّي الشركة).
  final String? error;

  /// الشركة المفتوحة: أجهزتها وحدها تُدار هنا (صفحة الجهاز الحيّة، التعديل، الحذف، الإضافة).
  final bool open;

  bool get failed => devices == null;
}

/// «كل الشركات» في قسم الأجهزة (٧ نوفمبر — المالك: «دمج الأجهزة… بنفس فكرة عرض المشتركين والاختيار بين الكل وشركة»):
/// أجهزة كلّ شركةٍ من شركات الحساب بطلبٍ موجَّه (x-company-key ⇒ مدخل الخادم network-devices-list: القائمة وحدها، بلا
/// كلمات سرّ الأجهزة)، والشركة المفتوحة بطلبها العاديّ.
///
/// كلّ صفٍّ يُتحقَّق: معرّفٌ موجبٌ غير مكرّر، ومديره مدير الشركة نفسها. صفٌّ واحدٌ مخالف يُسقط قائمة الشركة كلّها («تعذّرت»)
/// بدل أن يُنسب جهازٌ لغير شركته. وردٌّ بلا `success:true` وقائمةٍ صريحة تعذّرٌ لا «صفر أجهزة».
class MergedDevicesApi {
  MergedDevicesApi._();

  /// قائمتان معاً على الأكثر — كمشتركي «كل الشركات».
  static const concurrency = 2;

  /// صفوف الردّ ⇒ أجهزة [c]، أو null إن لم يكن الردّ قائمةً صالحة لها.
  @visibleForTesting
  static List<NetworkDevice>? parse(MergedCompany c, Object? body) {
    if (body is! Map || body['success'] != true || body['data'] is! List) return null;
    final admin = c.adminId.trim();
    if (admin.isEmpty) return null;
    final out = <NetworkDevice>[];
    final ids = <int>{};
    for (final row in body['data'] as List) {
      if (row is! Map) return null;
      final NetworkDevice d;
      try {
        d = NetworkDevice.fromJson(Map<String, dynamic>.from(row));
      } catch (_) {
        return null;
      }
      if (d.id <= 0 || d.adminId.trim() != admin || !ids.add(d.id)) return null;
      out.add(d);
    }
    return out;
  }

  /// [MergedMode.failText]: للمالك رسالة الخادم أو [fallback] كما كان؛ للموظّف باسم الصفحة دائماً (رفض صلاحيّةٍ هناك يُسمّيها).
  static String _err(MergedCompany c, Object? body, String fallback, [int? status]) =>
      MergedMode.failText(c, body, fallback, status: status);

  /// أجهزة [c] — موجَّهةً لشركتها، أو بطلب الجلسة نفسها إن كانت المفتوحة ([open]). لا يرمي.
  static Future<MergedDevicesPart> one(MergedCompany c, {bool open = false}) async {
    final failed = 'تعذّر جلب أجهزة «${c.name}» الآن';
    // «كل الصفحات»: لا devices.view له في هذه الصفحة ⇒ لا تُطلب أجهزتها، وتُسمّى (والفحص الشامل لا يشملها)
    if (MergedMode.pagePerm(c.key, 'devices.view') == false) {
      return MergedDevicesPart(company: c, error: '«${c.name}»: ${MergedMode.noAccess('أجهزتها')}', open: open);
    }
    if (!CompanyRoute.keyRe.hasMatch(c.key) || c.adminId.trim().isEmpty) {
      return MergedDevicesPart(company: c, error: failed, open: open);
    }
    Future<MergedDevicesPart> fetch() async {
      try {
        final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/admin/devices');
        final rows = parse(c, r.data);
        if (rows == null) return MergedDevicesPart(company: c, error: _err(c, r.data, failed, r.statusCode), open: open);
        return MergedDevicesPart(company: c, devices: List.unmodifiable(rows), open: open);
      } on DioException catch (e) {
        return MergedDevicesPart(company: c, error: _err(c, e.response?.data, failed, e.response?.statusCode), open: open);
      } catch (_) {
        return MergedDevicesPart(company: c, error: failed, open: open);
      }
    }

    return open ? fetch() : CompanyRoute.run(c.key, fetch);
  }

  /// أجهزة [companies] بترتيبها. صفحتان لمديرٍ واحد (المعرّف نفسه) قائمتهما واحدة ⇒ تُجلب للأولى وحدها. [openAdminId]: معرّف
  /// مدير الجلسة المفتوحة — شركته تُجلب بطلبها العاديّ وتُعلَّم [MergedDevicesPart.open].
  static Future<List<MergedDevicesPart>> load(List<MergedCompany> companies, {String? openAdminId}) async {
    final seen = <String>{};
    final todo = <MergedCompany>[
      for (final c in companies)
        if (seen.add(c.adminId.trim())) c,
    ];
    final open = openAdminId?.trim();
    final results = List<MergedDevicesPart?>.filled(todo.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final i = next++;
        final c = todo[i];
        results[i] = await one(c, open: open != null && open.isNotEmpty && c.adminId.trim() == open);
      }
    }

    await Future.wait([for (var w = 0; w < concurrency && w < todo.length; w++) worker()]);
    return List.unmodifiable(results.whereType<MergedDevicesPart>());
  }
}
