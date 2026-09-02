import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../services/device_alerts_service.dart';
import '../../services/device_sweep_coordinator.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/skeleton.dart';
import 'bulk_scan_screen.dart';
import 'device_alerts_screen.dart';
import 'devices_wall_screen.dart';
import 'network_device_details_screen.dart';
import 'network_device_form_sheet.dart';
import 'regions_screen.dart';
import 'widgets/brand_badge.dart';
import 'widgets/device_image.dart';
import '../../theme/typography.dart';
import 'detected_model.dart';
import 'model_detector.dart';
import '../../core/util/error_text.dart';

/// قائمة أجهزة الشبكة. راجع project_devices_monitoring_plan.
///
/// التصميم:
/// - Row 1 (chips): فلتر بالنوع (لنكات/سويتشات/سكاتر/راوترات/AP/كاميرات/أخرى)
/// - Row 2 (chips): فلتر بالحالة (الكلّ/متصل/غير متصل/لم يُفحص)
/// - القائمة: cards بتصميم متسق مع باقي المشروع (AppColors)
class NetworkDevicesScreen extends StatefulWidget {
  const NetworkDevicesScreen({super.key, this.isActive});

  /// هل هذا التبويب مرئيّ الآن؟ (يمرّرها `MainShell`)
  ///
  /// حلقة الفحص تفتح مقبساً TCP لكلّ جهاز على الـLAN كلّ 20 ثانية.
  /// خارج الشبكة يفشل كلّ فحص بعد مهلته كاملة، فتصير الحلقة استنزافاً
  /// صافياً للبطّاريّة والبيانات. الشاشة تُوقف مؤقّتها أصلاً حين يذهب
  /// التطبيق للخلفيّة — وهذه الراية تمدّ المنطق نفسه إلى الاختفاء خلف
  /// تبويب آخر، وهي الحالة الأشيع بفارق كبير.
  ///
  /// `null` = بلا بوّابة (تُستعمل حين تُفتح الشاشة بمسار مستقلّ).
  final ValueListenable<bool>? isActive;

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
  Timer? _searchDebounce;

  // Selection mode — long-press لتنشيطه، tap يبدّل عنصر، exit بزرّ الـclose. 2026-08-18.
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  bool _bulkDeleting = false;

  // خريطة id → منطقة لعرض اسم المنطقة على الكارت وفي التفاصيل.
  // تُحدَّث في _initialLoad + _refresh (بعد أي تعديل مناطق).
  Map<int, DeviceRegion> _regionsById = const {};

  /// آخر حالة معروفة لكل جهاز (لرصد transition). key = device.id
  final Map<int, String> _lastKnownStatus = {};

  /// عدد الفشل المتتالي لكل جهاز — للـexponential backoff.
  /// جهاز يفشل باستمرار → نتجاهله في بعض الجولات لتوفير باتري وشبكة.
  final Map<int, int> _consecutiveFailures = {};
  int _probeRoundCount = 0;

  Timer? _probeTimer;

  /// كشف الطُرُز جارٍ — يمنع تشغيلين متوازيين.
  bool _detecting = false;
  // Probe أسرع (20s بدل 60s) — المستخدم يشتكي إن التحديث بطيء.
  // 20s = توازن بين responsiveness والـbattery/network.
  static const _probeInterval = Duration(seconds: 20);

  /// سقف المقابس المتزامنة في جولة المسح. ٢٤ يُبقي جولة الثمانين تحت
  /// ثانيتين ولا يُغرق مكدّس الشبكة على الهواتف الضعيفة.
  static const _probeConcurrency = 24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.isActive?.addListener(_onActiveChanged);
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
    widget.isActive?.removeListener(_onActiveChanged);
    _probeTimer?.cancel();
    _searchDebounce?.cancel();
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

  /// الشاشة حيّة **ومرئيّة** — الشرطان معاً يفتحان حلقة الفحص.
  /// ⚠️ لا نمسح إن كان جدار الأجهزة مفتوحاً فوقنا — راجع [DeviceSweep].
  bool get _mayProbe =>
      (widget.isActive?.value ?? true) && !DeviceSweep.suspended;

  void _onActiveChanged() {
    if (_mayProbe) {
      _startProbeTimer();
      // فحص فوري عند العودة — القيم المعروضة قد تكون قديمة بدقائق.
      if (_all.isNotEmpty) _probeAll();
    } else {
      _probeTimer?.cancel();
    }
  }

  void _startProbeTimer() {
    _probeTimer?.cancel();
    // ⚠️ الحارس هنا لا عند الاستدعاء: `initState` و`didChangeAppLifecycle`
    // و`_onActiveChanged` كلّها تستدعيها، ونسيان الحارس في واحدة يعيد
    // العطل كاملاً.
    if (!_mayProbe) return;
    _probeTimer = Timer.periodic(_probeInterval, (_) => _probeAll());
  }

  /// أول تحميل عند فتح الشاشة: قائمة من backend + probe فوري.
  /// الفرق عن _refresh: يظهر spinner كبير في المنتصف (الشاشة فارغة).
  Future<void> _initialLoad() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // نجلب devices + regions بالتوازي — واحد ما يعطّل الثاني.
      final results = await Future.wait([
        NetworkDevicesApi.list(),
        NetworkDevicesApi.listRegions().catchError((_) => <DeviceRegion>[]),
      ]);
      final rows = results[0] as List<NetworkDevice>;
      final regions = results[1] as List<DeviceRegion>;
      if (!mounted) return;
      // **مهم**: نعمل reset لـ _lastKnownStatus بلا القيم القديمة من backend.
      // السبب: backend يحمل last_status من ساعات مضت (cache). لو استعملناه
      // كـbaseline، أوّل probe يعطي transitions وهميّة (لو المدير قفل
      // التطبيق ورجع بعد وقت طويل، سيرى spam إشعارات لأشياء قديمة).
      // نمرّرها 'unknown' → checkTransition يتخطّاها → baseline نظيف.
      _lastKnownStatus.clear();
      setState(() {
        _all = rows;
        _regionsById = {for (final r in regions) r.id: r};
        _loading = false;
      });
      // 🔥 probe فوري — لا ننتظر 20s للـTimer الأوّل.
      _probeAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanError(e, fallback: 'فشل التحميل');
        _loading = false;
      });
    }
  }

  /// Refresh يدوي (زر أو pull-to-refresh) + بعد add/delete/region-change.
  ///
  /// 2026-08-18: كان يعمل probe فقط بلا list fetch → أجهزة محذوفة تبقى
  /// ظاهرة، ومُضافة ما تظهر إلا بعد كيل التطبيق. الآن يجلب list جديدة
  /// من backend أوّلاً ثم يعمل probe.
  ///
  /// نحافظ على `lastStatus/lastResponseMs` من الـstate القديم لتفادي
  /// وميض "unknown" أثناء انتظار الـprobe الجديد (~1-2s).
  /// كشف طُرُز الأجهزة التي لا يُطابق طرازها صورةً.
  ///
  /// يُشغَّل بضغطة مطوّلة على زرّ التحديث. مرّةً واحدة تكفي: الطراز
  /// يُكتب في قاعدة البيانات فتظهر الصور بعدها بلا إعادة كشف.
  Future<void> _detectModels() async {
    if (_detecting) return;
    setState(() => _detecting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ModelDetector.run(_all, isCanceled: () => !mounted);
      if (!mounted) return;
      if (r.updated.isNotEmpty) {
        // نُحدّث القائمة من الخادم: الكشف كتب فيها، والصور تُبنى من
        // الطراز المخزَّن.
        await _refresh();
        if (!mounted) return;
      }
      final parts = <String>[];
      if (r.updated.isNotEmpty) parts.add('كُشف ${r.updated.length} طراز');
      if (r.unmatched.isNotEmpty) {
        // ⚠️ الجزء المهمّ: طراز مكشوف بلا صورة يبقى بشارته، فيظنّ
        // المستخدم أنّ الكشف فشل. نقول له بالضبط أيّ صور ينقصه.
        parts.add('بلا صورة: ${r.unmatched.join(' · ')}');
      }
      messenger.showSnackBar(SnackBar(
        content: Text(parts.isEmpty
            ? 'لا جديد — كلّ جهاز مكشوف أو غير متّصل'
            : parts.join('  •  ')),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: r.unmatched.isEmpty ? 3 : 8),
      ));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _refresh() async {
    try {
      // devices + regions معاً — يضمن ظهور مناطق مُنشأة من شاشة أخرى.
      final results = await Future.wait([
        NetworkDevicesApi.list(),
        NetworkDevicesApi.listRegions().catchError((_) => <DeviceRegion>[]),
      ]);
      final fresh = results[0] as List<NetworkDevice>;
      final regions = results[1] as List<DeviceRegion>;
      if (!mounted) return;
      // Preserve status حسب id — الأجهزة الموجودة تحتفظ بحالتها القديمة
      // مؤقّتاً، الجديدة تدخل بـstatus من backend (unknown غالباً).
      final oldById = {for (final d in _all) d.id: d};
      final merged = <NetworkDevice>[];
      for (final d in fresh) {
        final old = oldById[d.id];
        if (old != null) {
          merged.add(d.copyWith(
            lastStatus: old.lastStatus,
            lastResponseMs: old.lastResponseMs,
            lastProbedAt: old.lastProbedAt,
          ));
        } else {
          merged.add(d);
        }
      }
      setState(() {
        _all = merged;
        _regionsById = {for (final r in regions) r.id: r};
        _error = null;
      });
      await _probeAll();
    } catch (e) {
      // فشل الـlist fetch لا يوقف الـprobe — الأجهزة القديمة تُفحص كما هي.
      if (_all.isNotEmpty) {
        await _probeAll();
      } else if (mounted) {
        setState(() => _error = humanError(e, fallback: 'فشل التحميل'));
      }
    }
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
    if (_probing || _all.isEmpty || !_mayProbe) return;
    // 2026-08-18: setState — الـAppBar refresh icon يعتمد على _probing
    // لتبديل CPI ↔ زرّ. تغيير الـflag بلا setState → الأيقونة تعلق.
    setState(() => _probing = true);
    _probeRoundCount++;
    try {
      // اجمع الـtransitions المُحتملة + التحديثات (بلا setState لكل جهاز).
      // كان: N setState = N × rebuild كامل للـCustomScrollView (dropped frames)
      // الآن: 1 setState بعد كل الـFuture.wait
      final pendingTransitions = <_PendingTransition>[];
      final updates = <int, NetworkDevice>{}; // id → updated device
      // نتائج الجولة تُجمَع هنا وتُرسل **دفعةً واحدة** بعد اكتمالها.
      // كان كلّ جهاز يُرسل طلبه بنفسه = ٢٤٠ طلباً/دقيقة على ٨٠ جهازاً.
      final probed = <({int id, String status, int? responseMs})>[];

      // ⚠️ طابور عمّال بسقف، لا `Future.wait` على الكلّ.
      //
      // كان المسح يفتح مقبساً لكلّ جهاز دفعةً — ثمانون معاً على أكبر
      // حساب اليوم. يعمل لأنّ فحص TCP رخيص، لكن لا سقف يمنع حساباً
      // بثلاثمئة جهاز من فتح ثلاثمئة مقبس. السقف نفسه المُختبَر في
      // `bulkScanSubnet`.
      final queue = Queue<NetworkDevice>.from(
          _all.where((d) => _shouldProbeInRound(d.id)));
      Future<void> probeWorker() async {
        while (queue.isNotEmpty) {
          final d = queue.removeFirst();
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
                device: d,
                oldStatus: oldStatus,
                newStatus: newStatus,
              ));
            }
            _lastKnownStatus[d.id] = newStatus;
            // تحديث backoff counter
            if (newStatus == 'offline') {
              _consecutiveFailures[d.id] = (_consecutiveFailures[d.id] ?? 0) + 1;
            } else {
              _consecutiveFailures[d.id] = 0;
            }

            probed.add((id: d.id, status: newStatus, responseMs: r.responseMs));

            updates[d.id] = d.copyWith(
              lastProbedAt: DateTime.now(),
              lastStatus: newStatus,
              lastResponseMs: r.responseMs,
            );
          } catch (_) {
            // فشل probe لجهاز واحد ما يوقف الباقي
          }
        }
      }

      await Future.wait(List.generate(
        queue.length < _probeConcurrency ? queue.length : _probeConcurrency,
        (_) => probeWorker(),
      ));

      // طلب واحد لكلّ الجولة. fire-and-forget مقصود: الفحص المحلّيّ
      // انتهى وحالة الشاشة تُحدَّث من `updates` أدناه بلا انتظار الخادم.
      if (probed.isNotEmpty) {
        unawaited(
            NetworkDevicesApi.saveProbeResults(probed).catchError((_) => false));
      }

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
      final offlineTransitions =
          pendingTransitions.where((t) => t.newStatus == 'offline').length;
      final onlineTransitions =
          pendingTransitions.where((t) => t.newStatus == 'online').length;
      final threshold = (totalDevices * 0.7).ceil();

      final phoneLeftNetwork =
          offlineTransitions >= threshold && offlineTransitions > 1;
      final phoneRejoinedNetwork =
          onlineTransitions >= threshold && onlineTransitions > 1;

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
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _openForm({NetworkDevice? existing}) async {
    final result = await showModalBottomSheet<NetworkDevice>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDeviceFormSheet(existing: existing),
    );
    // 2026-08-18: نستعمل _refresh (يجلب list + يحافظ على status) بدل
    // _initialLoad الذي يعرض spinner كامل ويمسح القائمة مؤقّتاً — تجربة
    // مزعجة بعد إضافة/تعديل جهاز واحد.
    if (result != null) _refresh();
  }

  Future<void> _openDetails(NetworkDevice d) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NetworkDeviceDetailsScreen(device: d)),
    );
    // إذا المستخدم عدّل/حذف الجهاز → إعادة تحميل list + probe
    // وإلا → probe فوري (details شافت حالة جديدة، القائمة لازم تتزامن)
    if (changed == true) {
      _refresh();
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
  /// يفتح «نظرة عامّة». الشاشة تمسك [DeviceSweep] فتتوقّف جولتنا ما
  /// دامت مفتوحة، ثمّ نُحدّث عند العودة لأنّها مسحت نيابةً عنّا.
  Future<void> _openWall() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DevicesWallScreen()),
    );
    if (mounted) _refresh();
  }

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
  /// 2026-08-18: bypassDedup=true — الاختبارات المتكرّرة كانت تُفلتَر بصمت.
  Future<void> _testAlert() async {
    HapticFeedback.mediumImpact();
    final sample = _all.isNotEmpty ? _all.first : null;
    await DeviceAlertsService.instance.checkTransition(
      deviceId: sample?.id ?? 0,
      deviceName: sample?.name ?? 'جهاز تجريبي',
      deviceIp: sample?.ip ?? '192.168.1.1',
      oldStatus: 'online',
      newStatus: 'offline',
      bypassDedup: true,
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
        final haystack =
            '${d.name} ${d.ip} ${d.mac ?? ''} ${d.location ?? ''} ${d.model ?? ''}'
                .toLowerCase();
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
        'online' => AppColors.success,
        'offline' => AppColors.error,
        _ => AppColors.textLow,
      };

  @override
  Widget build(BuildContext context) {
    // ⚡ مرّة واحدة للإطار (تدقيق أداء 2026-08-31).
    //
    // `_filtered` جالبٌ يُرشّح ثمّ **يفرز** القائمة كلّها، ومقارنُه
    // `_compareIps` يشقّ العنوانين ويُجري أربع `int.tryParse` لكلّ
    // طرف. وكان يُستدعى داخل `itemBuilder` — أي فرزةٌ كاملة لكلّ صفّ
    // مرسوم، فقائمةٌ من 40 جهازاً تُفرَز 40 مرّة في الإطار الواحد.
    final devices = _filtered;
    // Selection mode → AppBar تعرض عدد المحدَّد + أزرار bulk actions
    // بدل الـtitle العادي. زرّ الـback (Android) يخرج من selection بدل الخروج من الشاشة.
    if (_selectionMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _exitSelection();
        },
        child: _buildSelectionScaffold(),
      );
    }
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
                    right: 4,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(R.sm),
                        border:
                            Border.all(color: AppColors.surface, width: 1.5),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: AppType.daysWordBold(color: AppColors.onBrand),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ]);
            },
          ),
          // جدار المراقبة — يتبع `devices.view` كبقيّة العرض، فلا مفتاح
          // صلاحيّة رابع لشاشةٍ تُظهر ما تُظهره هذه أصلاً.
          IconButton(
            icon: const Icon(LucideIcons.layoutGrid, size: 20),
            onPressed: _openWall,
            tooltip: 'نظرة عامّة',
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
                  width: 40,
                  height: 40,
                  child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 20),
                  onPressed: _refresh,
                  tooltip: 'تحديث فوري',
                ),
          // زرّ كشف الطُرُز — **ظاهر** لا ضغطة مخفيّة: لا يظهر إلّا حين
          // يوجد جهاز يحتاجه، ويختفي حين تكتمل الطُرُز. لا يُشغَّل
          // تلقائيّاً لأنّه يفتح جلسة مصادَقة على كلّ جهاز، وذلك قرار
          // المستخدم لا سلوك خفيّ يتّصل بأجهزته دون علمه.
          if (_all.any(DetectedModel.needsDetection))
            _detecting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(LucideIcons.scanSearch, size: 20),
                    onPressed: _detectModels,
                    tooltip: 'كشف طُرُز الأجهزة',
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
                    width: 36,
                    height: 36,
                    child: Icon(LucideIcons.plus,
                        size: 18, color: AppColors.onBrand),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const SkeletonDeviceList()
          : _error != null
              ? Center(
                  child:
                      Text(_error!, style: TextStyle(color: AppColors.textMid)))
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
                      devices.isEmpty
                          ? SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyDevices(
                                hasActiveFilter: _all.isNotEmpty &&
                                    (_typeFilter != null ||
                                        _statusFilter != null ||
                                        _search.isNotEmpty),
                                onClearFilter: () => setState(() {
                                  _typeFilter = null;
                                  _statusFilter = null;
                                  _search = '';
                                  _searchCtrl.clear();
                                }),
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                  Sp.md, 0, Sp.md, 90),
                              sliver: SliverList.separated(
                                itemCount: devices.length,
                                itemBuilder: (_, i) =>
                                    _deviceCard(devices[i]),
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }

  /// Scaffold بديل يظهر في selection mode — AppBar فيها عدد المحدَّد
  /// وأزرار bulk actions. القائمة تبقى نفسها لكن الكارتات تعرض checkbox.
  Widget _buildSelectionScaffold() {
    // نفس الرفع كما في build: الفرزة كانت تتكرّر لكلّ صفّ.
    final devices = _filtered;
    final canManage = Perms.has('devices.manage');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: _exitSelection,
          tooltip: 'إلغاء التحديد',
        ),
        title: Text('${_selectedIds.length} مُحدَّد',
            style: const TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.checkCheck, size: 20),
            onPressed: _selectAllFiltered,
            tooltip: 'تحديد الكل',
          ),
          if (canManage)
            _bulkDeleting
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.onBrand),
                    ),
                  )
                : IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 20),
                    onPressed: _bulkDelete,
                    tooltip: 'حذف المُحدَّد',
                  ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _searchBar()),
            SliverToBoxAdapter(child: _summaryRow()),
            SliverToBoxAdapter(child: _typeFilterRow()),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            devices.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyDevices(),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, 90),
                    sliver: SliverList.separated(
                      itemCount: devices.length,
                      itemBuilder: (_, i) => _deviceCard(devices[i]),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// دخول selection mode بأوّل جهاز محدَّد. long-press = الـpattern الأصيل
  /// في Android للـmulti-select. iOS + Android يفهمانه بلا تعلّم.
  void _enterSelection(NetworkDevice d) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(d.id);
    });
  }

  void _toggleSelected(NetworkDevice d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(d.id)) {
        _selectedIds.remove(d.id);
        // آخر واحد يُلغى تحديده → نخرج من selection mode تلقائياً
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(d.id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// اختيار كل الأجهزة الحاليّة (بعد الفلترة).
  void _selectAllFiltered() {
    HapticFeedback.selectionClick();
    setState(() {
      for (final d in _filtered) {
        _selectedIds.add(d.id);
      }
    });
  }

  /// حذف كل المُحدَّدة — dialog تأكيد + snackbar للنتيجة.
  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 32),
        title: Text('حذف $count جهاز'),
        content: Text(
          'سيتم حذف $count جهاز بشكل نهائي. لا يمكن التراجع. متابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            child: Text('حذف $count'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkDeleting = true);
    HapticFeedback.mediumImpact();
    // 2026-08-18: طلب واحد بدل N — كان الـloop يُطلق Cloudflare rate-limit
    // (429) على N>~10. bulkDelete backend يستعمل WHERE IN بترانزاكشن واحد.
    final ids = _selectedIds.toList();
    String snackText;
    Color snackColor;
    try {
      final r = await NetworkDevicesApi.bulkDelete(ids);
      snackText = r.deleted == r.requested
          ? 'حُذف ${r.deleted} جهاز بنجاح'
          : 'حُذف ${r.deleted} من ${r.requested} — الباقي غير موجود';
      snackColor =
          r.deleted == r.requested ? AppColors.success : AppColors.error;
    } catch (e) {
      snackText = 'فشل الحذف: ${e.toString().replaceFirst('Exception: ', '')}';
      snackColor = AppColors.error;
    }
    if (!mounted) return;
    setState(() {
      _bulkDeleting = false;
      _selectionMode = false;
      _selectedIds.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(snackText),
      backgroundColor: snackColor,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
    await _refresh();
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
          color: AppColors.success,
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
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required String? filterStatus,
  }) {
    final active = _statusFilter == filterStatus;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              // نقر ثاني على نفس الحالة النشطة → يلغي الفلتر (يرجع للكل)
              _statusFilter =
                  active && filterStatus != null ? null : filterStatus;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? color.withValues(alpha: 0.10) : AppColors.surface,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(
                color: active ? color : AppColors.border,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10.5, height: 1.3,
                          color: AppColors.textLow,
                          fontWeight: FontWeight.w600)),
                  Text(value,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: color,
                          height: 1.1)),
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
        // 2026-08-18: debounce 250ms — للـ500+ جهاز، كل keystroke بدون
        // debounce = filter+sort ثقيل على main thread (jank محسوس).
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 250), () {
            if (mounted) setState(() => _search = v);
          });
        },
        style: const TextStyle(fontSize: 14, height: 1.3),
        decoration: InputDecoration(
          hintText: 'ابحث باسم أو IP أو MAC أو موقع…',
          hintStyle: AppType.subtitle(color: AppColors.textLow),
          prefixIcon:
              Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.icon),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.icon),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.icon),
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
            _typeChip(entry.key, entry.value, _countByType(entry.key),
                _typeIcon(entry.key)),
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
      borderRadius: BorderRadius.circular(R.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(
            color: active ? AppColors.brand : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(children: [
          Icon(icon,
              size: 14, color: active ? AppColors.onBrand : AppColors.textMid),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppType.bodyStrong(color: active ? AppColors.onBrand : AppColors.textHi),
          ),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.onBrand.withValues(alpha: 0.25)
                    : AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5, height: 1.3,
                  fontWeight: FontWeight.bold,
                  color: active ? AppColors.onBrand : AppColors.brand,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

// _list() القديمة أُزيلت — استعملنا CustomScrollView + Slivers مباشرة في build.

  Widget _deviceCard(NetworkDevice d) {
    final statusCol = _statusColor(d.lastStatus);
    final selected = _selectionMode && _selectedIds.contains(d.id);
    final canManage = Perms.has('devices.manage');
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      elevation: 0,
      child: InkWell(
        // في selection mode: tap = toggle. عادي: tap = يفتح التفاصيل.
        onTap:
            _selectionMode ? () => _toggleSelected(d) : () => _openDetails(d),
        // long-press = يدخل selection mode ويضيف هذا الجهاز.
        // مطلوب devices.manage — الـview-only ما يحتاج bulk delete.
        onLongPress:
            canManage && !_selectionMode ? () => _enterSelection(d) : null,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(Sp.md),
          child: Row(
            children: [
              // في selection mode: checkbox قبل الأيقونة
              if (_selectionMode) ...[
                Icon(
                  selected ? LucideIcons.checkSquare : LucideIcons.square,
                  size: 20,
                  color: selected ? AppColors.brand : AppColors.textLow,
                ),
                const SizedBox(width: Sp.sm),
              ],
              Stack(children: [
                DeviceImage(brand: d.brand, model: d.model, size: 44),
                // Type icon صغير في الزاوية العلوى (لتمييز router عن switch عن link)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1),
                    ),
                    child: TypeIcon(
                        type: d.type, size: 10, color: AppColors.textMid),
                  ),
                ),
                // Status dot سفلى يمين
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
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
                      style: AppType.cardTitleBold(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(LucideIcons.globe,
                          size: 11, color: AppColors.textLow),
                      const SizedBox(width: 3),
                      Text(
                        d.ip,
                        style: AppType.muted(color: AppColors.textMid),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                        child: Text(
                          NetworkDeviceLabels.brandLabel(d.brand),
                          style: AppType.daysWord(color: AppColors.textMid),
                        ),
                      ),
                      if (d.protocol != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoftBg,
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                          child: Text(
                            // ⚠️ UBNT تُعرض SSH لا API: الاتّصال بها
                            // SSH على 22 فعليّاً، و«api» تسمية داخليّة.
                            // الشارة كانت تقول للمستخدم شيئاً غير صحيح.
                            (d.brand == 'ubnt' && d.protocol == 'api')
                                ? 'SSH'
                                : d.protocol!.toUpperCase(),
                            style: AppType.daysWordBold(color: AppColors.brand),
                          ),
                        ),
                      ],
                    ]),
                    // Region badge — يظهر إن كان الجهاز مسند لمنطقة (2026-08-18)
                    if (d.regionId != null &&
                        _regionsById[d.regionId!] != null) ...[
                      const SizedBox(height: 3),
                      Builder(builder: (_) {
                        final region = _regionsById[d.regionId!]!;
                        final color =
                            _parseRegionColor(region.color) ?? AppColors.brand;
                        return Row(children: [
                          Icon(LucideIcons.mapPin, size: 10, color: color),
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(R.pill),
                              border: Border.all(
                                  color: color.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              region.name,
                              style: AppType.daysWordBold(color: color),
                            ),
                          ),
                        ]);
                      }),
                    ],
                    if (d.location != null && d.location!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(LucideIcons.building2,
                            size: 10, color: AppColors.textLow),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            d.location!,
                            style: TextStyle(
                                fontSize: 10.5, height: 1.3, color: AppColors.textLow),
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
                      style: AppType.microBold(color: statusCol),
                    ),
                  const SizedBox(height: 4),
                  Icon(LucideIcons.chevronLeft,
                      size: 16, color: AppColors.textLow),
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
  const _EmptyDevices({this.hasActiveFilter = false, this.onClearFilter});
  final bool hasActiveFilter;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                  hasActiveFilter ? LucideIcons.filterX : LucideIcons.router,
                  size: 40,
                  color: AppColors.brand),
            ),
            const SizedBox(height: Sp.lg),
            Text(hasActiveFilter ? 'لا نتائج بهذا الفلتر' : 'لا توجد أجهزة',
                style: TextStyle(
                    fontSize: 16, height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 4),
            Text(
              hasActiveFilter
                  ? 'قد تكون كل الأجهزة مخفيّة — امسح الفلتر لرؤيتها'
                  : 'أضف أول جهاز شبكة من زرّ + أعلى الصفحة',
              style: AppType.body(color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
            if (hasActiveFilter && onClearFilter != null) ...[
              const SizedBox(height: Sp.md),
              TextButton.icon(
                onPressed: onClearFilter,
                icon: Icon(LucideIcons.x, size: 14, color: AppColors.brand),
                label: Text('مسح الفلتر',
                    style: TextStyle(color: AppColors.brand)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// يحوّل hex ("#RRGGBB" أو "RRGGBB") إلى Color، null لو غير صالح.
Color? _parseRegionColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
