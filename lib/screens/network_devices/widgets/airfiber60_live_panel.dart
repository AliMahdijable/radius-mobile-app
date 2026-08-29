import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';

/// لوحة مراقبة متخصّصة لـUBNT airFiber 60 (GP/LR) — PtP 60 GHz link view.
/// mca-status عنده مضلّل (signal=-93، wlanTxRate=0). البيانات الحقيقيّة في wstalist.prs_sta.
/// المعروض: SNR + RSSI + Distance + Capacity + Margin + MCS.
class AirFiber60LivePanel extends StatefulWidget {
  final NetworkDevice device;
  const AirFiber60LivePanel({super.key, required this.device});

  @override
  State<AirFiber60LivePanel> createState() => _AirFiber60LivePanelState();
}

class _AirFiber60LivePanelState extends State<AirFiber60LivePanel> {
  UbntStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  // ethernet rate tracking (delta بين قراءتين)
  final Map<String, _BytesPoint> _lastBytes = {};
  final Map<String, _IfaceRate> _rates = {};

  static const _refreshInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    setState(() => _monitoring = true);
    await _fetch();
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
  }

  void _stopMonitoring() {
    _timer?.cancel();
    setState(() => _monitoring = false);
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      // diagnostic (debug فقط — لا يُطبع في release لتفادي كشف الـuser)
      if (kDebugMode) {
        debugPrint('🔵 airFiber creds user_len=${user.length} '
            'pass_len=${pass.length} port=${widget.device.apiPort ?? 22}');
      }
      if (user.isEmpty || pass.isEmpty) {
        throw UbntException('لم يتم إعداد credentials للجهاز '
            '(user="$user" pass_len=${pass.length})');
      }
      final port = widget.device.apiPort ?? 22;

      // 2026-08-18: نُطبّق partial فقط للتحميل الأوّل — refresh لا يستفيد
      // منه لأنّه يفرغ الـstations مؤقّتاً → hero card يختفي → المستخدم
      // يشوف الجهاز "فُصل ورجع". فيه بديل: نحتفظ بالـstations القديمة
      // ونستبدل باقي الحقول من partial.
      final isFirstLoad = _stats == null;
      final s = await UbntApi.fetchStats(
        ip: widget.device.ip,
        port: port,
        user: user,
        pass: pass,
        // ⚡ Tier 1 partial بعد mca-status/af-status (~500ms-1s):
        // device name/CPU/RAM/signal فوراً بدل انتظار wstalist (~1-2s كامل).
        onPartialReady: isFirstLoad
            ? (partial) {
                if (!mounted) return;
                setState(() {
                  _stats = partial;
                });
              }
            : null, // ← refresh: تجاهل partial، انتظر البيانات الكاملة
      );

      _updateInterfaceRates(s);

      if (!mounted) return;
      setState(() {
        _stats = s;
        _lastFetch = DateTime.now();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UbntException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  void _updateInterfaceRates(UbntStats s) {
    final now = DateTime.now();
    for (final iface in s.interfaces) {
      if (iface.rxBytes == null || iface.txBytes == null) continue;
      final prev = _lastBytes[iface.ifname];
      _lastBytes[iface.ifname] =
          _BytesPoint(iface.rxBytes!, iface.txBytes!, now);
      if (prev != null) {
        final dt = now.difference(prev.at).inMilliseconds / 1000;
        if (dt > 0) {
          _rates[iface.ifname] = _IfaceRate(
            rxBps: ((iface.rxBytes! - prev.rx) * 8 / dt).round(),
            txBps: ((iface.txBytes! - prev.tx) * 8 / dt).round(),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _loading) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ));
    }
    if (_error != null && _stats == null) {
      return _errorCard();
    }
    if (_stats == null) return const SizedBox.shrink();

    final s = _stats!;
    final peer = s.stations.isNotEmpty ? s.stations.first : null;

    return Column(children: [
      // Header controls
      _controlBar(),
      const SizedBox(height: Sp.md),
      // 2026-08-18: عرض banner خطأ فوق البيانات القديمة إن كان الفشل الأخير
      // ما زال قائماً — سابقاً كان صامتاً تماماً (المستخدم يظنّ الجهاز يعمل).
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.dangerSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              'آخر تحديث فشل — البيانات معروضة من آخر جولة ناجحة',
              style:
                  TextStyle(fontSize: 11, color: AppColors.error, height: 1.4),
            )),
          ]),
        ),
        const SizedBox(height: Sp.md),
      ],
      // 🎯 Hero: peer + signal + SNR + MCS
      if (peer != null) _heroCard(peer),
      if (peer != null) const SizedBox(height: Sp.md),
      // ⚖️ Signal margin + Capacity utilization
      if (peer != null && peer.dlSignalExpect != null) _marginCard(peer),
      if (peer != null && peer.dlSignalExpect != null)
        const SizedBox(height: Sp.md),
      // 📊 Link performance
      if (peer != null) _linkPerformanceCard(peer),
      if (peer != null) const SizedBox(height: Sp.md),
      // 🌡️ System (CPU/RAM/Uptime)
      _systemCard(s),
      const SizedBox(height: Sp.md),
      // 🔌 Ethernet
      if (s.interfaces.isNotEmpty) _ethernetCard(s),
      if (s.interfaces.isNotEmpty) const SizedBox(height: Sp.md),
      // 📍 Location
      if (s.hasLocation) _locationCard(s),
      if (s.hasLocation) const SizedBox(height: Sp.md),
      // ℹ️ Info (firmware + sector)
      _infoCard(s, peer),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // Header controls
  // ═══════════════════════════════════════════════════════
  Widget _controlBar() {
    final freshMs = _lastFetch != null
        ? DateTime.now().difference(_lastFetch!).inSeconds
        : null;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _monitoring
              ? AppColors.success.withValues(alpha: 0.12)
              : AppColors.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(R.card),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // 2026-08-18: النقطة الخضراء تبقى دائماً — التبديل السابق
          // بـCircularProgressIndicator كان يبدو كأنّ الجهاز فُصل ورجع.
          // الآن: opacity pulse خفيف فقط عند _loading (يوحي التحديث
          // بدون كسر استمرارية "الحيّة").
          AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: _loading ? 0.35 : 1.0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _monitoring ? AppColors.success : AppColors.textLow,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
              _monitoring
                  ? (freshMs != null ? 'مباشر · قبل ${freshMs}ث' : 'مباشر')
                  : 'موقوف',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _monitoring ? AppColors.success : AppColors.textMid,
              )),
        ]),
      ),
      const Spacer(),
      IconButton(
        onPressed: _loading ? null : _fetch,
        icon: Icon(LucideIcons.refreshCw, size: 16, color: AppColors.textMid),
        tooltip: 'تحديث الآن',
      ),
      IconButton(
        onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
        icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16, color: AppColors.textMid),
        tooltip: _monitoring ? 'إيقاف المراقبة' : 'بدء المراقبة',
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 🎯 Hero — peer name + signal + SNR + MCS
  // ═══════════════════════════════════════════════════════
  Widget _heroCard(UbntStation peer) {
    final signalColor = _signalColor(peer.signal);
    final peerName = peer.hostname ?? peer.mac;
    final snr = peer.snr;

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            signalColor.withValues(alpha: 0.10),
            signalColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: signalColor.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        // Peer name + link status
        Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: peer.isLinked60 ? AppColors.success : AppColors.error,
              boxShadow: peer.isLinked60
                  ? [
                      BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.4),
                          blurRadius: 6),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(peerName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.brandAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('60 GHz',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandAccent)),
          ),
        ]),
        const SizedBox(height: 12),
        // 4 metrics: RSSI | SNR | MCS RX | MCS TX
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _heroMetric(
                icon: LucideIcons.signal,
                label: 'RSSI',
                value: '${peer.signal}',
                unit: 'dBm',
                color: signalColor,
              )),
              _heroDivider(),
              Expanded(
                  child: _heroMetric(
                icon: LucideIcons.activity,
                label: 'SNR',
                value: snr != null ? '$snr' : '—',
                unit: snr != null ? 'dB' : '',
                color: snr != null ? _snrColor(snr) : AppColors.textLow,
              )),
              _heroDivider(),
              Expanded(
                  child: _heroMetric(
                icon: LucideIcons.arrowDown,
                label: 'RX MCS',
                value: peer.rxMcs?.toString() ?? '—',
                unit: '',
                color: AppColors.success,
              )),
              _heroDivider(),
              Expanded(
                  child: _heroMetric(
                icon: LucideIcons.arrowUp,
                label: 'TX MCS',
                value: peer.txMcs?.toString() ?? '—',
                unit: '',
                color: AppColors.brandAccent,
              )),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // شرائط قوّة الإشارة والـSNR (بصريّة، تصعد وتنزل مع القيم)
        _qualityBar(
          label: 'قوّة الإشارة',
          percent: _signalPercent(peer.signal),
          badge: _signalLabel(peer.signal),
          color: signalColor,
        ),
        const SizedBox(height: 8),
        _qualityBar(
          label: 'SNR',
          percent: snr != null ? _snrPercent(snr) : 0,
          badge: snr != null ? _snrLabel(snr) : '—',
          color: snr != null ? _snrColor(snr) : AppColors.textLow,
        ),
        const SizedBox(height: 10),
        // MAC
        Align(
          alignment: Alignment.centerRight,
          child: Text(peer.mac,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 10, color: AppColors.textLow)),
        ),
      ]),
    );
  }

  /// شريط جودة بصري — يشتغل مثل CPU%: يرتفع/ينخفض مع القيم.
  /// يعرض label + badge (تسمية) على اليمين + progress bar ملوّن.
  Widget _qualityBar({
    required String label,
    required double percent,
    required String badge,
    required Color color,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textMid)),
        const Spacer(),
        Text(badge,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 6),
        Text('${percent.round()}%',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 4),
      LayoutBuilder(builder: (context, constraints) {
        final fillWidth =
            constraints.maxWidth * (percent / 100).clamp(0.0, 1.0);
        return Stack(children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.borderSoft,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            height: 8,
            width: fillWidth,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                color.withValues(alpha: 0.6),
                color,
              ]),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 1)),
              ],
            ),
          ),
        ]);
      }),
    ]);
  }

  Widget _heroDivider() => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.borderSoft,
      );

  Widget _heroMetric({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.textMid)),
      const SizedBox(height: 2),
      Text(value,
          textDirection: TextDirection.ltr,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1)),
      if (unit.isNotEmpty)
        Text(unit,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: AppColors.textLow)),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // ⚖️ Signal margin card
  // ═══════════════════════════════════════════════════════
  Widget _marginCard(UbntStation peer) {
    final actual = peer.signal;
    final expected = peer.dlSignalExpect!;
    final margin = peer.signalMargin!;
    final utilization = peer.capacityUtilization;

    final marginColor = margin >= -3
        ? AppColors.success
        : margin >= -8
            ? AppColors.warning
            : AppColors.error;

    final utilColor = utilization == null
        ? AppColors.textLow
        : utilization >= 90
            ? AppColors.success
            : utilization >= 60
                ? AppColors.warning
                : AppColors.error;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.gauge, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('هامش الإشارة والسعة',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        // Signal margin
        IntrinsicHeight(
          child: Row(children: [
            Expanded(
                child: _marginTile(
              label: 'الفعلي',
              value: '$actual',
              unit: 'dBm',
              color: AppColors.textHi,
            )),
            const _MarginArrow(),
            Expanded(
                child: _marginTile(
              label: 'المتوقّع',
              value: '$expected',
              unit: 'dBm',
              color: AppColors.textMid,
            )),
            _heroDivider(),
            Expanded(
                child: _marginTile(
              label: 'الهامش',
              value: margin >= 0 ? '+$margin' : '$margin',
              unit: 'dB',
              color: marginColor,
            )),
          ]),
        ),
        const SizedBox(height: 12),
        // Capacity utilization
        if (utilization != null) ...[
          Row(children: [
            Text('استغلال السعة',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMid)),
            const Spacer(),
            Text('${utilization.round()}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: utilColor)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (utilization / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(utilColor),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _marginTile({
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.textMid)),
      const SizedBox(height: 2),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1)),
          const SizedBox(width: 2),
          Text(unit, style: TextStyle(fontSize: 9, color: AppColors.textLow)),
        ],
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 📊 Link performance — distance, capacity, uptime, sector
  // ═══════════════════════════════════════════════════════
  Widget _linkPerformanceCard(UbntStation peer) {
    final distanceKm = peer.distanceMeters != null
        ? (peer.distanceMeters! / 1000).toStringAsFixed(2)
        : null;
    final dlMbps = peer.dlCapacityKbps != null
        ? (peer.dlCapacityKbps! / 1000).toStringAsFixed(0)
        : null;
    final ulMbps = peer.ulCapacityKbps != null
        ? (peer.ulCapacityKbps! / 1000).toStringAsFixed(0)
        : null;
    final linkUptime =
        peer.linkUptimeSec != null ? _formatUptime(peer.linkUptimeSec!) : null;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.radioTower, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('أداء اللنك',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 12),
        // Row 1: DL Capacity | UL Capacity
        IntrinsicHeight(
          child: Row(children: [
            Expanded(
                child: _valueCard(
              icon: LucideIcons.arrowDown,
              label: 'DL Capacity',
              value: dlMbps ?? '—',
              unit: 'Mbps',
              color: AppColors.success,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _valueCard(
              icon: LucideIcons.arrowUp,
              label: 'UL Capacity',
              value: ulMbps ?? '—',
              unit: 'Mbps',
              color: AppColors.brandAccent,
            )),
          ]),
        ),
        const SizedBox(height: 8),
        // Row 2: Distance | Link uptime | Sector
        IntrinsicHeight(
          child: Row(children: [
            Expanded(
                child: _valueCard(
              icon: LucideIcons.mapPin,
              label: 'المسافة',
              value: distanceKm ?? '—',
              unit: 'km',
              color: AppColors.brandAccent,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _valueCard(
              icon: LucideIcons.clock,
              label: 'مدّة اللنك',
              value: linkUptime ?? '—',
              unit: '',
              color: AppColors.textHi,
            )),
            const SizedBox(width: 8),
            Expanded(
                child: _valueCard(
              icon: LucideIcons.compass,
              label: 'Sector',
              value: peer.rxSector != null && peer.txSector != null
                  ? '${peer.rxSector}/${peer.txSector}'
                  : '—',
              unit: '',
              color: AppColors.warning,
            )),
          ]),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 🌡️ System card — CPU/RAM/Uptime
  // ═══════════════════════════════════════════════════════
  Widget _systemCard(UbntStats s) {
    final cpuPercent = s.host.cpuload.toDouble();
    final memPercent = s.memUsedPercent ?? 0;

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.cpu, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('النظام',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
          const Spacer(),
          if (s.host.temperature != 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.thermometer,
                  size: 12, color: _tempColor(s.host.temperature)),
              const SizedBox(width: 2),
              Text('${s.host.temperature}°C',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _tempColor(s.host.temperature))),
            ]),
        ]),
        const SizedBox(height: 12),
        // CPU
        _percentRow(
          icon: LucideIcons.cpu,
          label: 'CPU',
          percent: cpuPercent,
          detail: '${cpuPercent.round()}%',
        ),
        const SizedBox(height: 8),
        // RAM
        if (s.memTotalMb != null && s.memUsedMb != null)
          _percentRow(
            icon: LucideIcons.memoryStick,
            label: 'RAM',
            percent: memPercent,
            detail: '${s.memUsedMb} / ${s.memTotalMb} MB',
          ),
        const SizedBox(height: 8),
        // Uptime
        Row(children: [
          Icon(LucideIcons.timer, size: 14, color: AppColors.textMid),
          const SizedBox(width: 6),
          Text('Uptime',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMid)),
          const Spacer(),
          Text(_formatUptime(s.host.uptime),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
        ]),
      ]),
    );
  }

  Widget _percentRow({
    required IconData icon,
    required String label,
    required double percent,
    required String detail,
  }) {
    final color = _percentColor(percent);
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.textMid),
      const SizedBox(width: 6),
      SizedBox(
        width: 32,
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMid)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 110,
        child: Text(detail,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════
  // 🔌 Ethernet — lanSpeed + real-time RX/TX
  // ═══════════════════════════════════════════════════════
  Widget _ethernetCard(UbntStats s) {
    final eths = s.interfaces.where((i) => i.ifname.startsWith('eth')).toList();
    if (eths.isEmpty) return const SizedBox.shrink();

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.cable, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('Ethernet',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
          const Spacer(),
          if (s.lanSpeed != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(s.lanSpeed!,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success)),
            ),
        ]),
        const SizedBox(height: 8),
        for (final iface in eths) _ethRow(iface),
      ]),
    );
  }

  Widget _ethRow(UbntInterface iface) {
    final rate = _rates[iface.ifname];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iface.plugged ? AppColors.success : AppColors.textLow,
          ),
        ),
        const SizedBox(width: 6),
        Text(iface.ifname,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi)),
        if (iface.speed != null && iface.speed! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('${iface.speed}M',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand)),
          ),
        ],
        const Spacer(),
        if (rate != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.arrowDown, size: 10, color: AppColors.success),
            Text(' ${_formatBps(rate.rxBps)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(width: 8),
            Icon(LucideIcons.arrowUp, size: 10, color: AppColors.brandAccent),
            Text(' ${_formatBps(rate.txBps)}',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
          ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 📍 Location
  // ═══════════════════════════════════════════════════════
  Widget _locationCard(UbntStats s) {
    final lat = s.latitude!.toStringAsFixed(6);
    final lng = s.longitude!.toStringAsFixed(6);
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    return _cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.mapPin, size: 16, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('الموقع',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('$lat, $lng',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text('اضغط لنسخ الإحداثيّات',
                    style: TextStyle(fontSize: 9, color: AppColors.textLow)),
              ])),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '$lat,$lng'));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('نُسخت الإحداثيّات'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: Icon(LucideIcons.copy, size: 16, color: AppColors.textMid),
            tooltip: 'نسخ',
          ),
          IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mapsUrl));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('نُسخ رابط Google Maps'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating));
              }
            },
            icon: Icon(LucideIcons.externalLink,
                size: 16, color: AppColors.brand),
            tooltip: 'نسخ رابط Google Maps',
          ),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ℹ️ Info
  // ═══════════════════════════════════════════════════════
  Widget _infoCard(UbntStats s, UbntStation? peer) {
    final essid = s.wireless?.essid ?? '—';
    // firmware مثل GP.ipq806x.v2.6.8.48409 → نُبرز v2.6.8
    final fw = s.host.fwversion;
    final fwShort = _extractVersion(fw);

    return ExpandableSection(
      key: PageStorageKey('af60-${widget.device.id}-info'),
      initiallyExpanded: true,
      header: Row(children: [
        Icon(LucideIcons.info, size: 16, color: AppColors.brand),
        const SizedBox(width: 6),
        Text('معلومات الجهاز',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi)),
      ]),
      content: Column(children: [
        _infoRow('Platform', s.host.devmodel),
        _infoRow('Firmware', fwShort.isNotEmpty ? fwShort : fw),
        _infoRow('ESSID', essid),
        if (peer != null && peer.mac.isNotEmpty) _infoRow('Peer MAC', peer.mac),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMid)),
        const Spacer(),
        Flexible(
            child: Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════
  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    final hasSpace = value.contains(' ');
    final valueSize = hasSpace ? 15.0 : 18.0;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMid)),
            ]),
            const SizedBox(height: 8),
            Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: valueSize,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1)),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Text(unit,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textLow)),
                  ],
                ]),
          ]),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(children: [
        Icon(LucideIcons.circleAlert, size: 20, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_error ?? 'خطأ',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error))),
        TextButton(onPressed: _fetch, child: const Text('إعادة')),
      ]),
    );
  }

  // ── color/label helpers ─────────────────────────────
  Color _signalColor(int dbm) => Grade.signal(dbm).fill;

  String _signalLabel(int dbm) {
    if (dbm >= -60) return 'ممتازة';
    if (dbm >= -70) return 'جيّدة';
    if (dbm >= -80) return 'مقبولة';
    return 'ضعيفة';
  }

  /// dBm → % — mapping خطّي بين -95 (0%) و -40 (100%).
  /// airFiber 60 عادةً بين -70 و -40 = 45%..100%.
  double _signalPercent(int dbm) {
    if (dbm >= -40) return 100.0;
    if (dbm <= -95) return 0.0;
    return ((dbm + 95) / 55 * 100).clamp(0.0, 100.0);
  }

  Color _snrColor(int snr) => Grade.snr(snr).fill;

  /// SNR → % — mapping خطّي بين 0 (0%) و 40 (100%).
  double _snrPercent(int snr) {
    if (snr >= 40) return 100.0;
    if (snr <= 0) return 0.0;
    return (snr / 40 * 100).clamp(0.0, 100.0);
  }

  String _snrLabel(int snr) {
    if (snr >= 25) return 'ممتاز';
    if (snr >= 15) return 'جيّد';
    if (snr >= 10) return 'مقبول';
    return 'ضعيف';
  }

  Color _tempColor(int t) => Grade.temperature(t).fill;

  Color _percentColor(double p) => Grade.percentHigherBetter(p).fill;

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '—';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatBps(int bps) {
    if (bps < 1000) return '${bps}b';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  String _extractVersion(String fw) {
    // "GP.ipq806x.v2.6.8.48409.251217.1118" → "v2.6.8"
    final m = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(fw);
    return m != null ? 'v${m.group(1)}' : '';
  }
}

// Small arrow used between margin tiles
class _MarginArrow extends StatelessWidget {
  const _MarginArrow();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(LucideIcons.arrowRight, size: 12, color: AppColors.textLow),
    );
  }
}

class _BytesPoint {
  final int rx, tx;
  final DateTime at;
  const _BytesPoint(this.rx, this.tx, this.at);
}

class _IfaceRate {
  final int rxBps, txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}
