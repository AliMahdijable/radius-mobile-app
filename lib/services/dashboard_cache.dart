import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/dashboard_api.dart';
import '../api/sas4_api.dart';

/// Persists dashboard widget values to SharedPreferences so the next
/// cold start can render KPIs INSTANTLY from the last successful fetch,
/// while the live network call runs in the background.
///
/// Cache-first pattern:
///   initState → DashboardCache.read* to seed widgets synchronously
///     (via a Future.microtask on first frame — SharedPreferences is
///      cheap enough this is nearly imperceptible)
///   → live fetch fires + updates when it returns
///
/// Only the numeric KPIs are cached (SAS4 stats + wallet). Debtors +
/// activation list are heavier / more likely to be stale, so they stay
/// fetch-only. TTL is not enforced here — even a stale value is better
/// than a spinner for perceived-performance.
class DashboardCache {
  DashboardCache._();

  static const _kSas4 = 'dash.cache.sas4';
  static const _kWallet = 'dash.cache.wallet';
  static const _kRevenue = 'dash.cache.revenue'; // day-scope only

  /// Read + save operations use SharedPreferences.getInstance() which is
  /// async on first call but cached on subsequent — so all reads after
  /// the first are effectively O(1).

  static Future<void> saveSas4(Sas4Stats s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSas4, jsonEncode(s.toJson()));
  }

  static Future<Sas4Stats?> readSas4() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSas4);
    if (raw == null) return null;
    try {
      return Sas4Stats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveWallet(WalletResult w) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWallet, jsonEncode(w.toJson()));
  }

  static Future<WalletResult?> readWallet() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kWallet);
    if (raw == null) return null;
    try {
      return WalletResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRevenue(RevenueResult r) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRevenue, jsonEncode(r.toJson()));
  }

  static Future<RevenueResult?> readRevenue() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRevenue);
    if (raw == null) return null;
    try {
      return RevenueResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Wipes all cached KPIs — call on logout so the next login doesn't
  /// briefly flash the previous admin's numbers.
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_kSas4),
      p.remove(_kWallet),
      p.remove(_kRevenue),
    ]);
  }
}
