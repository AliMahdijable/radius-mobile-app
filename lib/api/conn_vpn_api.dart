import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «ربط VPN» (٣ نوفمبر — الخادم server/connVpn/agentRoutes.js): حين لا يكون التطبيق على شبكة الوكيل يقيس الخادم أجهزة مشتركيه
/// عبر نفق VPN. لصاحب الحساب وحده (أسرار شبكته)؛ الموظّف يُرفض بالخادم.
///   • ايرث لنك: نفق الشركة يصل كلّ وكلائها — لا ملفّ.
///   • سوبرنت: النفق الدائم لمن يصله، وإلّا الربط التلقائيّ بالملفّ الثالث (يوزره من اسمه والباسورد الموحّد)، أو ملفّه بيوزره.
///   • غيرها: يرفع الوكيل ملفّه (.ovpn) ويُكمل ما ينقصه (يوزر/باسورد، كلمة سرّ المفتاح).

class ConnVpnTest {
  const ConnVpnTest({required this.connected, required this.message, this.atMs});
  final bool connected;
  final String message;
  final int? atMs;

  static ConnVpnTest? fromJson(Object? j) {
    if (j is! Map) return null;
    return ConnVpnTest(
      connected: j['connected'] == true,
      message: '${j['message'] ?? ''}',
      atMs: (j['at_ms'] as num?)?.toInt(),
    );
  }
}

class ConnVpnStatus {
  const ConnVpnStatus({
    this.companyLabel,
    this.companyHealthy = false,
    this.autoLabel,
    this.autoUser,
    this.profileSaved = false,
    this.profileHasAuth = false,
    this.profileError,
    this.reverse = false,
    this.lastTest,
    this.sweepAtMs,
    this.sweepOnline = 0,
    this.sweepReachable = 0,
    this.sweepReadable = 0,
  });

  /// نفق الشركة الدائم يصل هذا الوكيل (لا ملفّ)
  final String? companyLabel;
  final bool companyHealthy;

  /// الربط التلقائيّ بقالب الشركة (سوبرنت VPN-ALL)
  final String? autoLabel;
  final String? autoUser;
  final bool profileSaved;
  final bool profileHasAuth;
  final String? profileError;
  final bool reverse;
  final ConnVpnTest? lastTest;
  final int? sweepAtMs;
  final int sweepOnline;
  final int sweepReachable;
  final int sweepReadable;

  bool get covered => companyLabel != null;
  bool get autoLinked => !covered && !profileSaved && autoLabel != null;
  bool get canTest => covered || profileSaved || autoLinked;

  factory ConnVpnStatus.fromJson(Map<String, dynamic> j) {
    final c = j['company_tunnel'];
    final a = j['auto_link'];
    final p = j['profile'];
    final s = j['last_sweep'];
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return ConnVpnStatus(
      companyLabel: c is Map ? '${c['label'] ?? ''}' : null,
      companyHealthy: c is Map && c['healthy'] == true,
      autoLabel: a is Map ? '${a['label'] ?? ''}' : null,
      autoUser: a is Map ? a['user']?.toString() : null,
      profileSaved: p is Map && p['saved'] == true,
      profileHasAuth: p is Map && p['has_auth'] == true,
      profileError: p is Map ? p['last_error']?.toString() : null,
      reverse: j['reverse_enabled'] == true,
      lastTest: ConnVpnTest.fromJson(j['last_test']),
      sweepAtMs: s is Map ? (s['at_ms'] as num?)?.toInt() : null,
      sweepOnline: s is Map ? n(s['online']) : 0,
      sweepReachable: s is Map ? n(s['reachable']) : 0,
      sweepReadable: s is Map ? n(s['readable']) : 0,
    );
  }
}

class ConnVpnAnalysis {
  const ConnVpnAnalysis({
    required this.ok,
    required this.errors,
    required this.needsAuth,
    required this.embeddedAuth,
    required this.needsKeyPassword,
    required this.servers,
  });
  final bool ok;
  final List<String> errors;
  final bool needsAuth;
  final bool embeddedAuth;
  final bool needsKeyPassword;
  final int servers;

  factory ConnVpnAnalysis.fromJson(Map<String, dynamic> j) => ConnVpnAnalysis(
        ok: j['ok'] == true,
        errors: [for (final e in (j['errors'] as List? ?? const [])) '$e'],
        needsAuth: j['needs_auth'] == true,
        embeddedAuth: j['embedded_auth'] == true,
        needsKeyPassword: j['needs_key_password'] == true,
        servers: (j['servers'] as num?)?.toInt() ?? 0,
      );
}

class ConnVpnApi {
  ConnVpnApi._();

  static const maxFileBytes = 64 * 1024;

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return '${d['message']}';
    }
    return fallback;
  }

  /// null = لا «ربط VPN» لهذا الحساب (موظّف، أو لم يُفتح له «تنبيه المشترك» بعد، أو خادمٌ أقدم).
  static Future<ConnVpnStatus?> status() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/status');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) return ConnVpnStatus.fromJson(Map<String, dynamic>.from(d));
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 conn-vpn/status: $e');
    }
    return null;
  }

  static Future<({ConnVpnAnalysis? analysis, String? message})> analyze(String ovpn) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/conn-vpn/analyze', data: {'ovpn': ovpn});
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) return (analysis: ConnVpnAnalysis.fromJson(Map<String, dynamic>.from(d)), message: null);
      return (analysis: null, message: r.data?['message']?.toString() ?? 'تعذّر فحص الملفّ');
    } catch (e) {
      return (analysis: null, message: _msg(e, 'تعذّر فحص الملفّ'));
    }
  }

  static Future<({bool ok, String? message})> save({
    required String ovpn,
    String? username,
    String? password,
    String? keyPassword,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/conn-vpn/profile', data: {
        'ovpn': ovpn,
        if (username != null && username.isNotEmpty) 'username': username,
        if (password != null && password.isNotEmpty) 'password': password,
        if (keyPassword != null && keyPassword.isNotEmpty) 'key_password': keyPassword,
      });
      return (ok: r.data?['success'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  static Future<({bool ok, String? message})> remove() async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>('/api/v2/conn-vpn/profile');
      return (ok: r.data?['success'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحذف'));
    }
  }

  /// «فحص الاتصال»: اتّصالٌ فعليّ + عيّنة من مشتركيه المتّصلين (≈ دقيقة) — يُستطلع حتى ينتهي.
  static Future<({ConnVpnTest? result, String? message})> test({
    Duration every = const Duration(milliseconds: 2500),
    int maxPolls = 60,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/conn-vpn/test');
      final id = (r.data?['data'] as Map?)?['test_id']?.toString();
      if (id == null || id.isEmpty) return (result: null, message: r.data?['message']?.toString() ?? 'تعذّر الفحص');
      for (var i = 0; i < maxPolls; i++) {
        await Future<void>.delayed(every);
        final p = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/test/$id');
        final d = p.data?['data'];
        if (d is Map && d['state'] == 'done') return (result: ConnVpnTest.fromJson(d['result']), message: null);
      }
      return (result: null, message: 'الفحص أطول من المعتاد — افتح الصفحة بعد قليل');
    } catch (e) {
      return (result: null, message: _msg(e, 'تعذّر الفحص'));
    }
  }

  static Future<({bool ok, String? message})> reverse(bool on) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/conn-vpn/reverse', data: {'enabled': on});
      return (ok: r.data?['success'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }
}
