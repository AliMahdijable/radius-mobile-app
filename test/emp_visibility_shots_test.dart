import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_editor_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'employee_ledger/ledger_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «ما يشوفه الموظّف» (٢٣ نوفمبر — المالك: «المدير يقدر يخلي الموظف ما يشوف الديون او ما يشوف اليوزرية… ونطين الصور»):
/// لقطات المراجعة لقسم الصلاحيّات الجديد في محرّر الموظّف. تُكتب حين يُعطى VISUAL_OUT وحده.
const _devices = [
  VisualDevice('390', Size(390, 844), 3),
  VisualDevice('390_dark', Size(390, 844), 3, dark: true),
  VisualDevice('320', Size(320, 720), 3),
];

/// الكتالوج كما سيرسله الخادم: القسم الجديد بعد «المشتركون»، وكلّ مفتاحٍ بسطرٍ يقول أين يختفي.
final Map<String, Object> catalogJson = {
  'permissions': {
    'subscribers.view': {'label': 'عرض المشتركين', 'category': 'subscribers'},
    'subscribers.activate': {'label': 'تفعيل مشترك', 'category': 'subscribers'},
    'subscribers.pay_debt': {'label': 'تسديد دين', 'category': 'subscribers'},
    'see.debts': {
      'label': 'يشوف ديون المشتركين',
      'category': 'see',
      'hint': 'إذا انطفى: لا مبالغ ولا «مديون» بالقائمة والكرت والتجديد والرئيسيّة والتقارير — ويبقى يسدّد',
    },
    'see.usernames': {
      'label': 'يشوف يوزر المشترك',
      'category': 'see',
      'hint': 'إذا انطفى: الاسم العربي بداله بكلّ الشاشات والتقارير والوصل — والبحث باليوزر يشتغل',
    },
    'see.phones': {
      'label': 'يشوف هاتف المشترك',
      'category': 'see',
      'hint': 'إذا انطفى: بلا رقم ولا أزرار اتصال وواتساب — ورسائل واتسابك توصل',
    },
    'see.counts': {
      'label': 'يشوف أعداد المشتركين',
      'category': 'see',
      'hint': 'إذا انطفى: بلا كارت المشتركين بالرئيسيّة ولا أعداد التبويبات',
    },
    'see.balance': {
      'label': 'يشوف رصيد الصفحة',
      'category': 'see',
      'hint': 'إذا انطفى: بلا كارت الرصيد والنقاط بالرئيسيّة',
    },
    'reports.financial': {'label': 'تقرير مالي', 'category': 'reports'},
    'reports.daily_activations': {'label': 'التفعيلات اليومية', 'category': 'reports'},
  },
  'categories': {
    'subscribers': {'label': 'المشتركون'},
    'see': {'label': 'ما يشوفه الموظّف'},
    'reports': {'label': 'التقارير'},
  },
  'defaults': {
    'subscribers.view': true,
    'subscribers.activate': true,
    'subscribers.pay_debt': true,
    'see.debts': true,
    'see.usernames': true,
    'see.phones': true,
    'see.counts': true,
    'see.balance': true,
  },
  'presets': <String, Object>{},
};

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final out = Platform.environment['VISUAL_OUT'];
  if (out == null || out.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('$out/empvis_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

void main() {
  setUpAll(visualSetUpAll);

  for (final d in _devices) {
    testWidgets('محرّر الموظّف — «ما يشوفه الموظّف» ${d.tag}', (t) async {
      await visualSetUp(s1bSasOwner);
      ApiClient.dio.httpClientAdapter = LedgerServer();
      PermissionsService.debugSet(isEmployee: false, permissions: const {});
      EmployeeLedgerState.reset();
      final catalog = PermissionsCatalog.fromJson(catalogJson);
      // موظّفٌ يجدّد ويسدّد، والمدير طفّى عنه الديون والهاتف
      final emp = Employee.fromJson({
        'id': 7,
        'username': 'emp1',
        'full_name': 'أحمد',
        'is_active': true,
        'permissions': {
          'subscribers.view': true,
          'subscribers.activate': true,
          'subscribers.pay_debt': true,
          'see.debts': false,
          'see.usernames': true,
          'see.phones': false,
          'see.counts': true,
          'see.balance': false,
          'reports.daily_activations': true,
        },
      })!;
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showEmployeeEditorSheet(c, catalog: catalog, employee: emp),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 2);
      await t.tap(find.textContaining('الصلاحيات ('));
      await settle(t, seconds: 1);
      final list = find.byType(ListView).last;
      for (var i = 0; i < 10 && find.text('ما يشوفه الموظّف').evaluate().isEmpty; i++) {
        await t.drag(list, const Offset(0, -200));
        await settle(t, seconds: 1);
      }
      expect(find.text('ما يشوفه الموظّف'), findsOneWidget);
      await t.ensureVisible(find.text('ما يشوفه الموظّف'));
      await settle(t, seconds: 1);
      await _shot(t, '01_editor', d);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 4));
      EmployeeLedgerState.reset();
      await visualTearDown();
    });
  }
}
