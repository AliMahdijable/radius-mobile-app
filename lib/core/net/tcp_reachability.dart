import 'dart:async';
import 'dart:io';

import 'device_net.dart';

/// Quick TCP-connect probe — short-circuits the device-health fan-out
/// before we waste 4s × N HTTP login attempts on an unreachable IP.
/// Tries ports 80/443/8080 in parallel and returns true on the first
/// successful connect. `host:port` (a custom IP behind a forwarded port)
/// tries that port alone. Direct from the phone — and through the VPN pipe only inside
/// [DeviceNet.cpeZone] (the one open subscriber card in «وضع VPN»).
class TcpReachability {
  static const _ports = [80, 443, 8080];
  static const _defaultTimeout = Duration(milliseconds: 1200);

  /// `10.0.0.5:8080` ⇒ (10.0.0.5, 8080); a bare host or IPv6 ⇒ port null.
  static ({String host, int? port}) split(String address) {
    final a = address.trim();
    final m = RegExp(r'^([^:]+):(\d{1,5})$').firstMatch(a);
    if (m == null) return (host: a, port: null);
    return (host: m.group(1)!, port: int.parse(m.group(2)!));
  }

  static Future<bool> isReachable(String host,
      {Duration timeout = _defaultTimeout}) async {
    if (host.trim().isEmpty) return false;
    final target = split(host);
    final ports = target.port == null ? _ports : [target.port!];
    final completer = Completer<bool>();
    var pending = ports.length;
    for (final port in ports) {
      _tryConnect(target.host, port, timeout).then((ok) {
        if (completer.isCompleted) return;
        if (ok) {
          completer.complete(true);
        } else if (--pending == 0) {
          completer.complete(false);
        }
      });
    }
    return completer.future;
  }

  /// كـ[isReachable] بحكمٍ ثالث — null: الطريق نفسه تعذّر لا الجهاز (ممرّ «وضع VPN» رفض العنوان أو تعذّر الخادم أو امتلأ الممرّ)،
  /// فلا يُقال «لا يستجيب» عن جهازٍ لم يُسأل. خطأ الجهاز عبر الممرّ (مهلة، رفض المنفذ، لا طريق) يحمل رمز النظام كالمباشر ⇒ false.
  /// المباشر كـ[isReachable] حرفاً (true/false).
  static Future<bool?> verdict(String host, {Duration timeout = _defaultTimeout}) async {
    if (host.trim().isEmpty) return false;
    final target = split(host);
    final ports = target.port == null ? _ports : [target.port!];
    final completer = Completer<bool?>();
    var pending = ports.length;
    var unknown = false;
    for (final port in ports) {
      _tryVerdict(target.host, port, timeout).then((v) {
        if (completer.isCompleted) return;
        if (v == true) {
          completer.complete(true);
          return;
        }
        if (v == null) unknown = true;
        if (--pending == 0) completer.complete(unknown ? null : false);
      });
    }
    return completer.future;
  }

  static Future<bool?> _tryVerdict(String host, int port, Duration timeout) async {
    try {
      final socket = await DeviceNet.cpeConnect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } on SocketException catch (e) {
      return DeviceNet.cpePiped && e.osError == null ? null : false;
    } catch (_) {
      return false;
    }
  }

  /// زمن فتح اتّصالٍ واحد بالعنوان (منفذه إن كُتب، وإلّا 80 — منفذ صفحة الجهاز) — null: لم يُفتح خلال [timeout].
  /// يقيس بُعد الشبكة لا صحّة الجهاز: ~5 ملّي ث على شبكة الوكيل، ونصف ثانيةٍ فأكثر عبر VPN من بعيد (قِيس ٢٩ أكتوبر).
  static Future<Duration?> connectTime(String address,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final target = split(address);
    if (target.host.isEmpty) return null;
    final sw = Stopwatch()..start();
    try {
      final socket = await DeviceNet.cpeConnect(target.host, target.port ?? 80, timeout: timeout);
      sw.stop();
      socket.destroy();
      return sw.elapsed;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _tryConnect(
      String host, int port, Duration timeout) async {
    try {
      final socket = await DeviceNet.cpeConnect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
