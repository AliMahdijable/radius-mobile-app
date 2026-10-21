import 'package:dio/dio.dart';

import '../models/merged_company.dart';
import '../models/subscriber.dart';
import '../services/merged_mode.dart';
import '../services/merged_rows.dart';
import 'api_client.dart';
import 'company_route.dart';
import 'dashboard_api.dart';

/// رقمٌ مجموعٌ من شركات «كل الشركات» ومن لم يدخله ولماذا (لا صفرٌ صامت لشركةٍ تعذّرت — قاعدة الويب §4).
class MergedSum<T> {
  const MergedSum(this.value, this.excluded, {this.byKey = const {}, this.reasons = const {}});

  /// null: لم تدخل شركةٌ واحدة.
  final T? value;

  /// «الاسم: السبب» لكلّ شركةٍ خارج المجموع.
  final List<String> excluded;

  /// قيمة كلّ شركةٍ دخلت المجموع (بمفتاحها) — الشركة المختارة في الشريط تُعرض بها وحدها.
  final Map<String, T> byKey;

  /// سبب غياب كلّ شركةٍ خارج المجموع (بمفتاحها، بلا اسمها).
  final Map<String, String> reasons;

  /// شركةٌ واحدة من المجموع: قيمتها وحدها، أو سبب غيابها. ربطٌ ثانٍ للمدير نفسه يُقرأ من أصله (قائمتهما واحدة).
  MergedSum<T> only(MergedCompany c) {
    final k = MergedDashboardApi.canonicalKey(c.key);
    final v = byKey[k];
    if (v != null) return MergedSum<T>(v, const []);
    final why = reasons[k];
    return MergedSum<T>(null, [if (why != null) '${c.name}: $why']);
  }
}

/// الرئيسية في «كل الشركات» (٢١ أكتوبر): كلّ رقمٍ = نداءٌ موجَّهٌ لكلّ شركةٍ على المعالج الحقيقيّ نفسه ثمّ الجمع بقواعد الويب
/// (client-v2 pages/Dashboard.tsx sumMoney/sumDaily): الدينار وحده يُجمع، وشركةٌ بعملةٍ أخرى أو مجهولة تُسمّى ولا تُجمع؛ قراءةٌ
/// متعذّرة (علم balance_unavailable/unavailable أو فشل) تُسمّى ولا تدخل؛ وربطان للمدير نفسه (sameManagerOf) يُعدّان مرّة.
class MergedDashboardApi {
  MergedDashboardApi._();

  /// الشركات التي تُجمع: الصالحة بلا مكرّر المدير نفسه.
  static List<MergedCompany> countable() {
    final usable = MergedMode.usable;
    final dup = sameManagerOf(usable);
    return usable.where((c) => !dup.containsKey(c.key)).toList();
  }

  /// ربطٌ ثانٍ للمدير نفسه ⇒ مفتاح أصله (أرقامه تُقرأ مرّةً تحت الأصل)؛ وإلّا المفتاح نفسه.
  static String canonicalKey(String key) => sameManagerOf(MergedMode.usable)[key]?.key ?? key;

  static bool _iqd(MergedCompany c) => c.currency == 'IQD';

  static Future<List<R>> _each<R>(List<MergedCompany> cs, Future<R> Function(MergedCompany c) f) =>
      Future.wait([for (final c in cs) CompanyRoute.run(c.key, () => f(c))]);

  /// الرصيد (بإشارته) والنقاط.
  static Future<MergedSum<WalletResult>> wallet() async {
    final cs = countable();
    final res = await _each(cs, (c) async {
      try {
        final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/admin-widgets');
        return r.data;
      } on DioException {
        return null;
      }
    });
    num balance = 0;
    num points = 0;
    var any = false;
    final excluded = <String>[];
    final byKey = <String, WalletResult>{};
    final reasons = <String, String>{};
    void skip(MergedCompany c, String why) {
      excluded.add('${c.name}: $why');
      reasons[c.key] = why;
    }

    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final b = res[i];
      if (b == null || b['success'] == false || b['balance_unavailable'] == true) {
        skip(c, 'تعذّرت قراءة الرصيد');
        continue;
      }
      final p = b['points'];
      final pts = p is num ? p : (num.tryParse('${p ?? 0}') ?? 0);
      points += pts;
      if (!_iqd(c)) {
        skip(c, c.currency ?? 'عملةٌ غير معروفة');
        continue;
      }
      final v = b['balance'];
      final bal = v is num ? v : (num.tryParse('${v ?? 0}') ?? 0);
      balance += bal;
      byKey[c.key] = WalletResult(balance: bal, points: pts);
      any = true;
    }
    return MergedSum(any ? WalletResult(balance: balance, points: points) : null, excluded,
        byKey: byKey, reasons: reasons);
  }

  /// الإيراد للمدّة: مجموع الشركات بالدينار، والسلسلة اليوميّة مجموعةً بالتاريخ.
  static Future<MergedSum<RevenueResult>> revenue(RevenuePeriod period) async {
    final cs = countable();
    final res = await _each(cs, (c) => DashboardApi.fetchRevenue(period, adminIdOverride: c.adminId));
    var amount = 0;
    var any = false;
    final byDay = <DateTime, int>{};
    final excluded = <String>[];
    final byKey = <String, RevenueResult>{};
    final reasons = <String, String>{};
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final r = res[i];
      final why = r == null ? 'تعذّر جلب الإيراد' : (!_iqd(c) ? (c.currency ?? 'عملةٌ غير معروفة') : null);
      if (why != null) {
        excluded.add('${c.name}: $why');
        reasons[c.key] = why;
        continue;
      }
      amount += r!.amount;
      for (final p in r.series) {
        byDay[p.date] = (byDay[p.date] ?? 0) + p.amount;
      }
      byKey[c.key] = r;
      any = true;
    }
    final series = [for (final e in byDay.entries) RevenuePoint(date: e.key, amount: e.value)]
      ..sort((a, b) => a.date.compareTo(b.date));
    return MergedSum(any ? RevenueResult(amount: amount, series: series) : null, excluded,
        byKey: byKey, reasons: reasons);
  }

  /// تفعيلات اليوم وتمديداته — مجموع العدد، وآخر العمليّات من كلّ الشركات (الأحدث أوّلاً).
  static Future<MergedSum<DailyActivationsResult>> daily() async {
    final cs = countable();
    final res = await _each(cs, (c) => DashboardApi.fetchDailyActivations(adminIdOverride: c.adminId));
    var act = 0;
    var ext = 0;
    var any = false;
    final recent = <Map<String, dynamic>>[];
    final excluded = <String>[];
    final byKey = <String, DailyActivationsResult>{};
    final reasons = <String, String>{};
    for (var i = 0; i < cs.length; i++) {
      final r = res[i];
      if (r == null) {
        excluded.add('${cs[i].name}: تعذّر جلب تفعيلات اليوم');
        reasons[cs[i].key] = 'تعذّر جلب تفعيلات اليوم';
        continue;
      }
      act += r.activations;
      ext += r.extensions;
      recent.addAll(r.recent);
      byKey[cs[i].key] = r;
      any = true;
    }
    String at(Map<String, dynamic> m) => '${m['created_at'] ?? m['time'] ?? ''}';
    recent.sort((a, b) => at(b).compareTo(at(a)));
    return MergedSum(
      any ? DailyActivationsResult(activations: act, extensions: ext, recent: recent.take(20).toList()) : null,
      excluded,
      byKey: byKey,
      reasons: reasons,
    );
  }

  /// عدّادات المشتركين والديون من الصفوف المدموجة — حلقة الرئيسيّة العاديّة نفسها (DashboardApi.fetchDebtors) حرفاً.
  static DebtorsResult debtorsFrom(List<Subscriber> list) {
    var debtCount = 0;
    var debtTotal = 0;
    var nearExpiry = 0;
    var online = 0;
    var offline = 0;
    var active = 0;
    var expired = 0;
    var onlineNoPlan = 0;
    var disabled = 0;
    var total = 0;
    for (final s in list) {
      if (s.isAbandoned) continue;
      total++;
      if (s.hasDebt) {
        debtCount++;
        debtTotal += s.debtAbs.round();
      }
      if (s.isNearExpiry) nearExpiry++;
      if (s.isOnline && !s.isExpired) online++;
      if (s.isOffline) offline++;
      if (s.isExpired) expired++;
      if (s.isActive) active++;
      if (s.isOnline && s.isExpired) onlineNoPlan++;
      if (s.isDisabled) disabled++;
    }
    return DebtorsResult(
      count: debtCount,
      total: debtTotal,
      nearExpiry: nearExpiry,
      online: online,
      offline: offline,
      active: active,
      expired: expired,
      totalSubs: total,
      onlineNoPlan: onlineNoPlan,
      disabled: disabled,
    );
  }
}
