import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/l10n/iq_material_localizations.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/widgets/app_date_picker.dart';
import 'package:rad_mysvcs/core/widgets/copyable.dart';
import 'package:rad_mysvcs/theme/date_picker_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart' show SimDiskLoader, simSetUpAll;

/// المالك ٢٤ أكتوبر (صورة «اختر الفترة»): المنتقي يملأ نافذة الحاسبة، بأشهرٍ مصريّة («أكتوبر») وفيروزيٍّ ليس من
/// التطبيق — و«معلومات المتّصلين والجهاز (ماك، آيبي…) اجعلهن قابلات للنسخ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // خطّ التطبيق الحقيقيّ — خطّ الاختبار الافتراضيّ يرسم كلّ حرفٍ مربّعاً بعرضه فيُقاس النصّ العربيّ أعرض بكثير.
  setUpAll(simSetUpAll);

  group('أسماء الأشهر العراقيّة في تقاويم Material', () {
    late MaterialLocalizations l;
    setUpAll(() async {
      l = await const IqMaterialLocalizationsDelegate().load(const Locale('ar'));
    });

    test('الشهر والسنة، اليوم والشهر، والتاريخ الكامل', () {
      final d = DateTime(2026, 10, 24); // السبت
      expect(l.formatMonthYear(d), 'تشرين الأوّل 2026');
      expect(l.formatShortMonthDay(d), '24 تشرين الأوّل');
      expect(l.formatShortDate(d), '24 تشرين الأوّل 2026');
      expect(l.formatMediumDate(d), 'السبت، 24 تشرين الأوّل');
      expect(l.formatFullDate(d), 'السبت، 24 تشرين الأوّل 2026');
      expect(l.formatMonthYear(DateTime(2027, 1, 5)), 'كانون الثاني 2027');
      for (final m in ['أكتوبر', 'يناير', 'نوفمبر']) {
        expect(l.formatMonthYear(DateTime(2026, 10)), isNot(contains(m)));
      }
    });

    test('ما سوى التواريخ يبقى ترجمة فلاتر العربيّة', () {
      expect(l, isA<MaterialLocalizationAr>());
      expect(l.cancelButtonLabel, isNotEmpty);
      expect(const IqMaterialLocalizationsDelegate().isSupported(const Locale('en')), isFalse);
    });
  });

  Future<void> pumpPicker(WidgetTester t, Size size, {DateTimeRange? range}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // ترجمات التطبيق محمّلة (كالتطبيق): بلاها يظهر مفتاح «common.apply» الطويل مكان «تطبيق» فيفيض الرأس زوراً.
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    EasyLocalization.logger.enableBuildModes = [];
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const SimDiskLoader(),
      child: Builder(builder: (ctx) => MaterialApp(
      locale: ctx.locale,
      supportedLocales: ctx.supportedLocales,
      localizationsDelegates: [
        const IqMaterialLocalizationsDelegate(),
        ...ctx.localizationDelegates,
      ],
      theme: ThemeData(useMaterial3: true, datePickerTheme: appDatePickerTheme()),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppDateRangePicker(
                context: ctx,
                firstDate: DateTime(2026, 1, 1),
                lastDate: DateTime(2026, 12, 31),
                initialDateRange: range ?? DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 24)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ))));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('الحاسبة: المنتقي نافذةٌ بالوسط بعرضٍ معقول، بالأشهر العراقيّة', (t) async {
    await pumpPicker(t, const Size(1400, 900));
    final frame = t.getSize(find.byType(AppDateRangeFrame).first);
    final dialog = t.getRect(find.descendant(of: find.byType(AppDateRangeFrame), matching: find.byType(Dialog)).first);
    expect(dialog.width, lessThanOrEqualTo(AppDateRangeFrame.maxWidth + 0.5));
    expect(dialog.width, lessThan(frame.width));
    expect(find.textContaining('تشرين الأوّل'), findsWidgets);
    expect(find.textContaining('أكتوبر'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('الهاتف: كما يرسمه Material (صفحةٌ كاملة)', (t) async {
    await pumpPicker(t, const Size(390, 844));
    final dialog = t.getRect(find.byType(Dialog).first);
    expect(dialog.width, 390);
    expect(find.textContaining('تشرين الأوّل'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('أطول فترة («كانون الثاني – كانون الأوّل») على هاتف ٣٢٠ بلا فيض', (t) async {
    await pumpPicker(t, const Size(320, 640),
        range: DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 12, 31)));
    expect(find.textContaining('كانون الثاني'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  group('النسخ', () {
    String? copied;
    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
          return null;
        },
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      AppPlatform.debugIsDesktop = null;
    });

    Widget app() => const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Copyable(label: 'الماك', value: 'AA:BB:CC:DD:EE:FF', child: Text('AA:BB:CC:DD:EE:FF')),
            ),
          ),
        );

    testWidgets('الحاسبة: الزرّ الأيمن ينسخ، وتلميحٌ يقوله', (t) async {
      AppPlatform.debugIsDesktop = true;
      await t.pumpWidget(app());
      expect(find.byType(Tooltip), findsOneWidget);
      await t.tap(find.text('AA:BB:CC:DD:EE:FF'), buttons: kSecondaryButton);
      await t.pump(const Duration(milliseconds: 600));
      expect(copied, 'AA:BB:CC:DD:EE:FF');
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('الهاتف: الضغط المطوّل ينسخ، بلا تلميح', (t) async {
      AppPlatform.debugIsDesktop = false;
      await t.pumpWidget(app());
      expect(find.byType(Tooltip), findsNothing);
      await t.longPress(find.text('AA:BB:CC:DD:EE:FF'));
      await t.pump(const Duration(milliseconds: 600));
      expect(copied, 'AA:BB:CC:DD:EE:FF');
      await t.pump(const Duration(seconds: 3));
    });
  });
}
