import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/connection_auto_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_auto_widgets.dart';
import 'package:rad_mysvcs/services/connection_readings_uploader.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «تنبيه المشترك» التلقائيّ (٣ نوفمبر — الخادم server/connAlertsAuto.js): التطبيق يقيس ويرفع القراءات الخام فقط، لحسابٍ فتحه
/// الخادم وتنبيهه مفعّل ووضعه غير يدويّ، ولمشتركي الحساب نفسه، بقراءةٍ لكلّ مشترك كلّ ١٥ دقيقة؛ والوكيل يختار الوضع والضوابط
/// ويوافق من «بانتظار موافقتك».
const _v = SimVariant(390, dark: false);

UbiquitiStatus _ubnt({int? signal = -55, int? ccq = 95, List<LanPort> lan = const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)]}) =>
    UbiquitiStatus(
      hostname: 'nano',
      firmware: 'XW.v6.3',
      uptimeSeconds: 100,
      ssid: 'AP',
      mode: 'sta',
      signalDbm: signal,
      noiseFloorDbm: -95,
      ccqPercent: ccq,
      distanceMeters: 800,
      txRateKbps: 0,
      rxRateKbps: 0,
      lanPorts: lan,
      peerMac: null,
      peerCount: null,
      baseUrl: 'http://10.0.0.2',
    );

DeviceHealthSnapshot _snapU(UbiquitiStatus u) => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.2', ubnt: u);
DeviceHealthSnapshot _snapO({String rx = '-20.5', String temp = '45'}) => DeviceHealthSnapshot(
      kind: DeviceKind.ont,
      ip: '10.0.0.3',
      ont: OntOpticalInfo(txPower: '2.1', rxPower: rx, voltage: '3300', temperature: temp, bias: '10', sendStatus: 'ok'),
    );

Subscriber _sub(String idx, {String? phone = '07701234567', String? expiration, bool enabled = true}) => Subscriber.fromJson({
      'idx': idx,
      'username': 'u$idx',
      'firstname': 'مشترك',
      'lastname': idx,
      'phone': phone,
      'expiration': expiration ?? DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      'enabled': enabled ? 1 : 0,
    });

Map<String, dynamic> _status({bool available = true, bool enabled = true, String mode = 'approval', bool dry = true, int pending = 0}) => {
      'success': true,
      'data': available
          ? {
              'available': true,
              'dry_run': dry,
              'alerts_enabled': enabled,
              'settings': {'mode': mode, 'remind_days': 3, 'max_sends': 3, 'daily_cap': 30, 'hour_from': 10, 'hour_to': 20, 'confirm_min': 30,
                'kinds': ['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp']},
              'counts': {'pending': pending, 'watching': 2, 'sent_today': 1},
              'in_window': true,
            }
          : {'available': false},
    };

void main() {
  test('القراءة: كيبل 10 ميكا والإشارة والـCCQ للنانو، والضوئيّ والحرارة للفايبر؛ «لم نقرأ» لا تُرفع؛ والمنتهي/المعطّل غير فعّال', () {
    final s = _sub('101');
    final r = ConnectionReadingsUploader.readingFor(
        s, _snapU(_ubnt(signal: -70, ccq: 40, lan: const [LanPort(name: 'eth0', speed: '10Mbps-Full', plugged: true)])))!;
    expect(r['idx'], '101');
    expect(r['phone'], '07701234567');
    expect((r['device'], r['lan'], r['signal'], r['ccq'], r['active']), ('ubnt', '10', -70, 40, true));
    final ok = ConnectionReadingsUploader.readingFor(s, _snapU(_ubnt()))!;
    expect(ok['lan'], 'ok', reason: 'سليمٌ مقروء يُرفع — هو ما يحلّ المشكلة بالخادم');
    final unplugged = ConnectionReadingsUploader.readingFor(
        s, _snapU(_ubnt(lan: const [LanPort(name: 'eth0', speed: null, plugged: false)])))!;
    expect(unplugged['lan'], 'unplugged');
    final o = ConnectionReadingsUploader.readingFor(s, _snapO(rx: '-28.4', temp: '71'))!;
    expect((o['device'], o['rx'], o['temp'], o['volt']), ('ont', -28.4, 71.0, 3.3), reason: 'الفولتيّة بالفولت (٥ نوفمبر)');
    expect(ConnectionReadingsUploader.readingFor(s, _snapU(_ubnt(signal: 0, ccq: 0, lan: const []))), isNull, reason: 'لم نقرأ شيئاً');
    final expired = _sub('7', expiration: DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
    expect(ConnectionReadingsUploader.readingFor(expired, _snapU(_ubnt()))!['active'], false);
    expect(ConnectionReadingsUploader.readingFor(_sub('8', enabled: false), _snapU(_ubnt()))!['active'], false);
  });

  group('الرفع', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnectionAutoApi.debugReset();
      ConnectionReadingsUploader.debugReset();
      server.reply('POST', '/api/v2/connection-alerts/readings', 200, {'success': true, 'data': {'active': true, 'received': 2}});
    });

    test('مطفأ للحساب ⇒ لا رفع أبداً', () async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(available: false));
      ConnectionReadingsUploader.debugSnapshotOf = (_) => _snapU(_ubnt(signal: -70));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), isEmpty);
    });

    test('مفتوح ومفعّل ⇒ مشتركو الحساب بلقطاتهم (لا صفٌّ بمفتاح شركةٍ غير صالح ولا بلا لقطة)، ثمّ لا تكرار قبل ١٥ دقيقة', () async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      final other = _sub('3').withCompany('nbtel:9');
      ConnectionReadingsUploader.debugSnapshotOf = (u) => u == 'u4' ? null : _snapU(_ubnt(signal: -70));
      await ConnectionReadingsUploader.collect([_sub('1'), _sub('2'), other, _sub('4')]);
      final b = server.bodies('POST', '/api/v2/connection-alerts/readings');
      expect(b, hasLength(1));
      expect((b.single['readings'] as List).map((r) => (r as Map)['idx']), ['1', '2']);
      await ConnectionReadingsUploader.collect([_sub('1'), _sub('2')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), hasLength(1), reason: 'مخنوقٌ لكلّ مشترك');
    });

    test('تحت المراقبة: الخادم يعطي موعد إعادة القياس ⇒ يُقاس المشترك وحده عنده (قبله لا) ويُرفع فوراً', () async {
      final due = DateTime.now().add(const Duration(minutes: 3));
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      server.reply('POST', '/api/v2/connection-alerts/readings', 200, {
        'success': true,
        'data': {'active': true, 'recheck': [{'key': 'i:1', 'idx': '1', 'username': 'u1', 'due_ms': due.millisecondsSinceEpoch}]},
      });
      ConnectionReadingsUploader.debugSnapshotOf = (_) => _snapU(_ubnt(signal: -70));
      var probes = 0;
      ConnectionReadingsUploader.debugProbe = (s) async {
        probes++;
        return _snapU(_ubnt(signal: -71));
      };
      await ConnectionReadingsUploader.collect([_sub('1')]);
      expect(ConnectionReadingsUploader.pendingRechecks.keys, ['u1']);
      expect(await ConnectionReadingsUploader.runRechecks(now: due.subtract(const Duration(seconds: 30))), 0, reason: 'قبل موعده لا');
      expect(probes, 0);
      server.reply('POST', '/api/v2/connection-alerts/readings', 200, {'success': true, 'data': {'active': true, 'confirmed': 1, 'recheck': []}});
      expect(await ConnectionReadingsUploader.runRechecks(now: due.add(const Duration(seconds: 1))), 1);
      expect(probes, 1, reason: 'فحصٌ مُجبَر لجهازه وحده');
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), hasLength(2));
      expect(((server.bodies('POST', '/api/v2/connection-alerts/readings').last['readings'] as List).single as Map)['signal'], -71);
      expect(ConnectionReadingsUploader.pendingRechecks, isEmpty, reason: 'تأكّد ⇒ لا موعد');
    });

    test('الوضع يدويّ أو التنبيه مطفأ ⇒ لا رفع', () async {
      ConnectionReadingsUploader.debugSnapshotOf = (_) => _snapU(_ubnt(signal: -70));
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(mode: 'manual'));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      ConnectionAutoApi.debugReset();
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(enabled: false));
      await ConnectionReadingsUploader.collect([_sub('1')]);
      expect(server.calls('POST', '/api/v2/connection-alerts/readings'), isEmpty);
    });
  });

  group('الواجهة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'owner'});
      ConnectionAutoApi.debugReset();
      PermissionsService.debugSet(isEmployee: false);
    });
    tearDown(PermissionsService.debugReset);

    testWidgets('البطاقة: مخفيّة لحسابٍ لم يُفتح له', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(available: false));
      await pumpSim(t, _v, home: (_) => const Scaffold(body: ConnAutoCard(canEdit: true)));
      await t.pumpAndSettle();
      expect(find.text('الإرسال التلقائيّ'), findsNothing);
      await simDrain(t);
    });

    testWidgets('البطاقة: «بموافقتي» افتراضاً وشريط المحاكاة؛ «تلقائيّ» + تذكيرٌ كلّ ٤ أيّام ⇒ الحفظ يرسلها', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 3));
      server.reply('PUT', '/api/v2/connection-alerts/auto', 200, {'success': true, 'message': 'تم الحفظ'});
      await pumpSim(t, _v, home: (_) => Scaffold(body: ListView(children: const [ConnAutoCard(canEdit: true)])));
      await t.pumpAndSettle();
      expect(find.text('الإرسال التلقائيّ'), findsOneWidget);
      expect(find.textContaining('وضع المحاكاة'), findsOneWidget);
      expect(find.textContaining('وأنت تضغط «أرسل»'), findsOneWidget, reason: 'شرح «بموافقتي»');
      expect(find.text('بانتظار موافقتك'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'شارة العدد');
      expect(find.text('حفظ الإرسال التلقائيّ'), findsNothing, reason: 'لا تغيير');
      await t.tap(find.text('تلقائيّ'));
      await t.pump();
      final plus = find.descendant(of: find.ancestor(of: find.text('ذكّر المشترك كلّ'), matching: find.byType(Row)).first, matching: find.byTooltip('زيادة'));
      await t.tap(plus);
      await t.pump();
      expect(find.text('4 أيّام'), findsOneWidget);
      await t.tap(find.text('حفظ الإرسال التلقائيّ'));
      await t.pumpAndSettle();
      final put = server.bodies('PUT', '/api/v2/connection-alerts/auto').single;
      expect((put['mode'], put['remind_days'], put['max_sends']), ('auto', 4, 3));
      await simDrain(t);
    });

    testWidgets('🐛 الرجوع للوضع المحفوظ يُخفي «حفظ»؛ والتأكيد بخيارات ٣/٥/١٠…٣٠ دقيقة', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      await pumpSim(t, _v, home: (_) => Scaffold(body: ListView(children: const [ConnAutoCard(canEdit: true)])));
      await t.pumpAndSettle();
      for (final m in ['تلقائيّ', 'يدويّ']) {
        await t.tap(find.text(m));
        await t.pump();
        expect(find.text('حفظ الإرسال التلقائيّ'), findsOneWidget, reason: m);
        await t.tap(find.text('بموافقتي'));
        await t.pump();
        expect(find.text('حفظ الإرسال التلقائيّ'), findsNothing, reason: 'رجع للمحفوظ من $m');
      }
      Finder btn(String tip) => find.descendant(
          of: find.ancestor(of: find.text('تأكّد من المشكلة بعد'), matching: find.byType(Row)).first, matching: find.byTooltip(tip));
      expect(find.text('30 دقيقة'), findsOneWidget);
      await t.tap(btn('إنقاص'));
      await t.pump();
      expect(find.text('25 دقيقة'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        await t.tap(btn('إنقاص'));
        await t.pump();
      }
      expect(find.text('3 دقيقة'), findsOneWidget, reason: '٢٥ ⇒ ٢٠ ⇒ ١٥ ⇒ ١٠ ⇒ ٥ ⇒ ٣ ثمّ يقف');
      await t.tap(btn('زيادة'));
      await t.pump();
      expect(find.text('5 دقيقة'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('تحت المراقبة: «هذه أوّل قراءة» + «أرسل الآن» يرسل له وحده', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      server.on('GET', '/api/v2/connection-alerts/queue', (o) => SimReply(200, {
            'success': true,
            'data': {
              'available': true,
              'items': o.queryParameters['state'] == 'watching'
                  ? [
                      {
                        'key': 'i:7', 'idx': '7', 'username': 'u7', 'name': 'ابو مصطفى', 'state': 'watching',
                        'problems': [{'kind': 'signal', 'label': 'الإشارة', 'text': '-62 dBm'}],
                        'first_bad_ms': DateTime.now().subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
                        'last_reading_ms': DateTime.now().subtract(const Duration(minutes: 2)).millisecondsSinceEpoch, 'sends': 0, 'muted': false,
                      },
                    ]
                  : [],
            },
          }));
      server.reply('POST', '/api/v2/connection-alerts/queue/action', 200, {'success': true, 'data': {'sent': true, 'dry': true}});
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_status()['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('تحت المراقبة'));
      await t.pumpAndSettle();
      expect(find.textContaining('هذه أوّل قراءةٍ سيّئة'), findsOneWidget);
      expect(find.textContaining(RegExp(r'بعد 2[78] دقيقة تقريباً')), findsOneWidget);
      await t.tap(find.text('أرسل الآن'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/connection-alerts/queue/action').single, {'action': 'send_now', 'keys': ['i:7']});
      expect(find.textContaining('محاكاة'), findsWidgets);
      await simDrain(t);
    });

    testWidgets('نقرة تنبيه «بانتظار موافقتك» (conn_alert_pending) ⇒ «تنبيهات المشتركين»؛ وغيره لا', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 2));
      server.reply('GET', '/api/v2/connection-alerts/queue', 200, {'success': true, 'data': {'available': true, 'items': []}});
      final key = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: key, home: (_) => const Scaffold(body: Text('الرئيسيّة')));
      await t.pumpAndSettle();
      expect(await openConnAlertPush(key.currentState!, const {'type': 'watani_ticket'}), isFalse);
      final f = openConnAlertPush(key.currentState!, const {'type': 'conn_alert_pending', 'count': '2'});
      await t.pumpAndSettle();
      expect(find.text('تنبيهات المشتركين'), findsOneWidget);
      expect(find.textContaining('وضع المحاكاة'), findsOneWidget);
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, isTrue);
      await simDrain(t);
    });

    test('الحالة: can_use/can_edit من الخادم؛ خادمٌ أقدم بلاهما ⇒ مفتوحٌ كما كان', () {
      final d = Map<String, dynamic>.from(_status()['data'] as Map);
      final old = ConnAutoStatus.fromJson(d);
      expect((old.canUse, old.canEdit), (true, null));
      final e = ConnAutoStatus.fromJson({...d, 'can_use': false, 'can_edit': false});
      expect((e.canUse, e.canEdit), (false, false));
      expect(e.withSettings(e.settings).canUse, isFalse, reason: 'نسخة الإعدادات تحفظه');
    });

    // ٤ نوفمبر — المالك: القسم والإشعار مفتاحان مستقلّان للموظّف («حتى لو القسم مفعل وطفي الاشعارات ماتوصله والعكس صحيح»)
    testWidgets('موظّفٌ بلا مفتاح القسم: «تنبيهات المشتركين» قفلٌ لا قائمة — ولو فتحها إشعار «أُرسل» (الإشعار مفتاحٌ مستقلّ)', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200,
          {'success': true, 'data': {...(_status()['data'] as Map), 'can_use': false, 'can_edit': false}});
      final key = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: key, home: (_) => const Scaffold(body: Text('الرئيسيّة')));
      await t.pumpAndSettle();
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson({...(_status()['data'] as Map), 'can_use': false, 'can_edit': false});
      final f = openConnAlertPush(key.currentState!, const {'type': 'conn_alert_sent', 'count': '1'});
      await t.pumpAndSettle();
      expect(find.textContaining('ليس لديك صلاحيّة «تنبيهات المشتركين»'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/connection-alerts/queue'), isEmpty, reason: 'لا يُطلب قسمٌ مقفل');
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, isTrue);
      await simDrain(t);
    });

    testWidgets('إشعار «أُرسل بالواتساب» (conn_alert_sent) يفتح «تنبيهات المشتركين» على تبويب «أُرسل»', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status());
      server.reply('GET', '/api/v2/connection-alerts/queue', 200, {'success': true, 'data': {'available': true, 'items': []}});
      final key = GlobalKey<NavigatorState>();
      await pumpSim(t, _v, navigatorKey: key, home: (_) => const Scaffold(body: Text('الرئيسيّة')));
      await t.pumpAndSettle();
      final f = openConnAlertPush(key.currentState!, const {'type': 'conn_alert_sent', 'count': '3'});
      await t.pumpAndSettle();
      expect(find.text('تنبيهات المشتركين'), findsOneWidget);
      final states = server.calls('GET', '/api/v2/connection-alerts/queue').map((r) => r.queryParameters['state']).toSet();
      expect(states, contains('sent,skipped'));
      key.currentState!.pop();
      await t.pumpAndSettle();
      expect(await f, isTrue);
      await simDrain(t);
    });

    testWidgets('القائمة: «بانتظار موافقتك» بمشاكله وأوقاته؛ «أرسل» يرسل مفتاحه، و«أرسل للكلّ» all', (t) async {
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 1));
      server.on('GET', '/api/v2/connection-alerts/queue', (o) {
        final st = o.queryParameters['state'];
        return SimReply(200, {
          'success': true,
          'data': {
            'available': true,
            'items': st == 'pending'
                ? [
                    {
                      'key': 'i:101', 'idx': '101', 'username': 'u101', 'name': 'علي حسن', 'state': 'pending',
                      'problems': [{'kind': 'signal', 'label': 'الإشارة', 'text': '\u2068-70 dBm\u2069'}],
                      'confirmed_ms': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
                      'last_reading_ms': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch, 'sends': 0, 'muted': false,
                    },
                  ]
                : [],
          },
        });
      });
      server.reply('POST', '/api/v2/connection-alerts/queue/action', 200, {'success': true, 'data': {'done': 1, 'skipped': 0}});
      server.reply('GET', '/api/v2/connection-alerts/log', 200, {'success': true, 'data': {'available': true, 'items': []}});
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_status(pending: 1)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      expect(find.text('علي حسن'), findsOneWidget);
      expect(find.textContaining('الإشارة: '), findsOneWidget);
      expect(find.textContaining('تأكّدت منذ ساعتين'), findsOneWidget);
      await t.tap(find.text('أرسل'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/connection-alerts/queue/action').last, {'action': 'approve', 'keys': ['i:101']});
      await t.tap(find.textContaining('أرسل للكلّ'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/connection-alerts/queue/action').last, {'action': 'approve', 'all': true});
      await simDrain(t);
    });

    testWidgets('عشرةٌ بكلّ تبويب و«تحميل المزيد»؛ وإجراءٌ ناجح يعيد تحميل التبويبات الأخرى بلا سحب (المالك ٣ نوفمبر)', (t) async {
      Map<String, dynamic> cs(int i, String st) => {
            'key': 'i:$i', 'idx': '$i', 'username': 'u$i', 'name': 'مشترك $i', 'state': st,
            'problems': [{'kind': 'signal', 'label': 'الإشارة', 'text': '-70 dBm'}],
            'confirmed_ms': DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch, 'sends': 0, 'muted': false,
          };
      var watching = 3;
      server.reply('GET', '/api/v2/connection-alerts/auto', 200, _status(pending: 25));
      server.on('GET', '/api/v2/connection-alerts/queue', (o) {
        final st = '${o.queryParameters['state']}';
        final limit = int.parse('${o.queryParameters['limit']}');
        final all = st == 'pending' ? [for (var i = 1; i <= 25; i++) cs(i, 'pending')] : st == 'watching' ? [for (var i = 100; i < 100 + watching; i++) cs(i, 'watching')] : <Map<String, dynamic>>[];
        return SimReply(200, {'success': true, 'data': {'available': true, 'items': all.take(limit).toList()}});
      });
      server.reply('POST', '/api/v2/connection-alerts/queue/action', 200, {'success': true, 'data': {'done': 1, 'skipped': 0}});
      server.reply('GET', '/api/v2/connection-alerts/log', 200, {'success': true, 'data': {'available': true, 'items': []}});
      ConnectionAutoApi.status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(_status(pending: 25)['data'] as Map));
      await pumpSim(t, _v, home: (_) => const ConnAutoQueueScreen());
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/connection-alerts/queue').first.queryParameters['limit'], 11);
      expect(find.textContaining('أرسل للكلّ (25)'), findsOneWidget, reason: 'العدد من الخادم لا من الصفحة');
      await t.dragUntilVisible(find.text('تحميل المزيد'), find.byType(ListView).first, const Offset(0, -300));
      await t.pumpAndSettle();
      expect(find.text('مشترك 10'), findsOneWidget);
      expect(find.text('مشترك 11'), findsNothing);
      await t.tap(find.text('تحميل المزيد'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/connection-alerts/queue').where((c) => c.queryParameters['state'] == 'pending').last.queryParameters['limit'], 21);
      // تبويب «تحت المراقبة» محمَّلٌ مسبقاً؟ نفتحه ثمّ نرجع ونرسل ⇒ يُعاد تحميله وحده
      await t.tap(find.text('تحت المراقبة'));
      await t.pumpAndSettle();
      expect(find.text('مشترك 102'), findsOneWidget);
      final before = server.calls('GET', '/api/v2/connection-alerts/queue').where((c) => c.queryParameters['state'] == 'watching').length;
      watching = 1;
      await t.tap(find.text('بانتظار موافقتك'));
      await t.pumpAndSettle();
      await t.tap(find.text('أرسل').first);
      await t.pumpAndSettle();
      final after = server.calls('GET', '/api/v2/connection-alerts/queue').where((c) => c.queryParameters['state'] == 'watching').length;
      expect(after, greaterThan(before), reason: 'الإجراء يعيد تحميل التبويبات الأخرى');
      await t.tap(find.text('تحت المراقبة'));
      await t.pumpAndSettle();
      expect(find.text('مشترك 102'), findsNothing);
      await simDrain(t);
    });
  });
}
