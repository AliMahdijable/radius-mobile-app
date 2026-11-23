import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/gdrive_backup_api.dart';
import 'package:rad_mysvcs/screens/backup/drive_backup_screen.dart';

/// «النسخ الاحتياطيّ إلى Google Drive» (٢٣ نوفمبر — server/gdriveBackup): ردود الخادم كما يقرؤها التطبيق، والشاشة على خادمٍ وهميّ
/// بالحال: الربط (صفحة Google ⇒ الانتظار ⇒ «تمّ» وتُغلق الصفحة وحدها)، الحال والنسخة الجارية، الانقطاع، الموظّف، الموعد، فكّ الربط،
/// و٣٢٠ بخطٍّ مكبَّر بلا فيضان.

const _bg = 3 * 3600 * 1000;
int _bgAt(int y, int mo, int d, int h, int mi) => DateTime.utc(y, mo, d, h, mi).millisecondsSinceEpoch - _bg;
final _now = _bgAt(2026, 11, 23, 10, 0); // ١٠ صباحاً بغداد

Map<String, Object?> _run(int id, String trigger, String status, int at, {int? subs, int? debtors, String? err, String? url}) => {
      'id': id,
      'trigger': trigger,
      'status': status,
      'started_at': at,
      'finished_at': status == 'running' ? null : at + 30000,
      'subscribers': subs,
      'debtors': debtors,
      'debt_total': debtors == null ? null : debtors * 25000,
      'bytes': subs == null ? null : 81234,
      'file_name': url == null ? null : 'ali — 2026-11-23 03-00.xlsx',
      'file_url': url,
      'error_code': err == null ? null : 'PARTIAL_LIST',
      'error_message': err,
    };

/// خادمٌ وهميّ بالحال — يجيب مسارات /api/v2/gdrive-backup ويسجّل ما وصله.
class _Server implements HttpClientAdapter {
  bool configured = true;
  bool featureOn = true;
  bool employee = false;
  bool linked = false;
  bool broken = false;
  String? job;
  int? linkedAt;
  Map<String, Object?> schedule = {'frequency': 'daily', 'weekday': null, 'monthday': null, 'time': '03:00', 'enabled': true};
  String scheduleText = 'كلّ يوم الساعة 03:00';
  List<Map<String, Object?>> runs = [];
  final calls = <String>[];
  final bodies = <String, Object?>{};

  Map<String, Object?> status() => {
        'success': true,
        'feature_enabled': featureOn,
        'configured': configured,
        'link': linked
            ? {
                'email': 'ali.agent@gmail.com',
                'linked_at': linkedAt ?? _now - 3600000,
                'broken': broken ? {'code': 'LINK_REVOKED', 'message': 'انقطع ربط Google Drive — اربطه من جديد من «النسخ الاحتياطيّ»'} : null,
                'folder_url': 'https://drive.google.com/drive/folders/FOLDER1',
              }
            : null,
        'schedule': schedule,
        'schedule_text': scheduleText,
        'next_at': linked ? _bgAt(2026, 11, 24, 3, 0) : null,
        'keep': 30,
        'job': job == null ? null : {'state': job, 'trigger': 'manual'},
        'runs': runs,
      };

  (int, Object?) route(RequestOptions o) {
    final m = o.method.toUpperCase();
    final p = o.path;
    calls.add('$m $p');
    if (o.data != null) bodies['$m $p'] = o.data;
    if (p.endsWith('/gdrive-backup/me')) {
      return (200, {'success': true, 'feature_enabled': featureOn, 'configured': configured, 'is_employee': employee, 'can_manage': !employee});
    }
    if (employee) return (403, {'success': false, 'code': 'MANAGER_ONLY', 'message': 'النسخ الاحتياطيّ لمدير الصفحة وحده'});
    if (!featureOn) return (403, {'success': false, 'code': 'FEATURE_OFF', 'message': 'الميزة غير مفعّلة لصفحتك بعد'});
    if (m == 'GET' && p.endsWith('/gdrive-backup')) return (200, status());
    if (m == 'POST' && p.endsWith('/connect')) {
      return (200, {'success': true, 'url': 'https://accounts.google.com/o/oauth2/v2/auth?client_id=x&state=S'});
    }
    if (m == 'PUT' && p.endsWith('/schedule')) {
      schedule = Map<String, Object?>.from(o.data as Map);
      scheduleText = schedule['frequency'] == 'weekly' ? 'كلّ يوم السبت الساعة ${schedule['time']}' : 'كلّ يوم الساعة ${schedule['time']}';
      return (200, status());
    }
    if (m == 'POST' && p.endsWith('/run')) {
      job = 'running';
      return (202, {...status(), 'queued': true});
    }
    if (m == 'DELETE' && p.endsWith('/link')) {
      linked = false;
      return (200, status());
    }
    return (404, {'success': false});
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (status, body) = route(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Server server;
  final launched = <(String, bool)>[];
  var closed = 0;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    launched.clear();
    closed = 0;
    DriveBackupScreen.launcher = (Uri u, {bool inApp = false}) async {
      launched.add((u.toString(), inApp));
      return true;
    };
    DriveBackupScreen.closeBrowser = () async => closed++;
    DriveBackupScreen.now = () => _now;
    DriveBackupScreen.linkPoll = const Duration(milliseconds: 40);
    DriveBackupScreen.jobPoll = const Duration(milliseconds: 40);
  });

  Future<void> open(WidgetTester tester, {double width = 390, double scale = 1.0}) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: const DriveBackupScreen(),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> settle(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('ردود الخادم', () {
    test('الحال كاملة: الربط والموعد والنسخ والجارية', () {
      server
        ..linked = true
        ..job = 'running'
        ..runs = [
          _run(3, 'first', 'ok', _bgAt(2026, 11, 23, 1, 0), subs: 1234, debtors: 56, url: 'https://drive.google.com/file/d/F/view'),
          _run(2, 'schedule', 'failed', _bgAt(2026, 11, 22, 3, 0), err: 'وصلت قائمة المشتركين ناقصةً من الشركة — لم يُحفظ ملفٌّ ناقص'),
        ];
      final s = GdbStatus.fromJson(server.status())!;
      expect(s.linked, isTrue);
      expect(s.link!.email, 'ali.agent@gmail.com');
      expect(s.link!.broken, isFalse);
      expect(s.link!.folderUrl, endsWith('FOLDER1'));
      expect(s.schedule, GdbSchedule.daily);
      expect(s.scheduleText, 'كلّ يوم الساعة 03:00');
      expect(s.keep, 30);
      expect(s.working, isTrue);
      expect(s.runs, hasLength(2));
      expect(s.lastOk!.id, 3);
      expect(gdbRunCounts(s.lastOk!), '1,234 مشترك · 56 مديناً');
      expect(s.runs[1].failed, isTrue);
      expect(GdbStatus.fromJson({'success': false}), isNull);
      expect(GdbMe.fromJson({'success': true, 'feature_enabled': true, 'configured': false, 'is_employee': true})!.isEmployee, isTrue);
    });

    test('الموعد يُرسل كما يقبله الخادم', () {
      expect(GdbSchedule.daily.toJson(), {'frequency': 'daily', 'time': '03:00', 'weekday': null, 'monthday': null, 'enabled': true});
      expect(const GdbSchedule(frequency: 'weekly', time: '21:30', weekday: 6).toJson()['weekday'], 6);
      expect(const GdbSchedule(frequency: 'monthly', time: '00:00', monthday: 0).toJson()['monthday'], 0);
      expect(GdbSchedule.fromJson({'frequency': 'hourly', 'time': '25:00'}), GdbSchedule.daily, reason: 'قيمٌ غريبة ⇒ الافتراضيّ');
    });

    test('وقت النسخة بتوقيت بغداد وعدد ما حُفظ', () {
      expect(gdbRunWhen(_bgAt(2026, 11, 23, 3, 0), now: _now), 'اليوم 03:00');
      expect(gdbRunWhen(_bgAt(2026, 11, 22, 23, 59), now: _now), 'أمس 23:59');
      expect(gdbRunWhen(_bgAt(2026, 11, 20, 3, 5), now: _now), '2026-11-20 03:05');
      expect(gdbRunWhen(null, now: _now), '—');
      expect(gdbRunCounts(GdbRun.fromJson(_run(1, 'schedule', 'ok', 0, subs: 9, debtors: 0))!), '9 مشترك · بلا ديون');
      expect(gdbRunCounts(GdbRun.fromJson(_run(1, 'schedule', 'ok', 0, subs: 1200, debtors: 1))!), '1,200 مشترك · 1 مدين');
      expect(gdbTriggerLabel('first'), 'أوّل نسخة');
      expect(gdbTriggerLabel('manual'), 'يدويّة');
      expect(gdbTriggerLabel('schedule'), 'تلقائيّة');
    });

    test('رابط الربط لـ Google وحدها', () async {
      final r = await GdriveBackupApi.connect();
      expect(r.url, startsWith('https://accounts.google.com/'));
      expect(server.bodies['POST /api/v2/gdrive-backup/connect'], {'via': 'app'});
    });
  });

  group('الشاشة', () {
    testWidgets('قبل الربط: ثلاث خطوات وزرٌّ واحد ⇒ صفحة Google ⇒ الانتظار ⇒ «تمّ» وتُغلق الصفحة وحدها', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('gdb-connect-card')), findsOneWidget);
      for (final s in gdbSteps) {
        expect(find.text(s), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('gdb-connect')));
      await settle(tester);
      expect(launched.single.$1, startsWith('https://accounts.google.com/'));
      expect(launched.single.$2, isTrue, reason: 'داخل التطبيق (Safari/Custom Tab)');
      expect(find.byKey(const ValueKey('gdb-waiting')), findsOneWidget);
      expect(find.byKey(const ValueKey('gdb-connect')), findsNothing, reason: 'لا زرّ ثانٍ أثناء الانتظار');
      // الوكيل ضغط «Allow» ⇒ الخادم يقول مربوط (وأوّل نسخةٍ جارية)
      server
        ..linked = true
        ..linkedAt = _now
        ..job = 'running';
      await settle(tester, 10);
      expect(closed, 1, reason: 'صفحة Google تُغلق وحدها');
      expect(find.text('تمّ ربط Google Drive — أوّل نسخة تُحفظ الآن'), findsOneWidget);
      expect(find.byKey(const ValueKey('gdb-status')), findsOneWidget);
      expect(find.text('جارٍ حفظ نسخة الآن…'), findsOneWidget);
      // انتهت أوّل نسخة ⇒ يظهر سطر «آخر نسخة»
      server
        ..job = null
        ..runs = [_run(3, 'first', 'ok', _now - 60000, subs: 1234, debtors: 56, url: 'https://drive.google.com/file/d/F/view')];
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('gdb-last')), findsOneWidget);
      expect(find.textContaining('1,234 مشترك · 56 مديناً'), findsWidgets);
      await close(tester);
    });

    testWidgets('مربوط: فتح المجلّد، «انسخ الآن» ⇒ جارية ⇒ انتهت', (tester) async {
      server
        ..linked = true
        ..runs = [_run(3, 'schedule', 'ok', _bgAt(2026, 11, 23, 3, 0), subs: 1234, debtors: 56, url: 'https://drive.google.com/file/d/F/view')];
      await open(tester);
      expect(find.textContaining('مربوط'), findsOneWidget);
      expect(find.textContaining('اليوم 03:00'), findsWidgets);
      expect(find.text('كلّ يوم الساعة 03:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gdb-folder')));
      await settle(tester);
      expect(launched.last.$1, 'https://drive.google.com/drive/folders/FOLDER1');
      await tester.tap(find.byKey(const ValueKey('gdb-run')));
      await settle(tester);
      expect(server.calls, contains('POST /api/v2/gdrive-backup/run'));
      expect(find.byKey(const ValueKey('gdb-job')), findsOneWidget);
      server.job = null;
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('gdb-job')), findsNothing);
      await close(tester);
    });

    testWidgets('ربطٌ مقطوع: السبب و«أعد الربط»، ولا «انسخ الآن»', (tester) async {
      server
        ..linked = true
        ..broken = true;
      await open(tester);
      expect(find.textContaining('انقطع ربط Google Drive'), findsOneWidget);
      expect(find.byKey(const ValueKey('gdb-reconnect')), findsOneWidget);
      expect(find.byKey(const ValueKey('gdb-run')), findsNothing);
      await close(tester);
    });

    testWidgets('الموظّف يرى القسم مقفلاً، والمفتاح المطفأ يُقال، والخدمة غير الجاهزة تُقال', (tester) async {
      server.employee = true;
      await open(tester);
      expect(find.text('لمدير الصفحة — يربط درايفه ويحدّد موعد النسخ'), findsOneWidget);
      await close(tester);
      server
        ..employee = false
        ..featureOn = false;
      await open(tester);
      expect(find.text('النسخ الاحتياطيّ غير مفعّل لصفحتك بعد'), findsOneWidget);
      await close(tester);
      server
        ..featureOn = true
        ..configured = false;
      await open(tester);
      expect(find.text('الخدمة قيد التجهيز من جهتنا — تظهر هنا قريباً.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('الموعد: أسبوعيّاً يوم السبت ⇒ PUT بما يقبله الخادم', (tester) async {
      server.linked = true;
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('gdb-schedule')));
      await settle(tester, 12);
      await tester.tap(find.text('كل أسبوع'));
      await settle(tester);
      expect(find.byKey(const ValueKey('gdb-weekday')), findsOneWidget);
      // الحال بكلمةٍ بجانب المفتاح (اتّجاهه ينقلب بالعربيّ)
      expect(find.text('مفعّل'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gdb-enabled')));
      await settle(tester);
      expect(find.text('موقوف'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gdb-enabled')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('gdb-schedule-save')));
      await settle(tester, 12);
      expect(server.bodies['PUT /api/v2/gdrive-backup/schedule'], {'frequency': 'weekly', 'time': '03:00', 'weekday': 6, 'monthday': null, 'enabled': true});
      expect(find.text('كلّ يوم السبت الساعة 03:00'), findsOneWidget);
      await close(tester);
    });

    testWidgets('إلغاء الربط بتأكيد ⇒ يعود زرّ الربط', (tester) async {
      server.linked = true;
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('gdb-unlink')));
      await tester.tap(find.byKey(const ValueKey('gdb-unlink')));
      await settle(tester, 12);
      await tester.tap(find.text('إلغاء الربط').last);
      await settle(tester, 12);
      expect(server.calls, contains('DELETE /api/v2/gdrive-backup/link'));
      expect(find.byKey(const ValueKey('gdb-connect')), findsOneWidget);
      await close(tester);
    });

    for (final w in [320.0, 480.0]) {
      testWidgets('عرض ${w.toInt()} بخطٍّ مكبَّر (1.3) بلا فيضان — قبل الربط وبعده', (tester) async {
        await open(tester, width: w, scale: 1.3);
        expect(tester.takeException(), isNull);
        await close(tester);
        server
          ..linked = true
          ..runs = [
            _run(3, 'first', 'ok', _now - 60000, subs: 123456, debtors: 9876, url: 'https://drive.google.com/file/d/F/view'),
            _run(2, 'schedule', 'failed', _now - 86400000, err: 'وصلت قائمة المشتركين ناقصةً من الشركة — لم يُحفظ ملفٌّ ناقص'),
          ];
        await open(tester, width: w, scale: 1.3);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  });
}
