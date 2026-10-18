import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/package_change.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edit_subscriber_sheet.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

/// تغيير الباقة «حالاً / عند انتهاء الاشتراك» — قرار المالك ١٨ أكتوبر (SAS4 كلّها، لا ايرث لنك).
///
/// العقد مع الخادم (activation-data + PUT /api/v2/subscribers/:idx + cancel-profile-change):
/// - activation-data: `subscription_active` · `profile_change` · `can_change_profile_active` ·
///   `immediate_keeps_date` (خادمٌ أقدم بلاها ⇒ القاعدة السابقة، فلا جدولةٌ تصير تغييراً فوريّاً).
/// - PUT: `change_type` للفعّال وحده؛ «حالاً» بلا تعديل التاريخ لا يُرسل التاريخ الأصليّ (الخادم
///   يُبقي تاريخ سوبرنت بنفسه)؛ الردّ `change_type` المنفَّذ و`expiration_kept`.
/// - الرفض `PACKAGE_CHANGE_ACTIVE_FORBIDDEN` يقفل الحقل بسببه.
const _idx = '216523';
const _putPath = '/api/v2/subscribers/$_idx';
const _adPath = '/api/v2/subscribers/$_idx/activation-data';
const _cancelPath = '/api/v2/subscribers/$_idx/cancel-profile-change';

String _sasTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

String _day(DateTime d) => _sasTime(d).substring(0, 10);

/// الانتهاء بعد شهرٍ تقريباً، بثوانٍ صفر كما يحفظها الساس.
final _activeExp = DateTime(DateTime.now().year, DateTime.now().month,
        DateTime.now().day, 14, 42, 31)
    .add(const Duration(days: 29));
final _expiredExp = DateTime.now().subtract(const Duration(days: 3));

Subscriber _sub(DateTime exp) => Subscriber.fromJson({
      'idx': _idx,
      'username': 'a1@ze',
      'firstname': 'علي',
      'lastname': 'زيد',
      'phone': '07701234567',
      'profile_name': 'Economy',
      'profile_id': 9,
      'expiration': _sasTime(exp),
      'enabled': 1,
    });

void main() {
  // ═══════════════════════════ القواعد الصافية ═══════════════════════════
  group('القواعد', () {
    test('«متى؟» يُعرض للفعّال في SAS4 مع خادمٍ يعرفها وحده', () {
      bool offers({
        bool changes = true,
        bool active = true,
        bool el = false,
        bool supported = true,
      }) =>
          offersPackageChangeTiming(
            changesPackage: changes,
            active: active,
            isEarthlink: el,
            timingSupported: supported,
          );
      expect(offers(), isTrue);
      expect(offers(active: false), isFalse, reason: 'غير الفعّال «حالاً» وحدها');
      expect(offers(el: true), isFalse, reason: 'ايرث لنك على canChangeAccount');
      expect(offers(supported: false), isFalse,
          reason: 'خادمٌ أقدم يتجاهل change_type فتصير الجدولة فوريّة');
      expect(offers(changes: false), isFalse);
    });

    test('التاريخ: ما عدّله المدير — والأصليّ مع الباقة أمام خادمٍ أقدم وحده (الكلاسيك)', () {
      bool sends({
        bool can = true,
        bool has = true,
        bool edited = false,
        bool pkg = true,
        bool legacy = false,
      }) =>
          sendsExpiration(
            canEditExpiration: can,
            hasExpiration: has,
            expirationEdited: edited,
            changesPackage: pkg,
            legacyServer: legacy,
          );
      expect(sends(), isFalse,
          reason: 'الخادم يُبقي تاريخ سوبرنت بنفسه، ونسخةٌ قديمة قد تُرجع تاريخاً مُدِّد');
      expect(sends(edited: true), isTrue);
      expect(sends(edited: true, pkg: false), isTrue);
      expect(sends(legacy: true), isTrue,
          reason: 'خادمٌ أقدم: الأصليّ يُرسَل فيعيده بعد أن يصفّره الساس');
      expect(sends(legacy: true, pkg: false), isFalse,
          reason: 'بلا تغيير باقة لا حاجة له — ولا نسخةٌ قديمة تُعاد');
      expect(sends(can: false, edited: true), isFalse, reason: 'لا يملك التاريخ');
      expect(sends(can: false, legacy: true), isFalse);
      expect(sends(has: false, legacy: true), isFalse);
    });

    test('قيمة change_type كما يقرؤها الخادم', () {
      expect(PackageChangeTiming.immediate.wire, 'immediate');
      expect(PackageChangeTiming.schedule.wire, 'schedule');
    });

    test('activation-data: الحقول الجديدة، وخادمٌ أقدم بلاها', () {
      final none = PackageChangeInfo.fromActivationData(null);
      expect(none.supported, isFalse);
      final old = PackageChangeInfo.fromActivationData(
          {'expiration': '2026-11-16 14:42:31', 'profile_id': 9});
      expect(old.supported, isFalse);
      expect(old.scheduled, isNull);

      final info = PackageChangeInfo.fromActivationData({
        'subscription_active': true,
        'profile_change': {
          'profile_id': 10,
          'profile_name': 'Plus',
          'due_date': '2026-11-16 14:42:31',
        },
        'can_change_profile_active': null,
        'immediate_keeps_date': false,
      });
      expect(info.supported, isTrue);
      expect(info.active, isTrue);
      expect(info.profileId, isNull, reason: 'لم تُرسَل');
      expect(
          PackageChangeInfo.fromActivationData({'profile_id': '10'}).profileId,
          10,
          reason: 'الباقة الآن من الساس');
      expect(info.canChangeProfile, isNull, reason: 'لم يرسلها هنا');
      expect(info.canChangeActive, isNull, reason: 'لا نعرف ⇒ يحكم الساس');
      expect(info.immediateKeepsDate, isFalse);
      expect(info.scheduled?.profileId, 10);
      expect(info.scheduled?.profileName, 'Plus');
      expect(info.scheduled?.dueDay, '2026-11-16');
      expect(info.withoutScheduled().scheduled, isNull);
      expect(info.withoutScheduled().supported, isTrue);
    });

    test('المجدول: «لا شيء» بأشكال الساس كلّها، والحدّ الأدنى باقةٌ معروفة', () {
      for (final raw in <Object?>[null, false, const [], 'null', 0]) {
        expect(ScheduledPackageChange.tryParse(raw), isNull, reason: '$raw');
      }
      expect(ScheduledPackageChange.tryParse({'profile_id': 0}), isNull);
      expect(ScheduledPackageChange.tryParse({'due_date': '2026-11-16'}), isNull);
      final byId = ScheduledPackageChange.tryParse({'profile_id': '11'});
      expect(byId?.profileId, 11);
      expect(byId?.profileName, '');
      expect(byId?.dueDay, '');
      final raw = ScheduledPackageChange.tryParse(
          {'profileName': 'Gold', 'dueDate': 'قريباً'});
      expect(raw?.profileName, 'Gold');
      expect(raw?.dueDay, 'قريباً', reason: 'موعدٌ لا يُفهم يُعرض كما جاء');
    });
  });

  // ═══════════════════════════ الشيت ═══════════════════════════
  group('شيت التعديل', () {
    late SimServer server;

    setUpAll(simSetUpAll);

    /// جلسة SAS4: سوبرنت (المعرّف العاري) أو شركةٌ بعيدة (`<code>:12`).
    Future<void> session({
      String code = 'supernet',
      bool employee = false,
      bool restricted = false,
      Map<String, bool> caps = const {},
      bool dateCapable = true,
    }) async {
      final home = code == ActiveCompany.homeSasCode;
      final adminId = home ? '12' : '$code:12';
      FlutterSecureStorage.setMockInitialValues({
        'auth.token': 'test-token',
        'auth.admin_id': adminId,
        'auth.admin_username': 'admin@poox',
        if (employee) 'auth.is_employee': '1',
        'auth.can_access_managers': dateCapable ? '1' : '0',
        'auth.can_access_packages': dateCapable ? '1' : '0',
      });
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      PermissionsService.debugSet(
        isEmployee: employee,
        permissions: const {'subscribers.view': true, 'subscribers.edit': true},
        managerRestricted: restricted,
        managerCaps: caps,
      );
      ProviderService.debugSet(null);
      SubscribersApi.clearAllCaches();
      await ActiveCompany.saveFromLogin(
        sasUrl: home ? 'https://reseller-supernet.net' : 'https://sas.jt.iq',
        adminId: adminId,
        loginUsername: employee ? 'ali.m' : 'admin@poox',
        adminUsername: 'admin@poox',
        isEmployee: employee,
        label: home ? 'سوبرنت' : 'جي تي',
        sasCode: code,
      );
      server = SimServer();
      ApiClient.dio.httpClientAdapter = server;
      server.reply('GET', '/api/v2/packages', 200, {
        'success': true,
        'data': const [
          {'id': 9, 'name': 'Economy', 'price': 25000},
          {'id': 10, 'name': 'Plus', 'price': 35000},
          {'id': 11, 'name': 'Gold', 'price': 45000},
        ],
      });
      server.reply('GET', '/api/v2/managers', 200, {
        'success': true,
        'data': const [
          {'id': 12, 'username': 'admin@poox', 'firstname': '', 'lastname': ''},
        ],
      });
      server.reply('GET', '/api/v2/subscribers/$_idx/password', 200, {
        'success': true,
        'data': {'password': '1234'},
      });
      server.on('PUT', _putPath, (req) {
        final body = Map<String, dynamic>.from(req.data as Map);
        final type = body['change_type'] ?? (body.containsKey('profile_id') ? 'immediate' : null);
        return SimReply(200, {
          'success': true,
          'data': {
            'idx': _idx,
            'changes': ['profile → ${body['profile_id']}'],
            'change_type': type,
            'expiration_kept': null,
          },
        });
      });
    }

    tearDown(() async {
      await ActiveCompany.clear();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
      SubscribersApi.clearAllCaches();
      ApiClient.dio.httpClientAdapter = HttpClientAdapter();
    });

    void activationData({
      DateTime? exp,
      bool newServer = true,
      bool? active = true,
      Object? pending,
      bool? canActive = true,
      bool? keepsDate = false,
      int profileId = 9,
    }) {
      final e = exp ?? _activeExp;
      server.reply('GET', _adPath, 200, {
        'success': true,
        'data': {
          'idx': _idx,
          'username': 'a1@ze',
          'profile_id': profileId,
          'profile_name': profileId == 9 ? 'Economy' : 'Plus',
          'parent_id': 12,
          'expiration': _sasTime(e),
          if (newServer) ...{
            'subscription_active': active,
            'profile_change': pending,
            'can_change_profile_active': canActive,
            'immediate_keeps_date': keepsDate,
          },
        },
      });
    }

    Future<void> open(WidgetTester t, {DateTime? exp, double width = 390, bool dark = false}) async {
      await pumpSim(t, SimVariant(width, dark: dark),
          home: (_) => simLauncher(
              (c) => showEditSubscriberSheet(c, _sub(exp ?? _activeExp))));
      await simOpen(t);
      expect(find.text('تعديل المشترك'), findsOneWidget);
    }

    Finder packageDropdown() => find.byType(DropdownButton<int>).first;

    Future<void> pick(WidgetTester t, String name) async {
      await t.ensureVisible(packageDropdown());
      await t.pumpAndSettle();
      await t.tap(packageDropdown());
      await t.pumpAndSettle();
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
    }

    Future<void> tapText(WidgetTester t, String text) async {
      final f = find.text(text);
      await t.ensureVisible(f.last);
      await t.pumpAndSettle();
      await t.tap(f.last);
      await t.pumpAndSettle();
    }

    Future<void> save(WidgetTester t) => tapText(t, 'حفظ التغييرات');

    List<Map<String, dynamic>> puts() => server.bodies('PUT', _putPath);

    /// «حالاً» أو «عند انتهاء الاشتراك» مختار؟ (Semantics.selected على الخيار)
    bool selected(WidgetTester t, String label) {
      final wire = label == 'حالاً' ? 'immediate' : 'schedule';
      final sem = t.widget<Semantics>(find.byKey(ValueKey('pkg-timing-$wire')));
      expect(find.descendant(of: find.byKey(ValueKey('pkg-timing-$wire')), matching: find.text(label)),
          findsOneWidget);
      return sem.properties.selected == true;
    }

    testWidgets(
        '🚨 سوبرنت: «عند انتهاء الاشتراك» افتراضاً، و«حالاً» يُبقي التاريخ بحكم الخادم — بلا تأكيد',
        (t) async {
      await session();
      activationData(keepsDate: true);
      server.on('PUT', _putPath, (req) => const SimReply(200, {
            'success': true,
            'data': {'idx': _idx, 'change_type': 'immediate', 'expiration_kept': true},
          }));
      await open(t);
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing,
          reason: 'لا سؤال قبل تغيير الباقة');
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsOneWidget);
      expect(selected(t, 'عند انتهاء الاشتراك'), isTrue,
          reason: 'افتراض الساس والويب: لا يلغي شيئاً ولا يغيّر شيئاً الآن');
      expect(selected(t, 'حالاً'), isFalse);
      await tapText(t, 'حالاً');
      expect(selected(t, 'حالاً'), isTrue);
      expect(find.textContaining('ويبقى تاريخ الانتهاء كما هو'), findsOneWidget);
      expect(find.textContaining('سيُعتبر المشترك منتهياً'), findsNothing);
      await save(t);
      expect(find.text('تغيير الباقة الآن؟'), findsNothing, reason: 'لا شيء يضيع');
      final body = puts().single;
      expect(body['profile_id'], 10);
      expect(body['change_type'], 'immediate');
      expect(body.containsKey('expiration'), isFalse,
          reason: 'الخادم يعيد التاريخ الأصليّ بنفسه — لا يُرسَل خفيةً');
      expect(simText('تغيّرت الباقة Plus — وبقي تاريخ الانتهاء كما هو'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('سوبرنت: «عند انتهاء الاشتراك» تُجدوَل، والرسالة بموعد الساس', (t) async {
      await session();
      activationData(keepsDate: true);
      final due = _activeExp.add(const Duration(minutes: 1));
      server.on('PUT', _putPath, (req) => SimReply(200, {
            'success': true,
            'data': {
              'idx': _idx,
              'changes': const ['profile → 10 (عند انتهاء الاشتراك)'],
              'change_type': 'schedule',
              'expiration_kept': null,
              'updated': {
                'idx': _idx,
                'profile_change': {
                  'profile_id': 10,
                  'profile_name': 'Plus',
                  'due_date': _sasTime(due),
                },
              },
            },
          }));
      await open(t);
      await pick(t, 'Plus');
      expect(selected(t, 'عند انتهاء الاشتراك'), isTrue);
      expect(find.textContaining('يكمل المشترك اشتراكه الحاليّ'), findsOneWidget);
      await save(t);
      final body = puts().single;
      expect(body['change_type'], 'schedule');
      expect(body['profile_id'], 10);
      expect(body.containsKey('expiration'), isFalse,
          reason: 'الجدولة لا تمسّ التاريخ — ولا نسخةٌ قديمة تُرسَل');
      expect(
          simText('جُدولت الباقة Plus — تتغيّر عند انتهاء الاشتراك (${_day(due)})'),
          findsOneWidget);
      await simDrain(t);
    });

    testWidgets('خادمٌ يعرف «متى؟»: تعديلٌ بلا باقة لا يحمل التاريخ (لا نسخةٌ قديمة تُعاد)',
        (t) async {
      await session();
      activationData();
      await open(t);
      final phone = find.widgetWithText(TextField, '07701234567');
      await t.ensureVisible(phone);
      await t.enterText(phone, '07709999999');
      await t.pumpAndSettle();
      await save(t);
      final body = puts().single;
      expect(body['phone'], '07709999999');
      expect(body.containsKey('expiration'), isFalse);
      expect(body.containsKey('change_type'), isFalse);
      await simDrain(t);
    });

    testWidgets(
        '🚨 شركةٌ بعيدة: الجدولة افتراضاً، و«حالاً» يحذّر «سيُعتبر منتهياً» ويطلب تأكيداً',
        (t) async {
      await session(code: 'jt');
      activationData(keepsDate: false);
      server.on('PUT', _putPath, (req) => const SimReply(200, {
            'success': true,
            'data': {'idx': _idx, 'change_type': 'immediate', 'expiration_kept': false},
          }));
      await open(t);
      await pick(t, 'Plus');
      expect(selected(t, 'عند انتهاء الاشتراك'), isTrue,
          reason: '«حالاً» هنا يلغي الاشتراك — فالآمن افتراضاً');
      await tapText(t, 'حالاً');
      expect(find.textContaining('سيُعتبر المشترك منتهياً'), findsOneWidget);
      // تراجع: لا طلب.
      await save(t);
      expect(find.text('تغيير الباقة الآن؟'), findsOneWidget);
      await tapText(t, 'تراجع');
      expect(puts(), isEmpty);
      // تأكيد: «حالاً» بلا تاريخ.
      await save(t);
      await tapText(t, 'غيّرها الآن');
      final body = puts().single;
      expect(body['change_type'], 'immediate');
      expect(body.containsKey('expiration'), isFalse,
          reason: 'لا يُعاد التاريخ خفيةً خارج سوبرنت');
      expect(find.textContaining('والمشترك منتهٍ الآن'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('سوبرنت بلا صلاحيّة تعديل التاريخ: «حالاً» يحذّر كغيره', (t) async {
      await session(dateCapable: false);
      activationData(keepsDate: false);
      await open(t);
      await pick(t, 'Gold');
      expect(selected(t, 'عند انتهاء الاشتراك'), isTrue);
      await tapText(t, 'حالاً');
      expect(find.textContaining('سيُعتبر المشترك منتهياً'), findsOneWidget);
      await save(t);
      await tapText(t, 'غيّرها الآن');
      final body = puts().single;
      expect(body['change_type'], 'immediate');
      expect(body['profile_id'], 11);
      expect(body.containsKey('expiration'), isFalse);
      await simDrain(t);
    });

    testWidgets('غير الفعّال: «حالاً» وحدها بلا سؤال ولا change_type', (t) async {
      await session();
      activationData(exp: _expiredExp, active: false);
      await open(t, exp: _expiredExp);
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing);
      expect(find.text('المشترك غير فعّال — تتغيّر الباقة حالاً'), findsOneWidget);
      await save(t);
      final body = puts().single;
      expect(body['profile_id'], 10);
      expect(body.containsKey('change_type'), isFalse);
      await simDrain(t);
    });

    testWidgets('الساس يقول «منتهٍ» ولو بقي تاريخٌ (status.expiration) — بلا سؤال',
        (t) async {
      await session();
      activationData(active: false);
      await open(t);
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing);
      await simDrain(t);
    });

    testWidgets('🚨 بلا صلاحيّة تغيير باقة الفعّال: الحقل مقفلٌ بسببه ولا طلب', (t) async {
      await session(code: 'jt');
      activationData(canActive: false);
      await open(t);
      final dd = t.widget<DropdownButton<int>>(packageDropdown());
      expect(dd.onChanged, isNull, reason: 'مقفل');
      expect(find.textContaining('صلاحيّتك في الساس لا تسمح بتغيير باقته'),
          findsOneWidget);
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing);
      expect(puts(), isEmpty);
      await simDrain(t);
    });

    testWidgets('الخادم يقول لا صلاحيّة لتغيير أيّ باقة: مقفلٌ ولو لغير الفعّال', (t) async {
      await session(code: 'jt');
      server.reply('GET', _adPath, 200, {
        'success': true,
        'data': {
          'idx': _idx,
          'profile_id': 9,
          'expiration': _sasTime(_expiredExp),
          'subscription_active': false,
          'profile_change': null,
          'can_change_profile': false,
          'can_change_profile_active': false,
          'immediate_keeps_date': false,
        },
      });
      await open(t, exp: _expiredExp);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNull);
      expect(find.text('صلاحيّتك في الساس لا تسمح بتغيير باقة المشترك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('مديرٌ فرعيّ بقدرةٍ معياريّة false والخادم لا يعرف: مقفل', (t) async {
      await session(
          restricted: true,
          caps: const {
            'subscribers.edit': true,
            'subscribers.change_profile_active': false,
          });
      activationData(canActive: null);
      await open(t);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNull);
      expect(find.textContaining('صلاحيّتك في الساس لا تسمح بتغيير باقته'),
          findsOneWidget);
      await simDrain(t);
    });

    testWidgets('مديرٌ فرعيّ بلا subscribers.change_profile والخادم لا يعرف: مقفلٌ لأيّ مشترك',
        (t) async {
      await session(
          restricted: true,
          caps: const {
            'subscribers.edit': true,
            'subscribers.change_profile': false,
          });
      activationData(exp: _expiredExp, active: false, canActive: null);
      await open(t, exp: _expiredExp);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNull);
      expect(find.text('صلاحيّتك في الساس لا تسمح بتغيير باقة المشترك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('موظّفٌ والخادم لا يعرف صلاحيّة مديره: يُعرض الاختيار ويحكم الساس',
        (t) async {
      await session(employee: true, dateCapable: false);
      activationData(canActive: null);
      await open(t);
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('🚨 رفض الساس (PACKAGE_CHANGE_ACTIVE_FORBIDDEN): رسالته، وقفلٌ، وعودة الباقة',
        (t) async {
      await session(employee: true, dateCapable: false);
      activationData(canActive: null);
      server.reply('PUT', _putPath, 403, {
        'success': false,
        'code': 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
        'message': 'المشترك فعّال، وصلاحيّتك في الساس لا تسمح بتغيير باقته قبل انتهاء اشتراكه',
      });
      await open(t);
      await pick(t, 'Plus');
      await save(t); // الجدولة افتراضاً — لا تأكيد
      expect(puts().single['change_type'], 'schedule');
      final dd = t.widget<DropdownButton<int>>(packageDropdown());
      expect(dd.onChanged, isNull);
      expect(dd.value, 9, reason: 'عادت الباقة لأصلها');
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing);
      expect(find.text('تعديل المشترك'), findsOneWidget, reason: 'الشيت باقٍ');
      await simDrain(t);
    });

    testWidgets('🚨 مجدولٌ ينتظر: «مجدول: Plus عند …» ويُلغى من الشيت', (t) async {
      await session();
      activationData(pending: {
        'profile_id': 10,
        'profile_name': 'Plus',
        'due_date': _sasTime(_activeExp),
      });
      server.reply('POST', _cancelPath, 200, {
        'success': true,
        'message': 'أُلغي تغيير الباقة المجدول',
        'data': {'idx': _idx, 'cancelled': true, 'profile_change': null},
      });
      await open(t);
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsOneWidget);
      await tapText(t, 'إلغاء الجدولة');
      expect(find.text('إلغاء تغيير الباقة المجدول'), findsOneWidget,
          reason: 'تأكيدٌ قبل الإلغاء');
      await tapText(t, 'إلغاء الجدولة');
      expect(server.calls('POST', _cancelPath), hasLength(1));
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsNothing);
      expect(find.text('أُلغي تغيير الباقة المجدول'), findsOneWidget);
      expect(find.text('تعديل المشترك'), findsOneWidget, reason: 'الشيت باقٍ');
      await simDrain(t);
    });

    testWidgets('مجدولٌ ينتظر واختيارٌ جديد: يُقال إنّ المجدول سيُلغى', (t) async {
      await session();
      activationData(keepsDate: true, pending: {'profile_id': 10, 'due_date': _sasTime(_activeExp)});
      await open(t);
      // الاسم من قائمة الباقات حين لا يرسله الساس.
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsOneWidget);
      await pick(t, 'Gold');
      expect(find.textContaining('سيُلغى التغيير المجدول'), findsOneWidget);
      await save(t);
      expect(puts().single['profile_id'], 11);
      await simDrain(t);
    });

    testWidgets('إلغاءٌ ولا مجدول عند الساس (شيتٌ قديم): لا خطأ، والإطار يزول', (t) async {
      await session();
      activationData(pending: {'profile_id': 10, 'profile_name': 'Plus', 'due_date': _sasTime(_activeExp)});
      server.reply('POST', _cancelPath, 200, {
        'success': true,
        'message': 'لا يوجد تغيير باقة مجدول لهذا المشترك',
        'data': {'idx': _idx, 'cancelled': false, 'profile_change': null},
      });
      await open(t);
      await tapText(t, 'إلغاء الجدولة');
      await tapText(t, 'إلغاء الجدولة');
      expect(find.text('لا يوجد تغيير باقة مجدول لهذا المشترك'), findsOneWidget);
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsNothing);
      await simDrain(t);
    });

    testWidgets('إلغاءٌ يرفضه الساس: رسالته، والمجدول باقٍ', (t) async {
      await session();
      activationData(pending: {'profile_id': 10, 'profile_name': 'Plus', 'due_date': _sasTime(_activeExp)});
      server.reply('POST', _cancelPath, 409, {
        'success': false,
        'code': 'CANCEL_REJECTED',
        'message': 'تعذّر إلغاء تغيير الباقة المجدول — رفضه الساس',
      });
      await open(t);
      await tapText(t, 'إلغاء الجدولة');
      await tapText(t, 'إلغاء الجدولة');
      expect(find.text('تعذّر إلغاء تغيير الباقة المجدول — رفضه الساس'), findsOneWidget);
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('خادمٌ أقدم: لا «متى؟»، والقاعدة السابقة كما هي', (t) async {
      await session();
      activationData(newServer: false);
      await open(t);
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing,
          reason: 'لا جدولة يتجاهلها خادمٌ قديم فيقطع الاشتراك');
      await save(t);
      final body = puts().single;
      expect(body.containsKey('change_type'), isFalse);
      expect(body['expiration'], _sasTime(_activeExp),
          reason: 'مديرٌ يملك التاريخ: يُرسَل الأصليّ فيعيده الخادم (الكلاسيك)');
      await simDrain(t);
    });

    testWidgets('خادمٌ أقدم ومديرٌ بلا التاريخ: يُمنع أثناء التفعيل كما كان', (t) async {
      await session(dateCapable: false);
      activationData(newServer: false);
      await open(t);
      await pick(t, 'Plus');
      await save(t);
      expect(puts(), isEmpty);
      expect(find.textContaining('يمكن تغيير الباقة بعد انتهاء التفعيل الحاليّ'),
          findsOneWidget);
      await simDrain(t);
    });

    // ═══════════ جولة التحقّق (١٨ أكتوبر): ما وجده المراجعان ═══════════

    /// يفتح الشيت بلا pumpAndSettle — دائرة «لحظةً…» تدور ما دام الحال ممسوكاً.
    Future<void> openHeld(WidgetTester t) async {
      await pumpSim(t, const SimVariant(390, dark: false),
          home: (_) => simLauncher(
              (c) => showEditSubscriberSheet(c, _sub(_activeExp))));
      await t.tap(find.text(simOpenLabel));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('تعديل المشترك'), findsOneWidget);
    }

    testWidgets(
        '🚨 الحقل معطّلٌ حتى يصل حال الاشتراك (لا اختيارٌ يعلق بقفلٍ يصل بعده)، وبقيّة الحقول تُحفظ',
        (t) async {
      await session(code: 'jt');
      activationData(canActive: false);
      server.hold('GET', _adPath);
      await openHeld(t);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNull,
          reason: 'لا اختيار قبل أن يُعرف حال الاشتراك');
      expect(find.text('لحظةً — يُقرأ حال اشتراك المشترك قبل تغيير الباقة'),
          findsOneWidget);
      // يصل القفل: الحقل يبقى على الباقة الآن مقفلاً، ولا طريقٌ مسدود — الهاتف يُحفظ.
      server.release('GET', _adPath);
      await t.pumpAndSettle();
      final dd = t.widget<DropdownButton<int>>(packageDropdown());
      expect(dd.onChanged, isNull);
      expect(dd.value, 9);
      expect(find.textContaining('صلاحيّتك في الساس لا تسمح بتغيير باقته'),
          findsOneWidget);
      final phone = find.widgetWithText(TextField, '07701234567');
      await t.ensureVisible(phone);
      await t.enterText(phone, '07709999999');
      await t.pumpAndSettle();
      await save(t);
      final body = puts().single;
      expect(body['phone'], '07709999999');
      expect(body.containsKey('profile_id'), isFalse);
      await simDrain(t);
    });

    testWidgets(
        '🚨 activation-data تعذّرت: لا «خادمٌ أقدم» ولا تاريخٌ من الصفّ — الحقل متوقّف و«أعد المحاولة» تفتحه',
        (t) async {
      await session(dateCapable: true);
      server.reply('GET', _adPath, 500,
          {'success': false, 'message': 'فشل جلب بيانات التفعيل'});
      await open(t);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNull);
      expect(
          find.text(
              'تعذّر قراءة حال اشتراك المشترك، فتغيير الباقة متوقّفٌ الآن (بقيّة الحقول تُحفظ)'),
          findsOneWidget);
      expect(find.text('يمكن تغيير الباقة بعد انتهاء التفعيل الحاليّ'),
          findsNothing);
      // تعود: «أعد المحاولة» ⇒ الحال يصل والحقل يُفتح، و«متى؟» كالمعتاد.
      activationData(keepsDate: true);
      await t.ensureVisible(find.byKey(const ValueKey('pkg-state-retry')));
      await t.tap(find.byKey(const ValueKey('pkg-state-retry')));
      await t.pumpAndSettle();
      expect(server.calls('GET', _adPath), hasLength(2));
      expect(
          t.widget<DropdownButton<int>>(packageDropdown()).onChanged, isNotNull);
      await pick(t, 'Plus');
      expect(find.text('متى تتغيّر الباقة؟'), findsOneWidget);
      await save(t);
      final body = puts().single;
      expect(body['change_type'], 'schedule');
      expect(body.containsKey('expiration'), isFalse,
          reason: 'لا تاريخ صفٍّ قديم يُرسَل');
      await simDrain(t);
    });

    testWidgets(
        '🚨 رفضٌ بعد أن ألغى الخادم المجدول (pending_cancelled): يزول سطر «مجدول»',
        (t) async {
      await session();
      activationData(keepsDate: true, pending: {
        'profile_id': 10,
        'profile_name': 'Plus',
        'due_date': _sasTime(_activeExp),
      });
      server.reply('PUT', _putPath, 409, {
        'success': false,
        'code': 'PACKAGE_CHANGE_REJECTED',
        'message': 'تعذّر تغيير الباقة — رفضه الساس — وأُلغي التغيير المجدول السابق',
        'pending_cancelled': true,
      });
      await open(t);
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsOneWidget);
      await pick(t, 'Gold');
      await save(t);
      expect(find.textContaining('وأُلغي التغيير المجدول السابق'), findsOneWidget);
      expect(simText('مجدول: Plus عند ${_day(_activeExp)}'), findsNothing,
          reason: 'لم يعد عند الساس');
      expect(find.text('إلغاء الجدولة'), findsNothing);
      await simDrain(t);
    });

    testWidgets('صفٌّ قديم: الباقة الآن من الساس (لا الصفّ)، والرجوع لباقة الصفّ يُرسَل',
        (t) async {
      await session();
      activationData(profileId: 10, keepsDate: true);
      await open(t);
      expect(t.widget<DropdownButton<int>>(packageDropdown()).value, 10);
      await pick(t, 'Economy');
      expect(find.text('متى تتغيّر الباقة؟'), findsOneWidget);
      await save(t);
      expect(puts().single['profile_id'], 9);
      await simDrain(t);
    });

    testWidgets(
        '🚨 «يبقى التاريخ» غير مضمون (null — صلاحيّاتٌ لم تُقرأ): تنبيهٌ وتأكيد، لا وعد',
        (t) async {
      await session();
      activationData(keepsDate: null, canActive: null);
      await open(t);
      await pick(t, 'Plus');
      await tapText(t, 'حالاً');
      expect(find.textContaining('ويبقى تاريخ الانتهاء كما هو'), findsNothing);
      expect(find.textContaining('سيُعتبر المشترك منتهياً'), findsOneWidget);
      await save(t);
      expect(find.text('تغيير الباقة الآن؟'), findsOneWidget,
          reason: 'تأكيدٌ قبل ما قد لا رجعة فيه');
      await tapText(t, 'تراجع');
      expect(puts(), isEmpty);
      await simDrain(t);
    });

    testWidgets(
        'ردٌّ غير حاسم (PACKAGE_CHANGE_UNCONFIRMED): رسالته، ويُقرأ الحال من جديد فيعرض ما عند الساس',
        (t) async {
      await session();
      activationData(keepsDate: true);
      server.reply('PUT', _putPath, 409, {
        'success': false,
        'code': 'PACKAGE_CHANGE_UNCONFIRMED',
        'message':
            'لم يصل ردّ الساس على تغيير الباقة — افتح المشترك وتأكّد من باقته قبل أن تعيد المحاولة',
      });
      await open(t);
      await pick(t, 'Plus');
      // الساس نفّذ فعلاً بعد المهلة: القراءة الجديدة تقول Plus.
      activationData(keepsDate: true, profileId: 10);
      await save(t);
      expect(find.textContaining('لم يصل ردّ الساس على تغيير الباقة'),
          findsOneWidget);
      expect(server.calls('GET', _adPath), hasLength(2));
      expect(t.widget<DropdownButton<int>>(packageDropdown()).value, 10);
      expect(find.text('متى تتغيّر الباقة؟'), findsNothing,
          reason: 'لا تغيير معلّق بعد القراءة الجديدة');
      await simDrain(t);
    });

    // ── الرسم: ٣٢٠ · ٣٦٠ · ٤٣٠ × فاتح · داكن — بلا فيضانٍ ولا استثناء ──
    for (final width in const [320.0, 360.0, 430.0]) {
      for (final dark in const [false, true]) {
        testWidgets('الرسم @${width.toInt()} ${dark ? 'داكن' : 'فاتح'}: الاختيار والتنبيه والمجدول',
            (t) async {
          await session(code: 'jt');
          activationData(pending: {
            'profile_id': 11,
            'profile_name': 'Gold Unlimited 100M',
            'due_date': _sasTime(_activeExp),
          });
          await open(t, width: width, dark: dark);
          await pick(t, 'Plus');
          await tapText(t, 'حالاً');
          expect(find.textContaining('سيُعتبر المشترك منتهياً'), findsOneWidget);
          expect(find.text('عند انتهاء الاشتراك'), findsOneWidget);
          expect(t.takeException(), isNull);
          await simDrain(t);
        });
      }
    }
  });
}
