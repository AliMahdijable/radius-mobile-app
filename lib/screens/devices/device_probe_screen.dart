// Temporary exploratory screen — probes a device (Huawei ONT first) over LAN
// from the phone. No backend involvement; the phone must be on the same WiFi
// as the device. Lets us see which login endpoint + status pages the device
// actually uses before we build the proper driver.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();

  Future<void> _probe() async {
    if (_running) return;
    setState(() { _running = true; _log.clear(); });
    final host = _host.text.trim();
    final u = _user.text.trim();
    final p = _pass.text;
    // Huawei ONTs commonly serve HTTPS on an unusual port (often 80 or
    // 443). The HTTP landing page's JS discloses the real SSL port —
    // for 10.100.11.201 it's 80. Try the obvious combinations.
    final bases = [
      'http://$host',
      'https://$host:80',
      'https://$host:443',
      'https://$host',
    ];

    for (final base in bases) {
      _line('');
      _line('=== $base ===');
      final dio = _buildDio(base);
      // 1) root — dump enough HTML to see the actual login form/script
      String rootBody = '';
      try {
        final r = await dio.get('/');
        rootBody = (r.data ?? '').toString();
        _line('root → ${r.statusCode} len=${rootBody.length}');
        // Print the first 500 chars so we can see the form/script
        final preview = rootBody.length > 500 ? rootBody.substring(0, 500) : rootBody;
        _line('--- root preview ---');
        _line(preview);
        _line('--- /preview ---');
        // Extract any <form action= and meta-refresh targets for clues.
        final forms = RegExp(r'''<form[^>]*action\s*=\s*["']([^"']+)["']''', caseSensitive: false).allMatches(rootBody);
        for (final m in forms) {
          _line('form action → ${m.group(1)}');
        }
        final metaRefresh = RegExp(r'''content\s*=\s*["']\s*\d+\s*;\s*url\s*=\s*([^"']+)''', caseSensitive: false).firstMatch(rootBody);
        if (metaRefresh != null) _line('meta refresh → ${metaRefresh.group(1)}');
        final scriptSrcs = RegExp(r'''<script[^>]*src\s*=\s*["']([^"']+)["']''', caseSensitive: false).allMatches(rootBody);
        for (final m in scriptSrcs) {
          _line('script src → ${m.group(1)}');
        }
      } catch (e) {
        _line('root error: $e');
        continue;
      }

      final cookies = <String, String>{};
      void eatCookies(Response r) {
        final raw = r.headers.map['set-cookie'] ?? const [];
        for (final line in raw) {
          final kv = line.split(';').first.split('=');
          if (kv.length >= 2) cookies[kv[0].trim()] = kv.sublist(1).join('=');
        }
      }
      String cookieHeader() =>
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

      final attempts = [
        {
          'label': 'POST /login.cgi (Username/Password)',
          'path': '/login.cgi',
          'body': {'Username': u, 'Password': p},
        },
        {
          'label': 'POST /login.cgi (UserName/PassWord)',
          'path': '/login.cgi',
          'body': {'UserName': u, 'PassWord': p},
        },
        {
          'label': 'POST /asp/login.asp (username/psd)',
          'path': '/asp/login.asp',
          'body': {'username': u, 'psd': p},
        },
        {
          'label': 'POST /login.cgi (SHA-256 password, English)',
          'path': '/login.cgi',
          'body': {'UserName': u, 'PassWord': _sha256(p), 'Language': 'english'},
        },
      ];

      bool loggedIn = false;
      for (final a in attempts) {
        final body = (a['body'] as Map<String, dynamic>)
            .entries
            .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
            .join('&');
        try {
          final res = await dio.post(
            a['path'] as String,
            data: body,
            options: Options(
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                if (cookies.isNotEmpty) 'Cookie': cookieHeader(),
                'Referer': '$base/',
              },
            ),
          );
          eatCookies(res);
          final bodyStr = (res.data ?? '').toString();
          final loc = res.headers.value('location') ?? '';
          final bad = RegExp(r'errorPage|Username or password|login failed|invalid', caseSensitive: false)
              .hasMatch(bodyStr);
          _line('[try] ${a['label']} → ${res.statusCode} loc=${loc.isEmpty ? '-' : loc.substring(0, loc.length.clamp(0, 40))} len=${bodyStr.length}${bad ? ' BAD' : ''}');
          if ((res.statusCode == 200 || res.statusCode == 302) && !bad && cookies.isNotEmpty) {
            loggedIn = true;
            break;
          }
        } catch (e) {
          _line('[try] ${a['label']} → ERROR ${e.toString().substring(0, e.toString().length.clamp(0, 120))}');
        }
      }

      if (!loggedIn) {
        _line('✗ Login attempts failed on $base');
        continue;
      }
      _line('✓ logged in, cookies=${cookies.keys.join(",")}');

      final pages = [
        '/html/status/wanstatus.asp',
        '/html/status/opticinfo.asp',
        '/html/network/opticinfo.asp',
        '/html/status/lanstatus.asp',
        '/html/bbsp/common/lanuserdevinfo.asp',
        '/html/bbsp/common/GetLanUserDevInfo.asp',
        '/html/amp/diag/gpondiag.asp',
      ];
      for (final path in pages) {
        try {
          final res = await dio.get(
            path,
            options: Options(
              headers: {'Cookie': cookieHeader(), 'Referer': '$base/'},
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
