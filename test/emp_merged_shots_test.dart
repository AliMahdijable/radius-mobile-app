import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_pages_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'emp_merged/emp_merged_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «كل الصفحات» للموظّف — لقطاتٌ للمراجعة (٩ نوفمبر): «صفحاتي» بـ«كل الصفحات»، والمشتركون بشارات الصفحات، والرئيسيّة، وكتابةٌ
/// مقفلة — بعرضَي ٣٦٠ و٤١٢ فاتحاً وداكناً. بياناتٌ تجريبيّة وحدها. المخرجات: EMP_SHOTS أو /Users/mahdi/release_work/emp_merged_shots.
String _outDir() {
  final env = Platform.environment['EMP_SHOTS'] ?? '';
  return env.isNotEmpty ? env : visualOutDir(); // الافتراض build/visual_perm (مُتجاهَل بgit) — لا كتابة خارج المستودع
}

const _devices = [
  VisualDevice('360_light', Size(360, 780), 3),
  VisualDevice('360_dark', Size(360, 780), 3, dark: true),
  VisualDevice('412_light', Size(412, 892), 3),
  VisualDevice('412_dark', Size(412, 892), 3, dark: true),
];

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${_outDir()}/${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
}

/// جلسة الموظّف بأسماءٍ تجريبيّة (لا اسم حقيقيّ في اللقطة).
Future<EmpServer> _up() async {
  final srv = await empUp();
  const s = FlutterSecureStorage();
  await s.write(key: 'auth.display_name', value: 'موظّف تجريبيّ');
  await s.write(key: 'auth.admin_username', value: 'admin@alef');
  await ActiveCompany.saveFromLogin(
    sasUrl: '',
    adminId: '2251',
    loginUsername: 'emp.demo',
    adminUsername: 'admin@alef',
    isEmployee: true,
    label: nameA,
    sasCode: 'supernet',
  );
  return srv;
}

Future<void> _down(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 6));
  await empDown();
}

/// «صفحاتي» كما تُفتح فعلاً: ورقةٌ فوق الشاشة.
class _SheetHost extends StatefulWidget {
  const _SheetHost();
  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showEmployeePagesSheet(context);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: AppColors.bg, body: const SizedBox.expand());
}

void main() {
  setUpAll(visualSetUpAll);

  for (final d in _devices) {
    testWidgets('لقطة «صفحاتي» بـ«كل الصفحات» — ${d.tag}', (t) async {
      await _up();
      await pumpVisual(t, d, home: (_) => const _SheetHost());
      await settle(t, seconds: 3);
      expect(find.text('كل الصفحات'), findsOneWidget);
      await _shot(t, '1_my_pages_all_pages', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('لقطة المشتركين بشارات الصفحات — ${d.tag}', (t) async {
      await _up();
      await t.runAsync(MergedMode.enter);
      final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, d, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 4);
      expect(find.textContaining('كل الصفحات'), findsWidgets);
      await _shot(t, '2_subscribers_page_tags', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('لقطة الرئيسيّة — ${d.tag}', (t) async {
      await _up();
      await t.runAsync(MergedMode.enter);
      await pumpVisual(t, d, home: (_) => const DashboardScreen());
      await settle(t, seconds: 4);
      await _shot(t, '3_dashboard', d);
      expect(t.takeException(), isNull);
      await _down(t);
    });

    testWidgets('لقطة كتابةٍ مقفلة (تسديد لمشترك صفحةٍ أخرى) — ${d.tag}', (t) async {
      await _up();
      await t.runAsync(() => MergedMode.load(fresh: true));
      MergedMode.active.value = true;
      final s = Subscriber.fromJson(Map<String, dynamic>.from(pageRows[kB]![1])).withCompany(kB);
      await pumpVisual(t, d, home: (_) => SubscriberDetailScreen(sub: s));
      await settle(t, seconds: 3);
      await t.tap(find.text('تسديد').first);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(MergedMode.writeLockedText), findsOneWidget);
      await _shot(t, '4_locked_write', d);
      await settle(t, seconds: 3);
      expect(t.takeException(), isNull);
      await _down(t);
    });
  }
}
