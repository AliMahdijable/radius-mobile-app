import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/vsol_olt_api.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/tower_layout.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_logic.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_paint.dart';
import 'package:rad_mysvcs/screens/network_devices/tower/tower_reading.dart';
import 'package:rad_mysvcs/theme/colors.dart';

NetworkDevice dev(
  int id,
  String name, {
  String type = 'router',
  String brand = 'mikrotik',
  String? model,
  String status = 'online',
  String? location,
}) =>
    NetworkDevice(
      id: id,
      adminId: '2',
      regionId: 1,
      name: name,
      type: type,
      brand: brand,
      model: model,
      ip: '10.0.0.$id',
      port: 8728,
      lastStatus: status,
      location: location,
      createdAt: DateTime(2026, 10, 1),
    );

/// أجهزة popq كما في قاعدة البيانات (٢٧ أكتوبر): الـBaseBox مسجّلة «راوتر»، والـCCR «سويج».
List<NetworkDevice> popq() => [
      dev(509, 'سكتر 1', model: 'BaseBox 5', location: 'جهة المعامل'),
      for (final (id, n) in [(1006, 3), (1007, 6), (1008, 4), (1009, 12), (1010, 11), (1012, 8), (1013, 7), (1014, 9)])
        dev(id, 'جهاز $n', model: 'BaseBox 5'),
      dev(1011, 'جهاز 10', model: 'SXT SA5'),
      dev(1514, 'سيرفر التوزيع', type: 'switch', model: 'CCR1009-7G-1C-1S+'),
      dev(1515, 'سكتر ubntu 18', type: 'link', brand: 'ubnt', model: 'PowerBeam M5'),
    ];

TowerReading reading({
  bool wireless = true,
  String? mode = 'ap-bridge',
  int? clients,
  int? quality,
  int? signal,
  int? frequency,
  int? width,
}) =>
    TowerReading(
      at: DateTime(2026, 10, 27),
      wireless: wireless,
      mode: mode,
      clients: clients,
      quality: quality,
      signal: signal,
      frequency: frequency,
      channelWidth: width,
    );

void main() {
  group('الشكل من الموديل أوّلاً', () {
    TowerShape shapeOf(String? model, {String type = 'router', String brand = 'mikrotik'}) =>
        TowerShapes.detect(dev(1, 'x', model: model, type: type, brand: brand)).shape;

    test('أجهزة popq: الموديل يغلب النوع المكتوب', () {
      expect(TowerShapes.detect(dev(1, 'a', model: 'BaseBox 5')), (shape: TowerShape.sector, source: ShapeSource.model));
      expect(shapeOf('PowerBeam M5', type: 'link', brand: 'ubnt'), TowerShape.dish);
      expect(shapeOf('SXT SA5'), TowerShape.panel, reason: 'لوحة لا Mimosa A5');
      expect(shapeOf('CCR1009-7G-1C-1S+', type: 'switch'), TowerShape.router);
    });

    test('علاماتٌ وطُرُزٌ أخرى', () {
      expect(shapeOf('RocketDish 5G-30', brand: 'ubnt'), TowerShape.dish, reason: 'الصحن قبل Rocket');
      expect(shapeOf('Rocket M5', brand: 'ubnt'), TowerShape.sector);
      expect(shapeOf('Rocket Prism 5AC', brand: 'ubnt'), TowerShape.sector);
      expect(shapeOf('LTU-Rocket', brand: 'ubnt'), TowerShape.sector);
      expect(shapeOf('NanoStation M5', brand: 'ubnt'), TowerShape.panel);
      expect(shapeOf('NSM5', brand: 'ubnt'), TowerShape.panel);
      expect(shapeOf('AF-5XHD', brand: 'ubnt'), TowerShape.dish);
      expect(shapeOf('LHG XL 5 ac'), TowerShape.dish);
      expect(shapeOf('RBLHG-5nD'), TowerShape.dish);
      expect(shapeOf('mANTBox 15s'), TowerShape.sector);
      expect(shapeOf('RB912UAG-5HPnD'), TowerShape.sector, reason: 'لوحة BaseBox 5');
      expect(shapeOf('OmniTIK 5 ac'), TowerShape.omni);
      expect(shapeOf('hAP ac2'), TowerShape.router);
      expect(shapeOf('RB4011iGS+'), TowerShape.router);
      expect(shapeOf('CRS326-24G-2S+'), TowerShape.sw);
      expect(shapeOf('A5c', brand: 'mimosa'), TowerShape.sector);
      expect(shapeOf('B5c', brand: 'mimosa'), TowerShape.dish);
      expect(shapeOf('C5x', brand: 'mimosa'), TowerShape.dish);
      expect(shapeOf('V1600D4', brand: 'vsol'), TowerShape.olt);
      expect(shapeOf('BDCOM P3600-04', brand: 'other'), TowerShape.olt);
      expect(shapeOf('BDCOM S2528-B', brand: 'other'), TowerShape.sw, reason: 'سويج BDCOM لا أولت');
      expect(shapeOf('RG-EST100-E', brand: 'ruijie'), TowerShape.panel);
    });

    test('بلا موديل: العلامة ثمّ النوع المكتوب', () {
      expect(TowerShapes.detect(dev(1, 'x', brand: 'vsol')).shape, TowerShape.olt);
      expect(TowerShapes.detect(dev(1, 'x', brand: 'cisco')).source, ShapeSource.brand);
      expect(TowerShapes.detect(dev(1, 'x', type: 'link', brand: 'ubnt')), (shape: TowerShape.dish, source: ShapeSource.type));
      expect(TowerShapes.detect(dev(1, 'x', type: 'camera', brand: 'other')).shape, TowerShape.other);
    });

    test('القراءة تصحّح الأضعف فقط، ولا تمسّ الموديل', () {
      final byType = TowerShapes.detect(dev(1, 'x', type: 'sector', brand: 'ubnt'));
      expect(TowerShapes.refine(byType, reading(wireless: false)).shape, TowerShape.router);
      expect(TowerShapes.refine(byType, reading(clients: 12)).shape, TowerShape.sector);
      expect(TowerShapes.refine(byType, reading(clients: 1, mode: 'sta')).shape, TowerShape.dish);
      final byModel = TowerShapes.detect(dev(1, 'x', model: 'PowerBeam M5', brand: 'ubnt'));
      expect(TowerShapes.refine(byModel, reading(clients: 30)).shape, TowerShape.dish);
    });

    test('الدور: صحنٌ بطرفٍ واحد لنك، والمستقبِل لنك، وسكترٌ بلا مشتركين يبقى سكتراً', () {
      expect(TowerShapes.roleOf(TowerShape.dish, reading(clients: 1, mode: 'ap')), TowerRole.link);
      expect(TowerShapes.roleOf(TowerShape.sector, reading(clients: 0)), TowerRole.sector);
      expect(TowerShapes.roleOf(TowerShape.sector, reading(clients: 1, mode: 'station')), TowerRole.link);
      expect(TowerShapes.roleOf(TowerShape.dish, reading(clients: 9, mode: 'ap')), TowerRole.sector);
      expect(TowerShapes.roleOf(TowerShape.panel, reading(clients: 9)), TowerRole.ap);
      expect(TowerShapes.roleOf(TowerShape.router, null), TowerRole.cabinet);
    });
  });

  group('الاتّجاه المكتوب', () {
    test('العربيّة والإنجليزيّة والدرجات', () {
      expect(hintAzimuthFromText('سكتر 1 جهة المعامل'), isNull, reason: 'معلمٌ لا اتّجاه');
      expect(hintAzimuthFromText('سكتر شمال شرق'), 45);
      expect(hintAzimuthFromText('السكتر الشمالي'), 0);
      expect(hintAzimuthFromText('جنوب غربي'), 225);
      expect(hintAzimuthFromText('غرب'), 270);
      expect(hintAzimuthFromText('سكتر ٤٥°'), 45);
      expect(hintAzimuthFromText('az 120 deg'), 120);
      expect(hintAzimuthFromText('north-east sector'), 45);
      expect(hintAzimuthFromText('NE link'), 45);
      expect(hintAzimuthFromText('شمال وجنوب'), isNull, reason: 'متناقض');
      expect(hintAzimuthFromText('جهاز 3'), isNull);
    });
  });

  group('الترتيب التلقائيّ', () {
    test('popq: اللنك فوق، 9 سكاتر موزّعة على حلقتين، اللوحة بالوسط، والسيرفر بالكابينة', () {
      final a = TowerArrange.arrange(popq());
      expect(a.length, 12);
      expect(a[1515]!.role, TowerRole.link);
      expect(a[1515]!.level, TowerLevel.top);
      expect(a[1515]!.nameSaysSectorButLink, isTrue);
      expect(a[1011]!.level, TowerLevel.mid);
      expect(a[1514]!.level, TowerLevel.base);
      expect(a[1514]!.azimuth, isNull);
      final sectors = a.values.where((x) => x.role == TowerRole.sector).toList();
      expect(sectors.length, 9);
      final az = sectors.map((s) => s.azimuth!).toList()..sort();
      expect(az, [0, 40, 80, 120, 160, 200, 240, 280, 320]);
      final byAz = [...sectors]..sort((x, y) => x.azimuth!.compareTo(y.azimuth!));
      for (var i = 0; i < byAz.length; i++) {
        expect(byAz[i].level, i.isEven ? TowerLevel.upper : TowerLevel.lower, reason: 'متناوبة بترتيب الاتّجاه');
      }
      expect(a.values.every((x) => !x.fixed), isTrue);
      expect(a.values.where((x) => x.azimuth != null).every((x) => x.azimuthSource == AzimuthSource.auto), isTrue);
    });

    test('حتميّ: نفس المدخلات ⇒ نفس الرسم على كلّ هاتف', () {
      final x = TowerArrange.arrange(popq());
      final y = TowerArrange.arrange(popq().reversed.toList());
      for (final id in x.keys) {
        expect(y[id]!.placement, x[id]!.placement);
      }
    });

    test('المكتوب بالاسم يُحترم، والباقي يتوزّع حوله', () {
      final devices = [
        dev(1, 'سكتر شمال', model: 'BaseBox 5'),
        dev(2, 'سكتر ب', model: 'BaseBox 5'),
        dev(3, 'سكتر ج', model: 'BaseBox 5'),
      ];
      final a = TowerArrange.arrange(devices);
      expect(a[1]!.azimuth, 0);
      expect(a[1]!.azimuthSource, AzimuthSource.name);
      expect({a[2]!.azimuth, a[3]!.azimuth}, {120, 240});
    });

    test('المثبَّت يبقى حتى مع «رتّبها من جديد»، والتقريبيّ المحفوظ يُعاد حسابه', () {
      final saved = {
        509: const TowerPlacement(deviceId: 509, level: TowerLevel.lower, azimuth: 22, beamwidth: 120, fixed: true),
        1006: const TowerPlacement(deviceId: 1006, level: TowerLevel.upper, azimuth: 300, beamwidth: 90),
        1011: const TowerPlacement(deviceId: 1011, shape: TowerShape.sector),
      };
      final keep = TowerArrange.arrange(popq(), saved: saved);
      expect(keep[509]!.placement, saved[509]);
      expect(keep[509]!.azimuthSource, AzimuthSource.fixed);
      expect(keep[1006]!.azimuth, 300);
      expect(keep[1006]!.azimuthSource, AzimuthSource.saved);
      expect(keep[1011]!.shape, TowerShape.sector, reason: 'الشكل الذي اختاره الوكيل');
      expect(keep[1011]!.shapeSource, ShapeSource.saved);

      final again = TowerArrange.arrange(popq(), saved: saved, rearrange: true);
      expect(again[509]!.placement, saved[509], reason: 'المثبَّت لا يتغيّر');
      expect(again[1006]!.azimuthSource, AzimuthSource.auto);
      expect(again[1011]!.shape, TowerShape.sector, reason: 'الشكل المختار يبقى');
    });
  });

  group('يحتاج انتباهاً', () {
    test('المطفأ أوّلاً، ثمّ CCQ والازدحام والتداخل — بسلّم القسم', () {
      final devices = [
        dev(1, 'جهاز 1', model: 'BaseBox 5'),
        dev(2, 'جهاز 2', model: 'BaseBox 5'),
        dev(3, 'جهاز 3', model: 'BaseBox 5'),
        dev(4, 'جهاز 4', model: 'BaseBox 5', status: 'offline'),
        dev(5, 'لنك', model: 'PowerBeam M5', brand: 'ubnt'),
      ];
      final readings = {
        1: reading(clients: 20, quality: 30, frequency: 5745, width: 20),
        2: reading(clients: 41, quality: 80, frequency: 5745, width: 20),
        3: reading(clients: 10, quality: 55, frequency: 5180, width: 20),
        5: reading(clients: 1, mode: 'sta', signal: -78),
      };
      final alerts = TowerAttention.compute(TowerArrange.arrange(devices, readings: readings), readings);
      expect(alerts.first.deviceId, 4);
      expect(alerts.first.tone, AppTone.danger);
      final byChip = {for (final a in alerts) a.chip: a};
      expect(byChip['جهاز 1 · CCQ 30٪']?.tone, AppTone.danger);
      expect(byChip['جهاز 3 · CCQ 55٪']?.tone, AppTone.warning);
      expect(byChip['جهاز 2 · مزدحم 41']?.tone, AppTone.warning);
      expect(byChip['جهاز 1 وجهاز 2 · تردّد متداخل'], isNotNull);
      expect(byChip['لنك · إشارة -78']?.tone, AppTone.warning);
      expect(alerts.any((a) => a.chip.contains('جهاز 2 · CCQ')), isFalse, reason: '80٪ ممتاز بسلّم القسم');
      final tones = alerts.map((a) => a.tone).toList();
      expect(tones.indexOf(AppTone.warning) > tones.lastIndexOf(AppTone.danger), isTrue);
    });

    test('سبعة سكاتر على قناةٍ واحدة ⇒ تنبيهٌ واحد بالعدد لا ٢١ شريحة', () {
      final devices = [for (var i = 1; i <= 7; i++) dev(i, 'سكتر $i', model: 'BaseBox 5')];
      final readings = {for (var i = 1; i <= 7; i++) i: reading(clients: 10, frequency: 5180, width: 20)};
      final alerts = TowerAttention.compute(TowerArrange.arrange(devices, readings: readings), readings);
      final co = alerts.where((a) => a.chip.contains('متداخل')).toList();
      expect(co, hasLength(1));
      expect(co.single.chip, '7 أجهزة على 5180 · تردّد متداخل');
      expect(co.single.detail, contains('سكتر 7'));
      expect(co.single.otherId, isNotNull, reason: 'يُبرز زوجاً في «من الأعلى»');
    });

    test('تردّدٌ واحد على سكترين ثبّت الوكيل أنّهما متعاكسان ⇒ لا تنبيه', () {
      final devices = [dev(1, 'أ', model: 'BaseBox 5'), dev(2, 'ب', model: 'BaseBox 5')];
      final readings = {1: reading(clients: 5, frequency: 5500), 2: reading(clients: 5, frequency: 5500)};
      final saved = {
        1: const TowerPlacement(deviceId: 1, level: TowerLevel.upper, azimuth: 0, fixed: true),
        2: const TowerPlacement(deviceId: 2, level: TowerLevel.upper, azimuth: 180, fixed: true),
      };
      final alerts = TowerAttention.compute(TowerArrange.arrange(devices, readings: readings, saved: saved), readings);
      expect(alerts.where((a) => a.chip.contains('متداخل')), isEmpty);
    });
  });

  group('السويج والراوتر في الكابينة (المالك ٢٧ أكتوبر: «السويجات ما يظهر بيها شي»)', () {
    test('المنافذ الشغّالة وأنشطها والطاقة، والمعالج المجهول (SwOS) لا «0٪»', () {
      const stats = MikrotikStats(
        cpuLoad: 0,
        memUsedPercent: 0,
        memTotalBytes: 0,
        memFreeBytes: 0,
        uptime: '3w3d12h34m6s',
        version: '7.19.6',
        boardName: 'netPower 16P',
        architectureName: 'arm',
        cpuCount: 2,
        cpuFrequencyMhz: 800,
        temperature: 42,
        voltage: 25.3,
        powerWatts: 47.3,
        interfaces: [],
        pppActiveCount: 0,
        cpuKnown: false,
      );
      final r = TowerReading.fromProbe(
        const ProbeResult(
          vitals: [],
          detail: DeviceDetail(uptime: '3w3d12h34m6s', ports: [
            PortTraffic(name: 'ether1', up: true, rxBps: 180000000, txBps: 9000000),
            PortTraffic(name: 'ether2-ftth', up: true, rxBps: 2000000, txBps: 40000000),
            PortTraffic(name: 'ether3', up: false),
            PortTraffic(name: 'sfp1', up: false),
          ]),
          counters: {},
          raw: stats,
        ),
        at: DateTime(2026, 10, 27),
      );
      expect(r.portsUp, 2);
      expect(r.portsTotal, 4);
      expect(r.busiestPort?.name, 'ether1');
      expect(r.downBps, 180000000);
      expect(r.poeWatts, 47.3);
      expect(r.voltage, 25.3);
      expect(r.cpu, isNull, reason: 'cpuKnown=false');
      expect(r.wireless, isFalse);
    });

    test('مدّة التشغيل بالعربيّ: صيغة RouterOS تُترجَم، والعربيّة تبقى', () {
      expect(TowerText.uptime('3w3d12h34m6s'), '3 أسابيع و3 أيام');
      expect(TowerText.uptime('2d5h'), 'يومين و5 ساعات');
      expect(TowerText.uptime('45m10s'), '45 دقيقة');
      expect(TowerText.uptime('12 يوماً'), '12 يوماً');
      expect(TowerText.uptime(null), '—');
    });
  });

  group('القراءة من جلسة القسم', () {
    test('مايكروتك سكتر: المشتركون ومتوسّط CCQ والإشارة والتردّد، والتنزيل = إرسال الواجهة اللاسلكيّة', () {
      const stats = MikrotikStats(
        cpuLoad: 12,
        memUsedPercent: 40,
        memTotalBytes: 64,
        memFreeBytes: 32,
        uptime: '12d',
        version: '6.49',
        boardName: 'BaseBox 5',
        architectureName: 'mipsbe',
        cpuCount: 1,
        cpuFrequencyMhz: 720,
        temperature: 51,
        interfaces: [],
        pppActiveCount: 0,
        wirelessInterfaces: [
          MikrotikWireless(
            name: 'wlan1',
            ssid: 's1',
            mode: 'ap-bridge',
            band: '5ghz-a/n',
            frequency: 5180,
            channelWidth: 20,
            txPower: 25,
            disabled: false,
            running: true,
          ),
        ],
      );
      final r = TowerReading.fromProbe(const ProbeResult(
        vitals: [],
        detail: DeviceDetail(
          ports: [
            PortTraffic(name: 'ether1', up: true, rxBps: 2000000, txBps: 15000000, linkSpeed: '100Mbps'),
            PortTraffic(name: 'wlan1', up: true, rxBps: 1500000, txBps: 14000000),
          ],
          peers: [
            PeerLink(name: 'a', signal: -60, ccq: 90),
            PeerLink(name: 'b', signal: -70, ccq: 80),
            PeerLink(name: 'c', signal: -65),
          ],
        ),
        counters: {},
        raw: stats,
      ));
      expect(r.wireless, isTrue);
      expect(r.isAccessPoint, isTrue);
      expect(r.clients, 3);
      expect(r.quality, 85);
      expect(r.signal, -65);
      expect(r.frequency, 5180);
      expect(r.channelWidth, 20);
      expect(r.downBps, 14000000);
      expect(r.upBps, 1500000);
      expect(r.linkSpeed, '100Mbps');
      expect(r.temperature, 51);
    });

    test('لنك PtP بطرفٍ واحد: التنزيل = الاتّجاه الأكبر (الوارد) لا الإرسال — إصلاح قلب AirFiber', () {
      // AirFiber/لنك ظهري: مودُه ليس «sta» ولا يخدم مشتركين (طرفٌ واحد)، فكان يُحسب الإرسال (tx)
      // تنزيلاً فيظهر مقلوباً. التنزيل الصحيح = الاتّجاه الأكبر (الوارد للبرج): rx=246 > tx=15.
      const stats = MikrotikStats(
        cpuLoad: 8,
        memUsedPercent: 30,
        memTotalBytes: 64,
        memFreeBytes: 44,
        uptime: '107d',
        version: '6.49',
        boardName: 'LHG 60',
        architectureName: 'arm',
        cpuCount: 1,
        cpuFrequencyMhz: 800,
        temperature: 40,
        interfaces: [],
        pppActiveCount: 0,
        wirelessInterfaces: [
          MikrotikWireless(
            name: 'wlan1',
            ssid: 'backhaul',
            mode: 'bridge',
            band: '5ghz-a/n',
            frequency: 5500,
            channelWidth: 40,
            txPower: 27,
            disabled: false,
            running: true,
          ),
        ],
      );
      final r = TowerReading.fromProbe(const ProbeResult(
        vitals: [],
        detail: DeviceDetail(
          ports: [
            PortTraffic(name: 'wlan1', up: true, rxBps: 246000000, txBps: 15000000),
          ],
          peers: [PeerLink(name: 'remote', signal: -54, ccq: 99)],
        ),
        counters: {},
        raw: stats,
      ));
      expect(r.clients, 1);
      expect(r.downBps, 246000000, reason: 'التنزيل = الوارد الأكبر، لا الإرسال');
      expect(r.upBps, 15000000);
    });

    test('بلا علامةٍ معروفة: لا لاسلكيّ ولا مشتركين — شرطة لا صفر', () {
      final r = TowerReading.fromProbe(const ProbeResult(vitals: [], detail: DeviceDetail(), counters: {}));
      expect(r.wireless, isFalse);
      expect(r.clients, isNull);
      expect(r.quality, isNull);
      expect(r.downBps, isNull);
    });
  });

  test('نصوص: الاتّجاهات الثمانية والمعدّلات', () {
    expect(TowerText.dir(0), 'شمال');
    expect(TowerText.dir(44), 'شمال شرق');
    expect(TowerText.dir(135), 'جنوب شرق');
    expect(TowerText.dir(359), 'شمال');
    expect(TowerText.dir(-90), 'غرب');
    expect(TowerText.bps(null), '—');
    expect(TowerText.bps(14000000), '14 Mbps');
    expect(TowerText.bps(3400000), '3.4 Mbps');
    expect(TowerText.bps(820000), '820 Kbps');
  });

  test('المكان يذهب للخادم ويعود كما هو', () {
    const p = TowerPlacement(deviceId: 7, level: TowerLevel.lower, azimuth: 350, beamwidth: 90, fixed: true, shape: TowerShape.sw);
    expect(p.toJson()['shape'], 'switch');
    expect(TowerPlacement.fromJson(p.toJson()), p);
    expect(TowerPlacement.fromJson({'device_id': 7, 'azimuth': 370})!.azimuth, 10);
    expect(TowerPlacement.fromJson({'device_id': 0}), isNull);
    final layouts = TowerLayouts.fromJson({
      'success': true,
      'towers': [
        {'region_id': 1, 'tower_type': 'roof', 'height_m': 18, 'rings': 2},
        {'region_id': -3},
      ],
      'placements': [p.toJson(), 'x'],
    });
    expect(layouts.towers[1], const TowerSettings(regionId: 1, type: TowerType.roof, heightM: 18, rings: 2));
    expect(layouts.towers.length, 1);
    expect(layouts.placements[7], p);
    expect(TowerLayouts.fromJson({'success': false}).placements, isEmpty);
  });

  group('تزاحم الأجهزة (المالك ٢٩ أكتوبر: «حل مشكلة تزاحم الاجهزه»)', () {
    test('spreadApart: المتطابقان يتباعدان أفقيّاً بعرض الصندوق، والبعيدان لا يتحرّكان، والكلّ داخل الحدود', () {
      const box = Size(50, 64);
      const bounds = Rect.fromLTWH(0, 0, 390, 430);
      final out = spreadApart(const [Offset(200, 200), Offset(200, 200), Offset(60, 380)], box, bounds);
      expect((out[0].dx - out[1].dx).abs(), greaterThanOrEqualTo(box.width + 6 - 0.6));
      expect(out[0].dy, 200);
      expect(out[2], const Offset(60, 380));
      for (final o in out) {
        expect(bounds.contains(o), isTrue);
      }
      // عند الحافّة: يُحبس الأوّل بالحدّ فيتمدّد الثاني نحو الداخل — لا يخرج أحدٌ من المنظر.
      final edge = spreadApart(const [Offset(20, 100), Offset(22, 100)], box, bounds);
      expect(edge.every((o) => o.dx >= box.width / 2 && o.dx <= 390 - box.width / 2), isTrue);
      expect((edge[0].dx - edge[1].dx).abs(), greaterThanOrEqualTo(box.width));
    });

    test('spreadApart: يخرج من العائق (الكابينة/أزرار المنظر) من أقرب جهة', () {
      final out = spreadApart(
        const [Offset(300, 380)],
        const Size(50, 64),
        const Rect.fromLTWH(0, 0, 390, 430),
        obstacles: const [Rect.fromLTWH(270, 360, 110, 70)],
      );
      final b = Rect.fromCenter(center: out.single, width: 50, height: 64);
      expect(b.overlaps(const Rect.fromLTWH(270, 360, 110, 70)), isFalse);
    });

    test('armRadius: الحلقة تتّسع بعدد أجهزتها حتى حدّ المنظر، وجهازٌ وحده على الهيكل كما كان', () {
      final geo = TowerGeometry(const Size(390, 430), const TowerSettings(regionId: 1));
      final i = geo.ringOf(TowerLevel.upper);
      final base = geo.ringRadius(i) + 8;
      expect(geo.armRadius(i, 1), base);
      expect(geo.armRadius(i, 5), greaterThan(base));
      expect(geo.armRadius(i, 5), greaterThan(geo.armRadius(i, 3)));
      expect(geo.armRadius(i, 40), 390 / 2 - 48);
      // الموضع على الحلقة الواسعة: الأماميّ بعيدٌ عن محور البرج بنصف القطر الجديد.
      final p = geo.place(TowerLevel.upper, 190, 100, crowd: 5);
      expect((p.x - geo.cx).abs(), closeTo(geo.armRadius(i, 5), 0.5));
    });
  });

  group('الأولت بعرض البرج (المالك ٢٩ أكتوبر: «الاولتي مجاي يجلب بينات في وضع البرج»)', () {
    VsolOltStats stats({BdcomChassis? chassis}) => VsolOltStats(
          uptime: const Duration(days: 3),
          uplinks: const [
            VsolUplink(index: 1, name: 'GE1', up: true, speedMbps: 1000, rxBytes: 0, txBytes: 0),
            VsolUplink(index: 2, name: 'GE2', up: false, speedMbps: 0, rxBytes: 0, txBytes: 0),
          ],
          ponPorts: const [
            VsolPonPort(index: 1, slot: 0, port: 1, up: true, rxBytes: 0, txBytes: 0, onuTotal: 2, onuOnline: 2),
            VsolPonPort(index: 2, slot: 0, port: 2, up: false, rxBytes: 0, txBytes: 0, onuTotal: 1, onuOnline: 0),
          ],
          onus: const [
            VsolOnu(ifIndex: 11, slot: 0, ponPort: 1, onuId: 1, online: true),
            VsolOnu(ifIndex: 12, slot: 0, ponPort: 1, onuId: 2, online: true),
            VsolOnu(ifIndex: 21, slot: 0, ponPort: 2, onuId: 1, online: false),
          ],
          chassis: chassis,
        );

    test('من لقطة البنية نفسها (oltProbeResult): المشتركون ومنافذ PON والربط والمعالج والحرارة', () {
      final r = TowerReading.fromProbe(oltProbeResult(stats(chassis: const BdcomChassis(cpuPct: 14, boxTempC: 46, ramBytes: 268435456))));
      final o = r.olt!;
      expect([o.onusOnline, o.onusTotal, o.ponUp, o.pons.length, o.uplinksUp, o.uplinksTotal, o.ramMb], [2, 3, 1, 2, 1, 2, 256]);
      expect(o.pons.first, (label: o.pons.first.label, up: true, online: 2, total: 2));
      expect(o.onlinePct!.round(), 67);
      expect([r.cpu, r.temperature], [14, 46]);
      expect(r.uptime, isNotNull);
      expect(r.wireless, isFalse);
      expect(r.clients, isNull, reason: 'مشتركو الأولت في olt لا في عدّاد اللاسلكيّ');
    });

    test('VSOL بلا مجسّ معالج: «—» لا صفر، وأولت بلا مشتركين بلا نسبة', () {
      final r = TowerReading.fromProbe(oltProbeResult(stats()));
      expect([r.cpu, r.temperature, r.olt!.ramMb], [null, null, null]);
      expect(const VsolOltStats().onusTotal, 0);
      expect(OltSummary.of(const VsolOltStats()).onlinePct, isNull);
    });

    test('بلا لقطة (قراءة الألياف الخفيفة بلا حمولة) ⇒ لا خلاصة أولت', () {
      final r = TowerReading.fromProbe(const ProbeResult(vitals: [], detail: DeviceDetail(), counters: {}));
      expect(r.olt, isNull);
    });
  });
}
