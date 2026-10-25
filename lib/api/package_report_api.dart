import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// «توزيع الباقات والأرباح» (#٥، ٢٥ أكتوبر) — `GET /api/reports/finance/packages` (server/packageDistribution.js).
///
/// لكلّ باقة: المشتركون الآن (الكلّ/الفعّال — بعد «نطاق العرض» على الخادم) · تفعيلات الفترة وتمديداتها · الإيراد (سعر البيع
/// لا النقد) · ولصاحب الحساب وحده الكلفة والربح الكلّي والمقدَّر. الخادم يحكم: `owner=false` ⇒ لا كلفة ولا ربح في الردّ أصلاً.
/// ما لم يُعرف null («—» في الواجهة) لا صفر، والمتعذّر يُسمّى في [PackageReport.unavailableParts].
class PackageReportRow {
  const PackageReportRow({
    required this.key,
    required this.name,
    this.profileId,
    this.price,
    this.subscribersTotal,
    this.subscribersActive,
    this.activations = 0,
    this.syncActivations = 0,
    this.extensions = 0,
    this.revenue = 0,
    this.unitCost,
    this.cost,
    this.costExempt = false,
    this.costComplete,
    this.costRows,
    this.costKnownRows,
    this.profitTotal,
    this.profitEstimated,
  });

  /// p:<id> · n:<اسم> · other («باقات أخرى») · unknown («باقة غير معروفة»).
  final String key;
  final String name;
  final int? profileId;
  final num? price;
  final int? subscribersTotal;
  final int? subscribersActive;
  final int activations;
  final int syncActivations;
  final int extensions;
  final num revenue;
  // لصاحب الحساب وحده:
  final num? unitCost;
  final num? cost;
  final bool costExempt;
  final bool? costComplete;
  final int? costRows;
  final int? costKnownRows;
  final num? profitTotal;
  final num? profitEstimated;

  bool get isAggregate => key == 'other' || key == 'unknown';

  factory PackageReportRow.fromJson(Map<String, dynamic> j) => PackageReportRow(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        profileId: _intOrNull(j['profile_id']),
        price: _numOrNull(j['price']),
        subscribersTotal: _intOrNull(j['subscribers_total']),
        subscribersActive: _intOrNull(j['subscribers_active']),
        activations: _intOrNull(j['activations']) ?? 0,
        syncActivations: _intOrNull(j['sync_activations']) ?? 0,
        extensions: _intOrNull(j['extensions']) ?? 0,
        revenue: _numOrNull(j['revenue']) ?? 0,
        unitCost: _numOrNull(j['unit_cost']),
        cost: _numOrNull(j['cost']),
        costExempt: j['cost_exempt'] == true,
        costComplete:
            j['cost_complete'] is bool ? j['cost_complete'] as bool : null,
        costRows: _intOrNull(j['cost_rows']),
        costKnownRows: _intOrNull(j['cost_known_rows']),
        profitTotal: _numOrNull(j['profit_total']),
        profitEstimated: _numOrNull(j['profit_estimated']),
      );
}

class PackageReportTotals {
  const PackageReportTotals({
    this.packages = 0,
    this.subscribersTotal,
    this.subscribersActive,
    this.activations = 0,
    this.syncActivations = 0,
    this.extensions = 0,
    this.revenue = 0,
    this.cost,
    this.profitTotal,
    this.costRows,
    this.costKnownRows,
    this.costComplete,
    this.profitEstimated,
    this.estimateMissingPackages = 0,
  });

  final int packages;
  final int? subscribersTotal;
  final int? subscribersActive;
  final int activations;
  final int syncActivations;
  final int extensions;
  final num revenue;
  final num? cost;
  final num? profitTotal;
  final int? costRows;
  final int? costKnownRows;
  final bool? costComplete;
  final num? profitEstimated;
  final int estimateMissingPackages;

  factory PackageReportTotals.fromJson(Map<String, dynamic> j) =>
      PackageReportTotals(
        packages: _intOrNull(j['packages']) ?? 0,
        subscribersTotal: _intOrNull(j['subscribers_total']),
        subscribersActive: _intOrNull(j['subscribers_active']),
        activations: _intOrNull(j['activations']) ?? 0,
        syncActivations: _intOrNull(j['sync_activations']) ?? 0,
        extensions: _intOrNull(j['extensions']) ?? 0,
        revenue: _numOrNull(j['revenue']) ?? 0,
        cost: _numOrNull(j['cost']),
        profitTotal: _numOrNull(j['profit_total']),
        costRows: _intOrNull(j['cost_rows']),
        costKnownRows: _intOrNull(j['cost_known_rows']),
        costComplete:
            j['cost_complete'] is bool ? j['cost_complete'] as bool : null,
        profitEstimated: _numOrNull(j['profit_estimated']),
        estimateMissingPackages:
            _intOrNull(j['estimate_missing_packages']) ?? 0,
      );
}

class PackageReport {
  const PackageReport({
    required this.owner,
    required this.costExempt,
    required this.rows,
    required this.totals,
    this.provider,
    this.subscribersPartial = false,
    this.unavailableParts = const [],
  });

  /// صاحب الحساب (الكلفة والربح في الردّ) — قرار الخادم لا التطبيق.
  final bool owner;
  final bool costExempt;
  final String? provider;
  final List<PackageReportRow> rows;
  final PackageReportTotals totals;
  final bool subscribersPartial;

  /// activity · package_cost · packages · subscribers — ما تعذّر جزءاً جزءاً (نصّه `pkgdist.part_<الجزء>`).
  final List<String> unavailableParts;

  bool get countsKnown => totals.subscribersActive != null;

  /// الأكثر فعّالين أوّلاً (ثمّ التفعيلات)؛ بلا أعدادٍ (تعذّرت) بالتفعيلات. «باقات أخرى» و«غير معروفة» للتقرير الكامل،
  /// وباقةٌ بلا مشتركين ولا حركة لا تُعرض في المختصر.
  ({List<PackageReportRow> top, int rest}) topRows(int n) {
    final real = rows
        .where((r) =>
            !r.isAggregate &&
            ((r.subscribersTotal ?? 0) > 0 ||
                r.activations > 0 ||
                r.extensions > 0))
        .toList();
    int key(PackageReportRow r) =>
        countsKnown ? (r.subscribersActive ?? 0) : r.activations;
    real.sort((a, b) {
      final c = key(b).compareTo(key(a));
      if (c != 0) return c;
      final d = b.activations.compareTo(a.activations);
      return d != 0 ? d : a.name.compareTo(b.name);
    });
    final top = real.take(n).toList();
    return (top: top, rest: real.length - top.length);
  }

  static PackageReport? fromBody(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! Map) return null;
    final d = Map<String, dynamic>.from(data);
    final rowsRaw = d['rows'];
    final totalsRaw = d['totals'];
    // علم التعذّر في الجسم أو داخل data — بلا تكرار (كـReportsApi.finance).
    final parts = <String>{
      for (final src in [body['unavailable_parts'], d['unavailable_parts']])
        if (src is List)
          for (final x in src) '$x',
    };
    return PackageReport(
      owner: d['owner'] == true,
      costExempt: d['cost_exempt'] == true,
      provider: d['provider']?.toString(),
      rows: rowsRaw is List
          ? rowsRaw
              .whereType<Map>()
              .map((m) =>
                  PackageReportRow.fromJson(Map<String, dynamic>.from(m)))
              .where((r) => r.key.isNotEmpty)
              .toList()
          : const [],
      totals: totalsRaw is Map
          ? PackageReportTotals.fromJson(Map<String, dynamic>.from(totalsRaw))
          : const PackageReportTotals(),
      subscribersPartial: d['subscribers_partial'] == true,
      unavailableParts: parts.toList(),
    );
  }
}

class PackageReportApi {
  PackageReportApi._();

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [userIds] نطاق تقارير التطبيق (loadScopeUserIds — المدير المسجّل وحده)؛ الخادم يقاطعه مع ما يملكه.
  /// [companyKey] «كل الشركات»: الشركة المختارة في الشريط (يمرّ بتوجيه الخادم، بلا user_ids — نطاقها من جلستها).
  /// [status] ٤٠٣ ⇒ «لا صلاحيّة» (القفل) لا «تعذّر».
  static Future<({PackageReport? data, String? error, int? status})> fetch({
    required DateTime from,
    required DateTime to,
    List<String>? userIds,
    int? employeeId,
    String? companyKey,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/finance/packages',
        queryParameters: {
          'date_from': '${_d(from)} 00:00:00',
          'date_to': '${_d(to)} 23:59:59',
          if (companyKey == null && userIds != null && userIds.isNotEmpty)
            'user_ids': userIds.where((id) => id.isNotEmpty).join(','),
          if (employeeId != null) 'employee_id': '$employeeId',
        },
        options: Options(
          // عدّ مشتركي كلّ باقة قد يأخذ ثوانيَ للحسابات الكبيرة أوّل مرّة (الخادم يتذكّره ٣ دقائق).
          receiveTimeout: const Duration(seconds: 60),
          extra: {if (companyKey != null) 'companyKey': companyKey},
        ),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          data: null,
          error: body['message']?.toString() ?? 'تعذّر جلب تقرير الباقات',
          status: r.statusCode
        );
      }
      final rep = PackageReport.fromBody(body);
      if (rep == null) {
        return (data: null, error: 'تنسيق غير متوقع', status: r.statusCode);
      }
      return (data: rep, error: null, status: r.statusCode);
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('🔴 package-report: $e');
      return (
        data: null,
        error: humanError(e, fallback: 'تعذّر جلب تقرير الباقات'),
        status: e.response?.statusCode,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 package-report: $e');
      return (data: null, error: 'تعذّر جلب تقرير الباقات', status: null);
    }
  }
}

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.round();
  final n = num.tryParse(v.toString().trim());
  return n?.round();
}

num? _numOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().trim());
}
