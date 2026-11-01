import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_table_row.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// مفاتيح موظّف المشروع الوطنيّ لأقسام بوّابته (١ نوفمبر — القرار ٢؛ العقد §9): «الجلسات» و«تقرير الجلسات» (`reports.sessions`)،
/// وجرس البوّابة (`notifications.view`)، والتعليق على المهامّ والطلبات (`subscribers.edit`). قدرات صاحب الحساب من الخادم تُبقي الأوّل
/// والأخير false — فالمحرّر يعرضها للوطنيّ بلا تصفيةٍ بها، بتلميحٍ يقول إنّها للبوّابة، و[ElEmployeePerms.outgoing] يحفظ قيمها (كان
/// يرسلها false بصمت فيُسحب «عرض التبليغات» الممنوح من الويب). وما يفتحه المفتاح نفسه خارج البوّابة (تقرير جلسات الساس، «تعديل»
/// المشترك) يبقى مخفيّاً لموظّف الوطنيّ كما هو لصاحبه.
const _v = SimVariant(390, dark: false);

/// قدرات صاحب حساب الوطنيّ كما يرسلها الخادم (providerKit canonicalPermissions).
const _ownerCaps = <String, bool>{
  'subscribers.view': true,
  'subscribers.activate': true,
  'subscribers.toggle': true,
  'subscribers.edit': false,
  'subscribers.delete': false,
  'subscribers.add': false,
  'reports.financial': true,
  'reports.packages': true,
  'reports.sessions': false,
  'reports.manager_debts': false,
  'managers.view': false,
  'employees.view': true,
};

const _sessionsHint = 'جلسات المشتركين و«تقرير الجلسات» في بوّابة المشروع الوطني';
const _notesHint = 'إشعارات بوّابة المشروع الوطني وإعلاناتها — للقراءة';
const _editHint = 'التعليق على المهامّ والطلبات في بوّابة المشروع الوطني';

final _catalog = PermissionsCatalog.fromJson({
  'permissions': {
    'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
    'subscribers.edit': {'label': 'تعديل بيانات المشترك', 'category': 'subscribers'},
    'subscribers.view_activity': {'label': 'سجلّ حركات المشترك', 'category': 'subscribers'},
    'reports.financial': {'label': 'التقارير الماليّة', 'category': 'reports'},
    'reports.packages': {'label': 'توزيع الباقات', 'category': 'reports'},
    'reports.sessions': {'label': 'الجلسات الحالية', 'category': 'reports'},
    'notifications.view': {'label': 'عرض التبليغات', 'category': 'notifications'},
    'managers.view': {'label': 'عرض المدراء الفرعيّين', 'category': 'managers'},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
    'reports': {'label': 'التقارير'},
    'notifications': {'label': 'التبليغات'},
    'managers': {'label': 'المدراء'},
  },
  'defaults': {'subscribers.view': true},
  'presets': <String, Object>{},
});

/// خطأ Flutter المعروف في تبويب المعلومات (`SwitchListTile` داخل سطحٍ ملوّن) — كمحاكاة محرّر ايرث لنك.
const _listTileError = 'ListTile background color or ink splashes may be invisible';

Future<void> _tolerateListTile(Future<void> Function() body) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains(_listTileError)) return;
    prev?.call(d);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = prev;
  }
}

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  group('المفاتيح', () {
    test('صاحب حساب الوطنيّ: الثلاثة في المحرّر رغم قدراته false، بتلميحات البوّابة — وما سواها مصفّى بقدراته كما كان', () {
      final k = ElEmployeePerms.keys;
      for (final on in ElEmployeePerms.nationalExtraKeys) {
        expect(k.contains(on), isTrue, reason: on);
      }
      expect(k.contains('managers.view') || k.contains('subscribers.delete'), isFalse, reason: 'قدرته false ⇒ لا يُمنح');
      expect(ElEmployeePerms.hintFor('reports.sessions'), _sessionsHint);
      expect(ElEmployeePerms.hintFor('notifications.view'), _notesHint);
      expect(ElEmployeePerms.hintFor('subscribers.edit'), _editHint);
      expect(ElEmployeePerms.hintFor('reports.financial'), 'يشمل رصيد حسابك عند الشركة', reason: 'تلميحات الشركة المُضافة باقية');
    });

    test('outgoing يحفظ قيم الثلاثة للوطنيّ (كانت تُرسل false بصمت)', () {
      final out = ElEmployeePerms.outgoing(_catalog.permissions.keys, {
        'subscribers.view': true,
        'reports.sessions': true,
        'notifications.view': true,
        'subscribers.edit': false,
        'managers.view': true,
      });
      expect(out['reports.sessions'], isTrue);
      expect(out['notifications.view'], isTrue);
      expect(out['subscribers.edit'], isFalse, reason: 'قيمتها كما اختارها المالك');
      expect(out['managers.view'], isFalse, reason: 'ما لا يراه المالك لا يُمنح');
      final granted = ElEmployeePerms.outgoing(_catalog.permissions.keys, {'subscribers.edit': true});
      expect(granted['subscribers.edit'], isTrue);
    });

    test('موظّف الوطنيّ يُرى بمفاتيحها (permShown) — وغير الوطنيّ من الشركات المُضافة كما كان', () {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      expect(ElEmployeePerms.keys.containsAll(ElEmployeePerms.nationalExtraKeys), isTrue);
      ProviderService.debugSet('nabd', label: 'نبض');
      expect(ElEmployeePerms.keys.contains('reports.sessions') || ElEmployeePerms.keys.contains('notifications.view'), isFalse);
      expect(ElEmployeePerms.hintFor('reports.sessions'), isNot(_sessionsHint));
      // مالك نبض: subscribers.edit يتبع قدرته كما كان
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.edit': false});
      expect(ElEmployeePerms.keys.contains('subscribers.edit'), isFalse);
    });

    test('ما يفتحه المفتاحان خارج البوّابة (تقرير جلسات الساس، «تعديل» المشترك) مخفيٌّ لموظّف الوطنيّ كصاحبه', () {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true, 'subscribers.edit': true, 'reports.sessions': true});
      expect(providerHidesAction('reports.sessions'), isTrue);
      expect(providerHidesAction('subscribers.edit'), isTrue);
      expect(providerHidesAction('subscribers.view'), isFalse);
      expect(providerHidesAction('subscribers.toggle'), isFalse, reason: 'ما مُنحه الموظّف يحكمه كما كان');
      // صاحب الحساب: بقدراته كما كان
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      expect(providerHidesAction('reports.sessions'), isTrue);
      expect(providerHidesAction('subscribers.edit'), isTrue);
      expect(providerHidesAction('subscribers.activate'), isFalse);
      // موظّف شركةٍ مُضافة أخرى: لا يُخفى شيء (يحكمه ما مُنح)
      ProviderService.debugSet('nabd', label: 'نبض');
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.edit': true});
      expect(providerHidesAction('subscribers.edit'), isFalse);
    });
  });

  group('المحرّر', () {
    Future<void> open(WidgetTester t, {Employee? employee}) async {
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showEmployeeEditorSheet(c, catalog: _catalog, employee: employee, isEarthlink: true)));
      await simOpen(t);
      await t.tap(find.textContaining('الصلاحيات ('));
      await t.pumpAndSettle();
    }

    /// قائمة الصلاحيّات كسولة: يُمرَّر إليها حتى يُبنى الصفّ.
    Future<void> reveal(WidgetTester t, Finder f) async {
      final list = find.ancestor(of: simText('عرض المشتركين', skipOffstage: false), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(f, 120, scrollable: list);
      await t.pumpAndSettle();
    }

    testWidgets('يعرض الثلاثة بتلميحات البوّابة، وحفظ موظّفٍ قائم يُبقي «عرض التبليغات» الممنوح من الويب', (t) async {
      await _tolerateListTile(() async {
        server.reply('PUT', '/api/v2/employees/31', 200, {'success': true});
        final emp = Employee.fromJson({
          'id': 31,
          'username': 'sara.nat',
          'full_name': 'سارة',
          'is_active': 1,
          'permissions': {
            'subscribers.view': true,
            'notifications.view': true,
            'reports.sessions': true,
            'subscribers.edit': false,
          },
        });
        await open(t, employee: emp);
        for (final label in ['تعديل بيانات المشترك', 'الجلسات الحالية', 'عرض التبليغات']) {
          await reveal(t, simText(label));
          expect(simText(label), findsOneWidget, reason: label);
        }
        for (final hint in [_editHint, _sessionsHint, _notesHint]) {
          await reveal(t, simText(hint));
          expect(simText(hint), findsOneWidget, reason: hint);
        }
        expect(simText('عرض المدراء الفرعيّين', skipOffstage: false), findsNothing, reason: 'قدرة المالك false ⇒ لا يُعرض');
        await t.tap(find.text('حفظ'));
        await t.pumpAndSettle();
        final perms = Map<String, dynamic>.from(server.bodies('PUT', '/api/v2/employees/31').single['permissions'] as Map);
        expect(perms['notifications.view'], isTrue, reason: 'لا يُسحب بصمت بتعديلٍ من التطبيق');
        expect(perms['reports.sessions'], isTrue);
        expect(perms['subscribers.edit'], isFalse);
        expect(perms['subscribers.view'], isTrue);
        expect(perms['managers.view'], isFalse);
        await simDrain(t);
      });
    });
  });

  group('قائمة صفّ المشترك (الحاسبة)', () {
    final sub = Subscriber.fromJson({
      'idx': '13293073',
      'username': 'FBG885F15P1',
      'firstname': 'مريم',
      'lastname': 'عبد الله',
      'expiration': '2026-11-20 10:00:00',
    });

    Future<void> openMenu(WidgetTester t) async {
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showSubscriberRowMenu(c, sub, position: const Offset(40, 40), onOpenDetails: () {})));
      await simOpen(t);
    }

    testWidgets('«تعديل» مخفيٌّ لموظّف الوطنيّ ولو مُنح subscribers.edit (للتعليق في البوّابة) — وحيٌّ لموظّف شركةٍ مُضافة أخرى', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'subscribers.edit': true});
      await openMenu(t);
      expect(find.text('سجل الحركات'), findsOneWidget, reason: 'القائمة مفتوحة');
      expect(find.text('تعديل'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      ProviderService.debugSet('nabd', label: 'نبض');
      await openMenu(t);
      expect(find.text('تعديل'), findsOneWidget, reason: 'غير الوطنيّ يحكمه ما مُنح كما كان');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await simDrain(t);
    });
  });
}
