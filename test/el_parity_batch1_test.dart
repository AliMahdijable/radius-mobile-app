import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/bulk_activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edit_subscriber_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';

import 'sim_el/sim_harness.dart' show simText;
import 'visual_perm/visual_perm_harness.dart';

/// تدقيق ١٨ أكتوبر — الدفعة ① (حجبٌ واسعٌ بالخطأ لايرث لنك)، جهة التطبيق.
///
/// ما يحرسه هذا الملفّ (والبقيّة في `perms_gating_test.dart` و
/// `package_change_rule_test.dart`):
/// - «قوالب الطباعة» في الإعدادات لكلّ الشركات (كانت مخفيّة لايرث لنك).
/// - «تجديد» الجماعيّ لايرث لنك: بمكانه **مقفلٌ بالسبب** — الخادم يرفضه
///   بـ409 `EL_METHOD_REQUIRED` — ولا يفتح الورقة.
/// - تعديل المشترك لايرث لنك: لا منتقي «تاريخ الانتهاء» ولا «تابع إلى» (لا
///   API لهما)، ويومه الأخير يقبل تغيير الباقة (canChangeAccount).
/// - محرّر موظّف ايرث لنك: الأجهزة (`devices.*`) ممّا يُمنح، ولا ما سواها.
const _bulkReason =
    'ايرث لنك: التفعيل الجماعيّ غير متاح — فعّل كلّ مشترك من نافذته (رصيد أون‑لاين أو كارت)';

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

/// يسجّل أجسام الطلبات (غير GET) ويمرّرها للخادم الوهميّ كما هي.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.inner);
  final HttpClientAdapter inner;
  final writes = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (o.method.toUpperCase() != 'GET') {
      writes['${o.method.toUpperCase()} ${o.path}'] = o.data;
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

/// فيضان نصف بكسلٍ قائمٌ في صفّ المشترك بخطّ الاختبار (انظر
/// `subscribers_tab_locked_test`)، وخطأ ListTile المعروف في تبويب معلومات
/// محرّر الموظّف — ليسا موضوع هذا الملفّ، فلا يُسقطانه.
void _tolerateKnownLayoutNoise() {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString();
    if (s.contains('overflowed') ||
        s.contains('ListTile background color or ink splashes may be invisible')) {
      return;
    }
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

Future<void> _drain(WidgetTester t, {int seconds = 6}) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(Duration(seconds: seconds));
  await visualTearDown();
}

/// صفحةٌ بزرّ «افتح» يفتح [open] — للأوراق.
Widget _launcher(void Function(BuildContext c) open) => Scaffold(
      backgroundColor: AppColors.bg,
      body: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => open(c),
            child: const Text('افتح'),
          ),
        ),
      ),
    );

String _sasTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Subscriber _sub({required DateTime expiration, bool? canChange}) =>
    Subscriber.fromJson({
      'idx': '1',
      'username': 'ali1@najaf',
      'firstname': 'علي',
      'lastname': 'حسن الموسوي',
      'phone': '07701000001',
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': _sasTime(expiration),
      'enabled': 1,
      if (canChange != null) 'can_change_package': canChange,
    });

void main() {
  setUpAll(visualSetUpAll);

  // ═══════════════════════ التجديد الجماعيّ ═══════════════════════
  group('التجديد الجماعيّ لايرث لنك — السبب', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    tearDown(() async {
      ProviderService.debugSet(null);
      await ActiveCompany.clear();
    });

    test('ايرث لنك ⇒ السبب · SAS4 ⇒ متاح', () {
      ProviderService.debugSet('earthlink');
      expect(bulkActivateUnavailableReason(), isNotNull);
      ProviderService.debugSet(null);
      expect(bulkActivateUnavailableReason(), isNull);
    });

    test('الشركة المفتوحة ايرث لنك ولو لم يصل /me بعد', () async {
      ProviderService.debugSet(null);
      await ActiveCompany.saveFromLogin(
        sasUrl: '',
        adminId: 'earthlink:5',
        loginUsername: 'mahdi.el',
        adminUsername: 'mahdi.el',
        isEmployee: false,
        label: 'ايرث لنك (Earthlink)',
        sasCode: 'earthlink',
      );
      expect(bulkActivateUnavailableReason(), isNotNull);
    });
  });

  group('التجديد الجماعيّ — الزرّ', () {
    Future<VisualServer> openList(WidgetTester t, Scenario s) async {
      _tolerateKnownLayoutNoise();
      final server = await visualSetUp(s);
      await pumpVisual(t, phone, home: (_) => const SubscribersScreen());
      await settle(t, seconds: 2);
      // الضغط المطوَّل على بطاقة ⇒ وضع التحديد وشريطه.
      await t.longPress(simText('علي حسن الموسوي').first);
      await settle(t, seconds: 1);
      return server;
    }

    Finder renewPill() => find.ancestor(
        of: find.text('تجديد (1)'), matching: _byTypeName('_PrimaryPill'));

    testWidgets('🚨 مالك ايرث لنك: «تجديد» بمكانه مقفلٌ بالسبب ولا يفتح الورقة',
        (t) async {
      final server = await openList(t, s1Owner);
      expect(renewPill(), findsOneWidget, reason: 'بمكانه لا مخفيّ');
      expect(
          find.descendant(of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsOneWidget);

      await t.tap(renewPill());
      await t.pump();
      expect(find.text(_bulkReason), findsOneWidget,
          reason: 'السبب نفسه لا «اطلبها من مديرك»');
      expect(find.byType(BottomSheet), findsNothing);
      await t.pump(const Duration(seconds: 3)); // مؤقّت رسالة القفل
      expect(server.log.join('\n').contains('activation-data'), isFalse,
          reason: 'لا ورقة ولا جلب');
      await _drain(t);
    });

    testWidgets('🚨 موظّف ايرث لنك يملك التفعيل: مقفلٌ بالسبب نفسه', (t) async {
      await openList(
        t,
        const Scenario(
          id: 'T_el_emp_activate',
          title: 'موظّف ايرث لنك — تفعيل',
          actor: Actor.elEmployee,
          provider: 'earthlink',
          keys: {'subscribers.view': true, 'subscribers.activate': true},
        ),
      );
      expect(
          find.descendant(of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsOneWidget);
      await t.tap(renewPill());
      await t.pump();
      expect(find.text(_bulkReason), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await _drain(t);
    });

    testWidgets('مالك ساس: «تجديد» مفتوحٌ كما كان', (t) async {
      await openList(t, s1bSasOwner);
      expect(renewPill(), findsOneWidget);
      expect(
          find.descendant(of: renewPill(), matching: find.byIcon(LucideIcons.lock)),
          findsNothing);
      expect(
          find.descendant(
              of: renewPill(), matching: find.byIcon(LucideIcons.calendarPlus)),
          findsOneWidget);
      await _drain(t);
    });
  });

  // ═══════════════════════ قوالب الطباعة ═══════════════════════
  group('الإعدادات — «قوالب الطباعة» لكلّ الشركات', () {
    for (final s in [s1Owner, s3ElEmpNone, s1bSasOwner]) {
      testWidgets('${s.title}: الصفّ بمكانه', (t) async {
        await visualSetUp(s);
        final nav = GlobalKey<NavigatorState>();
        await pumpVisual(t, phoneTall,
            navigatorKey: nav,
            home: (_) => Scaffold(backgroundColor: AppColors.bg));
        await settle(t, seconds: 1);
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
        );
        await settle(t, seconds: 2);
        expect(find.text('قوالب الطباعة'), findsOneWidget);
        expect(t.takeException(), isNull);
        await _drain(t);
      });
    }
  });

  // ═══════════════════════ تعديل المشترك ═══════════════════════
  group('تعديل المشترك لايرث لنك', () {
    /// يضبط الجلسة ثمّ علمَي «المدير/الباقات» (يقرؤهما الشيت من الخزنة).
    Future<_Recorder> setUpSession(
      Scenario s, {
      bool managers = false,
      bool packages = false,
    }) async {
      final server = await visualSetUp(s);
      const storage = FlutterSecureStorage();
      await storage.write(
          key: 'auth.can_access_managers', value: managers ? '1' : '0');
      await storage.write(
          key: 'auth.can_access_packages', value: packages ? '1' : '0');
      final rec = _Recorder(server);
      ApiClient.dio.httpClientAdapter = rec;
      return rec;
    }

    Future<void> openEdit(WidgetTester t, Subscriber sub) async {
      _tolerateKnownLayoutNoise();
      await pumpVisual(t, phone,
          home: (_) => _launcher((c) => showEditSubscriberSheet(c, sub)));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
    }

    const expirationLabel = 'تاريخ الانتهاء';
    const parentLabel = 'تابع إلى (المدير)';

    testWidgets('🚨 موظّف ايرث لنك بـpackages.view: لا منتقي تاريخ (لا API له)',
        (t) async {
      final rec = await setUpSession(
        const Scenario(
          id: 'T_el_emp_edit',
          title: 'موظّف ايرث لنك — تعديل',
          actor: Actor.elEmployee,
          provider: 'earthlink',
          keys: {
            'subscribers.view': true,
            'subscribers.edit': true,
            'packages.view': true,
          },
        ),
        packages: true,
      );
      await openEdit(t,
          _sub(expiration: DateTime.now().add(const Duration(days: 20))));
      expect(find.text('تعديل المشترك'), findsOneWidget);
      expect(find.text(expirationLabel), findsNothing);
      expect(find.text(parentLabel), findsNothing);
      // ولا «حفظ» بلا تغيير: التاريخ لا يُرسَل خفيةً فيبدو تغييراً.
      expect(find.text('لا توجد تغييرات'), findsOneWidget);
      expect(rec.writes, isEmpty);
      await _drain(t);
    });

    testWidgets('🚨 مالك ايرث لنك بعلمَي المدير والباقات: لا تاريخ ولا «تابع إلى»',
        (t) async {
      await setUpSession(s1Owner, managers: true, packages: true);
      await openEdit(t,
          _sub(expiration: DateTime.now().add(const Duration(days: 20))));
      expect(find.text(expirationLabel), findsNothing);
      expect(find.text(parentLabel), findsNothing);
      await _drain(t);
    });

    testWidgets('مالك ساس سوبر: التاريخ و«تابع إلى» كما كانا', (t) async {
      await setUpSession(s1bSasOwner, managers: true, packages: true);
      await openEdit(t,
          _sub(expiration: DateTime.now().add(const Duration(days: 20))));
      expect(find.text(expirationLabel), findsOneWidget);
      expect(find.text(parentLabel), findsOneWidget);
      await _drain(t);
    });

    Future<void> pickStandardAndSave(WidgetTester t) async {
      await t.tap(find.byType(PackagePickerField));
      await settle(t, seconds: 1);
      await t.tap(find.text(iso('Standard')));
      await settle(t, seconds: 1);
      await t.tap(find.text('حفظ التغييرات'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    testWidgets('🚨 ايرث لنك في يومه الأخير (canChangeAccount): تتغيّر الباقة',
        (t) async {
      final rec = await setUpSession(s1Owner, managers: true, packages: true);
      await openEdit(
          t,
          _sub(
            expiration: DateTime.now().add(const Duration(hours: 10)),
            canChange: true,
          ));
      await pickStandardAndSave(t);
      final put = rec.writes['PUT /api/v2/subscribers/1'];
      expect(put, isA<Map>(), reason: 'أُرسل التغيير — لا منع');
      final body = Map<String, dynamic>.from(put as Map);
      expect(body['profile_id'], 8);
      expect(body.containsKey('expiration'), isFalse,
          reason: 'لا تاريخ يُرسَل لايرث لنك');
      expect(body.containsKey('parent_id'), isFalse);
      await t.pump(const Duration(seconds: 4)); // إشعار النجاح
      await _drain(t);
    });

    testWidgets('ايرث لنك فعّالٌ لأكثر من يوم وخادمٌ بلا حكم: يُمنع بقاعدتها',
        (t) async {
      final rec = await setUpSession(s1Owner);
      await openEdit(
          t, _sub(expiration: DateTime.now().add(const Duration(days: 20))));
      await pickStandardAndSave(t);
      expect(rec.writes.containsKey('PUT /api/v2/subscribers/1'), isFalse);
      expect(
          find.textContaining('تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ'),
          findsOneWidget);
      await t.pump(const Duration(seconds: 4)); // إشعار المنع
      await _drain(t);
    });
  });

  // ═══════════════════════ موظّف ايرث لنك — الأجهزة ═══════════════════════
  group('صلاحيّات موظّف ايرث لنك — الأجهزة تُمنح', () {
    const devices = ['devices.view', 'devices.monitor', 'devices.manage'];

    test('المفاتيح الثلاثة ممّا يُمنح، وكلٌّ وحده (لا دورٌ جاهز يحملها)', () {
      for (final k in devices) {
        expect(ElEmployeePerms.keys, contains(k));
        for (final p in ElEmployeePerms.presets) {
          expect(p.keys, isNot(contains(k)), reason: '${p.id} ← $k');
        }
      }
    });

    test('ما يُرسَل: الأجهزة كما اختارها المالك، وما لا يُمنح false دائماً', () {
      final out = ElEmployeePerms.outgoing(
        const [
          'subscribers.view',
          ...devices,
          'whatsapp.broadcast',
          'settings.edit',
          'print_templates.edit',
        ],
        const {
          'subscribers.view': true,
          'devices.view': true,
          'devices.monitor': true,
          'whatsapp.broadcast': true,
          'settings.edit': true,
          'print_templates.edit': true,
        },
      );
      expect(out['devices.view'], isTrue);
      expect(out['devices.monitor'], isTrue);
      expect(out['devices.manage'], isFalse);
      expect(out['whatsapp.broadcast'], isFalse);
      expect(out['settings.edit'], isFalse);
      expect(out['print_templates.edit'], isFalse);
    });

    testWidgets('المحرّر يعرض فئة الأجهزة بمفاتيحها الثلاثة', (t) async {
      _tolerateKnownLayoutNoise();
      await visualSetUp(s1Owner);
      final catalog = PermissionsCatalog.fromJson({
        'permissions': {
          'subscribers.view': {
            'label': 'عرض المشتركين',
            'category': 'subscribers'
          },
          'devices.view': {'label': 'عرض قائمة الأجهزة', 'category': 'devices'},
          'devices.monitor': {
            'label': 'مراقبة الأجهزة الحيّة',
            'category': 'devices'
          },
          'devices.manage': {'label': 'إدارة الأجهزة', 'category': 'devices'},
          'settings.edit': {
            'label': 'تعديل إعدادات النظام',
            'category': 'settings'
          },
        },
        'categories': {
          'subscribers': {'label': 'المشتركون'},
          'devices': {'label': 'الأجهزة'},
          'settings': {'label': 'الإعدادات'},
        },
        'defaults': {'subscribers.view': true},
        'presets': <String, Object>{},
      });
      await pumpVisual(t, phoneTall,
          home: (_) => _launcher((c) =>
              showEmployeeEditorSheet(c, catalog: catalog, isEarthlink: true)));
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      await t.tap(find.textContaining('الصلاحيات ('));
      await settle(t, seconds: 1);
      expect(find.text('الأجهزة'), findsOneWidget);
      expect(find.text('عرض قائمة الأجهزة'), findsOneWidget);
      expect(find.text('مراقبة الأجهزة الحيّة'), findsOneWidget);
      expect(find.text('إدارة الأجهزة'), findsOneWidget);
      // وما لا يُمنح لموظّف ايرث لنك لا يُعرض.
      expect(find.text('تعديل إعدادات النظام'), findsNothing);
      await _drain(t);
    });
  });
}
