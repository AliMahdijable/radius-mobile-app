import '../../../api/reports_api.dart';
import '../../../core/util/ar_date.dart';

// تصدير التقرير الماليّ كاملاً (٢٢ نوفمبر — المالك: «من يختار فلاتر ومن يطبع أو ينقر زر إكسل أو PDF يطلع على حسب الفلاتر … وملف
// الPDF جاي يظهر مرات مقصوص مو كامل»).
//
// السبب: الخادم يرسل لكلّ طلبٍ آخر 1000 حركة من الفترة ([PackageCostKpis.recentLogsServerCap]) — شهرٌ مزدحم يخرج ملفّه من منتصفه.
// هنا: ما قُصّ يُعاد طلبه بفتراتٍ أصغر (نصفين فنصفين، باليوم) حتى تصل كلّ فترةٍ كاملة، وتُجمع الأحدث أوّلاً بلا تكرار (الفترات
// منفصلة). يومٌ واحدٌ فوق السقف، أو طلبٌ تعذّر، أو حدّ الطلبات ⇒ يُسمّى في [FinanceFullLogs.gaps] — لا ملفّ ناقصٌ بصمت.

typedef FinanceRangeFetch = Future<({bool ok, FinanceReport? data, String? error})> Function(DateTime from, DateTime to);

class FinanceFullLogs {
  const FinanceFullLogs({required this.logs, required this.gaps, required this.requests});

  /// كلّ الحركات الأحدث أوّلاً (كما يرتّبها الخادم داخل كلّ فترة).
  final List<FinanceLog> logs;

  /// ما لم يكتمل وسببه («2026/11/05: آخر 1000 حركة منه») — فارغ = كاملة.
  final List<String> gaps;

  /// الطلبات الإضافيّة التي احتاجها.
  final int requests;

  bool get complete => gaps.isEmpty;
}

class FinanceExportLoader {
  FinanceExportLoader._();

  /// سقف الطلبات الإضافيّة لتصديرٍ واحد (لكلّ شركة) — حماية الخادم من سنةٍ مزدحمة؛ ما بعده يُسمّى ناقصاً.
  static const maxRequests = 60;

  /// السطور مقصوصةٌ عند سقف الخادم.
  static bool capped(FinanceReport r) => r.recentLogs.length >= PackageCostKpis.recentLogsServerCap;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _plus(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
  static int _days(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays + 1;

  static String _span(DateTime a, DateTime b) {
    final x = iqDateOf(a), y = iqDateOf(b);
    return x == y ? x : '$x – $y';
  }

  /// كلّ حركات [from]–[to] (باليوم) — [first] ما وصل للفترة كلّها؛ غير مقصوصٍ ⇒ هو نفسه بلا أيّ طلب.
  static Future<FinanceFullLogs> load({
    required DateTime from,
    required DateTime to,
    required FinanceReport first,
    required FinanceRangeFetch fetch,
    void Function(int requests)? onProgress,
    bool Function()? cancelled,
    int maxRequests = FinanceExportLoader.maxRequests,
  }) async {
    final out = <FinanceLog>[];
    final gaps = <String>[];
    var requests = 0;
    if (first.unavailableParts.contains('recent_logs')) {
      // الخادم قال إنّ سجلّ الفترة ناقص (لا سقفٌ يُقسَّم) — يُصدَّر ما وصل ويُسمّى
      return FinanceFullLogs(logs: first.recentLogs, gaps: ['${_span(from, to)}: السجلّ لم يُقرأ كاملاً من الشركة'], requests: 0);
    }

    Future<void> walk(DateTime a, DateTime b, FinanceReport? known) async {
      var r = known;
      if (r == null) {
        if (cancelled?.call() ?? false) {
          gaps.add('${_span(a, b)}: أُلغي');
          return;
        }
        if (requests >= maxRequests) {
          gaps.add('${_span(a, b)}: لم يُجلب (فترةٌ طويلة مزدحمة — صدّرها على أجزاء)');
          return;
        }
        requests++;
        onProgress?.call(requests);
        final res = await fetch(a, b);
        if (!res.ok || res.data == null) {
          gaps.add('${_span(a, b)}: تعذّر جلبها${res.error == null ? '' : ' (${res.error})'}');
          return;
        }
        r = res.data!;
        if (r.unavailableParts.contains('recent_logs')) {
          out.addAll(r.recentLogs);
          gaps.add('${_span(a, b)}: السجلّ لم يُقرأ كاملاً من الشركة');
          return;
        }
      }
      if (!capped(r)) {
        out.addAll(r.recentLogs);
        return;
      }
      final n = _days(a, b);
      if (n <= 1) {
        out.addAll(r.recentLogs);
        gaps.add('${iqDateOf(a)}: آخر ${r.recentLogs.length} حركة منه فقط');
        return;
      }
      // الأحدث أوّلاً: النصف الثاني ثمّ الأوّل
      final mid = _plus(a, n ~/ 2 - 1);
      await walk(_plus(mid, 1), b, null);
      await walk(a, mid, null);
    }

    await walk(_day(from), _day(to), first);
    return FinanceFullLogs(logs: out, gaps: gaps, requests: requests);
  }
}
