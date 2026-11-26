import 'package:flutter/foundation.dart';

import '../core/util/format.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «عمولات الموظفين» بالتقارير (٢٦ نوفمبر — المالك: «شون رح يميز ٥ الالف رحت للموظف» ثمّ «تمام الي تشوف افضل سوي»): لكلّ موظّفٍ
/// له «ربح الموظف لكلّ عمليّة» — عمليّاته الكاملة في الفترة × ربحه لحظتها (عدّ «حدود الموظّف» نفسه، فيطابق عمولة كشف الراتب)، وما
/// لم يُصرف منها، وعمولة سطر كلّ تفعيل. GET /api/v2/employee-ledger/commissions (الخادم 0713445) — كالموقع (120f127). عرضٌ وحده:
/// لا يغيّر رقماً من أرقام التقرير.
class EmpCommissionRow {
  const EmpCommissionRow({
    required this.employeeId,
    required this.name,
    required this.active,
    required this.payMode,
    required this.inPayslip,
    required this.ops,
    required this.amount,
    this.unpaidOps,
    this.unpaid,
  });

  final int employeeId;
  final String name;
  final bool active;

  /// salary | commission | both | null.
  final String? payMode;

  /// أجره «عمولة» أو «راتب وعمولة» ⇒ تُصرف بكشف راتبه.
  final bool inPayslip;
  final int ops;
  final double amount;

  /// null = لا يُصرف بكشفه (أجره راتبٌ وحده) أو لا حدّ لعمولته بعد — لا «صفر».
  final int? unpaidOps;
  final double? unpaid;

  static EmpCommissionRow? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final e = raw['employee'];
    if (e is! Map) return null;
    final id = _i(e['id']);
    if (id <= 0) return null;
    final name = '${e['name'] ?? ''}'.trim().isNotEmpty ? '${e['name']}'.trim() : '${e['username'] ?? '#$id'}'.trim();
    return EmpCommissionRow(
      employeeId: id,
      name: name,
      active: raw['active'] != false,
      payMode: raw['pay_mode'] is String ? raw['pay_mode'] as String : null,
      inPayslip: raw['in_payslip'] == true,
      ops: _i(raw['ops']),
      amount: _n(raw['amount']),
      unpaidOps: raw['unpaid_ops'] == null ? null : _i(raw['unpaid_ops']),
      unpaid: raw['unpaid'] == null ? null : _n(raw['unpaid']),
    );
  }
}

class EmpCommissions {
  const EmpCommissions({
    required this.employees,
    required this.ops,
    required this.amount,
    required this.payslipAmount,
    required this.unpaid,
    required this.paidInPeriod,
    required this.byActivity,
  });

  final List<EmpCommissionRow> employees;
  final int ops;
  final double amount;

  /// عمولة عمليّات الفترة لمن تُصرف بكشف راتبه.
  final double payslipAmount;
  final double unpaid;

  /// عمولة الكشوف المصروفة أيّام الفترة (محسوبةٌ أصلاً بالصرفيّات).
  final double paidInPeriod;

  /// رقم سطر النشاط ⇒ عمولته.
  final Map<int, double> byActivity;

  /// البطاقة تظهر: موظّفٌ له عمليّاتٌ كاملة بربحٍ في الفترة.
  bool get any => ops > 0 && employees.any((e) => e.ops > 0);

  /// عمولة سطر نشاطٍ واحد، أو null.
  double? of(int activityId) {
    final v = byActivity[activityId];
    return v != null && v > 0 ? v : null;
  }

  /// «صافي الربح بعد العمولات»: العمولة يوم العمليّة لا يوم الصرف — الصافي − عمولة عمليّات الفترة (لمن تُصرف بكشفه) + ما صُرف منها
  /// بكشف راتبٍ أيّام الفترة (محسوبٌ أصلاً بالصرفيّات فلا يُطرح مرّتين).
  num netAfter(num net) => (net - payslipAmount + paidInPeriod).round();

  /// يظهر سطر «بعد العمولات»؟ — ما يُطرح أو يُعاد.
  bool get hasNetAdjust => payslipAmount > 0 || paidInPeriod > 0;

  /// null = لا بطاقة ولا شارة: الميزة مطفأة أو ردٌّ ناقص.
  static EmpCommissions? fromJson(Object? raw) {
    if (raw is! Map || raw['feature_enabled'] != true) return null;
    final list = raw['employees'];
    final t = raw['totals'];
    final by = raw['by_activity'];
    if (list is! List || t is! Map || by is! Map) return null;
    final map = <int, double>{};
    by.forEach((k, v) {
      final id = int.tryParse('$k');
      final n = _n(v);
      if (id != null && n > 0) map[id] = n;
    });
    return EmpCommissions(
      employees: list.map(EmpCommissionRow.fromJson).whereType<EmpCommissionRow>().toList(),
      ops: _i(t['ops']),
      amount: _n(t['amount']),
      payslipAmount: _n(t['payslip_amount']),
      unpaid: _n(t['unpaid']),
      paidInPeriod: _n(t['paid_in_period']),
      byActivity: map,
    );
  }
}

/// «عملية واحدة» · «عمليتان» · «4 عمليات» · «20 عملية».
String empOpsText(int n) {
  final k = n < 0 ? 0 : n;
  if (k == 1) return 'عملية واحدة';
  if (k == 2) return 'عمليتان';
  final word = k >= 3 && k <= 10 ? 'عمليات' : 'عملية';
  return '$k $word';
}

/// «عمولة الموظف 5,000 د.ع» — تحت مبلغ السطر.
String empCommissionText(num n) => 'عمولة الموظف ${formatIQD(n)} د.ع';

/// يضمّ نصّ العمولة إلى سطر الكلفة الموجود (إن وُجد).
String? withEmpCommission(String? cost, num? n) {
  final parts = [
    if ((cost ?? '').isNotEmpty) cost!,
    if (n != null && n > 0) empCommissionText(n),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class EmployeeCommissionsApi {
  EmployeeCommissionsApi._();

  /// الفترة بأيّامها (بداية يوم [from] ونهاية يوم [to] ببغداد). null = لا بطاقة ولا شارة: بلا صلاحيّة الرواتب (403)، أو مطفأ، أو
  /// خادمٌ أقدم، أو تعذّر — للصفحة المفتوحة وحدها (المسار لا يُوجَّه في «كل الشركات» — كالرواتب المستحقّة).
  static Future<EmpCommissions?> fetch(DateTime from, DateTime to) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/employee-ledger/commissions',
        queryParameters: {'date_from': _ymd(from), 'date_to': _ymd(to)},
        options: CompanyRoute.explicit(null),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return EmpCommissions.fromJson(body['data']);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 employee-ledger commissions: $e');
      return null;
    }
  }
}

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
