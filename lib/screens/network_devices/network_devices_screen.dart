import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../api/network_devices_api.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../services/device_alerts_service.dart';
import '../../services/device_sweep_coordinator.dart';
import '../../services/device_warmup.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../widgets/skeleton.dart';
import 'bulk_scan_screen.dart';
import 'device_alerts_screen.dart';
import 'device_sort.dart';
import 'probe_backoff.dart';
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
import '../../core/util/fit_hint.dart';
import '../top_actions.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/platform/desktop_layout.dart';
import '../desktop/desk_table_scroll.dart';

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

  /// مُرشِّح المنطقة. `null` = الكلّ، و[_kNoRegion] = «بلا منطقة».
  /// وهذه الأخيرة ليست ترفاً: أجهزةٌ لم تُسنَد إلى منطقة تضيع في
  /// القائمة، ولا سبيل إلى جمعها لتصنيفها إلّا بمُرشِّحٍ لها.
  int? _regionFilter;
  static const int _kNoRegion = -1;
  String _search = '';
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  // Selection mode — long-press لتنشيطه، tap يبدّل عنصر، exit بزرّ الـclose. 2026-08-18.
  bool _selectionMode = false;

  /// الحاسبة: جدولٌ (كبرامج مراقبة الشبكات) أو بطاقات — يبقى اختيار الجلسة بين الزيارات.
  static bool _deskTableView = true;
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
  DeviceSortField _sortField = DeviceSortField.ip;
  SortDir _sortDir = SortDir.asc;

  int _probeRoundCount = 0;

  /// طلب فحصٍ شاملٍ وصل وجولةٌ جارية — يُنفَّذ بعدها. راجع [_probeAll].
  bool _forcePending = false;

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
    // التسخين خدمةٌ لهذه الشاشة — يتوقّف بخروجها فلا يستنزف الشبكة
    // والمستخدم في مكانٍ آخر.
    DeviceWarmup.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    widget.isActive?.removeListener(_onActiveChanged);
    _probeTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _devHScroll.dispose();
    super.dispose();
  }

  /// عند background نوقف الـtimer (توفير باتري) — عند resumed نُشغّله + probe فوري
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _probeTimer?.cancel();
      // ⚠️ والتسخين معه: خدمةٌ صامتة لا معنى لها والتطبيق في الخلفيّة،
      // وتركُها تستنزف الشبكة والبطّاريّة بلا ناظر.
      DeviceWarmup.instance.stop();
    } else if (state == AppLifecycleState.resumed) {
      _startProbeTimer();
      // probe فوري لتحديث الحالة بعد العودة
      if (_all.isNotEmpty) {
        _probeAll(force: true);
        // يستأنف من حيث وقف — ما سُخِّن لا يُعاد.
        DeviceWarmup.instance.start(_all);
      }
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
      if (_all.isNotEmpty) _probeAll(force: true);
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
    // ⚠️ المؤقّت وحده بلا `force` — هو صاحب التباطؤ وسببُ وجوده.
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
        _recomputeRegionCounts();
        _loading = false;
      });
      // 🔥 probe فوري — لا ننتظر 20s للـTimer الأوّل.
      // تسخينٌ صامت في الخلفيّة: يملأ مخزن القراءات ما دام المدير
      // هنا، فيكون فتحُ أيّ جهازٍ فوريّاً. راجع [DeviceWarmup].
      DeviceWarmup.instance.start(_all);
      _probeAll(force: true);
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
        _recomputeRegionCounts();
        _error = null;
      });
      await _probeAll(force: true);
    } catch (e) {
      // فشل الـlist fetch لا يوقف الـprobe — الأجهزة القديمة تُفحص كما هي.
      if (_all.isNotEmpty) {
        await _probeAll(force: true);
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
  bool _shouldProbeInRound(int deviceId, {required bool force}) =>
      deviceProbeDue(
        force: force,
        consecutiveFailures: _consecutiveFailures[deviceId] ?? 0,
        round: _probeRoundCount,
      );

  /// [force] يتخطّى تباطؤ الفشل ويفحص **كلّ** جهاز.
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٠٤: «الدخول ع الأجهزة يجلب ٣ ويوقف، أخرج
  /// وأرجع للقسم ٣ مرّات حتّى يظهرهم كلّهم».
  ///
  /// والسبب أنّ التباطؤ كان يُطبَّق على **كلّ** استدعاء. وهو مقصودٌ
  /// للمؤقّت وحده (جولة كلّ ٢٠ ثانية بلا ناظر)، بينما دخول التبويب
  /// وسحب التحديث والعودة من الخلفيّة كلّها أفعال **يطلبها المستخدم**
  /// وينتظر جوابها الآن.
  ///
  /// ولماذا كانت ثلاثة بالذات: هاتف المدير غالباً على بيانات الجوّال لا
  /// على شبكة الأجهزة، فتتراكم إخفاقاتها حتّى تبلغ السقف ٦. وشاشة
  /// التبويب داخل `IndexedStack` **لا تُهدَم**، فيبقى `_probeRoundCount`
  /// و`_consecutiveFailures` حيّين طوال عمر التطبيق. فكلّ دخولٍ يفحص من
  /// تقسم دورتُه رقمَ الجولة وحده — أقلّيّةٌ تتبدّل في كلّ مرّة، وثلاث
  /// دخلاتٍ تلزم لتغطية الجميع. وهو بالضبط ما وصفه المستخدم.
  Future<void> _probeAll({bool force = false}) async {
    // ⚠️ جولةٌ جارية لا تُسقط طلب المستخدم بل تؤجّله.
    //
    // المؤقّت يطلق كلّ ٢٠ ثانية، فاحتمال أن يدخل المدير التبويب أثناء
    // جولةٍ سارية عالٍ. والحارس القديم كان يبتلع الطلب صامتاً — فيدخل
    // المدير فلا يتحدّث شيء، وهو نصف الشكوى.
    if (_probing) {
      if (force) _forcePending = true;
      return;
    }
    if (_all.isEmpty || !_mayProbe) return;
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

      // ── دفقٌ تدريجيّ مخنوق ──────────────────────────────────────
      //
      // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «فحص الأجهزة بطيء بالعرض، كأنّه ينتظر
      // جواب جهاز جهاز».
      //
      // والجولة كانت ترسم **مرّةً واحدة بعد اكتمالها كلّها**: ثمانون
      // جهازاً على أربعة وعشرين عاملاً، والمنقطع يستهلك مهلته كاملةً
      // (ثانيتان) — فأربع موجاتٍ = ثماني ثوانٍ من الجمود قبل أن يتحرّك
      // شيء. والحال أنّ أوّل جهازٍ ردّ بعد جزءٍ من الثانية.
      //
      // ⚠️ ولا setState لكلّ جهاز: التعليق أدناه يشرح لماذا (ثمانون
      // إعادة بناء كاملة للقائمة = إطارات ساقطة). الخنق يجمع بينهما —
      // دفعةٌ كلّ ٤٠٠ms، أي رسمتان أو ثلاث في الثانية على الأكثر.
      var pendingFlush = false;
      void flush() {
        if (!mounted || updates.isEmpty) return;
        setState(() {
          for (var i = 0; i < _all.length; i++) {
            final u = updates[_all[i].id];
            if (u != null) _all[i] = u;
          }
        });
      }

      void scheduleFlush() {
        if (pendingFlush) return;
        pendingFlush = true;
        Future.delayed(const Duration(milliseconds: 400), () {
          pendingFlush = false;
          flush();
        });
      }

      // ⚠️ طابور عمّال بسقف، لا `Future.wait` على الكلّ.
      //
      // كان المسح يفتح مقبساً لكلّ جهاز دفعةً — ثمانون معاً على أكبر
      // حساب اليوم. يعمل لأنّ فحص TCP رخيص، لكن لا سقف يمنع حساباً
      // بثلاثمئة جهاز من فتح ثلاثمئة مقبس. السقف نفسه المُختبَر في
      // `bulkScanSubnet`.
      final queue = Queue<NetworkDevice>.from(
          _all.where((d) => _shouldProbeInRound(d.id, force: force)));
      Future<void> probeWorker() async {
        while (queue.isNotEmpty) {
          final d = queue.removeFirst();
          try {
            // الطريقة تتبع البروتوكول: TCP لميكروتك وUBNT، وSNMP على
            // UDP لمنفذ ١٦١، وICMP لمن لا منفذ له. راجع [probeDevice].
            final r = await NetworkDevicesApi.probeDevice(d);
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
            scheduleFlush();
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

      // رسمةٌ ختاميّة: تضمن وصول ما جاء بعد آخر خنق.
      flush();

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
      // طلبٌ وصل أثناء الجولة — يُنفَّذ الآن بدل أن يضيع.
      if (_forcePending && mounted) {
        _forcePending = false;
        unawaited(_probeAll(force: true));
      }
    }
  }

  Future<void> _openForm({NetworkDevice? existing}) async {
    final result = await showAppSheet<NetworkDevice>(
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
      // ⚠️ كان هنا `_consecutiveFailures.clear()` — التفافٌ موضعيّ على
      // العطل نفسه الذي بلّغ عنه المستخدم لاحقاً في التبويب كلّه. وهو
      // يعمل لكنّه يمحو تباطؤ **كلّ** الأجهزة، فتُقصَف المنقطعة ستّ
      // جولاتٍ كاملة قبل أن يستقرّ التباطؤ من جديد.
      //
      // و`force` يفعل المقصود بلا هدم: جولةٌ شاملةٌ واحدة، والتباطؤ
      // يبقى محفوظاً لما بعدها.
      _probeAll(force: true);
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
  Future<void> _pickSort() async {
    final r = await showDeviceSortSheet(
      context,
      field: _sortField,
      dir: _sortDir,
    );
    if (r == null || !mounted) return;
    setState(() {
      _sortField = r.field;
      _sortDir = r.dir;
    });
  }

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

  /// عنصر قائمةٍ منسدلة بأيقونةٍ ونصّ — شكلٌ واحد لكلّ العناصر.
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMid),
          const SizedBox(width: 10),
          // ⚠️ `Expanded` لا نصٌّ عارٍ: «الترتيب · اسم الحقل» قد يطول،
          //    وصفٌّ فيه نصٌّ بلا مرونة يفيض ويُرسم شريطاً أصفر.
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  List<NetworkDevice> get _filtered {
    final q = _search.trim().toLowerCase();
    final result = _all.where((d) {
      if (_typeFilter != null && d.type != _typeFilter) return false;
      if (_statusFilter != null && d.lastStatus != _statusFilter) return false;
      if (_regionFilter != null) {
        if (_regionFilter == _kNoRegion) {
          if (d.regionId != null) return false;
        } else if (d.regionId != _regionFilter) {
          return false;
        }
      }
      if (q.isNotEmpty) {
        // اسم المنطقة جزءٌ من الكومة: المنطقة تُعرَض على كلّ كرت،
        // والبحث الذي لا يجد ما تراه العين يبدو مكسوراً.
        final regionName = d.regionId == null
            ? ''
            : (_regionsById[d.regionId!]?.name ?? '');
        final haystack =
            '${d.name} ${d.ip} ${d.mac ?? ''} ${d.location ?? ''} ${d.model ?? ''} $regionName'
                .toLowerCase();
        if (!haystack.contains(q)) return false;
      }
      return true;
    }).toList();
    // 2026-08-18: كان ترتيباً ثابتاً بالـIP تصاعديّاً. صار قابلاً
    // للاختيار (٢٠٢٦-٠٩-٠٢) بنفس وحدة «نظرة عامّة» — شاشتان تعرضان
    // الأجهزة نفسها يجب ألّا ترتّباها بمنطقين.
    result.sort((a, b) => compareDevices(a, b, _sortField, _sortDir));
    return result;
  }

  int _countByType(String type) => _all.where((d) => d.type == type).length;

  /// عدد الأجهزة لكلّ منطقة — يُحسَب **مرّةً عند تغيّر البيانات**.
  ///
  /// 🐛 كان يُحسَب في كلّ بناء: صفّ المناطق يُعاد بناؤه مع كلّ ضغطة
  /// مفتاح في البحث ومع كلّ نبضة فحص، وكلّ شريحةٍ تمسح قائمة الأجهزة
  /// كاملة. أربعون منطقة × ألفا جهاز = ثمانون ألف فحصٍ في الإطار
  /// الواحد — تلعثمٌ مرئيّ على كلّ حرفٍ يُكتب.
  Map<int?, int> _regionCounts = const {};

  void _recomputeRegionCounts() {
    final m = <int?, int>{};
    for (final d in _all) {
      m[d.regionId] = (m[d.regionId] ?? 0) + 1;
    }
    _regionCounts = m;
  }

  int _countByRegion(int? regionId) =>
      _regionCounts[regionId == _kNoRegion ? null : regionId] ?? 0;
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
    // يشقّ العنوانين ويُجري أربع `int.tryParse` لكلّ طرف. وكان
    // يُستدعى داخل `itemBuilder` — أي فرزةٌ كاملة لكلّ صفّ مرسوم،
    // فقائمةٌ من 40 جهازاً تُفرَز 40 مرّة في الإطار الواحد.
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
    // ٢٠ أكتوبر (طلب المالك): لا AppBar — رأس التبويب الموحّد كباقي التبويبات:
    // «الأجهزة» يميناً، وأزرار الأعلى المشتركة (المساعد · الجرس · الترس)
    // يساراً بمكانها من كلّ تبويب ([TabHeader]).
    //
    // وأدوات القائمة التي كان الشريط يحملها (تنبيهات الأجهزة · التحديث ·
    // المزيد · الإضافة) نزلت جنب البحث في سطرٍ **مثبَّت** ([_toolsBar]): تبقى
    // ظاهرةً مع التمرير كما كانت، والعنوان وحده يمرّ مع القائمة — فالمساحة
    // الثابتة أعلى الشاشة كما كانت تقريباً (سطرٌ مكان الشريط).
    //
    // ⚠️ والسطر نفسه يظهر أثناء التحميل والخطأ (بلا تمرير): «تحديث» هو طريق
    // إعادة المحاولة الوحيد بعد فشل التحميل، و«+» يضيف أوّل جهاز.
    const header = Padding(
      padding: EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
      child: TabHeader(title: 'الأجهزة'),
    );
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: _loading || _error != null
            ? Column(
                children: [
                  header,
                  _toolsBar(),
                  Expanded(
                    child: _loading
                        ? const SkeletonDeviceList()
                        : Center(
                            child: Text(_error!,
                                style: TextStyle(color: AppColors.textMid))),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: DeskHScrollInput(
                  scroll: _devHScroll,
                  child: CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(child: header),
                    // البحث والأدوات — مثبَّتان أعلى القائمة (مكان الشريط).
                    PinnedHeaderSliver(child: _toolsBar()),
                    // Summary row: total + online + offline
                    SliverToBoxAdapter(child: _summaryRow()),
                    // Type filters (chips الحالة أُزيلت — تدمج بكارتات الملخّص)
                    SliverToBoxAdapter(child: _typeFilterRow()),
                    SliverToBoxAdapter(child: _regionFilterRow()),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    // List
                    devices.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyDevices(
                              hasActiveFilter: _all.isNotEmpty &&
                                  (_typeFilter != null ||
                                      _statusFilter != null ||
                                      _regionFilter != null ||
                                      _search.isNotEmpty),
                              onClearFilter: () => setState(() {
                                _typeFilter = null;
                                _statusFilter = null;
                                _regionFilter = null;
                                _search = '';
                                _searchCtrl.clear();
                              }),
                            ),
                          )
                        : SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                                Sp.md, 0, Sp.md, Inset.tabBar(context)),
                            sliver: _deviceList(devices),
                          ),
                  ],
                )),
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
                    padding: EdgeInsets.fromLTRB(
                        Sp.md, 0, Sp.md, Inset.tabBar(context)),
                    sliver: _deviceList(devices),
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
            // «الإجمالي» المختار بحبّة القائمة الرماديّة لا بإطارٍ أسود سميك؛ والمتّصل/المفصول بلونهما الخفيف.
            decoration: BoxDecoration(
              color: !active
                  ? AppColors.surface
                  : filterStatus == null
                      ? AppColors.surfaceSunken
                      : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(
                color: !active
                    ? AppColors.border
                    : filterStatus == null
                        ? AppColors.borderStrong
                        : color.withValues(alpha: 0.55),
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

  /// البحث بعرض الشاشة — لوضع التحديد (رأسه شريط العدد والإجراءات).
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
      child: _searchField(),
    );
  }

  /// سطر البحث وأدوات القائمة — كانت الأدوات في الشريط العلويّ حتى ٢٠ أكتوبر،
  /// ثمّ صار رأس التبويب الموحّد ([TabHeader]) فنزلت جنب البحث، والسطر مثبَّتٌ
  /// أعلى القائمة فتبقى ظاهرةً مع التمرير كما كانت.
  ///
  /// ⚠️ كانت سبعة أزرارٍ في الشريط فقُصّ العنوان إلى «الأ…»؛ والبقاء ظاهراً حقٌّ
  /// يُكتسب: الإضافة والتحديث يُستعملان في كلّ زيارة، والتنبيهات تحمل **عدداً**
  /// لا يُرى داخل قائمة مطويّة. وما عداها يُفتح مرّةً كلّ حين فمكانه «المزيد».
  /// والدوّارات لا تدخل القائمة: الفحص والكشف يُريان وهما يعملان، مكان زرّيهما.
  Widget _toolsBar() {
    // الأدوات بمقاس أزرار الأعلى وفراغها، وطرفها على حشوة الرأس (‎16) — فكلّ
    // أداةٍ تحت نظيرها فوقها، والبحث على حافّة المحتوى تحته (‎12).
    final gap = TopActionChip.gapOf(context);
    return ColoredBox(
      color: AppColors.bg,
      child: Padding(
        padding:
            const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.lg, Sp.xs),
        child: Row(
          children: [
            Expanded(child: _searchField()),
            const SizedBox(width: Sp.sm),
            // تنبيهات الأجهزة (فصلٌ/عودة) بعددها — والضغط المطوّل إشعارٌ
            // تجريبيّ. صفّارةٌ لا جرس: جرس الإشعارات في أزرار الأعلى فوقها
            // مباشرةً، وجرسان في شاشةٍ واحدة لا يُعرف أيّهما لأيّ شيء.
            ValueListenableBuilder<int>(
              valueListenable: DeviceAlertsService.instance.unreadCount,
              builder: (context, count, _) => _ToolButton(
                tooltip: 'تنبيهات الأجهزة (اضغط مطوّلاً للاختبار)',
                onTap: _openAlerts,
                onLongPress: _testAlert,
                badge: count,
                child: Icon(
                  LucideIcons.siren,
                  size: 20,
                  color: count > 0 ? AppColors.error : AppColors.textBody,
                ),
              ),
            ),
            // الحاسبة: جدول ⇄ بطاقات.
            if (DesktopScope.of(context)) ...[
              SizedBox(width: gap),
              _ToolButton(
                tooltip: _deskTableView ? 'عرض بطاقات' : 'عرض جدول',
                onTap: () => setState(() => _deskTableView = !_deskTableView),
                child: Icon(_deskTableView ? LucideIcons.layoutGrid : LucideIcons.table2,
                    size: 20, color: AppColors.textBody),
              ),
            ],
            SizedBox(width: gap),
            // تحديث فوري — دوّارةٌ مكانه أثناء الفحص.
            _ToolButton(
              tooltip: 'تحديث فوري',
              busy: _probing,
              onTap: _refresh,
              child:
                  Icon(LucideIcons.refreshCw, size: 20, color: AppColors.textBody),
            ),
            SizedBox(width: gap),
            // ── ما تبقّى في قائمةٍ منسدلة — ودوّارة الكشف مكانها وهو يعمل ──
            _ToolButton(
              busy: _detecting,
              wrap: (content) => PopupMenuButton<String>(
                tooltip: 'المزيد',
                borderRadius: BorderRadius.circular(R.icon),
                onSelected: (v) {
                  switch (v) {
                    case 'wall':
                      _openWall();
                    case 'sort':
                      _pickSort();
                    case 'regions':
                      _openRegions();
                    case 'scan':
                      _openBulkScan();
                    case 'detect':
                      _detectModels();
                  }
                },
                itemBuilder: (_) => [
                  _menuItem('wall', LucideIcons.layoutGrid, 'نظرة عامّة'),
                  // الترتيب الحاليّ في التسمية — القائمة المطويّة تُخفي
                  // الأيقونة التي كانت تدلّ عليه.
                  _menuItem(
                      'sort', _sortField.icon, 'الترتيب · ${_sortField.label}'),
                  if (Perms.has('devices.manage'))
                    _menuItem('regions', LucideIcons.mapPin, 'إدارة المناطق'),
                  if (Perms.has('devices.manage'))
                    _menuItem(
                        'scan', LucideIcons.radar, 'اكتشاف أجهزة الشبكة'),
                  // كشف الطُرُز — لا يظهر إلّا حين يوجد جهاز يحتاجه، ولا
                  // يُشغَّل تلقائيّاً لأنّه يفتح جلسة مصادَقة على كلّ
                  // جهاز، وذلك قرار المستخدم لا سلوك خفيّ.
                  if (_all.any(DetectedModel.needsDetection))
                    _menuItem('detect', LucideIcons.scanSearch,
                        'كشف طُرُز الأجهزة'),
                ],
                child: content,
              ),
              child: Icon(LucideIcons.ellipsisVertical,
                  size: 20, color: AppColors.textBody),
            ),
            // إضافة جهاز — لمن يملك الإدارة وحده.
            if (Perms.has('devices.manage')) ...[
              SizedBox(width: gap),
              _ToolButton(
                filled: true,
                tooltip: 'إضافة جهاز',
                onTap: () => _openForm(),
                child: const Icon(LucideIcons.plus,
                    size: 18, color: AppColors.onBrand),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// حقل البحث وحده — في سطر الأدوات ([_toolsBar]) وفي وضع التحديد.
  Widget _searchField() {
    final hintStyle = AppType.subtitle(color: AppColors.textLow);
    const fieldStyle = TextStyle(fontSize: 14, height: 1.3);
    return LayoutBuilder(
      builder: (context, c) => TextField(
        controller: _searchCtrl,
        // 2026-08-18: debounce 250ms — للـ500+ جهاز، كل keystroke بدون
        // debounce = filter+sort ثقيل على main thread (jank محسوس).
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 250), () {
            if (mounted) setState(() => _search = v);
          });
        },
        style: fieldStyle,
        decoration: InputDecoration(
          // الحقل يتشارك سطره مع الأدوات: أطول تلميحٍ يُقرأ كاملاً بدل بترٍ
          // بـ«…». خارج النصّ كما يحسبه `InputDecorator` (M3 بحدٍّ محيط):
          // مربّع أيقونة البحث ‎48 وفراغها ‎4، ثمّ الحشوة الختاميّة ‎14 وفراغ
          // الحدّ ‎4.
          hintText: fittingHint(
            context,
            maxWidth: c.maxWidth - 48 - 4 - 14 - 4,
            style: hintStyle,
            fieldStyle: fieldStyle,
            candidates: const [
              'ابحث باسم أو IP أو MAC أو موقع…',
              'ابحث باسم أو IP أو MAC…',
              'ابحث باسم أو IP…',
              'اسم أو IP…',
              // ‎360 (أشيع عرض): «اسم أو IP…» يزيد نقطةً عن مكانه — فبلا النقاط
              // قبل أن ننزل إلى «بحث».
              'اسم أو IP',
              'بحث',
            ],
          ),
          hintStyle: hintStyle,
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

  /// صفّ المناطق — يظهر فقط حين توجد مناطق فعلاً.
  ///
  /// بلا هذا كانت المنطقة شارةً على الكرت لا أكثر: تُرى ولا يُبنى
  /// عليها. وشبكة المزوّد تُدار بالمناطق — «أيّ أجهزة الكرادة معطّلة؟»
  /// سؤالٌ يوميّ لم يكن له جواب إلّا بالقراءة اليدويّة.
  Widget _regionFilterRow() {
    if (_regionsById.isEmpty) return const SizedBox.shrink();
    final regions = _regionsById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final orphans = _countByRegion(_kNoRegion);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _regionChip(null, 'كلّ المناطق', _all.length, AppColors.brand),
          const SizedBox(width: 6),
          for (final r in regions) ...[
            _regionChip(r.id, r.name, _countByRegion(r.id),
                _parseRegionColor(r.color) ?? AppColors.brand),
            const SizedBox(width: 6),
          ],
          if (orphans > 0)
            _regionChip(_kNoRegion, 'بلا منطقة', orphans, AppColors.textMid),
        ]),
      ),
    );
  }

  Widget _regionChip(int? id, String label, int count, Color color) {
    final active = _regionFilter == id;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _regionFilter = active ? null : id);
      },
      borderRadius: BorderRadius.circular(R.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(
            color: active ? color : AppColors.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppType.bodyStrong(
                  color: active ? color : AppColors.textHi)),
          const SizedBox(width: 5),
          Text('$count',
              style: TextStyle(
                  fontSize: 10.5,
                  height: 1.3,
                  fontWeight: FontWeight.bold,
                  color: active ? color : AppColors.textMid)),
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

  /// القائمة: على الحاسبة شبكة بطاقاتٍ بأعمدة (بعرضٍ أقصى وارتفاعٍ ثابت) بدل بطاقاتٍ ممدودة بعرض
  /// الشاشة — والبطاقة نفسها في الحالتين، تُبنى عند ظهورها وحدها.
  Widget _deviceList(List<NetworkDevice> devices) {
    if (DesktopScope.of(context)) {
      if (_deskTableView) return _deskTable(devices);
      return SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisExtent: 168,
          crossAxisSpacing: Sp.md,
          mainAxisSpacing: Sp.md,
        ),
        itemCount: devices.length,
        itemBuilder: (_, i) => _deskDeviceCard(devices[i]),
      );
    }
    return SliverList.separated(
      itemCount: devices.length,
      itemBuilder: (_, i) => _deviceCard(devices[i]),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
    );
  }

  // ═══════════════ الحاسبة: جدول الأجهزة وبطاقاتها الكبيرة ═══════════════
  // المالك (٢٣ أكتوبر): «الأجهزة معلوماتها زغيرة… لا موبايل ولا PC» — برامج الإدارة ومراقبة الأجهزة على
  // الحاسبة جداول بأعمدةٍ واضحة وحالةٍ مقروءة من بعيد. الهاتف لا يتغيّر (DesktopScope وحده).

  static String _statusLabel(String s) => switch (s) {
        'online' => 'متصل',
        'offline' => 'مفصول',
        _ => 'غير معروف',
      };

  /// «منذ ٤ دقائق» من `status_since` (يتحرّك عند التحوّل وحده) — null لغيابه أو لوقتٍ قادم.
  static String? _since(DateTime? since) {
    if (since == null) return null;
    final d = DateTime.now().difference(since);
    if (d.isNegative) return null;
    if (d.inMinutes < 1) return 'منذ لحظات';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
    return 'منذ ${d.inDays} يوماً';
  }

  static String _clockOf(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _statusPill(NetworkDevice d, {bool big = false}) {
    final col = _statusColor(d.lastStatus);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 10 : 8, vertical: big ? 5 : 3),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            _statusLabel(d.lastStatus),
            style: AppType.label(color: col).copyWith(fontSize: big ? 13.5 : 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget? _deskRegion(NetworkDevice d) {
    final region = d.regionId == null ? null : _regionsById[d.regionId!];
    if (region == null) return null;
    final color = _parseRegionColor(region.color) ?? AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(region.name, style: AppType.daysWordBold(color: color)),
    );
  }

  /// أعمدة الجدول: المفتاح، التسمية، حصّة العرض الافتراضيّة، وأضيق ما يُسحب إليه.
  static const _deskCols = <(String, String, int, double)>[
    ('status', 'الحالة', 15, 96),
    ('device', 'الجهاز', 30, 180),
    ('model', 'الطراز', 18, 96),
    ('ip', 'العنوان', 15, 110),
    ('location', 'الموقع', 16, 90),
    ('response', 'الاستجابة', 10, 76),
    ('probed', 'آخر فحص', 9, 76),
  ];

  // ── عروض الأعمدة (المالك ٢٤ أكتوبر: «الجدول بيه صلاحيّة يلگص ويزيد حجم الأعمدة» و«يمرر ويسحب») ──
  // افتراضيّاً كما كانت: الأعمدة تملأ العرض بحصصها. أوّل سحبٍ لحافّة عمودٍ يثبّت العروض كلّها على ما تظهر
  // به ثمّ يغيّر العمود؛ وما لا يتّسع يتمرّر أفقيّاً و«الحالة» و«الجهاز» ثابتان في البداية. النقر المزدوج على
  // الحافّة يعيد العمود لحصّته، وتُحفظ على هذا الجهاز.
  static const _kDevWidths = 'desk.devices.colwidths.v1';
  static Map<String, double> _devWidths = const {};
  static bool _devWidthsLoaded = false;
  final DeskHScroll _devHScroll = DeskHScroll();

  /// مرّةً لكلّ تشغيل — صامتٌ إن تعذّرت الخزنة (الحصص الافتراضيّة تبقى).
  void _loadDevWidths() {
    if (_devWidthsLoaded) return;
    _devWidthsLoaded = true;
    const FlutterSecureStorage().read(key: _kDevWidths).then((raw) {
      final out = <String, double>{};
      for (final part in (raw ?? '').split(',')) {
        final kv = part.split(':');
        final v = kv.length == 2 ? double.tryParse(kv[1]) : null;
        if (v != null && v > 0 && _deskCols.any((c) => c.$1 == kv[0])) out[kv[0]] = v;
      }
      if (out.isNotEmpty && mounted) setState(() => _devWidths = Map.unmodifiable(out));
    }).catchError((_) {});
  }

  void _saveDevWidths() {
    final raw = _devWidths.entries.map((e) => '${e.key}:${e.value.round()}').join(',');
    const FlutterSecureStorage().write(key: _kDevWidths, value: raw).catchError((_) {});
  }

  /// ما يأخذه الصفّ غير الأعمدة: الحشوتان والسهم وحدّا الجدول (ومربّع التحديد في وضعه).
  double get _devFixed => 2 * Sp.lg + 20 + 2 + (_selectionMode ? 32 : 0);

  /// عروض الأعمدة لجدولٍ بعرض [tableWidth]، ونافذة الأعمدة المتمرّرة (ما بعد «الجهاز») ومحتواها.
  ({Map<String, double> w, double viewport, double content}) _devLayout(double tableWidth) {
    final avail = tableWidth - _devFixed > 0 ? tableWidth - _devFixed : 0.0;
    final flexSum = _deskCols.fold<int>(0, (s, c) => s + c.$3);
    final w = <String, double>{};
    for (final c in _deskCols) {
      final share = avail * c.$3 / flexSum;
      w[c.$1] = _devWidths.isEmpty ? share : (_devWidths[c.$1] ?? share).clamp(c.$4, 900).toDouble();
    }
    // «الجهاز» لا يأكل نافذة الأعمدة المتمرّرة كلّها.
    final maxDevice = avail - w['status']! - 160;
    if (w['device']! > maxDevice) w['device'] = maxDevice > 180 ? maxDevice : 180;
    final viewport = avail - w['status']! - w['device']!;
    final middle = _deskCols.skip(2).fold<double>(0, (s, c) => s + w[c.$1]!);
    final vp = viewport > 0 ? viewport : 0.0;
    return (w: w, viewport: vp, content: middle > vp ? middle : vp);
  }

  void _resizeDevCol(Map<String, double> shown, String key, double delta) {
    final live = _devWidths.isEmpty ? Map<String, double>.from(shown) : Map<String, double>.from(_devWidths);
    final c = _deskCols.firstWhere((c) => c.$1 == key);
    live[key] = ((live[key] ?? shown[key]!) + delta).clamp(c.$4, 900).toDouble();
    setState(() => _devWidths = Map.unmodifiable(live));
  }

  void _resetDevCol(String key) {
    if (!_devWidths.containsKey(key)) return;
    setState(() => _devWidths = Map.unmodifiable({..._devWidths}..remove(key)));
    _saveDevWidths();
  }

  /// السحب الأفقيّ بالفأرة على الرأس أو صفٍّ يمرّر الأعمدة حين يكون هناك ما يتمرّر.
  Widget _devDrag(bool scrolls, Widget child) {
    if (!scrolls) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _devHScroll.scrollBy(rtl ? d.delta.dx : -d.delta.dx),
      child: child,
    );
  }

  Widget _deskTable(List<NetworkDevice> devices) {
    _loadDevWidths();
    return SliverLayoutBuilder(builder: (context, constraints) {
      final lay = _devLayout(constraints.crossAxisExtent);
      _devHScroll.setMetrics(viewport: lay.viewport, content: lay.content);
      final scrolls = lay.content - lay.viewport > 0.5;
      final label = AppType.label(color: AppColors.textMid).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700);
      Widget headCell((String, String, int, double) c) => SizedBox(
            width: lay.w[c.$1],
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(c.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: label),
                  ),
                ),
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  child: DeskColResizeHandle(
                    tooltip: 'اسحب لتغيير العرض — نقرتان تعيدانه',
                    onDrag: (d) => _resizeDevCol(lay.w, c.$1, d),
                    onEnd: _saveDevWidths,
                    onReset: () => _resetDevCol(c.$1),
                  ),
                ),
              ],
            ),
          );
      final head = _devDrag(
        scrolls,
        Container(
          padding: const EdgeInsets.fromLTRB(Sp.lg, 12, Sp.lg, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            children: [
              // ارتفاعٌ ثابت: خلايا الرأس (والمقبض فوق حافّتها) Stack لا يتقلّص على محتواه.
              SizedBox(
                height: 24,
                child: Row(
                children: [
                  if (_selectionMode) const SizedBox(width: 32),
                  headCell(_deskCols[0]),
                  headCell(_deskCols[1]),
                  Expanded(
                    child: DeskHViewport(
                      scroll: _devHScroll,
                      contentWidth: lay.content,
                      edgeShadows: scrolls,
                      child: Row(children: [for (final c in _deskCols.skip(2)) headCell(c), const Spacer()]),
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
              ),
              ),
              // شريط التمرير الأفقيّ تحت الرأس، بمحاذاة الأعمدة المتمرّرة.
              if (scrolls)
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: (_selectionMode ? 32 : 0) + lay.w['status']! + lay.w['device']!,
                    end: 20,
                    top: 6,
                  ),
                  child: DeskHScrollbar(scroll: _devHScroll),
                ),
            ],
          ),
        ),
      );
      return DecoratedSliver(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: head),
            SliverList.separated(
              itemCount: devices.length,
              itemBuilder: (_, i) => _devDrag(scrolls, _deskRow(devices[i], lay.w, lay.content, scrolls, last: i == devices.length - 1)),
              separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: AppColors.border),
            ),
          ],
        ),
      );
    });
  }

  Widget _deskRow(NetworkDevice d, Map<String, double> w, double content, bool scrolls, {required bool last}) {
    final selected = _selectionMode && _selectedIds.contains(d.id);
    final canManage = Perms.has('devices.manage');
    final online = d.lastStatus == 'online';
    final since = _since(d.statusSince);
    final region = _deskRegion(d);
    final cell = AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5);
    final sub = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5);
    Widget col(String key, Widget child) => SizedBox(
          width: w[key],
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: Sp.sm),
            child: Align(alignment: AlignmentDirectional.centerStart, child: child),
          ),
        );
    return Material(
      color: selected ? AppColors.brandSoftBg : Colors.transparent,
      borderRadius: last ? const BorderRadius.vertical(bottom: Radius.circular(R.lg)) : null,
      child: InkWell(
        onTap: _selectionMode ? () => _toggleSelected(d) : () => _openDetails(d),
        onLongPress: canManage && !_selectionMode ? () => _enterSelection(d) : null,
        borderRadius: last ? const BorderRadius.vertical(bottom: Radius.circular(R.lg)) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: 10),
          child: Row(
            children: [
              if (_selectionMode)
                SizedBox(
                  width: 32,
                  child: Icon(selected ? LucideIcons.checkSquare : LucideIcons.square,
                      size: 18, color: selected ? AppColors.brand : AppColors.textLow),
                ),
              col(
                'status',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusPill(d),
                    if (since != null) ...[
                      const SizedBox(height: 3),
                      Text(since, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                    ],
                  ],
                ),
              ),
              col(
                'device',
                Row(
                  children: [
                    DeviceImage(brand: d.brand, model: d.model, size: 44),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: cell.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                          Text(NetworkDeviceLabels.typeLabel(d.type),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: DeskHViewport(
                    scroll: _devHScroll,
                    contentWidth: content,
                    edgeShadows: scrolls,
                    child: Row(
                      children: [
                        col(
                          'model',
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(NetworkDeviceLabels.brandLabel(d.brand),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: cell),
                              if ((d.model ?? '').isNotEmpty)
                                Text(d.model!, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
                            ],
                          ),
                        ),
                        col(
                          'ip',
                          Text(d.ip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: cell.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                        col(
                          'location',
                          region ??
                              Text((d.location ?? '').isEmpty ? '—' : d.location!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: cell.copyWith(color: AppColors.textMid)),
                        ),
                        col(
                          'response',
                          Text(
                            online && d.lastResponseMs != null ? '${d.lastResponseMs} ms' : '—',
                            textDirection: TextDirection.ltr,
                            style: cell.copyWith(
                              fontWeight: FontWeight.w700,
                              color: online ? _statusColor(d.lastStatus) : AppColors.textLow,
                            ),
                          ),
                        ),
                        col(
                          'probed',
                          Text(_clockOf(d.lastProbedAt),
                              textDirection: TextDirection.ltr, style: cell.copyWith(color: AppColors.textMid)),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deskDeviceCard(NetworkDevice d) {
    final selected = _selectionMode && _selectedIds.contains(d.id);
    final canManage = Perms.has('devices.manage');
    final online = d.lastStatus == 'online';
    final statusCol = _statusColor(d.lastStatus);
    final since = _since(d.statusSince);
    final region = _deskRegion(d);
    final sub = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5);
    Widget metric(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro()),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: color ?? AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: _selectionMode ? () => _toggleSelected(d) : () => _openDetails(d),
        onLongPress: canManage && !_selectionMode ? () => _enterSelection(d) : null,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: selected ? AppColors.brand : AppColors.border, width: selected ? 1.5 : 1),
          ),
          padding: const EdgeInsets.all(Sp.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (_selectionMode) ...[
                    Icon(selected ? LucideIcons.checkSquare : LucideIcons.square,
                        size: 20, color: selected ? AppColors.brand : AppColors.textLow),
                    const SizedBox(width: Sp.sm),
                  ],
                  DeviceImage(brand: d.brand, model: d.model, size: 76),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(d.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(
                          [
                            NetworkDeviceLabels.brandLabel(d.brand),
                            if ((d.model ?? '').isNotEmpty) d.model!,
                            NetworkDeviceLabels.typeLabel(d.type),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sub,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  _statusPill(d, big: true),
                ],
              ),
              const SizedBox(height: Sp.sm),
              Row(
                children: [
                  Icon(LucideIcons.globe, size: 13, color: AppColors.textLow),
                  const SizedBox(width: 4),
                  Text(d.ip, textDirection: TextDirection.ltr, style: sub.copyWith(color: AppColors.textBody)),
                  const SizedBox(width: Sp.md),
                  if (region != null)
                    Flexible(child: region)
                  else if ((d.location ?? '').isNotEmpty) ...[
                    Icon(LucideIcons.building2, size: 13, color: AppColors.textLow),
                    const SizedBox(width: 4),
                    Expanded(child: Text(d.location!, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub)),
                  ],
                ],
              ),
              const Spacer(),
              Divider(height: Sp.md, thickness: 1, color: AppColors.border),
              Row(
                children: [
                  metric('الاستجابة', online && d.lastResponseMs != null ? '${d.lastResponseMs} ms' : '—',
                      color: online ? statusCol : AppColors.textLow),
                  metric(online ? 'متصل' : 'الحالة', since ?? '—'),
                  metric('آخر فحص', _clockOf(d.lastProbedAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          // الحاسبة: البطاقة بارتفاع خليّة الشبكة — المحتوى في وسطها لا أعلاها.
          alignment: AlignmentDirectional.centerStart,
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
                      // ⚠️ مرنٌ ليتنازل قبل الشارات: عنوانٌ من ١٥ محرفاً
                      // («192.168.100.200») + شاراتُ الطراز والبروتوكول
                      // تتجاوز الصفّ عند ٣٢٠ — وبلا مرونةٍ يفيض بدل أن
                      // يُقصّ، والفيض عطلٌ ظاهر.
                      Flexible(
                        child: Text(
                          d.ip,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.muted(color: AppColors.textMid),
                        ),
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

/// زرّ أداةٍ جنب البحث — شكل أزرار رأس المشتركين نفسه (سطحٌ بحدٍّ خفيف ونصف
/// قطر 14)، بمقاس أزرار الأعلى فوقه ([TopActionChip.sizeOf]: ‎42، و‎38 على
/// الشاشات الضيّقة). و[filled] بتعبئة البراند (الإضافة).
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.badge = 0,
    this.busy = false,
    this.filled = false,
    this.wrap,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;

  /// عددٌ أحمر على الركن — يُخفى عند الصفر.
  final int badge;

  /// دوّارةٌ مكان الأيقونة والنقر مقفل (فحصٌ أو كشفٌ جارٍ).
  final bool busy;
  final bool filled;

  /// يلفّ المحتوى بلاقط نقرٍ غير `InkWell` (قائمة «المزيد» المنسدلة).
  final Widget Function(Widget content)? wrap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final radius = BorderRadius.circular(R.icon);
    final side = TopActionChip.sizeOf(context);
    final content = Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: filled ? null : Border.all(color: AppColors.borderSoft),
      ),
      child: busy
          ? SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandAccent,
              ),
            )
          : child,
    );
    Widget button = Material(
      color: filled ? AppColors.brand : AppColors.surface,
      borderRadius: radius,
      child: wrap != null && !busy
          ? wrap!(content)
          : InkWell(
              borderRadius: radius,
              onTap: busy ? null : onTap,
              onLongPress: busy ? null : onLongPress,
              child: content,
            ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -4,
          left: -4,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.errorFill,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: AppType.muted(color: AppColors.onBrand)
                    .copyWith(fontSize: 10.5, height: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
