import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/network_device.dart';
import '../../services/device_alerts_service.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'bulk_scan_screen.dart';
import 'device_alerts_screen.dart';
import 'network_device_details_screen.dart';
import 'network_device_form_sheet.dart';
import 'regions_screen.dart';
import 'widgets/brand_badge.dart';

/// قائمة أجهزة الشبكة. راجع project_devices_monitoring_plan.
///
/// التصميم:
/// - Row 1 (chips): فلتر بالنوع (لنكات/سويتشات/سكاتر/راوترات/AP/كاميرات/أخرى)
/// - Row 2 (chips): فلتر بالحالة (الكلّ/متصل/غير متصل/لم يُفحص)
/// - القائمة: cards بتصميم متسق مع باقي المشروع (AppColors)
class NetworkDevicesScreen extends StatefulWidget {
  const NetworkDevicesScreen({super.key});

  @override
  State<NetworkDevicesScreen> createState() => _NetworkDevicesScreenState();
}

class _NetworkDevicesScreenState extends State<NetworkDevicesScreen>
    with WidgetsBindingObserver {
  List<NetworkDevice> _all = [];
  bool _loading = true;
  bool _probing = false;
  String? _error;
  String? _typeFilter;
  String? _statusFilter;
  String _search = '';
  final _searchCtrl = TextEditingController();

  /// آخر حالة معروفة لكل جهاز (لرصد transition). key = device.id
  final Map<int, String> _lastKnownStatus = {};

  /// عدد الفشل المتتالي لكل جهاز — للـexponential backoff.
  /// جهاز يفشل باستمرار → نتجاهله في بعض الجولات لتوفير باتري وشبكة.
  final Map<int, int> _consecutiveFailures = {};
  int _probeRoundCount = 0;

  Timer? _probeTimer;
  // Probe أسرع (20s بدل 60s) — المستخدم يشتكي إن التحديث بطيء.
  // 20s = توازن بين responsiveness والـbattery/network.
  static const _probeInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialLoad();
    // نطلب صلاحيّة الإشعارات مرّة واحدة (Android 13+/iOS)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeviceAlertsService.instance.requestPermission();
    });
    _startProbeTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _probeTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// عند background نوقف الـtimer (توفير باتري) — عند resumed نُشغّله + probe فوري
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _probeTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startProbeTimer();
      // probe فوري لتحديث الحالة بعد العودة
      if (_all.isNotEmpty) _probeAll();
    }
  }

  void _startProbeTimer() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probeAll());
  }

  /// أول تحميل عند فتح الشاشة: قائمة من backend + probe فوري.
  /// الفرق عن _refresh: يظهر spinner كبير في المنتصف (الشاشة فارغة).
  Future<void> _initialLoad() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await NetworkDevicesApi.list();
      if (!mounted) return;
      // **مهم**: نعمل reset لـ _lastKnownStatus بلا القيم القديمة من backend.
      // السبب: backend يحمل last_status من ساعات مضت (cache). لو استعملناه
      // كـbaseline، أوّل probe يعطي transitions وهميّة (لو المدير قفل
      // التطبيق ورجع بعد وقت طويل، سيرى spam إشعارات لأشياء قديمة).
      // نمرّرها 'unknown' → checkTransition يتخطّاها → baseline نظيف.
      _lastKnownStatus.clear();
      setState(() { _all = rows; _loading = false; });
      // 🔥 probe فوري — لا ننتظر 20s للـTimer الأوّل.
      _probeAll();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'فشل التحميل: $e'; _loading = false; });
    }
  }

  /// Refresh يدوي (زر أو pull-to-refresh): مباشرة probe بلا list fetch.
  /// السبب: backend عنده الحالة القديمة، الـprobe الجديد هو مصدر الحقيقة.
  Future<void> _refresh() async {
    if (_all.isEmpty) {
      // لسّه ما فيه أجهزة — اجلب القائمة أوّلاً
      await _initialLoad();
      return;
    }
    await _probeAll();
  }

  /// probe كل الأجهزة بالتوازي (batch) + قارن مع الحالة السابقة + أنشئ alerts.
  ///
  /// **مهم**: نجمع كل الـtransitions أوّلاً، ثمّ نقرّر جماعياً هل نُطلق
  /// alerts أم نتخطّاها. السبب: لو المدير خرج من شبكة الـWiFi (رجع لسيلولار
  /// مثلاً)، **كل** الأجهزة رح تفشل في نفس الجولة — هذا مو "أعطال أجهزة"
  /// بل تغيير شبكة عند الهاتف. نتخطّى الـalerts في هذي الحالة.
  /// هل نُفحص هذا الجهاز في الجولة الحاليّة (backoff)؟
  /// جهاز بـ0 فشل: كل جولة (20s)
  /// جهاز بـ2 فشل: كل جولتين (40s)
  /// جهاز بـ4 فشل: كل 4 جولات (80s)
  /// جهاز بـ6+ فشل: كل 6 جولات (120s max — يوفّر باتري)
  bool _shouldProbeInRound(int deviceId) {
    final fails = _consecutiveFailures[deviceId] ?? 0;
    if (fails == 0) return true;
    final skipEvery = fails.clamp(1, 6);
    return _probeRoundCount % skipEvery == 0;
  }

  Future<void> _probeAll() async {
    if (_probing || _all.isEmpty) return;
    _probing = true;
    _probeRoundCount++;
    try {
      // اجمع الـtransitions المُحتملة + التحديثات (بلا setState لكل جهاز).
      // كان: N setState = N × rebuild كامل للـCustomScrollView (dropped frames)
      // الآن: 1 setState بعد كل الـFuture.wait
      final pendingTransitions = <_PendingTransition>[];
      final updates = <int, NetworkDevice>{};   // id → updated device

      await Future.wait(_all.where((d) => _shouldProbeInRound(d.id)).map((d) async {
        try {
          // TCP probe (أدقّ من ICMP على iOS) — نستعمل apiPort لو موجود
          // (Mikrotik=8728، UBNT=22، Mimosa=161)، وإلا الـport الأساسي.
          final r = await NetworkDevicesApi.localIcmpPing(
            ip: d.ip,
            tcpPort: d.apiPort ?? d.port,
          );
          final oldStatus = _lastKnownStatus[d.id] ?? 'unknown';
          final newStatus = r.status;

          if (oldStatus != newStatus && oldStatus != 'unknown') {
            pendingTransitions.add(_PendingTransition(
              device: d, oldStatus: oldStatus, newStatus: newStatus,
            ));
          }
          _lastKnownStatus[d.id] = newStatus;
          // تحديث backoff counter
          if (newStatus == 'offline') {
            _consecutiveFailures[d.id] = (_consecutiveFailures[d.id] ?? 0) + 1;
          } else {
            _consecutiveFailures[d.id] = 0;
          }

          // fire-and-forget — نُصرّح unawaited لتوضيح النية
          unawaited(NetworkDevicesApi.saveProbeResult(
            deviceId: d.id, status: newStatus, responseMs: r.responseMs,
          ).catchError((_) {}));

          updates[d.id] = d.copyWith(
            lastProbedAt: DateTime.now(),
            lastStatus: newStatus,
            lastResponseMs: r.responseMs,
          );
        } catch (_) {
          // فشل probe لجهاز واحد ما يوقف الباقي
        }
      }));

      // setState **واحد** لكل التحديثات
      if (mounted && updates.isNotEmpty) {
        setState(() {
          for (int i = 0; i < _all.length; i++) {
            final u = updates[_all[i].id];
            if (u != null) _all[i] = u;
          }
        });
      }

      // كشف تغيير شبكة الهاتف (بدل مشكلة الأجهزة):
      // - "خروج من الشبكة": ≥70% من الأجهزة راحت offline في جولة واحدة → suppress
      // - "عودة للشبكة": ≥70% من الأجهزة رجعت online في جولة واحدة → suppress
      final totalDevices = _all.length;
      final offlineTransitions = pendingTransitions
          .where((t) => t.newStatus == 'offline').length;
      final onlineTransitions = pendingTransitions
          .where((t) => t.newStatus == 'online').length;
      final threshold = (totalDevices * 0.7).ceil();

      final phoneLeftNetwork = offlineTransitions >= threshold &&
          offlineTransitions > 1;
      final phoneRejoinedNetwork = onlineTransitions >= threshold &&
          onlineTransitions > 1;

      if (phoneLeftNetwork || phoneRejoinedNetwork) {
        // suppress — تغيير شبكة عند الهاتف، مو أعطال حقيقيّة
        return;
      }

      // أطلق alerts للـtransitions المتبقّية
      for (final t in pendingTransitions) {
        await DeviceAlertsService.instance.checkTransition(
          deviceId: t.device.id,
          deviceName: t.device.name,
          deviceIp: t.device.ip,
          oldStatus: t.oldStatus,
          newStatus: t.newStatus,
        );
      }
    } finally {
      _probing = false;
    }
  }

  Future<void> _openForm({NetworkDevice? existing}) async {
    final result = await showModalBottomSheet<NetworkDevice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: existing),
    );
    if (result != null) _initialLoad();
  }

  Future<void> _openDetails(NetworkDevice d) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NetworkDeviceDetailsScreen(device: d)),
    );
    // إذا المستخدم عدّل الجهاز → إعادة تحميل كاملة (list + probe)
    // وإلا → probe فوري (details شافت حالة جديدة، القائمة لازم تتزامن)
    if (changed == true) {
      _initialLoad();
    } else {
      // Reset backoff لكل الأجهزة عند الرجوع — يضمن probe فوري بلا تخطّي
      _consecutiveFailures.clear();
      _probeAll();
    }
  }

  void _openAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceAlertsScreen()),
    );
  }

  /// شاشة المناطق — تُرجع bool يشير إن حصلت تعديلات. لو نعم نُعيد
  /// تحميل قائمة الأجهزة (region_id قد تغيّرت على بعضها بسبب delete=null).
  Future<void> _openRegions() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegionsScreen()),
    );
    if (changed == true && mounted) {
      await _refresh();
    }
  }

  /// شاشة Bulk scan — يرجع bool لو أُضيف أي جهاز.
  /// نمرّر IPs الحاليّة عشان الـscanner يميّز المكرّرات ("مضاف مسبقاً").
  Future<void> _openBulkScan() async {
    final existingIps = _all.map((d) => d.ip).toSet();
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BulkScanScreen(existingIps: existingIps),
      ),
    );
    if (added == true && mounted) {
      await _refresh();
    }
  }

  /// اختبار تجريبي — يطلق alert فوري (بدون انتظار probe حقيقي).
  /// يُستدعى بـlong-press على البيل. مفيد لتأكيد إن الإشعارات مسموحة والقناة تعمل.
  Future<void> _testAlert() async {
    HapticFeedback.mediumImpact();
    final sample = _all.isNotEmpty ? _all.first : null;
    await DeviceAlertsService.instance.checkTransition(
      deviceId: sample?.id ?? 0,
      deviceName: sample?.name ?? 'جهاز تجريبي',
      deviceIp: sample?.ip ?? '192.168.1.1',
      oldStatus: 'online',
      newStatus: 'offline',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('تمّ إطلاق إشعار تجريبي — تحقّق من شريط الإشعارات'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brand,
    ));
  }

  List<NetworkDevice> get _filtered {
    final q = _search.trim().toLowerCase();
    final result = _all.where((d) {
      if (_typeFilter != null && d.type != _typeFilter) return false;
      if (_statusFilter != null && d.lastStatus != _statusFilter) return false;
      if (q.isNotEmpty) {
        final haystack = '${d.name} ${d.ip} ${d.mac ?? ''} ${d.location ?? ''} ${d.model ?? ''}'.toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
    // 2026-08-18: ترتيب بالـIP تصاعديّاً (من الأصغر). طلب المستخدم لكل شاشات الأجهزة.
    result.sort((a, b) => _compareIps(a.ip, b.ip));
    return result;
  }

  /// يقارن IPv4 كأربعة أرقام (بدل lex string). "10.0.0.5" < "10.0.0.20".
  static int _compareIps(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 4; i++) {
      final va = (i < pa.length ? pa[i] : null) ?? 0;
      final vb = (i < pb.length ? pb[i] : null) ?? 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  int _countByType(String type) => _all.where((d) => d.type == type).length;
  int _countByStatus(String s) => _all.where((d) => d.lastStatus == s).length;

  IconData _typeIcon(String type) {
    return switch (type) {
      'link' => LucideIcons.satellite,
      'switch' => LucideIcons.network,
      'sector' => LucideIcons.radioTower,
      'router' => LucideIcons.router,
      'ap' => LucideIcons.wifi,
      'camera' => LucideIcons.video,
      _ => LucideIcons.circuitBoard,
    };
  }

  Color _statusColor(String status) => switch (status) {
        'online' => const Color(0xFF10B981),
        'offline' => AppColors.error,
        _ => AppColors.textLow,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الأجهزة'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        actions: [
          // Bell icon مع badge — long-press = اختبار إشعار تجريبي
          ValueListenableBuilder<int>(
            valueListenable: DeviceAlertsService.instance.unreadCount,
            builder: (context, count, _) {
              return Stack(clipBehavior: Clip.none, children: [
                GestureDetector(
                  onLongPress: _testAlert,
                  child: IconButton(
                    icon: Icon(
                      count > 0 ? LucideIcons.bellDot : LucideIcons.bell,
                      size: 20,
                      color: count > 0 ? AppColors.error : AppColors.textMid,
                    ),
                    onPressed: _openAlerts,
                    tooltip: 'التنبيهات (اضغط مطوّلاً للاختبار)',
                  ),
                ),
                if (count > 0)
                  Positioned(
                    right: 4, top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w900),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ]);
            },
          ),
          // Manage-tier tools — 2026-08-18: مخفيّة للـview-only.
          if (Perms.has('devices.manage')) ...[
            IconButton(
              icon: const Icon(LucideIcons.mapPin, size: 20),
              onPressed: _openRegions,
              tooltip: 'إدارة المناطق',
            ),
            IconButton(
              icon: const Icon(LucideIcons.radar, size: 20),
              onPressed: _openBulkScan,
              tooltip: 'اكتشاف أجهزة الشبكة',
            ),
          ],
          // زر تحديث — يظهر animation دوران أثناء الـprobe
          _probing
              ? Container(
                  padding: const EdgeInsets.all(10),
                  width: 40, height: 40,
                  child: const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 20),
                  onPressed: _refresh,
                  tooltip: 'تحديث فوري',
                ),
          // زر "+" إضافة جهاز — manage tier فقط
          if (Perms.has('devices.manage'))
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Material(
                color: AppColors.brand,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _openForm(),
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 36, height: 36,
                    child: Icon(LucideIcons.plus, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: AppColors.textMid)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: CustomScrollView(
                    slivers: [
                      // Search bar (sticky-ish أعلى)
                      SliverToBoxAdapter(child: _searchBar()),
                      // Summary row: total + online + offline
                      SliverToBoxAdapter(child: _summaryRow()),
                      // Type filters (chips الحالة أُزيلت — تدمج بكارتات الملخّص)
                      SliverToBoxAdapter(child: _typeFilterRow()),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      // List
                      _filtered.isEmpty
                          ? const SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyDevices(),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  Sp.md, 0, Sp.md, 90),
                              sliver: SliverList.separated(
                                itemCount: _filtered.length,
                                itemBuilder: (_, i) => _deviceCard(_filtered[i]),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryRow() {
    final online = _countByStatus('online');
    final offline = _countByStatus('offline');
    final total = _all.length;
    // 2026-08-18: الكارتات الآن قابلة للنقر → تعمل toggle للـstatus filter.
    // (chips الفلترة السفليّة أُزيلت — دمج نفس الوظيفة هنا).
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 12, Sp.md, 8),
      child: Row(children: [
        _summaryTile(
          icon: LucideIcons.layers,
          label: 'الإجمالي',
          value: '$total',
          color: AppColors.textHi,
          filterStatus: null, // نقر → يعرض الكل
        ),
        const SizedBox(width: 8),
        _summaryTile(
          icon: LucideIcons.wifi,
          label: 'متّصل',
          value: '$online',
          color: const Color(0xFF10B981),
          filterStatus: 'online',
        ),
        const SizedBox(width: 8),
        _summaryTile(
          icon: LucideIcons.wifiOff,
          label: 'مفصول',
          value: '$offline',
          color: AppColors.error,
          filterStatus: 'offline',
        ),
      ]),
    );
  }

  Widget _summaryTile({
    required IconData icon, required String label,
    required String value, required Color color,
    required String? filterStatus,
  }) {
    final active = _statusFilter == filterStatus;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              // نقر ثاني على نفس الحالة النشطة → يلغي الفلتر (يرجع للكل)
              _statusFilter = active && filterStatus != null ? null : filterStatus;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? color.withValues(alpha: 0.10) : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? color : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textLow,
                          fontWeight: FontWeight.w600)),
                  Text(value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900,
                          color: color, height: 1.1)),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'ابحث باسم أو IP أو MAC أو موقع…',
          hintStyle: TextStyle(fontSize: 13, color: AppColors.textLow),
          prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
          suffixIcon: _search.isEmpty ? null : IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _search = '');
            },
          ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.brand, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _typeFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _typeChip(null, 'الكلّ', _all.length, LucideIcons.layoutGrid),
          const SizedBox(width: 6),
          for (final entry in NetworkDeviceLabels.types.entries) ...[
            _typeChip(entry.key, entry.value, _countByType(entry.key), _typeIcon(entry.key)),
            const SizedBox(width: 6),
          ],
        ]),
      ),
    );
  }

  Widget _typeChip(String? type, String label, int count, IconData icon) {
    final active = _typeFilter == type;
    return InkWell(
      onTap: () => setState(() => _typeFilter = active ? null : type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.brand : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: active ? Colors.white : AppColors.textMid),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textHi,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? Colors.white.withValues(alpha: 0.25) : AppColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : AppColors.brand,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _statusFilterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
      child: Row(children: [
        _statusChip(null, 'الكلّ', _all.length),
        const SizedBox(width: 6),
        _statusChip('online', 'متّصل', _countByStatus('online')),
        const SizedBox(width: 6),
        _statusChip('offline', 'غير متّصل', _countByStatus('offline')),
        const SizedBox(width: 6),
        _statusChip('unknown', 'لم يُفحص', _countByStatus('unknown')),
      ]),
    );
  }

  Widget _statusChip(String? status, String label, int count) {
    final active = _statusFilter == status;
    final color = status == null ? AppColors.brand : _statusColor(status);
    return InkWell(
      onTap: () => setState(() => _statusFilter = active ? null : status),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(children: [
          if (status != null) ...[
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: active ? Colors.white : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            '$label ($count)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textHi,
            ),
          ),
        ]),
      ),
    );
  }

  // _list() القديمة أُزيلت — استعملنا CustomScrollView + Slivers مباشرة في build.

  Widget _deviceCard(NetworkDevice d) {
    final statusCol = _statusColor(d.lastStatus);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: () => _openDetails(d),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          padding: const EdgeInsets.all(Sp.md),
          child: Row(
            children: [
              Stack(children: [
                BrandBadge(brand: d.brand, size: 44),
                // Type icon صغير في الزاوية العلوى (لتمييز router عن switch عن link)
                Positioned(
                  top: -3, right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: TypeIcon(type: d.type, size: 10, color: AppColors.textMid),
                  ),
                ),
                // Status dot سفلى يمين
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: statusCol,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
              ]),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textHi,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(LucideIcons.globe, size: 11, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Text(
                        d.ip,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          NetworkDeviceLabels.brandLabel(d.brand),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                        ),
                      ),
                      if (d.protocol != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            d.protocol!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    if (d.location != null && d.location!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(LucideIcons.mapPin, size: 10, color: AppColors.textLow),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            d.location!,
                            style: TextStyle(fontSize: 10, color: AppColors.textLow),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (d.lastResponseMs != null && d.lastStatus == 'online')
                    Text(
                      '${d.lastResponseMs} ms',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusCol,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Transition مؤقّت داخل probe round — قبل قرار suppress/fire.
class _PendingTransition {
  final NetworkDevice device;
  final String oldStatus;
  final String newStatus;
  _PendingTransition({
    required this.device,
    required this.oldStatus,
    required this.newStatus,
  });
}

/// Empty state — يظهر لو ما في أجهزة أصلاً أو ما في نتائج للفلتر.
class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.router, size: 40, color: AppColors.brand),
            ),
            const SizedBox(height: Sp.lg),
            Text('لا توجد نتائج',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text('جرّب تغيير الفلتر أو أضف جهاز جديد',
                style: TextStyle(fontSize: 12, color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}
