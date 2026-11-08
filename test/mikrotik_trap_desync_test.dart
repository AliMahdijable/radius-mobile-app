import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/mikrotik_api.dart';
import 'package:rad_mysvcs/api/mikrotik_binary_api.dart';

/// ٨ نوفمبر — المالك (سكتر BaseBox 5 · RouterOS 6.49.19): WinBox يعرض ستّة عملاء وتطبيق الحاسوب «العملاء المتّصلون 0 —
/// registration-table فارغ». العلّة في قارئ الـAPI: RouterOS يُنهي الأمر المرفوض بـ`!trap` ثمّ `!done`، وكان `!done`
/// يُترك فيقرأه الأمر التالي ردّاً له وتتأخّر كلّ الردود بعده أمراً — وعلى RouterOS 6 يُرفض `/interface/w60g/print` و
/// `/interface/wifi/print` قبل جدول التسجيل مباشرةً.
///
/// خادمٌ وهميّ على loopback (مقابسُ حقيقيّة) بسلوك الجهاز: أمرٌ لا يعرفه ⇒ `!trap` ثمّ `!done`.
class _FakeRouterOs {
  _FakeRouterOs(this.replies, {this.delays = const {}});

  /// الأمر ← جمله (كلّ جملةٍ كلماتها)، ثمّ `!done`. أمرٌ غائب ⇒ `!trap … no such command prefix` ثمّ `!done`.
  final Map<String, List<List<String>>> replies;
  final Map<String, Duration> delays;
  final asked = <String>[];
  bool omitDoneAfterTrap = false;
  late ServerSocket _server;

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
    return _server.port;
  }

  Future<void> stop() => _server.close();

  void _serve(Socket s) {
    final buf = <int>[];
    var chain = Future<void>.value();
    s.listen((data) {
      buf.addAll(data);
      while (true) {
        final sentence = _take(buf);
        if (sentence == null) break;
        chain = chain.then((_) => _answer(s, sentence));
      }
    }, onError: (_) {}, cancelOnError: true);
  }

  static List<String>? _take(List<int> buf) {
    var i = 0;
    final words = <String>[];
    while (true) {
      if (i >= buf.length) return null;
      final b0 = buf[i];
      int len;
      int next;
      if (b0 < 0x80) {
        len = b0;
        next = i + 1;
      } else {
        if (i + 1 >= buf.length) return null;
        len = ((b0 & 0x3F) << 8) | buf[i + 1];
        next = i + 2;
      }
      if (len == 0) {
        buf.removeRange(0, next);
        return words;
      }
      if (next + len > buf.length) return null;
      words.add(utf8.decode(buf.sublist(next, next + len)));
      i = next + len;
    }
  }

  static List<int> _enc(List<String> words) {
    final out = <int>[];
    for (final w in words) {
      final bytes = utf8.encode(w);
      final n = bytes.length;
      if (n < 0x80) {
        out.add(n);
      } else {
        final v = n | 0x8000;
        out
          ..add((v >> 8) & 0xFF)
          ..add(v & 0xFF);
      }
      out.addAll(bytes);
    }
    out.add(0);
    return out;
  }

  Future<void> _answer(Socket s, List<String> sentence) async {
    final cmd = sentence.first;
    asked.add(cmd);
    if (cmd == '/login') {
      s.add(_enc(['!done']));
      return;
    }
    final wait = delays[cmd];
    if (wait != null) await Future<void>.delayed(wait);
    final r = replies[cmd];
    if (r == null) {
      s.add(_enc(['!trap', '=category=0', '=message=no such command prefix']));
      if (!omitDoneAfterTrap) s.add(_enc(['!done']));
      return;
    }
    for (final w in r) {
      s.add(_enc(w));
    }
    s.add(_enc(['!done']));
  }
}

/// ماكات عملاء السكتر الستّة كما في WinBox المالك.
const _macs = [
  'F4:E2:C6:92:D5:F3',
  '68:72:51:5A:B8:3C',
  'F4:92:BF:E2:31:9E',
  '18:E8:29:32:DA:0D',
  '70:A7:41:20:56:0D',
  '70:A7:41:20:D0:0C',
];

/// BaseBox 5 · RouterOS 6.49.19 كما يردّ عبر الـAPI — بلا حزمتي w60g وwifi (أمراهما غائبان ⇒ !trap ثمّ !done).
Map<String, List<List<String>>> _baseBox5() => {
      '/system/resource/print': [
        [
          '!re', '=uptime=6w3d01:02:03', '=version=6.49.19 (long-term)', '=board-name=BaseBox 5', '=cpu-load=7',
          '=total-memory=67108864', '=free-memory=33554432', '=architecture-name=mipsbe', '=cpu-count=1',
          '=cpu-frequency=720',
        ],
      ],
      '/interface/print': [
        ['!re', '=name=ether1', '=type=ether', '=running=true', '=disabled=false', '=rx-byte=1000', '=tx-byte=2000'],
        ['!re', '=name=wlan1', '=type=wlan', '=running=true', '=disabled=false', '=rx-byte=3000', '=tx-byte=4000'],
        ['!re', '=name=bridge1', '=type=bridge', '=running=true', '=disabled=false', '=rx-byte=5000', '=tx-byte=6000'],
      ],
      '/system/health/print': [
        ['!re', '=voltage=24', '=temperature=40'],
      ],
      '/ppp/active/print': [],
      '/interface/ethernet/monitor': [
        ['!re', '=name=ether1', '=status=link-ok', '=rate=100Mbps', '=full-duplex=true'],
      ],
      '/interface/bridge/port/print': [
        ['!re', '=interface=ether1', '=bridge=bridge1', '=disabled=false'],
        ['!re', '=interface=wlan1', '=bridge=bridge1', '=disabled=false'],
      ],
      '/interface/wireless/print': [
        [
          '!re', '=name=wlan1', '=ssid=HASSAN EARTHLINK', '=mode=ap-bridge', '=band=5ghz-a', '=frequency=5190',
          '=channel-width=20mhz', '=disabled=false', '=running=true',
        ],
      ],
      '/interface/wireless/registration-table/print': [
        for (var i = 0; i < _macs.length; i++)
          [
            '!re', '=interface=wlan1', '=mac-address=${_macs[i]}', '=radio-name=R$i', '=signal-strength=-4$i@6Mbps',
            '=tx-rate=54Mbps', '=rx-rate=36Mbps', '=uptime=4d07:01:00', '=tx-ccq=90', '=rx-ccq=88',
          ],
      ],
      '/ip/dhcp-server/lease/print': [],
      '/interface/wireless/access-list/print': [
        ['!re', '=mac-address=${_macs[2]}', '=comment=Mustfa aljmael'],
      ],
      '/ip/arp/print': [],
    };

void main() {
  setUp(() {
    MikrotikApi.resetRoutesForTest();
    MikrotikApi.resetSshFallbackForTest();
    MikrotikBinaryClient.trapDoneWait = const Duration(seconds: 2);
  });

  test('RouterOS 6 بلا w60g ولا wifi: جدول التسجيل يصل بعملائه الستّة وأسماؤهم من access-list (لا ردودٌ مُزاحة)', () async {
    final fake = _FakeRouterOs(_baseBox5());
    final port = await fake.start();
    try {
      final s = await MikrotikApi.fetchStatsFor(
        ip: '127.0.0.1',
        protocol: 'api',
        apiPort: port,
        creds: const {'user': 'admin', 'pass': 'x'},
      );
      expect(s.via, 'API');
      expect(s.boardName, 'BaseBox 5');
      expect(s.wirelessInterfaces.map((w) => w.name), ['wlan1']);
      expect(s.wirelessClients.map((c) => c.mac).toList(), _macs, reason: 'كانت صفراً: الجدول يقرأ !done أمر wifi');
      expect(s.wirelessClients.firstWhere((c) => c.mac == _macs[2]).hostname, 'Mustfa aljmael',
          reason: 'الاسم من access-list للماك نفسه — كانت صفوف جدول التسجيل تُقرأ «عقود DHCP»');
      expect(s.wirelessClients.first.signalStrength, -40);
      expect(fake.asked, containsAllInOrder(['/interface/w60g/print', '/interface/wifi/print', '/interface/wireless/registration-table/print']));
    } finally {
      await fake.stop();
    }
  });

  test('عميل الـAPI: الأمر المرفوض (!trap ثمّ !done) يُرمى بسببه، والأمر التالي يأخذ ردّه هو', () async {
    final fake = _FakeRouterOs({
      '/a/print': [
        ['!re', '=name=x'],
      ],
    });
    final port = await fake.start();
    final c = MikrotikBinaryClient(host: '127.0.0.1', port: port, user: 'u', pass: 'p');
    try {
      await c.connect();
      await c.login();
      await expectLater(
        c.query(['/nope/print']),
        throwsA(isA<MikrotikBinaryException>().having((e) => e.message, 'message', contains('no such command'))),
      );
      expect(await c.query(['/a/print']), [
        {'name': 'x'},
      ]);
      expect(await c.query(['/a/print']), [
        {'name': 'x'},
      ]);
    } finally {
      await c.close();
      await fake.stop();
    }
  });

  test('!trap بلا !done: الاتّصال يُعدّ مكسوراً — الأمر التالي يُرفض لا يقرأ بقايا غيره', () async {
    MikrotikBinaryClient.trapDoneWait = const Duration(milliseconds: 300);
    final fake = _FakeRouterOs({
      '/a/print': [
        ['!re', '=name=x'],
      ],
    })
      ..omitDoneAfterTrap = true;
    final port = await fake.start();
    final c = MikrotikBinaryClient(host: '127.0.0.1', port: port, user: 'u', pass: 'p');
    try {
      await c.connect();
      await c.login();
      await expectLater(
        c.query(['/nope/print']),
        throwsA(isA<MikrotikBinaryException>().having((e) => e.message, 'message', contains('no such command'))),
        reason: 'سبب الفشل المفهوم لا «مهلة» — المنادي يقرّر به طريقاً آخر',
      );
      await expectLater(c.query(['/a/print']), throwsA(isA<MikrotikBinaryException>()));
    } finally {
      await c.close();
      await fake.stop();
    }
  });

  test('منادٍ تخلّى عن أمرٍ بطيء (Future.timeout): الأمر التالي ينتظر دوره ويأخذ ردّه هو لا ردّ البطيء', () async {
    final fake = _FakeRouterOs({
      '/slow/print': [
        ['!re', '=name=slow'],
      ],
      '/a/print': [
        ['!re', '=name=x'],
      ],
    }, delays: const {'/slow/print': Duration(milliseconds: 400)});
    final port = await fake.start();
    final c = MikrotikBinaryClient(host: '127.0.0.1', port: port, user: 'u', pass: 'p');
    try {
      await c.connect();
      await c.login();
      await expectLater(
        c.query(['/slow/print']).timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      expect(await c.query(['/a/print']), [
        {'name': 'x'},
      ]);
    } finally {
      await c.close();
      await fake.stop();
    }
  });
}
