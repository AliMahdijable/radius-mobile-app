import 'package:flutter/foundation.dart';

import '../../models/fiber_network.dart';
import 'fiber_onu.dart';

enum FiberLinkConfidence { sure, likely }

/// اقتراح ربطٍ بين ONU ومشترك — لا يُحفظ إلّا بتثبيت الوكيل.
@immutable
class FiberLinkSuggestion {
  const FiberLinkSuggestion({
    required this.key,
    required this.ident,
    required this.username,
    required this.source,
    required this.confidence,
    required this.why,
  });

  final String key;
  final String? ident;

  /// اليوزر كما هو بالساس (حالة الحروف محفوظة).
  final String username;
  final FiberLinkSource source;
  final FiberLinkConfidence confidence;

  /// السبب بالعربيّ: «نفس الماك بجلسته الحاليّة» …
  final String why;

  bool get sure => confidence == FiberLinkConfidence.sure;
}

/// لماذا بقي جهازٌ بلا ربط.
enum FiberUnlinkedReason {
  /// مفصولٌ — لا جلسة ولا أجهزة خلفه نقرؤها الآن.
  offline,

  /// متّصل والأجهزة خلفه معروفة، ولا جلسة بالساس تطابقها.
  noSession,

  /// متّصل ولم نقرأ بعدُ الأجهزة خلفه (جدول الأولت لم يكتمل أو لا يكشفها).
  unknownDevices,
}

@immutable
class FiberLinkPlan {
  const FiberLinkPlan({required this.suggestions, required this.unlinked, required this.linkedCount});
  final List<FiberLinkSuggestion> suggestions;
  final Map<FiberUnlinkedReason, List<String>> unlinked;
  final int linkedCount;

  int get sureCount => suggestions.where((s) => s.sure).length;
  int get unlinkedCount => unlinked.values.fold(0, (a, b) => a + b.length);
}

/// الربط التلقائيّ بثلاث طرق، بلا تخمين:
///   ١. وصف الـONU على الأولت = يوزر المشترك (يكتبه كثيرٌ من الوكلاء عند التركيب) ⇒ أكيد.
///   ٢. ماك جهازٍ خلف الـONU (جدول الأولت) = ماك جلسة المشترك بالساس ⇒ أكيد إن تفرّد.
///   ٣. ماك الـONU نفسها = ماك الجلسة (الـONU راوترٌ يتّصل بنفسه) ⇒ أكيد، وبفرق ١–٣ (منفذ WAN) ⇒ محتمل.
/// اليوزر الواحد لا يُقترح لجهازين؛ والتعارض يُسقط الاقتراح بدل أن يختار عشوائيّاً.
class FiberLinker {
  FiberLinker._();

  static int? _macInt(String? ident) =>
      ident != null && RegExp(r'^[0-9a-f]{12}$').hasMatch(ident) ? int.tryParse(ident, radix: 16) : null;

  static FiberLinkPlan plan({
    required int oltId,
    required List<FiberOnuLive> onus,
    required FiberLayout layout,
    required Map<String, String> sessionMacByUser,
    Map<String, String> knownUsernames = const {},
  }) {
    // اليوزر (بحروفٍ صغيرة) ← ماك الجلسة المطبَّع؛ والماك ← اليوزرات.
    final userByMac = <String, Set<String>>{};
    final sessionUsers = <String, String>{};
    for (final e in sessionMacByUser.entries) {
      final u = e.key.trim().toLowerCase();
      final m = fiberIdent(e.value);
      if (u.isEmpty || m == null || !RegExp(r'^[0-9a-f]{12}$').hasMatch(m)) continue;
      userByMac.putIfAbsent(m, () => {}).add(u);
      sessionUsers[u] = e.key.trim();
    }
    final names = <String, String>{
      for (final e in knownUsernames.entries) e.key.trim().toLowerCase(): e.value,
      for (final e in sessionUsers.entries) e.key: e.value,
    };
    final alreadyLinked = <String>{
      for (final r in layout.onus.values)
        if (r.oltId == oltId && r.username != null) r.username!.toLowerCase(),
    };

    final raw = <FiberLinkSuggestion>[];
    final unlinked = <FiberUnlinkedReason, List<String>>{};
    var linked = 0;
    for (final o in onus) {
      final rec = layout.recordFor(oltId, o.key, o.ident);
      if (rec?.username != null) {
        linked++;
        continue;
      }
      FiberLinkSuggestion? best;
      void consider(String userLower, FiberLinkSource src, FiberLinkConfidence c, String why) {
        if (alreadyLinked.contains(userLower)) return;
        final shown = names[userLower] ?? userLower;
        final s = FiberLinkSuggestion(key: o.key, ident: o.ident, username: shown, source: src, confidence: c, why: why);
        if (best == null || (s.sure && !best!.sure)) best = s;
      }

      // ١. الوصف = اليوزر
      final nm = o.onu.name?.trim().toLowerCase();
      if (nm != null && nm.isNotEmpty) {
        if (names.containsKey(nm)) {
          consider(nm, FiberLinkSource.name, FiberLinkConfidence.sure, 'اسم الجهاز على الأولت = يوزره');
        } else {
          final tokens = nm.split(RegExp(r'[\s|,;/()\[\]]+')).where((t) => t.length >= 3 && names.containsKey(t)).toSet();
          if (tokens.length == 1) {
            consider(tokens.first, FiberLinkSource.name, FiberLinkConfidence.likely, 'يوزره مكتوبٌ باسم الجهاز');
          }
        }
      }
      // ٢. ماك جهازٍ خلفه = ماك جلسته
      if (o.online) {
        final users = <String>{};
        for (final mac in o.onu.learnedMacs) {
          final m = fiberIdent(mac);
          if (m == null) continue;
          users.addAll(userByMac[m] ?? const {});
        }
        if (users.length == 1) {
          consider(users.first, FiberLinkSource.mac, FiberLinkConfidence.sure, 'نفس الماك بجلسته الحاليّة');
        }
        // ٣. ماك الـONU نفسها
        final own = _macInt(o.ident);
        if (own != null) {
          final exact = userByMac[o.ident!] ?? const <String>{};
          if (exact.length == 1) {
            consider(exact.first, FiberLinkSource.onuMac, FiberLinkConfidence.sure, 'الجهاز نفسه يتّصل بيوزره');
          } else if (exact.isEmpty) {
            final near = <String>{};
            for (var d = 1; d <= 3; d++) {
              for (final m in [own + d, own - d]) {
                if (m < 0) continue;
                near.addAll(userByMac[m.toRadixString(16).padLeft(12, '0')] ?? const {});
              }
            }
            if (near.length == 1) {
              consider(near.first, FiberLinkSource.onuMac, FiberLinkConfidence.likely, 'ماك منفذ الإنترنت بالجهاز يقارب ماكه');
            }
          }
        }
      }
      if (best != null) {
        raw.add(best!);
      } else {
        final why = !o.online
            ? FiberUnlinkedReason.offline
            : (o.onu.learnedMacs.isEmpty ? FiberUnlinkedReason.unknownDevices : FiberUnlinkedReason.noSession);
        unlinked.putIfAbsent(why, () => []).add(o.key);
      }
    }

    // يوزرٌ لجهازين: الأكيد يغلب المحتمل، وأكيدان (أو محتملان) يُسقطان معاً.
    final byUser = <String, List<FiberLinkSuggestion>>{};
    for (final s in raw) {
      byUser.putIfAbsent(s.username.toLowerCase(), () => []).add(s);
    }
    final out = <FiberLinkSuggestion>[];
    for (final list in byUser.values) {
      if (list.length == 1) {
        out.add(list.first);
        continue;
      }
      final sure = list.where((s) => s.sure).toList();
      if (sure.length == 1) {
        out.add(sure.first);
      }
      for (final s in list) {
        if (!(sure.length == 1 && identical(s, sure.first))) {
          unlinked.putIfAbsent(FiberUnlinkedReason.noSession, () => []).add(s.key);
        }
      }
    }
    out.sort((a, b) {
      if (a.sure != b.sure) return a.sure ? -1 : 1;
      return a.key.compareTo(b.key);
    });
    return FiberLinkPlan(
      suggestions: List.unmodifiable(out),
      unlinked: Map.unmodifiable({for (final e in unlinked.entries) e.key: List<String>.unmodifiable(e.value)}),
      linkedCount: linked,
    );
  }
}
