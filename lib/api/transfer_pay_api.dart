import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/server_time.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «الحوالات» (٢٣ نوفمبر — الخادم server/transferPay.js `abd6761`، الموقع `1f51a9a`): نداءات الخادم.
///
/// - `GET /api/v2/transfer-pay` ⇒ `{available, methods, names}` — هل تُعرض «استلمته» لهذه الصفحة (المفتاح `transfer_pay`،
///   ساس فور وحده الآن) وأسماء «أخرى» المستعملة.
/// - `GET /api/v2/transfer-pots` ⇒ `{available, pots, total, withdrawals, can_withdraw}` — رصيد كلّ طريقة وآخر السحوبات.
/// - `POST /api/v2/transfer-pots/withdraw` `{paid_via, paid_via_name?, amount, note?, client_ref}` — «سحب للصندوق»؛ المفتاح
///   نفسه ⇒ السحب نفسه (`duplicate`) فالإعادة لا تسحب مرّتين.
/// - `POST /api/v2/transfer-pots/withdrawals/:id/void` `{reason?}` — إلغاء سحب (مرّةً واحدة).
///
/// كلّها للشركة المفتوحة ([CompanyRoute.runOpen]): «كل الشركات» لا يوجّهها (ليست في قائمة الخادم).
class TransferPotData {
  const TransferPotData({
    required this.key,
    required this.via,
    required this.name,
    required this.label,
    required this.received,
    required this.withdrawn,
    required this.balance,
    required this.count,
  });

  /// zaincash | master | other:<الاسم>
  final String key;

  /// zaincash | master | other
  final String via;
  final String? name;
  final String label;
  final num received;
  final num withdrawn;

  /// الباقي الآن = ما وصل − ما سُحب.
  final num balance;
  final int count;

  static TransferPotData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final via = raw['via']?.toString() ?? '';
    if (via != 'zaincash' && via != 'master' && via != 'other') return null;
    final name = raw['name']?.toString();
    return TransferPotData(
      key: raw['key']?.toString() ?? via,
      via: via,
      name: (name ?? '').trim().isEmpty ? null : name!.trim(),
      label: raw['label']?.toString() ?? via,
      received: _num(raw['received']),
      withdrawn: _num(raw['withdrawn']),
      balance: _num(raw['balance']),
      count: _num(raw['count']).toInt(),
    );
  }
}

class TransferWithdrawalData {
  const TransferWithdrawalData({
    required this.id,
    required this.via,
    required this.name,
    required this.label,
    required this.amount,
    required this.isVoidRow,
    required this.voided,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final String via;
  final String? name;
  final String label;

  /// موجبٌ للسحب، سالبٌ لسطر الإلغاء.
  final num amount;

  /// سطر إلغاء (`kind == 'withdraw_void'`).
  final bool isVoidRow;

  /// سحبٌ أُلغي (له سطر إلغاء).
  final bool voided;
  final String? note;
  final DateTime? createdAt;

  static TransferWithdrawalData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _num(raw['id']).toInt();
    if (id <= 0) return null;
    final name = raw['name']?.toString();
    final note = raw['note']?.toString();
    return TransferWithdrawalData(
      id: id,
      via: raw['via']?.toString() ?? '',
      name: (name ?? '').trim().isEmpty ? null : name!.trim(),
      label: raw['label']?.toString() ?? '',
      amount: _num(raw['amount']),
      isVoidRow: raw['kind']?.toString() == 'withdraw_void',
      voided: raw['voided'] == true,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      createdAt: _time(raw['created_at']),
    );
  }
}

class TransferPotsData {
  const TransferPotsData({required this.available, required this.pots, required this.total, required this.withdrawals, required this.canWithdraw});

  final bool available;
  final List<TransferPotData> pots;
  final num total;
  final List<TransferWithdrawalData> withdrawals;

  /// السحب وإلغاؤه للمدير وحده (المالك: «الى ان المدير يسحبها»).
  final bool canWithdraw;

  /// لا مفتاح ولا رصيد ولا سحوبات ⇒ لا بطاقة (الشاشة كما كانت).
  bool get hidden => !available && pots.isEmpty && withdrawals.isEmpty;

  static TransferPotsData fromJson(Map<String, dynamic> d) => TransferPotsData(
        available: d['available'] == true,
        pots: [
          for (final p in (d['pots'] is List ? d['pots'] as List : const []))
            if (TransferPotData.fromJson(p) case final v?) v,
        ],
        total: _num(d['total']),
        withdrawals: [
          for (final w in (d['withdrawals'] is List ? d['withdrawals'] as List : const []))
            if (TransferWithdrawalData.fromJson(w) case final v?) v,
        ],
        canWithdraw: d['can_withdraw'] == true,
      );
}

/// نتيجة سحبٍ أو إلغاء: [unknown] = لم يصل ردٌّ (أو قال الخادم إنّه لم يتأكّد) — قد يكون نُفّذ، فلا «فشل» ولا «نجاح».
typedef TransferWriteResult = ({bool ok, bool duplicate, bool unknown, String? code, String? message});

abstract final class TransferPayApi {
  /// هل تُعرض «استلمته» + أسماء «أخرى». null = تعذّرت القراءة (يبقى ما كان).
  static Future<({bool available, List<String> names})?> info() async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Map<String, dynamic>>('/api/v2/transfer-pay'));
      final d = r.data?['data'];
      if (d is! Map) return null;
      final names = <String>[
        for (final n in (d['names'] is List ? d['names'] as List : const []))
          if (n is String && n.trim().isNotEmpty) n.trim(),
      ];
      return (available: d['available'] == true, names: names.take(8).toList());
    } catch (e) {
      if (kDebugMode) debugPrint('[transfer-pay] info: $e');
      return null;
    }
  }

  /// رصيد كلّ طريقة وآخر السحوبات (صلاحيّة settlements.view). null = تعذّرت القراءة.
  static Future<TransferPotsData?> pots() async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.get<Map<String, dynamic>>('/api/v2/transfer-pots'));
      final d = r.data?['data'];
      if (d is! Map) return null;
      return TransferPotsData.fromJson(Map<String, dynamic>.from(d));
    } catch (e) {
      if (kDebugMode) debugPrint('[transfer-pay] pots: $e');
      return null;
    }
  }

  /// مفتاح الطلب: نفسه لكلّ إعادةٍ من الشيت نفسه ⇒ الخادم يردّ السحب نفسه ولا يسحب مرّتين.
  static String newClientRef() {
    final r = Random.secure();
    return 'tw${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// «سحب للصندوق» من رصيد [via] (+ [name] لـ«أخرى»).
  static Future<TransferWriteResult> withdraw({
    required String via,
    String? name,
    required num amount,
    String? note,
    required String clientRef,
  }) =>
      _write('/api/v2/transfer-pots/withdraw', {
        'paid_via': via,
        if (via == 'other') 'paid_via_name': name ?? '',
        'amount': amount,
        'client_ref': clientRef,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      });

  /// إلغاء سحب [id] (مرّةً واحدة): يرجع المبلغ لرصيد طريقته ويخرج من الصندوق.
  static Future<TransferWriteResult> voidWithdrawal(int id, {String? reason}) =>
      _write('/api/v2/transfer-pots/withdrawals/$id/void', {
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
      });

  static Future<TransferWriteResult> _write(String path, Map<String, Object?> body) async {
    try {
      final r = await CompanyRoute.runOpen(() => ApiClient.dio.post<Map<String, dynamic>>(path, data: body));
      final b = r.data ?? const {};
      final ok = b['success'] == true;
      return (ok: ok, duplicate: b['duplicate'] == true, unknown: false, code: b['code']?.toString(), message: b['message']?.toString());
    } on DioException catch (e) {
      final b = e.response?.data;
      final code = b is Map ? b['code']?.toString() : null;
      final message = b is Map ? b['message']?.toString() : null;
      // لا ردّ (انقطاع/مهلة) أو قال الخادم «لم نتأكّد» ⇒ قد يكون نُفّذ
      final unknown = e.response == null || code == 'TRANSFER_OUTCOME_UNKNOWN';
      if (kDebugMode) debugPrint('[transfer-pay] $path: ${e.response?.statusCode} $code');
      return (ok: false, duplicate: false, unknown: unknown, code: code, message: message);
    } catch (e) {
      if (kDebugMode) debugPrint('[transfer-pay] $path: $e');
      return (ok: false, duplicate: false, unknown: true, code: null, message: null);
    }
  }
}

num _num(Object? v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

DateTime? _time(Object? v) => parseServerUtc(v?.toString());

/// «النقد المُستلم» حسب الطريقة (GET /reports/finance → kpis.cash_by_via) — يُرسل حين توجد حوالةٌ بالفترة وحدها.
class CashByViaData {
  const CashByViaData({required this.cash, required this.transfersSum, required this.transfers});

  final num cash;
  final num transfersSum;
  final List<({String key, String via, String label, num sum, int count})> transfers;

  static CashByViaData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['transfers'];
    if (list is! List || list.isEmpty) return null;
    return CashByViaData(
      cash: _num(raw['cash']),
      transfersSum: _num(raw['transfers_sum']),
      transfers: [
        for (final t in list)
          if (t is Map)
            (
              key: t['key']?.toString() ?? '',
              via: t['via']?.toString() ?? '',
              label: t['label']?.toString() ?? '',
              sum: _num(t['sum']),
              count: _num(t['count']).toInt(),
            ),
      ],
    );
  }

  /// سطور العرض: الكاش = المجموع المعروض ([total] — بطاقة «الإيراد النقدي» نفسها) ناقص الحوالات، فيبقى المجموع هو نفسه.
  List<({String via, String label, num sum, int? count})> rows(num total) => [
        (via: 'cash', label: 'كاش', sum: total - transfersSum, count: null),
        for (final t in transfers) (via: t.via, label: t.label, sum: t.sum, count: t.count),
      ];

  /// سطر التصدير: «منه: كاش X · زين كاش Y · …».
  String exportLine(num total, String Function(num) money) => 'منه: ${rows(total).map((r) => '${r.label} ${money(r.sum)}').join(' · ')}';
}

/// مبلغ طريقةٍ واحدة (زين كاش / ماستر / «أخرى» باسمها) في [FinanceTwData].
typedef TwViaSum = ({String via, String? name, String label, num sum});

/// «الحوالات» بالتقرير الماليّ (٢٦ نوفمبر — المالك: «… وماينحسبن بالمال المستلم لان هنه بعدهن بالماستر الى ان يسحبهن … يلا
/// ينزلن» ثمّ «نعم موافق»؛ كالموقع FinanceTw): `kpis.tw` — ما سُحب للصندوق بالفترة (بتاريخ السحب؛ إلغاء السحب سالبٌ داخله) ورصيد
/// كلّ طريقةٍ الآن (لم يُسحب). يرسله الخادم حين يوجد منه شيءٌ وحده، وبلا فلتر موظّفٍ ولا نوع (السحب للمدير ولا نوع له).
class FinanceTwData {
  const FinanceTwData({required this.withdrawn, this.withdrawnByVia = const [], required this.pendingNow, this.pendingByVia = const []});

  final num withdrawn;
  final List<TwViaSum> withdrawnByVia;
  final num pendingNow;
  final List<TwViaSum> pendingByVia;

  static FinanceTwData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    List<TwViaSum> list(Object? v) => [
          if (v is List)
            for (final x in v)
              if (x is Map)
                (
                  via: x['via']?.toString() ?? '',
                  name: (x['name']?.toString() ?? '').trim().isEmpty ? null : x['name'].toString().trim(),
                  label: x['label']?.toString() ?? '',
                  sum: _num(x['sum']),
                ),
        ];
    return FinanceTwData(
      withdrawn: _num(raw['withdrawn']),
      withdrawnByVia: list(raw['withdrawn_by_via']),
      pendingNow: _num(raw['pending_now']),
      pendingByVia: list(raw['pending_by_via']),
    );
  }
}

/// «المال المستلم» (٢٦ نوفمبر، كالموقع cashInHandOf) = الكاش (المجموع [total] ناقص ما استُلم حوالةً بالفترة) + ما سُحب للصندوق
/// بالفترة — null بلا حوالةٍ ولا سحب (البطاقة «الإيراد النقدي» كما كانت). الربح لا يتغيّر (الحوالة مالُك وإن لم تُسحب): هذا لما
/// بيدك وحده.
({num cash, num withdrawn, num inHand, num pending})? cashInHandOf(num total, CashByViaData? byVia, FinanceTwData? tw) {
  if (byVia == null && tw == null) return null;
  final cash = total - (byVia?.transfersSum ?? 0);
  final withdrawn = tw?.withdrawn ?? 0;
  return (cash: cash, withdrawn: withdrawn, inHand: cash + withdrawn, pending: tw?.pendingNow ?? 0);
}
