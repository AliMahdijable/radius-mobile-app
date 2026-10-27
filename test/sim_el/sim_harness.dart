import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';
import 'package:rad_mysvcs/theme/typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_fonts.dart';
import 'package:rad_mysvcs/theme/date_picker_theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// محاكاة شاشات ايرث لنك — العدّة المشتركة.
//
// كلّ حالةٍ تُرسم كما يراها المدير: بالعربيّة (RTL) وبخطّ التطبيق الحقيقيّ
// وأيقوناته، بثيم التطبيق نفسه (نسخةٌ من `_buildTheme` في main.dart)، أمام
// خادمٍ وهميّ على `ApiClient.dio` — لا شبكة حقيقيّة أبداً. وتُرسم بثلاثة
// عروض (٣٢٠ · ٣٦٠ · ٣٩٠ × ٧٨٠) وبالوضعين.
//
// [simCheck] نقطة الفحص: يحفظ اللقطة أوّلاً (فتبقى حتى لو فشل ما بعدها)،
// ثمّ يفشل على أيّ استثناء (فيضان RenderFlex وغيره) وعلى أيّ نصٍّ تقنيّ أو
// إنجليزيّ خامٍ ظاهر، ويسجّل النصوص المقصوصة (SIM-TRUNC) للمراجعة.
// ═══════════════════════════════════════════════════════════════════════

/// ارتفاع الشاشة المنطقيّ لكلّ الحالات.
const double kSimHeight = 780;

/// عرضٌ × وضع.
@immutable
class SimVariant {
  const SimVariant(this.width, {required this.dark});
  final double width;
  final bool dark;

  String get tag => 'w${width.toInt()}_${dark ? 'dark' : 'light'}';

  @override
  String toString() => tag;
}

/// المصفوفة: ٣٢٠ · ٣٦٠ · ٣٩٠ × فاتح · داكن.
const simVariants = <SimVariant>[
  SimVariant(320, dark: false),
  SimVariant(320, dark: true),
  SimVariant(360, dark: false),
  SimVariant(360, dark: true),
  SimVariant(390, dark: false),
  SimVariant(390, dark: true),
];

/// يولّد اختباراً لكلّ تنويعة: `<screen>/<state> @<variant>`.
void simCase(
  String screen,
  String state,
  Future<void> Function(WidgetTester t, SimVariant v) body,
) {
  for (final v in simVariants) {
    testWidgets('$screen/$state @${v.tag}', (t) async {
      // ظلالٌ حقيقيّة في اللقطة (الإطار يرسمها كتلاً سوداء افتراضاً)، وتُعاد
      // قبل فحص ثوابت الإطار في آخر الاختبار.
      debugDisableShadows = false;
      try {
        await body(t, v);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

/// مفتاح جذر اللقطة — يلفّ التطبيق كلّه (الصفحات والأوراق والإشعارات).
const simRootKey = ValueKey<String>('sim-root');

/// خطوط التطبيق وأيقوناته + لا نقرة تقع على غير هدفها + سكوت سجلّ الترجمة.
Future<void> simSetUpAll() async {
  await loadAppFonts();
  await _loadIconFonts();
  WidgetController.hitTestWarningShouldBeFatal = true;
  EasyLocalization.logger.enableBuildModes = [];
}

/// Lucide (أيقونات التطبيق) + MaterialIcons (✕ وأيقونات الإشعار) — بلاها
/// تُرسم الأيقونات مربّعات في اللقطة.
Future<void> _loadIconFonts() async {
  Future<ByteData> bytes(String asset, String fallbackFile) async {
    try {
      return await rootBundle.load(asset);
    } catch (_) {
      final b = File(fallbackFile).readAsBytesSync();
      return ByteData.view(Uint8List.fromList(b).buffer);
    }
  }

  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(bytes('packages/lucide_icons_flutter/assets/lucide.ttf',
        'third_party/lucide_icons_flutter/assets/lucide.ttf'));
  await lucide.load();
  try {
    final material = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await material.load();
  } catch (_) {/* الأيقونات المادّيّة قليلة هنا — لا تُفشل المحاكاة */}
}

/// حال كلّ اختبار: جلسة ايرث لنك (`earthlink:5`) بتوكنٍ وهميّ، وخادمٌ جديد.
Future<SimServer> simSetUp({Map<String, String> secure = const {}}) async {
  FlutterSecureStorage.setMockInitialValues({
    'auth.token': 'sim-token',
    'auth.admin_id': 'earthlink:5',
    'auth.admin_username': 'mahdi.el',
    ...secure,
  });
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
  final server = SimServer();
  ApiClient.dio.httpClientAdapter = server;
  ApiClient.debugResetSessionEnd();
  return server;
}

// ═══════════════════════════ الثيم ═══════════════════════════

/// نسخة `_buildTheme` في `main.dart` (خاصّةٌ هناك) — ما يمسّ الرسم منها.
ThemeData simTheme(Brightness brightness) {
  final wasDark = AppColors.isDark;
  AppColors.setDarkMode(brightness == Brightness.dark);
  final base =
      brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: base.textTheme.apply(fontFamily: AppType.family),
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: AppColors.brand,
            onPrimary: AppColors.onBrand,
            surface: AppColors.surface,
            onSurface: AppColors.textHi,
            error: AppColors.error,
          )
        : ColorScheme.light(
            primary: AppColors.brand,
            onPrimary: AppColors.onBrand,
            surface: AppColors.surface,
            onSurface: AppColors.textHi,
            error: AppColors.error,
          ),
    datePickerTheme: appDatePickerTheme(),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceSheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.xl)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: Sp.xxl, vertical: Sp.xxl),
      titleTextStyle: AppType.sheetTitle(),
      contentTextStyle:
          AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
      actionsPadding: const EdgeInsets.fromLTRB(Sp.xl, Sp.sm, Sp.xl, Sp.lg),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, H.chip),
        padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
        textStyle: AppType.button(),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, H.chip),
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        foregroundColor: AppColors.textBody,
        textStyle: AppType.button(),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.brandSurface,
      contentTextStyle: AppType.body(color: AppColors.onBrand),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
  AppColors.setDarkMode(wasDark);
  return theme;
}

// ═══════════════════════════ التطبيق ═══════════════════════════

/// يرسم [home] داخل تطبيقٍ بثيم التطبيق وترجمته وعرض [v] ووضعه.
Future<void> pumpSim(
  WidgetTester t,
  SimVariant v, {
  required WidgetBuilder home,
  GlobalKey<NavigatorState>? navigatorKey,
  bool settle = true,
}) async {
  t.view.physicalSize = Size(v.width, kSimHeight);
  t.view.devicePixelRatio = 1.0;
  t.platformDispatcher.platformBrightnessTestValue =
      v.dark ? Brightness.dark : Brightness.light;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
  AppColors.setDarkMode(v.dark);
  addTearDown(() => AppColors.setDarkMode(false));
  final light = simTheme(Brightness.light);
  final dark = simTheme(Brightness.dark);
  await t.pumpWidget(RepaintBoundary(
    key: simRootKey,
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
          themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
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
  if (settle) await t.pumpAndSettle();
}

/// صفحةٌ خلف الأوراق: زرٌّ عربيّ يفتحها (لا «open» لاتينيّة في اللقطة).
const simOpenLabel = 'افتح';

Widget simLauncher(void Function(BuildContext c) open) => Scaffold(
      backgroundColor: AppColors.bg,
      body: Builder(
        builder: (c) => Center(
          child: TextButton(
            onPressed: () => open(c),
            child: const Text(simOpenLabel),
          ),
        ),
      ),
    );

/// يضغط زرّ الفتح وينتظر استقرار الورقة.
Future<void> simOpen(WidgetTester t) async {
  await t.tap(find.text(simOpenLabel));
  await t.pumpAndSettle();
}

/// يُفرغ مؤقّتات الإشعارات العائمة (أطولها ٢٠ث) قبل نهاية الاختبار.
Future<void> simDrain(WidgetTester t) async {
  await t.pump(const Duration(seconds: 30));
  await t.pumpAndSettle();
}

// ═══════════════════════════ نقطة الفحص ═══════════════════════════

/// اللقطة ثمّ الفحوص. [allow] نصوصٌ ظاهرة مقصودة تُستثنى من فحص النصّ الخام
/// (يُذكر سببها عند المستدعي).
Future<void> simCheck(
  WidgetTester t,
  SimVariant v,
  String screen,
  String state, {
  Iterable<Pattern> allow = const [],
}) async {
  final where = '$screen/$state @${v.tag}';
  await expectLater(
    find.byKey(simRootKey),
    matchesGoldenFile('shots/$screen/${state}__${v.tag}.png'),
  );
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء/FlutterError في $where:\n$ex');
  final bad = simRawTextViolations(allow: allow);
  expect(bad, isEmpty, reason: 'نصٌّ تقنيّ/خامٌ ظاهر في $where: $bad');
  _logTruncations(t, where);
}

/// نصوصٌ لا يجوز أن يراها المدير: استثناءات ورموز خادم ومفاتيح ترجمة
/// وروابط و«null»… الأنماط تُطابَق بعد نزع محارف العزل الاتّجاهيّ.
final simForbidden = <String, RegExp>{
  'Exception': RegExp('exception', caseSensitive: false),
  'null': RegExp(r'\bnull\b', caseSensitive: false),
  'http/url': RegExp(r'https?:|\bhttp\b|www\.', caseSensitive: false),
  'Error': RegExp(r'\berror\b', caseSensitive: false),
  'Instance of': RegExp('instance of', caseSensitive: false),
  'undefined/NaN': RegExp(r'\bundefined\b|\bNaN\b|\bInfinity\b'),
  'dart type': RegExp(
      r"type '|is not a subtype|NoSuchMethod|StateError|TypeError|RangeError|FormatException|Dio"),
  'path/stack': RegExp(r'/api/|\.dart\b|#\d+\s+\w'),
  'braces': RegExp(r'[{}\[\]]'),
  'i18n key': RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$'),
  'status=': RegExp(r'\b(status|statusCode|code)\s*[=:]\s*\d', caseSensitive: false),
  'SERVER_CODE': RegExp(r'\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\b'),
};

final _isolates = RegExp(r'[\u2066-\u2069\u200E\u200F\u202A-\u202E]');

/// اسم النمط الممنوع الذي يطابقه [text] (بعد نزع محارف العزل)، أو `null`.
String? simForbiddenMatch(String text) {
  final clean = text.replaceAll(_isolates, '');
  for (final e in simForbidden.entries) {
    if (e.value.hasMatch(clean)) return e.key;
  }
  return null;
}

/// كلّ نصٍّ ظاهر (`RichText` على المسرح) يطابق نمطاً ممنوعاً.
List<String> simRawTextViolations({Iterable<Pattern> allow = const []}) {
  final out = <String>[];
  for (final text in simVisibleTexts()) {
    if (allow.any((a) => a.allMatches(text).isNotEmpty)) continue;
    final hit = simForbiddenMatch(text);
    if (hit != null) out.add('[$hit] «$text»');
  }
  return out;
}

/// نصٌّ يطابق [s] بعد نزع محارف العزل الاتّجاهيّ (`iso()` في core/util/bidi).
Finder simText(String s, {bool skipOffstage = true}) => find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll(_isolates, '') ==
              s,
      description: 'نصّ «$s» (بلا محارف العزل)',
      skipOffstage: skipOffstage,
    );

/// نصوص `RichText` الظاهرة الآن بلا محارف العزل.
List<String> simVisibleTexts() => [
      for (final e in find.byType(RichText).evaluate())
        (e.widget as RichText).text.toPlainText().replaceAll(_isolates, ''),
    ].where((s) => s.trim().isNotEmpty).toList();

void _logTruncations(WidgetTester t, String where) {
  final cut = <String>{};
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderParagraph && ro.didExceedMaxLines) {
      cut.add(ro.text.toPlainText().replaceAll(_isolates, ''));
    }
  }
  for (final s in cut) {
    stdout.writeln('SIM-TRUNC|$where|$s');
  }
}

// ═══════════════════════════ الخادم الوهميّ ═══════════════════════════

/// ردٌّ وهميّ: JSON افتراضاً، أو HTML (صفحة بوّابة) بـ[SimReply.html].
@immutable
class SimReply {
  const SimReply(this.status, [this.body = const {'success': true}])
      : html = null;
  const SimReply.html(this.status, String this.html) : body = null;

  final int status;
  final Object? body;
  final String? html;

  ResponseBody toBody() => html != null
      ? ResponseBody.fromString(html!, status, headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        })
      : ResponseBody.fromString(jsonEncode(body), status, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
}

typedef SimHandler = FutureOr<SimReply> Function(RequestOptions req);

/// خادمٌ وهميّ بعقد `/api/**`: مساراتٌ مسجَّلة بـ«METHOD path»، وما لم
/// يُسجَّل يردّ ٤٠٤ ويُذكر في [unhandled]. [hold] يُمسك ردّ مسارٍ حتى
/// [release] — لما يجري **أثناء** الانتظار. ومعالجٌ يرمي `DioException`
/// يحاكي ما لا ردّ له (مهلة/انقطاع).
class SimServer implements HttpClientAdapter {
  final _routes = <String, SimHandler>{};
  final _holds = <String, Completer<void>>{};

  /// كلّ طلبٍ وصل، بترتيبه.
  final requests = <RequestOptions>[];

  /// مساراتٌ طُلبت ولا معالج لها (ردّت ٤٠٤).
  final unhandled = <String>[];

  static String _key(String method, String path) =>
      '${method.toUpperCase()} $path';

  void on(String method, String path, SimHandler handler) =>
      _routes[_key(method, path)] = handler;

  void reply(String method, String path, int status, Object? body) =>
      on(method, path, (_) => SimReply(status, body));

  void hold(String method, String path) =>
      _holds[_key(method, path)] = Completer<void>();

  void release(String method, String path) {
    final c = _holds.remove(_key(method, path));
    if (c != null && !c.isCompleted) c.complete();
  }

  List<RequestOptions> calls(String method, String path) => requests
      .where((r) => _key(r.method, r.path) == _key(method, path))
      .toList();

  List<Map<String, dynamic>> bodies(String method, String path) => [
        for (final r in calls(method, path))
          Map<String, dynamic>.from(r.data as Map),
      ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final key = _key(options.method, options.path);
    final gate = _holds[key];
    if (gate != null) await gate.future;
    final handler = _routes[key];
    if (handler == null) {
      unhandled.add(key);
      return const SimReply(404, {'success': false, 'message': 'غير موجود'})
          .toBody();
    }
    final r = await handler(options);
    return r.toBody();
  }

  @override
  void close({bool force = false}) {}
}

/// مهلةٌ بلا ردّ — كما يرميها المحوّل الحقيقيّ بعد `receiveTimeout`.
Never simTimeout(RequestOptions o) => throw DioException(
      requestOptions: o,
      type: DioExceptionType.receiveTimeout,
      message: 'receive timeout',
    );

/// الترجمات من القرص مباشرةً (كاختبارات المستودع) — `Future.value` لا
/// `SynchronousFuture`: المكتبة تجمع المحمّلات بـ`Future.wait`.
class SimDiskLoader extends AssetLoader {
  const SimDiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>);
}
