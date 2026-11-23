import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart';

import 'report_kit.dart';
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
      // الموظّفون قائمةٌ لكلّ شركة (٢٣ نوفمبر)؛ والحفظ الأقدم نصٌّ واحد ⇒ موظّفٌ واحد
      String? one(Object? x) => x == null || '$x'.isEmpty ? null : '$x';
      final employees = j['e'] is Map
          ? {
              for (final e in (j['e'] as Map).entries)
                '${e.key}': {
                  for (final x in e.value is List ? e.value as List : [e.value])
                    if (one(x) != null) one(x)!,
                },
            }
          : <String, Set<String>>{};
      employees.removeWhere((k, s) => s.isEmpty || (k == openGroup && !sameOpen));
      return RpFilterValue(
        range: RpRange.fromKey(j['p']?.toString(), now: now),
        compare: j['c'] != false,
        companies: {for (final x in (j['co'] is List ? j['co'] as List : const [])) '$x'},
        managers: managers,
        // «مع الفرعيّين» بمفتاحٍ جديد «ws» (٢٢ نوفمبر): «s» القديم حُفظ true افتراضاً قبل أن يظهر المفتاح — لا يُورَث فيضمّ الفرعيّين
        // تلقائيّاً حين يصل parent_id من الخادم
        withSubs: j['ws'] == true,
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
          'ws': v.withSubs,
          'mm': v.managerMode.name,
          'e': {for (final e in v.employees.entries) e.key: e.value.toList()},
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

/// الأقسام الفرعيّة المطويّة لكلّ تقرير (المالك ٢٢ نوفمبر: «الأقسام الفرعيّة خلّيها مقفولة — المهمّات تظهر والفرعيّة هو ينقر عليها
/// ويظهرها… اعتمد هلشي بتصميم التطبيق والموقع»): [defaults] ما يُفتح أوّل مرّة (السجلّ يفتح حركاته، والماليّ يطويها)، وما فتحه الوكيل
/// أو طواه يُتذكّر على هذا الجهاز. التخزين يتعذّر ⇒ الافتراض بلا خطأ.
class RpFolds {
  RpFolds(this.report, this.defaults);

  final String report;
  final Map<String, bool> defaults;
  final Map<String, bool> _state = {};

  String get _key => 'report.v2.$report.folds';

  bool open(String section) => _state[section] ?? defaults[section] ?? false;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      for (final e in j.entries) {
        if (e.value is bool) _state['${e.key}'] = e.value as bool;
      }
    } catch (_) {
      // الافتراض
    }
  }

  /// [RpFold] القسم لشاشةٍ تعيد بناءها بـ[rebuild] (setState).
  RpFold fold(String section, void Function(VoidCallback fn) rebuild) =>
      RpFold(open: open(section), onToggle: () => rebuild(() => toggle(section)));

  void toggle(String section) {
    _state[section] = !open(section);
    final snapshot = Map<String, bool>.of(_state);
    unawaited(() async {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_key, jsonEncode(snapshot));
      } catch (_) {
        // تفضيلٌ لا أكثر
      }
    }());
  }
}
