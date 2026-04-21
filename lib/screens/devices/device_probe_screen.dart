// Temporary exploratory screen — probes a device (Huawei ONT first) over LAN
// from the phone. No backend involvement; the phone must be on the same WiFi
// as the device. Lets us see which login endpoint + status pages the device
// actually uses before we build the proper driver.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';

class DeviceProbeScreen extends StatefulWidget {
  const DeviceProbeScreen({super.key});

  @override
  State<DeviceProbeScreen> createState() => _DeviceProbeScreenState();
}

class _DeviceProbeScreenState extends State<DeviceProbeScreen> {
  final _host = TextEditingController(text: '10.100.11.201');
  final _user = TextEditingController(text: 'telecomadmin');
  final _pass = TextEditingController(text: 'admintelecom');
  final _log = <String>[];
  bool _running = false;

  Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      // HTTPS handshake on small routers can be slow — give it more time.
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      followRedirects: false,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    ));
    // Accept self-signed HTTPS certs commonly shipped by Huawei ONTs.
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  void _line(String s) {
    if (!mounted) return;
    setState(() => _log.add(s));
  }

  Future<void> _probe() async {
    if (_running) return;
    setState(() { _running = true; _log.clear(); });
    final host = _host.text.trim();
    final u = _user.text.trim();
    final p = _pass.text;
    // HG8145C serves management UI on HTTPS port 80 (confirmed by JS in root page).
    // Try HTTPS:80 first, fall back to standard ports.
    final bases = [
      'https://$host:80',
      'https://$host:443',
      'https://$host',
      'http://$host',
    ];

    for (final base in bases) {
      _line('');
      _line('=== $base ===');
      final dio = _buildDio(base);
      // Quick connectivity check — just confirm the host responds.
      try {
        final r = await dio.get('/');
        _line('root → ${r.statusCode} len=${(r.data ?? '').toString().length}');
      } catch (e) {
        _line('root error: $e');
        continue;
      }

      // Cookie jar — populated from Set-Cookie on successful login.
      String sessionCookie = '';
      void eatLoginCookie(Response r) {
        final raw = r.headers.map['set-cookie'] ?? const [];
        for (final line in raw) {
          // e.g. "Cookie=sid=<hash>:Language:english:id=1;path=/"
          final nameVal = line.split(';').first; // "Cookie=sid=..."
          final eq = nameVal.indexOf('=');
          if (eq > 0) {
            final name = nameVal.substring(0, eq).trim();
            final val  = nameVal.substring(eq + 1).trim();
            if (name == 'Cookie' && val.contains('sid=')) {
              sessionCookie = '$name=$val';
            }
          }
        }
      }

      // HG8145C login flow (confirmed via browser + PowerShell trace):
      //   1) POST /asp/GetRandCount.asp  (NOT GET) — returns 32-hex token
      //      on the SAME TCP/TLS connection as step 2 (server ties token
      //      to the connection).
      //   2) POST /login.cgi with:
      //        Cookie: Cookie=body:Language:english:id=-1   (pre-login marker)
      //        UserName      = <plain>
      //        PassWord      = base64(<plain password>)
      //        x.X_HW_Token  = <token from step 1>
      //   3) Success → Set-Cookie: Cookie=sid=<hash>:Language:english:id=1
      //                response body contains: var pageName = 'index.asp';
      //      Failure → no Set-Cookie, body contains: var pageName = '/';
      String? hwToken;
      try {
        final tok = await dio.post('/asp/GetRandCount.asp',
            data: '',
            options: Options(headers: {'Referer': '$base/'}));
        final raw = (tok.data ?? '').toString().trim();
        _line('GetRandCount → ${tok.statusCode} «${raw.length > 80 ? raw.substring(0, 80) : raw}»');
        final m = RegExp(r'[0-9a-fA-F]{16,}').firstMatch(raw);
        hwToken = m?.group(0);
      } catch (e) {
        _line('GetRandCount error: $e');
      }

      if (hwToken == null) {
        _line('✗ No token, skipping $base');
        continue;
      }

      bool loggedIn = false;
      try {
        final b64Pass = base64Encode(utf8.encode(p));
        final loginBody =
            'UserName=${Uri.encodeQueryComponent(u)}'
            '&PassWord=${Uri.encodeQueryComponent(b64Pass)}'
            '&x.X_HW_Token=${Uri.encodeQueryComponent(hwToken)}';
        final res = await dio.post(
          '/login.cgi',
          data: loginBody,
          options: Options(headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Origin': base,
            'Referer': '$base/',
            'Cookie': 'Cookie=body:Language:english:id=-1',
          }),
        );
        eatLoginCookie(res);
        final bodyStr = (res.data ?? '').toString();
        _line('login.cgi → ${res.statusCode} len=${bodyStr.length}  sid=${sessionCookie.isNotEmpty ? "✓" : "✗"}');
        res.headers.forEach((name, values) {
          _line('  hdr $name: ${values.join(" | ")}');
        });
        _line('  FULL BODY: $bodyStr');
        // Success: server redirects to index.asp; failure: redirects to /
        loggedIn = bodyStr.contains("pageName = 'index.asp'") && sessionCookie.isNotEmpty;
      } catch (e) {
        _line('login.cgi error: $e');
      }

      if (!loggedIn) {
        _line('✗ Login failed on $base');
        continue;
      }
      _line('✓ Logged in  cookie=$sessionCookie');

      // Confirmed page paths from frame.asp menu structure.
      final pages = [
        '/index.asp',
        '/html/ssmp/deviceinfo/deviceinfo.asp',
        '/html/amp/opticinfo/opticinfo.asp',
        '/html/bbsp/waninfo/waninfo.asp',
        '/html/amp/wlaninfo/wlaninfo.asp',
        '/html/bbsp/dhcpinfo/dhcpinfo.asp',
        '/html/bbsp/userdevinfo/userdevinfo.asp',
        '/html/ssmp/bss/bssinfo.asp',
        '/html/bbsp/common/GetLanUserDevInfo.asp',
      ];
      for (final path in pages) {
        try {
          final res = await dio.get(
            path,
            options: Options(
              headers: {'Cookie': sessionCookie, 'Referer': '$base/index.asp'},
            ),
          );
          final body = (res.data ?? '').toString();
          final preview = body.replaceAll(RegExp(r'\s+'), ' ').trim();
          final snippet = preview.length > 120 ? preview.substring(0, 120) : preview;
          _line('[page] $path → ${res.statusCode} len=${body.length}  «$snippet»');
        } catch (e) {
          _line('[page] $path → ERROR');
        }
      }
      break; // done on first working base
    }

    if (!mounted) return;
    setState(() => _running = false);
    _line('');
    _line('=== DONE ===');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فحص جهاز — تجريبي')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _host, decoration: const InputDecoration(labelText: 'IP الجهاز (بدون http://)')),
            const SizedBox(height: 8),
            TextField(controller: _user, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
            const SizedBox(height: 8),
            TextField(controller: _pass, decoration: const InputDecoration(labelText: 'كلمة السر')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : _probe,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_running ? 'جاري الفحص...' : 'فحص'),
            ),
            const SizedBox(height: 12),
            const Text('النتيجة (شاركها لو فشل):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
