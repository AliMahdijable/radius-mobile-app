import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../models/device_health.dart';
import '../sheets/device_config_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// كارت «معلومات الجهاز» — يفحص IP المشترك عند أوّل بناء ويعرض قياسات
/// الجهاز. الشريحة 4 من إعادة التصميم (2026-08-29).
///
/// المخطّط يبني الكارت من ثلاث طبقات ثابتة:
///   1. **رأس**: أيقونة 18 بلون الـaccent + عنوان 14/w600 + حبّة حالة
///      ملوّنة دلاليّاً + زرّا `settings` و`sync` في الطرف.
///   2. **جسم القياسات**: بلاطات غاطسة (#F7F8F5 · r14) — ثلاث بالعرض
///      لـUbiquiti (الإشارة · SNR · CCQ)، وشبكة 2×2 لـONT (RX · TX ·
///      الفولتيّة · الحرارة).
///   3. **صفوف التفاصيل**: تسمية خافتة يمين وقيمة `ltr` يسار.
///
/// حالة الفحص لها رسم خاصّ في المخطّط (سطر «جارٍ فحص الجهاز تلقائيّاً…»
/// + هياكل نابضة) بدل الدوّارة الوسطى — تُشعر المدير أنّ الكارت سيمتلئ
/// لا أنّه عالق.
///
/// ⚠️ زرّا الرأس هما المدخل الوحيد لـ`DeviceConfigSheet` وللفحص اليدوي
/// — لا يُسقطان مهما تغيّر التصميم.
class DeviceProbeCard extends StatefulWidget {
  const DeviceProbeCard({
    super.key,
    this.ip = '',
    required this.username,
  });

  /// IP من SAS4 (framedipaddress). قد يكون فارغاً — الـprobe() داخلياً
  /// يجرّب customIp من DeviceConfig أوّلاً، فحتى المشتركون بلا session
  /// نشط يحصلون على فحص لو المدير خزّن customIp في إعدادات الجهاز.
  final String ip;
  final String username;

  @override
  State<DeviceProbeCard> createState() => _DeviceProbeCardState();
}

class _DeviceProbeCardState extends State<DeviceProbeCard>
    with WidgetsBindingObserver {
  bool _loading = true;
  DeviceHealthSnapshot? _snap;
  String? _notes;

  // ═══════════ الترافيك اللحظي ═══════════
  //
  // عدّادات البايت تصل أصلاً في كلّ استجابة `/status.cgi` — نفس الطلب
  // الذي يجريه الفحص. المعدّل فرق قراءتين مقسوماً على الزمن بينهما،
  // فالنبضة الأولى تزرع المرجع ولا تُنتج قيمة.
  //
  // ⚠️ **الجلسة تُفتح مرّة واحدة** ثمّ يُعاد استعمالها: تسجيل دخول كلّ
  // 3 ثوانٍ على معالج CPE ضعيف عبء لا مبرّر له، و`fetchStatus` تقبل
  // جلسة قائمة.
  static const _pulse = Duration(seconds: 3);
  Timer? _trafficTimer;
  UbntTrafficSession? _session;
  int? _lastRx;
  int? _lastTx;
  DateTime? _lastSample;
  int? _rxBps;
  int? _txBps;
  bool _pulsing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ⚠️ اقرأ ما فحصته موجة القائمة قبل أن تفحص.
    //
    // كان الكارت يُطلق فحصاً كاملاً عند كل فتح بلا سؤال الكاش، بينما
    // شريحة القائمة تقرأه قراءةً متزامنة ولا تفحص أبداً. فالنتيجة:
    // جهاز يُفحص مرّة في القائمة ومرّة عند فتح كارته — ومعه دوّارة
    // تحميل تُوحي بأنّ شيئاً يجري وهو معروف أصلاً.
    //
    // نقرأ بالـusername أوّلاً (لا يلتبس مع تجاوز العنوان) ثمّ بالـIP.
    // النتيجة القديمة تُعرض أيضاً: الجهاز الذي فُحص مرّة لا ينبغي أن
    // يبدو مجهولاً بعدها. إن كانت قديمة نُحدّثها في الخلفيّة بلا دوّارة.
    final hit = DeviceProbeApi.peek(
      username: widget.username,
      ip: widget.ip.trim(),
    );
    if (hit != null) {
      _snap = hit.snap;
      _loading = false;
      _maybeStartTraffic();
      _loadNotesOnly();
      if (hit.stale) _refreshQuietly();
      return;
    }
    _run();
  }

  /// الجهاز مفحوص أصلاً: نكمل بجلب الملاحظات بلا دوّارة ولا فحص.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trafficTimer?.cancel();
    _session?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ⚠️ بدون هذا يبقى المؤقّت يطرق جهاز المشترك كلّ 3 ثوانٍ والتطبيق
    // في الخلفيّة — شاشة التفاصيل كانت خالية من أيّ مراقب دورة حياة.
    if (state == AppLifecycleState.resumed) {
      _maybeStartTraffic();
    } else {
      _trafficTimer?.cancel();
      _trafficTimer = null;
      // نُغلق قناة SSH أيضاً — إبقاؤها مفتوحة والتطبيق في الخلفيّة
      // يستهلك جلسة على جهاز المشترك بلا أيّ فائدة.
      _session?.close();
      _session = null;
    }
  }

  /// يبدأ الاستطلاع لأجهزة Ubiquiti وحدها.
  ///
  /// ONT مستثناة عمداً: عميل Huawei يكشط صفحة بصريّات بلا أيّ عدّاد
  /// بايت، ومهلاته 15 ثانية لأنّ تلك الأجهزة بطيئة — فاستطلاعها كلّ
  /// 3 ثوانٍ غير وارد أصلاً.
  void _maybeStartTraffic() {
    if (_trafficTimer != null) return;
    final snap = _snap;
    // ⚠️ الشرط على **نوع الجهاز** لا على وجود عدّادات في لقطة الفحص:
    // لقطة الفحص تأتي من `status.cgi` وهو لا يُصدّر عدّادات بايت على
    // airOS — لذلك كان الشرط السابق (`ubnt?.rxBytes != null`) يمنع
    // الاستطلاع من البدء إطلاقاً، فتبقى بلاطة SNR إلى الأبد.
    // العدّادات تأتي من SSH كما تفعل لوحة الأجهزة، وهو المسار المُثبَت.
    if (snap == null || snap.kind != DeviceKind.ubiquiti) return;
    _pulseTraffic(); // نبضة فوريّة تزرع المرجع بلا انتظار 3 ثوانٍ
    _trafficTimer = Timer.periodic(_pulse, (_) => _pulseTraffic());
  }

  Future<void> _pulseTraffic() async {
    if (_pulsing || !mounted) return;
    _pulsing = true;
    try {
      // الجلسة تُفتح مرّة وتُعاد. الأمر الوحيد في كلّ نبضة هو
      // `cat /proc/net/dev` — بضع مئات من البايتات وتفرّع عمليّة واحدة.
      if (_session == null) {
        final creds = await DeviceProbeApi.resolveUbntCreds(
          fallbackIp: widget.ip,
          subscriberUsername: widget.username,
        );
        if (creds == null) return;
        _session = await UbntTrafficSession.open(
          ip: creds.ip,
          user: creds.user,
          pass: creds.pass,
        );
      }
      final sess = _session;
      if (sess == null) return;

      final read = await sess.sample();
      if (read == null) {
        // الجلسة ماتت غالباً (انقطاع أو مهلة الجهاز) — نُغلقها ليُعاد
        // فتحها في النبضة القادمة بدل الإصرار على قناة ميّتة.
        sess.close();
        _session = null;
        return;
      }

      final now = DateTime.now();
      if (_lastRx != null && _lastSample != null) {
        final secs = now.difference(_lastSample!).inMilliseconds / 1000.0;
        final dDown = read.down - _lastRx!;
        final dUp = read.up - _lastTx!;
        // الفرق السالب يعني التفاف عدّاد أو إعادة إقلاع — يُتخطّى بدل
        // عرض قيمة سالبة أو قفزة كاذبة.
        if (secs > 0.5 && dDown >= 0 && dUp >= 0) {
          final r = (dDown * 8 / secs).round();
          final t = (dUp * 8 / secs).round();
          // سقف عقلانيّة: قراءة شاذّة بعد التفاف 32-bit تمرّ بلا هذا.
          const sane = 10000000000;
          if (r <= sane && t <= sane && mounted) {
            setState(() {
              _rxBps = r;
              _txBps = t;
            });
          }
        }
      }
      _lastRx = read.down;
      _lastTx = read.up;
      _lastSample = now;
    } catch (_) {
      // نبضة فاشلة: لا نمسّ المرجع، فالنبضة الناجحة التالية تحسب
      // المعدّل على كامل الفجوة — متوسّط صحيح لا قفزة.
      _session?.close();
      _session = null;
    } finally {
      _pulsing = false;
    }
  }

  Future<void> _loadNotesOnly() async {
    final cfg = await DeviceConfigApi.fetchConfig(widget.username);
    if (!mounted) return;
    setState(() => _notes = cfg?.notes?.trim());
  }

  /// تحديث صامت لنتيجة قديمة: بلا `_loading` فلا دوّارة ولا وميض.
  /// إن فشل الفحص تبقى النتيجة القديمة معروضة — أفضل من فراغ.
  Future<void> _refreshQuietly() async {
    final snap = await DeviceProbeApi.probe(
      fallbackIp: widget.ip,
      subscriberUsername: widget.username,
    );
    if (!mounted || snap == null) return;
    setState(() => _snap = snap);
  }

  Future<void> _run({bool force = false}) async {
    setState(() => _loading = true);
    // Probe + notes in parallel — both go through small caches so the
    // total cost on a warm session is sub-100ms.
    final results = await Future.wait([
      DeviceProbeApi.probe(
        fallbackIp: widget.ip,
        subscriberUsername: widget.username,
        force: force,
      ),
      DeviceConfigApi.fetchConfig(widget.username),
    ]);
    if (!mounted) return;
    final snap = results[0] as DeviceHealthSnapshot?;
    final cfg = results[1] as DeviceConfig?;
    setState(() {
      _snap = snap;
      _notes = cfg?.notes?.trim();
      _loading = false;
    });
    _maybeStartTraffic();
  }

  Future<void> _openConfig() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => DeviceConfigSheet(username: widget.username),
    );
    if (changed == true && mounted) {
      // The sheet already invalidated per-IP cache when it saved.
      _run(force: true);
    }
  }

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
          _header(),
          const SizedBox(height: 14),
          _body(),
          // مطلب 2026-06-11: سطر ملاحظة المدير من DeviceConfig.notes.
          // مخفي إذا فاضي حتى لا يضيف ارتفاع ع الكرت بدون فائدة.
          if ((_notes ?? '').isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.icon),
                border: Border.all(color: AppColors.warningSoftBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(LucideIcons.fileText,
                      size: 13, color: AppColors.warningFill),
                  const SizedBox(width: Sp.x6),
                  Expanded(
                    child: Text(_notes!,
                        style: AppType.body(color: AppColors.warningOnSoft)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// رأس الكارت — أيقونة + عنوان + حبّة الحالة + زرّان.
  Widget _header() {
    final chip = _statusChip();
    return Row(
      children: [
        // ⚠️ `Flexible` و`Spacer` في صفّ واحد يتقاسمان الفراغ.
        //
        // كان الترتيب: … Flexible(chip) ثمّ Spacer() — ولكليهما
        // flex=1، فيقتسمان الفراغ الحرّ نصفين. والحبّة بـ`FlexFit.loose`
        // تأخذ مقاسها الطبيعي فقط، فيضيع نصيبها من الفراغ **بلا أن
        // يُعاد توزيعه** — فتظهر فجوة قبل الزرّين ولا يبلغان حافّة
        // الكارت. (بلاغ المستخدم بالصورة 2026-08-30)
        //
        // الحلّ: تجميع محتوى البداية في `Expanded` واحد يبتلع الفراغ
        // كلّه، فينزاح الزرّان إلى النهاية فعلاً.
        Expanded(
          child: Row(
            children: [
              Icon(LucideIcons.router, size: 18, color: AppColors.brandAccent),
              const SizedBox(width: Sp.sm),
              Flexible(
                child: Text('معلومات الجهاز',
                    style: AppType.cardTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: Sp.sm),
              chip,
            ],
          ),
        ),
        _HeaderIcon(
          icon: LucideIcons.settings,
          onTap: _openConfig,
        ),
        const SizedBox(width: Sp.sm),
        _HeaderIcon(
          icon: LucideIcons.refreshCw,
          busy: _loading,
          onTap: _loading ? null : () => _run(force: true),
        ),
      ],
    );
  }

  Widget _statusChip() {
    late final String label;
    late final Color fg, bg, border;
    if (_loading && _snap == null) {
      label = 'جارٍ الفحص';
      fg = AppColors.textMid;
      bg = AppColors.surfaceSunken;
      border = AppColors.border;
    } else if (_snap == null) {
      label = 'غير متاح';
      fg = AppColors.dangerOnSoft;
      bg = AppColors.dangerSoftBg;
      border = AppColors.dangerSoftBorder;
    } else {
      label = switch (_snap!.kind) {
        DeviceKind.ont => 'ONT',
        DeviceKind.ubiquiti => 'UBNT',
        _ => 'متصل',
      };
      fg = AppColors.brandOnSoft;
      bg = AppColors.brandSoftBg;
      border = AppColors.brandSoftBorder;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.pillLabel(color: fg).copyWith(letterSpacing: 0),
      ),
    );
  }

  Widget _body() {
    if (_loading && _snap == null) return _scanning();
    final snap = _snap;
    if (snap == null) return _unreachable();
    if (snap.kind == DeviceKind.ont) return _ontBody(snap.ont!);
    if (snap.kind == DeviceKind.ubiquiti) return _ubntBody(snap.ubnt!);
    return const SizedBox.shrink();
  }

  /// حالة الفحص — سطر مطمئِن + هياكل نابضة، كما يرسمها المخطّط.
  Widget _scanning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.brandAccent,
                  backgroundColor: AppColors.border,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('جارٍ فحص الجهاز تلقائياً…',
                        style: AppType.rowValue()),
                    const SizedBox(height: Sp.xxs),
                    Text('يتم تجربة Ubiquiti ثم ONT', style: AppType.muted()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.md),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: Sp.sm),
              const Expanded(child: _SkeletonBox(height: 56)),
            ],
          ],
        ),
        const SizedBox(height: Sp.md),
        const _SkeletonBar(widthFactor: 0.78),
        const SizedBox(height: Sp.sm),
        const _SkeletonBar(widthFactor: 0.60),
        const SizedBox(height: Sp.sm),
        const _SkeletonBar(widthFactor: 0.68),
      ],
    );
  }

  Widget _unreachable() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.plugZap, size: 20, color: AppColors.textHint),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('لم يُتمكّن من الوصول للجهاز',
                    style: AppType.rowValue(color: AppColors.textMid)),
                const SizedBox(height: Sp.xxs),
                Text('اضبط الـIP وبيانات الدخول من زرّ الإعدادات',
                    style: AppType.muted()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════ ONT ═══════════════

  Widget _ontBody(OntOpticalInfo o) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // شبكة 2×2 كما في المخطّط — أربع قيم بصريّة قبل التفاصيل.
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.arrowDown,
                label: 'RX Power',
                value: '${o.rxPower} dBm',
                color: o.rxOk ? AppColors.brandAccent : AppColors.error,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.arrowUp,
                label: 'TX Power',
                value: '${o.txPower} dBm',
                color: o.txOk ? AppColors.textHi : AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.zap,
                label: 'الفولتية',
                value: '${o.voltage} mV',
                color: o.voltageOk ? AppColors.textHi : AppColors.warningFill,
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _MetricTile(
                icon: LucideIcons.thermometer,
                label: 'الحرارة',
                value: '${o.temperature} °C',
                color: o.tempOk ? AppColors.textHi : AppColors.warningFill,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _DetailRow(label: 'نوع الجهاز', value: 'Huawei ONT', strong: true),
        if (o.sendStatus.trim().isNotEmpty && o.sendStatus.trim() != '--')
          _DetailRow(label: 'حالة الليف', value: o.sendStatus),
      ],
    );
  }

  // ═══════════════ Ubiquiti ═══════════════

  Widget _ubntBody(UbiquitiStatus u) {
    // 🐛 بلاغ 2026-08-31 بصورة: «↓587K ↑3…» — رقم الرفع مقصوص.
    //
    // القياس من ملفّ الخطّ المشحون نفسه (IBMPlexSansArabic-700، upem
    // 1000) لا بالتقدير:
    //
    //   المتاح للبلاطة @414dp = (414 − 82) ÷ 3 − 24 = 86.67 نقطة
    //   «↓587K ↑3.2M» @14px    = 6.861em × 14      = 96.05 نقطة
    //
    // والسهمان وحدهما 1.800em — **26٪ من النصّ** بلا أيّ معلومة
    // رقميّة (U+2191/U+2193 عرضهما 0.900em، أوسع من الرقم بـ50٪).
    //
    // ولا يوجد هاتف يتّسع لها: 320→55.3 · 360→68.7 · 393→79.7 ·
    // 414→86.7 · 430→92.0 نقطة، وكلّها دون الـ96.05. حتّى القيمة
    // الدنيا «↓0K ↑0K» (64.8) تفيض على 320.
    //
    // والأسوأ أنّ القصّ يكذب لا يُخفي فقط: على 360 يختفي الرفع كلّه،
    // وعلى 320 تختفي وحدة القياس فيُقرأ «587» بلا معرفة أكيلو هي أم
    // ميغا، وعلى 320 مع تكبير 1.2 يصير «↓58…» — رقمٌ **خاطئ**.
    //
    // الحلّ بنيويّ لا تجميليّ: القصيرتان ثابتتا الطول تتقاسمان الصفّ،
    // والترافيك — الوحيد المتغيّر الطول — يأخذ العرض الكامل (324 نقطة
    // على 414dp = 3.4× حاجته، و226 على 320dp = 2.4×).
    final short = <Widget>[
      if (u.signalDbm != null)
        _MetricTile(
          label: 'الإشارة',
          value: '${u.signalDbm} dBm',
          color: _healthColor(u.signalHealth),
        ),
      if (u.ccqPercent != null)
        _MetricTile(
          label: 'CCQ',
          value: '${u.ccqPercent}%',
          color: _healthColor(u.ccqHealth),
        ),
      // SNR يبقى في الصفّ: قصيرٌ ثابت («28 dB») ولا يظهر إلّا حين لا
      // يُصدّر الإصدار عدّادات بايت، فلا يزاحم الترافيك أبداً.
      if (_snap?.kind != DeviceKind.ubiquiti && u.snrDb != null)
        _MetricTile(
          label: 'SNR',
          value: '${u.snrDb} dB',
          color: AppColors.textHi,
        ),
    ];

    // الترافيك اللحظي محلّ SNR (طلب المستخدم 2026-08-30): SNR رقم
    // شبه ثابت يُنظر إليه عند التركيب، والترافيك هو ما يُسأل عنه
    // يوميّاً — «هل المشترك يسحب فعلاً؟».
    final Widget? wide = _snap?.kind == DeviceKind.ubiquiti
        ? _MetricTile(
            label: 'الترافيك',
            value: _rxBps == null
                ? '—'
                : '↓${_fmtBps(_rxBps!)} ↑${_fmtBps(_txBps ?? 0)}',
            color: _rxBps == null ? AppColors.textLow : AppColors.brandAccent,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (short.isNotEmpty)
          // ⚠️ بلا `crossAxisAlignment: CrossAxisAlignment.stretch` هنا.
          // هي الغريزة لتسوية ارتفاع البلاطات، لكنّها تُعيد المشكلة:
          // تفرض قيداً ضيّقاً على الأبناء فيُقصّ النصّ من جديد.
          Row(
            children: [
              for (var i = 0; i < short.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm),
                Expanded(child: short[i]),
              ],
            ],
          ),
        if (wide != null) ...[
          if (short.isNotEmpty) const SizedBox(height: Sp.sm),
          wide, // العرض الكامل — بلا Expanded وبلا جار
        ],
        if (short.isNotEmpty || wide != null) const SizedBox(height: 14),
        _DetailRow(
          label: 'نوع الجهاز',
          value: u.hostname.isEmpty ? 'Ubiquiti' : '${u.hostname} (UBNT)',
          strong: true,
        ),
        if (u.firmware.isNotEmpty)
          _DetailRow(label: 'الإصدار', value: u.firmware, small: true),
        if (u.ssid.isNotEmpty)
          _DetailRow(label: 'SSID', value: u.ssid, small: true),
        // 🐛 كانت صفّاً واحداً بتسمية «الإرسال / الاستقبال» (7.24em —
        // أطول تسمية في الكارت) وقيمة «144.4 Mbps / 300.0 Mbps». وفي
        // `_DetailRow` التسمية بلا flex فتأخذ عرضها كاملاً أوّلاً،
        // والقيمة `Expanded` تمتصّ النقص كلّه — فتُقصّ سرعة الاستقبال
        // كلّيّاً على 360dp، وهي الرقم الذي يقرّر به الفنّيّ إن كان
        // اللنك يحتاج إعادة توجيه.
        //
        // القسمة إلى صفّين تُقصّر أطول تسمية من 7.24em إلى 2.76em ولا
        // تمسّ `_DetailRow` ولا السبعة الآخرين الذين يستعملونه.
        if ((u.txRateKbps ?? 0) > 0)
          _DetailRow(label: 'الإرسال', value: _rate(u.txRateKbps)),
        if ((u.rxRateKbps ?? 0) > 0)
          _DetailRow(label: 'الاستقبال', value: _rate(u.rxRateKbps)),
        if (u.peerMac != null && u.peerMac!.isNotEmpty)
          _DetailRow(label: 'Peer MAC', value: u.peerMac!, small: true),
        if (u.peerCount != null && u.peerCount! > 0)
          _DetailRow(label: 'المتصلون', value: '${u.peerCount}'),
        // مطلب 2026-06-11: عرض كل المنافذ (لا فقط primary) — كل
        // eth interface بحبّة منفصلة مع plugged/speed.
        if (u.lanPorts.isNotEmpty) _lanPortsRow(u.lanPorts),
      ],
    );
  }

  /// صفّ المنافذ — تسمية يمين وحبّات المنافذ يسار، كما في المخطّط
  /// («ETH0 · 100M» بلون البراند و«ETH1 · مفصول» رماديّة).
  Widget _lanPortsRow(List<LanPort> ports) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('المنافذ', style: AppType.body(color: AppColors.textLabel)),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: Sp.x6,
              runSpacing: Sp.x6,
              children: [for (final p in ports) _lanChip(p)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lanChip(LanPort p) {
    final unplugged = !p.plugged;
    final speed = p.displaySpeed;
    final Color fg = unplugged ? AppColors.textLow : _speedColor(speed);
    final Color bg = unplugged ? AppColors.bg : AppColors.brandSoftBg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text(
        '${p.label} · ${unplugged ? 'مفصول' : speed}',
        textDirection: TextDirection.ltr,
        style: AppType.pillLabel(color: fg).copyWith(letterSpacing: 0),
      ),
    );
  }

  static Color _speedColor(String speed) {
    if (speed.contains('Gbps')) return AppColors.brandAccent;
    final m = RegExp(r'(\d+)\s*Mbps').firstMatch(speed);
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    if (mbps == null) return AppColors.textMid;
    return mbps >= 100 ? AppColors.brandAccent : AppColors.warningFill;
  }

  static Color _healthColor(String h) {
    switch (h) {
      case 'good':
        return AppColors.brandAccent;
      case 'warn':
        return AppColors.warningFill;
      case 'bad':
        return AppColors.error;
      default:
        return AppColors.textHi;
    }
  }

  static String _rate(int? kbps) {
    if (kbps == null || kbps == 0) return '—';
    if (kbps >= 1000) return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
    return '$kbps Kbps';
  }
}

/// زرّ أيقوني في رأس الكارت — 18dp بلا خلفيّة، كما في المخطّط.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, this.onTap, this.busy = false});
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.all(Sp.xs),
        child: SizedBox(
          width: 18,
          height: 18,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textLow),
                )
              : Icon(icon, size: 18, color: AppColors.textLow),
        ),
      ),
    );
  }
}

/// البلاطة الغاطسة للقياس — تسمية 10.5 فوق قيمة 14/w700 ملوّنة دلاليّاً.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
  });
  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.textLabel),
                const SizedBox(width: Sp.xs),
              ],
              Flexible(
                child: Text(label,
                    style: AppType.micro(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: Sp.xxs),
          Text(
            value,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.cardTitle(color: color)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// صفّ تفصيل — تسمية خافتة يمين وقيمة `ltr` يسار.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.small = false,
  });
  final String label;
  final String value;

  /// أوّل صفّ في المجموعة (نوع الجهاز) بلون نصّ عالٍ.
  final bool strong;

  /// القيم الطويلة (firmware / SSID / MAC) بدرجة أصغر حتى لا تلتفّ.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = small
        ? AppType.body(color: AppColors.textBody).copyWith(fontSize: 11.5)
        : AppType.body(
            color: strong ? AppColors.textHi : AppColors.textBody,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        children: [
          // ⚠️ `Flexible` **مع** `maxLines`+`overflow` معاً لا وحدها:
          // `softWrap` افتراضها true، فتسمية عربيّة طويلة تلتفّ سطرين
          // بدل أن تُختصر — فيتغيّر ارتفاع الكارت بدل أن يُحلّ شيء.
          //
          // والغاية أن تتنازل التسمية أوّلاً: البيانات أثمن من عنوانها.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(color: AppColors.textLabel),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// هيكل نابض — بلاطة القياس أثناء الفحص.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
    );
  }
}

/// هيكل نابض — سطر تفصيل أثناء الفحص.
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
    );
  }
}

/// صياغة معدّل بالبت/ثانية بوحدة مقروءة.
///
/// منزلة عشريّة واحدة: البلاطة ضيّقة، ومنزلتان تدفعان النصّ للقصّ في
/// «↓12.34 ↑3.45».
/// يُنسّق معدّلاً بالبت/ثانية.
///
/// 🐛 كان يفتح بـ`if (bps < 1000) return '0K';` — فمشتركٌ يسحب 400 إلى
/// 999 بت/ث يُعرَض «0K»، وهو **بصريّاً مطابق** للوصلة الميّتة. فيستنتج
/// المدير أنّ المشترك لا يسحب شيئاً وقد يقطعه. جوابٌ خاطئ بثقة، لا نقص.
///
/// و«0K» ليست أقصر ممّا يستحقّ: بعد أن أخذت بلاطة الترافيك العرض
/// الكامل (2026-08-31) صار الفارق بين «0K» و«587b» بلا أثر على التخطيط.
@visibleForTesting
String fmtBpsForTest(int bps) => _fmtBps(bps);

String _fmtBps(int bps) {
  if (bps <= 0) return '0';
  if (bps < 1000) return '${bps}b'; // الصدق أهمّ من التوحيد
  if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)}K';
  if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
  return '${(bps / 1000000000).toStringAsFixed(1)}G';
}
