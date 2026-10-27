import '../../models/fiber_network.dart';
import 'fiber_onu.dart';
import 'fiber_outage.dart';
import 'fiber_tree.dart';

/// نصوص شبكة الألياف — مكانٌ واحد للشاشات والإشعار (فلا يقول الإشعار شيئاً والشاشة غيره).
class FiberText {
  FiberText._();

  /// «جهاز واحد · جهازان · ٣ أجهزة · ١٢ جهازاً» بأرقامٍ لاتينيّة كبقيّة التطبيق.
  static String devices(int n) => n == 1
      ? 'جهاز واحد'
      : n == 2
          ? 'جهازان'
          : n >= 3 && n <= 10
              ? '$n أجهزة'
              : '$n جهازاً';

  static String subscribers(int n) => n == 1
      ? 'مشترك واحد'
      : n == 2
          ? 'مشتركان'
          : n >= 3 && n <= 10
              ? '$n مشتركين'
              : '$n مشتركاً';

  static String ports(int n) => n == 1
      ? 'منفذ واحد'
      : n == 2
          ? 'منفذان'
          : n >= 3 && n <= 10
              ? '$n منافذ'
              : '$n منفذاً';

  /// «منفذ فارغ · منفذان فارغان · 9 منافذ فارغة · 12 منفذاً فارغاً».
  static String freePorts(int n) => n <= 0
      ? 'بلا منافذ فارغة'
      : n == 1
          ? 'منفذ فارغ'
          : n == 2
              ? 'منفذان فارغان'
              : n <= 10
                  ? '$n منافذ فارغة'
                  : '$n منفذاً فارغاً';

  static String boxes(int n) => n == 1
      ? 'صندوق واحد'
      : n == 2
          ? 'صندوقان'
          : n >= 3 && n <= 10
              ? '$n صناديق'
              : '$n صندوقاً';

  static String clock(DateTime t, {bool seconds = false}) {
    final l = t.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return seconds ? '${p(l.hour)}:${p(l.minute)}:${p(l.second)}' : '${p(l.hour)}:${p(l.minute)}';
  }

  /// «٤٥ ثانية · ٢٣ دقيقة · ساعة و١٠ دقائق · ٣ أيّام».
  static String duration(Duration d) {
    if (d.inSeconds < 60) {
      final s = d.inSeconds < 1 ? 1 : d.inSeconds;
      return s <= 10 && s >= 3 ? '$s ثوانٍ' : (s == 1 ? 'ثانية' : (s == 2 ? 'ثانيتين' : '$s ثانية'));
    }
    if (d.inMinutes < 60) return _minutes(d.inMinutes);
    if (d.inHours < 24) {
      final h = d.inHours;
      final m = d.inMinutes % 60;
      final hs = h == 1 ? 'ساعة' : (h == 2 ? 'ساعتين' : (h <= 10 ? '$h ساعات' : '$h ساعة'));
      return m == 0 ? hs : '$hs و${_minutes(m)}';
    }
    final days = d.inDays;
    return days == 1 ? 'يوم' : (days == 2 ? 'يومين' : (days <= 10 ? '$days أيّام' : '$days يوماً'));
  }

  static String _minutes(int m) => m == 1 ? 'دقيقة' : (m == 2 ? 'دقيقتين' : (m <= 10 ? '$m دقائق' : '$m دقيقة'));

  static String verdict(FiberEventKind k) => switch (k) {
        FiberEventKind.cut => 'على الأغلب قطع بالليف',
        FiberEventKind.power => 'انطفاء كهرباء بالمنطقة',
        FiberEventKind.mixed => 'قطع ليف وانطفاء كهرباء معاً',
        FiberEventKind.unknown => 'انقطاعٌ جماعيّ',
      };

  static String _boxName(FiberLayout l, int? id) => id == null ? '' : (l.boxes[id]?.name ?? 'الصندوق');

  /// عنوان العطل: «عطل · صندوق 3-أ» · «عطل · PON 3 كلّه» · «٥ أجهزة انقطعت معاً · PON 3».
  static String outageTitle({
    required FiberEventScope scope,
    required String pon,
    required int count,
    int? boxId,
    required FiberLayout layout,
  }) =>
      switch (scope) {
        FiberEventScope.box || FiberEventScope.splitter => 'عطل · ${_boxName(layout, boxId)}',
        FiberEventScope.pon => 'عطل · ${fiberPonDisplay(pon)} كلّه',
        FiberEventScope.group => '${devices(count)} انقطعت معاً · ${fiberPonDisplay(pon)}',
      };

  /// أين القطع، بجملةٍ واحدة.
  static String outageWhere({
    required FiberEventScope scope,
    required FiberEventKind kind,
    int? boxId,
    required FiberLayout layout,
    FiberPonTree? tree,
  }) {
    if (kind == FiberEventKind.power) return 'الأجهزة طفت لانقطاع الكهرباء — ما يحتاج فنّياً';
    switch (scope) {
      case FiberEventScope.box:
        final path = tree?.pathTo(boxId ?? 0) ?? const [];
        final parent = path.length >= 2 ? path[path.length - 2].name : 'المنفذ';
        return 'بين $parent و${_boxName(layout, boxId)}';
      case FiberEventScope.splitter:
        return 'قبل ${_boxName(layout, boxId)} أو فيه';
      case FiberEventScope.pon:
        return 'بالكيبل الرئيسيّ أو منفذ الأولت';
      case FiberEventScope.group:
        return 'الصناديق غير محدّدة على هذا المنفذ — رتّبها لتعرف المكان';
    }
  }

  static ({String title, String body}) outagePush(FiberOutage e, FiberLayout l, String oltName) {
    final title = 'عطل ألياف · ${outageTitle(scope: e.scope, pon: e.pon, count: e.count, boxId: e.boxId, layout: l)}';
    final body = '${devices(e.count)} انقطعت معاً على ${fiberPonDisplay(e.pon)} ($oltName) — ${verdict(e.kind)}';
    return (title: _cap(title, 120), body: _cap(body, 240));
  }

  static ({String title, String body}) backPush(FiberEventRecord e, FiberLayout l, String oltName) {
    final where = outageTitle(scope: e.scope, pon: e.pon, count: e.onuKeys.length, boxId: e.boxId, layout: l)
        .replaceFirst('عطل · ', '');
    final dur = e.endedAt == null ? '' : ' بعد ${duration(e.endedAt!.difference(e.startedAt))}';
    return (
      title: _cap('رجع النت · $where', 120),
      body: _cap('رجعت أجهزة العطل (${devices(e.onuKeys.length)}) على ${fiberPonDisplay(e.pon)} ($oltName)$dur', 240),
    );
  }

  static String _cap(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

  /// يوزرات المشتركين المربوطين بهذه الأجهزة (بهويّتها إن عُرفت الآن).
  static List<String> linkedUsers(FiberLayout layout, int oltId, Iterable<String> keys, Iterable<FiberOnuLive> live) {
    final byKey = {for (final o in live) o.key: o};
    final out = <String>{};
    for (final k in keys) {
      final o = byKey[k];
      final rec = layout.recordFor(oltId, k, o?.ident);
      final u = rec?.username;
      if (u != null && u.isNotEmpty) out.add(u);
    }
    return out.toList()..sort();
  }
}
