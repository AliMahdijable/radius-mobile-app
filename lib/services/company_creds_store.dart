import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Pro البند ٤ ③: كلمات سرّ الساس محفوظةٌ **على الجهاز** لكلّ شركة (قرار
/// المستخدم) — فيدخل الشركة من «شركاتي» بضغطة. الخادم يعرف الربط فقط
/// (شركة + يوزر)، لا كلمة السرّ.
///
/// المفتاح ساسٌ+يوزر: نفس اليوزر قد يوجد في شركتين (`SavedProfilesStore`
/// مفتاحه اليوزر وحده فيدهس أحدهما الآخر). خارج `auth.*` كي ينجو من خروج
/// الساس؛ ويُمسح كلّه عند خروج **الحساب** (`AccountService.signOut`).
class CompanyCredsStore {
  CompanyCredsStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      accountName: 'mysvcs_radius_companies',
    ),
  );
  static const _kList = 'companies.creds';

  static String _key(String sasUrl, String username) =>
      '${_host(sasUrl)}|${username.trim().toLowerCase()}';

  /// مضيف الرابط بلا www. — «sas.jt.iq» و«https://sas.jt.iq/admin» شركةٌ واحدة.
  static String _host(String sasUrl) {
    final s = sasUrl.trim();
    if (s.isEmpty) return '';
    final uri = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    final h = (uri?.host ?? s).toLowerCase();
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  static Future<Map<String, dynamic>> _readAll() async {
    try {
      final raw = await _storage.read(key: _kList);
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw);
      return m is Map<String, dynamic> ? m : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> upsert({
    required String sasUrl,
    required String username,
    required String password,
  }) async {
    final all = await _readAll();
    all[_key(sasUrl, username)] = {
      'url': sasUrl.trim(),
      'u': username.trim(),
      'p': password,
    };
    await _storage.write(key: _kList, value: jsonEncode(all));
  }

  /// كلمة السرّ المحفوظة لهذه الشركة/اليوزر، أو null.
  static Future<String?> passwordFor(String sasUrl, String username) async {
    final e = (await _readAll())[_key(sasUrl, username)];
    if (e is Map && e['p'] is String && (e['p'] as String).isNotEmpty) {
      return e['p'] as String;
    }
    return null;
  }

  static Future<void> remove(String sasUrl, String username) async {
    final all = await _readAll();
    if (all.remove(_key(sasUrl, username)) != null) {
      await _storage.write(key: _kList, value: jsonEncode(all));
    }
  }

  static Future<void> clearAll() => _storage.delete(key: _kList);
}
