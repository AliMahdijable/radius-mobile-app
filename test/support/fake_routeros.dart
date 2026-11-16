import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;

/// جهاز RouterOS وهميّ يتكلّم الـAPI الثنائيّ (8728) على loopback — بقواعد الجهاز الحقيقيّ كما في التوثيق الرسميّ:
/// الدخول الحديث (6.43+: `/login =name= =password=` ⇐ `!done`)، والقديم بالتحدّي ([legacyLogin]: `!done =ret=<hex>` ثمّ
/// `=response=00<md5(0+pass+challenge)>`)، والرفض `!trap =message=invalid user name or password (6)` ثمّ `!done`، والأمر الذي لا
/// يعرفه `!trap no such command prefix` ثمّ `!done`. يسجّل كلّ ما يُرسَل ليُثبت الاختبار أنّنا نقرأ وحدنا.
class FakeRouterOs {
  FakeRouterOs({this.user = 'admin', this.pass = 'mt-pass', this.legacyLogin = false});

  String user;
  String pass;

  /// RouterOS قبل 6.43 (دخول التحدّي).
  bool legacyLogin;

  /// صفوف كلّ أمر `print` (المفتاح: الأمر كما هو) — غائبٌ ⇒ «no such command».
  final rows = <String, List<Map<String, String>>>{};

  /// ردود `monitor`/`monitor-traffic`: المفتاح `<الأمر>|<numbers أو interface>`.
  final monitors = <String, Map<String, String>>{};

  /// الأوامر كما وصلت (بعد الدخول)، والجمل كاملة، وعدد الدخولات والاتّصالات.
  final asked = <String>[];
  final sentences = <List<String>>[];
  int logins = 0;
  int failedLogins = 0;
  int connections = 0;
  int open = 0;
  late ServerSocket _server;

  int get port => _server.port;

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
    return _server.port;
  }

  Future<void> stop() => _server.close();

  /// أوامر كتابة/عمليّات أو قراءة فيها أسرار — لا يجوز أن يظهر منها شيء.
  Iterable<String> get forbidden => asked.where((c) {
        final low = c.toLowerCase();
        return low.endsWith('/set') ||
            low.endsWith('/add') ||
            low.endsWith('/remove') ||
            low.endsWith('/enable') ||
            low.endsWith('/disable') ||
            low.contains('reboot') ||
            low.contains('reset-configuration') ||
            low.contains('shutdown') ||
            low == '/interface/pppoe-client/print' ||
            low.startsWith('/user') ||
            low.startsWith('/export') ||
            low.contains('/password');
      });

  void _serve(Socket s) {
    connections++;
    open++;
    final buf = <int>[];
    var authed = false;
    String? challengeHex;
    var chain = Future<void>.value();
    s.listen((data) {
      buf.addAll(data);
      while (true) {
        final sentence = _take(buf);
        if (sentence == null) break;
        chain = chain.then((_) async {
          final cmd = sentence.first;
          final p = _params(sentence);
          if (cmd == '/login') {
            if (legacyLogin && !p.containsKey('response')) {
              // أوّل /login في RouterOS القديم: تحدٍّ مهما حمل
              final ch = List<int>.generate(16, (i) => (i * 37 + 11) & 0xFF);
              challengeHex = ch.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
              s.add(_enc(['!done', '=ret=$challengeHex']));
              return;
            }
            final ok = legacyLogin
                ? p['name'] == user && p['response'] == _expected(pass, challengeHex)
                : p['name'] == user && p['password'] == pass;
            if (ok) {
              logins++;
              authed = true;
              s.add(_enc(['!done']));
            } else {
              failedLogins++;
              s.add(_enc(['!trap', '=message=invalid user name or password (6)']));
              s.add(_enc(['!done']));
            }
            return;
          }
          if (!authed) {
            s.add(_enc(['!trap', '=message=not logged in']));
            s.add(_enc(['!done']));
            return;
          }
          asked.add(cmd);
          sentences.add(sentence);
          if (cmd.endsWith('/monitor') || cmd.endsWith('/monitor-traffic')) {
            final key = '$cmd|${p['numbers'] ?? p['interface'] ?? ''}';
            final m = monitors[key];
            if (m == null) {
              s.add(_enc(['!trap', '=message=no such item']));
              s.add(_enc(['!done']));
              return;
            }
            s.add(_enc(['!re', for (final e in m.entries) '=${e.key}=${e.value}']));
            s.add(_enc(['!done']));
            return;
          }
          final r = rows[cmd];
          if (r == null) {
            s.add(_enc(['!trap', '=category=0', '=message=no such command prefix']));
            s.add(_enc(['!done']));
            return;
          }
          final pl = p['.proplist']?.split(',').toSet();
          for (final row in r) {
            s.add(_enc([
              '!re',
              for (final e in row.entries)
                if (pl == null || pl.contains(e.key)) '=${e.key}=${e.value}',
            ]));
          }
          s.add(_enc(['!done']));
        });
      }
    }, onError: (_) {}, onDone: () {
      open--;
      s.destroy();
    }, cancelOnError: true);
  }

  static String _expected(String pass, String? challengeHex) {
    if (challengeHex == null) return '';
    final ch = [for (var i = 0; i < challengeHex.length; i += 2) int.parse(challengeHex.substring(i, i + 2), radix: 16)];
    return '00${md5.convert([0, ...utf8.encode(pass), ...ch])}';
  }

  static Map<String, String> _params(List<String> words) {
    final out = <String, String>{};
    for (final w in words.skip(1)) {
      if (!w.startsWith('=')) continue;
      final eq = w.indexOf('=', 1);
      if (eq < 0) continue;
      out[w.substring(1, eq)] = w.substring(eq + 1);
    }
    return out;
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

  // ── أجهزة جاهزة بشكل ردودها الحقيقيّ ──────────────────────────────

  /// نانو SXT Lite5 بوضع station-bridge على RouterOS 6.48.6، يطلب PPPoE بنفسه، وكيبله 100 Full.
  void sxtNano({bool connected = true, int signal = -63, int snr = 38}) {
    rows['/system/resource/print'] = [
      {'uptime': '2w3d4h5m6s', 'version': '6.48.6 (long-term)', 'board-name': 'SXT Lite5', 'cpu-load': '7'},
    ];
    rows['/system/identity/print'] = [
      {'name': 'Ali-Home-SXT'},
    ];
    rows['/interface/print'] = [
      {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
      {'name': 'wlan1', 'type': 'wlan', 'running': connected ? 'true' : 'false', 'disabled': 'false'},
      {'name': 'pppoe-out1', 'type': 'pppoe-out', 'running': 'true', 'disabled': 'false'},
      {'name': 'bridge1', 'type': 'bridge', 'running': 'true', 'disabled': 'false'},
    ];
    rows['/interface/wireless/print'] = [
      {
        'name': 'wlan1',
        'mode': 'station-bridge',
        'ssid': 'Tower-North',
        'frequency': '5180',
        'band': '5ghz-a/n',
        'running': connected ? 'true' : 'false',
        'disabled': 'false',
      },
    ];
    rows['/interface/wireless/registration-table/print'] = [
      if (connected)
        {
          'interface': 'wlan1',
          'mac-address': '4C:5E:0C:11:22:33',
          'ap': 'true',
          'signal-strength': '$signal@HT20-7',
          'tx-signal-strength': '-61',
          'signal-to-noise': '$snr',
          'tx-ccq': '91',
          'rx-ccq': '88',
          'tx-rate': '130Mbps-20MHz/2S/SGI',
          'rx-rate': '117Mbps-20MHz/2S',
          'uptime': '1d2h3m4s',
          'distance': '1.2km',
          'radio-name': 'SECTOR-N1',
        },
    ];
    monitors['/interface/ethernet/monitor|ether1'] = {'name': 'ether1', 'status': 'link-ok', 'rate': '100Mbps', 'full-duplex': 'true'};
    monitors['/interface/pppoe-client/monitor|pppoe-out1'] = {'status': 'connected', 'uptime': '5h6m7s', 'local-address': '10.9.8.7'};
    monitors['/interface/monitor-traffic|wlan1'] = {'rx-bits-per-second': '23400000', 'tx-bits-per-second': '1850000'};
  }

  /// راوتر hAP ac² (RouterOS 7.12) بوضع AP ومعه ثلاثة متّصلين وخمسة إيجارات و PPPoE.
  void hapRouter() {
    rows['/system/resource/print'] = [
      {'uptime': '9d1h', 'version': '7.12.1 (stable)', 'board-name': 'hAP ac^2', 'cpu-load': '3'},
    ];
    rows['/system/identity/print'] = [
      {'name': 'Home-hAP'},
    ];
    rows['/interface/print'] = [
      {'name': 'ether1', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
      {'name': 'ether2', 'type': 'ether', 'running': 'true', 'disabled': 'false'},
      {'name': 'wlan1', 'type': 'wlan', 'running': 'true', 'disabled': 'false'},
      {'name': 'wlan2', 'type': 'wlan', 'running': 'true', 'disabled': 'false'},
      {'name': 'pppoe-out1', 'type': 'pppoe-out', 'running': 'true', 'disabled': 'false'},
    ];
    rows['/interface/wireless/print'] = [
      {'name': 'wlan1', 'mode': 'ap-bridge', 'ssid': 'Home', 'running': 'true', 'disabled': 'false'},
      {'name': 'wlan2', 'mode': 'ap-bridge', 'ssid': 'Home-5G', 'running': 'true', 'disabled': 'false'},
    ];
    rows['/interface/wireless/registration-table/print'] = [
      {'interface': 'wlan1', 'mac-address': 'AA:BB:CC:00:00:01', 'signal-strength': '-55', 'last-ip': '192.168.88.11'},
      {'interface': 'wlan2', 'mac-address': 'AA:BB:CC:00:00:02', 'signal-strength': '-48', 'last-ip': '192.168.88.12'},
      {'interface': 'wlan2', 'mac-address': 'AA:BB:CC:00:00:03', 'signal-strength': '-70'},
    ];
    rows['/ip/dhcp-server/lease/print'] = [
      for (var i = 1; i <= 5; i++)
        {'address': '192.168.88.1$i', 'mac-address': 'AA:BB:CC:00:00:0$i', 'host-name': 'phone-$i', 'status': i <= 4 ? 'bound' : 'waiting'},
    ];
    monitors['/interface/ethernet/monitor|ether1'] = {'name': 'ether1', 'status': 'link-ok', 'rate': '1Gbps', 'full-duplex': 'true'};
    monitors['/interface/pppoe-client/monitor|pppoe-out1'] = {'status': 'connected', 'uptime': '1d1h', 'local-address': '10.9.8.8'};
    monitors['/interface/monitor-traffic|pppoe-out1'] = {'rx-bits-per-second': '51000000', 'tx-bits-per-second': '4100000'};
  }
}
