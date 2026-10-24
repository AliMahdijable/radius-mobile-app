import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/mikrotik_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'expandable_section.dart';
import '_grade.dart';
import '../../../theme/typography.dart';
import '../detected_model.dart';
import '../../../core/util/error_text.dart';
import '../../desktop/desk_widgets.dart';
import '../../../core/widgets/copyable.dart';
import '../../../core/platform/desktop_layout.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';

/// Panel للمراقبة الحيّة لجهاز Mikrotik.
/// - Auto-start عند فتح الصفحة (لا يحتاج المستخدم يضغط "بدء")
/// - CPU / RAM / أعلى interface throughput
/// - رسم بياني للـtraffic الإجمالي (RX + TX) آخر ~15 دقيقة
/// - قسم البريدجات (إن وُجدت): ترافيك كلّ بريدج ومنافذه، الأعلى أوّلاً
/// - قائمة interfaces من نوع ether/sfp (بدون pppoe/vlan)، وكلّ منفذٍ عضوٍ يحمل اسم بريدجه
/// - كل ether يظهر مع سرعة RX/TX حاليّة
/// - «الأعلى» (البطاقتان والرسم) من البريدجات والإيثر معاً — البريدج يجمع منافذه فيتصدّر غالباً
class MikrotikLivePanel extends StatefulWidget {
  final NetworkDevice device;
  const MikrotikLivePanel({super.key, required this.device});

  @override
  State<MikrotikLivePanel> createState() => _MikrotikLivePanelState();
}

class _MikrotikLivePanelState extends State<MikrotikLivePanel> {
  MikrotikStats? _stats;
  bool _loading = false;
  String? _error;
  Timer? _timer;
  Timer? _bootstrapT1, _bootstrapT2; // fast-bootstrap timers — لازم dispose
  bool _monitoring = false;
  DateTime? _lastFetch;

  /// آخر قيمة bytes لكل interface (لحساب rate من delta)
  final Map<String, _BytesPoint> _lastBytes = {};

  /// السرعات الحاليّة (bps) لكل interface — تُحسب بعد الـfetch الثاني
  final Map<String, _IfaceRate> _rates = {};

  /// history للـtraffic الإجمالي — للرسم البياني
  final List<_TrafficSample> _history = [];
  static const int _maxHistory = 30; // 30 × 8s ≈ 4 دقائق history

  /// 2026-08-20: sticky snapshot لآخر مجموعة عملاء غير فارغة. عند refresh
  /// إذا reg-table returned empty (glitch، permission، timeout عابر)،
  /// نعرض آخر لقطة معروفة بدل ما نُخفي القسم كلياً — يمنع "الوميض" الذي
  /// كان يجعل المستخدم يشوف الأجهزة تختفي وترجع كل refresh cycle.
  List<MikrotikWirelessClient> _stickyClients = const [];
  // 8s cadence (بدل 15s) — user requested أسرع تحديث. Progressive rendering
  // يعطي partial في 500ms، لكن refresh cycle نفسه صار أسرع.
  static const _refreshInterval = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    // ── بذرةٌ من المخزن ────────────────────────────────────────────
    //
    // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «بكلّ جهاز أنقر عليه لازم يعيد إرسال الطلب،
    // وهذا مزعج. هو كلّهن طلب واحد، مفروض يجلب كلّ المعلومات ويبقى
    // يحافظها — وقت ما أنقر على الكارت تطلع لي».
    //
    // «نظرة عامّة» فتحت جلسةً لهذا الجهاز قبل قليل وحفظت حمولتها.
    // نعرضها فوراً ثمّ نُحدّث في الخلفيّة — فالنقر يُظهر بيانات لا
    // دوّاراً، والجلسة الثانية تصحّح ما شاخ منها.
    //
    // والنوع مفحوص داخل المخزن: جهازٌ غُيّرت علامته يحمل حمولةً من
    // النوع القديم، وبذرُها هنا ترمي.
    _stats = DeviceStatsCache.instance.seedFor<MikrotikStats>(widget.device.id);
    // ⚠️ وعمرُها الحقيقيّ معها.
    //
    // 🐛 تحذير المستخدم ٢٠٢٦-٠٩-٠٢: «المعلومات الحيّة ما تتغيّر، تبقى
    // ثابتة». والبذرة لقطةٌ قد يبلغ عمرها دقيقتين، وكانت تُعرض تحت
    // شارة «مباشر» كأنّها الآن.
    //
    // فنُورّث لحظتَها لا لحظتنا: الشارة تقول «قبل ٤٥ث» صادقةً، ثمّ
    // تهبط إلى «قبل ٠ث» حين يصل جلبُنا بعد جزءٍ من الثانية.
    // رقمٌ قديمٌ **معلومُ القِدَم** أمانة؛ ومعروضٌ كأنّه الآن كذبة.
    final seedAge = DeviceStatsCache.instance.ageOf(widget.device.id);
    if (_stats != null && seedAge != null) {
      _lastFetch = DateTime.now().subtract(seedAge);
    }
    _startMonitoring();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bootstrapT1?.cancel();
    _bootstrapT2?.cancel();
    super.dispose();
  }

  Future<void> _startMonitoring() async {
    setState(() => _monitoring = true);
    // fetch أوّل — baseline (bytes counters بلا rates)
    await _fetch();
    // Fast bootstrap: fetch سريع بعد 2s ثمّ آخر بعد 5s — يعطي:
    //   t=0:  baseline
    //   t=2:  أوّل rate → history 1 sample
    //   t=5:  ثاني rate → history 2 samples → **الرسم البياني يظهر**
    //   t=15: عادي (تلقائياً من _timer)
    // بدون هذا: الرسم ينتظر 15s + 15s = 30s قبل ما يبان.
    _bootstrapT1?.cancel();
    _bootstrapT2?.cancel();
    _bootstrapT1 = Timer(const Duration(seconds: 2), () {
      if (mounted && _monitoring) _fetch();
    });
    _bootstrapT2 = Timer(const Duration(seconds: 5), () {
      if (mounted && _monitoring) _fetch();
    });
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
  }

  void _stopMonitoring() {
    _timer?.cancel();
    setState(() {
      _monitoring = false;
    });
  }

  Future<void> _fetch() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(widget.device.id);
      final user = (creds['user'] ?? '').toString();
      final pass = (creds['pass'] ?? '').toString();
      if (user.isEmpty || pass.isEmpty) {
        throw MikrotikException('لم يتم إعداد credentials للجهاز');
      }
      // 2026-08-18: partial فقط لأوّل تحميل — refresh لا يستفيد منه
      // (partial بلا interfaces/wireless مؤقّتاً → ExpandableSections تختفي
      // → تفقد state (expanded/collapsed)). نفس bug UBNT + AF60 المُصلَح.
      final isFirstLoad = _stats == null;
      final stats = await MikrotikApi.fetchStats(
        ip: widget.device.ip,
        port: widget.device.apiPort ?? 8728,
        user: user,
        pass: pass,
        // ⚡ عرض جزئي فوري — CPU/RAM/interfaces تظهر بعد ~500ms
        // بدل انتظار كل شيء (~2-3s)
        //
        // ⚠️ مهم جداً: **لا** نلمس _lastFetch أو _lastBytes هنا!
        // (bug 2026-08-13: كنّا نضبط _lastFetch في callback → rate calc
        // للـfetch النهائي كان يستعمل elapsed = 500ms بدل 15s الحقيقيّة
        // → 30× overestimate → ether1 يظهر 4.10Gbps بدل 130Mbps!)
        //
        // Rate calculation يبقى فقط في المكان الي بعد الـawait (النهائي)
        // — يستعمل _lastFetch الصحيح من fetch السابق.
        onPartialReady: isFirstLoad
            ? (partial) {
                if (!mounted) return;
                setState(() {
                  _stats = partial;
                });
              }
            : null,
      );
      if (!mounted) return;

      final now = DateTime.now();
      // احسب السرعات من الفارق مع الـfetch السابق
      if (_lastFetch != null) {
        final elapsed = now.difference(_lastFetch!).inMilliseconds / 1000.0;
        if (elapsed > 0) {
          for (final iface in stats.interfaces) {
            final prev = _lastBytes[iface.name];
            if (prev != null &&
                iface.rxBytes != null &&
                iface.txBytes != null) {
              final dRx = iface.rxBytes! - prev.rxBytes;
              final dTx = iface.txBytes! - prev.txBytes;
              if (dRx >= 0 && dTx >= 0) {
                final rxBps = (dRx * 8 / elapsed).round();
                final txBps = (dTx * 8 / elapsed).round();
                // Safety cap: أي رقم > 10Gbps = خطأ (لا يوجد راوتر Mikrotik
                // يتجاوز 10G على واجهة واحدة). نتجاهله بدل عرض قراءة مضلّلة.
                const maxSaneBps = 10000000000; // 10 Gbps
                if (rxBps <= maxSaneBps && txBps <= maxSaneBps) {
                  _rates[iface.name] = _IfaceRate(rxBps: rxBps, txBps: txBps);
                }
              }
            }
            if (iface.rxBytes != null && iface.txBytes != null) {
              _lastBytes[iface.name] = _BytesPoint(
                rxBytes: iface.rxBytes!,
                txBytes: iface.txBytes!,
                at: now,
              );
            }
          }
        }
      } else {
        // أوّل fetch — نحفظ البيانات فقط للفارق التالي
        for (final iface in stats.interfaces) {
          if (iface.rxBytes != null && iface.txBytes != null) {
            _lastBytes[iface.name] = _BytesPoint(
              rxBytes: iface.rxBytes!,
              txBytes: iface.txBytes!,
              at: now,
            );
          }
        }
      }

      // نحسب **أعلى interface** بدل المجموع — عشان الكراف يُطابق كروت
      // "أعلى iface ↓" و "أعلى iface ↑" اللي فوق (طلب المستخدم 2026-08-14).
      // كل سامبل يحمل max rx + max tx عند تلك اللحظة (من أي ether/sfp أو بريدج).
      int maxRxSampleBps = 0, maxTxSampleBps = 0;
      for (final iface in stats.interfaces) {
        if (!_isHeadline(iface)) continue;
        final rate = _rates[iface.name];
        if (rate != null) {
          if (rate.rxBps > maxRxSampleBps) maxRxSampleBps = rate.rxBps;
          if (rate.txBps > maxTxSampleBps) maxTxSampleBps = rate.txBps;
        }
      }
      if (_lastFetch != null) {
        _history.add(_TrafficSample(
            at: now, rxBps: maxRxSampleBps, txBps: maxTxSampleBps));
        if (_history.length > _maxHistory) _history.removeAt(0);
      }

      // 2026-08-20: حدّث sticky snapshot فقط لو رجعت clients فعلاً. لو
      // reg-table فارغ (glitch عابر)، الـUI يبقى يعرض آخر لقطة معروفة
      // بدل ما القسم يختفي. الحالة الوحيدة الي نصفّر فيها: interfaces
      // نفسها اختفت (الجهاز ما عاد AP).
      final freshClients = stats.wirelessClients;
      final noWirelessIfaces = stats.wirelessInterfaces.isEmpty;
      final nextSticky = noWirelessIfaces
          ? const <MikrotikWirelessClient>[]
          : (freshClients.isNotEmpty ? freshClients : _stickyClients);

      setState(() {
        _stats = stats;
        DeviceStatsCache.instance.putRaw(widget.device.id, stats);
        _stickyClients = nextSticky;
        _loading = false;
        _error = null;
        _lastFetch = now;
      });
      // الموديل من الجهاز نفسه — `board-name` أدقّ ممّا يُكتب يدويّاً،
      // وعليه تُطابَق صورة الجهاز في القائمة.
      DetectedModel.save(widget.device, stats.boardName);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is MikrotikException ? e.message : humanError(e);
        _loading = false;
      });
    }
  }

  bool _isEther(MikrotikInterface i) => i.type == 'ether' || i.type == 'sfp';

  bool _isBridge(MikrotikInterface i) => i.type == 'bridge' && !i.disabled;

  /// مصدر «الأعلى» (البطاقتان والرسم): البريدجات ثمّ الإيثر. البريدج مجموعة منافذ فترافيكه الأعلى
  /// غالباً — وعند التساوي يتقدّم (طلب المستخدم ١٨ أكتوبر: «الترافيك الأعلى أولويّة إن وُجد بريدج»).
  bool _isHeadline(MikrotikInterface i) => _isBridge(i) || _isEther(i);

  List<MikrotikInterface> _headlinePool() => [
        ...(_stats?.interfaces ?? []).where(_isBridge),
        ...(_stats?.interfaces ?? []).where(_isEther),
      ];

  int _trafficOf(MikrotikInterface i) {
    final r = _rates[i.name];
    return r == null ? 0 : r.rxBps + r.txBps;
  }

  /// أعلى interface بالـRX (download) — منفصل عن الـTX
  ({String name, int bps})? _maxRxIface() {
    ({String name, int bps})? best;
    for (final i in _headlinePool()) {
      final r = _rates[i.name];
      if (r == null) continue;
      if (best == null || r.rxBps > best.bps) {
        best = (name: i.name, bps: r.rxBps);
      }
    }
    return best;
  }

  /// أعلى interface بالـTX (upload) — منفصل عن الـRX
  ({String name, int bps})? _maxTxIface() {
    ({String name, int bps})? best;
    for (final i in _headlinePool()) {
      final r = _rates[i.name];
      if (r == null) continue;
      if (best == null || r.txBps > best.bps) {
        best = (name: i.name, bps: r.txBps);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    if (_stats == null && _error == null) {
      return Container(
        padding: const EdgeInsets.all(Sp.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.brand)),
            const SizedBox(width: 10),
            Text('جاري الاتصال بـMikrotik…',
                style: AppType.body(color: AppColors.textMid)),
          ]),
        ]),
      );
    }

    return Column(children: [
      // Main card: header + metrics + graph (دائماً ظاهر)
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _header(),
          if (_error != null) _errorBox(),
          if (_stats != null) ...[
            // RepaintBoundary لكل section — كل قسم يُرسم مستقلاً بلا rebuild
            // للـchart (الأثقل بصرياً) عند تحديث القيم فقط
            RepaintBoundary(child: _desk ? _deskBoardBanner() : _boardBanner()),
            RepaintBoundary(child: _metricsRow()),
            // الحاسبة: مكان الرسم محجوزٌ من البداية (رسالة «تُجمع القراءات») فلا تقفز الصفحة حين يظهر.
            if (_desk || _history.length >= 2) ...[
              const SizedBox(height: 4),
              _trafficGraph(), // فيه RepaintBoundary داخلياً
            ],
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      // Expandable sections (تُطوى/تُفتح)
      if (_stats != null) ..._buildExpandables(),
    ]);
  }

  List<Widget> _buildExpandables() {
    if (_desk) return _deskExpandables();
    final s = _stats!;
    final ethers = s.interfaces.where(_isEther).toList();
    // البريدجات: الأعلى ترافيكاً أوّلاً (طلب المستخدم ١٨ أكتوبر).
    final bridges = s.interfaces.where(_isBridge).toList()
      ..sort((a, b) => _trafficOf(b).compareTo(_trafficOf(a)));
    return [
      if (bridges.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('mikrotik-${widget.device.id}-bridge'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.layers, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Bridges (${bridges.length})', style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(child: _bridgesContent(bridges, s)),
        ),
      ],
      // 2026-08-18: PageStorageKey يحفظ expanded عبر rebuilds
      if (ethers.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('mikrotik-${widget.device.id}-eth'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.network, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Ethernet Interfaces (${ethers.length})',
                style: AppType.bodyBold()),
          ]),
          // RepaintBoundary → عزل الـinterface list عن باقي rebuilds
          content: RepaintBoundary(child: _interfacesContent(ethers)),
        ),
      ],
      if (s.hasWireless) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('mikrotik-${widget.device.id}-wifi'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.wifi, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('Wireless (${s.wirelessInterfaces.length})',
                style: AppType.bodyBold()),
          ]),
          content: DeskRows(children: [
            for (final w in s.wirelessInterfaces) _wirelessCard(w),
          ]),
        ),
      ],
      // 2026-08-20: القسم يظهر دائماً لأي جهاز AP (حتى لو صفر عملاء).
      // كان يختفي كلياً عند empty → المستخدم يظنّ "الاستعلام مكسور" —
      // بينما الحقيقة قد تكون AP بدون عملاء أو الاستعلام رجع فارغ.
      // نُميّز بينهما بنص واضح داخل القسم.
      if (s.isAccessPoint) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('mikrotik-${widget.device.id}-clients'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.users, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('العملاء المتّصلون (${_stickyClients.length})',
                style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(
            child: _stickyClients.isEmpty
                ? _emptyClientsHint()
                : _clientsContent(_stickyClients),
          ),
        ),
      ],
    ];
  }

  Widget _interfacesContent(List<MikrotikInterface> ethers) {
    int maxRate = 0;
    for (final iface in ethers) {
      final r = _rates[iface.name];
      if (r != null) maxRate = math.max(maxRate, math.max(r.rxBps, r.txBps));
    }
    final s = _stats;
    return DeskRows(children: [
      for (final iface in ethers)
        _interfaceRow(iface, maxRate, bridgeTag: s?.bridgeOf(iface.name)),
    ]);
  }

  /// كلّ بريدج: ترافيكه + منافذه (ملوّنةً بحالتها). الشريط نسبيّ لأعلى بريدج.
  Widget _bridgesContent(List<MikrotikInterface> bridges, MikrotikStats s) {
    int maxRate = 0;
    for (final b in bridges) {
      final r = _rates[b.name];
      if (r != null) maxRate = math.max(maxRate, math.max(r.rxBps, r.txBps));
    }
    final byName = {for (final i in s.interfaces) i.name: i};
    return DeskRows(children: [
      for (final b in bridges)
        _interfaceRow(b, maxRate,
            members: [
              for (final p in s.bridgePorts[b.name] ?? const <String>[])
                (name: p, iface: byName[p]),
            ]),
    ]);
  }

  Widget _memberChips(List<({String name, MikrotikInterface? iface})> members) {
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final m in members)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: m.iface == null || m.iface!.disabled
                    ? AppColors.textLow
                    : (m.iface!.running ? AppColors.success : AppColors.error),
              ),
            ),
            const SizedBox(width: 4),
            Text(m.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textMid)),
          ]),
        ),
    ]);
  }

  /// 2026-08-20: state فارغ للـclients section — يميّز بين "AP بلا عملاء"
  /// و"استعلام فشل". الأخير سيظهر أيضاً في banner الأحمر بأعلى الصفحة.
  Widget _emptyClientsHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(LucideIcons.userX,
              size: 22, color: AppColors.textLow.withValues(alpha: 0.6)),
          const SizedBox(height: 6),
          Text('لا يوجد عملاء متصلون حالياً',
              style: AppType.bodyStrong(color: AppColors.textMid)),
          const SizedBox(height: 2),
          Text('registration-table فارغ — قد يكون الـSSID بلا عملاء الآن',
              style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _clientsContent(List<MikrotikWirelessClient> cs) {
    return Column(children: [
      DeskRows(children: [for (final c in cs.take(30)) _clientRow(c)]),
      if (cs.length > 30)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${cs.length - 30} عميل آخر',
              style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
        ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // Header
  // ══════════════════════════════════════════════════════════════
  Widget _header() {
    final desk = _desk;
    final meta = desk
        ? TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.textMid)
        : TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textMid);
    final metaLow = meta.copyWith(color: AppColors.textLow);
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Row(children: [
        Container(
          width: desk ? 40 : 32,
          height: desk ? 40 : 32,
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.activity, size: desk ? 20 : 16, color: AppColors.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desk ? 'مراقبة حيّة · MikroTik API' : 'مراقبة حيّة (Mikrotik API)',
                style: desk ? AppType.cardTitleBold() : AppType.bodyBold()),
            const SizedBox(height: 2),
            Row(children: [
              if (_monitoring) ...[
                _pulseDot(),
                const SizedBox(width: 4),
              ],
              Text(
                // 2026-08-18: النصّ ثابت — التغيّر السابق كان يُوحي "فُصل ورجع".
                // الـ_pulseDot يعطي المؤشّر البصري كافياً.
                _monitoring
                    ? (desk
                        ? 'مباشر · يتحدّث كلّ ${arCount(_refreshInterval.inSeconds, one: 'ثانية', two: 'ثانيتين', few: 'ثوانٍ', many: 'ثانية')}'
                        : 'مباشر · كل ${_refreshInterval.inSeconds}s')
                    : 'متوقّف',
                style: meta,
              ),
              if (_lastFetch != null) ...[
                Text(' • ', style: metaLow),
                Text(
                  '${desk ? 'آخر تحديث' : 'آخر:'} ${_lastFetch!.hour.toString().padLeft(2, '0')}:${_lastFetch!.minute.toString().padLeft(2, '0')}:${_lastFetch!.second.toString().padLeft(2, '0')}',
                  style: metaLow,
                ),
              ],
            ]),
          ]),
        ),
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          onPressed: _loading ? null : _fetch,
          tooltip: 'تحديث الآن',
          color: AppColors.brand,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(
            _monitoring ? LucideIcons.pause : LucideIcons.play,
            size: 16,
            color: _monitoring ? AppColors.error : AppColors.success,
          ),
          onPressed: _monitoring ? _stopMonitoring : _startMonitoring,
          tooltip: _monitoring ? 'إيقاف' : 'استئناف',
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _pulseDot() => Container(
        width: 6,
        height: 6,
        decoration:
            BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
      );

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Sp.md),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(children: [
        Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.error),
        const SizedBox(width: 8),
        Expanded(
            child: Text(_error!,
                style: TextStyle(
                    fontSize: 11, color: AppColors.error, height: 1.4))),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Board banner (moved from stats — since uptime moved to metric card)
  // ══════════════════════════════════════════════════════════════
  Widget _boardBanner() {
    final s = _stats!;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Icon(LucideIcons.router, size: 14, color: AppColors.brand),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${s.boardName} • ${s.version.split(' ').first}',
            style: TextStyle(
                fontSize: 11, height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.textHi),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Uptime badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.clock, size: 9, color: AppColors.brand),
            const SizedBox(width: 3),
            Text(_formatUptime(s.uptime),
                style: AppType.microBold(color: AppColors.brand)),
          ]),
        ),
        if (s.pppActiveCount > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.successSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text('PPP: ${s.pppActiveCount}',
                style: AppType.microBold(color: AppColors.success)),
          ),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 3 metric cards: CPU / RAM / أعلى interface
  // ══════════════════════════════════════════════════════════════
  Widget _metricsRow() {
    if (_desk) return _deskMetricsRow();
    final s = _stats!;
    final maxRx = _maxRxIface();
    final maxTx = _maxTxIface();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Column(children: [
        // Row 1: CPU | RAM | Temperature — كل الكارتات بنفس الارتفاع
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.cpu,
                label: 'CPU',
                percent: s.cpuLoad.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.memoryStick,
                label: 'RAM',
                percent: s.memUsedPercent.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.thermometer,
                label: 'حرارة',
                value: s.temperature != null ? '${s.temperature}' : '—',
                unit: s.temperature != null ? '°C' : '',
                color: _tempColor(s.temperature),
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Row 2: Voltage | أعلى تنزيل ↓ | أعلى رفع ↑
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Polymorphic status card:
              //   priority: voltage → PSU → fans → dash
              //   CCR1009 يعطي voltage. CCR2116 يعطي PSU + fans (بلا voltage).
              //   جهاز صغير قد لا يعطي أي شيء (—).
              Expanded(child: _powerStatusCard(s)),
              const SizedBox(width: 8),
              Expanded(
                  child: _topRateCard(
                down: true, // أعلى واجهةٍ بالاستقبال
                iface: maxRx,
                color: AppColors.success,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _topRateCard(
                down: false,
                iface: maxTx,
                color: AppColors.info,
              )),
            ],
          ),
        ),
      ]),
    );
  }

  /// Power status card — يعرض أفضل مؤشّر متوفّر:
  ///   1. Voltage (لو الجهاز يعطيه — CCR1009 مثلاً)
  ///   2. PSU status (dual PSU — CCR2116)
  ///   3. Fan status (لو الجهاز به مراوح — enterprise routers)
  ///   4. "—" لو لا شيء متوفّر (RB بسيط)
  Widget _powerStatusCard(MikrotikStats s) {
    // #1 Voltage
    if (s.voltage != null) {
      return _valueCard(
        icon: LucideIcons.plug,
        label: 'فولتيّة',
        value: s.voltage!.toStringAsFixed(1),
        unit: 'V',
        color: _voltageColor(s.voltage),
      );
    }
    // #2 PSU status
    if (s.psus.isNotEmpty) {
      final okCount = s.psus.where((p) => p.isOk == true).length;
      final total = s.psus.length;
      final allOk = okCount == total;
      final anyOk = okCount > 0;
      final color = allOk
          ? AppColors.success
          : anyOk
              ? AppColors.warning
              : AppColors.error;
      return _valueCard(
        icon: LucideIcons.batteryCharging,
        label: 'PSU',
        value: '$okCount/$total',
        unit: allOk ? 'OK' : 'FAIL',
        color: color,
      );
    }
    // #3 Fans
    if (s.fans.isNotEmpty) {
      final avgRpm =
          s.fans.map((f) => f.intValue ?? 0).fold<int>(0, (a, b) => a + b) ~/
              s.fans.length;
      return _valueCard(
        icon: LucideIcons.fan,
        label: '${s.fans.length} مروحة',
        value: '${(avgRpm / 100).round() / 10}K', // 4185 → 4.2K
        unit: 'RPM',
        color: AppColors.info,
      );
    }
    // #4 غير متوفّر
    return _valueCard(
      icon: LucideIcons.plug,
      label: 'فولتيّة',
      value: '—',
      unit: '',
      color: AppColors.textLow,
    );
  }

  /// كارت قيمة عامّة (بدون progress bar) — للحرارة والفولتيّة.
  /// mainAxisAlignment: spaceBetween يوزّع العناصر عند stretch (نفس ارتفاع _percentCard).
  Widget _valueCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: AppType.microBold(color: AppColors.textMid)),
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: value == '—' ? AppColors.textLow : color,
                      height: 1)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                // يساراً إلى يمين: «°C» كانت تظهر «C°» (صورة المالك ٢٥ أكتوبر)
                Text(unit,
                    textDirection: TextDirection.ltr,
                    style: AppType.muted()),
              ],
            ],
          ),
          // مُسافة صغيرة أسفل لمحاذاة تقريبيّة مع progress bar في _percentCard
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Color _tempColor(int? t) => Grade.temperature(t).fill;

  Color _voltageColor(double? v) => Grade.voltage(v).fill;

  Widget _percentCard({
    required IconData icon,
    required String label,
    required double percent,
  }) {
    final color = _colorForPercent(percent);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppType.microBold(color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${percent.round()}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                    height: 1)),
            const SizedBox(width: 2),
            Text('%',
                style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
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

  Widget _topRateCard({
    required bool down,
    required ({String name, int bps})? iface,
    required Color color,
  }) {
    final hasData = iface != null && iface.bps > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row 1: icon + "أعلى" فقط (بدون اسم — يأخذ سطره الخاصّ)
          Row(children: [
            Icon(down ? LucideIcons.arrowDown : LucideIcons.arrowUp, size: 12, color: color),
            const SizedBox(width: 4),
            Text(down ? 'أعلى تنزيل' : 'أعلى رفع',
                style: AppType.microBold(color: AppColors.textMid)),
          ]),
          // Row 2: اسم الـiface بحجم مقروء بلا تقطيع (لأنّه في سطره الخاصّ)
          if (hasData)
            Text(iface.name,
                style: AppType.bodyBold()),
          // Row 3: value (big number) — «يُحسب…» حتى القراءة الثانية (السرعة فرقُ قراءتين)، لا «—» كأنّه معطّل
          Text(hasData ? _formatBps(iface.bps) : (_rates.isEmpty ? 'يُحسب…' : '—'),
              style: TextStyle(
                  fontSize: hasData ? 17 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: hasData ? color : AppColors.textLow,
                  height: 1)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Traffic graph — RX + TX gradient area chart
  // ══════════════════════════════════════════════════════════════
  Widget _trafficGraph() {
    final desk = _desk;
    // نافذةٌ ثابتة بآخر [_maxHistory] قراءة (~٤ دقائق) تمتلئ من طرف «الآن»: القراءتان الأوليان قطعةٌ قصيرة
    // عنده لا خطٌّ ممدودٌ بعرض الرسم كأنّه اتّجاه أربع دقائق (صورة المالك ٢٥ أكتوبر: خطٌّ مستقيم من نقطتين).
    final n = _history.length;
    final first = _maxHistory - n;
    final lastX = (_maxHistory - 1).toDouble();
    // كلا الخطّين من الأسفل (baseline=0)، بألوان مختلفة وتعبئة شفّافة
    // → التداخل يظهر بلون مختلط، الاختلاف واضح بصرياً.
    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (int i = 0; i < n; i++) {
      final x = (first + i).toDouble();
      rxSpots.add(FlSpot(x, _history[i].rxBps.toDouble()));
      txSpots.add(FlSpot(x, _history[i].txBps.toDouble()));
    }
    final peak = _history.fold<int>(0, (m, s) => math.max(m, math.max(s.rxBps, s.txBps)));
    final maxY = _niceCeil(peak * 1.15);

    final lastRx = _history.isNotEmpty ? _history.last.rxBps : 0;
    final lastTx = _history.isNotEmpty ? _history.last.txBps : 0;

    // التنزيل أخضر الرسوم والرفع أزرق اللوحة الوحيد — كانا أخضرين متقاربين لا يُفرَّقان.
    final rxColor = AppColors.chartLine;
    final txColor = AppColors.info;
    final windowMin = (_maxHistory * _refreshInterval.inSeconds / 60).round();

    final Widget chart = n < 2
        ? Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
              const SizedBox(width: 8),
              Text('تُجمع القراءات — يظهر الرسم بعد ثوانٍ',
                  style: AppType.body(color: AppColors.textMid)),
            ]),
          )
        // RepaintBoundary + duration:0 → يمنع rebuild الكامل عند كل setState
        // الـchart كان أكبر مصدر للـjank (animation 150ms افتراضي × كل fetch)
        : RepaintBoundary(
            child: LineChart(
            duration: Duration.zero, // ألغي الـanimation بين updates
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.borderSoft,
                  strokeWidth: 0.5,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                // الحاسبة: محور الوقت (قبل ٤ دقائق … الآن) — النافذة ثابتة فالتسميات صادقة.
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: desk,
                    reservedSize: 24,
                    interval: lastX / 2,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                      child: Text(
                        value >= lastX
                            ? 'الآن'
                            : 'قبل ${arMinutes(value <= 0 ? windowMin : (windowMin / 2).round())}',
                        style: AppType.micro(color: AppColors.textLow),
                      ),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: desk ? 52 : 44,
                    interval: maxY / 4,
                    getTitlesWidget: (value, _) => Text(
                      _formatBpsShort(value.toInt()),
                      style: desk
                          ? AppType.micro(color: AppColors.textLow)
                          : TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY,
              minX: 0,
              maxX: lastX,
              // الأزرق (TX) أوّلاً — يُرسم تحت (bottom layer)
              // الأخضر (RX) ثاني — فوق (top layer) لكن بتعبئة شفّافة
              // → مناطق التداخل تظهر بلون مختلط
              lineBarsData: [
                _lineBarData(txSpots, txColor, lastX), // أزرق تحت
                _lineBarData(rxSpots, rxColor, lastX), // أخضر فوق
              ],
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) =>
                      AppColors.textHi.withValues(alpha: 0.9),
                  getTooltipItems: (spots) => spots.map((s) {
                    final isTx = s.barIndex == 0; // الأوّل في lineBarsData
                    return LineTooltipItem(
                      '${isTx ? "↑" : "↓"} ${_bpsFull(s.y.toInt())}',
                      AppType.microBold(color: isTx ? txColor : rxColor),
                    );
                  }).toList(),
                ),
              ),
            ),
          ));

    return Container(
      margin: const EdgeInsets.all(Sp.md),
      padding: EdgeInsets.all(desk ? Sp.lg : Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.chartLine, size: desk ? 16 : 14, color: AppColors.brand),
          const SizedBox(width: 6),
          // الكراف يعرض trajectory أعلى interface (يتطابق مع كروت «أعلى تنزيل / رفع» اللي فوق)
          // ⚠️ مرنٌ لأنّ الصفّ بلا مرنٍ يفيض ولا يُقصّ: النصّ غير المرن
          // يُقاس بلا حدٍّ أعلى، فـ`maxLines` و`ellipsis` عليه لا تعملان
          // أبداً — يأخذ مقاسه كاملاً ويدفع الصفّ إلى الخطوط الصفراء.
          Flexible(
            child: desk
                ? Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'سير الترفك', style: AppType.cardTitleBold(color: AppColors.textHi)),
                      TextSpan(
                          text: '   أعلى واجهةٍ في كلّ لحظة · آخر ${arMinutes(windowMin)}',
                          style: AppType.muted(color: AppColors.textLow)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('سير الترفك',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.pillBold(color: AppColors.textHi)),
          ),
          const Spacer(),
          if (n >= 2) ...[
            _legendChip(down: true, value: lastRx, color: rxColor),
            const SizedBox(width: 6),
            _legendChip(down: false, value: lastTx, color: txColor),
          ],
        ]),
        SizedBox(height: desk ? Sp.lg : 12),
        SizedBox(height: desk ? 210 : 120, child: chart),
      ]),
    );
  }

  /// خطّ + تعبئة شفّافة من الأسفل (كل خطّ من baseline=0).
  /// التعبئة شفّافة عشان لمّا الاثنين يتداخلون، اللون المخلوط يبيّن التداخل.
  /// ونقطةٌ عند آخر قراءة وحدها — «الآن» ظاهرةٌ ولو كانت القراءات قليلة.
  LineChartBarData _lineBarData(List<FlSpot> spots, Color color, double lastX) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.28,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.x == lastX,
        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
          radius: 3.5,
          color: color,
          strokeWidth: 2,
          strokeColor: AppColors.surfaceSunken,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.25), // شفّاف عشان التداخل يبان
            color.withValues(alpha: 0.02),
          ],
        ),
      ),
    );
  }

  /// مفتاح الخطّ بقيمته الآن. الحاسبة: نقطةٌ بلون الخطّ + «تنزيل/رفع» + القيمة بوحدتها.
  Widget _legendChip({required bool down, required int value, required Color color}) {
    if (!_desk) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text('${down ? '↓' : '↑'} ${_formatBps(value)}',
            style: AppType.microBold(color: color)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(down ? 'تنزيل' : 'رفع', style: AppType.label(color: AppColors.textMid)),
        const SizedBox(width: 6),
        Text(_bpsFull(value),
            textDirection: TextDirection.ltr,
            style: AppType.rowValue(color: AppColors.textHi)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // الحاسبة — صفّ أرقامٍ واحد، وجدول الواجهات وبطاقة الوايرلس جنباً إلى جنب، وجدول العملاء.
  // المالك ٢٥ أكتوبر بصور «سكتر 1»: صفوفٌ بعرض الشاشة أرقامها بطرفها أو وسطها، ونصٌّ صغير،
  // و«أعلى iface» بـ«—». الهاتف كما هو.
  // ══════════════════════════════════════════════════════════════
  bool get _desk => DesktopScope.of(context);

  Widget _deskBoardBanner() {
    final s = _stats!;
    Widget fact(IconData icon, String label, String value) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(label, style: AppType.label(color: AppColors.textMid)),
          const SizedBox(width: 6),
          Text(value, style: AppType.rowValue(color: AppColors.textHi)),
        ]);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Wrap(spacing: Sp.xl, runSpacing: Sp.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
        fact(LucideIcons.router, 'الطراز', s.boardName),
        fact(LucideIcons.package, 'RouterOS', s.version.split(' ').first),
        fact(LucideIcons.clock, 'يعمل منذ', _uptimeAr(s.uptime)),
        if (s.pppActiveCount > 0) fact(LucideIcons.users, 'جلسات PPP', '${s.pppActiveCount}'),
      ]),
    );
  }

  /// ستّ بطاقاتٍ في صفٍّ واحد (ثلاثٌ في صفّين إن ضاق): المعالج، الذاكرة، الحرارة، الطاقة، أعلى تنزيل، أعلى رفع.
  Widget _deskMetricsRow() {
    final s = _stats!;
    final tiles = <Widget>[
      _deskPercentTile(
        icon: LucideIcons.cpu,
        label: 'المعالج',
        percent: s.cpuLoad.toDouble(),
        sub: s.cpuFrequencyMhz > 0
            ? isoJoin([
                '${s.cpuFrequencyMhz} MHz',
                if (s.cpuCount > 1) arCount(s.cpuCount, one: 'نواة', two: 'نواتان', few: 'أنوية', many: 'نواة'),
              ], ' · ')
            : null,
      ),
      _deskPercentTile(
        icon: LucideIcons.memoryStick,
        label: 'الذاكرة',
        percent: s.memUsedPercent.toDouble(),
        sub: s.memTotalBytes > 0
            ? '${iso(_bytesShort(s.memUsedBytes))} من ${iso(_bytesShort(s.memTotalBytes))}'
            : null,
      ),
      _deskTempTile(s),
      _deskPowerTile(s),
      _deskRateTile(down: true, iface: _maxRxIface()),
      _deskRateTile(down: false, iface: _maxTxIface()),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth >= 6 * 140 + 5 * Sp.sm ? 6 : 3;
        return Column(children: [
          for (var i = 0; i < tiles.length; i += perRow) ...[
            if (i > 0) const SizedBox(height: Sp.sm),
            // كلّ البطاقات بارتفاعٍ واحد
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var k = i; k < math.min(i + perRow, tiles.length); k++) ...[
                  if (k > i) const SizedBox(width: Sp.sm),
                  Expanded(child: tiles[k]),
                ],
              ]),
            ),
          ],
        ]);
      }),
    );
  }

  Widget _deskTile({
    required IconData icon,
    required String label,
    required Color color,
    required Widget value,
    Widget? footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: AppColors.isDark ? 0.22 : 0.14), AppColors.surface),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
          ),
        ]),
        const SizedBox(height: 10),
        value,
        const Spacer(),
        if (footer != null) ...[const SizedBox(height: Sp.sm), footer],
      ]),
    );
  }

  /// الرقم الكبير بوحدته يساراً إلى يمين («5.8 Mbps»، «38 °C») فلا يتفكّك في الفقرة العربيّة.
  Widget _deskValue(String value, String unit, {Color? color}) {
    final known = value != '—';
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 24,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: known ? (color ?? AppColors.textHi) : AppColors.textLow,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        if (known && unit.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(unit, textDirection: TextDirection.ltr, style: AppType.body(color: AppColors.textLow)),
        ],
      ],
    );
  }

  Widget _deskSub(String text, {Color? color}) => Text(text,
      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: color ?? AppColors.textLow));

  String _gradeWord(AppTone t, {required String ok, required String warn, required String bad}) => switch (t) {
        AppTone.success => ok,
        AppTone.warning => warn,
        AppTone.danger => bad,
        _ => '',
      };

  Widget _deskPercentTile({required IconData icon, required String label, required double percent, String? sub}) {
    final tone = Grade.percentLowerBetter(percent);
    return _deskTile(
      icon: icon,
      label: label,
      color: tone.fill,
      value: _deskValue('${percent.round()}', '%'),
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(tone.fill),
          ),
        ),
        if (sub != null) ...[const SizedBox(height: 6), _deskSub(sub)],
      ]),
    );
  }

  Widget _deskTempTile(MikrotikStats s) {
    final t = s.temperature;
    final tone = Grade.temperature(t);
    return _deskTile(
      icon: LucideIcons.thermometer,
      label: 'الحرارة',
      color: t == null ? AppColors.textLow : tone.fill,
      value: _deskValue(t != null ? '$t' : '—', '°C', color: tone.fill),
      footer: _deskSub(t == null ? 'لا يقرؤها هذا الجهاز' : _gradeWord(tone, ok: 'طبيعيّة', warn: 'مرتفعة', bad: 'حرجة')),
    );
  }

  /// كـ[_powerStatusCard]: الفولتيّة ثمّ مزوّدات الطاقة ثمّ المراوح.
  Widget _deskPowerTile(MikrotikStats s) {
    if (s.voltage != null) {
      final tone = Grade.voltage(s.voltage);
      return _deskTile(
        icon: LucideIcons.plug,
        label: 'الفولتيّة',
        color: tone.fill,
        value: _deskValue(s.voltage!.toStringAsFixed(1), 'V', color: tone.fill),
        footer: _deskSub(_gradeWord(tone, ok: 'طبيعيّة', warn: 'خارج المعتاد', bad: 'غير طبيعيّة')),
      );
    }
    if (s.psus.isNotEmpty) {
      final ok = s.psus.where((p) => p.isOk == true).length;
      final total = s.psus.length;
      final tone = ok == total ? AppTone.success : (ok > 0 ? AppTone.warning : AppTone.danger);
      return _deskTile(
        icon: LucideIcons.batteryCharging,
        label: 'مزوّدات الطاقة',
        color: tone.fill,
        value: _deskValue('$ok/$total', '', color: tone.fill),
        footer: _deskSub(ok == total ? 'كلّها تعمل' : 'مزوّدٌ متوقّف', color: ok == total ? null : tone.fill),
      );
    }
    if (s.fans.isNotEmpty) {
      final avg = s.fans.map((f) => f.intValue ?? 0).fold<int>(0, (a, b) => a + b) ~/ s.fans.length;
      return _deskTile(
        icon: LucideIcons.fan,
        label: 'المراوح',
        color: AppColors.info,
        value: _deskValue('$avg', 'RPM'),
        footer: _deskSub(arCount(s.fans.length, one: 'مروحة واحدة', two: 'مروحتان', few: 'مراوح', many: 'مروحة')),
      );
    }
    return _deskTile(
      icon: LucideIcons.plug,
      label: 'الفولتيّة',
      color: AppColors.textLow,
      value: _deskValue('—', ''),
      footer: _deskSub('لا يقرؤها هذا الجهاز'),
    );
  }

  Widget _deskRateTile({required bool down, required ({String name, int bps})? iface}) {
    final color = down ? AppColors.chartLine : AppColors.info;
    final Widget value;
    if (iface == null) {
      // السرعة فرقُ قراءتين: «يُحسب…» حتى الثانية لا «—» كأنّه معطّل.
      value = Text(_rates.isEmpty ? 'يُحسب…' : '—', style: AppType.statValue(color: AppColors.textLow));
    } else {
      final (v, u) = _bpsParts(iface.bps);
      value = _deskValue(v, u, color: color);
    }
    return _deskTile(
      icon: down ? LucideIcons.arrowDown : LucideIcons.arrowUp,
      label: down ? 'أعلى تنزيل' : 'أعلى رفع',
      color: color,
      value: value,
      footer: iface == null
          ? _deskSub(_rates.isEmpty ? 'بعد القراءة الثانية' : 'لا ترافيك')
          : Align(alignment: AlignmentDirectional.centerStart, child: _deskPill(iface.name, AppTone.neutral)),
    );
  }

  Widget _deskPill(String text, AppTone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.softBorder),
        ),
        child: Text(iso(text), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.pillBold(color: tone.onSoft)),
      );

  Widget _dash() => Text('—', style: AppType.body(color: AppColors.textLow));

  Widget _deskSectionHeader(IconData icon, String title, int count, {String? hint}) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
        child: Icon(icon, size: 16, color: AppColors.brand),
      ),
      const SizedBox(width: 10),
      Text(title, style: AppType.cardTitleBold()),
      const SizedBox(width: 8),
      _deskPill('$count', AppTone.neutral),
      if (hint != null) ...[
        const SizedBox(width: 10),
        Flexible(
          child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textLow)),
        ),
      ],
    ]);
  }

  List<Widget> _deskExpandables() {
    final s = _stats!;
    final ethers = s.interfaces.where(_isEther).toList();
    // البريدجات: الأعلى ترافيكاً أوّلاً (طلب المستخدم ١٨ أكتوبر).
    final bridges = s.interfaces.where(_isBridge).toList()
      ..sort((a, b) => _trafficOf(b).compareTo(_trafficOf(a)));
    final ifaces = bridges.isEmpty && ethers.isEmpty
        ? null
        : ExpandableSection(
            key: PageStorageKey('mikrotik-${widget.device.id}-ifaces'),
            initiallyExpanded: true,
            header: _deskSectionHeader(LucideIcons.network, 'الواجهات', bridges.length + ethers.length,
                hint: bridges.isEmpty ? null : 'البريدجات أوّلاً — الأعلى ترافيكاً'),
            content: RepaintBoundary(child: _deskIfaceTable([...bridges, ...ethers], s)),
          );
    final wifi = !s.hasWireless
        ? null
        : ExpandableSection(
            key: PageStorageKey('mikrotik-${widget.device.id}-wifi'),
            initiallyExpanded: true,
            header: _deskSectionHeader(LucideIcons.wifi, 'الوايرلس', s.wirelessInterfaces.length),
            content: Column(children: [
              for (final (k, w) in s.wirelessInterfaces.indexed) ...[
                if (k > 0) const SizedBox(height: Sp.sm),
                _deskWirelessCard(w),
              ],
            ]),
          );
    return [
      if (ifaces != null || wifi != null) ...[
        const SizedBox(height: Sp.md),
        // الواجهات والوايرلس جنباً إلى جنب (الوايرلس أضيق) بدل قسمين بعرض الصفحة.
        if (ifaces != null && wifi != null)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: ifaces),
            const SizedBox(width: Sp.md),
            Expanded(flex: 2, child: wifi),
          ])
        else
          ifaces ?? wifi!,
      ],
      // 2026-08-20: القسم يظهر دائماً لأي جهاز AP حتى بصفر عملاء — كالهاتف.
      if (s.isAccessPoint) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('mikrotik-${widget.device.id}-clients'),
          initiallyExpanded: true,
          header: _deskSectionHeader(LucideIcons.users, 'العملاء المتّصلون', _stickyClients.length),
          content: RepaintBoundary(
            child: _stickyClients.isEmpty ? _emptyClientsHint() : _deskClientsTable(_stickyClients),
          ),
        ),
      ],
    ];
  }

  /// الواجهات جدولاً كقائمة Winbox: البريدجات ثمّ الإيثر، وتحت كلّ سرعةٍ شريطٌ نسبةً لأعلاها في الجدول.
  Widget _deskIfaceTable(List<MikrotikInterface> rows, MikrotikStats s) {
    int maxRx = 0, maxTx = 0;
    for (final i in rows) {
      final r = _rates[i.name];
      if (r != null) {
        maxRx = math.max(maxRx, r.rxBps);
        maxTx = math.max(maxTx, r.txBps);
      }
    }
    final byName = {for (final i in s.interfaces) i.name: i};
    return _DeskTable(
      columns: const [('الواجهة', 4), ('الربط', 2), ('البريدج / المنافذ', 4), ('تنزيل ↓', 3), ('رفع ↑', 3)],
      rows: [
        for (final i in rows)
          [
            _ifaceNameCell(i),
            _linkCell(i),
            if (_isBridge(i))
              _portsCell([
                for (final p in s.bridgePorts[i.name] ?? const <String>[]) (name: p, iface: byName[p]),
              ])
            else if (s.bridgeOf(i.name) case final b?)
              Align(alignment: AlignmentDirectional.centerStart, child: _deskPill(b, AppTone.brand))
            else
              _dash(),
            _rateCell(i, down: true, max: maxRx),
            _rateCell(i, down: false, max: maxTx),
          ],
      ],
    );
  }

  Widget _ifaceNameCell(MikrotikInterface i) {
    final tone = i.disabled ? AppTone.neutral : (i.running ? AppTone.success : AppTone.danger);
    final color = i.disabled ? AppColors.textLow : tone.fill;
    final type = switch (i.type) { 'bridge' => 'بريدج', 'ether' => 'إيثرنت', 'sfp' => 'SFP', _ => i.type };
    final state = i.disabled ? 'معطّل' : (i.running ? 'يعمل' : 'مفصول');
    return Row(children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(i.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.rowValue(color: i.disabled ? AppColors.textLow : AppColors.textHi)),
          Text('$type · $state', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: color)),
        ]),
      ),
    ]);
  }

  Widget _linkCell(MikrotikInterface i) {
    final ls = i.linkSpeed;
    if (ls == null || ls.isEmpty || !i.running) return _dash();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _deskPill(_shortLinkSpeed(ls), Grade.linkSpeedText(ls)),
    );
  }

  Widget _portsCell(List<({String name, MikrotikInterface? iface})> members) {
    if (members.isEmpty) return _dash();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final m in members)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: m.iface == null || m.iface!.disabled
                    ? AppColors.textLow
                    : (m.iface!.running ? AppColors.success : AppColors.error),
              ),
            ),
            const SizedBox(width: 5),
            Text(m.name, style: AppType.pillLabel(color: AppColors.textBody)),
          ]),
        ),
    ]);
  }

  Widget _rateCell(MikrotikInterface i, {required bool down, required int max}) {
    final r = _rates[i.name];
    if (r == null) {
      return Text(i.running && !i.disabled ? 'يُحسب…' : '—', style: AppType.body(color: AppColors.textLow));
    }
    final bps = down ? r.rxBps : r.txBps;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(iso(_bpsFull(bps)), style: AppType.rowValue(color: bps > 0 ? AppColors.textHi : AppColors.textLow)),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(R.pill),
        child: LinearProgressIndicator(
          value: max > 0 ? (bps / max).clamp(0.0, 1.0) : 0,
          minHeight: 4,
          backgroundColor: AppColors.borderSoft,
          valueColor: AlwaysStoppedAnimation(down ? AppColors.chartLine : AppColors.info),
        ),
      ),
    ]);
  }

  Widget _deskWirelessCard(MikrotikWireless w) {
    final active = w.running && !w.disabled;
    final tone = active ? AppTone.success : (w.disabled ? AppTone.neutral : AppTone.danger);
    final clients = _stickyClients.where((c) => c.iface == w.name).length;
    final facts = <Widget>[
      if (w.band.isNotEmpty) _fact('النطاق', w.band, ltr: true),
      if (w.frequency > 0) _fact('التردّد', '${w.frequency} MHz', ltr: true),
      if (w.channelWidth > 0) _fact('عرض القناة', '${w.channelWidth} MHz', ltr: true),
      if (w.txPower > 0) _fact('قدرة الإرسال', '${w.txPower} dBm', ltr: true),
      if (w.isAp) _fact('العملاء', '$clients'),
    ];
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w.isAp ? LucideIcons.radioTower : LucideIcons.satellite, size: 18, color: tone.fill),
          const SizedBox(width: 8),
          Text(w.name, style: AppType.cardTitleBold()),
          const SizedBox(width: 8),
          Flexible(child: _deskPill(_modeLabel(w.mode), AppTone.brand)),
          const Spacer(),
          _deskPill(active ? 'يعمل' : (w.disabled ? 'معطّل' : 'متوقّف'), tone),
        ]),
        if (w.ssid.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          _fact('اسم الشبكة (SSID)', w.ssid, ltr: true, copy: true),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 480 ? 3 : (c.maxWidth >= 300 ? 2 : 1);
            final width = (c.maxWidth - Sp.md * (cols - 1)) / cols;
            return Wrap(spacing: Sp.md, runSpacing: Sp.md, children: [
              for (final f in facts) SizedBox(width: width, child: f),
            ]);
          }),
        ],
      ]),
    );
  }

  /// حقيقةٌ بعنوانها فوقها. [ltr]: قيمةٌ لاتينيّة («5535 MHz») معزولةٌ فلا تنقلب.
  Widget _fact(String label, String value, {bool ltr = false, bool copy = false}) {
    final text = Text(ltr ? iso(value) : value,
        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: AppColors.textHi));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: AppType.label(color: AppColors.textMid)),
      const SizedBox(height: 3),
      copy ? Copyable(label: label, value: value, child: text) : text,
    ]);
  }

  /// العملاء جدولاً كـ«Registration Table» في Winbox — الاسم والـIP والماك تُنسخ بضغطٍ مطوّل أو زرٍّ أيمن.
  Widget _deskClientsTable(List<MikrotikWirelessClient> cs) {
    const limit = 100;
    // عمودا IP وCCQ بقدر ما يعطيه الجهاز: السكتر بوضع الجسر لا يعرف IP عملائه، وwifi في RouterOS 7 بلا CCQ —
    // عمودٌ كلّه «—» مساحةٌ ضائعة.
    final ip = cs.any((c) => c.ip != null);
    final ccq = cs.any((c) => c.txCcq > 0 || c.rxCcq > 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _DeskTable(
        columns: [
          ('العميل', 4),
          if (ip) ('IP', 3),
          ('الماك', 3),
          ('الإشارة', 3),
          if (ccq) ('CCQ', 2),
          ('السرعة', 3),
          ('متّصل منذ', 2),
        ],
        rows: [for (final c in cs.take(limit)) _clientCells(c, ip: ip, ccq: ccq)],
      ),
      if (cs.length > limit)
        Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Text(
              '+ ${arCount(cs.length - limit, one: 'عميلٌ آخر', two: 'عميلان آخران', few: 'عملاء آخرين', many: 'عميلاً آخر')}',
              style: AppType.muted(color: AppColors.textLow)),
        ),
    ]);
  }

  List<Widget> _clientCells(MikrotikWirelessClient c, {required bool ip, required bool ccq}) {
    final name = c.hostname ?? c.comment;
    final sig = _signalColorFor(c.signalStrength);
    final q = c.txCcq > 0 ? c.txCcq : c.rxCcq;
    final mono = AppType.body(color: AppColors.textMid).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return [
      if (name != null)
        Copyable(
          label: 'اسم العميل',
          value: name,
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: AppColors.textHi)),
        )
      else
        Text('بلا اسم', style: AppType.body(color: AppColors.textLow)),
      if (ip)
        if (c.ip case final v?)
          Copyable(label: 'IP', value: v, child: Text(iso(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono))
        else
          _dash(),
      Copyable(
        label: 'الماك',
        value: c.mac,
        child: Text(iso(c.mac), maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
      ),
      Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: sig, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(iso(c.signalDisplay),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowValue(color: sig)),
        ),
        const SizedBox(width: 3),
        Text('dBm', style: AppType.muted(color: AppColors.textLow)),
      ]),
      if (ccq)
        if (q > 0)
          Align(alignment: AlignmentDirectional.centerStart, child: _deskPill('$q%', Grade.percentHigherBetter(q)))
        else
          _dash(),
      Row(children: [
        Icon(LucideIcons.arrowDown, size: 12, color: AppColors.chartLine),
        const SizedBox(width: 2),
        Text('${c.rxRate}', style: AppType.rowValue(color: AppColors.textHi)),
        const SizedBox(width: 8),
        Icon(LucideIcons.arrowUp, size: 12, color: AppColors.info),
        const SizedBox(width: 2),
        Text('${c.txRate}', style: AppType.rowValue(color: AppColors.textHi)),
        const SizedBox(width: 4),
        Text('Mbps', style: AppType.muted(color: AppColors.textLow)),
      ]),
      Text(c.uptime > 0 ? _durAr(c.uptime) : '—',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
    ];
  }

  // ══════════════════════════════════════════════════════════════
  // Interfaces section — فقط ether + sfp، مع RX/TX rates
  // ══════════════════════════════════════════════════════════════
Widget _interfaceRow(
    MikrotikInterface iface,
    int maxRate, {
    String? bridgeTag,
    List<({String name, MikrotikInterface? iface})>? members,
  }) {
    final rate = _rates[iface.name];
    final color = iface.disabled
        ? AppColors.textLow
        : (iface.running ? AppColors.success : AppColors.error);
    final statusIcon = iface.disabled
        ? LucideIcons.circleOff
        : (iface.running ? LucideIcons.arrowUp : LucideIcons.arrowDown);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(children: [
        Row(children: [
          Icon(statusIcon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            iface.name,
            style: TextStyle(
              fontSize: 11, height: 1.25,
              fontWeight: FontWeight.w600,
              color: iface.disabled ? AppColors.textLow : AppColors.textHi,
            ),
          ),
          if (iface.linkSpeed != null &&
              iface.linkSpeed!.isNotEmpty &&
              iface.running) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color:
                    _linkSpeedColor(iface.linkSpeed!).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(
                _shortLinkSpeed(iface.linkSpeed!),
                style: AppType.daysWordBold(color: _linkSpeedColor(iface.linkSpeed!)),
              ),
            ),
          ],
          // الشارة تأخذ ما بقي وتصطفّ من البداية، فالسرعتان بطرف الصفّ دائماً. كانت `Flexible` بجانب `Spacer`
          // يتقاسمان الفراغ نصفين فتقع السرعتان وسط الصفّ (صورة المالك ٢٥ أكتوبر).
          if (bridgeTag != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.brandSoftBg,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    bridgeTag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.daysWordBold(color: AppColors.brand),
                  ),
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (rate != null) ...[
            Icon(LucideIcons.arrowDown, size: 9, color: AppColors.success),
            const SizedBox(width: 2),
            Text(_formatBps(rate.rxBps),
                style: AppType.microBold(color: AppColors.textHi)),
            const SizedBox(width: 8),
            Icon(LucideIcons.arrowUp, size: 9, color: AppColors.info),
            const SizedBox(width: 2),
            Text(_formatBps(rate.txBps),
                style: AppType.microBold(color: AppColors.textHi)),
          ] else if (iface.running) ...[
            Text('—',
                style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
          ],
        ]),
        // شريط نسبي حسب أعلى traffic بين كل الـethers
        if (rate != null && maxRate > 0 && (rate.rxBps + rate.txBps) > 0) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
                child: _miniBar((rate.rxBps + rate.txBps) / maxRate, color)),
          ]),
        ],
        // منافذ البريدج (إن عُرفت)
        if (members != null && members.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _memberChips(members),
          ),
        ],
      ]),
    );
  }

  Widget _miniBar(double ratio, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 2,
        backgroundColor: AppColors.borderSoft,
        valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // Helpers
  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // Wireless section — للـMikrotik links/sectors/APs
  // ══════════════════════════════════════════════════════════════
Widget _wirelessCard(MikrotikWireless w) {
    final active = w.running && !w.disabled;
    final color = active ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w.isAp ? LucideIcons.radioTower : LucideIcons.satellite,
              size: 14, color: color),
          const SizedBox(width: 6),
          Text(w.name,
              style: AppType.pillBold(color: AppColors.textHi)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.pill),
            ),
            child: Text(_modeLabel(w.mode),
                style: AppType.daysWordBold(color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        if (w.ssid.isNotEmpty) _wlRow(LucideIcons.wifi, 'SSID', w.ssid),
        if (w.band.isNotEmpty) _wlRow(LucideIcons.radio, 'Band', w.band),
        // كلّ مقطعٍ معزول: كان يظهر «MHz • 20MHz 5535» و«dBm 24» (صورة المالك ٢٥ أكتوبر).
        if (w.frequency > 0)
          _wlRow(LucideIcons.satellite, 'التردد',
              isoJoin(['${w.frequency} MHz', if (w.channelWidth > 0) '${w.channelWidth} MHz'], ' • ')),
        if (w.txPower > 0)
          _wlRow(LucideIcons.zap, 'TX Power', iso('${w.txPower} dBm')),
      ]),
    );
  }

  Widget _wlRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 10, color: AppColors.textLow),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10.5, height: 1.3, color: AppColors.textMid)),
        const Spacer(),
        Text(value,
            style: AppType.microBold(color: AppColors.textHi)),
      ]),
    );
  }

  String _modeLabel(String m) => switch (m) {
        'ap-bridge' => 'AP Bridge',
        'bridge' => 'Bridge',
        'station' => 'Station',
        'station-bridge' => 'Station Bridge',
        'station-wds' => 'Station WDS',
        'wds-slave' => 'WDS Slave',
        _ => m,
      };

  // ══════════════════════════════════════════════════════════════
  // Wireless clients (registration table)
  // ══════════════════════════════════════════════════════════════
Widget _clientRow(MikrotikWirelessClient c) {
    final signalColor = _signalColorFor(c.signalStrength);
    final hasName = c.hostname != null || c.comment != null;
    // Use best CCQ (tx-ccq usually higher)
    final ccq = c.txCcq > 0 ? c.txCcq : c.rxCcq;
    final ccqColor = _ccqColor(ccq);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: signalColor,
              borderRadius: BorderRadius.circular(R.pill),
            )),
        const SizedBox(width: 8),
        // Name + secondary
        // primary: hostname/comment لو موجود، وإلا نعرض IP لو موجود، وإلا MAC
        // secondary: MAC (لو الـprimary مو MAC) + IP (لو الـprimary مو IP)
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            () {
              // اختر الـprimary display — hostname → IP → MAC
              // Cairo دائماً (feedback_font_cairo_always)
              final String primary =
                  hasName ? (c.hostname ?? c.comment!) : (c.ip ?? c.mac);
              // ضغطٌ مطوّل (أو زرٌّ أيمن على الحاسبة) ينسخ — المالك ٢٤ أكتوبر.
              return Copyable(
                label: hasName ? 'اسم العميل' : (c.ip != null ? 'IP' : 'الماك'),
                value: primary,
                child: Text(primary,
                    style: AppType.pillBold(color: AppColors.textHi),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              );
            }(),
            const SizedBox(height: 2),
            // secondary line: IP (لو الـprimary اسم) + MAC دائماً بعده
            Row(children: [
              if (hasName && c.ip != null) ...[
                Copyable(
                  label: 'IP',
                  value: c.ip,
                  child: Text(c.ip!,
                      style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textMid)),
                ),
                const SizedBox(width: 6),
              ],
              // MAC يظهر فقط لو الـprimary مو نفس MAC
              if (hasName || c.ip != null)
                Flexible(
                  child: Copyable(
                    label: 'الماك',
                    value: c.mac,
                    child: Text(c.mac,
                        style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        // Signal + CCQ + rates
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.signalDisplay,
                textDirection: TextDirection.ltr,
                style: AppType.bodyBold(color: signalColor)),
            const SizedBox(width: 2),
            Text('dBm',
                style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
            if (ccq > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ccqColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text('$ccq%',
                    textDirection: TextDirection.ltr,
                    style: AppType.bodyBold(color: ccqColor)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(LucideIcons.arrowDown, size: 8, color: AppColors.success),
            Text(' ${c.rxRate}',
                style: AppType.daysWordBold(color: AppColors.textHi)),
            const SizedBox(width: 6),
            Icon(LucideIcons.arrowUp, size: 8, color: AppColors.info),
            Text(' ${c.txRate}',
                style: AppType.daysWordBold(color: AppColors.textHi)),
            Text(' Mbps',
                style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow)),
          ]),
        ]),
      ]),
    );
  }

  Color _ccqColor(int ccq) => Grade.percentHigherBetter(ccq).fill;

  Color _signalColorFor(int dbm) {
    if (dbm >= -60) return AppColors.success;
    if (dbm >= -70) return AppColors.info;
    if (dbm >= -80) return AppColors.warning;
    return AppColors.error;
  }

  Color _colorForPercent(double p) {
    if (p >= 85) return AppColors.error;
    if (p >= 65) return AppColors.warning;
    return AppColors.success;
  }

  /// اختصار الـlink speed: "1Gbps" → "1G", "100Mbps" → "100M", "10Mbps" → "10M"
  String _shortLinkSpeed(String raw) {
    final r = raw.toLowerCase().replaceAll('bps', '').trim();
    if (r.endsWith('g')) return '${r.substring(0, r.length - 1).trim()}G';
    if (r.endsWith('m')) return '${r.substring(0, r.length - 1).trim()}M';
    return raw;
  }

  /// اللون حسب سرعة الـport — 1G أخضر، 100M أزرق، 10M أصفر، أقلّ أحمر
  Color _linkSpeedColor(String raw) => Grade.linkSpeedText(raw).fill;

  /// اختصار uptime: "3w2d15h4m5s" → "3أ 2ي" (أسبوع/يوم) أو "17س 4د"
  String _formatUptime(String raw) {
    if (raw.isEmpty) return '—';
    final weeks = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final days = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final hours = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final mins = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    if (weeks != null) return '${weeks}w ${days ?? "0"}d';
    if (days != null) return '${days}d ${hours ?? "0"}h';
    if (hours != null) return '${hours}h ${mins ?? "0"}m';
    if (mins != null) return '${mins}m';
    return raw;
  }

  String _formatBps(int bps) {
    if (bps <= 0) return '0';
    if (bps < 1000) return '${bps}bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(1)}K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)}M';
    return '${(bps / 1000000000).toStringAsFixed(2)}G';
  }


  /// 5800000 → ('5.8', 'Mbps') — الرقم ووحدته منفصلين للعرض الكبير.
  (String, String) _bpsParts(int bps) {
    if (bps < 1000) return ('${math.max(bps, 0)}', 'bps');
    if (bps < 1000000) return ((bps / 1e3).toStringAsFixed(1), 'Kbps');
    if (bps < 1000000000) return ((bps / 1e6).toStringAsFixed(1), 'Mbps');
    return ((bps / 1e9).toStringAsFixed(2), 'Gbps');
  }

  String _bpsFull(int bps) {
    final (v, u) = _bpsParts(bps);
    return '$v $u';
  }

  /// أعلى المحور بقيمةٍ أرباعُها مستديرة (1، 1.2، 1.6، 2، 3، 4، 6، 8، 10 × 10ⁿ) — 3M، 6M، 9M، 12M لا 3M و7M و10M.
  double _niceCeil(double v) {
    if (v <= 1000) return 1000;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 1.2, 1.6, 2.0, 3.0, 4.0, 6.0, 8.0, 10.0]) {
      if (m * p >= v) return m * p;
    }
    return 10 * p;
  }

  String _formatBpsShort(int bps) {
    // دون العشرة بمنزلةٍ عشريّة («2.5M»، «1.2M») وما فوقها مقرَّب («48M») — كان 2.5M يُكتب «3M» و1.2M «1M».
    String t(double v) {
      if (v >= 10) return '${v.round()}';
      final s = v.toStringAsFixed(1);
      return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
    }
    if (bps <= 0) return '0';
    if (bps < 1000) return '$bps';
    if (bps < 1000000) return '${t(bps / 1000)}K';
    if (bps < 1000000000) return '${t(bps / 1000000)}M';
    return '${t(bps / 1000000000)}G';
  }

  /// «9w4d» → «9 أسابيع و4 أيام» (بدل اختصار RouterOS على الحاسبة).
  String _uptimeAr(String raw) {
    int g(String unit) => int.tryParse(RegExp('(\\d+)$unit').firstMatch(raw)?.group(1) ?? '') ?? 0;
    final w = g('w'), d = g('d'), h = g('h'), m = g('m(?!s)');
    String and(String a, int n, String Function(int) f) => n > 0 ? '$a و${f(n)}' : a;
    if (w > 0) return and(arWeeks(w), d, arDays);
    if (d > 0) return and(arDays(d), h, arHours);
    if (h > 0) return and(arHours(h), m, arMinutes);
    if (m > 0) return arMinutes(m);
    return raw.isEmpty ? '—' : raw;
  }

  /// مدّة اتّصال العميل: «45 ث» · «12 دقيقة» · «3 ساعات» · «يومين».
  String _durAr(int seconds) {
    if (seconds < 60) return '$seconds ث';
    if (seconds < 3600) return arMinutes(seconds ~/ 60);
    if (seconds < 86400) return arHours(seconds ~/ 3600);
    return arDays(seconds ~/ 86400);
  }

  String _bytesShort(int b) {
    const mb = 1024 * 1024;
    if (b >= 1024 * mb) return '${(b / (1024 * mb)).toStringAsFixed(1)} GB';
    return '${(b / mb).round()} MB';
  }
}

class _BytesPoint {
  final int rxBytes;
  final int txBytes;
  final DateTime at;
  const _BytesPoint(
      {required this.rxBytes, required this.txBytes, required this.at});
}

class _IfaceRate {
  final int rxBps;
  final int txBps;
  const _IfaceRate({required this.rxBps, required this.txBps});
}

class _TrafficSample {
  final DateTime at;
  final int rxBps;
  final int txBps;
  const _TrafficSample(
      {required this.at, required this.rxBps, required this.txBps});
}

/// جدول الحاسبة داخل اللوحة: رأسٌ بأسماء الأعمدة ثمّ صفوفٌ بفاصلٍ رفيع وتظليلٍ عند المرور — كجداول Winbox.
/// [columns]: (العنوان، الوزن)، وخلايا كلّ صفٍّ بترتيبها.
class _DeskTable extends StatelessWidget {
  const _DeskTable({required this.columns, required this.rows});

  final List<(String, int)> columns;
  final List<List<Widget>> rows;

  Widget _line(List<Widget> cells) => Row(children: [
        for (var k = 0; k < columns.length; k++) ...[
          if (k > 0) const SizedBox(width: Sp.md),
          Expanded(flex: columns[k].$2, child: cells[k]),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: _line([
            for (final c in columns)
              Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
          ]),
        ),
        for (var r = 0; r < rows.length; r++) _DeskTableRow(divider: r > 0, child: _line(rows[r])),
      ]),
    );
  }
}

class _DeskTableRow extends StatefulWidget {
  const _DeskTableRow({required this.divider, required this.child});

  final bool divider;
  final Widget child;

  @override
  State<_DeskTableRow> createState() => _DeskTableRowState();
}

class _DeskTableRowState extends State<_DeskTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
        decoration: BoxDecoration(
          color: _hover ? AppColors.surfaceSunken : null,
          border: widget.divider ? Border(top: BorderSide(color: AppColors.borderSoft)) : null,
        ),
        child: widget.child,
      ),
    );
  }
}
