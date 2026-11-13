import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/api/employee_presence_api.dart';
import 'package:rad_mysvcs/screens/employees/employee_presence_widgets.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'employee_ledger/ledger_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «الموظف المتّصل الآن» — لقطاتٌ للمراجعة (١٤ نوفمبر): قسم الموظفين بشارة «متّصل» ونقطة الصورة، «نشاط الموظفين»، و«نشاط الموظف» —
/// بعرض ٣٢٠/٣٦٠/٣٩٠ فاتحاً وداكناً. بياناتٌ تجريبيّة وحدها. المخرجات: VISUAL_OUT (أو build/visual_perm المُتجاهَل بgit).
const _devices = [
  VisualDevice('320', Size(320, 760), 3),
  VisualDevice('360', Size(360, 800), 3),
  VisualDevice('390_dark', Size(390, 844), 3, dark: true),
];

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${visualOutDir()}/presence_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $name ${d.tag}:\n$ex');
}

void main() {
  setUpAll(visualSetUpAll);

  late LedgerServer server;

  Future<void> up() async {
    await visualSetUp(s1bSasOwner);
    server = LedgerServer()
      ..presenceOn = true
      ..withDisabledEmployee = true;
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugSet(isEmployee: false);
    EmployeeLedgerState.reset();
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    EmployeeLedgerState.reset();
    await visualTearDown();
  }

  for (final d in _devices) {
    testWidgets('قسم الموظفين بالحضور ${d.tag}', (t) async {
      await up();
      await pumpVisual(t, d, home: (_) => const EmployeesScreen());
      await settle(t, seconds: 2);
      await _shot(t, '01_employees', d);
      await t.tap(find.byKey(const ValueKey('employees-presence-badge')));
      await settle(t, seconds: 1);
      await _shot(t, '02_overview', d);
      await down(t);
    });

    testWidgets('نشاط الموظف ${d.tag}', (t) async {
      await up();
      final detail = PresenceDetail.fromJson(presenceDetailJson())!;
      await pumpVisual(
        t,
        d,
        home: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => EmployeeActivitySheet(employeeId: 7, name: 'أحمد', loader: () async => (data: detail, message: null)),
              ),
              child: const Text('افتح'),
            ),
          ),
        ),
      );
      await settle(t, seconds: 1);
      await t.tap(find.text('افتح'));
      await settle(t, seconds: 1);
      await _shot(t, '03_activity', d);
      await down(t);
    });
  }
}
