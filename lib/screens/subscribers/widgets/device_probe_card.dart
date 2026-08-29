import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_config_api.dart';
import '../../../api/device_probe_api.dart';
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

class _DeviceProbeCardState extends State<DeviceProbeCard> {
  bool _loading = true;
  DeviceHealthSnapshot? _snap;
  String? _notes;

  @override
  void initState() {
    super.initState();
    _run();
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
                  Icon(LucideIcons.fileText,
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
        Icon(LucideIcons.router, size: 18, color: AppColors.brandAccent),
        const SizedBox(width: Sp.sm),
        Text('معلومات الجهاز', style: AppType.cardTitle()),
        const SizedBox(width: Sp.sm),
        Flexible(child: chip),
        const Spacer(),
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
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.lg, vertical: 14),
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
                    Text('يتم تجربة Ubiquiti ثم ONT',
                        style: AppType.muted()),
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
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.lg, vertical: 14),
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
                color:
                    o.voltageOk ? AppColors.textHi : AppColors.warningFill,
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
        _DetailRow(label: 'نوع الجهاز', value: 'Huawei ONT', strong: true),
        if (o.sendStatus.trim().isNotEmpty && o.sendStatus.trim() != '--')
          _DetailRow(label: 'حالة الليف', value: o.sendStatus),
      ],
    );
  }

  // ═══════════════ Ubiquiti ═══════════════

  Widget _ubntBody(UbiquitiStatus u) {
    final tiles = <Widget>[
      if (u.signalDbm != null)
        _MetricTile(
          label: 'الإشارة',
          value: '${u.signalDbm} dBm',
          color: _healthColor(u.signalHealth),
        ),
      if (u.snrDb != null)
        _MetricTile(
          label: 'SNR',
          value: '${u.snrDb} dB',
          color: AppColors.textHi,
        ),
      if (u.ccqPercent != null)
        _MetricTile(
          label: 'CCQ',
          value: '${u.ccqPercent}%',
          color: _healthColor(u.ccqHealth),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tiles.isNotEmpty) ...[
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],
        _DetailRow(
          label: 'نوع الجهاز',
          value: u.hostname.isEmpty ? 'Ubiquiti' : '${u.hostname} (UBNT)',
          strong: true,
        ),
        if (u.firmware.isNotEmpty)
          _DetailRow(label: 'الإصدار', value: u.firmware, small: true),
        if (u.ssid.isNotEmpty)
          _DetailRow(label: 'SSID', value: u.ssid, small: true),
        if ((u.txRateKbps ?? 0) > 0 || (u.rxRateKbps ?? 0) > 0)
          _DetailRow(
            label: 'الإرسال / الاستقبال',
            value: '${_rate(u.txRateKbps)} / ${_rate(u.rxRateKbps)}',
          ),
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
    final Color bg =
        unplugged ? AppColors.bg : AppColors.brandSoftBg;
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
          Text(label, style: AppType.body(color: AppColors.textLabel)),
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
        color: AppColors.bg,
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
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.pill),
          ),
        ),
      ),
    );
  }
}
