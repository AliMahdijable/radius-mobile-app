import 'package:flutter/foundation.dart';

import 'company_route.dart';

/// ما قاله الخادم عن المشترك بعد عمليّةٍ ناجحة (تفعيل/تمديد/تسديد) — للوصل وحده.
///
/// كان الوصل يقدّر الانتهاء الجديد «اليوم + مدّة الباقة»، والساس يمدّ من انتهاء المشترك
/// الفعّال لا من اليوم. الخادم يعيد `data.updated` (الانتهاء والأيّام بعد العمليّة) و
/// `data.new_balance` (ساس وايرث لنك سواء) — يُلتقطان هنا عند النجاح، قراءةً لا تمسّ العمليّة،
/// ويقرؤهما الوصل مرّةً واحدة ([take]).
@immutable
class ReceiptFacts {
  const ReceiptFacts({this.expiration, this.remainingDays, this.newBalance, this.amountPaid});

  final String? expiration;
  final int? remainingDays;

  /// رصيد المشترك بعد العمليّة: سالبٌ = دين.
  final num? newBalance;

  /// ما سُدِّد فعلاً (`amount_paid`) — «كامل الدين» يقرؤه الخادم حيّاً من الساس، فقد يخالف
  /// الرقم المعروض في الشيت.
  final num? amountPaid;

  static const _maxAge = Duration(minutes: 2);
  static final Map<String, ({ReceiptFacts facts, DateTime at})> _last = {};

  /// «كل الشركات»: المفتاح بشركة الطلب — idx قد يتكرّر بين شركتين.
  static String _key(String? companyKey, String idx) => '${companyKey ?? ''}|$idx';

  /// من جسم ردٍّ ناجح لـ[idx] (داخل نطاق الشركة الموجَّه إن وُجد).
  static void capture(String idx, Object? body) {
    final f = parse(body);
    if (f == null) return;
    _last[_key(CompanyRoute.currentKey, idx)] = (facts: f, at: DateTime.now());
  }

  /// ما التُقط لـ[idx] في الدقيقتين الأخيرتين — ويُنسى بقراءته.
  static ReceiptFacts? take(String? idx, {String? companyKey}) {
    if (idx == null || idx.isEmpty) return null;
    final hit = _last.remove(_key(companyKey, idx));
    if (hit == null || DateTime.now().difference(hit.at) > _maxAge) return null;
    return hit.facts;
  }

  @visibleForTesting
  static ReceiptFacts? parse(Object? body) {
    final data = body is Map ? body['data'] : null;
    if (data is! Map) return null;
    final up = data['updated'];
    final updated = up is Map ? up : const {};
    final exp = '${updated['expiration'] ?? ''}'.trim();
    final days = int.tryParse('${updated['remaining_days'] ?? ''}');
    // التسديد والتفعيل: new_balance. التمديد لا يغيّر الدين فيعيد الرصيد في updated.notes.
    final nb = num.tryParse('${data['new_balance'] ?? ''}') ?? num.tryParse('${updated['notes'] ?? ''}');
    final paid = num.tryParse('${data['amount_paid'] ?? ''}');
    if (exp.isEmpty && days == null && nb == null && paid == null) return null;
    return ReceiptFacts(
      expiration: exp.isEmpty ? null : exp,
      remainingDays: days,
      newBalance: nb,
      amountPaid: paid,
    );
  }

  @visibleForTesting
  static void clear() => _last.clear();
}
