import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// ICMP ping على ويندوز من النظام نفسه (iphlpapi: IcmpSendEcho) بدل تشغيل `ping.exe`.
///
/// لماذا لا dart_ping على ويندوز:
///  - يقرأ ردود ping الإنكليزيّة فقط؛ ويندوز بالعربيّة يطبعها مترجمةً ⇒ الجهاز «مفصول» دائماً.
///  - تشغيل `ping.exe` من برنامجٍ بواجهة يفتح نافذة سوداء تومض مع كلّ فحص (كلّ ٢٠ث في قسم الأجهزة).
/// النداء يحجب الخيط حتى المهلة، فيجري في Isolate منفصل.
class WindowsIcmp {
  WindowsIcmp._();

  /// [count] محاولات بمهلة [timeout] لكلٍّ منها. يُرجع أزمنة الردود الناجحة (ms) — فارغة =
  /// لا ردّ. عنوانٌ غير IPv4 (أو اسمٌ لا يُحلّ) ⇒ فارغة.
  static Future<List<int>> ping(String host,
      {int count = 3, Duration timeout = const Duration(seconds: 2)}) async {
    final ip = await _ipv4(host);
    if (ip == null) return const [];
    final addr = ip.rawAddress;
    // IPAddr بترتيب الشبكة كما يخرج من inet_addr: البايت الأوّل في أدنى الذاكرة.
    final dest = addr[0] | (addr[1] << 8) | (addr[2] << 16) | (addr[3] << 24);
    final ms = timeout.inMilliseconds.clamp(200, 10000);
    return Isolate.run(() => _echo(dest, count, ms));
  }

  static Future<InternetAddress?> _ipv4(String host) async {
    final parsed = InternetAddress.tryParse(host.trim());
    if (parsed != null) {
      return parsed.type == InternetAddressType.IPv4 ? parsed : null;
    }
    try {
      final found = await InternetAddress.lookup(host.trim(), type: InternetAddressType.IPv4)
          .timeout(const Duration(seconds: 3));
      return found.isEmpty ? null : found.first;
    } catch (_) {
      return null;
    }
  }

  static List<int> _echo(int dest, int count, int timeoutMs) {
    final lib = DynamicLibrary.open('iphlpapi.dll');
    final create = lib.lookupFunction<IntPtr Function(), int Function()>('IcmpCreateFile');
    final close =
        lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('IcmpCloseHandle');
    final send = lib.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<Void>, Uint16, Pointer<Void>, Pointer<Void>,
            Uint32, Uint32),
        int Function(int, int, Pointer<Void>, int, Pointer<Void>, Pointer<Void>, int,
            int)>('IcmpSendEcho');

    final handle = create();
    // INVALID_HANDLE_VALUE = -1
    if (handle == -1 || handle == 0) return const [];
    const payloadSize = 32;
    // ICMP_ECHO_REPLY (40 بايت على x64) + الحمولة + 8 كما توصي الوثائق — بهامشٍ واسع.
    const replySize = 512;
    final payload = calloc<Uint8>(payloadSize);
    final reply = calloc<Uint8>(replySize);
    final times = <int>[];
    try {
      for (var i = 0; i < payloadSize; i++) {
        payload[i] = 0x61 + (i % 23);
      }
      for (var i = 0; i < count; i++) {
        final n = send(handle, dest, payload.cast(), payloadSize, nullptr, reply.cast(),
            replySize, timeoutMs);
        if (n == 0) continue;
        final view = reply.cast<Uint32>();
        // الحقل الثاني Status (0 = IP_SUCCESS)، والثالث RoundTripTime بالملّي ثانية.
        if (view[1] == 0) times.add(view[2]);
      }
    } finally {
      calloc.free(payload);
      calloc.free(reply);
      close(handle);
    }
    return times;
  }
}
