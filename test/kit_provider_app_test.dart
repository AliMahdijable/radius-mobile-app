import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports — لنصوص «قوائم أخرى» بلا ودجت (Localization.load وحده يملأ tr()).
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/package_change.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/consumption_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// «الشركات المُضافة» في التطبيق (providerKit بالخادم — نبض وAccessGate، ٣٠ أكتوبر؛ المالك: «…وكامل نبض واككس كيت»).
///
/// الخادم (f9611aa) يفتح دخول التطبيق خلف `pro_settings.<name>_app` ويخدمها بعقود SAS4 نفسها. ما يحرسه هنا: معرفتها
/// باسمها من الخادم، «يعمل من موقع الويب» رفضُ شركةٍ لا بوّابة حساب، ما لا يخدمه مزوّدها لا يظهر لصاحبها (قدراته false)،
/// مودل التفعيل بوضع «المزوّد» والباقة الأخرى «حالاً» وحدها، التمديد بالمدّة بلا كلفة (نبض)، و«الاستهلاك» مجاميعه لا أعمدة.
void main() {
  tearDown(() {
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  group('المعرفة والرفض والإخفاء', () {
    test('كلّ مزوّدٍ ليس من الأربعة شركةٌ مُضافة، واسمها من الخادم', () {
      for (final p in ['nabd', 'accessgate', 'newco']) {
        expect(ProviderService.isKitName(p), isTrue, reason: p);
      }
      for (final p in [null, '', 'sas4', 'earthlink', 'ftth', 'fiberx']) {
        expect(ProviderService.isKitName(p), isFalse, reason: '$p');
      }
      ProviderService.debugSet('nabd', label: 'نبض');
      expect([ProviderService.isKit, ProviderService.label], [true, 'نبض']);
      ProviderService.debugSet('nabd');
      expect(ProviderService.label, 'nabd', reason: 'بلا اسمٍ ⇒ رمزها');
      ProviderService.debugSet('fiberx');
      expect(ProviderService.isKit, isFalse);
    });

    test('«يعمل من موقع الويب» لأيّ مزوّد رفضُ شركةٍ لا بوّابة حساب', () {
      for (final c in ['nabd-web-only', 'accessgate-web-only', 'fiberx-web-only', 'ftth-web-only']) {
        final f = LoginFailure('x', code: c);
        expect([f.isWebOnly, f.isAccountGate], [true, false], reason: c);
      }
      expect(const LoginFailure('x', code: 'subscription-ended').isAccountGate, isTrue);
      expect(const LoginFailure('x', code: 'company-limit').isWebOnly, isFalse);
    });

    test('ما لا يخدمه مزوّد الشركة (قدرته false) لا يظهر لصاحبها؛ ما يخدمه يظهر؛ وغيرها لا يمسّه', () {
      ProviderService.debugSet('nabd', label: 'نبض');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: {
        'subscribers.view': true,
        'subscribers.activate': true,
        'subscribers.extend': true,
        'subscribers.delete': false,
        'subscribers.edit_location': false,
        'reports.sessions': false,
        'whatsapp.send': true,
      });
      expect(sessionIsKit, isTrue);
      for (final k in ['subscribers.delete', 'subscribers.edit_location', 'reports.sessions']) {
        expect(providerHidesAction(k), isTrue, reason: k);
      }
      for (final k in ['subscribers.activate', 'subscribers.extend', 'whatsapp.send', 'subscribers.view']) {
        expect(providerHidesAction(k), isFalse, reason: k);
      }
      // SAS4 بالخريطة نفسها: القفل بالصلاحيّة كما كان، لا إخفاء
      ProviderService.debugSet(null);
      expect(providerHidesAction('subscribers.delete'), isFalse);
    });

    test('«قوائم أخرى»: الموظّفون مفتوحون (موظّفونا — 03cc682)، والمدراء بلا قدرة المحوّل بمكانهم مقفلين بسببٍ يسمّي الشركة', () async {
      await _loadTranslations();
      ProviderService.debugSet('nabd', label: 'نبض');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: {
        'managers.view': false,
        'employees.view': true,
      });
      final mods = {for (final m in buildAppModules()) m.id: m};
      expect([mods['employees']?.unavailable, mods['employees']?.isLocked], [null, false]);
      expect(mods['managers']?.unavailable, 'غير متاح لحساب نبض بعد');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: {'managers.view': true});
      expect({for (final m in buildAppModules()) m.id: m}['managers']?.unavailable, isNull, reason: 'نبض بمدرائه');
    });

    test('«كل الشركات»: المزوّد kit يُقرأ شركةً مُضافة (لا SAS4)، تدخل الدمج حين يقول الخادم ok، ومفتاحها المغلق ⇒ خارجه بسببه', () {
      final cs = MergedCompany.listFrom([
        {'key': 'c111111111111', 'code': 'nabd', 'provider': 'kit', 'status': 'ok', 'admin_id': 'nabd:myservices'},
        {'key': 'c222222222222', 'code': 'accessgate', 'provider': 'kit', 'status': 'unavailable', 'reason': 'kit_web_only',
          'message': 'حساب هذه الشركة يعمل من موقع الويب حالياً — قريباً في التطبيق'},
        {'key': 'c333333333333', 'code': 'jt', 'provider': 'sas4', 'status': 'ok'},
      ]);
      expect(cs.map((c) => c.provider), [MergedProvider.kit, MergedProvider.kit, MergedProvider.sas4]);
      expect([cs[0].appCapable, cs[0].usable, cs[0].currency], [true, true, 'IQD']);
      expect([cs[1].usable, cs[1].reason], [false, 'kit_web_only']);
    });

    test('موظّف الشركة المُضافة: مفاتيحها (المشتركون كاملاً + الحسابات الفرعيّة) لا مفاتيح فايبر اكس، وتوضيحها باسمها', () {
      ProviderService.debugSet('nabd', label: 'نبض');
      final k = ElEmployeePerms.keys;
      for (final on in ['subscribers.add', 'subscribers.edit', 'subscribers.delete', 'subscribers.toggle', 'managers.view', 'managers.deposit']) {
        expect(k.contains(on), isTrue, reason: on);
      }
      for (final off in ['subscribers.edit_location', 'reports.sessions', 'reports.manager_debts', 'employees.manage']) {
        expect(k.contains(off), isFalse, reason: off);
      }
      expect(ElEmployeePerms.hintFor('managers.view'), 'الحسابات الفرعيّة عند الشركة (المدراء) وأرصدتها');
      expect(ElEmployeePerms.hintFor('subscribers.add'), 'مشتركٌ جديد عند الشركة بحسابك فيها', reason: 'لا نصّ ايرث لنك (باسورد الإيداع/الكارت)');
      // صاحب حساب AccessGate (بلا حساباتٍ فرعيّة): محرّره بلا مفاتيح «المدراء» — لا يُمنح ما لا يخدمه حسابه
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: {
        'managers.view': false, 'managers.add': false, 'managers.deposit': false, 'subscribers.add': true, 'subscribers.view': true,
      });
      final owner = ElEmployeePerms.keys;
      expect(owner.contains('managers.view') || owner.contains('managers.deposit'), isFalse);
      expect(owner.contains('subscribers.add') && owner.contains('sales.view'), isTrue, reason: 'الغائب من القدرات = ميزةٌ عندنا');
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      expect(ElEmployeePerms.keys.contains('managers.view'), isTrue, reason: 'موظّفها: مفاتيحها كلّها (الخادم يعرض ∩ القدرات)');
      PermissionsService.debugReset();
      ProviderService.debugSet('fiberx');
      expect(ElEmployeePerms.keys.contains('subscribers.add'), isFalse, reason: 'فايبر اكس كما كان');
    });

    test('activation-data: schedule_supported:false صريحةً ⇒ لا جدولة؛ غيابها (SAS4) ⇒ كما كان', () {
      final kit = PackageChangeInfo.fromActivationData({
        'profile_id': 32,
        'subscription_active': true,
        'immediate_keeps_date': true,
        'schedule_supported': false,
        'profile_change': null,
      });
      expect([kit.supported, kit.scheduleSupported, kit.immediateKeepsDate], [true, false, true]);
      expect(kit.withoutScheduled().scheduleSupported, isFalse);
      final sas = PackageChangeInfo.fromActivationData({'subscription_active': true, 'immediate_keeps_date': false});
      expect(sas.scheduleSupported, isNull);
    });
  });

  group('الشيتات', () {
    late _Server server;

    setUpAll(() async {
      await loadAppFonts();
      WidgetController.hitTestWarningShouldBeFatal = true;
    });

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      server = _Server();
      ApiClient.dio.httpClientAdapter = server;
      CardsState.reset();
      ProviderService.debugSet('nabd', label: 'نبض');
    });

    test('«مشترك جديد»: بلا مديرٍ رقميّ (معرّف الشركة نصّيّ) يُرسَل بلا parent_id ويُنشأ تحت حسابها؛ ومع مديرٍ مختار كما كان', () async {
      final a = await SubscribersApi.createSubscriber(username: 'kt1', password: 'x1', profileId: 32, parentId: null);
      final b = await SubscribersApi.createSubscriber(username: 'kt2', password: 'x2', profileId: 32, parentId: 7);
      expect([a.ok, b.ok], [true, true]);
      final sent = server.bodies('/api/v2/subscribers');
      expect(sent, hasLength(2));
      expect(sent[0].containsKey('parent_id'), isFalse, reason: 'الخادم: بلا parent_id ⇒ حساب الجلسة');
      expect(sent[1]['parent_id'], 7);
      // النموذج لا يقف عند «تعذّر تحديد المدير الأصلي» للشركة المُضافة وحدها
      final sheet = File('lib/screens/subscribers/sheets/add_subscriber_sheet.dart').readAsStringSync();
      expect(sheet.contains('if (parentId == null && !ProviderService.isKit) {'), isTrue);
    });

    final sub = Subscriber.fromJson({
      'idx': '746',
      'username': 'nbu',
      'firstname': 'علي',
      'profile_id': 32,
      'profile_name': 'MyServices Test',
    });

    Future<void> open(WidgetTester t, Future<void> Function(BuildContext) show) async {
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        saveLocale: false,
        assetLoader: const _DiskLoader(),
        child: Builder(
          builder: (ctx) => MaterialApp(
            locale: ctx.locale,
            supportedLocales: ctx.supportedLocales,
            localizationsDelegates: ctx.localizationDelegates,
            home: Scaffold(
              body: Builder(
                builder: (c) => Center(child: TextButton(onPressed: () => show(c), child: const Text('open'))),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    Future<void> tapText(WidgetTester t, String text) async {
      final f = find.text(text);
      await t.ensureVisible(f.last);
      await t.pumpAndSettle();
      await t.tap(f.last);
      await t.pumpAndSettle();
    }

    Future<void> drain(WidgetTester t) async {
      await t.pump(const Duration(seconds: 9));
      await t.pumpAndSettle();
    }

    testWidgets('التفعيل بوضع المزوّد: كلفته باسم الشركة، والباقة الأخرى «حالاً» بلا سؤال ⇒ profile_id + change_type now', (t) async {
      await open(t, (c) => showActivateSheet(c, sub));
      expect(find.text('كلفة الباقة عند نبض'), findsOneWidget);
      expect(find.text('متى تبدأ الباقة الجديدة؟'), findsNothing);
      final picker = find.byType(PackagePickerField);
      await t.ensureVisible(picker);
      await t.pumpAndSettle();
      await t.tap(picker);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Fast').last);
      await t.pumpAndSettle();
      expect(find.text('متى تبدأ الباقة الجديدة؟'), findsNothing, reason: 'لا «عند الانتهاء» عند نبض');
      expect(find.textContaining('الباقة الأخرى تُفعَّل حالاً'), findsOneWidget);
      await tapText(t, 'تجديد الآن');
      final b = server.bodies('/activate').single;
      expect([b['profile_id'], b['change_type'], b['paymentType']], [33, 'now', 'non-cash']);
      await drain(t);
    });

    testWidgets('تمديد نبض بالمدّة: بلا كلفة ولا طريقة دفع، والزرّ يعمل ⇒ profile_id = الأيّام + method balance', (t) async {
      await open(t, (c) => showExtendSheet(c, sub));
      expect(find.text('مدّة التمديد'), findsOneWidget);
      expect(find.text('sheets.payment_method'.tr()), findsNothing);
      expect(find.text('بلا كلفة'), findsOneWidget);
      expect(find.textContaining('0 د.ع'), findsNothing, reason: '«0 د.ع» تضلّل');
      await t.tap(find.text('تمديد يومين — بلا كلفة'));
      await t.pumpAndSettle();
      await tapText(t, 'تمديد الآن');
      final b = server.bodies('/extend').single;
      expect([b['profile_id'], b['method']], ['2', 'balance']);
      await drain(t);
    });

    testWidgets('«الاستهلاك» للشركة المُضافة: مجاميع الشهر واليوم وأمس — لا «يوميّ/شهريّ» ولا «لا استهلاك»', (t) async {
      await open(t, (c) => showConsumptionSheet(c, sub));
      expect(server.paths.where((p) => p.endsWith('/traffic')), isEmpty, reason: 'لا تفصيل يوميّ عند مزوّدها');
      expect(find.text('يوميّ'), findsNothing);
      expect(find.text('هذا الشهر'), findsOneWidget);
      expect(find.text('اليوم'), findsOneWidget);
      expect(find.text('أمس'), findsOneWidget);
      expect(find.textContaining('التفصيل اليوميّ غير متاح عند نبض'), findsOneWidget);
      expect(find.text('لا استهلاك مسجَّل في هذه المدّة'), findsNothing);
      final q = server.queries.lastWhere((q) => q.path == '/api/v2/subscribers-usage');
      expect(q.queryParameters['ids'], '746');
      expect(q.queryParameters['month'], matches(RegExp(r'^\d{4}-\d{2}$')));
    });
  });
}

Future<void> _loadTranslations() async {
  final ar = jsonDecode(File('assets/translations/ar.json').readAsStringSync()) as Map<String, dynamic>;
  Localization.load(const Locale('ar'), translations: Translations(ar));
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>);
}

class _Server implements HttpClientAdapter {
  final _requests = <RequestOptions>[];

  Iterable<String> get paths => _requests.map((r) => r.path);
  Iterable<RequestOptions> get queries => _requests;

  List<Map<String, dynamic>> bodies(String suffix) => _requests
      .where((r) => r.path.endsWith(suffix))
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _requests.add(options);
    final (int, Map<String, dynamic>) reply;
    switch (options.path) {
      case '/api/v2/subscribers/746/activation-data':
        reply = (200, {
          'success': true,
          'data': {
            'provider': 'nabd',
            'provider_label': 'نبض',
            'idx': '746',
            'username': 'nbu',
            'profile_name': 'MyServices Test',
            'profile_id': 32,
            'user_price': 1000,
            'base_price': 1000,
            'price_after_discount': 1000,
            'discount_amount': 0,
            'price_source': 'sell_price',
            'custom_price': null,
            'overridden_discount': 0,
            'needs_repricing': false,
            'current_balance': 0,
            'manager_balance': 250000,
            'packages': [
              {'id': 32, 'name': 'MyServices Test', 'price': 1000, 'cost': 500, 'days': 30},
              {'id': 33, 'name': 'Fast', 'price': 25000, 'cost': 20000, 'days': 30},
            ],
            'package_change_allowed': true,
            'package_change_timing': ['now'],
            'subscription_active': true,
            'can_change_profile': true,
            'can_change_profile_active': true,
            'immediate_keeps_date': true,
            'schedule_supported': false,
            'profile_change': null,
          },
        });
      case '/api/v2/subscribers/746/activate':
      case '/api/v2/subscribers/746/extend':
        reply = (200, {'success': true});
      case '/api/v2/subscribers/746/extension-options':
        reply = (200, {
          'success': true,
          'data': {
            'provider': 'nabd',
            'provider_label': 'نبض',
            'mode': 'days',
            'current_profile_id': 32,
            'current_profile_name': 'MyServices Test',
            'manager_balance': 250000,
            'reward_points_balance': 0,
            'packages': [
              {'id': 1, 'name': 'تمديد يوم — بلا كلفة', 'price': 0, 'reward_points_required': 0, 'duration': 'يوم'},
              {'id': 2, 'name': 'تمديد يومين — بلا كلفة', 'price': 0, 'reward_points_required': 0, 'duration': 'يومان'},
              {'id': 3, 'name': 'تمديد ثلاثة أيّام — بلا كلفة', 'price': 0, 'reward_points_required': 0, 'duration': 'ثلاثة أيّام'},
            ],
          },
        });
      case '/api/v2/subscribers':
        reply = (200, {'success': true, 'message': 'تمّ'});
      case '/api/v2/subscribers-usage':
        reply = (200, {
          'success': true,
          'data': {
            '746': {'today': 1500000000, 'month': 36000000000, 'yesterday': 2000000000},
          },
          'errors': {},
        });
      default:
        reply = (404, {'success': false});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
