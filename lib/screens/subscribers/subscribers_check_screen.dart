import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/util/bidi.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../models/merged_company.dart';
import '../../models/subscriber.dart';
import '../../services/connection_alerts.dart';
import '../../services/merged_mode.dart';
import '../../services/subscribers_check.dart';
import '../../services/agent_net_presence.dart';
import '../../services/vpn_now.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/company_tag.dart';
import 'subscriber_detail_screen.dart';
import 'widgets/subs_metric_strip.dart';
import 'widgets/device_chip_micro.dart';
import '../../services/merged_text.dart';

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» و«تره فحص المشتركين ثكيل كلش… مو مثل مايعرضون الاشارات وسرعته بكارت
/// المشتركين»، ثمّ مع صورة الصفحة: «يحتاجلها ترتيب اكثر واظهار معلومات ال ccq كذلك وتصميم افضل»): تقريرٌ فوريّ من قراءات
/// الكارتات نفسها، والموجة تعيد القديم وحده في الخلفيّة (التقرير يتحدّث معها)؛ عبر الـVPN من فحص الخادم الأخير (يُعاد إن قدُم).
///
/// الترتيب: بطاقة ملخّص — شريط الفحص نفسه (١٠ نوفمبر — المالك: «شنو علاقة العداد بالعدد مفروض العداد يمثل الفحص»): جارٍ
/// «يفحص… 12 من 30» ثمّ «انتهى الفحص — 113 مشترك» بوقته، لا «قُرئ 58 من 113» عالقاً — ثمّ أقسامٌ تُفتح بالضغط: «بمشكلة»
/// (مجموعاتٍ بنوعها، الأسوأ أوّلاً) · «سليم» (الأقرب للحدّ أوّلاً) · «جهازه ما ردّ» (متّصلٌ بلا قراءة، وسببه)، وتحتها حبّاتٌ
/// رماديّة لمن لا يُقرأ أصلاً: «غير متّصل الآن» (ليس عطلاً) · «بلا مقاييس» · «لم يُفحص (بعد)» ([SubsCheckCat]). وكلّ مشتركٍ
/// بمقاييسه كلّها كالكارت: الإشارة وCCQ والكيبل (أو ضوء الفايبر وحرارته) — المشكلة حمراء، والقريب من الحدّ برتقاليّ. المشكلة
/// بحدود «تنبيه المشترك» ([SubscribersCheck]). الضغط على مشترك يفتح نافذته؛ و«نسخ التقرير» بالأقسام نفسها.
class SubscribersCheckScreen extends StatefulWidget {
  const SubscribersCheckScreen({
    super.key,
    required this.subscribers,
    required this.viaVpn,
    this.wave,
    this.onRefreshStale,
    this.onForceAll,
    this.big = false,
    this.companies,
    this.openCompany,
    this.vpnAllowed = true,
  });

  /// «كل الشركات» (٨ نوفمبر — المالك: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn والسوبرنت
  /// تشتغل لوكل»): شركات القائمة بترتيبها — كلٌّ بطريقها كـ«الفحص الشامل»: المفتوحة [openCompany] من شبكتك (ما لم يكن [viaVpn])،
  /// وغيرها بفحص الخادم عبر VPN شركتها، وبلا طريقٍ تُسمّى. null خارج الوضع.
  final List<MergedCompany>? companies;
  final String? openCompany;

  /// الفحص عبر VPN مفعّلٌ للموظّف (صاحب الحساب دائماً).
  final bool vpnAllowed;

  /// القائمة الحيّة (المحمّلة) من شاشة المشتركين.
  final List<Subscriber> Function() subscribers;
  final bool viaVpn;

  /// موجة الهاتف (على الشبكة): جاريةٌ أم انتهت، وكم فُحص من كم، ومن تشمل — شريط الفحص يعدّها هي.
  final ValueListenable<SubsWave>? wave;

  /// على الشبكة: الموجة للقديم وحده (خفيفة) — تُنادى عند الفتح وبـ«تحديث».
  final VoidCallback? onRefreshStale;

  /// على الشبكة: إعادة فحص الكلّ (ثقيلة، بطلبٍ صريح).
  final VoidCallback? onForceAll;

  /// حسابٌ كبير: الصفوف المحمّلة وحدها.
  final bool big;

  @override
  State<SubscribersCheckScreen> createState() => _SubscribersCheckScreenState();
}

/// رأس مجموعةٍ في قسم «بمشكلة».
class _Group {
  const _Group(this.kind, this.count);
  final ConnectionProblemKind kind;
  final int count;
}

class _SubscribersCheckScreenState extends State<SubscribersCheckScreen> {
  SubsCheckCat _seg = SubsCheckCat.problems;
  ConnectionProblemKind? _kind;

  /// «منذ دقيقتين» يبقى صادقاً والشاشة مفتوحة.
  Timer? _clock;

  /// «كل الشركات»: شركةٌ مختارة من بطاقة «الشركات» ⇒ مشتركوها وحدهم (والضغط ثانيةً يعيد الكلّ).
  String? _company;

  bool get _merged => (widget.companies ?? const []).isNotEmpty;

  /// الشركة المفتوحة تُقرأ من شبكتك (الموجة) ما لم يكن الفحص عبر الـVPN.
  bool _isLocal(String key) => !widget.viaVpn && key == widget.openCompany;

  /// شركاتٌ تُفحص عبر VPN شركتها (بطلبٍ موجَّه بمفتاحها) — وآخرها المفتوحة نفسها تكملةً لموجة الهاتف: مشتركو الفايبر (ONU بلا
  /// عنوانٍ يصله الموبايل) ضوؤهم من الأولت يقرؤه الخادم عبر نفق الشركة (صورة المالك ٨ نوفمبر: «قُرئ 0 من 80» وأولته «ONU 80/101»).
  /// فشل تكملتها لا يُسمّى (طريقها شبكتك).
  List<VpnMergedCompany> get _vpnCompanies {
    final cs = widget.companies ?? const <MergedCompany>[];
    return [
      for (final c in cs)
        if (!_isLocal(c.key)) (key: c.key, name: c.name),
      for (final c in cs)
        if (_isLocal(c.key)) (key: c.key, name: c.name),
    ];
  }

  /// (النوع، اسم الشريحة، عنوان المجموعة، الأيقونة)
  static const _kinds = [
    (ConnectionProblemKind.cable, 'الكيبل', 'الكيبل مفصول أو 10 ميكا', LucideIcons.cable),
    (ConnectionProblemKind.signal, 'الإشارة', 'إشارة ضعيفة', LucideIcons.signal),
    (ConnectionProblemKind.ccq, 'CCQ', 'CCQ منخفض', LucideIcons.activity),
    (ConnectionProblemKind.fiberRx, 'ضوء الفايبر', 'ضوء الفايبر ضعيف', LucideIcons.sun),
    (ConnectionProblemKind.fiberTemp, 'حرارة الفايبر', 'حرارة الفايبر عالية', LucideIcons.thermometer),
  ];

  static ({ConnectionProblemKind kind, String chip, String group, IconData icon}) _kindOf(ConnectionProblemKind k) {
    final x = _kinds.firstWhere((e) => e.$1 == k);
    return (kind: x.$1, chip: x.$2, group: x.$3, icon: x.$4);
  }

  @override
  void initState() {
    super.initState();
    DeviceProbeBus.tick.addListener(_changed);
    VpnNow.subscribers.addListener(_changed);
    ConnectionAlertSettings.current.addListener(_changed);
    widget.wave?.addListener(_changed);
    ConnectionAlertSettings.ensureLoaded();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(initial: true));
  }

  @override
  void dispose() {
    DeviceProbeBus.tick.removeListener(_changed);
    VpnNow.subscribers.removeListener(_changed);
    ConnectionAlertSettings.current.removeListener(_changed);
    widget.wave?.removeListener(_changed);
    _clock?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// الفتح والتحديث: على الشبكة الموجة للقديم وحده؛ عبر الـVPN فحص الخادم إن قدُمت قراءته (أو بالتحديث صراحةً).
  /// «كل الشركات»: الموجة للمفتوحة، وفحص الخادم لغيرها — عند الفتح لمن قدُمت قراءاته (١٠ د) أو لم تُفحص، وبالتحديث للكلّ.
  void _refresh({bool initial = false}) {
    if (_merged) {
      if (!widget.viaVpn && widget.openCompany != null) widget.onRefreshStale?.call();
      if (!widget.vpnAllowed || VpnNow.subscribers.busy) return;
      final now = DateTime.now();
      final todo = [
        for (final c in _vpnCompanies)
          if (!initial ||
              VpnNow.readingsAtFor(c.key) == null ||
              now.difference(VpnNow.readingsAtFor(c.key)!) > const Duration(minutes: 10))
            c,
      ];
      if (todo.isNotEmpty) VpnNow.subscribers.run(only: todo);
      return;
    }
    if (!widget.viaVpn) {
      widget.onRefreshStale?.call();
      return;
    }
    if (VpnNow.subscribers.busy) return;
    final at = VpnNow.readingsAtFor(null);
    if (!initial || at == null || DateTime.now().difference(at) > const Duration(minutes: 10)) {
      VpnNow.subscribers.run();
    }
  }

  ConnectionAlertThresholds _limits(String? company) =>
      (company == null ? null : VpnNow.limitsOf(company)) ?? ConnectionAlertSettings.current.value;

  /// موجة الهاتف جزءٌ من هذا الفحص (على الشبكة، أو المفتوحة في «كل الشركات») — وعبر الـVPN وحده لا.
  SubsWave? get _wave => widget.viaVpn ? null : widget.wave?.value;

  bool get _waveRunning => _wave?.running ?? false;

  bool get _busy => _merged
      ? (_waveRunning || VpnNow.subscribers.busy)
      : (widget.viaVpn ? VpnNow.subscribers.busy : _waveRunning);

  SubsCheckReport _report(List<Subscriber> subs) {
    if (_merged) {
      // فشل الهاتف «ما ردّ من شبكتك» لشركةٍ تُقرأ من شبكتك وهو عليها وحده — غيرها طريقه VPN شركتها (١٠ نوفمبر)
      final onNet = !VpnNow.mode.value && !AgentNetPresence.isOff;
      return SubscribersCheck.mixed(subs, _limits,
          companyNote: _companyNote, wave: _wave, localFailsFor: (c) => onNet && c != null && _isLocal(c));
    }
    return widget.viaVpn ? SubscribersCheck.vpn(subs, _limits) : SubscribersCheck.local(subs, _limits, wave: _wave);
  }

  /// شريط الفحص: موجة الهاتف أو فحص الخادم أو الاثنان («كل الشركات») — كلٌّ وانتهاؤه بوقته.
  SubsCheckProgress _progress(SubsCheckReport r) {
    final job = VpnNow.subscribers;
    if (_merged) {
      final cur = job.current;
      final name = cur == null ? null : widget.companies!.where((c) => c.key == cur).firstOrNull?.name;
      DateTime? at = _wave?.endedAt;
      for (final c in _vpnCompanies) {
        final t = VpnNow.readingsAtFor(c.key);
        if (t != null && (at == null || t.isAfter(at))) at = t;
      }
      return SubscribersCheck.progress(
        subs: r.total,
        wave: _wave,
        vpn: widget.vpnAllowed ? SubscribersCheck.vpnRunOf(job) : null,
        merged: true,
        vpnCompany: name,
        at: at ?? r.newest,
      );
    }
    if (widget.viaVpn) {
      return SubscribersCheck.progress(subs: r.total, vpn: SubscribersCheck.vpnRunOf(job), at: VpnNow.readingsAt);
    }
    return SubscribersCheck.progress(subs: r.total, wave: _wave ?? SubsWave.idle, at: _wave?.endedAt ?? r.newest);
  }

  String get _source => _merged
      ? mergedWord('كل الشركات — كلّ شركةٍ بطريقها', 'كل الصفحات — كلّ صفحةٍ بطريقها')
      : (widget.viaVpn ? 'عبر VPN' : 'من موبايلك على الشبكة');

  Future<void> _copy(SubsCheckReport r, SubsCheckProgress p) async {
    final names = {for (final c in widget.companies ?? const <MergedCompany>[]) c.key: c.name};
    final all = MergedMode.active.value && MergedMode.focused == null;
    await copyToClipboard(
      context,
      SubscribersCheck.reportText(r,
          progress: p,
          source: _source,
          companyOf: all && names.isNotEmpty ? (s) => s.companyKey == null ? null : names[s.companyKey!] : null),
      label: 'تقرير الفحص',
    );
  }

  /// سبب شركةٍ لم تُفحص عبر الـVPN (لمن لم يُقرأ من مشتركيها) — والموظّف بلا مفتاحه يُقال له.
  String? _companyNote(String? key) {
    if (key == null || _isLocal(key)) return null;
    if (!widget.vpnAllowed) return 'الفحص عبر VPN غير مفعّل لك';
    return VpnNow.noteOf(key);
  }

  void _open(Subscriber s) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ));

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final all = widget.subscribers();
    final full = _merged ? _report(all) : null;
    final subs = _company == null
        ? all
        : [
            for (final x in all)
              if (x.companyKey == _company) x
          ];
    final r = _company == null && full != null ? full : _report(subs);
    final p = _progress(r);
    final mergedAll = MergedMode.active.value && MergedMode.focused == null;
    final items = _items(r);
    final caption = _captionOf(_seg);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('الفحص العامّ للمشتركين', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          if (!widget.viaVpn && widget.onForceAll != null)
            IconButton(
              key: const ValueKey('subs-check-force'),
              tooltip: 'إعادة فحص الكلّ (أبطأ)',
              onPressed: _busy ? null : widget.onForceAll,
              icon: Icon(LucideIcons.radar, size: 20, color: AppColors.textMid),
            ),
          IconButton(
            key: const ValueKey('subs-check-refresh'),
            tooltip: 'تحديث',
            onPressed: _busy ? null : () => _refresh(),
            icon: _busy
                ? SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                : Icon(LucideIcons.refreshCw, size: 19, color: AppColors.textMid),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _summary(r, p),
                const SizedBox(height: Sp.md),
                if (_merged && full != null) ...[
                  _companiesCard(all, full),
                  const SizedBox(height: Sp.md),
                ],
                if (_seg == SubsCheckCat.problems && r.rows.isNotEmpty) ...[
                  _kindChips(r),
                  const SizedBox(height: Sp.xs),
                ],
                if (caption != null && items.isNotEmpty) _caption(caption.$1, caption.$2),
              ]),
            ),
          ),
          if (items.isEmpty)
            SliverToBoxAdapter(child: _empty(r))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((_, i) => _item(items[i], mergedAll), childCount: items.length),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.huge),
            sliver: SliverToBoxAdapter(child: _footer(mergedAll)),
          ),
        ],
      ),
    );
  }

  /// سطرٌ فوق القائمة يقول ما القسم ولماذا.
  (IconData, String)? _captionOf(SubsCheckCat c) => switch (c) {
        SubsCheckCat.problems => null,
        SubsCheckCat.healthy => (LucideIcons.arrowDownWideNarrow, 'الأقرب إلى حدّ المشكلة أوّلاً'),
        SubsCheckCat.noReply => (LucideIcons.info, 'متّصلون وأجهزتهم ما ردّت — السبب بجانب كلّ مشترك'),
        SubsCheckCat.offline => (LucideIcons.info, 'غير متّصلين الآن — ليس عطلاً بأجهزتهم'),
        SubsCheckCat.noMetrics => (LucideIcons.info, 'أجهزتهم تردّ بلا مقاييس — ليست نانو ولا وحدةً ضوئيّة'),
        SubsCheckCat.unchecked => (
            _busy ? LucideIcons.hourglass : LucideIcons.info,
            _busy ? 'لم يبلغهم الفحص بعد — يكمل الآن' : 'لم يصلهم الفحص — السبب بجانب كلّ مشترك'
          ),
      };

  /// صفوف القسم المفتوح: «بمشكلة» مجموعاتٍ بأسوأ نوع (أو نوعٌ واحد بالشريحة)، «سليم»، أو من لم يُقرأ في قسمه.
  List<Object> _items(SubsCheckReport r) {
    switch (_seg) {
      case SubsCheckCat.problems:
        if (_kind != null) return r.of(_kind!);
        final counts = <ConnectionProblemKind, int>{};
        for (final row in r.rows) {
          counts[row.worst!] = (counts[row.worst!] ?? 0) + 1;
        }
        final out = <Object>[];
        ConnectionProblemKind? last;
        for (final row in r.rows) {
          if (row.worst != last) {
            last = row.worst;
            out.add(_Group(last!, counts[last]!));
          }
          out.add(row);
        }
        return out;
      case SubsCheckCat.healthy:
        return r.healthy;
      default:
        return r.missingIn(_seg);
    }
  }

  Widget _item(Object it, bool mergedAll) {
    if (it is _Group) return _groupHeader(it);
    if (it is SubsCheckRow) return _row(it, mergedAll);
    return _missRow(it as SubsMissing, mergedAll);
  }

  // ─────────────────── الملخّص ───────────────────

  /// الأقسام الثانويّة — رماديّة: من لا يُقرأ جهازه أصلاً، وليس عطلاً يُتابَع.
  List<(SubsCheckCat, AppTone, IconData)> get _minor => [
        (SubsCheckCat.offline, AppTone.neutral, LucideIcons.wifiOff),
        (SubsCheckCat.noMetrics, AppTone.neutral, LucideIcons.gauge),
        (
          SubsCheckCat.unchecked,
          _busy ? AppTone.brand : AppTone.neutral,
          _busy ? LucideIcons.hourglass : LucideIcons.circleDashed
        ),
      ];

  Widget _summary(SubsCheckReport r, SubsCheckProgress p) {
    final bad = r.rows.length;
    final none = r.read == 0;
    final tone = none ? AppTone.neutral : (bad == 0 ? AppTone.success : AppTone.danger);
    final title = none ? 'لا قراءات بعد' : (bad == 0 ? 'لا مشاكل' : '${formatIQD(bad)} بمشكلة');
    final minor = [
      for (final (c, t, icon) in _minor)
        if (r.count(c) > 0 || _seg == c) _minorPill(c, r.count(c), t, icon),
    ];
    return Container(
      key: const ValueKey('subs-check-summary'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
            child: Icon(
              none ? LucideIcons.radar : (bad == 0 ? LucideIcons.shieldCheck : LucideIcons.triangleAlert),
              size: 22,
              color: tone.fill,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: AppType.title(color: none ? AppColors.textHi : tone.fill)
                      .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(_source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
            ]),
          ),
          // داخل البطاقة لا بالرأس (المالك ٧ نوفمبر: «ميزةٌ جديدة لا تضيف مربّعاً للرأس»)
          IconButton(
            key: const ValueKey('subs-check-copy'),
            tooltip: 'نسخ التقرير',
            visualDensity: VisualDensity.compact,
            onPressed: r.total == 0 ? null : () => _copy(r, p),
            icon: Icon(LucideIcons.copy, size: 18, color: AppColors.textMid),
          ),
        ]),
        const SizedBox(height: Sp.md),
        _progressRow(p),
        const SizedBox(height: Sp.md),
        Row(children: [
          Expanded(child: _segTile(SubsCheckCat.problems, bad, AppTone.danger, LucideIcons.triangleAlert)),
          const SizedBox(width: Sp.sm),
          Expanded(child: _segTile(SubsCheckCat.healthy, r.healthy.length, AppTone.success, LucideIcons.circleCheck)),
          const SizedBox(width: Sp.sm),
          Expanded(
              child: _segTile(SubsCheckCat.noReply, r.count(SubsCheckCat.noReply), AppTone.warning, LucideIcons.serverOff)),
        ]),
        if (minor.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: minor),
        ],
      ]),
    );
  }

  /// سطر الفحص وشريطه: جارٍ بعدّه ونسبته، ثمّ «انتهى الفحص» ممتلئاً بوقته — لا يبقى نصفاً بعد الانتهاء.
  Widget _progressRow(SubsCheckProgress p) {
    final (AppTone tone, IconData? icon) = switch (p.state) {
      SubsRunState.running => (AppTone.brand, null),
      SubsRunState.finished => (AppTone.success, LucideIcons.circleCheck),
      SubsRunState.failed => (AppTone.warning, LucideIcons.triangleAlert),
      SubsRunState.idle => (AppTone.neutral, LucideIcons.circleDashed),
    };
    final v = p.value;
    final side = p.running ? (v == null ? null : '${(v * 100).round()}%') : (p.at == null ? null : timeAgoAr(p.at));
    final done = p.state == SubsRunState.finished;
    return Column(
      key: const ValueKey('subs-check-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: icon == null
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tone.fill))
                : Icon(icon, size: 15, color: tone.fill),
          ),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(p.text,
                key: const ValueKey('subs-check-progress-text'),
                maxLines: p.state == SubsRunState.failed ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(
                        color: done
                            ? AppColors.textHi
                            : (p.state == SubsRunState.failed ? tone.onSoft : AppColors.textMid))
                    .copyWith(fontSize: 12.5, fontWeight: done ? FontWeight.w700 : FontWeight.w600)),
          ),
          if (side != null) ...[
            const SizedBox(width: Sp.sm),
            Text(side,
                key: const ValueKey('subs-check-progress-side'),
                textDirection: p.running ? TextDirection.ltr : null,
                style: AppType.label(color: p.running ? AppColors.textHi : AppColors.textMid)
                    .copyWith(fontSize: 12.5, fontWeight: p.running ? FontWeight.w700 : FontWeight.w500)),
          ],
        ]),
        if (p.running || done) ...[
          const SizedBox(height: Sp.x6),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              key: const ValueKey('subs-check-progress-bar'),
              value: p.running ? v : 1,
              minHeight: 6,
              backgroundColor: AppColors.surfaceSunken,
              color: done ? AppColors.success : AppColors.brand,
            ),
          ),
        ],
      ],
    );
  }

  void _select(SubsCheckCat c) => setState(() {
        _seg = c;
        _kind = null;
      });

  Widget _segTile(SubsCheckCat seg, int n, AppTone tone, IconData icon) {
    final on = _seg == seg;
    return Material(
      color: on ? tone.softBg : AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        key: ValueKey('subs-check-seg-${seg.name}'),
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => _select(seg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm, horizontal: Sp.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? tone.softBorder : Colors.transparent, width: BW.selected),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatIQD(n),
                style: AppType.title(color: n == 0 ? AppColors.textLow : tone.fill)
                    .copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: on ? tone.fill : AppColors.textLow),
              const SizedBox(width: Sp.xs),
              Flexible(
                child: Text(seg.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(color: on ? AppColors.textHi : AppColors.textMid)
                        .copyWith(fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  /// حبّةٌ رماديّة لقسمٍ ثانويّ — تُضغط كالبلاطة.
  Widget _minorPill(SubsCheckCat c, int n, AppTone tone, IconData icon) {
    final on = _seg == c;
    return Material(
      color: on ? (tone == AppTone.neutral ? AppColors.surface : tone.softBg) : AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        key: ValueKey('subs-check-seg-${c.name}'),
        borderRadius: BorderRadius.circular(R.pill),
        onTap: () => _select(c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md - 2, vertical: Sp.x6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(
              color: on ? (tone == AppTone.neutral ? AppColors.textLow : tone.softBorder) : Colors.transparent,
              width: BW.selected,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: on ? tone.fill : AppColors.textLow),
            const SizedBox(width: Sp.xs),
            Text(c.labelFor(running: _busy),
                style: AppType.label(color: on ? AppColors.textHi : AppColors.textMid)
                    .copyWith(fontSize: 11.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
            const SizedBox(width: Sp.x6),
            Text(formatIQD(n),
                style: AppType.label(color: on ? AppColors.textHi : AppColors.textBody)
                    .copyWith(fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  // ─────────────────── «كل الشركات»: الشركات ───────────────────

  /// سطرٌ لكلّ شركة كـ«الفحص الشامل»: طريقها (من شبكتك / عبر VPN الشركة / لماذا لم تُفحص) وكم قُرئ من متّصلي مشتركيها وكم
  /// بمشكلة — والضغط يعرض مشتركيها وحدهم. ١٠ نوفمبر: غير المتّصل بلا قراءة خارج العدد (لا يُقرأ أصلاً — «قُرئ» لا يكتمل معه).
  Widget _companiesCard(List<Subscriber> all, SubsCheckReport full) {
    final total = <String, int>{};
    for (final x in all) {
      final k = x.companyKey;
      if (k != null) total[k] = (total[k] ?? 0) + 1;
    }
    final offline = <String, int>{};
    for (final m in full.missingIn(SubsCheckCat.offline)) {
      final k = m.sub.companyKey;
      if (k != null) offline[k] = (offline[k] ?? 0) + 1;
    }
    final read = <String, int>{};
    final viaVpn = <String, int>{};
    final bad = <String, int>{};
    for (final row in [...full.healthy, ...full.rows]) {
      final k = row.sub.companyKey;
      if (k == null) continue;
      read[k] = (read[k] ?? 0) + 1;
      if (row.reading?.vpn ?? false) viaVpn[k] = (viaVpn[k] ?? 0) + 1;
    }
    for (final row in full.rows) {
      final k = row.sub.companyKey;
      if (k != null) bad[k] = (bad[k] ?? 0) + 1;
    }
    final shown = [
      for (final c in widget.companies!)
        if ((total[c.key] ?? 0) > 0) c
    ];
    final picked = _company == null ? null : shown.where((c) => c.key == _company).firstOrNull;
    final hint = picked != null
        ? '«${picked.name}» وحدها — اضغطها ثانيةً لعرض الكلّ'
        : (shown.length > 1 ? mergedWord('اضغط شركةً لعرض مشتركيها وحدهم', 'اضغط صفحةً لعرض مشتركيها وحدهم') : null);
    return Container(
      key: const ValueKey('subs-check-companies'),
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in shown)
          _companyRow(c,
              total: total[c.key] ?? 0,
              offline: offline[c.key] ?? 0,
              read: read[c.key] ?? 0,
              viaVpn: viaVpn[c.key] ?? 0,
              bad: bad[c.key] ?? 0),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, 2),
            child: Row(children: [
              Icon(picked != null ? LucideIcons.filter : LucideIcons.mousePointerClick,
                  size: 13, color: AppColors.textLow),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(hint,
                    key: const ValueKey('subs-check-companies-hint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _companyRow(MergedCompany c,
      {required int total, required int offline, required int read, required int viaVpn, required int bad}) {
    final on = _company == c.key;
    final counts = offline <= 0
        ? 'قُرئ ${formatIQD(read)} من ${formatIQD(total)}'
        : total - offline > 0
            ? 'قُرئ ${formatIQD(read)} من ${formatIQD(total - offline)} متّصل'
            : '${formatIQD(offline)} غير متّصل الآن';
    final job = VpnNow.subscribers;
    final local = _isLocal(c.key);
    final note = _companyNote(c.key);
    final at = VpnNow.readingsAtFor(c.key);
    final probing = _waveRunning;
    // المفتوحة: من الهاتف أوّلاً، وما قُرئ عبر VPN شركتها (ضوء الأولت) يُقال
    final localWay = viaVpn == 0 ? 'من شبكتك' : (viaVpn == read ? 'عبر VPN الشركة' : 'من شبكتك وعبر VPN الشركة');
    final (IconData icon, AppTone tone, String text) = local
        ? (probing
            ? (LucideIcons.loader, AppTone.brand, 'يُقرأ من شبكتك… · $counts')
            : job.busy && job.current == c.key
                ? (LucideIcons.loader, AppTone.brand, 'يُكمَّل عبر VPN الشركة… · $counts')
                : (LucideIcons.circleCheck, AppTone.success, '$localWay · $counts'))
        : job.busy && job.current == c.key
            ? (LucideIcons.loader, AppTone.brand, 'يُفحص عبر VPN الشركة… · $counts')
            // ما قبل الحاليّة فُحص في هذا الفحص نفسه — لا «بانتظار دورها»
            : job.waits(c.key)
                ? (LucideIcons.hourglass, AppTone.neutral, 'بانتظار دورها عبر VPN · $counts')
                // شركةٌ غير المفتوحة قُرئ بعض مشتركيها من شبكتك (أجهزتهم يصلها موبايلك) — يُقال ذلك قبل حال الـVPN
                : read > viaVpn && (note != null || at == null)
                    ? (
                        LucideIcons.circleCheck,
                        AppTone.success,
                        '${viaVpn > 0 ? 'من شبكتك وعبر VPN الشركة' : 'من شبكتك'} · $counts'
                            '${note != null ? ' · ${note.contains('تحتاج VPN') ? 'بلا VPN للباقي' : 'تعذّر VPN للباقي'}' : ''}'
                      )
                    : note != null
                        ? (
                            note.contains('تحتاج VPN') ? LucideIcons.shieldOff : LucideIcons.triangleAlert,
                            AppTone.warning,
                            note
                          )
                        : at != null
                            ? (
                                LucideIcons.circleCheck,
                                AppTone.success,
                                '${read > viaVpn ? 'من شبكتك وعبر VPN الشركة' : 'عبر VPN الشركة'} · ${timeAgoAr(at)} · $counts'
                              )
                            : (LucideIcons.circleDashed, AppTone.neutral, 'لم تُفحص بعد عبر VPN · $counts');
    final waiting = tone == AppTone.neutral;
    return Material(
      key: ValueKey('subs-check-company-${c.key}'),
      color: on ? AppTone.brand.softBg : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => setState(() {
          _company = on ? null : c.key;
          _kind = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? AppTone.brand.softBorder : Colors.transparent),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: tone == AppTone.warning ? tone.onSoft : AppColors.textMid)
                        .copyWith(fontSize: 11.5)),
              ]),
            ),
            const SizedBox(width: Sp.x6),
            if (on) ...[
              _pillSmall('معروضة', AppTone.brand),
              const SizedBox(width: Sp.x6),
            ] else if (bad > 0) ...[
              _pillSmall('${formatIQD(bad)} بمشكلة', AppTone.danger),
              const SizedBox(width: Sp.x6),
            ],
            Icon(icon, size: 18, color: waiting ? AppColors.textLow : tone.fill),
          ]),
        ),
      ),
    );
  }

  Widget _pillSmall(String text, AppTone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.softBorder),
        ),
        child: Text(text, style: AppType.label(color: tone.onSoft).copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  // ─────────────────── شرائح الأنواع ───────────────────

  Widget _kindChips(SubsCheckReport r) {
    Widget chip(String label, IconData? icon, int n, bool on, VoidCallback tap, Key key) => Material(
          color: on ? AppTone.danger.softBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.pill),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(R.pill),
            onTap: tap,
            child: Container(
              height: H.chipSm,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: on ? AppTone.danger.softBorder : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: on ? AppTone.danger.fill : AppColors.textMid),
                  const SizedBox(width: Sp.xs),
                ],
                Text(label,
                    style: AppType.label(color: on ? AppTone.danger.onSoft : AppColors.textHi)
                        .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: Sp.x6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 1),
                  decoration: BoxDecoration(
                    color: on ? AppTone.danger.fill : AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(formatIQD(n),
                      style: AppType.label(color: on ? AppColors.onBrand : AppColors.textMid)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        );
    // سطرٌ ثانٍ لا تمريرٌ جانبيّ — كلّ الأنواع ظاهرة
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        chip('الكل', null, r.rows.length, _kind == null, () => setState(() => _kind = null),
            const ValueKey('subs-check-kind-all')),
        for (final (k, label, _, icon) in _kinds)
          if (r.of(k).isNotEmpty)
            chip(label, icon, r.of(k).length, _kind == k, () => setState(() => _kind = k),
                ValueKey('subs-check-kind-${k.name}')),
      ],
    );
  }

  Widget _groupHeader(_Group g) {
    final k = _kindOf(g.kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, Sp.sm, 2, Sp.sm),
      child: Row(children: [
        Icon(k.icon, size: 15, color: AppTone.danger.fill),
        const SizedBox(width: Sp.x6),
        Text(k.group,
            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: Sp.x6),
        Text('(${formatIQD(g.count)})', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
        const SizedBox(width: Sp.sm),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ]),
    );
  }

  Widget _caption(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, Sp.sm),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.textLow),
          const SizedBox(width: Sp.x6),
          Expanded(child: Text(text, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5))),
        ]),
      );

  // ─────────────────── صفّ مشترك ───────────────────

  String _nameOf(Subscriber s) => s.fullName.trim().isEmpty ? s.username : s.fullName.trim();

  Widget _row(SubsCheckRow row, bool mergedAll) {
    final s = row.sub;
    final x = row.reading;
    final bad = {for (final p in row.problems) p.kind};
    final problem = bad.isNotEmpty;
    final meta = <String>[
      iso(s.username),
      if (x?.device != null) iso(x!.device!),
      if (x?.via != null) 'من ${x!.via}',
      if (!widget.viaVpn && x?.at != null) timeAgoAr(x!.at),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('subs-check-row-${s.companyKey ?? ''}|${s.username}'),
          onTap: () => _open(s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: problem ? AppTone.danger.softBorder : AppColors.border),
            ),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(Sp.md + 2, Sp.md, Sp.sm, Sp.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(_nameOf(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(color: AppColors.textHi)
                              .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                    if (mergedAll && s.companyKey != null) ...[
                      const SizedBox(width: Sp.x6),
                      CompanyTag(companyKey: s.companyKey!, fontSize: 11),
                    ],
                    const SizedBox(width: Sp.xs),
                    Icon(LucideIcons.chevronLeft, size: 17, color: AppColors.textLow),
                  ]),
                  const SizedBox(height: 2),
                  Text(meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
                  if (x != null) ...[
                    const SizedBox(height: Sp.sm),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Sp.xs),
                      child: SubsMetricStrip(reading: x, bad: bad, limits: _limits(s.companyKey)),
                    ),
                  ],
                ]),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: problem ? AppTone.danger.fill : AppColors.success),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────── من لم يُقرأ ───────────────────

  /// سببه بجانب اسمه — النصّ من [SubscribersCheck.missText] (هو نفسه في التقرير المنسوخ وجواب الأمر الصوتيّ).
  Widget _missRow(SubsMissing m, bool mergedAll) {
    final s = m.sub;
    final text = SubscribersCheck.missText(m, running: _busy);
    final tone = switch (m.why) {
      SubsMissWhy.dead => AppTone.danger,
      // ٩ نوفمبر: يردّ عبر الـVPN ولم تُقرأ مقاييسه — كان يُعدّ «سليم»
      SubsMissWhy.unmeasured || SubsMissWhy.noReply || SubsMissWhy.company => AppTone.warning,
      // لم يبلغه الفحص الجاري بعد — لا «ما ردّ» (لا أرقام كاذبة)
      SubsMissWhy.unchecked => m.note == null && _busy ? AppTone.brand : AppTone.neutral,
      SubsMissWhy.offline || SubsMissWhy.noMetrics => AppTone.neutral,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('subs-check-miss-${s.companyKey ?? ''}|${s.username}'),
          onTap: () => _open(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_nameOf(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(iso(s.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
                ]),
              ),
              if (mergedAll && s.companyKey != null) ...[
                CompanyTag(companyKey: s.companyKey!, fontSize: 11),
                const SizedBox(width: Sp.x6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.softBg,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(color: tone.softBorder),
                ),
                child: Text(text,
                    style: AppType.label(color: tone.onSoft).copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────── الفراغ والتذييل ───────────────────

  Widget _empty(SubsCheckReport r) {
    if (r.read == 0 && (_seg == SubsCheckCat.problems || _seg == SubsCheckCat.healthy)) {
      if (_busy) {
        return _notice(LucideIcons.radar,
            widget.viaVpn ? 'يفحص الخادم المشتركين عبر الـVPN…' : 'يُقرأ المشتركون الآن من موبايلك…');
      }
      return _notice(
          LucideIcons.info,
          widget.viaVpn
              ? 'لا قراءات عبر الـVPN بعد — اضغط «تحديث» ليفحص الخادم'
              : 'لا قراءات بعد — يُفحص المشتركون الآن من موبايلك');
    }
    return switch (_seg) {
      SubsCheckCat.problems =>
        _notice(LucideIcons.circleCheck, 'لا مشاكل ✓ — كلّ المقروئين ضمن حدود «تنبيه المشترك»', good: true),
      SubsCheckCat.healthy => _notice(LucideIcons.triangleAlert, 'لا أحد سليم — كلّ المقروئين بمشكلة'),
      SubsCheckCat.noReply =>
        _busy ? _notice(LucideIcons.radar, 'لا أحد حتى الآن — الفحص يكمل') : _noReplyEmpty(r),
      SubsCheckCat.offline => _offlineEmpty(r),
      SubsCheckCat.noMetrics => _notice(LucideIcons.circleCheck, 'لا جهاز بلا مقاييس ✓', good: true),
      SubsCheckCat.unchecked => _notice(LucideIcons.circleCheck, 'وصل الفحص الجميع ✓', good: true),
    };
  }

  /// «جهازه ما ردّ» فارغاً والفحص منتهٍ: ما يعنيه وحده (المراجعة F4/F13 — كان «كلّ المتّصلين قُرئت أجهزتهم ✓» وفحص
  /// الـVPN تعذّر فلم يُقرأ أحد): متّصلون بلا قراءة يُعدّون بأقسامهم، و✓ حين قُرئ كلّ متّصلٍ فعلاً.
  Widget _noReplyEmpty(SubsCheckReport r) {
    final unread = [
      for (final c in const [SubsCheckCat.unchecked, SubsCheckCat.noMetrics])
        if (r.count(c) > 0) '«${c.label}» ${formatIQD(r.count(c))}',
    ];
    if (unread.isNotEmpty) {
      return _notice(LucideIcons.info, 'لا أحد جهازه ما ردّ\nمتّصلون بلا قراءة: ${unread.join(' · ')}');
    }
    return [...r.rows, ...r.healthy].any((x) => x.sub.isOnline)
        ? _notice(LucideIcons.circleCheck, 'كلّ المتّصلين قُرئت أجهزتهم ✓', good: true)
        : _notice(LucideIcons.info, 'لا أحد جهازه ما ردّ');
  }

  /// «غير متّصل الآن» فارغاً: «الكلّ متّصل» حين لا غير متّصلٍ في المعروض أصلاً — من له قراءةٌ سابقة يُعدّ بقسمها
  /// (المراجعة F13).
  Widget _offlineEmpty(SubsCheckReport r) {
    final read = [...r.rows, ...r.healthy].where((x) => !x.sub.isOnline).length;
    if (read == 0) return _notice(LucideIcons.circleCheck, 'الكلّ متّصل الآن ✓', good: true);
    final where = '«${SubsCheckCat.healthy.label}» أو «${SubsCheckCat.problems.label}»';
    return _notice(LucideIcons.info, 'لا أحد هنا — ${formatIQD(read)} غير متّصل الآن بقراءةٍ سابقة في $where');
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  Widget _footer(bool mergedAll) {
    final t = _limits(null);
    final lines = <String>[
      // «كل الشركات»: الحدود لكلّ شركةٍ وحدها — لا سطرٌ واحد يصدق على الكلّ
      if (!mergedAll)
        'حدّ المشكلة من «تنبيه المشترك»: الإشارة أضعف من ${iso('${t.signalDbm} dBm')} · CCQ ${iso('${t.ccqPct}%')} أو أقلّ'
            ' · الضوء أضعف من ${iso('${_num(t.fiberRxDbm)} dBm')} · الحرارة فوق ${iso('${t.fiberTempC}°C')}',
      if (widget.big) 'الحساب كبير — الفحص للصفوف المحمّلة في القائمة',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text(l, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5)),
        ),
    ]);
  }

  Widget _notice(IconData icon, String text, {bool good = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
        child: Column(children: [
          Icon(icon, size: 34, color: good ? AppColors.success : AppColors.textLow),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: AppType.label(color: AppColors.textMid).copyWith(height: 1.6)),
        ]),
      );
}
