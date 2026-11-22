import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/employee_ledger_api.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'employee_ledger/ledger_fixture.dart';

/// شارة «مقيَّد» على بطاقة الموظّف (٢٢ نوفمبر — «موظّف ايرث لنك تابع لمدير فرعي»): تظهر للساس كما كانت ولايرث لنك الآن
/// (يوزر الحساب التابع فيه @ أصلاً ⇒ بلا «@@»)، ولا تظهر لفايبر اكس (لا مدراء فرعيّون هناك).
void main() {
  late LedgerServer server;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = LedgerServer()..ledgerFeature = false;
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugReset();
    EmployeeLedgerState.reset();
  });

  tearDown(() async {
    ProviderService.debugSet(null);
    await ActiveCompany.clear();
    PermissionsService.debugReset();
    EmployeeLedgerState.reset();
  });

  Widget app(Widget child) => EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en')],
        path: 'assets/translations',
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        saveLocale: false,
        assetLoader: const LedgerDiskLoader(),
        child: Builder(
          builder: (c) => MaterialApp(
            locale: c.locale,
            supportedLocales: c.supportedLocales,
            localizationsDelegates: c.localizationDelegates,
            home: Directionality(textDirection: TextDirection.rtl, child: child),
          ),
        ),
      );

  Future<void> pumpScreen(WidgetTester t) async {
    t.view.physicalSize = const Size(640, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(const EmployeesScreen()));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Map<String, dynamic> emp(int id, String user, {String? scope, String? scopeName}) => {
        'id': id,
        'username': user,
        'full_name': 'موظف $id',
        'is_active': true,
        'permissions': {'subscribers.view': true},
        if (scope != null) 'scope_admin_id': scope,
        if (scopeName != null) 'scope_admin_username': scopeName,
      };

  Future<void> company(String provider, String adminId, String code) async {
    ProviderService.debugSet(provider);
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: adminId,
      loginUsername: 'owner',
      adminUsername: 'owner',
      isEmployee: false,
      label: provider,
      sasCode: code,
    );
  }

  testWidgets('ايرث لنك: الشارة بيوزر الحساب التابع كما هو (بلا @@)، وغير المقيَّد بلا شارة', (t) async {
    await company('earthlink', 'earthlink:153357', 'earthlink');
    server.employeesList = [
      emp(41, 'emp.tabi', scope: 'earthlink:153574', scopeName: 'admin@T-Akrm'),
      emp(42, 'emp.free'),
    ];
    await pumpScreen(t);
    expect(find.text('مقيَّد بـadmin@T-Akrm'), findsOneWidget);
    expect(find.textContaining('@@'), findsNothing);
    expect(find.textContaining('مقيَّد بـ'), findsOneWidget, reason: 'غير المقيَّد بلا شارة');
  });

  testWidgets('ايرث لنك بلا يوزرٍ محفوظ للحساب التابع ⇒ معرّفه (كالساس)', (t) async {
    await company('earthlink', 'earthlink:153357', 'earthlink');
    server.employeesList = [emp(41, 'emp.tabi', scope: 'earthlink:153574')];
    await pumpScreen(t);
    expect(find.text('مقيَّد بـ@earthlink:153574'), findsOneWidget);
  });

  testWidgets('الساس كما كان: «مقيَّد بـ@يوزر»', (t) async {
    await company('sas4', '2', 'supernet');
    server.employeesList = [emp(41, 'emp.sas', scope: '5', scopeName: 'sub.five')];
    await pumpScreen(t);
    expect(find.text('مقيَّد بـ@sub.five'), findsOneWidget);
  });

  testWidgets('فايبر اكس: لا شارة ولو حمل الصفّ نطاقاً (لا مدراء فرعيّون هناك)', (t) async {
    await company('fiberx', 'fiberx:12', 'fiberx');
    server.employeesList = [emp(41, 'emp.fx', scope: 'fiberx:99', scopeName: 'x')];
    await pumpScreen(t);
    expect(find.textContaining('مقيَّد بـ'), findsNothing);
  });
}
