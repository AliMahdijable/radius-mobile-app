import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';

/// Panel للمراقبة الحيّة لجهاز UBNT airMax/airFiber.
/// التركيز على **wireless quality** (signal/SNR) لأنه المهم في PtP/PtMP.
class UbntLivePanel extends StatefulWidget {
  final NetworkDevice device;
  /// callback يُطلق مرّة واحدة حين نكتشف من الـstats أن الجهاز فعلاً
  /// airFiber 60 (رغم أن الـdevice.model ما مذكور فيه). الـcaller
  /// (details screen) يستخدمها ليبدّل للـAirFiber60LivePanel.
  /// 2026-08-18.
  final VoidCallback? onAirFiber60Detected;
  const UbntLivePanel({super.key, required this.device, this.onAirFiber60Detected});

  @override
  State<UbntLivePanel> createState() => _UbntLivePanelState();
}

class _UbntLivePanelState extends State<UbntLivePanel> {
  UbntStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  bool _monitoring = false;
  DateTime? _lastFetch;

  // rate tracking للـinterfaces
  final Map<String, _BytesPoint> _lastBytes = {};
  final Map<String, _IfaceRate> _rates = {};

  /// history للـtraffic (أعلى interface بكل جولة) — للـgraph
  /// 30 samples × 15s ≈ 7 دقائق تاريخ. مماثل لـMikrotik.
  final List<_TrafficSample> _history = [];
  static const int _maxHistory = 30;

  /// 2026-08-18: local guard — الـcallback onAirFiber60Detected تُطلق
  /// مرّة واحدة فقط عبر lifecycle الـpanel (بدل كل fetch بعد الاكتشاف).
  bool _af60Notified = false;

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
    setState(() => _loading = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      if (user.isEmpty || pass.isEmpty) {
        throw UbntException('لم يتم إعداد credentials للجهاز');
      }
      // 2026-08-18: partial فقط لأوّل تحميل — refresh لا يستفيد منه لأنّ
      // partial يفرغ stations/interfaces مؤقّتاً → ExpandableSections تختفي
      // → تفقد حالتها (expanded/collapsed) → تُرندَر بالوضع الافتراضي.
      // نفس bug AF60 الي أصلحته سابقاً.
      final isFirstLoad = _stats == null;
      final stats = await UbntApi.fetchStats(
        ip: widget.device.ip,
        port: widget.device.apiPort ?? 22,  // SSH default
        user: user,
        pass: pass,
        // ⚡ Tier 1 partial بعد mca-status (~500ms-1s): CPU/RAM/temp/signal
        // بدل انتظار wstalist + ifconfig + link speeds (~2-3s كامل)
        // ⚠️ **لا** نلمس _lastFetch/_lastBytes هنا (نفس bug Mikrotik السابق —
        // rate calc يستعمل elapsed مغلوط).
        onPartialReady: isFirstLoad ? (partial) {
          if (!mounted) return;
          setState(() {
            _stats = partial;
          });
        } : null,  // ← refresh: تجاهل partial، انتظر البيانات الكاملة
      );
      if (!mounted) return;

      final now = DateTime.now();
      // احسب rates
      if (_lastFetch != null) {
        final elapsed = now.difference(_lastFetch!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          for (final iface in stats.interfaces) {
            final prev = _lastBytes[iface.ifname];
            if (prev != null && iface.rxBytes != null && iface.txBytes != null) {
              final dRx = iface.rxBytes! - prev.rxBytes;
              final dTx = iface.txBytes! - prev.txBytes;
              if (dRx >= 0 && dTx >= 0) {
                _rates[iface.ifname] = _IfaceRate(
                  rxBps: (dRx * 8 / elapsed).round(),
                  txBps: (dTx * 8 / elapsed).round(),
                );
              }
            }
          }
        }
      }
      for (final iface in stats.interfaces) {
        if (iface.rxBytes != null && iface.txBytes != null) {
          _lastBytes[iface.ifname] = _BytesPoint(
            rxBytes: iface.rxBytes!,
            txBytes: iface.txBytes!,
          );
        }
      }
      // 2026-08-18: أضف sample لـtraffic graph — أعلى interface هذه الجولة
      // (نفس نمط Mikrotik). لا نُضيف قبل _lastFetch لأنّ الـrates لسّه 0.
      if (_lastFetch != null) {
        int maxRx = 0, maxTx = 0;
        for (final iface in stats.interfaces.where(_isDataIface)) {
          final r = _rates[iface.ifname];
          if (r != null) {
            if (r.rxBps > maxRx) maxRx = r.rxBps;
            if (r.txBps > maxTx) maxTx = r.txBps;
          }
        }
        _history.add(_TrafficSample(at: now, rxBps: maxRx, txBps: maxTx));
        if (_history.length > _maxHistory) _history.removeAt(0);
      }

      setState(() {
        _stats = stats;
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
      // 2026-08-18: كشف AF60 من الـstats — مرّة واحدة فقط عبر lifecycle.
      // كنا نطلق الـcallback كل fetch (بين إطلاقها وrebuild+dispose، أي
      // fetch جارٍ سيُطلقها ثانية). local flag يمنع الإطلاق المتكرّر.
      if (!_af60Notified &&
          stats.isAirFiber60 &&
          widget.onAirFiber60Detected != null) {
        _af60Notified = true;
        widget.onAirFiber60Detected!();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is UbntException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error == null) {
      return _connectingBox();
    }
    // 2026-08-18: أُعيد بناء البانل بنمط "كل قسم في كارت منفصل" مطابق
    // لـAirFiber60LivePanel + mode-aware ordering:
    //   - PtP link (Station mode): إشارة كبيرة + التركيز على peer واحد
    //   - PtMP AP mode: mode chip + التركيز على قائمة العملاء
    final s = _stats;
    final isAp = s?.isAp ?? false;
    final isStation = s?.isStation ?? false;
    return Column(children: [
      // Header (control bar — pause/refresh/آخر تحديث)
      _cardWrapper(child: _header()),
      if (_error != null) ...[
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _errorBox()),
      ],
      if (s != null) ...[
        // Board banner (airOS / airFiber badge + uptime + mode indicator)
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _boardBanner()),
        // Mode indicator (PtP link / PtMP access point) — 2026-08-18
        if (isAp || isStation) ...[
          const SizedBox(height: Sp.md),
          _cardWrapper(child: _modeIndicator(isAp: isAp)),
        ],
        // System metrics (Uptime / حرارة / CPU)
        const SizedBox(height: Sp.md),
        _cardWrapper(child: _systemMetrics()),
        // Signal hero — لو فيه wireless. حجم أكبر لـPtP (peer link)،
        // أصغر لـPtMP (فيه clients متعدّدين — القسم مو الأهم)
        if (s.wireless != null) ...[
          const SizedBox(height: Sp.md),
          _cardWrapper(child: _signalHero(s.wireless!)),
        ],
        // Traffic graph — widget مستقلّ مع KeepAlive → state ينجو من
        // parent rebuilds (كان يختفي/يعود على كل refresh قبل الإصلاح).
        // ValueKey('ubnt-graph-<id>') يضمن نفس الـState instance عبر builds.
        if (_history.length >= 2) ...[
          const SizedBox(height: Sp.md),
          _TrafficGraphCard(
            key: ValueKey('ubnt-graph-${widget.device.id}'),
            history: List.unmodifiable(_history),
            cardWrapper: _cardWrapper,
          ),
        ],
        // Expandable sections — للـPtMP نُظهر Stations أوّلاً (الأهم)
        ..._buildExpandables(),
      ],
    ]);
  }

  /// شارة تُظهر نمط عمل الجهاز — لينك PtP أم AP PtMP.
  /// 2026-08-18: طلب المستخدم — يريد فرق مرئي واضح بين الاثنين.
  Widget _modeIndicator({required bool isAp}) {
    final color = isAp
        ? const Color(0xFF7C3AED)   // بنفسجي — AP يخدم عملاء
        : const Color(0xFF0891B2);  // فيروزي — لينك PtP
    final icon = isAp ? LucideIcons.radioTower : LucideIcons.arrowLeftRight;
    final title = isAp ? 'نقطة وصول (Access Point)' : 'لينك نقطة-إلى-نقطة (PtP)';
    final subtitle = isAp
        ? 'يخدم عدة عملاء — PtMP'
        : 'اتصال مباشر مع peer واحد';
    final count = isAp && _stats?.stations != null
        ? '${_stats!.stations.length} عميل'
        : null;
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textHi)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: AppColors.textMid)),
          ],
        ),
      ),
      if (count != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(count,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  /// Card wrapper — نفس نمط AirFiber60LivePanel لتوحيد الشكل بين الاثنين.
  /// 2026-08-18.
  Widget _cardWrapper({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  List<Widget> _buildExpandables() {
    final s = _stats!;
    // 2026-08-18: ترتيب حسب نمط الجهاز — PtMP يُظهر Stations أوّلاً
    // (الأهم للـWISP)، PtP يُظهر Wireless details أوّلاً.
    final isAp = s.isAp;
    // 2026-08-18: PageStorageKey — يحفظ حالة expanded عبر rebuilds
    // (وحتى لو موقع القسم في الـColumn تغيّر). أساسي لأنّ refresh قد
    // يُغيّر ترتيب/وجود الأقسام (لكن الحالة تبقى محفوظة).
    final deviceId = widget.device.id;
    final wirelessSection = s.wireless == null ? null : [
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('ubnt-$deviceId-wireless'),
        initiallyExpanded: !isAp,  // AP: مطويّ افتراضياً (المهمّ العملاء)
        header: Row(children: [
          Icon(LucideIcons.wifi, size: 14, color: const Color(0xFF0559C9)),
          const SizedBox(width: 6),
          Text('تفاصيل Wireless',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        content: _wirelessDetails(s.wireless!),
      ),
    ];
    final stationsSection = s.stations.isEmpty ? null : [
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('ubnt-$deviceId-stations'),
        initiallyExpanded: isAp,  // AP: مفتوح افتراضياً
        header: Row(children: [
          Icon(LucideIcons.users, size: 14, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 6),
          Text(
            isAp
                ? 'العملاء المتّصلون (${s.stations.length})'
                : 'الطرف الآخر (peer)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi),
          ),
        ]),
        content: Column(children: [
          for (final st in s.stations.take(20)) _stationRow(st),
          if (s.stations.length > 20)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('+ ${s.stations.length - 20} عميل آخر',
                  style: TextStyle(fontSize: 10, color: AppColors.textLow)),
            ),
        ]),
      ),
    ];
    final ethernetSection = s.interfaces.isEmpty ? null : [
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('ubnt-$deviceId-interfaces'),
        initiallyExpanded: false,  // دائماً مطويّ — معلومات ثانويّة
        header: Row(children: [
          Icon(LucideIcons.network, size: 14, color: const Color(0xFF0559C9)),
          const SizedBox(width: 6),
          Text('Interfaces (${s.interfaces.where(_isDataIface).length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        content: Column(children: [
          for (final iface in s.interfaces.where(_isDataIface))
            _interfaceRow(iface),
        ]),
      ),
    ];
    // ترتيب mode-aware:
    // - PtMP AP: Stations أوّلاً (العملاء = الأهم) ثمّ Wireless ثمّ Ethernet
    // - PtP link: Wireless (peer info) أوّلاً ثمّ Stations (peer الوحيد) ثمّ Ethernet
    return [
      if (isAp) ...[
        if (stationsSection != null) ...stationsSection,
        if (wirelessSection != null) ...wirelessSection,
      ] else ...[
        if (wirelessSection != null) ...wirelessSection,
        if (stationsSection != null) ...stationsSection,
      ],
      if (ethernetSection != null) ...ethernetSection,
    ];
  }

  Widget _connectingBox() {
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
        const SizedBox(width: 10),
        Text('جاري الاتصال بـUBNT…',
            style: TextStyle(fontSize: 12, color: AppColors.textMid)),
      ]),
    );
  }

  Widget _header() {
    // 2026-08-18: أُزيل الـPadding — الآن _cardWrapper يهتمّ بالـpadding
    return Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF0559C9).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.radioTower, size: 16, color: const Color(0xFF0559C9)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة (UBNT via SSH)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
            const SizedBox(height: 2),
            Row(children: [
              if (_monitoring) ...[
                // 2026-08-18: opacity pulse بدل استبدال النصّ بـ"جاري التحديث…"
                // — لتفادي ظهور الجهاز كأنّه فُصل ورجع عند كل fetch
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _loading ? 0.35 : 1.0,
                  child: Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                _monitoring
                    ? 'مباشر · كل ${_refreshInterval.inSeconds}s'
                    : 'متوقّف',
                style: TextStyle(fontSize: 10, color: AppColors.textMid),
              ),
            ]),
          ]),
        ),
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          onPressed: _loading ? null : _fetch,
          color: const Color(0xFF0559C9),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play, size: 16,
              color: _monitoring ? AppColors.error : const Color(0xFF10B981)),
          onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
          visualDensity: VisualDensity.compact,
        ),
      ]);
  }

  Widget _errorBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!,
            style: TextStyle(fontSize: 11, color: AppColors.error, height: 1.4))),
      ]),
    );
  }

  Widget _boardBanner() {
    final h = _stats!.host;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0559C9).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(LucideIcons.radioTower, size: 14, color: const Color(0xFF0559C9)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${h.devmodel} • airOS ${h.fwversion}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textHi),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0559C9).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.clock, size: 9, color: const Color(0xFF0559C9)),
            const SizedBox(width: 3),
            Text(_formatUptime(h.uptime),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: const Color(0xFF0559C9))),
          ]),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // System metrics — CPU / RAM / Temperature (لو متوفّرة)
  // ══════════════════════════════════════════════════════════════
  Widget _systemMetrics() {
    final h = _stats!.host;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _percentCard(
            icon: LucideIcons.cpu, label: 'CPU',
            percent: h.cpuload.toDouble(),
          )),
          const SizedBox(width: 8),
          Expanded(child: _valueCard(
            icon: LucideIcons.thermometer,
            label: 'حرارة',
            value: h.temperature > 0 ? '${h.temperature}' : '—',
            unit: h.temperature > 0 ? '°C' : '',
            color: _tempColor(h.temperature),
          )),
          const SizedBox(width: 8),
          Expanded(child: _valueCard(
            icon: LucideIcons.clock,
            label: 'Uptime',
            value: h.uptime > 0 ? _formatUptime(h.uptime) : '—',
            unit: '',  // نضم كل النصّ في value بحجم موحّد
            color: const Color(0xFF0559C9),
          )),
        ],
      ),
    );
  }

  Widget _percentCard({
    required IconData icon,
    required String label,
    required double percent,
  }) {
    final color = _percentGradeColor(percent);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${percent.round()}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppColors.textHi, height: 1)),
            const SizedBox(width: 2),
            Text('%', style: TextStyle(fontSize: 10, color: AppColors.textLow)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    // إذا القيمة تحتوي مسافة (مثل "4d 1h") نُصغّرها قليلاً لتتّسع
    final hasSpace = value.contains(' ');
    final valueSize = hasSpace ? 15.0 : 18.0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w800,
                      color: value == '—' ? AppColors.textLow : color,
                      height: 1)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: TextStyle(fontSize: 11, color: AppColors.textLow)),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Color _percentGradeColor(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  Color _tempColor(int t) {
    if (t <= 0) return AppColors.textLow;
    if (t >= 75) return AppColors.error;
    if (t >= 60) return const Color(0xFFF59E0B);
    if (t >= 45) return const Color(0xFF06B6D4);
    return const Color(0xFF10B981);
  }

  // ══════════════════════════════════════════════════════════════
  // Signal Hero — النجم! semi-circular gauge بلوّن حسب جودة الإشارة
  // ══════════════════════════════════════════════════════════════
  Widget _signalHero(UbntWireless w) {
    final signalColor = _signalColor(w.signal);
    return Container(
        padding: const EdgeInsets.all(Sp.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              signalColor.withValues(alpha: 0.08),
              signalColor.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: signalColor.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(children: [
          // Gauge on the right — RepaintBoundary لعزل الـCustomPaint (rebuild
          // كل fetch كان يُعيد رسم الـpainter → jank بسيط لكن ملحوظ)
          SizedBox(
            width: 120, height: 90,
            child: RepaintBoundary(child: CustomPaint(
              painter: _SignalGaugePainter(
                percent: w.signalQualityPercent,
                color: signalColor,
                background: AppColors.border,
              ),
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${w.signal}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
                          color: signalColor, height: 1)),
                  const SizedBox(height: 2),
                  Text('dBm',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.textMid)),
                ]),
              ),
            )),
          ),
          const SizedBox(width: 16),
          // Details on the left
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('جودة الإشارة',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text(_signalLabel(w.signal),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: signalColor, height: 1.1)),
              const SizedBox(height: 10),
              _metric('SNR',
                  w.snr != null ? '${w.snr}' : '—',
                  w.snr != null ? 'dB' : '',
                  color: w.snr != null ? _snrColor(w.snr!) : AppColors.textLow),
              const SizedBox(height: 4),
              _metric('Noise',
                  w.hasNoise ? '${w.noise}' : '—',
                  w.hasNoise ? 'dBm' : '',
                  color: w.hasNoise ? AppColors.textMid : AppColors.textLow),
              const SizedBox(height: 4),
              _metric('CCQ',
                  w.hasCcq ? '${w.ccq}' : '—',
                  w.hasCcq ? '%' : '',
                  color: w.hasCcq ? _percentColor(w.ccq.toDouble()) : AppColors.textLow),
            ]),
          ),
        ]),
      );
  }

  Widget _metric(String label, String value, String unit, {required Color color}) {
    return Row(children: [
      SizedBox(width: 42,
        child: Text(label,
            style: TextStyle(fontSize: 10, color: AppColors.textLow))),
      Text(value,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
              color: color)),
      const SizedBox(width: 2),
      Text(unit, style: TextStyle(fontSize: 9, color: AppColors.textLow)),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // Wireless details section
  // ══════════════════════════════════════════════════════════════
  Widget _wirelessDetails(UbntWireless w) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _detailRow(LucideIcons.wifi, 'ESSID', w.essid.isEmpty ? '—' : w.essid),
          _detailRow(LucideIcons.radioTower, 'الوضع', _modeLabel(w.mode)),
          Row(children: [
            Expanded(
              child: _detailRow(LucideIcons.arrowDown, 'RX',
                  '${w.rxRate}', suffix: 'Mbps', color: const Color(0xFF10B981)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailRow(LucideIcons.arrowUp, 'TX',
                  '${w.txRate}', suffix: 'Mbps', color: const Color(0xFF3B82F6)),
            ),
          ]),
          _detailRow(LucideIcons.satellite, 'التردد',
              '${w.frequency} MHz${w.chanbw > 0 ? " (${w.chanbw}MHz)" : ""}${w.channel > 0 ? " • ch ${w.channel}" : ""}'),
          if (w.distance > 0)
            _detailRow(LucideIcons.mapPin, 'المسافة',
                w.distance >= 1000 ? '${(w.distance / 1000).toStringAsFixed(1)}km' : '${w.distance}m'),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {String? suffix, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 12, color: color ?? AppColors.textLow),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMid)),
        const Spacer(),
        Text(value,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: color ?? AppColors.textHi)),
        if (suffix != null) ...[
          const SizedBox(width: 3),
          Text(suffix, style: TextStyle(fontSize: 9, color: AppColors.textLow)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Interfaces section
  // ══════════════════════════════════════════════════════════════
  Widget _interfacesSection() {
    final ethers = _stats!.interfaces.where(_isDataIface).toList();
    if (ethers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.network, size: 14, color: const Color(0xFF0559C9)),
          const SizedBox(width: 6),
          Text('Ethernet (${ethers.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        for (final iface in ethers) _interfaceRow(iface),
      ]),
    );
  }

  Widget _interfaceRow(UbntInterface iface) {
    final rate = _rates[iface.ifname];
    final up = iface.plugged && iface.enabled;
    final color = up ? const Color(0xFF10B981) : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(up ? LucideIcons.arrowUp : LucideIcons.arrowDown, size: 12, color: color),
        const SizedBox(width: 6),
        Text(iface.ifname,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.textHi)),
        if (iface.speed != null && up) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: _speedColor(iface.speed!).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_speedLabel(iface.speed!),
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _speedColor(iface.speed!))),
          ),
        ],
        const Spacer(),
        if (rate != null) ...[
          Icon(LucideIcons.arrowDown, size: 9, color: const Color(0xFF10B981)),
          const SizedBox(width: 2),
          Text(_formatBps(rate.rxBps),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
          const SizedBox(width: 8),
          Icon(LucideIcons.arrowUp, size: 9, color: const Color(0xFF3B82F6)),
          const SizedBox(width: 2),
          Text(_formatBps(rate.txBps),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppColors.textHi)),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Stations section (لو AP mode)
  // ══════════════════════════════════════════════════════════════
  Widget _stationsSection() {
    final ss = _stats!.stations;
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.users, size: 14, color: const Color(0xFF0559C9)),
          const SizedBox(width: 6),
          Text('العملاء المتّصلون (${ss.length})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textHi)),
        ]),
        const SizedBox(height: 8),
        for (final s in ss.take(20)) _stationRow(s),
        if (ss.length > 20)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+ ${ss.length - 20} عميل آخر',
                style: TextStyle(fontSize: 10, color: AppColors.textLow)),
          ),
      ]),
    );
  }

  Widget _stationRow(UbntStation s) {
    final signalColor = _signalColor(s.signal);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Container(
          width: 4, height: 30, decoration: BoxDecoration(
            color: signalColor, borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.hostname ?? s.ip ?? s.mac,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textHi),
                overflow: TextOverflow.ellipsis),
            if (s.ip != null || s.mac.isNotEmpty)
              Text([s.ip, s.mac].where((e) => e != null && e.isNotEmpty).join(' • '),
                  style: TextStyle(fontSize: 9, color: AppColors.textLow),
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${s.signalDisplay} dBm',
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: signalColor)),
            if (s.ccq > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _percentColor(s.ccq.toDouble()).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${s.ccq}%',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                        color: _percentColor(s.ccq.toDouble()))),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text('↓${s.rxRate} / ↑${s.txRate} Mbps',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 9, color: AppColors.textMid)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════
  Color _signalColor(int dbm) {
    if (dbm >= -60) return const Color(0xFF10B981);
    if (dbm >= -70) return const Color(0xFF06B6D4);
    if (dbm >= -80) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  String _signalLabel(int dbm) {
    if (dbm >= -60) return 'ممتازة';
    if (dbm >= -70) return 'جيّدة';
    if (dbm >= -80) return 'مقبولة';
    return 'ضعيفة';
  }

  Color _snrColor(int snr) {
    if (snr >= 30) return const Color(0xFF10B981);
    if (snr >= 20) return const Color(0xFF06B6D4);
    if (snr >= 15) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _percentColor(double p) {
    if (p >= 80) return const Color(0xFF10B981);
    if (p >= 50) return const Color(0xFF06B6D4);
    if (p >= 30) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  Color _speedColor(int mbps) {
    if (mbps >= 1000) return const Color(0xFF10B981);
    if (mbps >= 100) return const Color(0xFF06B6D4);
    if (mbps >= 10) return const Color(0xFFF59E0B);
    return AppColors.error;
  }

  String _speedLabel(int mbps) {
    if (mbps >= 1000) return '${mbps ~/ 1000}G';
    return '${mbps}M';
  }

  String _modeLabel(String m) => switch (m) {
        'ap-ptp' => 'Access Point • PtP',
        'sta-ptp' => 'Station • PtP',
        'ap-ptmp' => 'Access Point • PtMP',
        'sta-ptmp' => 'Station • PtMP',
        _ => m.isEmpty ? '—' : m,
      };

  String _formatUptime(int seconds) {
    if (seconds <= 0) return '—';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    if (days > 7) {
      final weeks = days ~/ 7;
      return '${weeks}w ${days % 7}d';
    }
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  /// 2026-08-18: أي واجهة تحمل بيانات فعليّة (تظهر بالـUI + traffic
  /// يُحسَب لها). كان الفلتر السابق `startsWith('eth')` يستثني br0/wlan0
  /// الي أحياناً تكون الواجهة الوحيدة على airFiber 60 GP → traffic ما يظهر.
  static bool _isDataIface(UbntInterface i) {
    final n = i.ifname;
    if (n.startsWith('eth')) return true;
    if (n.startsWith('br')) return true;   // bridge (airFiber 60)
    if (n.startsWith('wlan') || n.startsWith('ath')) return true;  // wireless
    if (n == 'ppp0' || n == 'wan') return true;
    return false;
  }
}

// ══════════════════════════════════════════════════════════════
// Signal Gauge Painter — semi-circular arc مع لون متدرّج
// ══════════════════════════════════════════════════════════════
class _SignalGaugePainter extends CustomPainter {
  final double percent;      // 0..100
  final Color color;
  final Color background;
  _SignalGaugePainter({required this.percent, required this.color, required this.background});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.88);
    final radius = math.min(size.width / 2 - 6, size.height * 0.85);
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // background arc
    final bgPaint = Paint()
      ..color = background.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false, bgPaint,
    );

    // foreground arc based on percent
    final fgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withValues(alpha: 0.4), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final sweep = (percent / 100).clamp(0.0, 1.0) * sweepAngle;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweep, false, fgPaint,
    );

    // scale ticks
    final tickPaint = Paint()
      ..color = background.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final angle = startAngle + (sweepAngle * i / 4);
      final outer = Offset(
        center.dx + math.cos(angle) * (radius + 4),
        center.dy + math.sin(angle) * (radius + 4),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - 4),
        center.dy + math.sin(angle) * (radius - 4),
      );
      canvas.drawLine(outer, inner, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalGaugePainter old) =>
      old.percent != percent || old.color != color;
}

class _BytesPoint {
  final int rxBytes;
  final int txBytes;
  const _BytesPoint({required this.rxBytes, required this.txBytes});
}

class _IfaceRate {
  final int rxBps;
  final int txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}

/// عيّنة traffic لحظة واحدة — أعلى interface بها. 2026-08-18.
class _TrafficSample {
  final DateTime at;
  final int rxBps;
  final int txBps;
  const _TrafficSample({required this.at, required this.rxBps, required this.txBps});
}

/// كارت traffic graph مستقلّ — StatefulWidget مع KeepAlive لضمان أن
/// الـchart ينجو من parent rebuilds ولا يختفي/يتومض على كل refresh.
/// يستقبل history + cardWrapper من الـparent كـcallbacks.
/// 2026-08-18.
class _TrafficGraphCard extends StatefulWidget {
  final List<_TrafficSample> history;
  final Widget Function({required Widget child}) cardWrapper;

  const _TrafficGraphCard({
    super.key,
    required this.history,
    required this.cardWrapper,
  });

  @override
  State<_TrafficGraphCard> createState() => _TrafficGraphCardState();
}

class _TrafficGraphCardState extends State<_TrafficGraphCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;   // ينجو من ListView/Column rebuilds

  @override
  Widget build(BuildContext context) {
    super.build(context);   // مطلوب لـAutomaticKeepAlive
    final history = widget.history;
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (int i = 0; i < history.length; i++) {
      final x = i.toDouble();
      rxSpots.add(FlSpot(x, history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(x, history[i].txBps.toDouble()));
    }
    final maxRx = history.map((s) => s.rxBps).fold<int>(0, math.max);
    final maxTx = history.map((s) => s.txBps).fold<int>(0, math.max);
    final peak = math.max(maxRx, maxTx);
    final maxY = (peak * 1.25).clamp(1000, double.infinity).toDouble();

    final lastRx = history.isNotEmpty ? history.last.rxBps : 0;
    final lastTx = history.isNotEmpty ? history.last.txBps : 0;

    const rxColor = Color(0xFF10B981);
    const txColor = Color(0xFF3B82F6);

    return widget.cardWrapper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: 14, color: const Color(0xFF0559C9)),
          const SizedBox(width: 6),
          Text('أعلى interface (سير الترفك)',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHi)),
          const Spacer(),
          _legendChip('↓', _formatBps(lastRx), rxColor),
          const SizedBox(width: 6),
          _legendChip('↑', _formatBps(lastTx), txColor),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: RepaintBoundary(child: LineChart(
            duration: Duration.zero,   // لا animation → لا وميض
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border.withValues(alpha: 0.35),
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: maxY / 3,
                    getTitlesWidget: (value, _) => Text(
                      _formatBpsShort(value.toInt()),
                      style: TextStyle(fontSize: 9, color: AppColors.textLow),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: (history.length - 1).toDouble(),
              lineBarsData: [
                _lineBarData(txSpots, txColor),
                _lineBarData(rxSpots, rxColor),
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.textHi.withValues(alpha: 0.9),
                  getTooltipItems: (spots) => spots.map((s) {
                    final isTx = s.barIndex == 0;
                    return LineTooltipItem(
                      '${isTx ? "↑" : "↓"} ${_formatBps(s.y.toInt())}',
                      TextStyle(
                        color: isTx ? txColor : rxColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          )),
        ),
      ]),
    );
  }

  LineChartBarData _lineBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.28,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.02),
          ],
        ),
      ),
    );
  }

  Widget _legendChip(String arrow, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$arrow $value',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }

  String _formatBpsShort(int bps) {
    if (bps < 1000) return '0';
    if (bps < 1000000) return '${(bps / 1000).round()}K';
    if (bps < 1000000000) return '${(bps / 1000000).round()}M';
    return '${(bps / 1000000000).toStringAsFixed(1)}G';
  }
}
