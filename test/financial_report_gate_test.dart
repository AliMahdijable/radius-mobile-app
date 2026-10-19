import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// التقرير الماليّ لا يُطلب خلف قفل «لا صلاحيّة» (٣.٠.٣+١٦٣).
///
/// الحالة تُبنى ولو أقفل [ReportPermissionGate] الشاشة، فكان `_load()` في
/// `initState` يطلب `/api/reports/finance` ويرتدّ ٤٠٣ بلا أن يراه أحد (تدقيق المدير
/// المقيَّد ١٨ أكتوبر). الآن لا طلب بلا الصلاحيّة؛ وصلاحيّةٌ تصل والشاشة مفتوحة
/// (تحديث القدرات بعد الإقلاع) تطلبه مرّةً حينها — لا دوّارةً بلا طلب.
const _v = SimVariant(390, dark: false);
const _finance = '/api/reports/finance';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'next-gen:175'});
    ProviderService.debugSet(null);
    server.reply('GET', _finance, 200, {
      'success': true,
      'data': {'kpis': <String, Object?>{}, 'recentLogs': <Object?>[]},
    });
    server.reply('GET', '/api/v2/managers', 200, {'success': true, 'data': []});
    server.reply('GET', '/api/v2/employees', 200, {'success': true, 'data': []});
  });

  tearDown(PermissionsService.debugReset);

  Future<void> open(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => const FinancialReportScreen());
    expect(t.takeException(), isNull);
  }

  // نصّ `reports.no_permission` بالعربيّة (الترجمة تُحمَّل مع الشاشة لا قبلها).
  final locked = find.text('لا تملك صلاحية لهذا التقرير');

  testWidgets('🚨 مدير مقيَّد بخريطةٍ قديمة (reports.financial=false): لا طلب خلف القفل',
      (t) async {
    // debugSet يضبط الخريطة كما هي (بلا إسقاط المتقاعد) — آليّة الحارس وحدها.
    PermissionsService.debugSet(
      isEmployee: false,
      managerRestricted: true,
      managerCaps: const {'reports.financial': false},
    );
    await open(t);

    expect(locked, findsOneWidget);
    expect(server.calls('GET', _finance), isEmpty);
    expect(server.requests, isEmpty, reason: 'ولا أيّ طلبٍ آخر من الشاشة');
  });

  testWidgets('🚨 موظّف بلا reports.financial: لا طلب', (t) async {
    PermissionsService.debugSet(isEmployee: true);
    await open(t);

    expect(locked, findsOneWidget);
    expect(server.calls('GET', _finance), isEmpty);
  });

  testWidgets('🚨 صلاحيّةٌ تصل والشاشة مفتوحة: يُطلب التقرير مرّةً ويُعرض',
      (t) async {
    PermissionsService.debugSet(isEmployee: true);
    await open(t);
    expect(server.calls('GET', _finance), isEmpty);

    PermissionsService.debugSet(
      isEmployee: true,
      permissions: const {'reports.financial': true},
    );
    await t.pumpAndSettle();
    expect(locked, findsNothing);
    expect(server.calls('GET', _finance), hasLength(1));
    expect(find.text('الإيراد النقدي الإجمالي'), findsOneWidget,
        reason: 'البيانات معروضة لا دوّارةٌ معلّقة');

    // تغيّرٌ آخر في الصلاحيّات لا يكرّر الطلب.
    PermissionsService.debugSet(
      isEmployee: true,
      permissions: const {'reports.financial': true, 'subscribers.view': true},
    );
    await t.pumpAndSettle();
    expect(server.calls('GET', _finance), hasLength(1));
  });

  testWidgets('مسموح من البداية: طلبٌ واحد كما كان', (t) async {
    PermissionsService.debugSet(isEmployee: false);
    await open(t);

    expect(locked, findsNothing);
    expect(server.calls('GET', _finance), hasLength(1));
    expect(find.text('الإيراد النقدي الإجمالي'), findsOneWidget);
  });

  testWidgets('إغلاق الشاشة يفكّ المستمع (لا طلب بعد الإغلاق)', (t) async {
    PermissionsService.debugSet(isEmployee: true);
    await open(t);
    await pumpSim(t, _v, home: (_) => simLauncher((_) {}));
    PermissionsService.debugSet(
      isEmployee: true,
      permissions: const {'reports.financial': true},
    );
    await t.pumpAndSettle();
    expect(server.calls('GET', _finance), isEmpty);
    expect(t.takeException(), isNull);
  });
}
