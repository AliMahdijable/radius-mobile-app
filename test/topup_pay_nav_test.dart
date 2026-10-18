import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/screens/topup/pay_nav_policy.dart';
import 'package:rad_mysvcs/screens/topup/topup_pay_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// قاعدة التنقّل في صفحة دفع زين كاش — ما يُحمَّل وما يُلتقط وما يُمنع.
///
/// ⚠️ **المال هنا:** الرجوع إلى الساس يحمل توكن زين كاش، والرصيد لا يُضاف
/// إلّا إن وصل خادمنا. رجوعٌ لا يُلتقط = مالٌ دُفع بلا رصيد. وصفحة دفعٍ
/// تُلتقط خطأً = دفعٌ يُقطع في منتصفه.
void main() {
  final pay = Uri.parse('https://api.zaincash.iq/transaction/pay?id=abc123');

  PayNavPolicy policy({Object? capture}) => PayNavPolicy(
        capture: SelfDepositCapture.fromJson(capture ?? const {}),
        payUrl: pay,
      );

  group('الرجوع إلى الساس يُلتقط ولا يُحمَّل', () {
    test('🚨 مسار الهاش #/zaincash/process?token= — بلا معرفة المضيف', () {
      final p = policy();
      expect(
          p.decide('https://sas.speed.iq/#/zaincash/process?token=eyJhbGciOi.x.y'),
          PayNavAction.capture);
      expect(p.decide('https://sas.speed.iq/#/zaincashv2/process?token=t'),
          PayNavAction.capture);
      // الساس بعنوان IP ومنفذ.
      expect(p.decide('https://10.1.2.3:8443/#/zaincash/process?token=t'),
          PayNavAction.capture);
      // ومن ينتظر الـwebhook بلا توكن — يُلتقط أيضاً (الخادم يحكم).
      expect(p.decide('https://sas.speed.iq/#/zaincash/process?waiting_webhook=1'),
          PayNavAction.capture);
    });

    test('مضيف الساس من الخادم ⇒ أيّ رابطٍ عليه بدليل الدفع رجوعٌ (حتّى http)', () {
      final p = policy(capture: {'sas_host': 'SAS.Speed.iq'});
      expect(p.decide('http://sas.speed.iq/whatever?token=1'),
          PayNavAction.capture);
      expect(p.decide('https://sas.speed.iq./#/other/route?token=t'),
          PayNavAction.capture);
    });

    test('🚨 رابطٌ إلى الساس **بلا** توكن لا يُلتقط — يُحمَّل ويُلتقط الكامل بعده', () {
      final p = policy(capture: {'sas_host': 'sas.speed.iq'});
      // تحويلٌ وسيطٌ وصل بلا هاشه: إيقافه يُضيع الرابط الكامل الذي يليه.
      expect(p.decide('https://sas.speed.iq/'), PayNavAction.allow);
      expect(p.decide('https://sas.speed.iq/#/zaincash/process'),
          PayNavAction.allow);
      expect(p.decide('https://sas.speed.iq/admin/#/login'), PayNavAction.allow);
      // ثمّ يظهر الكامل (onUrlChange) فيُلتقط.
      expect(p.decide('https://sas.speed.iq/#/zaincash/process?token=a.b.c'),
          PayNavAction.capture);
      // ولا يُلتقط http بلا دليل — بل يُمنع كأيّ رابطٍ غير مشفَّر.
      expect(p.decide('http://sas.speed.iq/'), PayNavAction.block);
    });

    test('دليل الدفع في الهاش أو الاستعلام', () {
      expect(PayNavPolicy.hasProof(Uri.parse('https://x/#/a?token=t')), isTrue);
      expect(PayNavPolicy.hasProof(Uri.parse('https://x/?token=t#/a')), isTrue);
      expect(PayNavPolicy.hasProof(Uri.parse('https://x/#/a?waiting_webhook=1')),
          isTrue);
      expect(PayNavPolicy.hasProof(Uri.parse('https://x/#/a?token=')), isFalse);
      expect(PayNavPolicy.hasProof(Uri.parse('https://x/#/a?waiting_webhook=0')),
          isFalse);
    });

    test('مضيفون وأصولٌ بصيغٍ مختلفة', () {
      final c = SelfDepositCapture.fromJson({
        'origin': 'https://a.example.iq:8443',
        'hosts': ['b.example.iq', 'https://c.example.iq/x'],
        'routes': ['#/custom/return', 'pay/done'],
      });
      expect(c.hosts, {'a.example.iq', 'b.example.iq', 'c.example.iq'});
      expect(c.routes, containsAll(['/zaincash/process', '/custom/return', '/pay/done']));
      final p = PayNavPolicy(capture: c, payUrl: pay);
      expect(p.decide('https://x.iq/#/custom/return?token=1'), PayNavAction.capture);
      expect(p.decide('https://x.iq/pay/done?token=1'), PayNavAction.capture);
    });

    test('مسارٌ في المسار لا الهاش (ساسٌ بتوجيه المسارات)', () {
      expect(policy().decide('https://sas.iq/zaincash/process?token=1'),
          PayNavAction.capture);
      expect(policy().decide('https://sas.iq/admin/zaincash/process?token=1'),
          PayNavAction.capture);
    });
  });

  group('صفحة الدفع نفسها تُحمَّل', () {
    test('🚨 رابط الدفع ومضيفه لا يُلتقطان وإن حملا مسار الرجوع في معاملاتهم', () {
      final p = policy();
      expect(p.decide(pay.toString()), PayNavAction.allow);
      expect(
          p.decide('https://api.zaincash.iq/transaction/pay?id=1'
              '&redirect=https%3A%2F%2Fsas.iq%2F%23%2Fzaincash%2Fprocess'),
          PayNavAction.allow);
      // حتى لو كان مسار مضيف الدفع يشبه الرجوع.
      expect(p.decide('https://api.zaincash.iq/#/zaincash/process'),
          PayNavAction.allow);
    });

    test('https لأيّ مضيف (صفحات زين كاش الفرعيّة، OTP…)', () {
      expect(policy().decide('https://otp.zaincash.iq/verify'), PayNavAction.allow);
      expect(policy().decide('about:blank'), PayNavAction.allow);
    });
  });

  group('ما يُخرج الدفع من هنا يُمنع', () {
    test('🚨 تطبيقاتٌ خارجيّة وروابط غير مشفَّرة وجافاسكربت', () {
      final p = policy();
      for (final u in [
        'http://api.zaincash.iq/transaction/pay?id=1',
        'intent://pay#Intent;scheme=zaincash;end',
        'zaincash://pay?id=1',
        'tel:07800000000',
        'sms:07800000000',
        'mailto:a@b.c',
        'javascript:alert(1)',
        'data:text/html,hi',
        'file:///etc/passwd',
        'about:config',
        '',
        'https://',
      ]) {
        expect(p.decide(u), PayNavAction.block, reason: u);
      }
    });
  });

  group('أخطاء التحميل', () {
    test('أندرويد: أخطاء الشبكة للإطار الرئيسيّ وحده', () {
      expect(
          isFatalLoadError(
              type: WebResourceErrorType.hostLookup, code: -2, mainFrame: true),
          isTrue);
      expect(
          isFatalLoadError(
              type: WebResourceErrorType.timeout, code: -8, mainFrame: true),
          isTrue);
      expect(
          isFatalLoadError(
              type: WebResourceErrorType.hostLookup, code: -2, mainFrame: false),
          isFalse);
      expect(
          isFatalLoadError(
              type: WebResourceErrorType.unsupportedScheme,
              code: -10,
              mainFrame: true),
          isFalse);
    });

    test('آيفون: الرمز وحده — ‎-999 (منعناه) و‎102 (السياسة) ليسا عطلاً', () {
      expect(isFatalLoadError(code: -1009, mainFrame: true), isTrue); // لا نت
      expect(isFatalLoadError(code: -1200, mainFrame: true), isTrue); // شهادة
      expect(isFatalLoadError(code: -999, mainFrame: true), isFalse);
      expect(isFatalLoadError(code: 102, mainFrame: true), isFalse);
      expect(isFatalLoadError(code: -1002, mainFrame: true), isFalse);
    });
  });
}
