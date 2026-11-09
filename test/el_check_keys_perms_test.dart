import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';
import 'visual_perm/visual_perm_harness.dart';

/// محرّر موظّفي ايرث لنك/فايبر اكس/الشركات المُضافة والفحصان (٩ نوفمبر — مراجعة 3.0.18): «الفحص الشامل» والرادار مفعّلان
/// افتراضاً (`devices.deep_check`، `subscribers.check`)، وكان المحرّر لا يعرضهما و[ElEmployeePerms.outgoing] يرسل كلّ مفتاحٍ لا
/// يعرضه `false` — فيحفظه الخادم صريحاً ويختفي الفحصان عن الموظّف في 3.0.18. الآن: يُعرضان (ومعهما ما عبر VPN والتنبيهات لايرث
/// لنك والمُضافة)، وما لا يُعرض لا يُرسل (يُبقيه الخادم على المحفوظ/الافتراضيّ)، والطلب يحمل `perms_shown_only`.
const _v = SimVariant(390, dark: false);

/// كتالوجٌ كما يرسله الخادم (التسميات منه) — بما لا يعرضه محرّر ايرث لنك أيضاً.
final _catalog = PermissionsCatalog.fromJson({
  'permissions': {
    'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
    'subscribers.send_whatsapp': {'label': 'إرسال واتساب يدوي', 'category': 'subscribers'},
    'subscribers.check': {'label': 'الفحص العامّ على الشبكة', 'category': 'subscribers'},
    'subscribers.vpn_check': {'label': 'الفحص العامّ عبر VPN', 'category': 'subscribers'},
    'devices.view': {'label': 'عرض قائمة الأجهزة', 'category': 'devices'},
    'devices.deep_check': {'label': 'الفحص الشامل على الشبكة', 'category': 'devices'},
    'devices.deep_check_vpn': {'label': 'الفحص الشامل عبر VPN', 'category': 'devices'},
    'conn_vpn.link': {'label': 'ربط VPN', 'category': 'devices'},
    'conn_alerts.use': {'label': 'تنبيهات المشتركين — القسم (المشاكل والموافقة والإرسال)', 'category': 'alerts'},
    'agent_alerts.use': {'label': 'تنبيهات أجهزة الشبكة — القسم (الطافية وسجلّها)', 'category': 'alerts'},
    'whatsapp.send': {'label': 'إرسال رسالة لمشترك', 'category': 'whatsapp'},
    'settings.edit': {'label': 'تعديل إعدادات النظام', 'category': 'settings'},
    'renew_requests.use': {'label': 'طلبات التفعيل', 'category': 'subscribers'},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
    'devices': {'label': 'الأجهزة'},
    'alerts': {'label': 'التنبيهات'},
    'whatsapp': {'label': 'واتساب'},
    'settings': {'label': 'الإعدادات'},
  },
  'defaults': {
    'subscribers.view': true,
    'subscribers.send_whatsapp': true,
    'whatsapp.send': true,
    'devices.deep_check': true,
    'subscribers.check': true,
  },
  'presets': <String, Object>{},
});

void main() {
  tearDown(() {
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  group('المفاتيح', () {
    test('ايرث لنك والشركات المُضافة (والوطنيّ): الفحصان وما عبر VPN والتنبيهات في المحرّر', () {
      for (final p in ['earthlink', 'nabd', 'watani']) {
        ProviderService.debugSet(p);
        PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
        final k = ElEmployeePerms.keys;
        for (final key in ElEmployeePerms.roleFreeKeys) {
          expect(k.contains(key), isTrue, reason: '$p ← $key');
        }
      }
    });

    test('فايبر اكس: الفحصان على الشبكة وحدهما (بوّابته لا تمرّر ما عبر VPN ولا التنبيهات)', () {
      ProviderService.debugSet('fiberx');
      final k = ElEmployeePerms.keys;
      expect(k.containsAll(ElEmployeePerms.checkKeys), isTrue);
      for (final key in {...ElEmployeePerms.vpnKeys, ...ElEmployeePerms.alertKeys}) {
        expect(k.contains(key), isFalse, reason: key);
      }
    });

    test('صاحب حساب شركةٍ مُضافة: قدراته لا تُخفي الفحصين (ليسا في خريطة المزوّد)', () {
      ProviderService.debugSet('nabd', label: 'نبض');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.view': true, 'subscribers.edit': false});
      expect(ElEmployeePerms.keys.containsAll(ElEmployeePerms.roleFreeKeys), isTrue);
    });

    test('لا دور جاهز يحملها، والفحص المفعّل لا يجعل «موظّف عام» مخصّصاً', () {
      ProviderService.debugSet('earthlink');
      for (final p in ElEmployeePerms.presets) {
        expect(p.keys.intersection(ElEmployeePerms.roleFreeKeys), isEmpty, reason: p.id);
      }
      final general = ElEmployeePerms.presets.firstWhere((p) => p.id == 'general');
      final perms = {
        for (final k in general.keys) k: true,
        'devices.deep_check': true,
        'subscribers.check': true,
        'conn_vpn.link': true,
      };
      expect(ElEmployeePerms.matching(perms)?.id, 'general');
      expect(ElEmployeePerms.matching({...perms, 'devices.deep_check': false, 'subscribers.check': false})?.id, 'general');
    });
  });

  group('ما يُرسل', () {
    test('ما لا يعرضه المحرّر لا يُرسل (لا false) — والمعروض بقيمته، وwhatsapp.send يتبع «إرسال واتساب»', () {
      ProviderService.debugSet('earthlink');
      final out = ElEmployeePerms.outgoing(const [
        'subscribers.view',
        'subscribers.send_whatsapp',
        'devices.deep_check',
        'subscribers.check',
        'devices.deep_check_vpn',
        'whatsapp.send',
        'settings.edit',
        'renew_requests.use',
        'future.default_on',
      ], const {
        'subscribers.view': true,
        'subscribers.send_whatsapp': true,
        'devices.deep_check': true,
        'subscribers.check': false,
        'settings.edit': true,
        'renew_requests.use': true,
        'future.default_on': true,
      });
      expect(out, {
        'subscribers.view': true,
        'subscribers.send_whatsapp': true,
        'devices.deep_check': true,
        'subscribers.check': false,
        'devices.deep_check_vpn': false,
        'whatsapp.send': true,
      });
    });

    test('فايبر اكس: ما عبر VPN لا يُرسل (يبقى للخادم)', () {
      ProviderService.debugSet('fiberx');
      final out = ElEmployeePerms.outgoing(const ['subscribers.view', 'devices.deep_check', 'devices.deep_check_vpn', 'conn_vpn.link'],
          const {'subscribers.view': true, 'devices.deep_check': true, 'devices.deep_check_vpn': true, 'conn_vpn.link': true});
      expect(out, {'subscribers.view': true, 'devices.deep_check': true});
    });
  });

  group('المحرّر', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'earthlink:135762', 'auth.admin_username': 'owner'});
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: false);
    });

    Future<void> open(WidgetTester t, {Employee? employee}) async {
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showEmployeeEditorSheet(c, catalog: _catalog, employee: employee, isEarthlink: true)));
      await simOpen(t);
      await t.tap(find.textContaining('الصلاحيات ('));
      await t.pumpAndSettle();
    }

    testWidgets('موظّفٌ قديم بلا الفحصين: يُعرضان مفعّلين، و«موظّف عام» لا يطفئهما، والحفظ يرسلهما true بلا مفاتيح مخفيّة', (t) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('ListTile background color')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      server.reply('PUT', '/api/v2/employees/41', 200, {'success': true});
      final emp = Employee.fromJson({
        'id': 41,
        'username': 'ali.el',
        'full_name': 'علي',
        'is_active': 1,
        'permissions': {'subscribers.view': true, 'devices.view': true},
      })!;
      await open(t, employee: emp);
      // القائمة قصيرةٌ فتُبنى كلّها (بتسميات الكتالوج)
      for (final label in ['الفحص الشامل على الشبكة', 'الفحص العامّ على الشبكة', 'الفحص الشامل عبر VPN', 'ربط VPN']) {
        expect(simText(label, skipOffstage: false), findsOneWidget, reason: label);
      }
      expect(simText('تعديل إعدادات النظام', skipOffstage: false), findsNothing, reason: 'خارج مفاتيح ايرث لنك');
      // دورٌ جاهز لا يلمس الفحصين
      await t.tap(find.text('موظّف عام'));
      await t.pumpAndSettle();
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      final body = server.bodies('PUT', '/api/v2/employees/41').single;
      expect(body['perms_shown_only'], isTrue);
      final perms = Map<String, dynamic>.from(body['permissions'] as Map);
      expect(perms['devices.deep_check'], isTrue);
      expect(perms['subscribers.check'], isTrue);
      expect(perms['devices.deep_check_vpn'], isFalse);
      expect(perms['whatsapp.send'], isTrue, reason: 'يتبع «إرسال واتساب»');
      expect(perms.containsKey('settings.edit'), isFalse, reason: 'ما لا يعرضه لا يُرسل');
      expect(perms.containsKey('renew_requests.use'), isFalse, reason: 'يبقى على المحفوظ عند الخادم');
      await simDrain(t);
    });

    // مراجعة 3.0.18 الثانية: الدور لا يلمس ما عبر VPN والتنبيهات (00b20601) — فلا يقول «عرض فقط» «بلا أيّ عمليّة» والموظّف يربط VPN
    // ويوافق على تنبيهات المشتركين ويرسلها؛ يسمّي ما بقي ممنوحاً فرادى.
    testWidgets('«عرض فقط» وما مُنح فرادى من «ربط VPN» و«تنبيهات المشتركين» باقٍ: السطر يسمّيهما لا «بلا أيّ عمليّة»، والحفظ يُبقيهما', (t) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('ListTile background color')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      server.reply('PUT', '/api/v2/employees/42', 200, {'success': true});
      final emp = Employee.fromJson({
        'id': 42,
        'username': 'sara.el',
        'full_name': 'سارة',
        'is_active': 1,
        'permissions': {'subscribers.view': true, 'subscribers.send_whatsapp': true, 'conn_vpn.link': true, 'conn_alerts.use': true},
      })!;
      await open(t, employee: emp);
      await t.tap(find.text('عرض فقط'));
      await t.pumpAndSettle();
      const plain = 'يشاهد المشتركين والباقات والخصومات والأسعار بلا أيّ عمليّة';
      expect(find.text(plain), findsNothing, reason: 'الموظّف يربط VPN ويوافق على التنبيهات ويرسلها');
      expect(find.text('$plain — عدا ما منحته فرادى: ربط VPN · تنبيهات المشتركين (الموافقة والإرسال)'), findsOneWidget);
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      final perms = Map<String, dynamic>.from(server.bodies('PUT', '/api/v2/employees/42').single['permissions'] as Map);
      expect(perms['subscribers.send_whatsapp'], isFalse, reason: 'الدور ضبط مفاتيحه');
      expect(perms['conn_vpn.link'], isTrue, reason: 'والممنوح فرادى كما هو — كما يقول السطر');
      expect(perms['conn_alerts.use'], isTrue);
      await simDrain(t);
    });
  });

  group('سطر «عرض فقط»', () {
    test('بلا عمليّةٍ ممنوحةٍ فرادى ⇒ الوصف كما هو؛ والفحص والإشعار وقسم تنبيهات الأجهزة ليست عمليّة؛ وما لا يعرضه الكتالوج لا يُذكر', () {
      ProviderService.debugSet('earthlink');
      final view = ElEmployeePerms.presets.firstWhere((p) => p.id == 'view');
      final collect = ElEmployeePerms.presets.firstWhere((p) => p.id == 'collect');
      final catalog = _catalog.permissions.keys;
      final base = {for (final k in view.keys) k: true};
      expect(ElEmployeePerms.captionFor(view, base, catalogKeys: catalog), view.description);
      expect(
        ElEmployeePerms.captionFor(view, {
          ...base,
          'devices.deep_check': true,
          'subscribers.check': true,
          'devices.deep_check_vpn': true,
          'subscribers.vpn_check': true,
          'agent_alerts.use': true,
          'conn_vpn.link': false,
        }, catalogKeys: catalog),
        view.description,
      );
      expect(ElEmployeePerms.captionFor(view, {...base, 'conn_alerts.use': true}, catalogKeys: catalog),
          '${view.description} — عدا ما منحته فرادى: تنبيهات المشتركين (الموافقة والإرسال)');
      expect(ElEmployeePerms.captionFor(collect, {...base, 'conn_vpn.link': true}, catalogKeys: catalog), collect.description,
          reason: 'لا يدّعي غيره أنّه بلا عمليّة');
      ProviderService.debugSet('fiberx');
      expect(ElEmployeePerms.captionFor(view, {...base, 'conn_vpn.link': true}, catalogKeys: catalog), view.description,
          reason: 'فايبر اكس: «ربط VPN» خارج محرّره');
    });
  });

  group('الموظّف', () {
    test('موظّف ايرث لنك بلا قيمةٍ محفوظة: الفحص الشامل والرادار متاحان', () {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'devices.view': true});
      expect(PermissionsService.deepCheckNet, isTrue);
      expect(PermissionsService.subsCheckNet, isTrue);
    });

    testWidgets('رادار المشتركين ظاهرٌ لموظّف ايرث لنك بلا قيمةٍ محفوظة', (t) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      await visualSetUp(s2ElEmpSubs);
      await pumpVisual(t, phone, home: (_) => const SubscribersScreen());
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('subs-general-check')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
    });
  });
}
