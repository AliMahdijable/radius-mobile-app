import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// حساب مدير محفوظ للـquick-login (chip بشاشة الدخول).
class SavedProfile {
  final String username;
  final String encryptedPassword;
  final String displayName;
  final DateTime lastUsedAt;

  SavedProfile({
    required this.username,
    required this.encryptedPassword,
    required this.displayName,
    required this.lastUsedAt,
  });

  Map<String, dynamic> toJson() => {
        'u': username,
        'p': encryptedPassword,
        'n': displayName,
        't': lastUsedAt.toIso8601String(),
      };

  static SavedProfile? fromJson(dynamic v) {
    if (v is! Map) return null;
    final u = v['u']?.toString();
    final p = v['p']?.toString();
    if (u == null || u.isEmpty || p == null) return null;
    return SavedProfile(
      username: u,
      encryptedPassword: p,
      displayName: (v['n'] ?? u).toString(),
      lastUsedAt: DateTime.tryParse(v['t']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// تخزين حسابات المدراء المحفوظة (yُوزر/باسورد) على مسار مستقلّ
/// `profiles.*` — منفصل تماماً عن `auth.*` فلا يُمسَح مع تسجيل الخروج.
///
/// - flutter_secure_storage يوفّر OS-level encryption (Keychain/EncryptedSharedPrefs).
/// - نُضيف طبقة XOR بسيطة على الباسورد (defense-in-depth) بمفتاح app-scoped
///   يُولَّد مرّة ويُخزَّن تحت `profiles.enc_key`.
/// - JSON list واحد تحت `profiles.list` — أبسط + atomic (كل الحسابات
///   تُقرأ/تُكتَب سوى).
class SavedProfilesStore {
  SavedProfilesStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kList = 'profiles.list';
  static const _kEncKey = 'profiles.enc_key';
  static const int _maxProfiles = 8;

  static String? _cachedKey;

  static Future<String> _key() async {
    if (_cachedKey != null) return _cachedKey!;
    var k = await _storage.read(key: _kEncKey);
    if (k == null || k.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      k = base64Url.encode(bytes);
      await _storage.write(key: _kEncKey, value: k);
    }
    _cachedKey = k;
    return k;
  }

  static String _xor(String plain, List<int> key) {
    final bytes = utf8.encode(plain);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return base64.encode(out);
  }

  static String _unxor(String cipherB64, List<int> key) {
    final bytes = base64.decode(cipherB64);
    final out = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ key[i % key.length],
    );
    return utf8.decode(out);
  }

  /// شفّر باسورد ليُخزَّن بأمان. مفتاح app-scoped.
  static Future<String> encrypt(String plain) async {
    final k = await _key();
    return _xor(plain, base64Url.decode(k));
  }

  /// فكّ تشفير باسورد محفوظ. يرمي لو المفتاح مفقود.
  static Future<String> decrypt(String cipher) async {
    final k = await _key();
    return _unxor(cipher, base64Url.decode(k));
  }

  /// قائمة الحسابات المحفوظة، الأحدث أوّلاً.
  static Future<List<SavedProfile>> list() async {
    try {
      final raw = await _storage.read(key: _kList);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      final out = <SavedProfile>[];
      for (final v in decoded) {
        final p = SavedProfile.fromJson(v);
        if (p != null) out.add(p);
      }
      out.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// أضف أو حدّث حساب. يُستدعى فقط عند LoginSuccess.
  static Future<void> upsert({
    required String username,
    required String plainPassword,
    String displayName = '',
  }) async {
    final now = DateTime.now();
    final encrypted = await encrypt(plainPassword);
    final current = await list();
    final withoutMe = current.where((p) => p.username != username).toList();
    final updated = [
      SavedProfile(
        username: username,
        encryptedPassword: encrypted,
        displayName: displayName.isEmpty ? username : displayName,
        lastUsedAt: now,
      ),
      ...withoutMe,
    ];
    // حدّ أعلى — الأقدم يُقصَّ.
    while (updated.length > _maxProfiles) {
      updated.removeLast();
    }
    await _storage.write(
      key: _kList,
      value: json.encode(updated.map((p) => p.toJson()).toList()),
    );
  }

  /// احذف حساب واحد (long-press على الـchip).
  static Future<void> remove(String username) async {
    final current = await list();
    final filtered =
        current.where((p) => p.username != username).toList();
    if (filtered.length == current.length) return;
    await _storage.write(
      key: _kList,
      value: json.encode(filtered.map((p) => p.toJson()).toList()),
    );
  }

  /// امسح كل الحسابات المحفوظة (من إعدادات — "مسح الحسابات المحفوظة").
  static Future<void> clearAll() async {
    await _storage.delete(key: _kList);
  }
}
