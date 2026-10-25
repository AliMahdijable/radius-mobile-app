import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cards_api.dart' show CardsState;
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/app_version.dart';
import 'package:rad_mysvcs/services/employee_session.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sim_el/sim_harness.dart' show simTheme, SimDiskLoader;
import '../support/app_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════
// لقطات الصلاحيّات — عدّةٌ ترسم شاشات التطبيق الحقيقيّة (MainShell ·
// الرئيسيّة · «قوائم أخرى» · التقارير · الإعدادات · ورقة «+») بخطّ التطبيق
// وأيقوناته، بالعربيّة (RTL)، وبمجموعة صلاحيّاتٍ مختارة، أمام خادمٍ وهميّ على
// `ApiClient.dio` (لا شبكة حقيقيّة)، وتحفظ كلّ شاشةٍ صورة PNG للنظر.
//
// ليست ممّا يُشحن — أداةُ مراجعةٍ بصريّة لما يراه الموظّف قبل التعديل وبعده.
// التشغيل والمخرجات في README.md بجانبها.
// ═══════════════════════════════════════════════════════════════════════

/// مجلّد الإخراج: `--dart-define=VISUAL_OUT=…` أوّلاً، ثمّ متغيّر البيئة
/// `VISUAL_OUT`، وإلّا `build/visual_perm` داخل المستودع.
String visualOutDir() {
  const fromDefine = String.fromEnvironment('VISUAL_OUT');
  if (fromDefine.isNotEmpty) return fromDefine;
  final env = Platform.environment['VISUAL_OUT'] ?? '';
  if (env.isNotEmpty) return env;
  return '${Directory.current.path}/build/visual_perm';
}

// ═══════════════════════════ الأحجام ═══════════════════════════

@immutable
class VisualDevice {
  const VisualDevice(this.tag, this.size, this.dpr, {this.dark = false});
  final String tag;
  final Size size; // منطقيّ
  final double dpr;
  final bool dark;
}

const phone = VisualDevice('', Size(430, 932), 3);
const phoneDark = VisualDevice('_dark', Size(430, 932), 3, dark: true);
const ipad = VisualDevice('_ipad', Size(1024, 1366), 2);

/// هاتفٌ بالعرض نفسه وطولٍ يكفي القائمة كلّها — لترى كلّ العناصر في صورةٍ واحدة
/// («قوائم أخرى» والإعدادات أطول من شاشة). التخطيط نفسه، والفرق الطول وحده.
const phoneTall = VisualDevice('_full', Size(430, 2400), 2);

// ═══════════════════════════ السيناريوهات ═══════════════════════════

enum Actor { owner, elEmployee, sasSubAdmin }

@immutable
class Scenario {
  const Scenario({
    required this.id,
    required this.title,
    required this.actor,
    required this.provider,
    this.keys = const {},
    this.managerCaps = const {},
  });

  /// بادئة اسم الملفّ: `S2_el_emp_subs`.
  final String id;
  final String title;
  final Actor actor;

  /// `earthlink` أو `null` (ساس).
  final String? provider;

  /// مفاتيح الموظّف (‏Actor.elEmployee).
  final Map<String, bool> keys;

  /// قدرات المدير الفرعيّ المعياريّة (‏Actor.sasSubAdmin): الغائب = مسموح.
  final Map<String, bool> managerCaps;

  bool get isEl => provider == 'earthlink';

  /// هل يسمح الخادم بهذا المفتاح لهذا الفاعل؟ (نسخة `Perms.has` للخادم الوهميّ.)
  bool allows(String key) {
    switch (actor) {
      case Actor.owner:
        return true;
      case Actor.elEmployee:
        return keys[key] == true;
      case Actor.sasSubAdmin:
        return managerCaps[key] ?? true;
    }
  }

  bool allowsAny(Iterable<String> ks) => ks.any(allows);
}

/// S1 · مالك ايرث لنك — كلّ الصلاحيّات (المرجع: ما يراه المالك اليوم).
const s1Owner = Scenario(
  id: 'S1_owner',
  title: 'مالك ايرث لنك — كلّ الصلاحيّات',
  actor: Actor.owner,
  provider: 'earthlink',
);

/// S1b · مالك ساس (سوبرنت) — مرجع S4.
const s1bSasOwner = Scenario(
  id: 'S1b_sas_owner',
  title: 'مالك ساس — كلّ الصلاحيّات',
  actor: Actor.owner,
  provider: null,
);

/// S2 · موظّف ايرث لنك بـ`subscribers.view` وحدها — لقطة المالك (10.png).
const s2ElEmpSubs = Scenario(
  id: 'S2_el_emp_subs',
  title: 'موظّف ايرث لنك — subscribers.view وحدها',
  actor: Actor.elEmployee,
  provider: 'earthlink',
  keys: {'subscribers.view': true},
);

/// S3 · موظّف ايرث لنك بلا أيّ مفتاح.
const s3ElEmpNone = Scenario(
  id: 'S3_el_emp_none',
  title: 'موظّف ايرث لنك — بلا صلاحيّات',
  actor: Actor.elEmployee,
  provider: 'earthlink',
);

/// S4 · مدير فرعيّ في الساس — قدراتٌ قليلة من ACL الساس، والباقي ممنوع.
const s4SasSub = Scenario(
  id: 'S4_sas_subadmin',
  title: 'مدير فرعيّ ساس — صلاحيّات قليلة',
  actor: Actor.sasSubAdmin,
  provider: null,
  managerCaps: {
    'subscribers.view': true,
    'subscribers.activate': true,
    'subscribers.extend': true,
    'subscribers.add': false,
    'subscribers.delete': false,
    'subscribers.edit': false,
    'subscribers.pay_debt': false,
    'subscribers.add_debt': false,
    'subscribers.show_password': false,
    'managers.view': false,
    'packages.view': false,
    'packages.edit_prices': false,
    'reports.financial': false,
    // «توزيع الباقات» بمفتاحه منذ ٢٥ أكتوبر — مطفأٌ كبقيّة تقارير هذا الدور.
    'reports.packages': false,
    'reports.activations': false,
    'reports.manager_debts': false,
    'reports.sessions': false,
    'reports.expenses': false,
    'employees.view': false,
    'discounts.view': false,
    'subscriber_prices.view': false,
    'settlements.view': false,
    'settings.edit': false,
    'whatsapp.broadcast': false,
    'whatsapp.templates': false,
  },
);

const allScenarios = [s1Owner, s1bSasOwner, s2ElEmpSubs, s3ElEmpNone, s4SasSub];

// ═══════════════════════════ الإعداد ═══════════════════════════

/// خطوط التطبيق + أيقوناته (Lucide · MaterialIcons · CupertinoIcons).
Future<void> visualSetUpAll() async {
  await loadAppFonts();
  await _loadIconFonts();
  EasyLocalization.logger.enableBuildModes = [];
}

Future<ByteData> _bytes(String asset, List<String> fallbacks) async {
  try {
    return await rootBundle.load(asset);
  } catch (_) {
    for (final f in fallbacks) {
      final file = File(f);
      if (file.existsSync()) {
        return ByteData.view(Uint8List.fromList(file.readAsBytesSync()).buffer);
      }
    }
    rethrow;
  }
}

/// جذر Flutter SDK — لخطّ MaterialIcons إن لم يكن في حزمة الاختبار.
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_tester داخل <root>/bin/cache/artifacts/engine/<plat>/
  final exe = Platform.resolvedExecutable;
  final i = exe.indexOf('/bin/cache/');
  return i > 0 ? exe.substring(0, i) : null;
}

Future<void> _loadIconFonts() async {
  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(_bytes('packages/lucide_icons_flutter/assets/lucide.ttf',
        ['third_party/lucide_icons_flutter/assets/lucide.ttf']));
  await lucide.load();

  final root = _flutterRoot();
  final material = FontLoader('MaterialIcons')
    ..addFont(_bytes('fonts/MaterialIcons-Regular.otf', [
      if (root != null)
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]));
  await material.load();

  try {
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'));
    await cupertino.load();
  } catch (_) {/* قليلة الاستعمال — لا تُفشل اللقطة */}
}

/// يضبط الجلسة والصلاحيّات والمزوّد والخادم الوهميّ لسيناريو.
Future<VisualServer> visualSetUp(Scenario s) async {
  final emp = s.actor == Actor.elEmployee;
  final adminId = s.isEl ? 'earthlink:5' : 'supernet:12';
  FlutterSecureStorage.setMockInitialValues({
    'auth.token': 'visual-token',
    'auth.admin_id': adminId,
    'auth.admin_username': emp ? 'admin@najaf948' : (s.isEl ? 'admin@najaf948' : 'mahdi'),
    'auth.display_name': emp ? 'علي مهدي' : 'مهدي العبيدي',
    if (emp) 'auth.is_employee': '1',
    // جلسة موظّفٍ مباشرة (دخول موظّف ايرث لنك) — لا حساب ولا اشتراك.
    if (emp) 'employee.direct_session': '1',
  });
  SharedPreferences.setMockInitialValues({});
  // «الإصدار» في الإعدادات — بلاه يبقى «…» (لا منصّة في الاختبار).
  PackageInfo.setMockInitialValues(
    appName: 'MyServices Pro',
    packageName: 'net.mysvcs.app',
    version: '3.0.0',
    buildNumber: '154',
    buildSignature: '',
  );
  await AppVersion.load();
  await EasyLocalization.ensureInitialized();
  // شارة الكارتات ثابتةٌ في العمليّة — التطبيق يمسحها مع كلّ جلسة
  // (`SessionManager`)، فلا يرث سيناريو شارة سابقه.
  CardsState.reset();

  PermissionsService.debugSet(
    isEmployee: emp,
    permissions: s.keys,
    managerRestricted: s.actor == Actor.sasSubAdmin,
    managerCaps: s.managerCaps,
  );
  ProviderService.debugSet(s.provider);
  await EmployeeSession.restore();
  SubscribersApi.clearAllCaches();
  await ActiveCompany.saveFromLogin(
    sasUrl: s.isEl ? '' : 'https://reseller-supernet.net',
    adminId: adminId,
    loginUsername: emp ? 'ali.m' : (s.isEl ? 'admin@najaf948' : 'mahdi'),
    adminUsername: 'admin@najaf948',
    isEmployee: emp,
    label: s.isEl ? 'ايرث لنك' : 'سوبرنت',
    sasCode: s.isEl ? 'earthlink' : 'supernet',
  );

  final server = VisualServer(s);
  ApiClient.dio.httpClientAdapter = server;
  return server;
}

Future<void> visualTearDown() async {
  await ActiveCompany.clear();
  await EmployeeSession.clear(newSession: true);
  PermissionsService.debugReset();
  ProviderService.debugSet(null);
  SubscribersApi.clearAllCaches();
}

// ═══════════════════════════ التطبيق ═══════════════════════════

const visualRootKey = ValueKey<String>('visual-root');

/// يرسم [home] داخل تطبيقٍ بثيم التطبيق وترجمته (عربيّ RTL) وحجم [d].
Future<void> pumpVisual(
  WidgetTester t,
  VisualDevice d, {
  required WidgetBuilder home,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  t.view.physicalSize = d.size * d.dpr;
  t.view.devicePixelRatio = d.dpr;
  // شقّ الشاشة والمؤشّر السفليّ كهاتفٍ حقيقيّ — الترويسة والشريط يأخذان حشوتهما.
  t.view.padding = FakeViewPadding(top: 47 * d.dpr, bottom: 34 * d.dpr);
  t.view.viewPadding = FakeViewPadding(top: 47 * d.dpr, bottom: 34 * d.dpr);
  t.platformDispatcher.platformBrightnessTestValue =
      d.dark ? Brightness.dark : Brightness.light;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  AppColors.setDarkMode(d.dark);
  addTearDown(() => AppColors.setDarkMode(false));
  final light = simTheme(Brightness.light);
  final dark = simTheme(Brightness.dark);
  await t.pumpWidget(RepaintBoundary(
    key: visualRootKey,
    child: EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const SimDiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          themeMode: d.dark ? ThemeMode.dark : ThemeMode.light,
          theme: light,
          darkTheme: dark,
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
            child: child ?? const SizedBox.shrink(),
          ),
          home: Builder(builder: home),
        ),
      ),
    ),
  ));
}

/// يُنضج الشاشة: الترجمة، والجلب، والحركات، ومؤقّت التحديث (٧٠٠مث) وتبريده
/// (٣ث). بخطواتٍ محدودة لا `pumpAndSettle` — في الشاشات شمعاتٌ تتكرّر.
Future<void> settle(WidgetTester t, {int seconds = 5}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// يحفظ اللقطة `<scenario>_<screen><device>.png` بدقّة الجهاز (‎@3x للهاتف)
/// ثمّ يُفشل على أيّ استثناء. والسجلّ `<name>.requests.txt` بجانبها.
Future<void> shoot(
  WidgetTester t,
  Scenario s,
  String screen,
  VisualDevice d,
  VisualServer server,
) async {
  final name = '${s.id}_$screen${d.tag}';
  final boundary =
      t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${visualOutDir()}/$name.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  server.writeLog('$name.requests.txt');
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $name:\n$ex');
}

// ═══════════════════════════ الخادم الوهميّ ═══════════════════════════

/// خادمٌ وهميّ يردّ ردوداً معقولة لمسارات الشاشات، و403 `PERMISSION_DENIED`
/// لما لا يملك الفاعل مفتاحه (كبوّابة الموظّفين الحقيقيّة). ويسجّل كلّ طلب —
/// ليُرى أنّ القسم المقفل لا يكلّف نداءً.
class VisualServer implements HttpClientAdapter {
  VisualServer(this.s);
  final Scenario s;

  /// كلّ طلبٍ وصل: «METHOD path → status».
  final log = <String>[];

  void writeLog(String fileName) {
    final f = File('${visualOutDir()}/$fileName');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${s.id} — ${s.title}\n${log.join('\n')}\n');
  }

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  static ResponseBody _denied() => _json(403, {
        'success': false,
        'code': 'PERMISSION_DENIED',
        'message': 'ليس لديك صلاحيّة',
      });

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final r = _route(o);
    log.add('${o.method} ${o.path} → ${r.statusCode}');
    return r;
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _route(RequestOptions o) {
    final p = o.path;
    final get = o.method.toUpperCase() == 'GET';

    // ── المشتركون (الحلقة + المدينون + القائمة) ──
    if (get && p == '/api/v2/subscribers') {
      if (!s.allows('subscribers.view')) return _denied();
      return _json(200, {'success': true, 'data': fixtureSubscribers});
    }
    if (get && p == '/api/v2/online-users') {
      if (!s.allows('subscribers.view')) return _denied();
      return _json(200, {'success': true, 'data': const []});
    }
    if (get && p == '/api/v2/packages') {
      return _json(200, {'success': true, 'data': fixturePackages});
    }

    // ── الإيرادات ──
    if (get && p == '/api/reports/finance') {
      if (!s.allows('reports.financial')) return _denied();
      return _json(200, {
        'success': true,
        'data': {
          'totals': {'total_payments': 1285000},
          'timeseries': _revenueSeries(),
        },
      });
    }

    // ── «توزيع الباقات» (#٥) — بمفتاح التقرير الماليّ؛ الكلفة والربح للمالك وحده (owner من الخادم) ──
    if (get && p == '/api/reports/finance/packages') {
      if (!s.allows('reports.financial')) return _denied();
      final owner = s.actor == Actor.owner;
      Map<String, Object?> row(String key, String name, int total, int active, int acts, int ext, int revenue, int est) => {
            'key': key,
            'name': name,
            'profile_id': int.tryParse(key.substring(2)),
            'price': 35000,
            'subscribers_total': total,
            'subscribers_active': active,
            'activations': acts,
            'sync_activations': 0,
            'extensions': ext,
            'revenue': revenue,
            if (owner) ...{'unit_cost': 21000, 'cost': revenue * 6 ~/ 10, 'profit_total': revenue * 4 ~/ 10, 'profit_estimated': est},
          };
      return _json(200, {
        'success': true,
        'data': {
          'owner': owner,
          'cost_exempt': false,
          'provider': s.isEl ? 'earthlink' : 'sas4',
          'rows': [
            row('p:5', 'FTTH 50 ميغا', 412, 365, 38, 12, 1330000, 5110000),
            row('p:7', 'D-Active 75 ميغا العائليّة', 260, 231, 25, 9, 1375000, 4389000),
            row('p:9', 'Gaming 100', 74, 66, 11, 3, 825000, 1518000),
            row('p:3', 'اقتصاديّة 25', 58, 31, 6, 1, 150000, 310000),
            row('p:11', 'أعمال 200', 9, 8, 2, 0, 300000, 320000),
          ],
          'totals': {
            'packages': 5,
            'subscribers_total': 813,
            'subscribers_active': 701,
            'activations': 82,
            'sync_activations': 0,
            'extensions': 25,
            'revenue': 3980000,
            if (owner) ...{'cost': 2388000, 'profit_total': 1592000, 'cost_rows': 107, 'cost_known_rows': 107, 'cost_complete': true, 'profit_estimated': 11647000},
          },
        },
        'unavailable_parts': const [],
      });
    }

    // ── الرصيد والكارتات — الخادم يقنّع الرصيد بلا reports.financial ──
    if (get && p == '/api/v2/admin-widgets') {
      final money = s.allows('reports.financial');
      return _json(200, {
        'success': true,
        'balance': money ? 2450000 : null,
        'points': money ? 120 : null,
        if (!s.isEl) 'cards': {'enabled': true, 'remaining': 340},
      });
    }
    if (get && p == '/api/v2/cards/summary') {
      // شكل الخادم الحقيقيّ (`CardsSummary.fromJson`): الحقول في الجذر.
      return _json(200, {
        'success': true,
        'enabled': !s.isEl,
        'totals': {'remaining': 340},
        'profiles': const [],
        'series': const [],
      });
    }

    // ── آخر النشاطات ──
    if (get && p == '/api/activities/daily-activations') {
      if (!s.allows('reports.daily_activations')) return _denied();
      return _json(200, {
        'success': true,
        'counts': {'activations': 4, 'extensions': 2},
        'data': fixtureActivities(),
      });
    }

    // ── الواتساب ──
    if (get && p.startsWith('/api/whatsapp/connection-status/')) {
      if (!s.allowsAny(const [
        'whatsapp.connect',
        'whatsapp.send',
        'whatsapp.broadcast',
        'whatsapp.templates',
        'whatsapp.schedules',
      ])) {
        return _denied();
      }
      return _json(200, {
        'success': true,
        'connected': true,
        'status': 'connected',
        'phone': '9647701234567',
      });
    }

    // ── نطاق العرض: لا أقسام مخفيّة ──
    if (get && p == '/api/admin/view-scope') {
      return _json(200, {
        'success': true,
        'managers': const [],
        'sections': const [],
      });
    }

    // ── موظّف: /me ──
    if (get && p == '/api/v2/employees/me') {
      return _json(200, {
        'success': true,
        'isEmployee': s.actor == Actor.elEmployee,
        'permissions': s.keys,
      });
    }

    // كلّ ما سواه: فارغٌ ناجح — لا خطأ يلوّث اللقطة، ويبقى في السجلّ.
    return _json(200, {'success': true, 'data': const []});
  }
}

// ═══════════════════════════ البيانات ═══════════════════════════

Map<String, Object?> _row(
  int idx,
  String user, {
  required String first,
  required String last,
  required String profile,
  required int remaining,
  bool online = false,
  String? notes,
}) {
  final exp = DateTime.now().add(Duration(days: remaining));
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'idx': '$idx',
    'username': user,
    'firstname': first,
    'lastname': last,
    'phone': '0770${1000000 + idx}',
    'profile_name': profile,
    'profile_id': 7,
    'expiration': '${exp.year}-${two(exp.month)}-${two(exp.day)} 10:00:00',
    'remaining_days': remaining,
    'online_status': online ? 1 : 0,
    'enabled': 1,
    if (notes != null) 'notes': notes,
  };
}

/// ١٧ مشتركاً: نشطون ومتّصلون ومنتهون وقربوا الانتهاء ومدينون.
final fixtureSubscribers = <Map<String, Object?>>[
  _row(1, 'ali1@najaf', first: 'علي', last: 'حسن الموسوي', profile: 'Economy', remaining: 20, online: true),
  _row(2, 'zainab.k@najaf', first: 'زينب', last: 'كاظم', profile: 'Standard', remaining: 2),
  _row(3, 'hussein77@najaf', first: 'حسين', last: 'عبد الأمير', profile: 'Plus', remaining: -12, notes: '-35000'),
  _row(4, 'mustafa.office@najaf', first: 'مكتب', last: 'مصطفى', profile: 'Business', remaining: 68, online: true),
  _row(5, 'abbas.r@najaf', first: 'عبّاس', last: 'رضا', profile: 'Economy', remaining: 11),
  _row(6, 'maryam90@najaf', first: 'مريم', last: 'جاسم', profile: 'Standard', remaining: -3),
  _row(7, 'haider.s@najaf', first: 'حيدر', last: 'سالم', profile: 'Plus', remaining: 25, online: true, notes: '-20000'),
  _row(8, 'noor.h@najaf', first: 'نور', last: 'الهدى', profile: 'Economy', remaining: -30),
  _row(9, 'kareem.t@najaf', first: 'كريم', last: 'طالب', profile: 'Standard', remaining: 7),
  _row(10, 'sajad.m@najaf', first: 'سجّاد', last: 'محمّد', profile: 'Economy', remaining: -1),
  _row(11, 'fatima.a@najaf', first: 'فاطمة', last: 'علي', profile: 'Plus', remaining: 15),
  _row(12, 'ahmed.k@najaf', first: 'أحمد', last: 'كامل', profile: 'Standard', remaining: -8, notes: '-15000'),
  _row(13, 'yaser.n@najaf', first: 'ياسر', last: 'نعمة', profile: 'Economy', remaining: 1),
  _row(14, 'ruqaya.j@najaf', first: 'رقيّة', last: 'جواد', profile: 'Economy', remaining: -20),
  _row(15, 'muntadhar@najaf', first: 'منتظر', last: 'عادل', profile: 'Business', remaining: 40),
  _row(16, 'hawra.b@najaf', first: 'حوراء', last: 'باسم', profile: 'Standard', remaining: -5),
  _row(17, 'qasim.d@najaf', first: 'قاسم', last: 'داود', profile: 'Plus', remaining: 9, online: true),
];

final fixturePackages = [
  {'id': 7, 'name': 'Economy', 'price': 25000},
  {'id': 8, 'name': 'Standard', 'price': 35000},
  {'id': 9, 'name': 'Plus', 'price': 45000},
];

List<Map<String, Object?>> fixtureActivities() {
  final now = DateTime.now();
  String at(int minsAgo) {
    final d = now.subtract(Duration(minutes: minsAgo));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:00';
  }

  return [
    {
      'action': 'ACTIVATE',
      'action_description': 'تفعيل نقدي — Economy (25,000)',
      'user_firstname': 'علي',
      'user_lastname': 'حسن الموسوي',
      'user_username': 'ali1@najaf',
      'amount': 25000,
      'created_at': at(12),
      'admin_username': 'admin@najaf948',
    },
    {
      'action': 'EXTEND',
      'action_description': 'تمديد 3 أيّام',
      'user_firstname': 'زينب',
      'user_lastname': 'كاظم',
      'user_username': 'zainab.k@najaf',
      'amount': 0,
      'created_at': at(48),
      'acting_employee_full_name': 'علي مهدي',
    },
    {
      'action': 'DEBT_PAY',
      'action_description': 'تسديد دين',
      'user_firstname': 'حيدر',
      'user_lastname': 'سالم',
      'user_username': 'haider.s@najaf',
      'amount': 10000,
      'created_at': at(95),
      'admin_username': 'admin@najaf948',
    },
  ];
}

List<Map<String, Object?>> _revenueSeries() {
  final now = DateTime.now();
  const amounts = [
    90000, 140000, 60000, 210000, 175000, 120000, 230000, 80000, 150000, 30000
  ];
  return [
    for (var i = 0; i < amounts.length; i++)
      {
        'date': now
            .subtract(Duration(days: amounts.length - 1 - i))
            .toIso8601String()
            .substring(0, 10),
        'payments_sum': '${amounts[i]}.00',
      },
  ];
}
