import 'package:dio/dio.dart';

import '../core/util/bidi.dart';
import '../models/merged_company.dart';
import '../models/subscriber.dart';
import '../services/merged_mode.dart';
import '../services/merged_rows.dart';
import '../services/merged_text.dart';
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

/// واتساب كلّ شركة في «كل الشركات» (٨ نوفمبر): الحال بمفتاحها، وnull = تعذّر فحصها (يُسمّى لا يُعدّ منقطعاً).
class MergedWhatsApp {
  const MergedWhatsApp(this.rows, {this.denied = const {}});
  final List<({MergedCompany company, WhatsAppStatusResult? status})> rows;

  /// «كل الصفحات»: صفحاتٌ لا يملك فيها الموظّف أيّ مفتاح واتساب — لم تُفحص، وصفّها يقول «لا صلاحيّة» ولا تُعدّ في N/M.
  final Set<String> denied;

  bool isDenied(String key) => denied.contains(key);

  int get total => rows.where((r) => !denied.contains(r.company.key)).length;
  int get connected => rows.where((r) => r.status?.connected == true).length;
  bool get allConnected => total > 0 && connected == total;

  /// صفّ الشركة (ربطٌ ثانٍ للمدير نفسه يُقرأ من أصله — جلسة واتساب واحدة).
  ({MergedCompany company, WhatsAppStatusResult? status})? of(String key) {
    final k = MergedDashboardApi.canonicalKey(key);
    for (final r in rows) {
      if (r.company.key == k) return r;
    }
    return null;
  }
}

/// دين شركةٍ في «المدينون» بـ«الكل»: مبلغ مدينيها وعددهم — أو سبب غيابها عن المجموع (المبلغ والعدد null).
typedef MergedDebtLine = ({String key, int? amount, int? count, String? reason});

/// «المدينون — لكلّ شركة» (١٠ نوفمبر — المالك: «فصل دين الشركه بوضع الشركات» ثمّ «وهنت بالاعلى الدين الكلي
/// مجموعهن»): سطرٌ لكلّ شركة، والمجموع أعلاه **جمع الأسطر التي لها مبلغ** بالبناء — فلا يخالفها، ولا يدخله صفرٌ صامت
/// لشركةٍ لم تُقرأ ديونها.
class MergedDebts {
  const MergedDebts(this.lines);

  /// بترتيب شركات الحساب (ترتيب الشريط).
  final List<MergedDebtLine> lines;

  int get total => lines.fold(0, (n, l) => n + (l.amount ?? 0));
  int get count => lines.fold(0, (n, l) => n + (l.count ?? 0));

  /// شركةٌ واحدة دخلت المجموع على الأقلّ — وإلّا لا رقم («—» لا «٠»).
  bool get any => lines.any((l) => l.amount != null);

  /// الشركات خارج المجموع (بسبب كلٍّ منها).
  List<MergedDebtLine> get left => [for (final l in lines) if (l.amount == null) l];

  /// سطر المجموع لمن خارجه، قصيرٌ: «بلا «X» — سببها» (وشركتان بأسمائهما؛ وثلاثٌ فأكثر بعددها)، والأسباب المختلفة
  /// «السبب بجانب كلٍّ منها». الاسم معزول الاتّجاه — «سوبرنت (SuperNet) · admin@b» لا يتفكّك في السطر العربيّ.
  String? leftNote([String Function(String key)? nameOf]) {
    final out = left;
    if (out.isEmpty) return null;
    final name = nameOf ?? (k) => MergedMode.companyOf(k)?.name ?? k;
    final who = out.length <= 2
        ? out.map((l) => '«${iso(name(l.key))}»').join('، ')
        : '${out.length} ${out.length <= 10 ? mergedWord('شركات', 'صفحات') : mergedWord('شركة', 'صفحة')}';
    final why = {for (final l in out) l.reason}.length == 1 ? out.first.reason : 'السبب بجانب كلٍّ منها';
    return 'بلا $who — $why';
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

  /// واتساب كلّ شركة: GET /api/whatsapp/connection-status/:adminId موجَّهاً لها بمعرّف مديرها، ٢٠ث لكلٍّ (لا ينتظر الكلّ
  /// شركةً معلّقة).
  static Future<MergedWhatsApp> whatsApp() async {
    final cs = countable();
    // «كل الصفحات»: صفحةٌ بلا أيّ مفتاح واتساب للموظّف ⇒ لا فحص (بوّابة الرئيسيّة نفسها لكلّ صفحة)
    final denied = {for (final c in cs) if (MergedMode.pagePermAny(c.key, waKeys) == false) c.key};
    final res = await _each(
      cs,
      (c) => denied.contains(c.key)
          ? Future<WhatsAppStatusResult?>.value(null)
          : DashboardApi.fetchWhatsAppStatusAt(c.adminId)
              .timeout(const Duration(seconds: 20), onTimeout: () => null)
              .catchError((_) => null),
    );
    return MergedWhatsApp([for (var i = 0; i < cs.length; i++) (company: cs[i], status: res[i])], denied: denied);
  }

  /// مفاتيح `connection-status` بالخادم (requireWhatsAppAdminContext) — بوّابة حبّة واتساب الرئيسيّة نفسها.
  static const waKeys = ['whatsapp.connect', 'whatsapp.send', 'whatsapp.broadcast', 'whatsapp.templates', 'whatsapp.schedules'];

  /// الرصيد (بإشارته) والنقاط.
  static Future<MergedSum<WalletResult>> wallet() async {
    final cs = countable();
    final res = await _each(cs, (c) async {
      // «كل الصفحات»: لا reports.financial له في هذه الصفحة ⇒ لا يُطلب رصيدها (الساس لا يقنّعه للموظّف — البوّابة هنا)
      if (MergedMode.pagePerm(c.key, 'reports.financial') == false) {
        return <String, dynamic>{'success': false, 'code': 'PERMISSION_DENIED', 'local': true};
      }
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

    // «كل الصفحات» للموظّف (٩ نوفمبر): صلاحيّاته في كلّ صفحةٍ غيرها في الأخرى — رفضٌ (403) أو رصيدٌ يقنّعه الخادم (null بلا
    // reports.financial هناك) يُسمّى بالصفحة ولا يُجمع صفراً. المالك كما كان حرفاً.
    final emp = MergedMode.employeeSession;
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final b = res[i];
      if (emp && b != null && (b['code'] == 'PERMISSION_DENIED' || (b['success'] != false && b['balance'] == null))) {
        skip(c, MergedMode.noAccess('رصيدها'));
        continue;
      }
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
    bool denied(MergedCompany c) => MergedMode.pagePerm(c.key, 'reports.financial') == false;
    final res = await _each(
        cs, (c) => denied(c) ? Future<RevenueResult?>.value(null) : DashboardApi.fetchRevenue(period, adminIdOverride: c.adminId));
    var amount = 0;
    var any = false;
    final byDay = <DateTime, int>{};
    final excluded = <String>[];
    final byKey = <String, RevenueResult>{};
    final reasons = <String, String>{};
    for (var i = 0; i < cs.length; i++) {
      final c = cs[i];
      final r = res[i];
      final why = denied(c)
          ? MergedMode.noAccess('إيرادها')
          : r == null
              ? 'تعذّر جلب الإيراد'
              : (!_iqd(c) ? (c.currency ?? 'عملةٌ غير معروفة') : null);
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
    bool denied(MergedCompany c) => MergedMode.pagePerm(c.key, 'reports.daily_activations') == false;
    final res = await _each(cs,
        (c) => denied(c) ? Future<DailyActivationsResult?>.value(null) : DashboardApi.fetchDailyActivations(adminIdOverride: c.adminId));
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
        final why = denied(cs[i]) ? MergedMode.noAccess('تفعيلاتها') : 'تعذّر جلب تفعيلات اليوم';
        excluded.add('${cs[i].name}: $why');
        reasons[cs[i].key] = why;
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

  /// «المدينون» في «الكل» مقسوماً بالشركة (١٠ نوفمبر): الصفوف المدموجة نفسها — مشتركٌ تراه صفحتان مربوطتان يُعدّ
  /// مرّةً تحت الأقرب إليه، وربطٌ ثانٍ للمدير نفسه تحت أصله — بتعريف [debtorsFrom] حرفاً (hasDebt/debtAbs، بلا
  /// «المهمَل»)، بلا طلب. شركةٌ لا تُعرف ديونها تُسمّى بسببها ولا تُجمع (قاعدة الويب debtStateOf/mergedListTotals):
  /// قائمةٌ كبيرة أو تعذّرت أو ناقصة، دفترٌ تعذّر (debts_unavailable)، عملةٌ غير الدينار، شركةٌ خارج الوضع (تحتاج
  /// دخول، من الموقع، المشروع الوطنيّ)، أو أختٌ على ساسها نفسه تعذّرت قائمتها (مشتركها قد يكون عندها — لا يُعرف لمن).
  static MergedDebts debtsByCompany(MergedListResult r) {
    final parts = {for (final p in r.parts) p.company.key: p};
    final all = [for (final p in r.parts) p.company, ...r.missing]..sort((a, b) => a.index.compareTo(b.index));
    // ربطٌ ثانٍ للمدير نفسه: قائمته قائمة أصله ⇒ لا سطر ولا «بلا». الأصل من وصلت قائمته — كدمج الصفوف (mergeRows) نفسه.
    final same = sameManagerOf(all, prefer: (c) => parts[c.key]?.rows != null);
    final amount = <String, int>{};
    final count = <String, int>{};
    for (final s in r.rows) {
      final k = s.companyKey;
      if (k == null || s.isAbandoned || !s.hasDebt) continue;
      amount[k] = (amount[k] ?? 0) + s.debtAbs.round();
      count[k] = (count[k] ?? 0) + 1;
    }
    // قائمةٌ تعذّرت (لا الكبيرة: أمّها كبيرةٌ مثلها، ولا المرفوضة للموظّف): ديون أخواتها على الساس نفسه خارج المجموع.
    final failed = <String, List<MergedCompany>>{};
    for (final p in r.parts) {
      if (p.rows != null || p.bigTotal != null || p.denied || same.containsKey(p.company.key)) continue;
      failed.putIfAbsent(p.company.ns, () => []).add(p.company);
    }
    return MergedDebts([
      for (final c in all)
        if (!same.containsKey(c.key))
          if (_debtWhy(c, parts[c.key], failed[c.ns]) case final why?)
            (key: c.key, amount: null, count: null, reason: why)
          else
            (key: c.key, amount: amount[c.key] ?? 0, count: count[c.key] ?? 0, reason: null),
    ]);
  }

  /// لماذا لا تُجمع ديون [c] — null: تُجمع. نصٌّ قصير يفهمه الوكيل (يُقرأ في خانتها وبعد «بلا «X» —»).
  static String? _debtWhy(MergedCompany c, MergedCompanyList? p, List<MergedCompany>? failedNs) {
    if (p == null) {
      if (c.provider == MergedProvider.ftth) return 'ديونها لا تُجمع هنا بعد';
      if (!c.appCapable || c.reason == 'kit_web_only') return 'تُعرض من الموقع';
      return switch (c.status) {
        MergedStatus.needsLogin => mergedWord('تحتاج دخول', 'تحتاج دخول مديرها'),
        MergedStatus.loading => 'تُحمَّل الآن',
        _ => 'متوقّفة الآن',
      };
    }
    if (p.bigTotal != null) return mergedWord('كبيرة، افتحها وحدها', 'كبيرة، انتقل إليها من «صفحاتي»');
    if (p.rows == null) return p.denied ? MergedMode.noAccess('مشتركيها') : 'تعذّرت قراءة ديونها';
    if (p.partial) return 'قائمتها ناقصة من مزوّدها';
    if (p.debtsUnavailable) return 'تعذّرت قراءة ديونها';
    if (!_iqd(c)) return c.currency == null ? 'عملتها غير معروفة' : 'عملتها ${c.currency}';
    if (failedNs != null && failedNs.isNotEmpty) {
      return 'تعذّرت قائمة ${failedNs.map((x) => '«${iso(x.name)}»').join('، ')} المرتبطة بها';
    }
    return null;
  }
}
