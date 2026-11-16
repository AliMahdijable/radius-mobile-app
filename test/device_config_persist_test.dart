import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/device_config_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart';

/// محاكي «إعدادات جهاز المشترك» بالكود الحقيقيّ (الورقة + كرت الجهاز + [DeviceConfigApi]) أمام خادمٍ يحفظ ويقرأ كما يفعل خادمنا
/// حرفاً (server.js PUT/GET /api/subscribers/:u/device + device-batch، database/db.js upsertSubscriberDevice: PUT يكتب الحقول
/// الخمسة كلّها — الغائب null — والجهاز الثاني حين يحمل الطلب مفاتيحه).
///
/// المالك (١٥ نوفمبر، المشترك samer@m): «من اخزن الاعتماد يدوي مجرد اخرج وادخل يروح الحفظ». السجلّ: خمس حفظاتٍ من هاتف الوكيل
/// خزّنت صفّاً فارغاً كلّه. السبب: اليوزر وكلمة السرّ كُتبا في خانتَي «الجهاز الثاني» بلا آيبي ولا منفذ ⇒ الورقة أهملتهما بصمت
/// وأُغلقت كأنّها حفظت؛ وحفظٌ كهذا من جهازٍ يمسح ما حفظه جهازٌ آخر في الحقول الأولى (الخادم يكتب الكلّ).
const _v = SimVariant(390, dark: false);
const _u = 'samer@m';
const _hint = 'من «بيانات الدخول» إذا فارغ';

class _Devices {
  final rows = <String, Map<String, Object?>>{};
  int _id = 7000;

  /// القراءة تتعذّر (الخادم يردّ 503 كما يردّ حين تتعذّر هويّة الطلب).
  bool down = false;

  String path(String u) => '/api/subscribers/$u/device';

  void mount(SimServer s, Iterable<String> users) {
    for (final u in users) {
      s.on('GET', path(u), (o) {
        if (down) {
          throw DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 503, data: {'success': false}));
        }
        return SimReply(200, {'success': true, 'device': rows[u]});
      });
      s.on('PUT', path(u), (o) {
        final b = Map<String, dynamic>.from(o.data as Map);
        String? v(Object? x) => x == null || '$x'.isEmpty ? null : '$x';
        final cur = rows[u];
        final next = <String, Object?>{
          'id': cur?['id'] ?? ++_id,
          'deviceType': v(b['deviceType']),
          'username': v(b['username']),
          'password': v(b['password']),
          'customIp': v(b['customIp']),
          'notes': v(b['notes']),
          'updatedAt': '2026-11-14T23:33:43.000Z',
          'secondAddress': cur?['secondAddress'],
          'secondUsername': cur?['secondUsername'],
          'secondPassword': cur?['secondPassword'],
        };
        if (b.containsKey('secondAddress') || b.containsKey('secondUsername') || b.containsKey('secondPassword')) {
          next['secondAddress'] = v(b['secondAddress']);
          next['secondUsername'] = v(b['secondUsername']);
          next['secondPassword'] = v(b['secondPassword']);
        }
        rows[u] = next;
        return const SimReply(200, {'success': true});
      });
      s.on('DELETE', path(u), (_) {
        rows.remove(u);
        return const SimReply(200, {'success': true});
      });
    }
    s.on('POST', '/api/v2/subscribers/device-batch', (o) {
      final asked = [for (final x in (o.data as Map)['usernames'] as List) '$x'];
      return SimReply(200, {
        'success': true,
        'configs': {
          for (final u in asked)
            if (rows[u] != null) u: rows[u],
        },
      });
    });
  }
}

/// حقول الورقة بترتيبها: ٠ يوزر · ١ كلمة السرّ · ٢ آيبي · ٣ منفذ · ٤ آيبي الثاني · ٥ منفذه · ٦ يوزره · ٧ كلمة سرّه · ٨ ملاحظات.
const _fUser = 0, _fPass = 1, _fPort2 = 5, _fUser2 = 6, _fPass2 = 7;
Finder _f(int i) => find.byType(TextField).at(i);
String _text(WidgetTester t, int i) => t.widget<TextField>(_f(i)).controller!.text;

void main() {
  late SimServer server;
  late _Devices dev;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2868', 'auth.admin_username': 'mgr'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    DeviceConfigApi.clearAllCaches();
    dev = _Devices()..mount(server, [_u, 'saidnaser']);
  });

  tearDown(() {
    PermissionsService.debugReset();
    DeviceConfigApi.clearAllCaches();
  });

  Widget home(String user) => simLauncher((ctx) => showAppSheet<bool>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        builder: (_) => DeviceConfigSheet(username: user),
      ));

  Future<void> open(WidgetTester t) async {
    await t.tap(find.text(simOpenLabel));
    await t.pumpAndSettle();
    expect(find.byType(DeviceConfigSheet), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'انتهى تحميل الإعداد');
  }

  Future<void> save(WidgetTester t) async {
    await t.tap(find.text('حفظ وفحص الجهاز'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
  }

  /// ما يفعله كرت الجهاز وصفحة المشترك بعد كلّ حفظ: عدّة قراءاتٍ معاً للإعداد (الفحص + الملاحظات + الجهاز الثاني + العنوان).
  Future<void> cardReads(WidgetTester t, {String user = _u}) async {
    for (var i = 0; i < 4; i++) {
      unawaited(DeviceConfigApi.fetchConfig(user));
    }
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.pump();
  }

  List<Map<String, dynamic>> puts([String u = _u]) => server.bodies('PUT', dev.path(u));

  testWidgets('المشكلة: يوزر وكلمة مرور في خانتَي «الجهاز الثاني» بلا آيبي ولا منفذ ⇒ لا تُغلق الورقة كأنّها حفظت، ولا يُرسل شيء', (t) async {
    await pumpSim(t, _v, home: (_) => home(_u));
    await open(t);
    await t.ensureVisible(_f(_fUser2));
    await t.enterText(_f(_fUser2), 'admin');
    await t.enterText(_f(_fPass2), 'r0uter');
    await save(t);
    expect(find.byType(DeviceConfigSheet), findsOneWidget, reason: 'الورقة باقية — ما كُتب لم يُهمل بصمت');
    expect(puts(), isEmpty, reason: 'لا حفظ لصفٍّ فارغ');
    expect(dev.rows[_u], isNull);
    expect(find.textContaining('الجهاز الثاني يحتاج عنوان IP أو منفذ'), findsOneWidget, reason: 'الرسالة تقول ما ينقص وأين يُكتب اعتماد الجهاز نفسه');
    expect(find.byKey(const ValueKey('second-needs-address')), findsOneWidget);
    expect([_text(t, _fUser2), _text(t, _fPass2)], ['admin', 'r0uter'], reason: 'ما كتبه باقٍ أمامه');

    // يكتب المنفذ المحوّل للراوتر ⇒ السطر يزول والحفظ يحمل اعتماد الجهاز الثاني
    await t.pump(const Duration(seconds: 5));
    await t.ensureVisible(_f(_fPort2));
    await t.enterText(_f(_fPort2), '8080');
    await t.pump();
    expect(find.byKey(const ValueKey('second-needs-address')), findsNothing);
    await save(t);
    expect(find.byType(DeviceConfigSheet), findsNothing);
    expect(puts().single, {'notes': null, 'secondAddress': ':8080', 'secondUsername': 'admin', 'secondPassword': 'r0uter'});
    expect([dev.rows[_u]!['secondAddress'], dev.rows[_u]!['secondUsername'], dev.rows[_u]!['secondPassword']], [':8080', 'admin', 'r0uter']);
    await cardReads(t);

    // خرج ودخل: المحفوظ ظاهر
    await open(t);
    expect([_text(t, _fPort2), _text(t, _fUser2), _text(t, _fPass2)], ['8080', 'admin', 'r0uter']);
    await simDrain(t);
  });

  testWidgets('اعتماد الجهاز الثاني بلا عنوان: مسحُه يكفي للحفظ؛ وكلمة مرور وحدها بلا عنوان تُرفض كذلك', (t) async {
    await pumpSim(t, _v, home: (_) => home(_u));
    await open(t);
    await t.ensureVisible(_f(_fPass2));
    await t.enterText(_f(_fPass2), 'r0uter');
    await save(t);
    expect(find.byType(DeviceConfigSheet), findsOneWidget);
    expect(puts(), isEmpty);
    // قصد جهاز المشترك نفسه: ينقلها للحقل الأوّل ويمسح الثاني
    await t.pump(const Duration(seconds: 5));
    await t.enterText(_f(_fPass2), '');
    await t.pump();
    expect(find.byKey(const ValueKey('second-needs-address')), findsNothing);
    await t.ensureVisible(_f(_fPass));
    await t.enterText(_f(_fPass), 'r0uter');
    await save(t);
    expect(find.byType(DeviceConfigSheet), findsNothing);
    expect(dev.rows[_u]!['password'], 'r0uter');
    expect(dev.rows[_u]!['secondPassword'], isNull);
    await simDrain(t);
  });

  testWidgets('كلمة مرور وحدها في الحقل الأوّل (راوتر بلا يوزر): تُحفظ وتبقى بعد الخروج والدخول، وحفظٌ بلا تغيير لا يمسحها', (t) async {
    await pumpSim(t, _v, home: (_) => home(_u));
    await open(t);
    expect(_text(t, _fPass), '');
    await t.enterText(_f(_fPass), 'r0uter');
    await save(t);
    expect(find.byType(DeviceConfigSheet), findsNothing, reason: 'الورقة أُغلقت بعد الحفظ');
    expect([dev.rows[_u]!['username'], dev.rows[_u]!['password']], [null, 'r0uter']);
    await cardReads(t);
    for (var i = 0; i < 3; i++) {
      await open(t);
      expect(_text(t, _fPass), 'r0uter', reason: 'الفتحة ${i + 2}: كلمة المرور المحفوظة ظاهرة');
      await save(t);
      expect(dev.rows[_u]!['password'], 'r0uter', reason: 'الحفظ ${i + 2}: لا يمسح');
      await cardReads(t);
    }
    await simDrain(t);
  });

  testWidgets('يوزر وكلمة مرور: يُحفظان ويظهران بعد الخروج والدخول', (t) async {
    await pumpSim(t, _v, home: (_) => home('saidnaser'));
    await open(t);
    await t.enterText(_f(_fUser), 'admin');
    await t.enterText(_f(_fPass), '1234');
    await save(t);
    expect([dev.rows['saidnaser']!['username'], dev.rows['saidnaser']!['password']], ['admin', '1234']);
    await cardReads(t, user: 'saidnaser');
    for (var i = 0; i < 2; i++) {
      await open(t);
      expect([_text(t, _fUser), _text(t, _fPass)], ['admin', '1234'], reason: 'الفتحة ${i + 2}');
      await save(t);
      expect([dev.rows['saidnaser']!['username'], dev.rows['saidnaser']!['password']], ['admin', '1234'], reason: 'الحفظ ${i + 2}');
      await cardReads(t, user: 'saidnaser');
    }
    await simDrain(t);
  });

  testWidgets('جهازٌ آخر حفظ بعد آخر قراءةٍ عندنا: الورقة تقرأ من الخادم لا من كاش الدقائق الخمس — فلا تمسح حفظَه', (t) async {
    await pumpSim(t, _v, home: (_) => home(_u));
    // هذا الجهاز قرأ قبل قليل: لا إعداد (يبقى في كاشه خمس دقائق)
    await cardReads(t);
    expect(DeviceConfigApi.peekConfig(_u)!.isEmpty, isTrue);
    // جهازٌ آخر (هاتف الوكيل / المحاكي) حفظ كلمة سرّ الآن
    dev.rows[_u] = {
      'id': 7062, 'deviceType': null, 'username': null, 'password': 'r0uter', 'customIp': null, 'notes': null,
      'updatedAt': '2026-11-14T23:31:00.000Z', 'secondAddress': null, 'secondUsername': null, 'secondPassword': null,
    };
    await open(t);
    expect(_text(t, _fPass), 'r0uter', reason: 'المحفوظ الآن بالخادم — لا الفراغ الذي في الكاش');
    await save(t);
    expect(dev.rows[_u]!['password'], 'r0uter', reason: '«حفظ وفحص» من هذا الجهاز لا يمسح ما حفظه الآخر');
    await cardReads(t);
    expect(DeviceConfigApi.peekConfig(_u)!.password, 'r0uter', reason: 'وقراءة الكرت بعد الحفظ تحمل المحفوظ');
    await simDrain(t);
  });

  testWidgets('تعذّرت قراءة الإعداد: «تعذّر تحميل…» وإعادة المحاولة — لا حقول فارغة تُحفظ ولا حذف، ثمّ تنجح فتظهر', (t) async {
    dev.rows[_u] = {
      'id': 7062, 'deviceType': null, 'username': 'admin', 'password': 'r0uter', 'customIp': null, 'notes': null,
      'updatedAt': '2026-11-14T23:31:00.000Z', 'secondAddress': null, 'secondUsername': null, 'secondPassword': null,
    };
    dev.down = true;
    await pumpSim(t, _v, home: (_) => home(_u));
    await t.tap(find.text(simOpenLabel));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-config-load-failed')), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'لا حقول فارغة توهم بأنّ المحفوظ ضاع');
    expect(t.widget<SheetFooterBar>(find.byType(SheetFooterBar)).enabled, isFalse, reason: 'الحفظ مقفل');
    expect(t.widget<SheetFooterIconButton>(find.byType(SheetFooterIconButton)).onTap, isNull, reason: 'والحذف كذلك');
    await t.tap(find.text('حفظ وفحص الجهاز'), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(puts(), isEmpty);
    expect(server.calls('DELETE', dev.path(_u)), isEmpty);
    expect(dev.rows[_u]!['password'], 'r0uter', reason: 'المحفوظ كما هو');

    dev.down = false;
    await t.tap(find.byKey(const ValueKey('device-config-retry')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-config-load-failed')), findsNothing);
    expect([_text(t, _fUser), _text(t, _fPass)], ['admin', 'r0uter']);
    expect(t.widget<SheetFooterBar>(find.byType(SheetFooterBar)).enabled, isTrue);
    await simDrain(t);
  });

  testWidgets('موظّف بلا صلاحيّة الأجهزة والخادم يرفضه: «لا صلاحيّة…» لا «تعذّر… أعد المحاولة» — والخادم يُسأل دائماً (لا رفض مسبق)', (t) async {
    const denied = 'لا صلاحيّة لإعداد أجهزة المشتركين';
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', dev.path(_u), 403, {'success': false, 'message': 'لا صلاحيّة'});
    await pumpSim(t, _v, home: (_) => home(_u));
    await t.tap(find.text(simOpenLabel));
    await t.pumpAndSettle();
    expect(find.text(denied), findsOneWidget);
    expect(find.text('تعذّر تحميل إعداد الجهاز الآن'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(t.widget<SheetFooterBar>(find.byType(SheetFooterBar)).enabled, isFalse);
    expect(server.calls('GET', dev.path(_u)), hasLength(1), reason: 'سُئل الخادم — الرفض رفضُه');
    await simDrain(t);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    // صلاحيّته المحلّيّة قديمة والخادم يقبله (مُنحت للتوّ): الورقة تفتح بالمحفوظ كأيّ حساب
    dev.rows['saidnaser'] = {'id': 9, 'username': 'admin', 'password': 'r0uter'};
    await pumpSim(t, _v, home: (_) => home('saidnaser'));
    await open(t);
    expect(find.text(denied), findsNothing);
    expect([_text(t, _fUser), _text(t, _fPass)], ['admin', 'r0uter']);
    await simDrain(t);
  });

  testWidgets('التلميحات: حقول الاعتماد الفارغة تقول «من بيانات الدخول إذا فارغ» — لا افتراض مصنّعٍ رماديّ يبدو محفوظاً', (t) async {
    await pumpSim(t, _v, home: (_) => home(_u));
    await open(t);
    for (final i in [_fUser, _fPass, _fUser2, _fPass2]) {
      expect(t.widget<TextField>(_f(i)).decoration!.hintText, _hint, reason: 'الحقل $i');
    }
    for (final old in ['telecomadmin', 'admintelecom', 'ubnt']) {
      expect(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == old), findsNothing, reason: old);
    }
    // ولا يتبدّل باختيار النوع
    await t.tap(find.text('Ubiquiti'));
    await t.pump();
    expect(t.widget<TextField>(_f(_fUser)).decoration!.hintText, _hint);
    await simDrain(t);
  });

  testWidgets('٣٢٠ بخطّ ١٫٢: سطر «ينقص العنوان» وصفحة التعذّر لا يخرج منهما نصّ', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSim(t, const SimVariant(320, dark: true), home: (_) => home(_u));
    await open(t);
    await t.ensureVisible(_f(_fUser2));
    await t.enterText(_f(_fUser2), 'admin');
    await save(t);
    expect(find.byKey(const ValueKey('second-needs-address')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.byKey(const ValueKey('second-needs-address')));
    await t.pump();
    expect(t.takeException(), isNull);
    await simDrain(t);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    dev.down = true;
    await pumpSim(t, const SimVariant(320, dark: false), home: (_) => home('saidnaser'));
    await t.tap(find.text(simOpenLabel));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('device-config-load-failed')), findsOneWidget);
    expect(t.takeException(), isNull);
    await simDrain(t);
  });

  testWidgets('من كرت الجهاز نفسه (⚙ ⇒ حفظ ⇒ ⚙ ⇒ حفظ…): المحفوظ يظهر في كلّ فتحة ولا يُمسح', (t) async {
    server.reply('GET', '/api/admin/device-defaults', 200, {'success': true, 'defaults': null});
    // الجهاز نفسه لا يهمّ هنا: فحصٌ وهميّ لا يجد شيئاً (بلا شبكة) — المهمّ قراءات الكرت للإعداد حول الحفظ
    DeviceProbeApi.debugRunProbe = (_) async => null;
    DeviceProbeApi.debugConnectTime = (_) async => null;
    addTearDown(() {
      DeviceProbeApi.debugRunProbe = null;
      DeviceProbeApi.debugConnectTime = null;
    });
    await pumpSim(t, _v,
        home: (_) => const Scaffold(body: SingleChildScrollView(child: DeviceProbeCard(username: _u, ip: '10.9.8.7'))), settle: false);
    Future<void> settle([int seconds = 3]) async {
      for (var i = 0; i < seconds * 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
    }

    Future<void> gear() async {
      await t.tap(find.byIcon(LucideIcons.settings));
      await settle(2);
      expect(find.byType(DeviceConfigSheet), findsOneWidget);
    }

    Future<void> saveHere() async {
      await t.tap(find.text('حفظ وفحص الجهاز'));
      await settle(3);
      expect(find.byType(DeviceConfigSheet), findsNothing);
    }

    await settle();
    await gear();
    expect(_text(t, _fPass), '');
    await t.enterText(_f(_fPass), 'r0uter');
    await saveHere();
    expect(dev.rows[_u]!['password'], 'r0uter');
    for (var i = 0; i < 3; i++) {
      await gear();
      expect(_text(t, _fPass), 'r0uter', reason: 'الفتحة ${i + 2}: المحفوظ ظاهر');
      await saveHere();
      expect(dev.rows[_u]!['password'], 'r0uter', reason: 'الحفظ ${i + 2}: لا يُمسح');
    }
    expect(puts(), hasLength(4));
    await t.pumpWidget(const SizedBox.shrink());
    await simDrain(t);
  });

  test('القراءة الطازجة: التعذّر null (لا إعدادٌ فارغ)، ولا إعداد = فارغٌ صريح، والنجاح يحدّث الكاش', () async {
    expect((await DeviceConfigApi.fetchFresh(_u))!.isEmpty, isTrue, reason: 'لا صفّ ⇒ إعدادٌ فارغ (نجاح)');
    dev.rows[_u] = {'id': 1, 'username': 'admin', 'password': 'x1'};
    expect(DeviceConfigApi.peekConfig(_u)!.isEmpty, isTrue);
    final fresh = await DeviceConfigApi.fetchFresh(_u);
    expect([fresh!.username, fresh.password], ['admin', 'x1'], reason: 'تتخطّى الكاش');
    expect(DeviceConfigApi.peekConfig(_u)!.password, 'x1', reason: 'والكاش تحدّث');
    dev.down = true;
    expect(await DeviceConfigApi.fetchFresh(_u), isNull, reason: 'التعذّر ليس «فارغاً»');
    expect(DeviceConfigApi.peekConfig(_u)!.password, 'x1', reason: 'والتعذّر لا يمحو آخر قراءة');
    server.reply('GET', dev.path('saidnaser'), 403, {'success': false, 'message': 'لا صلاحيّة'});
    expect(await DeviceConfigApi.fetchFresh('saidnaser'), isNull, reason: 'الرفض كذلك');
    expect((await DeviceConfigApi.fetchFresh('  '))!.isEmpty, isTrue);
  });
}
