import 'dart:async';
import 'dart:io';

/// Quick TCP-connect probe — used to short-circuit the device-health
/// fan-out before we waste 4s × N HTTP login attempts on an unreachable
/// IP. Tries port 80 and 443 in parallel because some firmware on the
/// management network exposes only HTTPS, and a few blocks port 80
/// outright while keeping the management UI on 8080.
///
/// Returns true on the first successful connect on either port. Returns
/// false if both fail/time-out within [timeout].
class TcpReachability {
  static const _ports = [80, 443, 8080];
  static const _defaultTimeout = Duration(milliseconds: 1200);

  /// Returns true when a TCP handshake completes on any of [_ports]
  /// within [timeout]. Resolved short-circuits as soon as the first
  /// success arrives, even if the other attempts haven't returned yet.
  static Future<bool> isReachable(
    String host, {
    Duration timeout = _defaultTimeout,
  }) async {
    if (host.trim().isEmpty) return false;
    final completer = Completer<bool>();
    var pending = _ports.length;

    for (final port in _ports) {
      _tryConnect(host, port, timeout).then((ok) {
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

  /// One TCP connect attempt — bails as soon as the connect succeeds,
  /// or returns false on timeout / refused / network error. The socket
  /// is destroyed immediately so we don't hold open file descriptors.
  static Future<bool> _tryConnect(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
