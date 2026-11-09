import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// الأدوار الجاهزة لا تلمس الفحصين وما عبر VPN والتنبيهات (٩ نوفمبر — المنسّق بتفويض المالك): قوالب الخادم لموظّفي الساس (كاشير،
/// مساعد مدير، مشاهد فقط) لا تحمل `devices.deep_check`/`subscribers.check` فكان تطبيقها يُطفئ الفحصين المفعّلين افتراضاً (ويسحب «ربط
/// VPN» والتنبيهات الممنوحة). الآن كقوالب ايرث لنك/فايبر اكس/المُضافة: [ElEmployeePerms.roleFreeKeys] تبقى على قيمتها المحفوظة —
/// true كانت أو false — والباقي كما يقول القالب.
const _v = SimVariant(390, dark: false);

const _roleFree = ElEmployeePerms.roleFreeKeys;

/// ما يُحفظ للموظّف قبل القالب: لكلّ مفتاحٍ مستقلّ قيمةٌ مقصودة — نصفها true ونصفها false.
const _stored = <String, bool>{
  'devices.deep_check': false,
  'subscribers.check': true,
  'devices.deep_check_vpn': true,
  'subscribers.vpn_check': false,
  'conn_vpn.link': true,
  'conn_alerts.use': false,
  'conn_alerts.notify': true,
  'agent_alerts.use': true,
  'agent_alerts.notify': false,
};

/// مفاتيح كتالوجٍ صغير بما يحتاجه الاختبار — الفئات والتسميات كالخادم.
const _defs = <String, List<String>>{
  'subscribers': ['subscribers.view', 'subscribers.add', 'subscribers.activate', 'subscribers.check', 'subscribers.vpn_check'],
  'reports': ['reports.financial'],
  'devices': ['devices.view', 'conn_vpn.link', 'devices.deep_check', 'devices.deep_check_vpn'],
  'alerts': ['conn_alerts.use', 'conn_alerts.notify', 'agent_alerts.use', 'agent_alerts.notify'],
};

/// القالب كما يبنيه الخادم (employees.buildPermissionsFromKeys): كلّ مفاتيح الكتالوج، المدرجة true والباقي false.
Map<String, bool> _serverPreset(Set<String> on) => {
      for (final ks in _defs.values)
        for (final k in ks) k: on.contains(k),
    };

final _presets = <String, ({String label, Set<String> on})>{
  'cashier': (label: 'كاشير', on: {'subscribers.view', 'subscribers.activate'}),
  'assistant_manager': (label: 'مساعد مدير', on: {'subscribers.view', 'subscribers.add', 'subscribers.activate', 'reports.financial'}),
  'viewer': (label: 'مشاهد فقط', on: {'subscribers.view', 'reports.financial'}),
};

final _catalog = PermissionsCatalog.fromJson({
  'permissions': {
    for (final e in _defs.entries)
      for (final k in e.value) k: {'label': 'مفتاح $k', 'category': e.key},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
    'reports': {'label': 'التقارير'},
    'devices': {'label': 'الأجهزة'},
    'alerts': {'label': 'التنبيهات'},
  },
  'defaults': {'subscribers.view': true, 'devices.deep_check': true, 'subscribers.check': true},
  'presets': {
    for (final e in _presets.entries)
      e.key: {'label': e.value.label, 'description': 'قالب ${e.value.label}', 'permissions': _serverPreset(e.value.on)},
  },
});

void main() {
  group('PermPreset.applyTo', () {
    test('كلّ قالبٍ من الخادم: المفاتيح المستقلّة تبقى على المحفوظ (true وfalse)، والباقي كما يقول القالب', () {
      for (final p in _catalog.presets.values) {
        final current = {'subscribers.add': true, 'reports.financial': false, ..._stored};
        final out = p.applyTo(current);
        for (final k in _roleFree) {
          expect(out[k], _stored[k], reason: '${p.key} ← $k');
        }
        for (final k in ['subscribers.view', 'subscribers.add', 'subscribers.activate', 'reports.financial']) {
          expect(out[k], _presets[p.key]!.on.contains(k), reason: '${p.key} ← $k');
        }
        expect(current['devices.deep_check'], isFalse, reason: 'لا يُعدّل ما أُعطي');
      }
    });

    test('مفتاحٌ مستقلّ غائبٌ عن الحاليّ يبقى غائباً (لا false من القالب) — الخادم يُبقيه على المحفوظ/الافتراضيّ', () {
      final p = _catalog.presets['cashier']!;
      expect(p.permissions['devices.deep_check'], isFalse, reason: 'القالب نفسه يحمله false');
      final out = p.applyTo(const {'subscribers.view': true});
      for (final k in _roleFree) {
        expect(out.containsKey(k), isFalse, reason: k);
      }
      expect(out['subscribers.activate'], isTrue);
    });
  });

  group('المحرّر', () {
    late SimServer server;
    setUpAll(simSetUpAll);

    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    Future<void> openAndSave(WidgetTester t, {required bool el, required String chip, required int id}) async {
      server.reply('PUT', '/api/v2/employees/$id', 200, {'success': true});
      // محرّر الساس يحمّل المدراء الفرعيّين للقيد (دوّارةٌ حتى يصل الردّ)
      server.reply('GET', '/api/v2/managers', 200, {'success': true, 'data': []});
      final emp = Employee.fromJson({
        'id': id,
        'username': 'emp.$id',
        'full_name': 'موظف',
        'is_active': 1,
        'permissions': {'subscribers.view': true, 'subscribers.add': true, 'reports.financial': false, ..._stored},
      })!;
      await pumpSim(t, _v,
          home: (_) => simLauncher((c) => showEmployeeEditorSheet(c, catalog: _catalog, employee: emp, isEarthlink: el)));
      await simOpen(t);
      await t.tap(find.textContaining('الصلاحيات ('));
      await t.pumpAndSettle();
      await t.tap(find.text(chip));
      await t.pumpAndSettle();
      // إشعار «تم تطبيق …» (الساس) يغطّي «حفظ» ثوانيَ — يُنتظر
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
    }

    Map<String, dynamic> sent(int id) =>
        Map<String, dynamic>.from(server.bodies('PUT', '/api/v2/employees/$id').single['permissions'] as Map);

    void tolerateListTile() {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('ListTile background color')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
    }

    var id = 60;
    for (final e in _presets.entries) {
      final pid = ++id;
      testWidgets('الساس — «${e.value.label}»: الفحصان وما عبر VPN والتنبيهات كما حُفظت، والقالب يضبط الباقي', (t) async {
        tolerateListTile();
        server = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'mgr'});
        ProviderService.debugSet(null);
        PermissionsService.debugSet(isEmployee: false);
        await openAndSave(t, el: false, chip: e.value.label, id: pid);
        final perms = sent(pid);
        for (final k in _roleFree) {
          expect(perms[k], _stored[k], reason: k);
        }
        expect(perms['subscribers.add'], e.value.on.contains('subscribers.add'));
        expect(perms['reports.financial'], e.value.on.contains('reports.financial'));
        expect(perms['subscribers.activate'], e.value.on.contains('subscribers.activate'));
        await simDrain(t);
      });
    }

    for (final p in ElEmployeePerms.presets) {
      final pid = ++id;
      testWidgets('ايرث لنك — «${p.label}»: الفحصان وما عبر VPN والتنبيهات كما حُفظت', (t) async {
        tolerateListTile();
        server = await simSetUp(secure: {'auth.admin_id': 'earthlink:135762', 'auth.admin_username': 'owner'});
        ProviderService.debugSet('earthlink');
        PermissionsService.debugSet(isEmployee: false);
        await openAndSave(t, el: true, chip: p.label, id: pid);
        final perms = sent(pid);
        for (final k in _roleFree) {
          expect(perms[k], _stored[k], reason: k);
        }
        expect(perms['subscribers.view'], isTrue);
        expect(perms['subscribers.add'], p.keys.contains('subscribers.add'));
        await simDrain(t);
      });
    }
  });
}
