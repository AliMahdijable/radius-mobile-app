// Temporary exploratory screen — probes a Huawei ONT or Ubiquiti airOS
// device over LAN from the phone. No backend involvement; the phone must
// be on the same WiFi as the device. Used to validate credentials before
// wiring the device into the subscriber UI.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/ubiquiti_service.dart';
import '../../screens/devices/ont_device_screen.dart';
import '../../screens/devices/ubiquiti_device_screen.dart';

enum _ProbeType { ont, ubiquiti }

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
  bool _probeSuccess = false;
  _ProbeType _type = _ProbeType.ont;

  void _applyDefaultsFor(_ProbeType t) {
    setState(() {
      _type = t;
      if (t == _ProbeType.ont) {
        _user.text = 'telecomadmin';
        _pass.text = 'admintelecom';
      } else {
        _user.text = 'ubnt';
        _pass.text = 'ubnt';
      }
    });
  }

  Dio _buildDio(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      followRedirects: false,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    ));
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
    setState(() { _running = true; _log.clear(); _probeSuccess = false; });
    if (_type == _ProbeType.ont) {
      await _probeOnt();
    } else {
      await _probeUbiquiti();
    }
    if (!mounted) return;
    setState(() => _running = false);
    _line('');
    _line('=== DONE ===');
  }

  Future<void> _probeOnt() async {
    final host = _host.text.trim();
    final u = _user.text.trim();
    final p = _pass.text;
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
      try {
        final r = await dio.get('/');
        _line('root → ${r.statusCode} len=${(r.data ?? '').toString().length}');
      } catch (e) {
        _line('root error: $e');
        continue;
      }

      String sessionCookie = '';
      void eatLoginCookie(Response r) {
        final raw = r.headers.map['set-cookie'] ?? const [];
        for (final line in raw) {
          final nameVal = line.split(';').first;
          final eq = nameVal.indexOf('=');
          if (eq > 0) {
            final name = nameVal.substring(0, eq).trim();
            final val = nameVal.substring(eq + 1).trim();
            if (name == 'Cookie' && val.contains('sid=')) {
              sessionCookie = '$name=$val';
            }
          }
        }
      }

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
        loggedIn = bodyStr.contains("pageName = 'index.asp'") && sessionCookie.isNotEmpty;
      } catch (e) {
        _line('login.cgi error: $e');
      }

      if (!loggedIn) {
        _line('✗ Login failed on $base');
        continue;
      }
      _line('✓ Logged in  cookie=$sessionCookie');
      _probeSuccess = true;
      break;
    }
  }

  Future<void> _probeUbiquiti() async {
    final host = _host.text.trim();
    final u = _user.text.trim();
    final p = _pass.text;
    final bases = ['https://$host', 'http://$host'];

    for (final base in bases) {
      _line('');
      _line('=== $base ===');
      final dio = _buildDio(base);

      // 1) Root — see whether the device is even reachable.
      String rootBody = '';
      try {
        final r = await dio.get('/');
        rootBody = (r.data ?? '').toString();
        _line('root → ${r.statusCode} len=${rootBody.length}');
        r.headers.forEach((n, v) => _line('  hdr $n: ${v.join(" | ")}'));
        final preview = rootBody.length > 300 ? rootBody.substring(0, 300) : rootBody;
        _line('  preview: ${preview.replaceAll(RegExp(r"\s+"), " ")}');
      } catch (e) {
        _line('root error: $e');
        continue;
      }

      // 2) v6.x — POST /login.cgi with form body
      _line('');
      _line('→ v6.x attempt: POST /login.cgi');
      try {
        final body =
            'uri=&username=${Uri.encodeQueryComponent(u)}&password=${Uri.encodeQueryComponent(p)}';
        final res = await dio.post(
          '/login.cgi',
          data: body,
          options: Options(headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': '$base/login.cgi',
          }),
        );
        final bstr = (res.data ?? '').toString();
        _line('  login.cgi → ${res.statusCode} len=${bstr.length}');
        res.headers.forEach((n, v) => _line('    hdr $n: ${v.join(" | ")}'));
        final pv = bstr.replaceAll(RegExp(r'\s+'), ' ').trim();
        _line('    body: ${pv.length > 250 ? pv.substring(0, 250) : pv}');
      } catch (e) {
        _line('  login.cgi error: $e');
      }

      // 3) v8.x — JSON POST /api/auth
      _line('');
      _line('→ v8.x attempt: POST /api/auth');
      try {
        final res = await dio.post(
          '/api/auth',
          data: jsonEncode({'username': u, 'password': p}),
          options: Options(
            headers: {'Content-Type': 'application/json', 'Referer': '$base/'},
            responseType: ResponseType.json,
          ),
        );
        final bstr = (res.data ?? '').toString();
        _line('  /api/auth → ${res.statusCode} len=${bstr.length}');
        res.headers.forEach((n, v) => _line('    hdr $n: ${v.join(" | ")}'));
        final pv = bstr.replaceAll(RegExp(r'\s+'), ' ').trim();
        _line('    body: ${pv.length > 250 ? pv.substring(0, 250) : pv}');
      } catch (e) {
        _line('  /api/auth error: $e');
      }
    }

    // 4) Finally, try the real driver (uses the same steps but returns
    //    a parsed status object on success).
    _line('');
    _line('=== UbiquitiService.login + fetchStatus ===');
    final session = await UbiquitiService.login(host, u, p);
    if (session == null) {
      _line('✗ UbiquitiService.login returned null');
      return;
    }
    _line('✓ session  variant=${session.airosVariant}  base=${session.baseUrl}');
    final status = await UbiquitiService.fetchStatus(session);
    if (status == null) {
      _line('✗ fetchStatus returned null (JSON missing wireless/host?)');
      return;
    }
    _line('→ signal=${status.signalDbm} CCQ=${status.ccqPercent} LAN=${status.lanSpeed}');
    _probeSuccess = true;
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
            SegmentedButton<_ProbeType>(
              segments: const [
                ButtonSegment(value: _ProbeType.ont, label: Text('ONT (هواوي)')),
                ButtonSegment(value: _ProbeType.ubiquiti, label: Text('Ubiquiti')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _applyDefaultsFor(s.first),
            ),
            const SizedBox(height: 12),
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
            if (_probeSuccess) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (_type == _ProbeType.ont) {
                    context.push(
                      '/ont-device',
                      extra: OntDeviceArgs(
                        host: _host.text.trim(),
                        user: _user.text.trim(),
                        pass: _pass.text,
                      ),
                    );
                  } else {
                    context.push(
                      '/ubiquiti-device',
                      extra: UbiquitiDeviceArgs(
                        host: _host.text.trim(),
                        user: _user.text.trim(),
                        pass: _pass.text,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.sensors),
                label: Text(_type == _ProbeType.ont ? 'عرض بيانات الضوء' : 'عرض بيانات Ubiquiti'),
              ),
            ],
            const SizedBox(height: 12),
            const Text('النتيجة (شاركها لو فشل):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
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
