import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../services/vpn_now.dart';
import 'vpn_pipe.dart';

/// اتّصالات قرّاء الأجهزة (٧ نوفمبر — المالك: «بمجرد نقر الوكيل ع وضع vpn كل الفحصوات تمر من vpn»).
///
/// مباشرةٌ من الموبايل كما كانت؛ و«وضع VPN» مفعّل ⇒ العناوين الخاصّة (شبكة الوكيل) تمرّ عبر ممرّ الخادم وغرفة نفقه ([VpnPipe]) —
/// TCP (RouterOS API، Telnet، منافذ الفحص)، وSSH، والويب (HTTP/HTTPS)، وSNMP — فكلّ لوحةٍ وقراءةٍ تعمل كما على شبكته.
/// حارس «رجعت لشبكتك؟» يسأل الشبكة نفسها: [direct].
class DeviceNet {
  DeviceNet._();

  /// «وضع VPN» مفعّل ([VpnNow.mode]) — يُحقن في الاختبار.
  static bool Function() vpnOn = () => VpnNow.mode.value;

  static const _directKey = #deviceNetDirect;
  static const _vpnKey = #deviceNetVpn;

  /// [fn] بلا ممرّ مهما كان الوضع (حارس العودة للشبكة: ردّ الجهاز عبر الممرّ لا يعني أنّك على شبكتك).
  static Future<T> direct<T>(Future<T> Function() fn) => runZoned(fn, zoneValues: {_directKey: true});

  /// [fn] عبر الممرّ وإن لم يُشغَّل «وضع VPN» — «الفحص الشامل» عبر الـVPN وهو خارج شبكته (الحال من الخادم، والمعلومات بقرّائه هو).
  static Future<T> vpn<T>(Future<T> Function() fn) => runZoned(fn, zoneValues: {_vpnKey: true});

  static bool get _on => Zone.current[_directKey] != true && (Zone.current[_vpnKey] == true || vpnOn());

  /// عنوانٌ خاصّ IPv4 (10/8، 172.16/12، 192.168/16، 100.64/10) — ما يصله نفق الوكيل.
  static bool isPrivateV4(String host) {
    final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host.trim());
    if (m == null) return false;
    final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    if (o.any((x) => x > 255)) return false;
    return o[0] == 10 ||
        (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
        (o[0] == 192 && o[1] == 168) ||
        (o[0] == 100 && o[1] >= 64 && o[1] <= 127);
  }

  /// هذا الاتّصال يمرّ عبر الممرّ؟
  static bool viaPipe(Object host) {
    if (!_on) return false;
    return isPrivateV4(host is InternetAddress ? host.address : '$host');
  }

  /// [Socket.connect] — أو عبر الممرّ بالوضع.
  static Future<Socket> connect(Object host, int port, {Duration? timeout}) {
    if (!viaPipe(host)) return Socket.connect(host, port, timeout: timeout);
    return VpnPipe.connect(host is InternetAddress ? host.address : '$host', port, timeout: timeout);
  }

  /// [SSHSocket.connect] — أو عبر الممرّ بالوضع.
  static Future<SSHSocket> ssh(String host, int port, {Duration? timeout}) async {
    if (!viaPipe(host)) return SSHSocket.connect(host, port, timeout: timeout);
    return _PipeSsh(await VpnPipe.connect(host, port, timeout: timeout));
  }

  /// عميل HTTP لجهاز: بالوضع يمرّ اتّصاله عبر الممرّ، وHTTPS بـTLS فوقه تُقبل فيه شهادة الجهاز كما في المباشر (شهادات الأجهزة
  /// ذاتيّة التوقيع). خارج الوضع لا يُلمس.
  static HttpClient adopt(HttpClient c) {
    if (!_on) return c;
    c.connectionFactory = (uri, proxyHost, proxyPort) async {
      final https = uri.scheme == 'https';
      if (!viaPipe(uri.host)) {
        return https
            ? SecureSocket.startConnect(uri.host, uri.port, onBadCertificate: (_) => true)
            : Socket.startConnect(uri.host, uri.port);
      }
      final plain = VpnPipe.connect(uri.host, uri.port, timeout: c.connectionTimeout ?? const Duration(seconds: 8));
      final Future<Socket> sock = https ? plain.then((s) => SecureSocket.secure(s, host: uri.host, onBadCertificate: (_) => true)) : plain;
      return ConnectionTask.fromSocket(sock, () {
        sock.then((s) => s.destroy(), onError: (Object _) {});
      });
    };
    return c;
  }

  /// رسالة UDP بردّها عبر الممرّ (SNMP بالوضع — [viaPipe] يقرّر).
  static Future<Uint8List> udp(String host, int port, Uint8List data, Duration timeout) => VpnPipe.udp(host, port, data, timeout);

  /// بنك ICMP عبر الممرّ (ينفّذه الخادم من داخل النفق) ⇒ أزمنة الردود الصحيحة — [viaPipe] يقرّر.
  static Future<List<int>> ping(String host, {int count = 1, Duration timeout = const Duration(seconds: 2)}) =>
      VpnPipe.ping(host, count: count, timeout: timeout);

  /// زمن الاتّصال بالجهاز من داخل النفق لمقبسٍ فُتح عبر الممرّ (null للمباشر) — يُعرض كأنّه على شبكته.
  static int? connectMs(Socket s) => VpnPipe.connectMsOf(s);

  /// آخر زمن ردٍّ UDP من داخل النفق لهذا العنوان.
  static int? udpMs(String host) => VpnPipe.udpMsOf(host);
}

/// SSH فوق مقبس الممرّ — كمقبس dartssh2 الأصليّ تماماً.
class _PipeSsh implements SSHSocket {
  _PipeSsh(this._s);
  final Socket _s;

  @override
  Stream<Uint8List> get stream => _s;

  @override
  StreamSink<List<int>> get sink => _s;

  @override
  Future<void> get done => _s.done;

  @override
  Future<void> close() => _s.close();

  @override
  void destroy() => _s.destroy();

  @override
  Future<void> flush() => _s.flush();

  @override
  String toString() => '_PipeSsh(${_s.remotePort})';
}
