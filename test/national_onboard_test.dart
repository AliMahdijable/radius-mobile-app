import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_onboard_api.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/screens/national/national_onboard_screen.dart';
import 'package:rad_mysvcs/screens/national/national_work_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «إضافة مشترك» في التطبيق (٢ نوفمبر — نسخة الموقع WataniOnboardSheet؛ الخادم wataniOnboarding.js؛ المالك: «هي نفسها بالطلبات»):
/// القراءة والقواعد (صلاحية البطاقة ١٠ سنوات — سبب الإلغاء الحيّ — والتاريخ المكتوب كما على البطاقة)، ثمّ الصفحة: لا إرسال قبل
/// اكتمال الحقول، البطاقة المنتهية تُقال لحظة كتابة تاريخها، الجسم بالضبط كما يقرؤه الخادم، الطلب المكرّر بتأكيد، ورمز التأكيد.
const _v = SimVariant(390, dark: false);
const _base = '/api/v2/ftth/onboarding';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46, 0x49, 0x46]);

Map<String, Object?> _meta({int options = 1}) => {
      'success': true,
      'data': {
        'zones': [
          {'id': 'z-1', 'name': 'الزون الأوّل'},
          {'id': 'z-2', 'name': 'الزون الثاني'},
        ],
        'plans': [
          {'name': 'FIBER 35', 'title': 'فايبر 35', 'speed': '35 Mbps', 'price': 35000},
          {'name': 'FIBER 75', 'title': 'فايبر 75', 'speed': '75 Mbps', 'price': 50000},
        ],
        'install_options': [
          {'id': 'o-1', 'name': 'تركيب مجّانيّ', 'price': 0},
          if (options > 1) {'id': 'o-2', 'name': 'تركيب سريع', 'price': 25000},
        ],
        'contract_text': 'بنود العقد',
        'rules': {'card_years': 10, 'card_warn_days': 30},
      },
    };

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

/// الحقول بترتيبها في الصفحة.
const _fields = [
  'first', 'second', 'third', 'fourth', 'family', 'mobile', 'mFirst', 'mSecond', 'mThird', 'mFourth', //
  'idNumber', 'familyNumber', 'idPlace', 'idIssued', 'birthday', //
  'resNumber', 'resPlace', 'resIssued', //
  'address', 'neighbourhood', 'street', 'house', 'apartment',
];

Future<void> _type(WidgetTester t, String key, String text) async {
  final f = find.byType(TextField).at(_fields.indexOf(key));
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> _tapText(WidgetTester t, String text) async {
  final f = find.text(text).first;
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

const _valid = {
  'first': 'علي',
  'second': 'حسن',
  'third': 'كاظم',
  'family': 'الموسوي',
  'mobile': '٠٧٧٠١٢٣٤٥٦٧',
  'mFirst': 'زينب',
  'mSecond': 'جاسم',
  'mThird': 'محمد',
  'idNumber': '١٩٩٠١٢٣٤٥٦٧٨',
  'familyNumber': '1990ab12345',
  'idPlace': 'بغداد',
  'idIssued': '2019-05-10',
  'birthday': '15/1/1990',
  'resNumber': '445566',
  'resPlace': 'الكرخ',
  'resIssued': '٢٠٢٠-٠٢-٠٢',
  'address': 'قرب الجامع',
  'neighbourhood': '905',
  'street': '12',
  'house': '7/1',
};

void main() {
  group('القراءة والقواعد', () {
    test('المراجع والصلاحية والتاريخ المكتوب', () {
      final m = OnboardMeta.fromJson(Map<String, dynamic>.from(_meta(options: 2)['data'] as Map));
      expect((m.zones.length, m.plans.length, m.options.length, m.contract, m.cardYears, m.warnDays), (2, 2, 2, 'بنود العقد', 10, 30));
      expect((m.plans.first.name, m.plans.first.price, m.options.last.price), ('FIBER 35', 35000, 25000));

      final now = DateTime.utc(2026, 11, 2);
      final old = onboardCardExpiry(DateTime(2015, 3, 1), 10, now: now)!;
      expect((old.expired, old.on), (true, '2025-03-01'), reason: 'سبب الإلغاء الحيّ: مضت ١٠ سنوات');
      final ok = onboardCardExpiry(DateTime(2019, 5, 10), 10, now: now)!;
      expect((ok.expired, ok.on), (false, '2029-05-10'));
      expect(onboardCardExpiry(null, 10), isNull);

      final today = DateTime(2026, 11, 2);
      expect(parseOnboardDate('2018-03-21', now: today), DateTime(2018, 3, 21));
      expect(parseOnboardDate('21/3/2018', now: today), DateTime(2018, 3, 21));
      expect(parseOnboardDate('٢١/٣/٢٠١٨', now: today), DateTime(2018, 3, 21));
      expect(parseOnboardDate('2018-02-31', now: today), isNull, reason: 'يومٌ غير موجود');
      expect(parseOnboardDate('2027-01-01', now: today), isNull, reason: 'في المستقبل');
      expect(parseOnboardDate('18-3-21', now: today), isNull, reason: 'سنةٌ بلا أربعة أرقام');
      expect(parseOnboardDate('', now: today), isNull);
      expect(onboardLatin('٠٧٧٠۱۲۳ab'), '0770123ab');

      expect(onboardImageType(_jpeg), 'image/jpeg');
      expect(onboardImageType(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])), 'image/png');
      expect(onboardImageType(Uint8List.fromList([0x25, 0x50, 0x44, 0x46])), isNull, reason: 'PDF ليس صورة');

      expect(NationalBeta.fromJson({'beta': true, 'onboard': true}).onboard, isTrue);
      expect(NationalBeta.fromJson({'beta': true}).onboard, isFalse);
    });

    test('النتائج الأربع', () {
      final a = OnboardResult.of({'success': true, 'data': {'request_id': 'r-1', 'otp_sent_to': '•••4567'}});
      expect((a.state, a.requestId, a.sentTo), (OnboardState.applied, 'r-1', '•••4567'));
      expect(OnboardResult.of({'success': false, 'code': 'UNCONFIRMED', 'message': 'لم يتأكّد'}, status: 202).state, OnboardState.unconfirmed);
      expect(OnboardResult.of({'success': false, 'code': 'REPEATED', 'message': 'قبل قليل'}).state, OnboardState.repeated);
      final f = OnboardResult.of({'success': false, 'code': 'PORTAL_REJECTED', 'message': 'رفضت', 'portal_message': 'Invalid', 'field': 'mobile'});
      expect((f.state, f.message, f.field), (OnboardState.failed, 'رفضت — Invalid', 'mobile'));
      expect(OnboardResult.of('x').state, OnboardState.failed);
    });
  });

  group('الصفحة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      server.reply('GET', '$_base/meta', 200, _meta());
      for (final k in ['id_front', 'id_back', 'res_front', 'res_back', 'signature']) {
        server.reply('POST', '$_base/files?kind=$k', 200, {'success': true, 'data': {'id': 'f-$k', 'kind': k}});
      }
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    bool? got;
    Future<void> open(WidgetTester t) async {
      got = null;
      await pumpSim(
        t,
        _v,
        home: (_) => simLauncher((c) async => got = await Navigator.of(c).push<bool>(MaterialPageRoute(
              builder: (_) => NationalOnboardScreen(
                picker: (_, {required camera}) async => _jpeg,
                locate: (_) async => (lat: 33.3123456, lng: 44.3612345),
              ),
            ))),
      );
      await simOpen(t);
      await _settle(t);
    }

    Future<void> fillAll(WidgetTester t) async {
      for (final e in _valid.entries) {
        await _type(t, e.key, e.value);
      }
      for (final label in ['وجه البطاقة', 'ظهر البطاقة', 'وجه بطاقة السكن', 'ظهر بطاقة السكن']) {
        await _tapText(t, label);
      }
      await _tapText(t, 'اختر الزون');
      await _tapText(t, 'الزون الثاني');
      await _tapText(t, 'حدّد على الخريطة');
      await _tapText(t, 'اختر الباقة');
      await _tapText(t, 'فايبر 75 — 50,000');
      // التوقيع: خطٌّ داخل المربّع ⇒ يُرفع PNG
      final pad = find.byKey(const ValueKey('onboard-signature-pad'));
      await t.ensureVisible(pad);
      await t.pumpAndSettle();
      await t.drag(pad, const Offset(120, 30));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await _settle(t);
    }

    testWidgets('لا إرسال قبل اكتمال الحقول — والأخطاء بمكانها', (t) async {
      await open(t);
      expect(find.text('إضافة مشترك'), findsOneWidget);
      await t.tap(find.text('إرسال الطلب'));
      await _settle(t);
      expect(find.textContaining('أكمل الحقول المؤشَّرة بالأحمر'), findsOneWidget);
      expect(find.text('اكتب الاسم'), findsOneWidget);
      expect(server.calls('POST', _base), isEmpty);
      await simDrain(t);
    });

    testWidgets('البطاقة المنتهية تُقال لحظة كتابة تاريخها، ولا يُرسل شيء', (t) async {
      await open(t);
      await _type(t, 'idIssued', '2014-01-01');
      expect(find.textContaining('البطاقة منتهية (انتهت 2024-01-01)'), findsOneWidget, reason: 'قبل الضغط على إرسال');
      await t.tap(find.text('إرسال الطلب'));
      await _settle(t);
      expect(server.calls('POST', _base), isEmpty);
      expect(server.calls('POST', '$_base/validate-id'), isEmpty);
      await simDrain(t);
    });

    testWidgets('الطلب كاملاً بجسمٍ بالضبط ⇒ الرمز ⇒ تأكيده', (t) async {
      server.reply('POST', _base, 200, {'success': true, 'outcome': 'applied', 'data': {'request_id': 'r-77', 'otp_sent_to': '•••4567'}});
      server.reply('POST', '$_base/r-77/otp', 200, {'success': true, 'data': {'valid': true}});
      await open(t);
      await fillAll(t);
      expect(server.calls('POST', '$_base/files?kind=signature'), hasLength(1));
      expect(server.calls('POST', '$_base/files?kind=signature').single.headers['content-type'], 'image/png');
      expect(server.calls('POST', '$_base/files?kind=id_front').single.headers['content-type'], 'image/jpeg');
      await t.tap(find.text('إرسال الطلب'));
      await _settle(t);
      expect(server.bodies('POST', _base).single, {
        'name': {'first': 'علي', 'second': 'حسن', 'third': 'كاظم', 'fourth': '', 'family': 'الموسوي'},
        'mother': {'first': 'زينب', 'second': 'جاسم', 'third': 'محمد', 'fourth': ''},
        'mobile': '٠٧٧٠١٢٣٤٥٦٧',
        'national_id': {'id_number': '١٩٩٠١٢٣٤٥٦٧٨', 'family_number': '1990ab12345', 'place_of_issue': 'بغداد', 'issued_at': '2019-05-10', 'birthday': '1990-01-15'},
        'residence': {'card_number': '445566', 'place_of_issue': 'الكرخ', 'issued_at': '2020-02-02'},
        'site': {
          'lat': 33.3123456,
          'lng': 44.3612345,
          'address': 'قرب الجامع',
          'house': '7/1',
          'neighbourhood': '905',
          'street': '12',
          'apartment': '',
          'zone_id': 'z-2',
        },
        'plan_name': 'FIBER 75',
        'install_option_id': 'o-1',
        'files': {'id_front': 'f-id_front', 'id_back': 'f-id_back', 'res_front': 'f-res_front', 'res_back': 'f-res_back', 'signature': 'f-signature'},
      });
      expect(find.textContaining('أُرسل الطلب لبوّابة المشروع الوطني'), findsOneWidget);
      expect(find.textContaining('•••4567'), findsWidgets);
      await t.enterText(find.byType(TextField).first, '٤٥٦٧٨٩');
      await t.pump();
      await t.tap(find.text('تأكيد الرمز'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/r-77/otp').single, {'mobile': '٠٧٧٠١٢٣٤٥٦٧', 'otp': '456789'});
      expect(find.textContaining('الرمز صحيح'), findsOneWidget);
      await t.tap(find.byTooltip('رجوع'));
      await _settle(t);
      expect(got, isTrue, reason: 'تُعاد قراءة «الطلبات»');
      await simDrain(t);
    });

    testWidgets('طلبٌ لصاحب البطاقة نفسها قبل قليل ⇒ تأكيدٌ ثمّ confirmRepeat', (t) async {
      server.reply('POST', _base, 409, {'success': false, 'code': 'REPEATED', 'message': 'أُرسل طلبٌ لصاحب هذه البطاقة قبل قليل'});
      await open(t);
      await fillAll(t);
      await t.tap(find.text('إرسال الطلب'));
      await _settle(t);
      expect(find.text('طلبٌ آخر لصاحب البطاقة نفسها؟'), findsOneWidget);
      server.reply('POST', _base, 200, {'success': true, 'data': {'request_id': 'r-78', 'otp_sent_to': '•••4567'}});
      await t.tap(find.text('أرسله'));
      await _settle(t);
      final bodies = server.bodies('POST', _base);
      expect(bodies, hasLength(2));
      expect(bodies.first.containsKey('confirmRepeat'), isFalse);
      expect(bodies.last['confirmRepeat'], isTrue);
      expect(find.textContaining('أُرسل الطلب لبوّابة المشروع الوطني'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('لم يتأكّد الإرسال (202) ⇒ تُغلق الصفحة وتُعاد قراءة «الطلبات» بلا إعادة إرسال', (t) async {
      server.reply('POST', _base, 202, {'success': false, 'code': 'UNCONFIRMED', 'message': 'لم يتأكّد إرسال الطلب — افتح «الطلبات»'});
      await open(t);
      await fillAll(t);
      await t.tap(find.text('إرسال الطلب'));
      await _settle(t);
      expect(server.calls('POST', _base), hasLength(1));
      expect(got, isTrue);
      expect(find.text('إرسال الطلب'), findsNothing, reason: 'أُغلقت');
      await simDrain(t);
    });
  });

  group('الزرّ في «الطلبات»', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      NationalSheetApi.debugReset();
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      server.reply('GET', '/api/v2/ftth/lookups', 200, {
        'success': true,
        'data': {'beta': true, 'can_write': true, 'onboard': true},
      });
      server.reply('GET', '/api/v2/ftth/requests', 200, {'success': true, 'data': [], 'page': 1, 'size': 20, 'total': 0});
      server.reply('GET', '$_base/meta', 200, _meta());
    });
    tearDown(() {
      NationalSheetApi.debugReset();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    testWidgets('صاحب الحساب: «إضافة مشترك» يفتح الصفحة، ولا يظهر في «المهامّ»', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
      await _settle(t);
      final fab = find.widgetWithText(FloatingActionButton, 'إضافة مشترك');
      expect(fab, findsOneWidget);
      expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.userPlus)), findsOneWidget);
      await t.tap(fab);
      await _settle(t);
      expect(find.text('إرسال الطلب'), findsOneWidget);
      expect(server.calls('GET', '$_base/meta'), hasLength(1));
      await t.tap(find.byTooltip('رجوع'));
      await _settle(t);
      await t.tap(find.text('المهامّ'));
      await _settle(t);
      expect(find.widgetWithText(FloatingActionButton, 'إضافة مشترك'), findsNothing);
      await simDrain(t);
    });

    testWidgets('الموظّف: الزرّ بمكانه مقفلاً، والنقر لا يفتح شيئاً', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
      await _settle(t);
      final fab = find.widgetWithText(FloatingActionButton, 'إضافة مشترك');
      expect(fab, findsOneWidget);
      expect(find.descendant(of: fab, matching: find.byIcon(LucideIcons.lock)), findsOneWidget);
      await t.tap(fab);
      await _settle(t);
      expect(find.text('إرسال الطلب'), findsNothing);
      expect(server.calls('GET', '$_base/meta'), isEmpty);
      await t.pump(const Duration(seconds: 5));
      await simDrain(t);
    });

    testWidgets('مفتاحه مطفأ ⇒ لا زرّ', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      server.reply('GET', '/api/v2/ftth/lookups', 200, {
        'success': true,
        'data': {'beta': true, 'can_write': true, 'onboard': false},
      });
      await pumpSim(t, _v, home: (_) => const NationalWorkScreen());
      await _settle(t);
      expect(find.widgetWithText(FloatingActionButton, 'إضافة مشترك'), findsNothing);
      await simDrain(t);
    });
  });
}
