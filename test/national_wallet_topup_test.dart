import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/api/national_wallet_api.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_topup_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تعبئة محفظة المشترك» في التطبيق (٢ نوفمبر — نسخة الموقع WataniWalletTopup؛ الخادم wataniWallet.js): الرصيدان والمستلم، التحويل
/// بجسمٍ بالضبط (نقداً/دين/جزئيّ)، تأكيد التحويل الثاني (confirmRepeat)، الكارت بأرقامٍ عربيّة ⇒ لاتينيّة ولا يبقى في الحقل، والقفل
/// بسببه بلا زرّ؛ وقراءة النتائج الثلاث.
const _v = SimVariant(390, dark: false);
const _sid = '555';
const _base = '/api/v2/ftth/subscriptions/$_sid/wallet';

Map<String, Object?> _info({bool transferOk = true, bool cardOk = true, Map<String, Object?>? recent}) => {
      'success': true,
      'data': {
        'transfer': {'ok': transferOk, 'reason': transferOk ? null : 'حسابك في المشروع الوطني لا يملك صلاحيّة «تحويل الرصيد»'},
        'card': {'ok': cardOk, 'reason': cardOk ? null : 'لا صلاحيّة'},
        'partner_balance': 1250000,
        'customer_balance': 5000,
        'target': {'name': 'مريم عبد الله', 'phone': '•••4567'},
        'limits': {'min': 1000, 'max': 1000000, 'step': 250},
        'recent': recent,
      },
    };

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

Future<void> _typeAmount(WidgetTester t, int index, String text) async {
  final f = find.byType(TextField).at(index);
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

void main() {
  group('القراءة', () {
    test('النافذة والنتائج الثلاث', () {
      final i = WalletTopupInfo.fromJson(Map<String, dynamic>.from(_info(recent: {'amount': 25000, 'outcome': 'unknown', 'minutes': 3})['data'] as Map));
      expect((i.transferOk, i.cardOk, i.partnerBalance, i.customerBalance, i.targetPhone, i.min, i.step, i.recentAmount, i.recentUnknown),
          (true, true, 1250000, 5000, '•••4567', 1000, 250, 25000, true));
      final ok = WalletTopupResult.of({'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'debt_added': 15000, 'customer_balance': 30000}});
      expect((ok.state, ok.amount, ok.debtAdded, ok.customerBalance, ok.debtWarning), (WalletTopupState.applied, 25000, 15000, 30000, null));
      final dw = WalletTopupResult.of({'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'debt_added': 0}, 'debt_write': {'ok': false, 'message': 'سجّله يدويّاً'}});
      expect(dw.debtWarning, 'سجّله يدويّاً');
      expect(WalletTopupResult.of({'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد'}).state, WalletTopupState.unknown);
      expect(WalletTopupResult.of({'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'أكّد'}).state, WalletTopupState.repeat);
      final rej = WalletTopupResult.of({'success': false, 'code': 'PORTAL_REJECTED', 'message': 'رفضت', 'portal_message': 'Insufficient'});
      expect((rej.state, rej.message), (WalletTopupState.rejected, 'رفضت — Insufficient'));
      expect(walletDigits('١٢٣٤ ٥٦٧٨-۹0'), '1234567890');
      expect(NationalBeta.fromJson({'beta': true, 'wallet_topup': true}).walletTopup, isTrue);
      expect(NationalBeta.fromJson({'beta': true}).walletTopup, isFalse);
    });
  });

  group('النافذة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    WalletTopupResult? got;
    Future<void> open(WidgetTester t) async {
      got = null;
      await pumpSim(t, _v, home: (_) => simLauncher((c) async => got = await showNationalWalletTopupSheet(c, sid: _sid)));
      await simOpen(t);
      await _settle(t);
    }

    testWidgets('الرصيدان والمستلم، ثمّ تحويلٌ ديناً بجسمٍ بالضبط ⇒ تُغلق النافذة بالنتيجة', (t) async {
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('POST', '$_base/transfer', 200, {
        'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'payment_type': 'non-cash', 'cash_paid': 0, 'debt_added': 25000, 'customer_balance': 30000},
      });
      await open(t);
      expect(find.text('تعبئة محفظة المشترك'), findsOneWidget);
      expect(find.textContaining('مريم عبد الله'), findsOneWidget);
      expect(find.textContaining('•••4567'), findsOneWidget);
      await _typeAmount(t, 0, '25000');
      await t.tap(find.text('دين'));
      await t.pumpAndSettle();
      expect(find.textContaining('ويُسجَّل عليه دين'), findsOneWidget);
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/transfer').single, {'amount': 25000, 'paymentType': 'non-cash'});
      expect(got?.state, WalletTopupState.applied);
      expect(got?.debtAdded, 25000);
      expect(find.text('تعبئة محفظة المشترك'), findsNothing, reason: 'أُغلقت');
      await simDrain(t);
    });

    testWidgets('جزئيّ يرسل المدفوع؛ وتحويلٌ حديث ⇒ «نعم، تحويلٌ آخر» يرسل confirmRepeat', (t) async {
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('POST', '$_base/transfer', 409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'حُوّل لهذا المشترك 25,000 د.ع قبل دقائق — أكّد إن كان تحويلاً آخر'});
      await open(t);
      await _typeAmount(t, 0, '25000');
      await t.tap(find.text('جزئيّ'));
      await t.pumpAndSettle();
      await _typeAmount(t, 1, '10000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/transfer').single, {'amount': 25000, 'paymentType': 'partial-cash', 'partialAmount': 10000});
      expect(find.textContaining('أكّد إن كان تحويلاً آخر'), findsOneWidget);
      server.reply('POST', '$_base/transfer', 200, {'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'debt_added': 15000}});
      await t.tap(find.text('نعم، تحويلٌ آخر'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/transfer').last, {'amount': 25000, 'paymentType': 'partial-cash', 'partialAmount': 10000, 'confirmRepeat': true});
      expect(got?.state, WalletTopupState.applied);
      await simDrain(t);
    });

    testWidgets('الرفض يبقى في النافذة بنصّه؛ والكارت بأرقامٍ عربيّة يُرسل لاتينيّاً ولا يبقى في الحقل', (t) async {
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('POST', '$_base/card', 409, {'success': false, 'code': 'CARD_REJECTED', 'outcome': 'not_applied', 'message': 'لم تقبل البوّابة الكارت — تأكّد من الرقم وأنّه غير مستعمل (لم يتغيّر شيء)'});
      await open(t);
      await t.tap(find.text('بكارت'));
      await t.pumpAndSettle();
      expect(find.textContaining('لا يُحفظ عندنا'), findsOneWidget);
      await _typeAmount(t, 0, '١٢٣٤ ٥٦٧٨ ٩٠١٢');
      await t.tap(find.text('عبّئ بالكارت'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/card').single, {'pin': '123456789012'});
      expect(find.textContaining('لم تقبل البوّابة الكارت'), findsOneWidget);
      expect(find.text('١٢٣٤ ٥٦٧٨ ٩٠١٢'), findsNothing, reason: 'الرقم لا يبقى في الحقل');
      expect(got, isNull, reason: 'النافذة باقية');
      await simDrain(t);
    });

    testWidgets('انقطاعٌ بعد الإرسال أو 502 ليس منّا ⇒ «ربّما تمّ» وتُغلق النافذة؛ تعذّر الاتّصال أصلاً ⇒ «لم يُرسل شيء» وتبقى', (t) async {
      server.reply('GET', '$_base/topup', 200, _info());
      server.on('POST', '$_base/transfer', (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
      await open(t);
      await _typeAmount(t, 0, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(got?.state, WalletTopupState.unknown, reason: 'انقطاعٌ بعد الإرسال ليس «لم يتغيّر شيء»');
      expect(find.text('تعبئة محفظة المشترك'), findsNothing, reason: 'أُغلقت لتُقرأ المحفظة');

      server.on('POST', '$_base/transfer', (o) => const SimReply(502, '<html>Bad gateway</html>'));
      await open(t);
      await _typeAmount(t, 0, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(got?.state, WalletTopupState.unknown, reason: '5xx ليس ردّنا');

      server.on('POST', '$_base/transfer', (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionTimeout));
      await open(t);
      await _typeAmount(t, 0, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(got, isNull, reason: 'لم يتّصل أصلاً ⇒ النافذة باقية');
      expect(find.textContaining('لم يُرسل شيء'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('التحويل مقفلٌ بسببه بلا زرّ إرسال؛ والكارت متاح', (t) async {
      server.reply('GET', '$_base/topup', 200, _info(transferOk: false));
      await open(t);
      expect(find.textContaining('«تحويل الرصيد»'), findsOneWidget);
      expect(find.textContaining('حوّل'), findsNothing);
      await t.tap(find.text('بكارت'));
      await t.pumpAndSettle();
      expect(find.text('عبّئ بالكارت'), findsOneWidget);
      expect(server.calls('POST', '$_base/transfer'), isEmpty);
      expect(server.calls('POST', '$_base/card'), isEmpty);
      await simDrain(t);
    });
  });
}
