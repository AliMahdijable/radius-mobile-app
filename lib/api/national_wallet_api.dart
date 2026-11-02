import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'national_device_api.dart';
import 'national_sheet_api.dart';

/// «تعبئة محفظة المشترك» — المشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع `WataniWalletTopup.tsx`؛ الخادم
/// `server/watani/wataniWallet.js`، المالك: «شحن المحفظة كملهن ويب وتطبيقات» والطريقة «الاثنين»):
///   GET  /api/v2/ftth/subscriptions/:sid/wallet/topup     الرصيدان (المجهول null)، المستلم المطابق، الطريقتان وسبب قفل كلٍّ، الحدود
///   POST /api/v2/ftth/subscriptions/:sid/wallet/transfer  {amount, paymentType: cash|non-cash|partial-cash, partialAmount?, confirmRepeat?}
///   POST /api/v2/ftth/subscriptions/:sid/wallet/card      {pin}
/// لصاحب الحساب وحده، خلف مفتاح watani_wallet بالخادم. كتابةٌ واحدة بلا إعادة؛ النتيجة: تمّ / لم يتمّ / لم يتأكّد. رقم الكارت لا
/// يُخزَّن في التطبيق ولا يُعاد.

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v is num && v.isFinite) return v.round();
  if (v is String) return num.tryParse(v.trim())?.round();
  return null;
}

class WalletTopupInfo {
  const WalletTopupInfo({
    required this.transferOk,
    this.transferReason,
    required this.cardOk,
    this.cardReason,
    this.partnerBalance,
    this.customerBalance,
    this.targetName,
    this.targetPhone,
    this.min = 1000,
    this.max = 1000000,
    this.step = 250,
    this.recentAmount,
    this.recentUnknown = false,
    this.recentMinutes,
  });
  final bool transferOk;
  final String? transferReason;
  final bool cardOk;
  final String? cardReason;

  /// رصيد محفظة الوكيل ورصيد محفظة المشترك — المجهول null لا صفر.
  final int? partnerBalance;
  final int? customerBalance;

  /// المستلم المطابق: اسمه وهاتفه مقنَّعاً (•••1234).
  final String? targetName;
  final String? targetPhone;
  final int min;
  final int max;
  final int step;

  /// تحويلٌ حديث لهذا المشترك (خلال ١٠ دقائق): مبلغه، ولم يتأكّد؟
  final int? recentAmount;
  final bool recentUnknown;
  final int? recentMinutes;

  static WalletTopupInfo fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : const {};
    final t = m(j['transfer']);
    final c = m(j['card']);
    final target = m(j['target']);
    final lim = m(j['limits']);
    final rec = m(j['recent']);
    return WalletTopupInfo(
      transferOk: t['ok'] == true,
      transferReason: _sn(t['reason']),
      cardOk: c['ok'] == true,
      cardReason: _sn(c['reason']),
      partnerBalance: _int(j['partner_balance']),
      customerBalance: _int(j['customer_balance']),
      targetName: _sn(target['name']),
      targetPhone: _sn(target['phone']),
      min: _int(lim['min']) ?? 1000,
      max: _int(lim['max']) ?? 1000000,
      step: _int(lim['step']) ?? 250,
      recentAmount: _int(rec['amount']),
      recentUnknown: rec['outcome'] == 'unknown',
      recentMinutes: _int(rec['minutes']),
    );
  }
}

enum WalletTopupState {
  /// تمّ — المبلغ في محفظة المشترك.
  applied,

  /// لم يتمّ (رفضٌ صريح أو لم يُرسل) — لم يتغيّر شيء.
  rejected,

  /// لم يتأكّد — لا إعادة قبل التحقّق من محفظة المشترك.
  unknown,

  /// تحويلٌ حديث لهذا المشترك — يحتاج تأكيداً (confirmRepeat).
  repeat,
}

class WalletTopupResult {
  const WalletTopupResult(this.state, {this.message, this.code, this.amount, this.debtAdded, this.credited, this.customerBalance, this.debtWarning});
  final WalletTopupState state;
  final String? message;
  final String? code;
  final int? amount;
  final int? debtAdded;
  final int? credited;
  final int? customerBalance;

  /// التحويل تمّ لكنّ الدين لم يُسجَّل بدفترنا — يُقال للوكيل ليسجّله يدويّاً.
  final String? debtWarning;

  bool get applied => state == WalletTopupState.applied;

  static WalletTopupResult of(dynamic b) {
    if (b is! Map) return const WalletTopupResult(WalletTopupState.rejected, message: 'ردٌّ غير متوقّع من الخادم — لم يتغيّر شيء');
    final code = _sn(b['code']);
    final msg = [_sn(b['message']), _sn(b['portal_message'])].whereType<String>().join(' — ');
    if (b['success'] == true && b['outcome'] == 'applied') {
      final d = b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const <String, dynamic>{};
      final dw = b['debt_write'];
      return WalletTopupResult(
        WalletTopupState.applied,
        amount: _int(d['amount']),
        debtAdded: _int(d['debt_added']),
        credited: _int(d['credited']),
        customerBalance: _int(d['customer_balance']),
        debtWarning: dw is Map && dw['ok'] == false ? (_sn(dw['message']) ?? 'لم يُسجَّل الدين — سجّله يدويّاً') : null,
      );
    }
    if (code == 'RECENT_DUPLICATE') return WalletTopupResult(WalletTopupState.repeat, code: code, message: msg.isEmpty ? null : msg);
    if (code == 'OUTCOME_UNKNOWN' || b['outcome'] == 'unknown') {
      return WalletTopupResult(WalletTopupState.unknown, code: code,
          message: msg.isEmpty ? 'لم يتأكّد — افتح محفظة المشترك بعد دقيقة وتحقّق قبل أيّ إعادة' : msg);
    }
    return WalletTopupResult(WalletTopupState.rejected, code: code, message: msg.isEmpty ? 'تعذّر التنفيذ — لم يتغيّر شيء' : msg);
  }
}

class NationalWalletApi {
  NationalWalletApi._();

  /// مهلة الخادم ٣٠ث للكتابة + قراءة الرصيد قبلها وبعدها (+٣ث للتحقّق) — لا نقطع قبله فنظنّه «لم يتأكّد».
  static const _writeTimeout = Duration(seconds: 80);

  static String _base(String sid) => '/api/v2/ftth/subscriptions/${Uri.encodeComponent(sid)}/wallet';

  /// النافذة — ok(info) · locked · fail.
  static Future<NationalSheetResult<WalletTopupInfo?>> info(String sid) async {
    try {
      final r = await ApiClient.dio.get<dynamic>('${_base(sid)}/topup');
      final x = NationalDeviceApi.readOf(r.data);
      if (!x.ok || x.data == null) {
        if (x.locked) return NationalSheetResult.locked(x.lock!);
        if (!x.ok) return NationalSheetResult.fail(x.error, code: x.code, relogin: x.relogin);
        return const NationalSheetResult.ok(null);
      }
      final d = x.data!['data'];
      return d is Map ? NationalSheetResult.ok(WalletTopupInfo.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 wallet/topup: $e');
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  static Future<WalletTopupResult> _send(String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post<dynamic>(path,
          data: body, options: Options(receiveTimeout: _writeTimeout, sendTimeout: _writeTimeout));
      return WalletTopupResult.of(r.data);
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 POST wallet: ${e.response?.statusCode}');
      final b = e.response?.data;
      if (b is Map) return WalletTopupResult.of(b);
      if (e.type == DioExceptionType.receiveTimeout) {
        return const WalletTopupResult(WalletTopupState.unknown,
            message: 'انقطع الاتّصال قبل الردّ — ربّما تمّ: افتح محفظة المشترك بعد دقيقة وتحقّق قبل أيّ إعادة');
      }
      return const WalletTopupResult(WalletTopupState.rejected, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 POST wallet: $e');
      return const WalletTopupResult(WalletTopupState.rejected, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    }
  }

  /// من محفظة الوكيل إلى محفظة المشترك. [payType]: cash · non-cash · partial-cash ([partial] المدفوع نقداً).
  static Future<WalletTopupResult> transfer(String sid, {required int amount, required String payType, int? partial, bool confirmRepeat = false}) =>
      _send('${_base(sid)}/transfer', {
        'amount': amount,
        'paymentType': payType,
        if (payType == 'partial-cash') 'partialAmount': partial ?? 0,
        if (confirmRepeat) 'confirmRepeat': true,
      });

  /// بكارت الشركة — الرقم يمرّ للخادم وحده ولا يُحفظ.
  static Future<WalletTopupResult> card(String sid, String pin) => _send('${_base(sid)}/card', {'pin': pin});
}
