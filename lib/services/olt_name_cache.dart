import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// أسماء واجهات الأولت محفوظةً على الجهاز (ifIndex ← ifName): بها تقرأ لوحة الأولت وشبكة الألياف **عمود الحالة وحده**
/// عند الفتح (`VsolOltApi.fetchStats(knownNames:)`) بدل الأسماء والحالة معاً — نصف مسحة البنية على أولتٍ كبير بعيد
/// (٢٧ أكتوبر، المالك: «كلش يتاخر بفتح الاولتي… هلشي بكل olt»).
///
/// ليست قراءةً حيّة (لا حالة ولا عدّاد ولا ضوء) فلا تفسد بمرور الوقت — بخلاف [DeviceStatsCache] الذي يرفض القرص
/// عمداً. وما تغيّر منها يُكتشف: واجهةٌ لا يعرفها المحفوظ ⇒ تُقرأ الأسماء من جديد وتُحفظ. وتُمسح مع الخروج.
class OltNameCache {
  OltNameCache._();

  static const _prefix = 'olt.names.v1.';

  /// أقدم من هذا يُقرأ من جديد — جهازٌ أُعيد ترقيمه أو استُبدل.
  static const maxAge = Duration(days: 7);

  static final Map<int, ({DateTime at, Map<int, String> names})> _mem = {};

  static Future<Map<int, String>?> get(int deviceId) async {
    var e = _mem[deviceId];
    if (e == null) {
      try {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString('$_prefix$deviceId');
        if (raw != null) {
          final j = jsonDecode(raw);
          final at = DateTime.tryParse('${j['at']}');
          final m = j['names'];
          if (at != null && m is Map) {
            e = (
              at: at,
              names: Map.unmodifiable({
                for (final x in m.entries)
                  if (int.tryParse('${x.key}') != null && x.value is String) int.parse('${x.key}'): x.value as String,
              }),
            );
            _mem[deviceId] = e;
          }
        }
      } catch (_) {/* لا محفوظ — تُقرأ الأسماء */}
    }
    if (e == null || e.names.isEmpty || DateTime.now().difference(e.at) > maxAge) return null;
    return e.names;
  }

  static Future<void> put(int deviceId, Map<int, String> names) async {
    if (names.isEmpty) return;
    final cur = _mem[deviceId];
    // لم يتغيّر شيء ⇒ لا كتابة على القرص كلّ مسحة (يتجدّد العمر في الذاكرة وحدها).
    if (cur != null && _same(cur.names, names) && DateTime.now().difference(cur.at) < const Duration(hours: 12)) return;
    final e = (at: DateTime.now(), names: Map<int, String>.unmodifiable(names));
    _mem[deviceId] = e;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        '$_prefix$deviceId',
        jsonEncode({'at': e.at.toIso8601String(), 'names': {for (final x in names.entries) '${x.key}': x.value}}),
      );
    } catch (_) {/* الذاكرة تكفي هذه الجلسة */}
  }

  static bool _same(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  /// الخروج: لا يرث الحساب التالي بنية أجهزة سابقه.
  static Future<void> clear() async {
    _mem.clear();
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
