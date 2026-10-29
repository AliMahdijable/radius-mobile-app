import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/devices/device_defaults_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// ⑦ (٢٩ أكتوبر — المالك: «نضيف ٣ اختيارات بقسم اعتمادات الأجهزة»): شاشة الاعتمادات أمام خادمٍ وهميّ — الإضافيّ
/// المحفوظ يظهر، الإضافة بحدّ اثنين لكلّ نوع، الحذف يعيد الترقيم، والحفظ يرسل القائمتين كما يفهمهما الخادم. القيم وهميّة.
void main() {
  late _Server server;

  setUpAll(() async {
    await loadAppFonts();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    final adapter = ApiClient.dio.httpClientAdapter;
    ApiClient.dio.httpClientAdapter = server;
    addTearDown(() => ApiClient.dio.httpClientAdapter = adapter);
  });

  Future<List<Object?>> open(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final popped = <Object?>[];
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    final r = await Navigator.of(c).push<bool>(MaterialPageRoute(builder: (_) => const DeviceDefaultsScreen()));
                    popped.add(r);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    return popped;
  }

  testWidgets('المحفوظ يظهر، والإضافة بحدّ اثنين، والحذف يعيد الترقيم، والحفظ يرسل القائمتين', (t) async {
    server.defaults = {
      'ontUsername': 'adm-ont',
      'ontPassword': 'adm-ont-p',
      'ontExtra': [
        {'username': 'x-1', 'password': 'x-1-p'},
      ],
    };
    final popped = await open(t);
    expect(find.text('اعتماد 2'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'x-1'), findsOneWidget);
    expect(find.text('إضافة اعتماد آخر'), findsNWidgets(2), reason: 'ONT فيه واحد من اثنين، وUBNT فارغ');

    await t.tap(find.text('إضافة اعتماد آخر').first);
    await t.pumpAndSettle();
    expect(find.text('اعتماد 3'), findsOneWidget);
    expect(find.text('إضافة اعتماد آخر'), findsOneWidget, reason: 'ثلاثةٌ لـONT ⇒ لا زرّ إضافة له');

    // الخانة الجديدة: آخر حقلَي يوزر/باسورد في قسم ONT (قبل قسم UBNT).
    final fields = find.byType(TextField);
    await t.enterText(fields.at(4), 'x-2');
    await t.enterText(fields.at(5), 'x-2-p');
    await t.tap(find.byTooltip('حذف هذا الاعتماد').first);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'حقلا المحذوف يُتخلّص منهما بعد الإطار لا وهما مرسومان');
    expect(find.text('اعتماد 3'), findsNothing);
    expect(find.text('اعتماد 2'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'x-2'), findsOneWidget, reason: 'الباقي صار «اعتماد 2»');
    expect(find.widgetWithText(TextField, 'x-1'), findsNothing);

    await t.ensureVisible(find.text('حفظ الاعتمادات'));
    await t.tap(find.text('حفظ الاعتمادات'));
    await t.pumpAndSettle();
    expect(server.saved, hasLength(1));
    final body = server.saved.single;
    expect(body['ontUsername'], 'adm-ont');
    expect(body['ontExtra'], [
      {'username': 'x-2', 'password': 'x-2-p'},
    ]);
    expect(body['ubntExtra'], isEmpty);
    expect(popped, [true]);
    await t.pump(const Duration(seconds: 4)); // حفظ كاش الفحص المؤجَّل بعد مسحه (اعتماداتٌ جديدة)
  });

  testWidgets('خانةٌ إضافيّة بلا يوزر لا تُرسل', (t) async {
    await open(t);
    await t.tap(find.text('إضافة اعتماد آخر').last);
    await t.pumpAndSettle();
    expect(find.text('اعتماد 2'), findsOneWidget);
    await t.ensureVisible(find.text('حفظ الاعتمادات'));
    await t.tap(find.text('حفظ الاعتمادات'));
    await t.pumpAndSettle();
    expect(server.saved.single['ubntExtra'], isEmpty);
    expect(server.saved.single['ontExtra'], isEmpty);
    await t.pump(const Duration(seconds: 4));
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(
        jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>,
      );
}

/// خادمٌ وهميّ بعقد `/api/admin/device-defaults` (GET يعيد المحفوظ، PUT يحفظ الجسم).
class _Server implements HttpClientAdapter {
  Map<String, Object?> defaults = {};
  final saved = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final Object reply;
    if (options.path == '/api/admin/device-defaults' && options.method == 'PUT') {
      saved.add(Map<String, dynamic>.from(options.data as Map));
      reply = {'success': true};
    } else if (options.path == '/api/admin/device-defaults') {
      reply = {'success': true, 'defaults': defaults};
    } else {
      reply = {'success': true};
    }
    return ResponseBody.fromString(jsonEncode(reply), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
