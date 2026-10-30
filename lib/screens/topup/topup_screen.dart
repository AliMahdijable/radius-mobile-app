import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/self_deposit_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/util/phone.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/active_company.dart';
import '../../services/auth_storage.dart';
import '../../services/provider_service.dart';
import '../../services/self_deposit_pending.dart';
import '../../services/self_deposit_sync.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'paged_history.dart';
import 'pay_nav_policy.dart';
import 'topup_pay_page.dart';
import 'topup_widgets.dart';
import '../desktop/desk_widgets.dart';

/// «شحن رصيد الصفحة» — الإيداع الذاتيّ في الساس من التطبيق.
///
/// المالك وحده، ولكلّ شركة SAS4 بما فعّلته في الساس (`list/acp` وقت التشغيل):
///   • زين كاش — صفحة الدفع داخل التطبيق ([TopupPayPage]) ثمّ يتمّ الخادم
///     الإيداع بالتوكن الراجع.
///   • كارت تعبئة الساس / كارت كوشك — رمز PIN، والرصيد فوراً.
///   • تسديد — فاتورة تُدفع بمنفذ (اسم + هاتف يصله SMS).
///   • غيرها (HyperPay/Switch) — من لوحة الشركة على المتصفّح.
/// ايرث لنك والمشروع الوطنيّ بلا شحن (المزوّد لا يوفّره)، والموظّف مقفل.
class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  /// مبالغ سريعة لزين كاش والفاتورة.
  static const quickAmounts = [10000, 25000, 50000, 100000];

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

/// نتيجةٌ معروضة ومعها ما يلزم لـ«تحقّق الآن».
class _Shown {
  const _Shown(
    this.outcome, {
    required this.flow,
    this.amount,
    this.closedEarly = false,
    this.previous = false,
  });
  final SelfDepositOutcome outcome;
  final SelfDepositFlow flow;
  final int? amount;
  final bool closedEarly;

  /// من دفعةٍ سابقة حُسمت عند فتح الشاشة.
  final bool previous;
}

class _TopupScreenState extends State<TopupScreen> {
  SelfDepositOptions? _opts;
  bool _loading = true;
  String? _loadError;

  SelfDepositMethod? _method;
  final _amountCtrl = TextEditingController();
  int _amount = 0;
  final _pinCtrl = TextEditingController();
  bool _pinHidden = true;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _busy = false;
  bool _checking = false;
  _Shown? _shown;

  /// آخر عمليّات الشحن من الخادم: ١٠ ثمّ «عرض المزيد»، وبحثٌ برقم العمليّة (المالك ٣٠ أكتوبر). لا صفوف ⇒ لا قسم.
  late final PagedHistoryController<SelfDepositRecord> _history = PagedHistoryController<SelfDepositRecord>(
    fetch: ({before, query, required limit}) => SelfDepositApi.historyPage(limit: limit, before: before, query: query),
    idOf: (r) => r.psid,
  )..addListener(_onHistory);

  void _onHistory() {
    if (mounted) setState(() {});
  }
  String? _checkingPsid;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onText);
    _pinCtrl.addListener(_onText);
    _nameCtrl.addListener(_onText);
    _phoneCtrl.addListener(_onText);
    SelfDepositSync.install();
    SelfDepositSync.changes.addListener(_onSyncChange);
    _load();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  /// جولة تسليمٍ في الخلفيّة حسمت رجوعاً (عادت الشبكة، أو عاد التطبيق للواجهة):
  /// السجلّ من جديد، والنتيجة تُعرض إن لم يكن على الشاشة غيرها.
  void _onSyncChange() {
    if (!mounted) return;
    unawaited(_loadHistory());
    final rep = SelfDepositSync.lastReport;
    if (rep == null || _shown != null) return;
    for (final (p, o) in rep.results) {
      if (o.status == SelfDepositStatus.success && o.settled) {
        _show(_Shown(o,
            flow: SelfDepositFlow.redirect, amount: p.amount, previous: true));
        break;
      }
    }
  }

  @override
  void dispose() {
    SelfDepositSync.changes.removeListener(_onSyncChange);
    _history.dispose();
    _amountCtrl.dispose();
    _pinCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ═══════════════ التحميل ═══════════════

  Future<void> _load({bool reconcile = true}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final epoch = SelfDepositState.epoch;
    final r = await SelfDepositApi.options();
    if (!mounted) return;
    final data = r.data;
    setState(() {
      _loading = false;
      if (data == null) {
        _loadError = r.message ?? 'تعذّر جلب وسائل الدفع';
        return;
      }
      _opts = data;
      final inApp = data.inAppMethods;
      if (_method == null || !inApp.any((m) => m.id == _method!.id)) {
        _method = inApp.isEmpty ? null : inApp.first;
      }
    });
    if (data != null) SelfDepositState.apply(data, epoch: epoch);
    if (data == null || !data.enabled) return;
    // السجلّ والقيود المعلّقة لصاحب الحساب وحده — والمقفل لا يطلب شيئاً.
    // «متوقّفٌ مؤقّتاً» لصاحب الحساب أيضاً: سجلّه و«تحقّق» هما ما بقي له.
    final owner = data.block == SelfDepositBlock.none ||
        data.block == SelfDepositBlock.noPermission ||
        data.block == SelfDepositBlock.noGateways ||
        data.block == SelfDepositBlock.paused;
    if (!owner) return;
    if (reconcile) {
      unawaited(_reconcileStored().whenComplete(_loadHistory));
    } else {
      unawaited(_loadHistory());
    }
  }

  Future<void> _loadHistory() => _history.reload();

  /// عمليّات زين كاش سابقةٌ لم يُحسم أمرها (انقطع النت لحظة الرجوع، أو
  /// أُغلق التطبيق قبل أن يردّ الخادم) — يُعاد إرسال رجوعها أو يُسأل عنها.
  Future<void> _reconcileStored() async {
    // ١) روابط الرجوع الملتقطة: **كلّها**، الأقدم أوّلاً — جولة [SelfDepositSync]
    //    نفسها التي تجري عند الإقلاع والعودة للواجهة (لا قيد «أحدث ثلاثة»).
    final rep = await SelfDepositSync.run(force: true);
    if (!mounted) return;
    for (final (p, o) in rep.results) {
      // يُعرض ما يعني المدير: رصيدٌ أُضيف، أو رُفض، أو دفعةٌ ملتقطة لم تُحسم بعد.
      if (_shown == null) {
        _show(_Shown(o,
            flow: SelfDepositFlow.redirect, amount: p.amount, previous: true));
      }
    }
    // ٢) عمليّاتٌ بلا رجوع (فُتحت الصفحة وأُغلقت قبله): حالها من الخادم — أحدث
    //    ثلاثٍ وحدها (مذكّراتٌ لا دليل؛ «تحقّق» في السجلّ لما سواها).
    String? adminId;
    try {
      adminId = await AuthStorage.readAdminId();
    } catch (_) {
      return;
    }
    final plain = [
      for (final p in await SelfDepositPendingStore.forAdmin(adminId))
        if (p.returnUrl == null) p,
    ];
    for (final p in plain.reversed.take(3)) {
      final o = await SelfDepositApi.status(p.psid);
      if (o.settled) await SelfDepositPendingStore.remove(p.psid);
      if (!mounted) return;
      // بلا رجوعٍ ما زالت معلّقة (لم يُدفع) لا تُزعجه — الرصيد إن أُضيف يُقال.
      if (o.status == SelfDepositStatus.success && _shown == null) {
        _show(_Shown(o,
            flow: SelfDepositFlow.redirect, amount: p.amount, previous: true));
      }
    }
  }

  // ═══════════════ الإرسال ═══════════════

  int get _effectiveAmount => AmountShorthand.applies(_amount)
      ? AmountShorthand.expand(_amount)
      : _amount;

  String get _pin => _pinCtrl.text.replaceAll(RegExp(r'\s'), '');

  String get _phone =>
      localPhone(normalizeDigits(_phoneCtrl.text.trim()) ?? '');

  /// سبب تعطيل الزرّ — `null` = جاهز.
  String? get _invalid {
    final m = _method;
    if (m == null) return 'اختر طريقة الشحن';
    if (m.needsAmount) {
      final a = _effectiveAmount;
      if (a <= 0) return 'اكتب المبلغ';
      if (m.minAmount != null && a < m.minAmount!) {
        return 'أقلّ مبلغ ${formatIQD(m.minAmount!)} ${_currency()}';
      }
      if (m.maxAmount != null && a > m.maxAmount!) {
        return 'أكثر مبلغ ${formatIQD(m.maxAmount!)} ${_currency()}';
      }
    }
    if (m.needsPin && _pin.length < 4) return 'اكتب رمز الكارت';
    if (m.needsPayer) {
      if (_nameCtrl.text.trim().length < 3) return 'اكتب اسم الدافع';
      if (!RegExp(r'^07\d{9}$').hasMatch(_phone)) {
        return 'اكتب رقم هاتفٍ عراقيّ صحيح';
      }
    }
    return null;
  }

  String _currency() => _opts?.currencyLabel ?? 'د.ع';

  /// يوزر الصفحة واسم الشركة — من «شركاتي» في التطبيق، وإلّا ممّا قرأه الخادم.
  (String, String) _page() {
    final c = ActiveCompany.current;
    final user = (c?.shownUsername ?? '').trim();
    final company = (c?.shortLabel ?? '').trim();
    return (
      user.isNotEmpty ? user : (_opts?.sasUsername ?? '').trim(),
      company.isNotEmpty && company != '—'
          ? company
          : (_opts?.companyName ?? '').trim(),
    );
  }

  /// «صفحتك ali في سوبرنت» — أيّ صفحةٍ يُشحن رصيدها، قبل أن يدفع.
  String _whereText() {
    final (user, company) = _page();
    final page = user.isEmpty ? 'صفحتك' : 'صفحتك ${iso(user)}';
    return company.isEmpty ? page : '$page في ${iso(company)}';
  }

  String? _pageLine() {
    final (user, company) = _page();
    final line = isoJoin([user, company], ' · ');
    return line.isEmpty ? null : line;
  }

  Future<void> _submit() async {
    final m = _method;
    if (m == null || _busy || _invalid != null) return;
    FocusScope.of(context).unfocus();
    final amount = m.needsAmount ? _effectiveAmount : null;
    final cur = _currency();
    final where = _whereText();
    final ok = await showConfirmSheet(
      context,
      title: switch (m.flow) {
        SelfDepositFlow.pin => 'تعبئة بالكارت',
        SelfDepositFlow.invoice => 'إنشاء فاتورة تسديد',
        _ => 'تأكيد الشحن',
      },
      subtitle: m.label,
      icon: topupMethodIcon(m),
      message: switch (m.flow) {
        SelfDepositFlow.pin => 'سيُضاف رصيد الكارت إلى رصيد $where.',
        SelfDepositFlow.invoice =>
          'ستُنشأ فاتورة بـ${formatIQD(amount ?? 0)} $cur لرصيد $where، '
              'وتصل تعليمات التسديد برسالةٍ إلى ${iso(_phone)}.',
        _ => 'سيُضاف ${formatIQD(amount ?? 0)} $cur إلى رصيد $where.\n'
            'تُفتح صفحة ${m.label} داخل التطبيق لتدفع من محفظتك.',
      },
      confirmLabel: switch (m.flow) {
        SelfDepositFlow.pin => 'تعبئة',
        SelfDepositFlow.invoice => 'إنشاء الفاتورة',
        _ => 'متابعة للدفع',
      },
      cancelLabel: 'إلغاء',
    );
    if (ok != true || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _shown = null;
    });
    final start = await SelfDepositApi.request(
      method: m,
      amount: amount,
      pin: m.needsPin ? _pin : null,
      name: m.needsPayer ? _nameCtrl.text.trim() : null,
      phone: m.needsPayer ? _phone : null,
    );
    if (!mounted) return;
    if (start.isRedirect) {
      try {
        await _runRedirect(m, start, amount);
      } finally {
        if (mounted && _busy) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _busy = false);
    final o = start.outcome;
    if (o != null) {
      if (m.needsPin && o.status != SelfDepositStatus.unverified) {
        _pinCtrl.clear(); // رمزٌ استُعمل أو رُفض — لا يبقى ظاهراً
      }
      _show(_Shown(o, flow: m.flow, amount: amount));
      return;
    }
    showSheetSnack(context, start.message ?? 'تعذّر بدء العمليّة',
        isError: true);
    // أُطفئت الميزة أو تغيّرت وسائل الشركة منذ فُتحت الشاشة ⇒ تُقرأ من جديد.
    if (start.code == 'FEATURE_OFF' || start.code == 'METHOD_UNKNOWN') {
      unawaited(_load(reconcile: false));
    }
  }

  /// زين كاش: يُحفظ قيد العمليّة، تُفتح الصفحة، ويُسلَّم الرجوع للخادم.
  Future<void> _runRedirect(
      SelfDepositMethod m, SelfDepositStart start, int? amount) async {
    final psid = start.psid!;
    String? adminId;
    try {
      adminId = await AuthStorage.readAdminId();
    } catch (_) {}
    if (adminId != null && adminId.isNotEmpty) {
      await SelfDepositPendingStore.put(SelfDepositPending(
        psid: psid,
        adminId: adminId,
        createdAt: DateTime.now(),
        amount: amount,
        methodLabel: m.label,
      ));
    }
    if (!mounted) return;
    final res = await Navigator.of(context).push<PayPageResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TopupPayPage(
          payUrl: start.payUrl!,
          policy: PayNavPolicy(capture: start.capture!, payUrl: start.payUrl!),
          methodLabel: m.label,
          // يُكتب قبل أن تُغلق الصفحة — التوكن لا يضيع إن انقطع ما بعده
          // (ويُنشأ القيد إن فشلت كتابته عند البدء، بمعرّفٍ يُقرأ من جديد).
          onCaptured: (url) async {
            var id = adminId;
            if (id == null || id.isEmpty) {
              try {
                id = await AuthStorage.readAdminId();
              } catch (_) {}
            }
            await SelfDepositPendingStore.attachReturnUrl(psid, url,
                adminId: id, amount: amount, methodLabel: m.label);
          },
        ),
      ),
    );
    if (!mounted) return;
    final ret = res?.returnUrl;
    final SelfDepositOutcome o;
    if (ret != null) {
      o = await _deliver(psid, ret);
    } else {
      o = await SelfDepositApi.status(psid);
      if (o.settled) await SelfDepositPendingStore.remove(psid);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _show(_Shown(o,
        flow: SelfDepositFlow.redirect, amount: amount, closedEarly: ret == null));
  }

  /// يسلّم رابط الرجوع — ويعيد عند انقطاع الشبكة (الخادم يمنع التكرار). يُمحى
  /// القيد حين يقول الخادم إنّه استلمه أو حسمه؛ وما بقي بلا اتّصال تتولّاه
  /// [SelfDepositSync] بإعادةٍ متباعدة وعند العودة للواجهة.
  Future<SelfDepositOutcome> _deliver(String psid, String returnUrl) async {
    const waits = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)];
    late SelfDepositOutcome o;
    for (final w in waits) {
      if (w > Duration.zero) await Future<void>.delayed(w);
      o = await SelfDepositApi.complete(psid: psid, returnUrl: returnUrl);
      if (!o.offline) break;
    }
    if (o.settled) {
      await SelfDepositPendingStore.remove(psid);
    } else if (o.offline) {
      SelfDepositSync.retrySoon();
    }
    return o;
  }

  /// «تحقّق الآن» — الرجوع المحفوظ يُعاد إرساله، وإلّا يُسأل عن الحال.
  Future<void> _check() async {
    final s = _shown;
    final psid = s?.outcome.psid;
    if (s == null || psid == null || _checking) return;
    setState(() => _checking = true);
    String? adminId;
    try {
      adminId = await AuthStorage.readAdminId();
    } catch (_) {}
    final stored = (await SelfDepositPendingStore.forAdmin(adminId))
        .where((p) => p.psid == psid)
        .firstOrNull;
    final ret = stored?.returnUrl;
    final o = ret != null
        ? await _deliver(psid, ret)
        : await SelfDepositApi.status(psid);
    if (ret == null && o.settled) await SelfDepositPendingStore.remove(psid);
    if (!mounted) return;
    setState(() => _checking = false);
    _show(_Shown(o,
        flow: s.flow,
        amount: s.amount,
        closedEarly: s.closedEarly,
        previous: s.previous));
  }

  void _show(_Shown s) {
    setState(() => _shown = s);
    if (!s.previous) unawaited(_loadHistory());
    final o = s.outcome;
    if (o.status == SelfDepositStatus.success && !o.offline) {
      HapticFeedback.mediumImpact();
      if (o.balance != null) {
        setState(() => _opts = _opts?.withBalance(o.balance));
        SelfDepositState.noteBalance(o.balance);
      } else {
        unawaited(_load(reconcile: false));
      }
      // واللوحة تقرأ الرصيد من جديد حين يعود إليها المدير (دخول التبويب ⇒
      // تحديثٌ صامت) — بلا إعادة جلب قائمة المشتركين كلّها لرقمٍ واحد.
      if (s.flow == SelfDepositFlow.redirect) {
        _amountCtrl.clear();
        _amount = 0;
      }
    }
  }

  /// «تحقّق» على عمليّةٍ من السجلّ — برجوعها المحفوظ إن كان على الهاتف.
  Future<void> _checkRecord(SelfDepositRecord rec) async {
    if (_checkingPsid != null) return;
    setState(() => _checkingPsid = rec.psid);
    String? adminId;
    try {
      adminId = await AuthStorage.readAdminId();
    } catch (_) {}
    final stored = (await SelfDepositPendingStore.forAdmin(adminId))
        .where((p) => p.psid == rec.psid)
        .firstOrNull;
    final ret = stored?.returnUrl;
    final o = ret != null
        ? await _deliver(rec.psid, ret)
        : await SelfDepositApi.status(rec.psid);
    if (ret == null && o.settled) await SelfDepositPendingStore.remove(rec.psid);
    if (!mounted) return;
    setState(() => _checkingPsid = null);
    _show(_Shown(o, flow: rec.flow, amount: rec.outcome.amount?.round()));
  }

  Future<void> _openPanel(SelfDepositMethod m) async {
    final url = Uri.tryParse(_opts?.panelUrl ?? '');
    if (url == null || !(url.scheme == 'https' || url.scheme == 'http')) {
      showSheetSnack(context, '${m.label} تُستعمل من لوحة الشركة على المتصفّح');
      return;
    }
    final ok = await showConfirmSheet(
      context,
      title: 'من لوحة الشركة',
      subtitle: m.label,
      icon: LucideIcons.externalLink,
      message: '${m.label} تعمل من لوحة الشركة على المتصفّح وحده. ادخل '
          'بحساب صفحتك هناك ثمّ افتح «ايداع مالي».',
      confirmLabel: 'افتح لوحة الشركة',
      cancelLabel: 'إلغاء',
    );
    if (ok != true) return;
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened && mounted) {
      showSheetSnack(context, 'تعذّر فتح المتصفّح', isError: true);
    }
  }

  Future<void> _pastePin() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return;
    _pinCtrl.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  // ═══════════════ الرسم ═══════════════

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('شحن رصيد الصفحة',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 16)),
              Text('ايداع مالي في صفحتك بالساس',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brandAccent,
          onRefresh: () => _load(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Inset.route(context)),
            children: _children(),
          ),
        ),
      ),
    );
  }

  List<Widget> _children() {
    final o = _opts;
    if (o == null) {
      if (_loading) return const [_LoadingBody()];
      return [
        TopupStateCard(
          icon: LucideIcons.circleAlert,
          title: 'تعذّر التحميل',
          text: _loadError ?? 'تعذّر جلب وسائل الدفع',
          action: TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ),
      ];
    }
    final blocked = _blockedCard(o);
    final shown = _shown;
    // الرصيد لصاحب صفحة ساسٍ يُشحن رصيدها (ولو بلا صلاحيّةٍ أو وسائل بعد) —
    // لا للموظّف ولا لايرث لنك: لا رقم لهما هنا، و«—» يبدو عطلاً.
    final owner = o.block == SelfDepositBlock.none ||
        o.block == SelfDepositBlock.noPermission ||
        o.block == SelfDepositBlock.noGateways;
    return [
      if (owner) ...[
        TopupBalanceCard(
          balance: o.balance,
          loading: _loading,
          currency: o.currencyLabel,
          pageLine: _pageLine(),
          onRefresh: _load,
        ),
        const SizedBox(height: Sp.lg),
      ],
      if (shown != null) ...[
        _resultCard(shown, o.currencyLabel),
        const SizedBox(height: Sp.lg),
      ],
      if (blocked != null)
        blocked
      else if (o.supported == null && o.methods.isEmpty)
        TopupStateCard(
          icon: LucideIcons.circleAlert,
          title: 'تعذّر قراءة وسائل الدفع',
          text: 'الساس لم يردّ على قائمة وسائل الدفع — أعد المحاولة بعد قليل.',
          action:
              TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        )
      else ...[
        _methodsSection(o),
        if (_method != null) ...[
          const SizedBox(height: Sp.lg),
          _formSection(_method!, o),
        ],
      ],
      if (_history.visible) ...[
        const SizedBox(height: Sp.lg),
        _historySection(o.currencyLabel),
      ],
    ];
  }

  Widget _historySection(String currency) {
    return TopupSection(
      title: 'آخر العمليّات',
      children: [
        PagedHistoryList<SelfDepositRecord>(
          history: _history,
          divided: true,
          rowBuilder: (r) => TopupHistoryRow(
            record: r,
            currency: currency,
            busy: _checkingPsid == r.psid,
            onCheck: r.outcome.checkable ? () => _checkRecord(r) : null,
          ),
        ),
      ],
    );
  }

  Widget _resultCard(_Shown s, String currency) {
    final v = describeTopupOutcome(
      s.outcome,
      flow: s.flow,
      amount: s.amount,
      currency: currency,
      closedEarly: s.closedEarly,
    );
    final title = !s.previous
        ? v.title
        : s.outcome.status == SelfDepositStatus.success
            ? 'أُضيف رصيد دفعتك السابقة'
            : 'دفعتك السابقة: ${v.title}';
    final view = TopupResultView(
      tone: v.tone,
      icon: v.icon,
      title: title,
      body: v.body,
      balanceLine: v.balanceLine,
      refLine: v.refLine,
      checkable: v.checkable,
    );
    return TopupNoticeCard(
      view: view,
      actionLabel: v.checkable && s.outcome.psid != null ? 'تحقّق الآن' : null,
      onAction: _check,
      busy: _checking,
      onDismiss: v.checkable ? null : () => setState(() => _shown = null),
    );
  }

  /// ما يمنع الشحن، بسببه — لا نموذج ولا طلب لمقفل.
  Widget? _blockedCard(SelfDepositOptions o) {
    switch (o.block) {
      case SelfDepositBlock.none:
        return null;
      case SelfDepositBlock.disabled:
        return const TopupStateCard(
          locked: true,
          icon: LucideIcons.lock,
          title: 'الشحن غير مفعّل لحسابك',
          text: 'هذه الميزة لم تُفتح لحسابك بعد.',
        );
      case SelfDepositBlock.ownerOnly:
        return const TopupStateCard(
          locked: true,
          icon: LucideIcons.lock,
          title: 'لصاحب الحساب وحده',
          text: 'شحن رصيد الصفحة يقوم به صاحب الحساب — لا يُمنح للموظّفين.',
        );
      case SelfDepositBlock.provider:
        return TopupStateCard(
          locked: true,
          icon: LucideIcons.lock,
          title: topupProviderUnavailable(),
          text: ProviderService.isEarthlink
              ? 'ايرث لنك لا توفّر شحن الرصيد بزين كاش أو بالكارت من التطبيق.'
              : 'شركتك لا توفّر شحن الرصيد من التطبيق.',
        );
      case SelfDepositBlock.noPermission:
        return const TopupStateCard(
          locked: true,
          icon: LucideIcons.lock,
          title: 'صفحتك بلا صلاحيّة «ايداع مالي»',
          text: 'صلاحيّة الإيداع المالي غير مفعّلة لصفحتك في الساس — '
              'اطلبها من مديرك.',
        );
      case SelfDepositBlock.noGateways:
        return const TopupStateCard(
          locked: true,
          icon: LucideIcons.walletCards,
          title: 'لا توجد وسائل دفعٍ إلكترونيّ',
          text: 'شركتك لم تفعّل زين كاش ولا كارتات التعبئة في الساس بعد — '
              'حين تفعّلها تظهر هنا.',
        );
      case SelfDepositBlock.paused:
        return TopupStateCard(
          icon: LucideIcons.clock,
          title: 'الشحن متوقّفٌ مؤقّتاً',
          text: (o.message ?? '').trim().isNotEmpty
              ? o.message!.trim()
              : 'لا عمليّات شحنٍ جديدة الآن — عمليّاتك التي لم تُحسم تُتابَع هنا.',
        );
    }
  }

  Widget _methodsSection(SelfDepositOptions o) {
    final methods = o.methods;
    // وسيلتان بالاسم نفسه (zaincash وzaincashv2 مثلاً) ⇒ اسم الشركة يفرّقهما.
    final dup = <String, int>{};
    for (final m in methods) {
      dup[m.label] = (dup[m.label] ?? 0) + 1;
    }
    return TopupSection(
      title: 'طريقة الشحن',
      children: [
        for (var i = 0; i < methods.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          TopupMethodTile(
            method: methods[i],
            selected: _method?.id == methods[i].id,
            enabled: !_busy,
            subtitle: (dup[methods[i].label] ?? 0) > 1 && methods[i].name != null
                ? '${methods[i].hint} · ${iso(methods[i].name!)}'
                : null,
            onTap: () {
              final m = methods[i];
              if (!m.inApp) {
                _openPanel(m);
                return;
              }
              HapticFeedback.selectionClick();
              setState(() => _method = m);
            },
          ),
        ],
      ],
    );
  }

  Widget _formSection(SelfDepositMethod m, SelfDepositOptions o) {
    final cur = o.currencyLabel;
    final invalid = _invalid;
    return TopupSection(
      title: switch (m.flow) {
        SelfDepositFlow.pin => 'رمز الكارت',
        SelfDepositFlow.invoice => 'بيانات الفاتورة',
        _ => 'المبلغ',
      },
      children: [
        if (m.needsAmount) ...[
          SheetBox(
            focused: false,
            child: AmountTextField(
              controller: _amountCtrl,
              enabled: !_busy,
              currency: cur,
              onValue: (v) => setState(() => _amount = v),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final q in TopupScreen.quickAmounts)
                if ((m.minAmount == null || q >= m.minAmount!) &&
                    (m.maxAmount == null || q <= m.maxAmount!))
                  SheetQuickChip(
                    label: formatIQD(q),
                    selected: _effectiveAmount == q,
                    enabled: !_busy,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final t = AmountShorthand.format(q);
                      _amountCtrl.value = TextEditingValue(
                        text: t,
                        selection: TextSelection.collapsed(offset: t.length),
                      );
                      setState(() => _amount = q);
                    },
                  ),
            ],
          ),
          if (m.minAmount != null || m.maxAmount != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              [
                if (m.minAmount != null)
                  'أقلّ مبلغ ${formatIQD(m.minAmount!)} $cur',
                if (m.maxAmount != null)
                  'أكثر مبلغ ${formatIQD(m.maxAmount!)} $cur',
              ].join(' · '),
              style: AppType.muted(color: AppColors.textMid),
            ),
          ],
        ],
        if (m.needsPin) ...[
          SheetBox(
            icon: LucideIcons.keyRound,
            padding: const EdgeInsetsDirectional.fromSTEB(15, 4, 4, 4)
                .resolve(Directionality.of(context)),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pinCtrl,
                    enabled: !_busy,
                    obscureText: _pinHidden,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Za-z\- ]')),
                      LengthLimitingTextInputFormatter(40),
                    ],
                    style: _pinHidden
                        ? AppType.password()
                        : AppType.input().copyWith(letterSpacing: 1),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'الرمز السرّيّ (PIN)',
                      // بلا تباعد نقاط الإخفاء: التلميح يرث نمط الحقل.
                      hintStyle: AppType.input(color: AppColors.textPlaceholder)
                          .copyWith(letterSpacing: 0),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _pastePin,
                  tooltip: 'لصق',
                  icon: Icon(LucideIcons.clipboardPaste,
                      size: 18, color: AppColors.textMid),
                ),
                IconButton(
                  onPressed: () => setState(() => _pinHidden = !_pinHidden),
                  tooltip: _pinHidden ? 'إظهار' : 'إخفاء',
                  icon: Icon(_pinHidden ? LucideIcons.eye : LucideIcons.eyeOff,
                      size: 18, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text(
            m.internalName == 'kushok'
                ? 'يُضاف رصيد كارت كوشك كاملاً إلى صفحتك.'
                : 'اكشط الكارت واكتب الرمز السرّيّ — يُضاف رصيده كاملاً إلى صفحتك.',
            style: AppType.muted(color: AppColors.textMid),
          ),
        ],
        if (m.needsPayer) ...[
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'اسم الدافع',
            child: SheetBox(
              icon: LucideIcons.user,
              child: TextField(
                controller: _nameCtrl,
                enabled: !_busy,
                textInputAction: TextInputAction.next,
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'الاسم كما يُكتب في الفاتورة',
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'رقم الهاتف',
            footnote: 'تصله تعليمات التسديد برسالةٍ نصّيّة',
            child: SheetBox(
              icon: LucideIcons.phone,
              child: TextField(
                controller: _phoneCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ٠-٩]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '07xxxxxxxxx',
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: Sp.lg),
        _SubmitButton(
          label: switch (m.flow) {
            SelfDepositFlow.pin => 'تعبئة',
            SelfDepositFlow.invoice => 'إنشاء فاتورة',
            _ => 'ادفع ب${m.label}',
          },
          icon: topupMethodIcon(m),
          busy: _busy,
          onTap: invalid == null && !_busy ? _submit : null,
        ),
        if (invalid != null && _touched(m)) ...[
          const SizedBox(height: Sp.sm),
          Text(invalid,
              textAlign: TextAlign.center,
              style: AppType.muted(color: AppColors.textMid)),
        ],
      ],
    );
  }

  /// يُقال سبب التعطيل بعد أن يبدأ الكتابة — لا يُستقبَل بتحذير.
  bool _touched(SelfDepositMethod m) =>
      (m.needsAmount && _amountCtrl.text.isNotEmpty) ||
      (m.needsPin && _pinCtrl.text.isNotEmpty) ||
      (m.needsPayer &&
          (_nameCtrl.text.isNotEmpty || _phoneCtrl.text.isNotEmpty));
}

/// «غير متاح لدى ايرث لنك» — سبب القفل باسم المزوّد.
String topupProviderUnavailable() {
  if (ProviderService.isEarthlink) return 'غير متاح لدى ايرث لنك';
  if (ProviderService.isFtth) return 'غير متاح لدى المشروع الوطنيّ';
  // محفظة فايبر اكس (زين كاش / كي كارد) تُشحن من موقع الويب حالياً.
  if (ProviderService.isFiberx) return 'محفظة فايبر اكس تُشحن من الموقع حالياً';
  return 'غير متاح لشركتك';
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final live = onTap != null && !busy;
    final fg = live ? AppColors.onBrand : AppColors.textHint;
    return SizedBox(
      height: H.button,
      child: Material(
        color: live || busy ? AppColors.brand : AppColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(R.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.onBrand),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: fg),
                      const SizedBox(width: Sp.sm),
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.button(color: fg)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TopupBalanceCard(
            balance: null, loading: true, currency: 'د.ع'),
        const SizedBox(height: Sp.lg),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: AppColors.border),
          ),
        ),
      ],
    );
  }
}

/// سبب قفل بطاقة «قوائم أخرى» — `null` = مفتوحة.
String? topupCardLock(SelfDepositOptions o) => switch (o.block) {
      SelfDepositBlock.none => null,
      SelfDepositBlock.disabled => 'الشحن غير مفعّل لحسابك',
      SelfDepositBlock.ownerOnly => 'شحن الرصيد لصاحب الحساب وحده',
      SelfDepositBlock.provider => topupProviderUnavailable(),
      SelfDepositBlock.noPermission =>
        'صفحتك بلا صلاحيّة «ايداع مالي» في الساس — اطلبها من مديرك',
      SelfDepositBlock.noGateways =>
        'شركتك لم تفعّل الدفع الإلكترونيّ في الساس بعد',
      // متوقّفٌ مؤقّتاً: البطاقة مفتوحة — سجلّ العمليّات و«تحقّق» داخلها.
      SelfDepositBlock.paused => null,
    };
