import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// خانة واحدة من تقرير الاستهلاك — يومٌ أو شهر حسب النوع.
@immutable
class TrafficBucket {
  const TrafficBucket({
    required this.index,
    required this.rx,
    required this.tx,
    required this.total,
  });

  /// 1-based: اليوم 1..31 أو الشهر 1..12.
  final int index;
  final int rx; // تحميل
  final int tx; // رفع
  final int total;

  factory TrafficBucket.fromJson(Map<String, dynamic> j) => TrafficBucket(
        index: (j['i'] as num?)?.toInt() ?? 0,
        rx: (j['rx'] as num?)?.toInt() ?? 0,
        tx: (j['tx'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class TrafficReport {
  const TrafficReport({
    required this.type,
    required this.month,
    required this.year,
    required this.buckets,
    required this.total,
  });

  final String type; // daily | monthly
  final int month;
  final int year;
  final List<TrafficBucket> buckets;
  final int total;

  bool get isEmpty => total == 0;

  /// أعلى خانة — يُقاس عليها ارتفاع الأعمدة.
  int get peak =>
      buckets.fold<int>(0, (m, b) => b.total > m ? b.total : m);
}

/// تقرير استهلاك المشترك من SAS4.
///
/// 🔬 المسار اكتُشف 2026-09-01 بفكّ حمولة من واجهة SAS4: الحقل
/// `report_type` غير موثَّق، وبدونه يُرجع الخادم 500 صامتاً.
///
/// ⚠️ ولا يُجلب مع القائمة أبداً — نداءٌ لكلّ مشترك يعني 384 نداءً في
/// كلّ تحديث. عند فتح الكارت فقط.
class TrafficApi {
  TrafficApi._();

  static Future<({TrafficReport? report, String? error})> fetch({
    required String subscriberId,
    required String type, // daily | monthly
    int? month,
    int? year,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers/$subscriberId/traffic',
        queryParameters: {
          'type': type,
          if (month != null) 'month': month,
          if (year != null) 'year': year,
        },
      );
      final b = r.data ?? const {};
      if (b['success'] != true) {
        return (report: null, error: (b['message'] ?? 'تعذّر جلب الاستهلاك').toString());
      }
      final raw = b['buckets'];
      return (
        report: TrafficReport(
          type: (b['type'] ?? type).toString(),
          month: (b['month'] as num?)?.toInt() ?? 0,
          year: (b['year'] as num?)?.toInt() ?? 0,
          total: (b['total'] as num?)?.toInt() ?? 0,
          buckets: raw is List
              ? raw
                  .whereType<Map>()
                  .map((m) => TrafficBucket.fromJson(Map<String, dynamic>.from(m)))
                  .toList()
              : const [],
        ),
        error: null,
      );
    } catch (e) {
      return (report: null, error: humanError(e, fallback: 'تعذّر جلب الاستهلاك'));
    }
  }

  /// استهلاك مشتركٍ **بمجاميعه** — اليوم والشهر (وأمس إن عُرف) — للشركات المُضافة (نبض، AccessGate…، ٣٠ أكتوبر): مزوّدها
  /// لا يعطي تفصيلاً يوميّاً، فـ`/traffic` لا يخدمها (ردٌّ فارغ كان يُقرأ «لا استهلاك»). المصدر عقد القائمة نفسه
  /// `GET /api/v2/subscribers-usage?ids=<idx>&month=YYYY-MM` (بايت؛ null = لا نعرف — لا صفرٌ كاذب).
  static Future<({int? today, int? month, int? yesterday, String? error})> usageTotals({
    required String subscriberId,
    required int month,
    required int year,
  }) async {
    int? n(Object? v) => v is num ? v.round() : num.tryParse('${v ?? ''}')?.round();
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers-usage',
        queryParameters: {
          'ids': subscriberId,
          'month': '$year-${month.toString().padLeft(2, '0')}',
        },
      );
      final b = r.data ?? const {};
      final d = b['data'];
      final u = d is Map ? d[subscriberId] : null;
      if (b['success'] != true || u is! Map) {
        return (today: null, month: null, yesterday: null, error: (b['message'] ?? 'تعذّر جلب الاستهلاك').toString());
      }
      return (today: n(u['today']), month: n(u['month']), yesterday: n(u['yesterday']), error: null);
    } catch (e) {
      return (today: null, month: null, yesterday: null, error: humanError(e, fallback: 'تعذّر جلب الاستهلاك'));
    }
  }
}
