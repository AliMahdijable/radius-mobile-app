import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/theme/colors.dart';

/// أجهزة «البطاقات الكبيرة» للاختبار واللقطات — بياناتٌ تجريبيّة بشكل ما تُعيده العلامات فعلاً (لا أسماء مشتركين حقيقيّين):
/// سكتر UBNT بأحد عشر متّصلاً، لنك ميموزا، سكتر ميكروتك محطّةً (60GHz)، سويتش netPower بـPoE، أولت BDCOM بأربعة منافذ PON،
/// راوتر CCR بجلسات PPP، ومعطّل، وبلا بيانات دخول، وجهازٌ ينتظر قراءته الأولى.
class DeviceCardsFixture {
  DeviceCardsFixture(this.now);
  final DateTime now;

  NetworkDevice _d(int id, String name, String type, String brand, String model, String ip,
          {String status = 'online', int? ms = 14, bool creds = true, String protocol = 'api', Duration? since}) =>
      NetworkDevice(
        id: id,
        adminId: '1',
        name: name,
        type: type,
        brand: brand,
        model: model,
        ip: ip,
        port: protocol == 'snmp' ? 161 : 8728,
        protocol: protocol,
        hasCredentials: creds,
        lastStatus: status,
        lastResponseMs: ms,
        statusSince: since == null ? null : now.subtract(since),
        createdAt: DateTime(2026, 9, 1),
      );

  late final sector = _d(1, 'سكتر برج الشهداء ١', 'sector', 'ubnt', 'Rocket Prism 5AC Gen2', '10.70.241.10', ms: 9);
  late final link = _d(2, 'لنك الحيدريّة ⇄ البرج الرئيسيّ', 'link', 'mimosa', 'B5c', '10.70.240.2', ms: 11, protocol: 'snmp');
  late final link60 = _d(3, 'لنك الكورنيش 60G', 'link', 'mikrotik', 'Cube 60Pro ac', '10.70.240.6', ms: 7);
  late final switchDev = _d(4, 'سويتش غرفة البرج', 'switch', 'mikrotik', 'netPower 16P', '10.70.241.2', ms: 5);
  late final olt = _d(5, 'أولت المركز', 'other', 'bdcom', 'BDCOM P3600-04', '10.83.150.2', ms: 18, protocol: 'snmp');
  late final router = _d(6, 'راوتر المركز CCR', 'router', 'mikrotik', 'CCR1036-8G-2S+', '10.70.0.1', ms: 4);
  late final down = _d(7, 'سكتر برج الزهراء ٢', 'sector', 'ubnt', 'LiteBeam 5AC Gen2', '10.70.242.12',
      status: 'offline', ms: null, since: const Duration(hours: 3, minutes: 10));
  late final noCreds = _d(8, 'سويتش الطابق الثاني', 'switch', 'cisco', 'WS-C2960X-24TS-L', '10.70.241.3', creds: false, ms: 6, protocol: 'ssh');
  late final pending = _d(9, 'سكتر الكورنيش ٣', 'sector', 'mikrotik', 'RB921GS-5HPacD-19S', '10.70.243.4', ms: 12);

  List<NetworkDevice> get all => [sector, link, link60, switchDev, olt, router, down, noCreds, pending];

  VitalsState stateOf(NetworkDevice d) => switch (d.id) {
        1 => _sector(),
        2 => _link(),
        3 => _link60(),
        4 => _switch(),
        5 => _olt(),
        6 => _router(),
        8 => VitalsState(error: 'بلا بيانات دخول', at: now),
        9 => const VitalsState(loading: true),
        _ => VitalsState.idle,
      };

  VitalsState _sector() {
    const names = [
      'ali-home', 'hussein.k', 'zainab-2', 'abbas-cafe', 'murtadha', 'noor-shop', 'karrar99', 'ahmed.saad', 'fatima-h',
      'yaseen-net', 'm.jawad',
    ];
    const sig = [-79, -74, -71, -68, -66, -63, -61, -59, -58, -56, -54];
    const ccq = [61, 72, 84, 88, 90, 93, 95, 96, 97, 98, 99];
    return VitalsState(
      at: now.subtract(const Duration(seconds: 6)),
      vitals: const [
        Vital(label: '—', value: '—', tone: AppTone.neutral, icon: LucideIcons.signal),
        Vital(label: 'المعالج', value: '23', unit: '٪', tone: AppTone.success, icon: LucideIcons.cpu),
        Vital(label: 'الحرارة', value: '52', unit: '°', tone: AppTone.success, icon: LucideIcons.thermometer),
      ],
      detail: DeviceDetail(
        uptime: '12 يوماً',
        firmware: 'XC.v8.7.11',
        model: 'Rocket Prism 5AC Gen2',
        ports: const [
          PortTraffic(name: 'eth0', up: true, rxBps: 8100000, txBps: 61400000, linkSpeed: '1000M'),
          PortTraffic(name: 'ath0', up: true, rxBps: 61000000, txBps: 8000000),
        ],
        peers: [
          for (var i = 0; i < names.length; i++)
            PeerLink(name: names[i], signal: sig[i], ccq: ccq[i], rxRate: 130 + i * 20, txRate: 87 + i * 15, uptimeSec: 3600 * (i + 3)),
        ],
        peersLabel: 'المحطّات',
        glance: const DeviceGlance(
          uptimeSec: 86400 * 12 + 3600 * 5,
          peersKnown: true,
          cpu: 23,
          temp: 52,
          noise: -94,
          freqMhz: 5180,
          widthMhz: 40,
          ssid: 'Shuhada-1',
          mode: 'ap-ptmp',
          isAp: true,
        ),
      ),
    );
  }

  VitalsState _link() => VitalsState(
        at: now.subtract(const Duration(seconds: 4)),
        vitals: const [
          Vital(label: 'الاستقبال', value: '-52', unit: 'dBm', tone: AppTone.success, icon: LucideIcons.signal),
          Vital(label: 'معدّل RX', value: '520', unit: 'M', tone: AppTone.success, icon: LucideIcons.gauge),
          Vital(label: 'الحرارة', value: '47', unit: '°', tone: AppTone.success, icon: LucideIcons.thermometer),
        ],
        detail: const DeviceDetail(
          model: 'B5c',
          glance: DeviceGlance(
            uptimeSec: 86400 * 41 + 3600 * 2,
            linkUptime: true,
            temp: 47,
            signal: -52,
            snr: 31,
            noise: -88,
            freqMhz: 5745,
            widthMhz: 80,
            rxRateMbps: 520,
            txRateMbps: 433,
            ssid: 'Haidariya-PTP',
            isAp: false,
          ),
        ),
      );

  VitalsState _link60() => VitalsState(
        at: now.subtract(const Duration(seconds: 9)),
        vitals: const [
          Vital(label: 'المعالج', value: '11', unit: '٪', tone: AppTone.success, icon: LucideIcons.cpu),
          Vital(label: 'الذاكرة', value: '34', unit: '٪', tone: AppTone.success, icon: LucideIcons.memoryStick),
          Vital(label: 'الحرارة', value: '58', unit: '°', tone: AppTone.success, icon: LucideIcons.thermometer),
        ],
        detail: const DeviceDetail(
          ports: [
            PortTraffic(name: 'ether1', up: true, rxBps: 14200000, txBps: 186300000, linkSpeed: '1Gbps'),
            PortTraffic(name: 'wlan60-1', up: true, rxBps: 186000000, txBps: 14000000),
          ],
          peers: [PeerLink(name: '04:D6:AA:1B:2C:3D', signal: -61, txRate: 1540)],
          peersLabel: 'الطرف الآخر',
          glance: DeviceGlance(
            uptimeSec: 86400 * 6 + 3600 * 9,
            peersKnown: true,
            cpu: 11,
            mem: 34,
            temp: 58,
            signal: -61,
            signalPct: 87,
            freqMhz: 60480,
            distanceM: 412,
            txRateMbps: 1540,
            isAp: false,
          ),
        ),
      );

  VitalsState _switch() => VitalsState(
        at: now.subtract(const Duration(seconds: 3)),
        vitals: const [
          Vital(label: 'المعالج', value: '7', unit: '٪', tone: AppTone.success, icon: LucideIcons.cpu),
          Vital(label: 'الذاكرة', value: '41', unit: '٪', tone: AppTone.success, icon: LucideIcons.memoryStick),
          Vital(label: 'الحرارة', value: '42', unit: '°', tone: AppTone.success, icon: LucideIcons.thermometer),
        ],
        detail: DeviceDetail(
          ports: [
            const PortTraffic(name: 'ether1-uplink', up: true, rxBps: 412000000, txBps: 51300000, linkSpeed: '1Gbps'),
            for (var i = 2; i <= 16; i++)
              PortTraffic(
                name: 'ether$i',
                up: i <= 12,
                rxBps: i <= 12 ? (16 - i) * 3100000 : null,
                txBps: i <= 12 ? (16 - i) * 21000000 : null,
                linkSpeed: i <= 12 ? (i == 5 ? '100Mbps' : '1Gbps') : null,
              ),
            const PortTraffic(name: 'sfp17', up: true, rxBps: 63000000, txBps: 402000000, linkSpeed: '10Gbps'),
            const PortTraffic(name: 'sfp18', up: false),
          ],
          glance: const DeviceGlance(uptimeSec: 86400 * 63 + 3600 * 4, cpu: 7, mem: 41, temp: 42, voltage: 25.3, poeWatts: 47.3),
        ),
      );

  VitalsState _olt() => VitalsState(
        at: now.subtract(const Duration(seconds: 8)),
        vitals: const [
          Vital(label: 'المشتركون', value: '231', unit: '/248', tone: AppTone.success, icon: LucideIcons.users),
          Vital(label: 'منافذ PON', value: '3', unit: '/4', tone: AppTone.warning, icon: LucideIcons.splitSquareVertical),
          Vital(label: 'المعالج', value: '18', unit: '٪', tone: AppTone.success, icon: LucideIcons.cpu),
        ],
        detail: const DeviceDetail(
          model: 'BDCOM P3600-04',
          ports: [
            PortTraffic(name: 'GE0/1', up: true),
            PortTraffic(name: 'GE0/2', up: false),
            PortTraffic(name: 'TGE0/1', up: true),
          ],
          glance: DeviceGlance(
            uptimeSec: 86400 * 27 + 3600 * 11,
            cpu: 18,
            temp: 44,
            onusOnline: 231,
            onusTotal: 248,
            pons: [
              PonGlance('EPON0/1', up: true, online: 61, total: 62),
              PonGlance('EPON0/2', up: true, online: 58, total: 64),
              PonGlance('EPON0/3', up: true, online: 112, total: 122),
              PonGlance('EPON0/4', up: false, online: 0, total: 0),
            ],
            uplinksUp: 2,
            uplinksTotal: 3,
          ),
        ),
      );

  VitalsState _router() => VitalsState(
        at: now.subtract(const Duration(seconds: 5)),
        vitals: const [
          Vital(label: 'المعالج', value: '38', unit: '٪', tone: AppTone.success, icon: LucideIcons.cpu),
          Vital(label: 'الذاكرة', value: '71', unit: '٪', tone: AppTone.warning, icon: LucideIcons.memoryStick),
          Vital(label: 'الحرارة', value: '61', unit: '°', tone: AppTone.warning, icon: LucideIcons.thermometer),
        ],
        detail: const DeviceDetail(
          ports: [
            PortTraffic(name: 'sfp-sfpplus1-WAN', up: true, rxBps: 1830000000, txBps: 212000000, linkSpeed: '10Gbps'),
            PortTraffic(name: 'ether2-towers', up: true, rxBps: 198000000, txBps: 1210000000, linkSpeed: '1Gbps'),
            PortTraffic(name: 'ether3-olt', up: true, rxBps: 21000000, txBps: 640000000, linkSpeed: '1Gbps'),
            PortTraffic(name: 'ether4', up: false),
          ],
          glance: DeviceGlance(uptimeSec: 86400 * 9 + 3600 * 3, cpu: 38, mem: 71, temp: 61, voltage: 24.1, ppp: 1284),
        ),
      );
}
