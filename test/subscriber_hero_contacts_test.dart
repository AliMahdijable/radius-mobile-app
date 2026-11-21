import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/subscriber_contacts_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «الرقم الثاني ومعرف التلي كرام يظهرهن هنا وي كارت» (المالك ١٤ نوفمبر ٢٠٢٦ — لقطة بطاقة الهويّة): الأرقام الإضافيّة داخل
/// بطاقة الهويّة تحت سطر الهاتف وبشكله — لا كرت منفصل؛ القائم وحده؛ لا قصّ على ٣٢٠ بخطّ ١٫٢ ولا على ٤٨٠؛ «نسخ كلّ المعلومات»
/// يضمّها تحت الهاتف؛ والمفتاح المطفأ و«كل الشركات» ⇒ لا شيء.
Subscriber _sub({String? companyKey}) => Subscriber.fromJson({
      'idx': '7',
      'username': 'user7',
      'firstname': 'اثير',
      'lastname': 'الركابي',
      'phone': '9647765670141',
      'profile_name': '3--Standard',
      'profile_id': 7,
      'expiration': '2026-11-20 14:30:00',
      'online_status': 0,
      'enabled': 1,
      'notes': '-55000',
      'parent_username': 'admin@popq',
      'package_price': 45000,
    }).withCompany(companyKey);

List<String> _mockClipboard(WidgetTester t) {
  final clips = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') clips.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return clips;
}

final _hero = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SubscriberHero');

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'myservices'});
    SubscribersApi.clearAllCaches();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });
  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  void contacts(Map<String, Object?>? c, {bool enabled = true}) =>
      server.reply('GET', SubscriberContactsApi.path, 200, {'success': true, 'enabled': enabled, 'contact': c});

  Future<void> open(WidgetTester t, SimVariant v, {Subscriber? sub, double scale = 1.0}) async {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, v, home: (_) => SubscriberDetailScreen(sub: sub ?? _sub()), settle: false);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  testWidgets('داخل بطاقة الهويّة تحت الهاتف: «ثانٍ» بالرقم و«تلغرام» بالمعرّف — ولا كرت منفصل', (t) async {
    contacts({'wa_phone2': '07801234567', 'tg_contact': '@ali_hasan'});
    await open(t, const SimVariant(390, dark: false));
    for (final s in ['07801234567', '@ali_hasan', 'ثانٍ', 'تلغرام']) {
      expect(find.descendant(of: _hero, matching: find.text(s)), findsOneWidget, reason: s);
    }
    expect(find.text('أرقام تواصل إضافيّة'), findsNothing, reason: 'الكرت المنفصل أُزيل');
    // الترتيب: الهاتف ثمّ الثاني ثمّ تلغرام (من الأعلى للأسفل).
    final y = [
      t.getCenter(find.text('9647765670141')).dy,
      t.getCenter(find.text('07801234567')).dy,
      t.getCenter(find.text('@ali_hasan')).dy,
    ];
    expect(y[0] < y[1] && y[1] < y[2], isTrue, reason: '$y');
    expect(t.takeException(), isNull);
    await close(t);
  });

  for (final w in [320.0, 360.0, 390.0, 480.0]) {
    for (final scale in [1.0, 1.2]) {
      testWidgets('لا قصّ ولا فيضان: عرض ${w.toInt()} × خطّ $scale (معرّفٌ طويل ورقمٌ دوليّ)', (t) async {
        contacts({'wa_phone2': '07801234567', 'tg_contact': '@ali_hasan_karbala_net'});
        await open(t, SimVariant(w, dark: scale > 1), scale: scale);
        expect(t.takeException(), isNull);
        for (final s in ['07801234567', '@ali_hasan_karbala_net']) {
          final f = find.descendant(of: _hero, matching: find.text(s));
          expect(f, findsOneWidget, reason: s);
          final text = t.widget<Text>(f);
          expect(text.overflow, isNot(TextOverflow.ellipsis), reason: 'القيمة لا تُقصّ — تصغر');
          // داخل حدود البطاقة أفقيّاً.
          final r = t.getRect(f);
          final hero = t.getRect(_hero);
          expect(r.left >= hero.left - 0.5 && r.right <= hero.right + 0.5, isTrue, reason: '$s $r خارج $hero');
        }
        await close(t);
      });
    }
  }

  testWidgets('رقمٌ ثانٍ وحده: سطره وحده (لا سطر تلغرام فارغ)؛ وتلغرامٌ رقماً ⇒ اتصال', (t) async {
    contacts({'wa_phone2': '07801234567'});
    await open(t, const SimVariant(390, dark: false));
    expect(find.descendant(of: _hero, matching: find.text('ثانٍ')), findsOneWidget);
    expect(find.descendant(of: _hero, matching: find.text('تلغرام')), findsNothing);
    final callsBefore = find.descendant(of: _hero, matching: find.byIcon(Icons.call_rounded)).evaluate().length;
    expect(callsBefore, 2, reason: 'الهاتف + الثاني');
    await close(t);

    contacts({'tg_contact': '9647801112223'});
    await open(t, const SimVariant(390, dark: false));
    expect(find.descendant(of: _hero, matching: find.text('تلغرام')), findsOneWidget);
    expect(find.descendant(of: _hero, matching: find.text('9647801112223')), findsOneWidget);
    expect(find.descendant(of: _hero, matching: find.byIcon(Icons.call_rounded)).evaluate().length, 2,
        reason: 'تلغرامٌ رقماً يُتّصل به');
    await close(t);
  });

  testWidgets('«نسخ كلّ المعلومات» يضمّها تحت الهاتف — الرقم محلّيّاً كالهاتف', (t) async {
    contacts({'wa_phone2': '07801234567', 'tg_contact': '@ali_hasan'});
    final clips = _mockClipboard(t);
    await open(t, const SimVariant(390, dark: false));
    await t.tap(find.byTooltip('copy.all'.tr()));
    await t.pump();
    final text = clips.last;
    final phone = text.indexOf('الهاتف: 07765670141');
    final wa2 = text.indexOf('واتساب ثانٍ: 07801234567');
    final tg = text.indexOf('تلغرام: @ali_hasan');
    expect(phone >= 0 && wa2 > phone && tg > wa2, isTrue, reason: text);
    await close(t);
  });

  testWidgets('المفتاح مطفأ: لا صفّ؛ و«كل الشركات» (الدفعة ب، ٢١ نوفمبر): أرقام المشترك من شركته', (t) async {
    contacts({'wa_phone2': '07801234567'}, enabled: false);
    await open(t, const SimVariant(390, dark: false));
    expect(find.text('07801234567'), findsNothing);
    expect(find.text('ثانٍ'), findsNothing);
    await close(t);

    server.requests.clear();
    server.echoCompanyKey = true;
    final prev = AccountApi.tokenSource;
    AccountApi.tokenSource = ({bool force = false}) async => 'acct';
    addTearDown(() => AccountApi.tokenSource = prev);
    contacts({'wa_phone2': '07801234567'});
    await open(t, const SimVariant(390, dark: false), sub: _sub(companyKey: 'c0000000000b2'));
    final g = server.calls('GET', SubscriberContactsApi.path);
    expect(g.length, 1);
    expect(g.single.headers['x-company-key'], 'c0000000000b2', reason: 'من شركة المشترك لا المفتوحة');
    expect(find.text('07801234567'), findsOneWidget, reason: 'الرقم الثاني بكرت مشترك الشركة الأخرى');
    expect(find.text('ثانٍ'), findsOneWidget);
    await close(t);
  });
}
