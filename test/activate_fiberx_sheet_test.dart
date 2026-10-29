import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// فايبر اكس في التطبيق (٢٩ أكتوبر): شيت التفعيل بوضع «فايبر اكس» أمام خادمٍ وهميّ بعقد activation-data/activate نفسه.
///
/// ما يحرسه: تجديد الحاليّة بلا change_type ولا profile_id؛ باقةٌ أخرى ⇒ الزرّ مقفلٌ حتى «حالاً/عند الانتهاء» صريحاً ثمّ
/// profile_id + change_type؛ «تفعيلٌ مكرّر» عندهم (FIBERX_COOLOFF) ⇒ تأكيدٌ صريح يُعيد بـconfirmCooloff وحده؛ والمجهول
/// (FIBERX_OUTCOME_UNKNOWN) يقفل الزرّ بلا إعادة.
const _uuid = '0b0d6c4e-1a2b-4c3d-9e8f-001122334455';

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
    ApiClient.dio.httpClientAdapter = server;
    CardsState.reset();
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final sub = Subscriber.fromJson({
      'idx': _uuid,
      'username': 'fxu',
      'firstname': 'علي',
      'profile_id': 5,
      'profile_name': 'لايت',
    });
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
          home: Scaffold(
            body: Builder(
              builder: (c) => Center(
                child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')),
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
  }

  Future<void> tapFooter(WidgetTester t) async {
    final f = find.text('تجديد الآن');
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
    await t.tap(f.last);
    await t.pumpAndSettle();
  }

  Future<void> drain(WidgetTester t) async {
    await t.pump(const Duration(seconds: 9));
    await t.pumpAndSettle();
  }

  testWidgets('تجديد الحاليّة: بلا change_type ولا profile_id ولا confirmCooloff، والسعر بعد الخصم وكلفة فايبر اكس ظاهرة', (t) async {
    await open(t);
    expect(find.text('35,000 د.ع'), findsWidgets, reason: 'المستحقّ = البيع − الخصم');
    expect(find.text('كلفة الباقة عند فايبر اكس'), findsOneWidget);
    expect(find.text('متى تبدأ الباقة الجديدة؟'), findsNothing, reason: 'الحاليّة ⇒ لا توقيت');
    await tapFooter(t);
    final b = server.activateBodies.single;
    expect(b['paymentType'], 'non-cash');
    for (final k in ['change_type', 'profile_id', 'confirmCooloff', 'method']) {
      expect(b.containsKey(k), isFalse, reason: k);
    }
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    await drain(t);
  });

  testWidgets('باقةٌ أخرى: الزرّ مقفلٌ حتى التوقيت، ثمّ profile_id + change_type «عند الانتهاء»', (t) async {
    await open(t);
    final picker = find.byType(PackagePickerField);
    await t.ensureVisible(picker);
    await t.pumpAndSettle();
    await t.tap(picker);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('برو').last); // الاسم بعزلٍ اتّجاهيّ (iso)
    await t.pumpAndSettle();
    expect(find.text('متى تبدأ الباقة الجديدة؟'), findsOneWidget);
    expect(find.textContaining('اختر متى تبدأ'), findsOneWidget);
    await tapFooter(t);
    expect(server.activateBodies, isEmpty, reason: 'بلا توقيتٍ صريح لا طلب');
    await t.tap(find.text('عند الانتهاء'));
    await t.pumpAndSettle();
    await tapFooter(t);
    final b = server.activateBodies.single;
    expect([b['profile_id'], b['change_type'], b['paymentType']], [20, 'expiry', 'non-cash']);
    await drain(t);
  });

  testWidgets('«تفعيلٌ مكرّر» عند فايبر اكس: تأكيدٌ صريح يعيد بـconfirmCooloff وحده؛ والرفض لا يرسل شيئاً', (t) async {
    server.activateReplies = [
      (409, {'success': false, 'code': 'FIBERX_COOLOFF', 'message': 'فُعّل قبل 2 دقيقة (الانتظار 5). للمتابعة أكّد.'}),
      (200, {'success': true}),
    ];
    await open(t);
    await tapFooter(t);
    expect(find.text('تفعيلٌ مكرّر عند فايبر اكس'), findsOneWidget);
    expect(find.textContaining('يخصم محفظتك مرّةً أخرى'), findsOneWidget);
    await t.tap(find.text('متابعة التفعيل'));
    await t.pumpAndSettle();
    expect(server.activateBodies.length, 2);
    expect(server.activateBodies.first.containsKey('confirmCooloff'), isFalse);
    expect(server.activateBodies.last['confirmCooloff'], isTrue);
    await drain(t);
  });

  testWidgets('المجهول (FIBERX_OUTCOME_UNKNOWN): الزرّ يُقفل «راجع انتهاء المشترك أوّلاً» بلا إعادة', (t) async {
    server.activateReplies = [
      (409, {'success': false, 'code': 'FIBERX_OUTCOME_UNKNOWN', 'message': 'ما نعرف إذا تمّ التفعيل — افحص حالة المشترك'}),
    ];
    await open(t);
    await tapFooter(t);
    expect(find.text('راجع انتهاء المشترك أوّلاً'), findsWidgets);
    expect(server.activateBodies.length, 1);
    await drain(t);
  });
}

class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(File('assets/translations/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>);
}

class _Server implements HttpClientAdapter {
  List<(int, Map<String, dynamic>)> activateReplies = [];
  final _requests = <RequestOptions>[];

  List<Map<String, dynamic>> get activateBodies => _requests
      .where((r) => r.path.endsWith('/activate'))
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _requests.add(options);
    final (int, Map<String, dynamic>) reply;
    if (options.path == '/api/v2/subscribers/$_uuid/activation-data') {
      reply = (200, {
        'success': true,
        'data': {
          'provider': 'fiberx',
          'idx': _uuid,
          'username': 'fxu',
          'profile_name': 'لايت',
          'profile_id': 13,
          'user_price': 40000,
          'base_price': 40000,
          'price_after_discount': 35000,
          'discount_amount': 5000,
          'price_source': 'sell_price',
          'custom_price': null,
          'overridden_discount': 0,
          'needs_repricing': false,
          'current_balance': 0,
          'manager_balance': 500000,
          'packages': [
            {'id': 13, 'name': 'لايت', 'price': 40000, 'cost': 35000, 'days': 30},
            {'id': 20, 'name': 'برو', 'price': 50000, 'cost': 50000, 'days': 30},
          ],
          'package_change_allowed': true,
        },
      });
    } else if (options.path == '/api/v2/subscribers/$_uuid/activate') {
      reply = activateReplies.isNotEmpty ? activateReplies.removeAt(0) : (200, {'success': true});
    } else {
      reply = (404, {'success': false});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
