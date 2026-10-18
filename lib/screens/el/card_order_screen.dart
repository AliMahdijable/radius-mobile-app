import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/dashboard_api.dart';
import '../../api/earthlink_api.dart';
import '../../api/el_card_order_gate.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/el_deposit_password_field.dart';
import '../../widgets/skeleton.dart';

/// ايرث لنك — «طلب الكارتات» (صاحب الحساب وحده).
///
/// طلب دفعة كارتات تعبئة من ايرث لنك نفسها **يُخصم ثمنها من رصيد الإيداع**
/// — كما في تطبيقهم الرسميّ. قرار المستخدم (١٨ أكتوبر): «خلّيها الميزة»،
/// للمالك وحده، بتأكيدٍ قبل الطلب وحارس تكرار، وبلا تجربةٍ حيّة مسبقة.
///
/// ⚠️ مالٌ حقيقيّ — القواعد:
///  • **تأكيدٌ دائماً** قبل الإرسال، بتقدير الخادم نفسه
///    (`/el/card-order/quote`: سعر الكارت لدى ايرث لنك × العدد، والرصيد قبل
///    وبعد)، ومجموعه يُرسَل مع الطلب فيرفضه الخادم إن تغيّرت الكلفة.
///  • **نداءٌ واحد** بلا أيّ إعادة تلقائيّة، ومفتاح طلبٍ (`request_id`) يتبعه:
///    المفتاح = طلبٌ واحد. بعد نتيجةٍ غامضة يرفض الخادم المفتاح نفسه
///    (`ORDER_UNRESOLVED`) ولو مع `confirmRepeat`؛ و«طلبٌ جديدٌ فعلاً» (الإقرار)
///    يأخذ **مفتاحاً جديداً** دائماً — فلا يُقرأ الإقرار إعادةً للطلب نفسه.
///  • **حارس تكرار**: نفس السطور خلال [kElCardOrderDupWindow] (هنا أو عند
///    الخادم — ساعةٌ بعد نتيجةٍ غامضة) ⇒ إقرارٌ صريح بطلبٍ ثانٍ
///    (`confirmRepeat`)، والخادم يقرأ سجلّ ايرث لنك قبل أن يقبله بعد غموض
///    (`ORDER_MAYBE_PLACED` إن ظهر طلبٌ منذها).
///  • **غير المؤكَّد** (لا ردّ/`ORDER_UNCONFIRMED`): ربّما أُرسل ⇒ لا إعادة،
///    وتنبيهٌ يبقى حتى يراجع «سجلّ الطلبات»، والسجلّ يُحدَّث فوراً.
///  • **موقوفٌ بالخادم** (`CARD_ORDER_OFF` من التقدير أو الطلب): لا نموذج ولا
///    إرسال — تنبيهٌ مكانهما، والرصيد والسجلّ باقيان؛ والباب يُغلق معه
///    ([ElCardOrderGate]). سحبٌ للتحديث يعيد السؤال.
class ElCardOrderScreen extends StatefulWidget {
  const ElCardOrderScreen({super.key, this.days = 7, this.initialCounts});

  /// المدّة التي يُقرأ بها «المطلوب» لكلّ باقة (1 · 3 · 7 · 30).
  final int days;

  /// أعدادٌ مبدئيّة لكلّ باقة (`profile_id` ← العدد) — من «الكارتات المطلوبة».
  final Map<int, int>? initialCounts;

  @override
  State<ElCardOrderScreen> createState() => _ElCardOrderScreenState();
}

/// آخر طلبٍ أُرسل لهذا الحساب — حارس التكرار (لكلّ معرّف مدير).
@immutable
class _RecentOrder {
  const _RecentOrder(this.signature, this.at, {required this.unclear});
  final String signature;
  final DateTime at;
  final bool unclear;
}

/// باقةٌ في «طلب الكارتات»: من قائمة الموزّع (`/v2/packages` — ما يقبله الطلب)،
/// ومعها من «الكارتات المطلوبة» إن وُجدت: المتوفّر والمطلوب للمدّة وكلفة
/// التفعيل (تقديرٌ «≈» حتى يحسب الخادم سعر الكارت).
@immutable
class _Pkg {
  const _Pkg({
    required this.profileId,
    required this.name,
    this.available,
    this.needed = 0,
    this.fallbackCost,
  });

  final int profileId;
  final String name;

  /// `null` = غير معروف (الباقة ليست في «الكارتات المطلوبة»).
  final int? available;
  final int needed;
  final num? fallbackCost;
}

/// قائمة «طلب الكارتات»: باقات الموزّع ([packages] — ما يقبله الطلب) ومعها
/// المتوفّر/المطلوب/الكلفة من «الكارتات المطلوبة» ([needed]) بالمعرّف. تعذّرت
/// الأولى ⇒ الثانية وحدها؛ والاثنتان ⇒ `null`. الأعلى طلباً أوّلاً ثمّ الاسم.
List<_Pkg>? _mergePackages({
  required List<({int id, String name})>? packages,
  required List<ElNeededCard>? needed,
}) {
  if (packages == null && needed == null) return null;
  final byId = {
    for (final n in needed ?? const <ElNeededCard>[]) n.profileId: n,
  };
  final out = <_Pkg>[];
  if (packages != null) {
    for (final p in packages) {
      final n = byId[p.id];
      out.add(_Pkg(
        profileId: p.id,
        name: p.name,
        available: n?.available,
        needed: n?.needed ?? 0,
        fallbackCost: (n != null && n.unitPrice > 0) ? n.unitPrice : null,
      ));
    }
  } else {
    for (final n in needed!) {
      out.add(_Pkg(
        profileId: n.profileId,
        name: n.name,
        available: n.available,
        needed: n.needed,
        fallbackCost: n.unitPrice > 0 ? n.unitPrice : null,
      ));
    }
  }
  out.sort((a, b) {
    final byNeeded = b.needed.compareTo(a.needed);
    if (byNeeded != 0) return byNeeded;
    return a.name.compareTo(b.name);
  });
  return List<_Pkg>.unmodifiable(out);
}

/// أقصى عددٍ للسطر الواحد — حارسٌ من خطأ إصبع (١٠٠٠ بدل ١٠٠). الخادم
/// يحدّه بـ١٠٠٠ للباقة و٥٠٠٠ للطلب.
const int kElCardOrderMaxPerLine = 500;

/// أقصى عدد باقاتٍ في تقديرٍ واحد (حدّ الخادم ٣٠).
const int kElCardOrderQuoteMaxItems = 30;

/// توقيع الطلب: الباقات مرتّبةً بأعدادها — طلبان بالتوقيع نفسه تكرارٌ.
@visibleForTesting
String elCardOrderSignature(Iterable<ElCardOrderItem> items) {
  final list = [
    for (final i in items)
      if (i.count > 0) i,
  ]..sort((a, b) => a.profileId.compareTo(b.profileId));
  return list.map((i) => '${i.profileId}x${i.count}').join(',');
}

/// نافذة حارس التكرار: الطلب نفسه خلالها يحتاج إقراراً صريحاً.
const Duration kElCardOrderDupWindow = Duration(minutes: 10);

/// آخر طلبٍ لكلّ حساب (معرّف المدير) — يعيش ما عاش التطبيق، لا يُحفظ.
final Map<String, _RecentOrder> _recentOrders = {};

@visibleForTesting
void debugClearElCardOrderRecent() => _recentOrders.clear();

class _ElCardOrderScreenState extends State<ElCardOrderScreen> {
  // ── الباقات ──
  List<_Pkg>? _packages;
  bool _pkgLoading = true;
  String? _pkgError;
  final Map<int, int> _counts = {};

  /// سعر الكارت لكلّ باقة **كما يحسبه الخادم** (سعر ايرث لنك للكارت — ما
  /// يُخصم فعلاً)، من تقديرٍ أوّليّ ثمّ من كلّ تقدير. الغائب يُقدَّر بكلفة
  /// «الكارتات المطلوبة» ويُعلَّم «≈».
  final Map<int, num> _unit = {};

  // ── الرصيد ──
  num? _balance;
  bool _balanceLoading = true;

  // ── الإرسال ──
  final _deposit = ElDepositPasswordController();
  bool _quoting = false;
  bool _sending = false;

  /// آخر إرسالٍ بلا ردٍّ مؤكَّد — التنبيه يبقى حتى يراجع السجلّ.
  bool _unclear = false;
  String? _adminId;

  /// الخادم يقول «طلب الكارتات موقوف» — تنبيهٌ مكان النموذج.
  bool _off = false;

  /// مفتاح الطلب الجاري لتوقيعٍ بعينه — يُعاد نفسه لإرسالٍ **بلا إقرار** بعد فشلٍ
  /// مؤكَّد (لم يُرسَل) أو ردٍّ ضائع (فيُرجع الخادم النتيجة الأولى إن كانت وصلت، أو
  /// `ORDER_UNRESOLVED` إن غمضت)، ويُجدَّد بعد كلّ نجاح ومع كلّ إقرارٍ بطلبٍ جديد.
  ({String sig, String ref})? _attempt;

  // ── السجلّ ──
  List<ElCardOrder>? _orders;
  bool _ordersLoading = true;
  String? _ordersError;

  @override
  void initState() {
    super.initState();
    final init = widget.initialCounts;
    if (init != null) {
      for (final e in init.entries) {
        if (e.value > 0) {
          _counts[e.key] = math.min(e.value, kElCardOrderMaxPerLine);
        }
      }
    }
    _off = ElCardOrderGate.open.value == false;
    _deposit.addListener(_onDepositChanged);
    AuthStorage.readAdminId().then((id) {
      if (mounted) setState(() => _adminId = id);
    });
    _loadAll();
  }

  void _onDepositChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _deposit.removeListener(_onDepositChanged);
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadPackages(), _loadBalance(), _loadOrders()]);
  }

  Future<void> _loadPackages() async {
    if (mounted) {
      setState(() {
        _pkgLoading = true;
        _pkgError = null;
      });
    }
    final (list, needed) = await (
      EarthlinkApi.orderPackages(),
      EarthlinkApi.prepaidNeeded(days: widget.days),
    ).wait;
    if (!mounted) return;
    final pk = _mergePackages(
      packages: list.message == null ? list.items : null,
      needed: needed.message == null ? needed.items : null,
    );
    setState(() {
      _pkgLoading = false;
      if (pk != null) {
        _packages = pk;
        // عددٌ لباقةٍ لم تعد في القائمة لا يُرسَل.
        final ids = {for (final p in pk) p.profileId};
        _counts.removeWhere((k, _) => !ids.contains(k));
      } else {
        _pkgError = list.message ?? needed.message;
      }
    });
    if (pk != null && pk.isNotEmpty) _learnPrices(pk);
  }

  /// سعر الكارت لكلّ باقة من تقدير الخادم (كارتٌ واحد لكلّ باقة — قراءةٌ بلا
  /// أثر). يكفي ما عُرف منه: باقةٌ مجهولة السعر تبقى «≈» حتى المراجعة.
  Future<void> _learnPrices(List<_Pkg> pk) async {
    final items = [
      for (final p in pk.take(kElCardOrderQuoteMaxItems))
        (profileId: p.profileId, count: 1),
    ];
    final epoch = ElCardOrderGate.epoch;
    final q = await EarthlinkApi.quoteCardOrder(items);
    if (!mounted) return;
    // التقدير يفحص مفتاح الخادم قبل أيّ شيء: «موقوف» أو تقديرٌ (ولو جزئيّاً) ⇒
    // الحال معروفة.
    if (q.code == EarthlinkApi.codeCardOrderOff) {
      _markOff(epoch);
      return;
    }
    if (q.data != null) _markOn(epoch);
    final costs = q.data?.unitCosts;
    if (costs == null || costs.isEmpty) return;
    setState(() => _unit.addAll(costs));
  }

  /// `CARD_ORDER_OFF`: النموذج يُستبدل بالتنبيه، والباب يُغلق معه.
  void _markOff(int epoch) {
    ElCardOrderGate.apply(false, epoch: epoch);
    if (mounted && !_off) setState(() => _off = true);
  }

  void _markOn(int epoch) {
    ElCardOrderGate.apply(true, epoch: epoch);
    if (mounted && _off) setState(() => _off = false);
  }

  Future<void> _loadBalance() async {
    if (mounted) setState(() => _balanceLoading = true);
    final w = await DashboardApi.fetchWallet();
    if (!mounted) return;
    setState(() {
      _balance = w?.balance;
      _balanceLoading = false;
    });
  }

  Future<void> _loadOrders() async {
    if (mounted) {
      setState(() {
        _ordersLoading = true;
        _ordersError = null;
      });
    }
    // باسورد مكتوبٌ في الحقل (لا محفوظ) يُرسَل مع السجلّ — الخادم يطلبه حين
    // لا محفوظ عنده (`DEPOSIT_PASSWORD_REQUIRED`).
    final r =
        await EarthlinkApi.cardOrders(depositPassword: _deposit.passwordToSend);
    if (!mounted) return;
    setState(() {
      _ordersLoading = false;
      if (r.message == null) {
        _orders = r.items;
      } else {
        _ordersError = r.message;
      }
    });
  }

  // ═══════════════ الحساب ═══════════════

  List<({_Pkg pkg, int count})> get _lines {
    final pk = _packages ?? const <_Pkg>[];
    return [
      for (final p in pk)
        if ((_counts[p.profileId] ?? 0) > 0)
          (pkg: p, count: _counts[p.profileId]!),
    ];
  }

  /// سعر الكارت المعروض: الخادم إن عرفه، وإلّا كلفة «الكارتات المطلوبة»
  /// تقديراً، وإلّا `null` (يُحسب عند المراجعة).
  num? _unitOf(_Pkg p) => _unit[p.profileId] ?? p.fallbackCost;
  bool _exact(_Pkg p) => _unit.containsKey(p.profileId);

  int get _totalCards => _lines.fold<int>(0, (s, l) => s + l.count);

  /// `null` = سطرٌ مختار بلا أيّ سعر بعد — المجموع عند المراجعة.
  num? get _totalCost {
    num t = 0;
    for (final l in _lines) {
      final u = _unitOf(l.pkg);
      if (u == null) return null;
      t += l.count * u;
    }
    return t;
  }

  /// المجموع تقديريٌّ إن غاب سعر الخادم عن سطرٍ مختار.
  bool get _totalApprox => _lines.any((l) => !_exact(l.pkg));

  List<ElCardOrderItem> get _items => [
        for (final l in _lines) (profileId: l.pkg.profileId, count: l.count),
      ];

  bool get _busy => _sending || _quoting;

  bool get _canReview =>
      !_off &&
      !_busy &&
      _totalCards > 0 &&
      _deposit.ready &&
      _packages != null;

  /// يزيد/ينقص من العدد **الحاليّ** لا من قيمةٍ التقطها الزرّ عند بنائه —
  /// نقرتان في الإطار نفسه تُحسبان اثنتين.
  void _stepCount(int profileId, int delta) =>
      _setCount(profileId, (_counts[profileId] ?? 0) + delta);

  void _setCount(int profileId, int value) {
    final v = value.clamp(0, kElCardOrderMaxPerLine);
    setState(() {
      if (v == 0) {
        _counts.remove(profileId);
      } else {
        _counts[profileId] = v;
      }
    });
  }

  void _fillNeeded() {
    final pk = _packages;
    if (pk == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _counts.clear();
      for (final p in pk) {
        if (p.needed > 0) {
          _counts[p.profileId] = math.min(p.needed, kElCardOrderMaxPerLine);
        }
      }
    });
  }

  _RecentOrder? _recentFor(String signature) {
    final id = _adminId;
    if (id == null) return null;
    final r = _recentOrders[id];
    if (r == null || r.signature != signature) return null;
    if (DateTime.now().difference(r.at) > kElCardOrderDupWindow) return null;
    return r;
  }

  // ═══════════════ الإرسال ═══════════════

  /// تقدير الخادم ثمّ شيت التأكيد ثمّ الإرسال. [serverRepeat] نصّ الخادم حين
  /// ردّ `RECENT_DUPLICATE` (طلبٌ من جهازٍ آخر/الويب لا يعرفه هذا التطبيق)،
  /// و[costChanged] حين تغيّرت الكلفة منذ التقدير السابق.
  Future<void> _review({String? serverRepeat, bool costChanged = false}) async {
    if (!_canReview) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    final items = _items;
    final sig = elCardOrderSignature(items);
    setState(() => _quoting = true);
    final epoch = ElCardOrderGate.epoch;
    final q = await EarthlinkApi.quoteCardOrder(items);
    if (!mounted) return;
    final quote = q.data;
    setState(() {
      _quoting = false;
      if (quote != null) _unit.addAll(quote.unitCosts);
    });
    if (q.code == EarthlinkApi.codeCardOrderOff) {
      _markOff(epoch);
      _snack(q.message ?? _offText, error: true);
      return;
    }
    if (quote == null || q.message != null) {
      _snack(q.message ?? 'تعذّر حساب كلفة الطلب', error: true);
      return;
    }
    final recent = _recentFor(sig);
    final String? repeat;
    if (serverRepeat != null) {
      repeat = serverRepeat;
    } else if (recent != null) {
      final mins = DateTime.now().difference(recent.at).inMinutes;
      final ago = mins <= 0 ? 'قبل أقلّ من دقيقة' : 'قبل $mins د';
      repeat = recent.unclear
          ? 'أرسلتَ الطلب نفسه $ago ولم يصل ردّه — ربّما وصل. راجع «سجلّ '
              'الطلبات» قبل أن تكرّره.'
          : 'طلبتَ الكارتات نفسها $ago.';
    } else {
      repeat = null;
    }
    final ok = await showElCardOrderConfirmSheet(
      context,
      quote: quote,
      balance: _balance,
      repeatNotice: repeat,
      costChanged: costChanged,
    );
    if (ok != true || !mounted) return;
    await _send(items, sig, quote, confirmRepeat: repeat != null);
  }

  Future<void> _send(
    List<ElCardOrderItem> items,
    String sig,
    ElCardQuote quote, {
    required bool confirmRepeat,
  }) async {
    if (_sending) return;
    HapticFeedback.lightImpact();
    final prev = _attempt;
    // الإقرار «أريد طلباً جديداً فعلاً» = طلبٌ آخر ⇒ مفتاحٌ جديد دائماً (المفتاح
    // القديم بعد نتيجةٍ غامضة يرفضه الخادم ORDER_UNRESOLVED، ولا يصحّ أن يحمل
    // confirmRepeat فيُقرأ إعادةً للطلب نفسه).
    final ref = (!confirmRepeat && prev != null && prev.sig == sig)
        ? prev.ref
        : _newRequestId();
    _attempt = (sig: sig, ref: ref);
    setState(() => _sending = true);
    final epoch = ElCardOrderGate.epoch;
    final r = await EarthlinkApi.placeCardOrder(
      items: items,
      requestId: ref,
      expectedTotal: quote.expectedTotal,
      confirmRepeat: confirmRepeat,
      depositPassword: _deposit.passwordToSend,
      rememberDepositPassword: _deposit.rememberToSend,
    );
    if (!mounted) return;
    // طلبٌ **سابق** ربّما وصل (هذا لم يُرسَل): المفتاح نفسه بعد غموض، أو ظهر في
    // سجلّ ايرث لنك طلبٌ منذ المحاولة الغامضة — التنبيه يبقى والسجلّ يُحدَّث.
    final earlierMaybe = r.code == EarthlinkApi.codeOrderUnresolved ||
        r.code == EarthlinkApi.codeOrderMaybePlaced;
    final id = _adminId;
    if (id != null && (r.ok || r.unclear || earlierMaybe)) {
      _recentOrders[id] = _RecentOrder(sig, DateTime.now(), unclear: !r.ok);
    }
    setState(() {
      _sending = false;
      if (r.ok) {
        _counts.clear();
        _unclear = false;
        _attempt = null; // طلبٌ تالٍ مفتاحه جديد
      } else if (r.unclear || earlierMaybe) {
        _unclear = true;
      }
    });
    if (r.ok) {
      HapticFeedback.mediumImpact();
      _snack(r.duplicate
          ? 'هذا الطلب وصل سابقاً — لم يُطلب مرّة ثانية'
          : (r.message ?? 'أُرسل طلب الكارتات'));
    } else if (r.unclear) {
      _snack(r.message ??
              'لم يصل ردٌّ مؤكَّد — راجع سجلّ الطلبات قبل أن تطلب مرّة أخرى',
          error: true);
    } else if (r.code == EarthlinkApi.codeOrderUnresolved) {
      // المفتاح نفسه بعد نتيجةٍ غامضة: لم يُرسَل ثانيةً. طلبٌ جديدٌ فعلاً = إقرارٌ
      // صريح ومفتاحٌ جديد (والخادم يقرأ سجلّ ايرث لنك قبله).
      _loadBalance();
      _loadOrders();
      await _review(
          serverRepeat: r.message ??
              'محاولتك السابقة لهذا الطلب لم يُعرف مصيرها — راجع «سجلّ '
                  'الطلبات» قبل أن تكرّره.');
      return;
    } else if (r.code == EarthlinkApi.codeOrderMaybePlaced) {
      // ظهر في سجلّ ايرث لنك طلبٌ منذ المحاولة الغامضة (أو لم يُجزم) — لم يُرسَل
      // طلبٌ ثانٍ؛ رسالة الخادم تقول ذلك، والسجلّ أمامه.
      _snack(
          r.message ??
              'غالباً وصل طلبك السابق — لم يُرسَل طلبٌ ثانٍ. راجع «سجلّ الطلبات».',
          error: true);
      _loadBalance();
      _loadOrders();
      return;
    } else if (r.code == EarthlinkApi.codeOrderRepeat) {
      // حارس الخادم: الطلب نفسه قبل قليل (ربّما من جهازٍ آخر) ⇒ إقرارٌ صريح.
      await _review(serverRepeat: r.message ?? 'طلبتَ الكارتات نفسها قبل قليل.');
      return;
    } else if (r.code == EarthlinkApi.codeCostChanged) {
      _snack(r.message ?? 'تغيّرت كلفة الكروت — راجع الطلب من جديد',
          error: true);
      await _review(costChanged: true);
      return;
    } else if (r.code == EarthlinkApi.codeCardOrderOff) {
      // أُوقف بالخادم بين المراجعة والإرسال: لم يُرسَل شيء.
      _markOff(epoch);
      _snack(r.message ?? _offText, error: true);
      return;
    } else {
      _snack(r.message ?? 'تعذّر إرسال طلب الكارتات', error: true);
    }
    if (r.ok || r.unclear) {
      _loadBalance();
      _loadOrders();
    }
  }

  static const _offText = 'طلب الكارتات موقوفٌ مؤقّتاً — لم يُرسَل شيء';

  /// مفتاح طلبٍ عشوائيّ (٣٢ خانة ستّ عشريّة) — بصيغة `request_id` عند الخادم.
  static String _newRequestId() {
    final rnd = math.Random.secure();
    return List<String>.generate(
        16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppType.button(color: AppColors.onBrand)),
        backgroundColor: error ? AppColors.errorFill : AppColors.brand,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
        margin: const EdgeInsets.all(Sp.lg),
      ),
    );
  }

  Future<void> _editCount(_Pkg p) async {
    final v = await showElCardCountDialog(
      context,
      title: p.name,
      initial: _counts[p.profileId] ?? 0,
    );
    if (v == null || !mounted) return;
    _setCount(p.profileId, v);
  }

  // ═══════════════ البناء ═══════════════

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('طلب الكارتات',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 16)),
              Text('من ايرث لنك — يُخصم من رصيد الإيداع',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: AppColors.brandAccent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _balanceCard(),
                const SizedBox(height: Sp.lg),
                if (_unclear) ...[
                  _note(
                    LucideIcons.triangleAlert,
                    'آخر طلبٍ لم يصل ردّه — ربّما أُرسل وخُصم ثمنه. راجع «سجلّ '
                    'الطلبات» أدناه قبل أن تطلب مرّة أخرى.',
                    tone: AppTone.warning,
                  ),
                  const SizedBox(height: Sp.lg),
                ],
                if (_off)
                  _note(
                    LucideIcons.circlePause,
                    'طلب الكارتات موقوفٌ مؤقّتاً — لا يُرسَل أيّ طلبٍ الآن. '
                    'سجلّ طلباتك السابقة أدناه.',
                    tone: AppTone.warning,
                  )
                else ...[
                  _packagesSection(),
                  const SizedBox(height: Sp.lg),
                  _sendSection(),
                ],
                const SizedBox(height: Sp.xl),
                _historySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.onBrandFill2,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: const Icon(LucideIcons.wallet,
                color: AppColors.onBrand, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رصيد الإيداع الحاليّ',
                    style: AppType.label(color: AppColors.onBrandSecondary)),
                const SizedBox(height: 4),
                if (_balanceLoading)
                  const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.onBrand),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      textBaseline: TextBaseline.alphabetic,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      children: [
                        Text(
                          _balance == null ? '—' : formatIQD(_balance!),
                          textDirection: TextDirection.ltr,
                          style: AppType.amount(color: AppColors.onBrand)
                              .copyWith(fontSize: 22),
                        ),
                        const SizedBox(width: 6),
                        Text('د.ع',
                            style: AppType.body(
                                color: AppColors.onBrandSecondary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _balanceLoading ? null : _loadBalance,
            icon: const Icon(LucideIcons.refreshCw,
                color: AppColors.onBrandStrong, size: 18),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  // ═══════════════ الباقات ═══════════════

  Widget _packagesSection() {
    final pk = _packages;
    final anyNeeded = (pk ?? const <_Pkg>[]).any((p) => p.needed > 0);
    return _SectionCard(
      icon: LucideIcons.tickets,
      title: 'الكارتات',
      trailing: (pk != null && anyNeeded)
          ? TextButton.icon(
              onPressed: _busy ? null : _fillNeeded,
              icon: Icon(LucideIcons.listChecks,
                  size: 16, color: AppColors.brandAccent),
              label: Text('املأ بالمطلوب',
                  style: AppType.label(color: AppColors.brandAccent)),
            )
          : null,
      children: [
        Text(
          'اختر عدد الكارتات لكلّ باقة. سعر الكارت لدى ايرث لنك، والمطلوب '
          '${_periodText(widget.days)} من «الكارتات المطلوبة».',
          style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.5),
        ),
        const SizedBox(height: Sp.md),
        if (pk == null && _pkgError != null)
          _errorBox(_pkgError!, onRetry: _loadPackages, busy: _pkgLoading)
        else if (pk == null)
          Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(height: Sp.sm),
                const SkeletonBox(height: 72, borderRadius: R.md),
              ],
            ],
          )
        else if (pk.isEmpty)
          _note(LucideIcons.inbox, 'لا توجد باقات كارتات لهذا الحساب')
        else
          for (var i = 0; i < pk.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.sm),
            _OrderRow(
              pkg: pk[i],
              count: _counts[pk[i].profileId] ?? 0,
              unit: _unitOf(pk[i]),
              exact: _exact(pk[i]),
              periodText: _periodText(widget.days),
              enabled: !_busy,
              onStep: (d) => _stepCount(pk[i].profileId, d),
              onEdit: () => _editCount(pk[i]),
            ),
          ],
      ],
    );
  }

  // ═══════════════ الإرسال ═══════════════

  Widget _sendSection() {
    final total = _totalCost;
    final approx = _totalApprox ? '≈ ' : '';
    final after =
        (_balance == null || total == null) ? null : _balance! - total;
    final short = after != null && after < 0 && _totalCards > 0;
    return _SectionCard(
      icon: LucideIcons.shoppingCart,
      title: 'الطلب',
      children: [
        SheetRowsGroup(rows: [
          SheetRowData(
            label: 'عدد الكارتات',
            value: formatIQD(_totalCards),
          ),
          SheetRowData(
            label: 'الكلفة',
            value: total == null
                ? 'عند المراجعة'
                : '$approx${formatIQD(total)} د.ع',
            strong: true,
          ),
          if (after != null && _totalCards > 0)
            SheetRowData(
              label: 'الرصيد بعد الطلب (تقريباً)',
              value: '${after < 0 ? '-' : ''}${formatIQD(after)} د.ع',
              valueColor: short ? AppColors.error : null,
            ),
        ]),
        if (short) ...[
          const SizedBox(height: Sp.sm),
          _note(LucideIcons.circleAlert,
              'رصيد الإيداع لا يكفي لهذا الطلب على الأغلب — ايرث لنك ترفضه.',
              tone: AppTone.danger),
        ],
        const SizedBox(height: Sp.md),
        Text('باسورد الإيداع', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(height: Sp.sm),
        ElDepositPasswordField(
          controller: _deposit,
          enabled: !_busy,
          hint: '••••••',
        ),
        const SizedBox(height: Sp.lg),
        _primaryButton(
          label: _totalCards > 0
              ? 'مراجعة الطلب (${formatIQD(_totalCards)} كارت)'
              : 'مراجعة الطلب',
          icon: LucideIcons.shoppingCart,
          loading: _busy,
          onTap: _canReview ? () => _review() : null,
        ),
        const SizedBox(height: Sp.sm),
        Text(
          'تُحسب الكلفة من ايرث لنك ويُعرض الطلب كاملاً للتأكيد قبل الإرسال.',
          textAlign: TextAlign.center,
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }

  // ═══════════════ السجلّ ═══════════════

  Widget _historySection() {
    final orders = _orders;
    return _SectionCard(
      icon: LucideIcons.history,
      title: 'سجلّ الطلبات',
      trailing: _ordersLoading
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.brandAccent),
              ),
            )
          : IconButton(
              onPressed: _loadOrders,
              tooltip: 'تحديث',
              icon: Icon(LucideIcons.refreshCw,
                  size: 18, color: AppColors.textMid),
            ),
      children: [
        if (orders == null && _ordersError != null)
          _errorBox(_ordersError!, onRetry: _loadOrders, busy: _ordersLoading)
        else if (orders == null)
          Column(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(height: Sp.sm),
                const SkeletonBox(height: 84, borderRadius: R.md),
              ],
            ],
          )
        else if (orders.isEmpty)
          _note(LucideIcons.inbox, 'لا طلبات كارتات سابقة')
        else
          for (var i = 0; i < orders.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.sm),
            _OrderHistoryRow(order: orders[i]),
          ],
      ],
    );
  }

  // ═══════════════ عناصر مشتركة ═══════════════

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null && !loading;
    return SizedBox(
      height: H.button,
      child: Material(
        color: enabled ? AppColors.brand : AppColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(R.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.onBrand),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon,
                            size: 18,
                            color: enabled
                                ? AppColors.onBrand
                                : AppColors.textLow),
                        const SizedBox(width: Sp.sm),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.button(
                                color: enabled
                                    ? AppColors.onBrand
                                    : AppColors.textLow),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox(String message,
      {required VoidCallback onRetry, required bool busy}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(LucideIcons.triangleAlert, message, tone: AppTone.danger),
        const SizedBox(height: Sp.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: busy ? null : onRetry,
            icon: Icon(LucideIcons.refreshCw,
                size: 16, color: AppColors.brandAccent),
            label: Text('إعادة المحاولة',
                style: AppType.label(color: AppColors.brandAccent)),
          ),
        ),
      ],
    );
  }

  Widget _note(IconData icon, String text, {AppTone tone = AppTone.neutral}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: tone.fill),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text,
                style: AppType.body(color: AppColors.textBody)
                    .copyWith(height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// «لأسبوع» … — نصّ المدّة كما في «الكارتات المطلوبة».
String _periodText(int days) => switch (days) {
      1 => 'ليوم واحد',
      3 => 'لـ٣ أيام',
      7 => 'لأسبوع',
      30 => 'لشهر',
      _ => 'لـ$days يوم',
    };

/// بطاقة قسم: رأسٌ بأيقونة وعنوان (وطرفٌ اختياريّ) ثمّ محتوى.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: H.iconBox,
                height: H.iconBox,
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(icon, size: 18, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.cardTitleBold(color: AppColors.textHi)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: Sp.md),
          ...children,
        ],
      ),
    );
  }
}

/// صفّ باقة في الطلب: الاسم والكلفة والمتوفّر/المطلوب، ومُعدِّد العدد.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.pkg,
    required this.count,
    required this.unit,
    required this.exact,
    required this.periodText,
    required this.enabled,
    required this.onStep,
    required this.onEdit,
  });

  final _Pkg pkg;
  final int count;

  /// سعر الكارت المعروض (`null` = يُحسب عند المراجعة)، و[exact] = من الخادم
  /// (لا «≈» تقديريّ).
  final num? unit;
  final bool exact;
  final String periodText;
  final bool enabled;

  /// يزيد/ينقص من العدد الحاليّ بمقدار (±١ أو ±١٠).
  final ValueChanged<int> onStep;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final on = count > 0;
    final approx = exact ? '' : '≈ ';
    final u = unit;
    final facts = <String>[
      u == null
          ? 'السعر عند المراجعة'
          : 'سعر الكارت $approx${formatIQD(u)} د.ع',
      if (pkg.available != null) 'المتوفّر ${formatIQD(pkg.available!)}',
      if (pkg.needed > 0) 'المطلوب $periodText ${formatIQD(pkg.needed)}',
    ];
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: on ? AppColors.brandSoftBg : AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(
            color: on ? AppColors.brandSoftBorder : AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pkg.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi)
                      .copyWith(fontSize: 13.5),
                ),
              ),
              const SizedBox(width: Sp.sm),
              _CountStepper(
                value: count,
                enabled: enabled,
                onStep: onStep,
                onEdit: onEdit,
                label: pkg.name,
              ),
            ],
          ),
          const SizedBox(height: Sp.xs),
          Text(
            facts.join(' · '),
            style: AppType.muted(color: AppColors.textLow),
          ),
          if (on && u != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              'المجموع $approx${formatIQD(count * u)} د.ع',
              style: AppType.bodyStrong(color: AppColors.brandOnSoft),
            ),
          ],
        ],
      ),
    );
  }
}

/// [−] العدد [+] — النقر على العدد يكتبه، والضغط المطوّل ±١٠.
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.value,
    required this.enabled,
    required this.onStep,
    required this.onEdit,
    required this.label,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onStep;
  final VoidCallback onEdit;
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final canDec = enabled && value > 0;
    final canInc = enabled && value < kElCardOrderMaxPerLine;
    return Directionality(
      // الأرقام والعلامتان بترتيبٍ ثابت: − يسار و+ يمين كلوحة الأرقام.
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: LucideIcons.minus,
            semantics: 'إنقاص $label',
            onTap: canDec ? () => onStep(-1) : null,
            onLongPress: canDec ? () => onStep(-10) : null,
          ),
          Semantics(
            label: 'عدد كارتات $label',
            value: '$value',
            button: true,
            child: InkWell(
              onTap: enabled ? onEdit : null,
              borderRadius: BorderRadius.circular(R.sm),
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
                child: Text(
                  '$value',
                  style: AppType.statValue(
                      color: value > 0 ? AppColors.brand : AppColors.textLow),
                ),
              ),
            ),
          ),
          _StepButton(
            icon: LucideIcons.plus,
            semantics: 'زيادة $label',
            onTap: canInc ? () => onStep(1) : null,
            onLongPress: canInc ? () => onStep(10) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semantics,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final String semantics;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final on = onTap != null;
    return Semantics(
      label: semantics,
      button: true,
      enabled: on,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(R.sm),
          child: Ink(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon,
                size: 16, color: on ? AppColors.brand : AppColors.textHint),
          ),
        ),
      ),
    );
  }
}

/// صفّ طلبٍ سابق: رقمه وتاريخه وحاله، ثمّ سطوره (الباقة × العدد · المعتمد).
class _OrderHistoryRow extends StatelessWidget {
  const _OrderHistoryRow({required this.order});
  final ElCardOrder order;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final (label, tone) = elCardOrderStatusLabel(order);
    final date = elOrderDate(order.createdAt);
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.batchNo == null
                      ? 'طلب كارتات'
                      : 'طلب رقم ${order.batchNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi),
                ),
              ),
              const SizedBox(width: Sp.sm),
              ToneChip(label: label, tone: tone, dense: true),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 2),
            Text(date,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style: AppType.muted(color: AppColors.textLow)),
          ],
          if (order.lines.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            for (final l in order.lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(LucideIcons.ticket,
                        size: 13, color: AppColors.textLow),
                    const SizedBox(width: Sp.xs),
                    Expanded(
                      child: Text(
                        l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body(color: AppColors.textBody),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    Text(
                      l.approvedCount > 0
                          ? '${formatIQD(l.amount)} كارت · اعتُمد ${formatIQD(l.approvedCount)}'
                          : '${formatIQD(l.amount)} كارت',
                      style: AppType.muted(color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// تسمية حال الطلب ونغمتها — العربيّة للمعروف، والنصّ الخام لغيره.
@visibleForTesting
(String, AppTone) elCardOrderStatusLabel(ElCardOrder o) => switch (o.status) {
      ElCardOrderStatus.pending => ('قيد المراجعة', AppTone.warning),
      ElCardOrderStatus.approved => ('معتمد', AppTone.success),
      ElCardOrderStatus.rejected => ('مرفوض', AppTone.danger),
      ElCardOrderStatus.cancelled => ('ملغى', AppTone.neutral),
      ElCardOrderStatus.unknown => (
          (o.statusRaw ?? '').trim().isEmpty ? '—' : o.statusRaw!.trim(),
          AppTone.neutral
        ),
    };

/// تاريخ الطلب «2026/10/18 · 14:05» من صيغ ايرث لنك المعروفة
/// («18/10/2026 02:05 PM» · ISO)، وإلّا النصّ كما هو.
@visibleForTesting
String? elOrderDate(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  String fmt(DateTime t) =>
      '${t.year}/${two(t.month)}/${two(t.day)} · ${two(t.hour)}:${two(t.minute)}';
  final m = RegExp(
          r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?)?$')
      .firstMatch(s);
  if (m != null) {
    var h = int.tryParse(m.group(4) ?? '') ?? 0;
    final ap = m.group(6)?.toUpperCase();
    if (ap == 'PM' && h < 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    final t = DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      h,
      int.tryParse(m.group(5) ?? '') ?? 0,
    );
    return m.group(4) == null
        ? '${t.year}/${two(t.month)}/${two(t.day)}'
        : fmt(t);
  }
  final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  if (iso != null) return fmt(iso);
  return s;
}

/// كتابة العدد مباشرةً — `null` عند الإلغاء.
Future<int?> showElCardCountDialog(
  BuildContext context, {
  required String title,
  required int initial,
}) {
  final ctrl = TextEditingController(text: initial > 0 ? '$initial' : '');
  return showDialog<int>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.sheetTitle()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          style: AppType.input(),
          decoration: InputDecoration(
            labelText: 'عدد الكارتات',
            helperText: 'حتّى ${formatIQD(kElCardOrderMaxPerLine)} للباقة',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(
              math.min(int.tryParse(v) ?? 0, kElCardOrderMaxPerLine)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(math.min(
                int.tryParse(ctrl.text) ?? 0, kElCardOrderMaxPerLine)),
            child: const Text('تمّ'),
          ),
        ],
      ),
    ),
  ).whenComplete(ctrl.dispose);
}

/// شيت تأكيد الطلب — **تقدير الخادم** حرفيّاً: السطور (سعر الكارت لدى ايرث لنك ×
/// العدد) والمجموع، والرصيد قبل وبعد، وتنبيه أنّ الطلب لا يُلغى من هنا.
/// [repeatNotice] غير `null` = الطلب نفسه أُرسل قبل قليل (هنا أو عند الخادم) ⇒
/// إقرارٌ صريح قبل تفعيل الزرّ. [costChanged] = تغيّرت الكلفة منذ التقدير
/// السابق. يرجع `true` عند التأكيد وحده.
Future<bool?> showElCardOrderConfirmSheet(
  BuildContext context, {
  required ElCardQuote quote,
  num? balance,
  String? repeatNotice,
  bool costChanged = false,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _ConfirmSheet(
        quote: quote,
        balance: balance,
        repeatNotice: repeatNotice,
        costChanged: costChanged,
      ),
    ),
  );
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.quote,
    required this.balance,
    required this.repeatNotice,
    required this.costChanged,
  });

  final ElCardQuote quote;
  final num? balance;
  final String? repeatNotice;
  final bool costChanged;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool _ack = false;

  bool get _dup => widget.repeatNotice != null;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final q = widget.quote;
    final total = q.total;
    // رصيد الخادم وقت التقدير أوّلاً (أحدث)، وإلّا ما في الشاشة.
    final bal = q.balance ?? widget.balance;
    final after = q.after ?? (bal == null ? null : bal - total);
    // «لا يكفي» تنبيهٌ لا منع (كالويب): الكلفة تقدير، وايرث لنك نفسها تحكم الرصيد
    // عند الطلب — رصيدٌ لا يكفي ترفضه هي.
    final short = q.enough == false || (after != null && after < 0);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.shoppingCart,
        title: 'تأكيد طلب الكارتات',
        subtitle: 'ايرث لنك — يُخصم من رصيد الإيداع',
        onClose: () => Navigator.of(context).pop(false),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.costChanged) ...[
            _box(
              icon: LucideIcons.refreshCw,
              tone: AppTone.info,
              text: 'تغيّرت كلفة الكروت لدى ايرث لنك منذ المراجعة السابقة — '
                  'هذه الكلفة الجديدة.',
            ),
            const SizedBox(height: Sp.md),
          ],
          _ConfirmLines(lines: q.lines),
          const SizedBox(height: Sp.md),
          SheetBrandResultCard(
            label: 'الكلفة — ${formatIQD(q.count)} كارت',
            value: '${formatIQD(total)} د.ع',
          ),
          if (bal != null) ...[
            const SizedBox(height: Sp.md),
            SheetRowsGroup(rows: [
              SheetRowData(
                  label: 'رصيد الإيداع الآن', value: '${formatIQD(bal)} د.ع'),
              if (after != null)
                SheetRowData(
                  label: 'بعد الطلب (تقريباً)',
                  value: '${after < 0 ? '-' : ''}${formatIQD(after)} د.ع',
                  valueColor: after < 0 ? AppColors.error : null,
                  strong: true,
                ),
            ]),
          ],
          if (short) ...[
            const SizedBox(height: Sp.md),
            _box(
              icon: LucideIcons.circleAlert,
              tone: AppTone.warning,
              text: 'رصيد الإيداع أقلّ من الكلفة التقديريّة — قد ترفض ايرث لنك '
                  'الطلب. عبّئ الرصيد أو قلّل الأعداد إن لزم.',
            ),
          ],
          const SizedBox(height: Sp.md),
          _box(
            icon: LucideIcons.triangleAlert,
            tone: AppTone.warning,
            text: 'سيُخصم المبلغ من رصيد الإيداع لدى ايرث لنك، ولا يُلغى الطلب '
                'من هنا. ${q.note ?? 'الكلفة بسعر الكارت لدى ايرث لنك، والمبلغ '
                    'النهائيّ ما تخصمه ايرث لنك.'}',
          ),
          if (_dup) ...[
            const SizedBox(height: Sp.md),
            _box(
              icon: LucideIcons.copy,
              tone: AppTone.danger,
              text: widget.repeatNotice!,
            ),
            const SizedBox(height: Sp.sm),
            Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(R.md),
                onTap: () => setState(() => _ack = !_ack),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm, vertical: Sp.xs),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(
                        color: _ack
                            ? AppColors.dangerSoftBorder
                            : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _ack,
                        onChanged: (v) => setState(() => _ack = v ?? false),
                        activeColor: AppColors.errorFill,
                      ),
                      Expanded(
                        child: Text('أعرف — أريد طلباً جديداً فعلاً',
                            style: AppType.body(color: AppColors.textHi)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'تأكيد الطلب — ${formatIQD(total)} د.ع',
        icon: LucideIcons.check,
        enabled: !_dup || _ack,
        color: _dup ? AppColors.errorFill : null,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    );
  }

  Widget _box({
    required IconData icon,
    required AppTone tone,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: tone.fill),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text,
                style: AppType.body(color: tone.onSoft).copyWith(height: 1.55)),
          ),
        ],
      ),
    );
  }
}

/// سطور الطلب في شيت التأكيد: الاسم كاملاً (سطران)، وتحته «العدد × كلفة
/// الكارت»، والمجموع في الطرف — فلا يُقصّ العدد مع اسمٍ طويل.
class _ConfirmLines extends StatelessWidget {
  const _ConfirmLines({required this.lines});
  final List<ElCardQuoteLine> lines;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lines[i].name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(color: AppColors.textHi)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatIQD(lines[i].count)} كارت × '
                          '${lines[i].unitCost == null ? '—' : formatIQD(lines[i].unitCost!)} د.ع',
                          style: AppType.muted(color: AppColors.textLabel),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Text(
                    lines[i].total == null
                        ? '—'
                        : '${formatIQD(lines[i].total!)} د.ع',
                    textDirection: TextDirection.ltr,
                    style: AppType.body(color: AppColors.textHi)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
