import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'report_period.dart';
import 'report_sheets.dart';

/// آخر فترةٍ وفلاتر لكلّ تقرير (بند المقترح ٩): الفلاتر وحدها — الأرقام حيّةٌ كلّ فتح. الفترة الجاهزة تُحفظ باسمها فتُحسب من
/// جديد («هذا الشهر» يبقى هذا الشهر غداً). تعذّر التخزين ⇒ الافتراض بلا خطأ.
///
/// مدراء [openGroup] وموظّفوها (الشركة المفتوحة) أرقامٌ داخل شركتها وحدها ⇒ تُحفظ معها بصمتها [openTag] (معرّف مديرها)، وتُسقط
/// حين تُفتح شركةٌ غيرها: «علي» المختار في سوبرنت لا يصير رقم 101 في ايرث لنك. مفاتيح «كل الشركات» فريدةٌ لكلّ ربطٍ فتبقى.
class RpPrefs {
  RpPrefs._();

  static const openGroup = 'open';

  static String _key(String report) => 'report.v2.$report';

  /// [fallback] فترة التقرير أوّل مرّة (سجلّ الحركات: هذا الأسبوع كما كان).
  static Future<RpFilterValue> load(String report,
      {required DateTime now, String? openTag, RpPreset fallback = RpPreset.thisMonth}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(report));
      if (raw == null) return RpFilterValue(range: RpRange.of(fallback, now: now));
      final j = jsonDecode(raw);
      if (j is! Map) return RpFilterValue(range: RpRange.of(fallback, now: now));
      Map<String, Set<String>> sets(Object? v) => v is Map
          ? {for (final e in v.entries) '${e.key}': {for (final x in (e.value is List ? e.value as List : const [])) '$x'}}
          : <String, Set<String>>{};
      final sameOpen = (j['ot']?.toString() ?? '') == (openTag ?? '');
      final managers = sets(j['m'])..removeWhere((k, s) => s.isEmpty || (k == openGroup && !sameOpen));
      final employees = j['e'] is Map
          ? {for (final e in (j['e'] as Map).entries) '${e.key}': '${e.value}'}
          : <String, String>{};
      if (!sameOpen) employees.remove(openGroup);
      return RpFilterValue(
        range: RpRange.fromKey(j['p']?.toString(), now: now),
        compare: j['c'] != false,
        companies: {for (final x in (j['co'] is List ? j['co'] as List : const [])) '$x'},
        managers: managers,
        withSubs: j['s'] != false,
        managerMode: j['mm'] == 'owner' ? RpManagerMode.owner : RpManagerMode.actor,
        employees: employees,
        types: [for (final x in (j['t'] is List ? j['t'] as List : const [])) '$x'],
        // باقات المفتوحة («|اسمها») لصفحتها وحدها — كمدرائها
        packages: {
          for (final x in (j['pk'] is List ? j['pk'] as List : const []))
            if (sameOpen || !'$x'.startsWith('|')) '$x',
        },
      );
    } catch (_) {
      return RpFilterValue(range: RpRange.of(fallback, now: now));
    }
  }

  static Future<void> save(String report, RpFilterValue v, {String? openTag}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key(report),
        jsonEncode({
          'p': v.range.key,
          'c': v.compare,
          'co': v.companies.toList(),
          'm': {for (final e in v.managers.entries) e.key: e.value.toList()},
          's': v.withSubs,
          'mm': v.managerMode.name,
          'e': v.employees,
          't': v.types,
          'pk': v.packages.toList(),
          'ot': openTag ?? '',
        }),
      );
    } catch (_) {
      // تفضيلٌ لا أكثر
    }
  }
}
