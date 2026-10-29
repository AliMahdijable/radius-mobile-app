import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import 'api_client.dart';

/// صفّ مشترك «الخدمة الترفيهية» (المحتوى) عند فايبر اكس — قراءةٌ فقط.
@immutable
class FxEntRow {
  const FxEntRow({
    required this.username,
    required this.name,
    required this.phone,
    required this.package,
    required this.status,
    required this.statusLabel,
    required this.expiry,
    required this.remainingDays,
    required this.months,
    required this.governorate,
    required this.internetPlan,
  });

  final String username; // ispUsername
  final String name;
  final String phone;
  final String package;
  final String status; // active | expired | pending
  final String statusLabel; // نشط / منتهٍ / …
  final String expiry; // «YYYY-MM-DD HH:mm:ss» بغداد أو ''
  final int? remainingDays;
  final int? months;
  final String governorate;
  final String internetPlan;

  bool get isActive => status == 'active';

  factory FxEntRow.fromJson(Map<String, dynamic> j) => FxEntRow(
        username: (j['username'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        package: (j['package'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        statusLabel: (j['status_label'] ?? '').toString(),
        expiry: (j['expiry'] ?? '').toString(),
        remainingDays: (j['remaining_days'] as num?)?.toInt(),
        months: (j['months'] as num?)?.toInt(),
        governorate: (j['governorate'] ?? '').toString(),
        internetPlan: (j['internet_plan'] ?? '').toString(),
      );
}

@immutable
class FxEntSummary {
  const FxEntSummary(
      {required this.total, required this.active, required this.expired, required this.nearExpiry});
  final int total, active, expired, nearExpiry;
  static const zero = FxEntSummary(total: 0, active: 0, expired: 0, nearExpiry: 0);

  factory FxEntSummary.fromJson(Map<String, dynamic> j) => FxEntSummary(
        total: (j['total'] as num?)?.toInt() ?? 0,
        active: (j['active'] as num?)?.toInt() ?? 0,
        expired: (j['expired'] as num?)?.toInt() ?? 0,
        nearExpiry: (j['near_expiry'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class FxEntResult {
  const FxEntResult({required this.summary, required this.rows, this.partial = false});
  final FxEntSummary summary;
  final List<FxEntRow> rows;
  final bool partial;
}

class FiberxEntertainmentApi {
  FiberxEntertainmentApi._();

  /// `GET /api/v2/fiberx/entertainment` — الملخّص والقائمة (قراءة). يُرجع الخطأ نصّاً لا يرمي.
  static Future<({FxEntResult? result, String? error})> fetch() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/fiberx/entertainment');
      final b = r.data ?? const {};
      if (b['success'] != true) {
        return (result: null, error: (b['message'] ?? 'تعذّر جلب الخدمة الترفيهية').toString());
      }
      final rawRows = b['data'];
      final rows = rawRows is List
          ? rawRows
              .whereType<Map>()
              .map((m) => FxEntRow.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : <FxEntRow>[];
      final sum = b['summary'];
      return (
        result: FxEntResult(
          summary: sum is Map
              ? FxEntSummary.fromJson(Map<String, dynamic>.from(sum))
              : FxEntSummary.zero,
          rows: rows,
          partial: b['partial'] == true,
        ),
        error: null,
      );
    } catch (e) {
      return (result: null, error: humanError(e, fallback: 'تعذّر جلب الخدمة الترفيهية'));
    }
  }
}
