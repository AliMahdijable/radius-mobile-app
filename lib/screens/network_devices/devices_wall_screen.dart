import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/util/bidi.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../services/device_alerts_service.dart';
import '../../services/device_stats_cache.dart';
import '../../services/device_sweep_coordinator.dart';
import '../../services/deep_probe_scheduler.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'device_sort.dart';
import 'device_vitals.dart';
import 'widgets/_grade.dart';
import 'widgets/device_image.dart';
import 'network_device_details_screen.dart';

/// نظرة عامّة على الأجهزة — كلّها في صفحة واحدة، مجموعةً حسب المنطقة.
///
/// ── لماذا صفحة مستقلّة ────────────────────────────────────────────
/// شاشة الأجهزة شاشة **إدارة**: تحديد، إضافة، حذف جماعيّ، مسح شبكة.
/// وهذه **جدار مراقبة**: تُقرأ ولا تُشغَّل. خلطهما يُفسد الاثنتين، ويُضخّم
/// ملفّاً بلغ ١٣٧٤ سطراً أصلاً.
///
/// ── المرحلة الأولى ────────────────────────────────────────────────
/// الطبقة الأولى وحدها: حيّ/ميت + زمن الاستجابة + منذ متى. ولا جلسة
/// عميقة واحدة (معالج/ذاكرة/إشارة) — تلك تأتي في المرحلة الثانية
/// مربوطةً بنافذة الرؤية. والصفحة مفيدة قبلها: أن ترى المعطّل مجموعاً
/// حسب البرج هو جوهر ما تفتح الصفحة لأجله.
class DevicesWallScreen extends StatefulWidget {
  const DevicesWallScreen({super.key});

  @override
  State<DevicesWallScreen> createState() => _DevicesWallScreenState();
}

class _DevicesWallScreenState extends State<DevicesWallScreen>
    with WidgetsBindingObserver {
  static const _sweepInterval = Duration(seconds: 20);

  /// سقف المقابس المتزامنة — نفس سقف شاشة الأجهزة.
  static const _sweepConcurrency = 24;

  /// كم فحصاً فاشلاً قبل أن نُعلن أنّنا لسنا على شبكة الأجهزة.
  ///
  /// على بيانات الجوّال تفشل كلّ محاولة بعد مهلتها، فثمانون جهازاً =
  /// طحنٌ متواصل بلا نتيجة. الشرط أن **يفشل الكلّ** ويكون العدد ثلاثة
  /// فأكثر — فجهاز واحد معطّل صدفةً لا يُطلق الإنذار.
  ///
  /// ⚠️ فحص TCP وحده لا يفرّق بين «لستُ على الشبكة» و«كلّ الأجهزة
  /// ساقطة فعلاً» — كلاهما صمت. لذلك نصّ اللافتة يصف **ما رأيناه**
  /// (لم يستجب أحد) ويقترح السبب، ولا يجزم به.
  static const _offNetworkThreshold = 3;

  List<NetworkDevice> _all = [];
  List<DeviceRegion> _regions = [];
  final Map<int, String> _lastKnown = {};

  bool _loading = true;
  bool _sweeping = false;
  bool _offNetwork = false;
  String? _error;
  Timer? _timer;
  final Set<int> _expanded = {};

  DeviceSortField _sortField = DeviceSortField.health;
  SortDir _sortDir = SortDir.asc;

  /// وسيط زمن الاستجابة في آخر جولة — أساس الحكم على «البطيء».
  int? _roundMedianMs;

  /// مقاييس كلّ جهاز — مُنبّه مستقلّ لكلّ بطاقة.
  ///
  /// يعيش في الشاشة لا في البطاقة: البطاقة تُهدم مع التمرير، ولو ماتت
  /// القيمة معها لأعادت كلّ عودةٍ إلى الأعلى فتحَ الجلسات من الصفر.
  final VitalsStore _vitals = VitalsStore();

  @override
  void initState() {
    super.initState();
    // نمسك المنسّق فوراً: شاشة الأجهزة تحتنا ما زالت حيّةً وستمسح
    // بالتوازي لولا هذا.
    DeviceSweep.acquire();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    DeviceSweep.release();
    _vitals.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
      if (_all.isNotEmpty) _sweep();
    } else {
      // حارس الحرارة: لا مسح والتطبيق في الخلفيّة.
      _timer?.cancel();
    }
  }

  Future<void> _pickSort() async {
    final r = await showDeviceSortSheet(
      context,
      field: _sortField,
      dir: _sortDir,
      subtitle: 'داخل كلّ منطقة',
    );
    if (r == null || !mounted) return;
    setState(() {
      _sortField = r.field;
      _sortDir = r.dir;
    });
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_sweepInterval, (_) => _sweep());
  }

  /// [silent] يُبقي القائمة معروضة أثناء الجلب.
  ///
  /// العودة من صفحة التفاصيل تُحدّث، ودوّارٌ يملأ الشاشة عندها يمحو
  /// السياق الذي كان المستخدم ينظر إليه قبل ثانية.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final devices = await NetworkDevicesApi.list();
      final regions = await NetworkDevicesApi.listRegions();
      if (!mounted) return;
      setState(() {
        _all = devices;
        _regions = regions;
        _loading = false;
        _error = null;
      });
      // البذرة من الخادم: نتفادى أن يبدو أوّل مسح تحوّلاً وهميّاً
      // فيُطلق تنبيهاً لجهاز لم يتغيّر فيه شيء.
      for (final d in _all) {
        _lastKnown[d.id] = d.lastStatus;
      }
      _start();
      _sweep();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // على التحديث الصامت نُبقي ما بين يدي المستخدم بدل استبداله
        // بشاشة خطأ — القائمة القديمة أنفع من لا شيء.
        if (!silent) _error = 'تعذّر جلب الأجهزة';
      });
    }
  }

  Future<void> _sweep() async {
    if (_sweeping || _all.isEmpty || !mounted) return;
    setState(() => _sweeping = true);

    final probed = <({int id, String status, int? responseMs})>[];
    final updates = <int, NetworkDevice>{};
    final transitions = <({NetworkDevice d, String from, String to})>[];
    var reachable = 0;
    var attempted = 0;

    // دفقٌ تدريجيّ مخنوق — نفس علاج قائمة الأجهزة (٢٠٢٦-٠٩-٠٢).
    //
    // الجولة كانت ترسم مرّةً بعد اكتمالها كلّها، والمنقطع يستهلك مهلته
    // كاملةً — فيجمد الجدار ثوانيَ وأوّل جهازٍ ردّ بعد جزءٍ من الثانية.
    // دفعةٌ كلّ ٤٠٠ms: لا جمود، ولا ثمانون إعادة بناء.
    var pendingFlush = false;
    void flush() {
      if (!mounted || updates.isEmpty) return;
      setState(() {
        _all = [for (final d in _all) updates[d.id] ?? d];
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

    final queue = Queue<NetworkDevice>.from(_all);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final d = queue.removeFirst();
        attempted++;
        try {
          final r = await NetworkDevicesApi.probeDevice(d);
          if (r.status == 'online') reachable++;
          final was = _lastKnown[d.id] ?? 'unknown';
          if (was != r.status && was != 'unknown') {
            transitions.add((d: d, from: was, to: r.status));
          }
          _lastKnown[d.id] = r.status;
          probed.add((id: d.id, status: r.status, responseMs: r.responseMs));
          updates[d.id] = d.copyWith(
            lastProbedAt: DateTime.now(),
            lastStatus: r.status,
            lastResponseMs: r.responseMs,
            // ⚠️ `statusSince` **لا** يُخمَّن محلّيّاً. الخادم يملك القيمة
            // الحقيقيّة ويعيدها في الجلب التالي؛ ولو كتبناها هنا لأعلنّا
            // «معطّل منذ لحظات» لجهاز ساقط منذ ساعة.
          );
          scheduleFlush();
        } catch (_) {
          // فشل جهاز واحد لا يوقف الجولة.
        }
      }
    }

    await Future.wait(List.generate(
      queue.length < _sweepConcurrency ? queue.length : _sweepConcurrency,
      (_) => worker(),
    ));

    if (probed.isNotEmpty) {
      unawaited(
          NetworkDevicesApi.saveProbeResults(probed).catchError((_) => false));
    }
    for (final t in transitions) {
      DeviceAlertsService.instance.checkTransition(
        deviceId: t.d.id,
        deviceName: t.d.name,
        deviceIp: t.d.ip,
        oldStatus: t.from,
        newStatus: t.to,
      );
    }

    // ── وسيط الجولة ──────────────────────────────────────────────
    //
    // 🐛 بلاغ ٢٠٢٦-٠٩-٠١: اثنا عشر جهازاً كلّها «بطيء · ٢٣٠ms» — نفس
    // الرقم بالضبط. والقياس سليم، لكنّ **التزامن يُفسده**: أربعة
    // وعشرون مقبساً تُفتح معاً، فما يقيسه المؤقّت هو ازدحام الدفعة لا
    // زمن الجهاز. الرقم يحمل إزاحةً مشتركة تُصيب الجميع بالتساوي.
    //
    // فالحكم صار **نسبيّاً**: بطيءٌ من تجاوز ضعف وسيط جولته. الإزاحة
    // المشتركة تسقط من الطرفين، ويبقى ما يميّز جهازاً عن أقرانه فعلاً.
    final lat = probed
        .map((p) => p.responseMs)
        .whereType<int>()
        .toList()
      ..sort();
    final median = lat.isEmpty ? null : lat[lat.length ~/ 2];

    if (!mounted) return;
    setState(() {
      _sweeping = false;
      _roundMedianMs = median;
      _offNetwork = reachable == 0 && attempted >= _offNetworkThreshold;
      // رسمةٌ ختاميّة: تضمن وصول ما جاء بعد آخر خنق.
      _all = [for (final d in _all) updates[d.id] ?? d];
    });
  }

  // ── ترتيب وتجميع ───────────────────────────────────────────────

  int _compare(NetworkDevice a, NetworkDevice b) =>
      compareDevices(a, b, _sortField, _sortDir);

  List<({DeviceRegion? region, List<NetworkDevice> devices})> get _groups {
    final byRegion = <int?, List<NetworkDevice>>{};
    for (final d in _all) {
      byRegion.putIfAbsent(d.regionId, () => []).add(d);
    }
    for (final list in byRegion.values) {
      list.sort(_compare);
    }

    final out = <({DeviceRegion? region, List<NetworkDevice> devices})>[];
    for (final r in _regions) {
      final list = byRegion.remove(r.id);
      if (list != null && list.isNotEmpty) out.add((region: r, devices: list));
    }
    // «بلا منطقة» مجموعة حقيقيّة أخيراً، لا بقايا مبعثرة. وتشمل أيضاً
    // أجهزةً تشير إلى منطقة محذوفة — وإلّا اختفت من الجدار كلّيّاً.
    final orphans = <NetworkDevice>[];
    for (final list in byRegion.values) {
      orphans.addAll(list);
    }
    if (orphans.isNotEmpty) {
      orphans.sort(_compare);
      out.add((region: null, devices: orphans));
    }
    // ⚠️ ترتيب المناطق يتبع المعيار نفسه، وإلّا تناقض المستويان:
    // بطاقاتٌ مرتّبةٌ أبجديّاً داخل مناطق مرتّبةٍ بالأعطال تبدو عشوائيّة.
    if (_sortField == DeviceSortField.health) {
      // الأكثر انقطاعاً أوّلاً — تُبصر البرج الساقط قبل أن تُمرّر.
      out.sort((a, b) {
        final ao = a.devices.where((d) => d.lastStatus == 'offline').length;
        final bo = b.devices.where((d) => d.lastStatus == 'offline').length;
        return bo.compareTo(ao);
      });
    } else {
      // «بلا منطقة» تبقى في الذيل: مجموعةٌ باقية لا اسمٌ يُرتَّب.
      out.sort((a, b) {
        if (a.region == null) return 1;
        if (b.region == null) return -1;
        return a.region!.name.compareTo(b.region!.name);
      });
    }
    return out;
  }

  // ── بناء ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final down = _all.where((d) => d.lastStatus == 'offline').length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('نظرة عامّة', style: AppType.cardTitle()),
            if (!_loading && _all.isNotEmpty)
              Text(
                down == 0
                    ? '${_all.length} جهازاً · الكلّ سليم'
                    : '$down غير متّصل من ${_all.length}',
                style: AppType.muted(
                    color: down == 0 ? AppColors.success : AppColors.error),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_sortField.icon, size: 20),
            tooltip: 'الترتيب · ${_sortField.label}',
            onPressed: _pickSort,
          ),
          if (_sweeping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(LucideIcons.refreshCw, size: 20),
              tooltip: 'فحص الآن',
              onPressed: _sweep,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _Notice(
        icon: LucideIcons.circleAlert,
        tone: AppTone.danger,
        title: _error!,
        action: ('إعادة المحاولة', _load),
      );
    }
    if (_all.isEmpty) {
      return const _Notice(
        icon: LucideIcons.router,
        tone: AppTone.neutral,
        title: 'لا أجهزة مسجّلة بعد',
        body: 'أضف أجهزتك من شاشة الأجهزة لتظهر هنا.',
      );
    }

    // ⚠️ تسطيح: البطاقة **ابن مباشر** للقائمة لا حفيدٌ داخل مجموعة.
    //
    // `ListView.builder` لا يبني إلّا ما قارب الشاشة — وهذا بالضبط
    // تبويب النظر الذي تقوم عليه المرحلة الثانية. ولو بقيت المجموعة
    // عنصراً واحداً يضمّ بطاقاتها، لبُنيت منطقةٌ فيها أربعون جهازاً
    // دفعةً، ولفتحت أربعين جلسةً لجهازٍ واحدٍ مرئيّ.
    final rows = _rows;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            Sp.md, Sp.sm, Sp.md, Inset.route(context)),
        itemCount: rows.length,
        itemBuilder: (context, i) => switch (rows[i]) {
          _BannerRow() => const _OffNetworkBanner(),
          final _HeaderRow r => _GroupHeader(
              title: r.region?.name ?? 'بلا منطقة',
              down: r.down,
              slow: r.slow,
              total: r.total,
            ),
          final _DeviceRow r => _DeviceCard(
              // ⚠️ مفتاح ثابت بمعرّف الجهاز: بلا مفتاح يُعيد Flutter
              // استعمال حالة البطاقة لجهازٍ آخر عند تغيّر الترتيب،
              // فتظهر مقاييس برجٍ فوق اسم برجٍ غيره.
              key: ValueKey(r.device.id),
              device: r.device,
              vitals: _vitals.of(r.device.id),
              onVitals: (v) => _vitals.set(r.device.id, v),
              medianMs: _roundMedianMs,
              prevSample: () => _vitals.sampleOf(r.device.id),
              onSample: (c) => _vitals.saveSample(r.device.id, c),
              open: _expanded.contains(r.device.id),
              onToggle: () => setState(() {
                if (_expanded.contains(r.device.id)) {
                  _expanded.remove(r.device.id);
                } else {
                  _expanded.add(r.device.id);
                }
              }),
              onOpen: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        NetworkDeviceDetailsScreen(device: r.device),
                  ),
                );
                if (mounted) _load(silent: true);
              },
            ),
        },
      ),
    );
  }

  /// يُسطّح المجموعات إلى صفوف: لافتة ثمّ عنوان مجموعة ثمّ بطاقاتها.
  List<_Row> get _rows {
    final out = <_Row>[];
    if (_offNetwork) out.add(const _BannerRow());
    for (final g in _groups) {
      final down = g.devices.where((d) => d.lastStatus == 'offline').length;
      final slow = g.devices
          .where((d) =>
              d.lastStatus == 'online' &&
              _DeviceCard.isSlow(d.lastResponseMs, _roundMedianMs))
          .length;
      out.add(_HeaderRow(g.region, down, slow, g.devices.length));
      for (final d in g.devices) {
        out.add(_DeviceRow(d));
      }
    }
    return out;
  }
}

// ── صفوف القائمة المسطّحة ────────────────────────────────────────

sealed class _Row {
  const _Row();
}

class _BannerRow extends _Row {
  const _BannerRow();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.region, this.down, this.slow, this.total);
  final DeviceRegion? region;
  final int down;
  final int slow;
  final int total;
}

class _DeviceRow extends _Row {
  const _DeviceRow(this.device);
  final NetworkDevice device;
}

// ══════════════════════════════════════════════════════════════════
// مكوّنات العرض
// ══════════════════════════════════════════════════════════════════

class _OffNetworkBanner extends StatelessWidget {
  const _OffNetworkBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppTone.warning.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppTone.warning.softBorder),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wifiOff, size: 18, color: AppTone.warning.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'لم يستجب أيّ جهاز — تأكّد أنّك على شبكة الأجهزة. '
              'القيم أدناه آخر ما سجّله الخادم.',
              style: AppType.muted(color: AppTone.warning.fill),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.down,
    required this.slow,
    required this.total,
  });

  final String title;
  final int down;
  final int slow;
  final int total;

  /// ⚠️ الملخّص يجب أن يوافق البطاقات تحته.
  ///
  /// كان يعدّ المعطّل وحده، فيقول «الكلّ سليم» فوق اثنَي عشر جهازاً
  /// موسومةٍ كلّها بالبطء. ملخّصٌ يناقض ما تحته أسوأ من غيابه.
  /// ⚠️ لا شارة حين يكون كلّ شيء سليماً.
  ///
  /// «الكلّ سليم» مكرّرةً فوق كلّ منطقة تُدرَّب العين على تجاهل ذلك
  /// الموضع — فحين يظهر فيه «٣ معطّل» لا تراه. الشارة تحمل خبراً أو
  /// تغيب، ولا خبر خبرٌ سارّ.
  (String, AppTone)? get _summary {
    if (down > 0) return ('$down من $total غير متّصل', AppTone.danger);
    if (slow > 0) return ('$slow بطيء', AppTone.warning);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.md, Sp.xs, Sp.sm),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: AppType.bodyStrong(color: AppColors.textMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: Container(height: 1, color: AppColors.divider)),
          if (summary != null) ...[
            const SizedBox(width: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.sm, vertical: Sp.xxs),
              decoration: BoxDecoration(
                color: summary.$2.softBg,
                borderRadius: BorderRadius.circular(R.chip),
                border: Border.all(color: summary.$2.softBorder),
              ),
              child: Text(summary.$1,
                  style: AppType.muted(color: summary.$2.fill)),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceCard extends StatefulWidget {
  const _DeviceCard({
    super.key,
    required this.device,
    required this.vitals,
    required this.onVitals,
    required this.medianMs,
    required this.prevSample,
    required this.onSample,
    required this.open,
    required this.onToggle,
    required this.onOpen,
  });

  final NetworkDevice device;
  final ValueNotifier<VitalsState> vitals;
  final ValueChanged<VitalsState> onVitals;
  final int? medianMs;
  final CounterSample? Function() prevSample;
  final ValueChanged<Map<String, ({int rx, int tx})>> onSample;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  /// أرضيّة مطلقة: تحت هذه لا يُوصف جهاز بالبطء مهما بلغ وسيط جولته.
  /// شبكةٌ كلّها تحت ٨٠ms شبكةٌ سليمة، ولو تفاوتت أضعافاً.
  static const slowFloorMs = 80;

  /// كم ضِعفاً من الوسيط يُعدّ شذوذاً.
  static const slowFactor = 2;

  /// هل هذا الجهاز بطيءٌ **قياساً بأقرانه في الجولة نفسها**؟
  ///
  /// ⚠️ لا عتبة مطلقة. الجولة تفحص العشرات معاً، فيحمل كلّ رقم إزاحةَ
  /// ازدحامٍ مشتركة — وعتبةٌ ثابتة تُسمّي الجميع بطيئاً أو لا أحد.
  /// المقارنة بالوسيط تُسقط الإزاحة وتُبقي التمايز.
  static bool isSlow(int? ms, int? medianMs) {
    if (ms == null || ms < slowFloorMs) return false;
    if (medianMs == null || medianMs <= 0) return false;
    return ms >= medianMs * slowFactor;
  }

  /// النغمة من الحالة وزمن الاستجابة معاً.
  static AppTone toneFor(String status, int? ms, int? medianMs) {
    if (status == 'offline') return AppTone.danger;
    if (status == 'unknown') return AppTone.neutral;
    if (isSlow(ms, medianMs)) return AppTone.warning;
    return AppTone.success;
  }

  static String labelFor(String status, int? ms, int? medianMs) =>
      switch (status) {
        'offline' => 'غير متّصل',
        'unknown' => 'لم يُفحص',
        _ => ms == null
            ? 'حيّ'
            : (isSlow(ms, medianMs) ? 'بطيء · ${ms}ms' : '${ms}ms'),
      };

  /// «منذ ٤ دقائق» — من `status_since` الذي يتحرّك عند التحوّل فقط.
  /// يعيد null لغياب القيمة أو لطابع زمنيّ في المستقبل (انحراف ساعة).
  static String? sinceText(DateTime? since, {DateTime? now}) {
    if (since == null) return null;
    final d = (now ?? DateTime.now()).difference(since);
    if (d.isNegative) return null;
    if (d.inMinutes < 1) return 'منذ لحظات';
    if (d.inMinutes < 60) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'منذ ${d.inHours} ساعة';
    return 'منذ ${d.inDays} يوماً';
  }

  @override
  State<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<_DeviceCard> {
  /// نبضة الجلب العميق للبطاقة المرئيّة.
  ///
  /// أبطأ من نبضة اللوحة المفردة (٨ث لميكروتك): الجدار يعرض ستّاً لا
  /// واحدة، والمجموع هو ما يُسخّن الهاتف.
  static const _pulse = Duration(seconds: 15);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // بعد الإطار: الجلب يكتب في مُنبّهٍ يستمع إليه بناؤنا، والكتابة
    // أثناء البناء تُسقط إطاراً بخطأ setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _kick());
    _timer = Timer.periodic(_pulse, (_) => _kick());
  }

  @override
  void didUpdateWidget(covariant _DeviceCard old) {
    super.didUpdateWidget(old);
    // جهاز عاد للحياة بعد مسحٍ سطحيّ: امتنعنا عن جلسته وهو معطّل،
    // فلولا هذا لبقيت خاناته فارغةً حتّى تُهدم البطاقة وتُبنى.
    if (old.device.lastStatus != widget.device.lastStatus) _kick();

    // ⚠️ الفتح إعلانُ نيّة — يُقدّم البطاقة على الطابور.
    //
    // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «ليش من أنقر على الكارت السهم مال جهاز يضلّ
    // يقيس؟ مو منطقيّ». وكان النقر لا يغيّر شيئاً في الأولويّة: البطاقة
    // تنتظر دورها كأنّ أحداً لم يفتحها — بينما بطاقاتٌ لا ينظر إليها
    // أحد تُجدّد قراءاتها أمامها.
    //
    // من فتح بطاقةً ينتظر تفصيلها الآن. تقديمُه هو المنطق.
    if (!old.open && widget.open) _kick(urgent: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // ⚠️ نصف فائدة المجدول: بطاقة خرجت من الشاشة قبل دورها تُسحب من
    // الطابور فلا تُفتح لها جلسة أصلاً.
    DeepProbeScheduler.instance.cancel(this);
    super.dispose();
  }

  void _kick({bool urgent = false}) {
    if (!mounted) return;
    final st = widget.vitals.value;
    // ⚠️ الطازج يُحترم — إلّا عند الفتح بلا تفاصيل.
    //
    // القراءة المطويّة خفيفة (ثلاثة أرقام بلا عملاء ولا منافذ)، فطزاجتُها
    // لا تُغني المفتوحَ عن جلسته. ولولا هذا الاستثناء لبقي المطويّ
    // المفتوح بلا تفصيلٍ عشرين ثانية بحجّة أنّ أرقامه حديثة.
    final needsDetail = widget.open && st.detail?.ports.isEmpty != false;
    if (st.loading || (st.isFresh && !needsDetail)) return;

    // الامتناع الصريح أرخص من محاولةٍ تفشل: كلّ محاولة تحجز خانةً من
    // ستّ وتنتظر مهلتها كاملةً قبل أن تُحرّرها.
    final skip = DeviceVitals.skipReason(widget.device);
    if (skip != null) {
      widget.onVitals(VitalsState(error: skip, at: DateTime.now()));
      return;
    }

    // نُبقي القيم القديمة معروضةً أثناء التحديث — وميضُ فراغٍ ثمّ رقمٍ
    // كلّ خمس عشرة ثانية أسوأ من رقمٍ عمره ثانيتان.
    widget.onVitals(VitalsState(
      vitals: st.vitals,
      detail: st.detail,
      loading: true,
      at: st.at,
    ));

    // القراءة الأولى تتقدّم — راجع [DeepProbeScheduler.submit].
    DeepProbeScheduler.instance.submit(
        this, first: urgent || st.vitals == null, () async {
      if (!mounted) return;
      try {
        final r = await DeviceVitals.fetch(
          widget.device,
          prev: widget.prevSample(),
          // المفتوحة وحدها تدفع ثمن التفاصيل — راجع [DeviceVitals.fetch].
          detailed: widget.open,
        );
        if (!mounted) return;
        // العيّنة تُحفظ **قبل** النشر: الجلسة القادمة تطرح منها.
        widget.onSample(r.counters);
        // والحمولة الخام تُحفظ لتُبذَر بها اللوحة المفردة — فلا يدفع
        // المستخدم ثمن الجلسة مرّتين حين ينقر البطاقة.
        if (r.raw != null) {
          DeviceStatsCache.instance.putRaw(widget.device.id, r.raw!);
        }
        widget.onVitals(VitalsState(
          vitals: r.vitals,
          detail: r.detail,
          at: DateTime.now(),
        ));
      } catch (_) {
        if (!mounted) return;
        widget.onVitals(VitalsState(
          vitals: st.vitals,
          detail: st.detail,
          error: 'تعذّر الاتّصال',
          at: DateTime.now(),
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final open = widget.open;
    final onToggle = widget.onToggle;
    final onOpen = widget.onOpen;
    final tone = _DeviceCard.toneFor(
        device.lastStatus, device.lastResponseMs, widget.medianMs);
    final since = _DeviceCard.sinceText(device.statusSince);
    final isDown = device.lastStatus == 'offline';

    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(
        color: isDown ? tone.softBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: isDown ? tone.softBorder : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      // شريط الحالة على الحافّة الأماميّة.
      //
      // يحمل ما كانت تحمله الشارة الكبيرة — بعرض ثلاث نقاط بدل ثلث
      // السطر. ويجعل عمود البطاقات يُقرأ رأسيّاً: تمسح العين الحافّة
      // فترى أين الأحمر قبل أن تقرأ اسماً واحداً.
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: tone.fill),
          ),
          Column(
            children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(R.md),
            child: Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Row(
                children: [
                  // السهم وحده يطوي؛ بقيّة البطاقة تفتح الصفحة الكاملة.
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(R.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(Sp.xs),
                      child: Icon(
                        open
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronLeft,
                        size: 18,
                        color: AppColors.textMid,
                      ),
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «صورة الجهاز مو معروضة».
                  //
                  // الجدار لم يعرضها إطلاقاً — كانت في المخطّط وسقطت
                  // من التنفيذ. والصورة ليست زينة: تُميّز السكتور من
                  // السويتش من البرج بلمحة، قبل قراءة اسمٍ واحد.
                  DeviceImage(
                    brand: device.brand,
                    model: device.model,
                    size: 34,
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(device.name,
                            style: AppType.listName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                          (device.model?.isNotEmpty ?? false)
                              ? isoJoin([device.ip, device.model!], ' · ')
                              : iso(device.ip),
                          style: AppType.muted(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  _StatusPill(
                    tone: tone,
                    text: _DeviceCard.labelFor(device.lastStatus,
                        device.lastResponseMs, widget.medianMs),
                  ),
                ],
              ),
            ),
          ),
          // الخانات الثلاث — لا تُرسَم للمعطّل: لا معنى لقراءة معالجٍ
          // لجهازٍ لا يردّ، ولافتة «آخر ظهور» أنفع في مكانها.
          if (!isDown)
            ValueListenableBuilder<VitalsState>(
              valueListenable: widget.vitals,
              builder: (_, st, __) => _VitalsStrip(state: st),
            ),
              // سطرٌ مضمّن بوزن شريط المقاييس نفسه — لا صندوق.
              //
              // الصندوق الأبيض بحدوده كان يأخذ من البطاقة غير المتّصلة
              // ضعف ما يأخذه الشريط من المتّصلة، لحقيقةٍ واحدة. وحين
              // تسقط منطقةٌ كاملة تصير الشاشة صناديق فارغة.
              if (isDown && since != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
                  child: Row(
                    children: [
                      Icon(LucideIcons.clock, size: 13, color: tone.fill),
                      const SizedBox(width: Sp.xs),
                      Text('آخر ظهور $since',
                          style: AppType.muted(color: tone.fill)),
                    ],
                  ),
                ),
              if (open)
                ValueListenableBuilder<VitalsState>(
                  valueListenable: widget.vitals,
                  builder: (_, st, __) =>
                      _CardDetails(device: device, detail: st.detail),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// شريط المقاييس — أرقام مضمّنة لا صندوق.
///
/// كان صندوقاً بحدود وفواصل وتسميةٍ نصّيّة فوق كلّ رقم، فأخذ نصف ارتفاع
/// البطاقة لثلاثة أرقام. والتسميات («المعالج» · «الذاكرة» · «الحرارة»)
/// تُحفَظ بعد مرّتين ثمّ تصير حبراً. الأيقونة تحمل المعنى في جزءٍ من
/// المساحة.
class _VitalsStrip extends StatelessWidget {
  const _VitalsStrip({required this.state});
  final VitalsState state;

  @override
  Widget build(BuildContext context) {
    final v = state.vitals;

    if (v == null && state.error != null) {
      return _Note(state.error!, tone: AppTone.neutral);
    }
    if (v == null) {
      return const _Note('يقرأ المقاييس…', tone: AppTone.neutral, dim: true);
    }

    return Opacity(
      // القيم القديمة تبهت أثناء التحديث بدل أن تختفي.
      opacity: state.loading ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
        child: Row(
          children: [
            for (final x in v) ...[
              _VitalChip(x),
              const SizedBox(width: Sp.lg),
            ],
          ],
        ),
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip(this.vital);
  final Vital vital;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(vital.icon, size: 13, color: AppColors.textMid),
        const SizedBox(width: Sp.xs),
        // ⚠️ اتّجاه صريح: الرقم ووحدته وحدةٌ لاتينيّة داخل صفحةٍ عربيّة.
        // بلا هذا يقلبهما محرّك الاتّجاه الثنائيّ فيظهر «٪ ٣٤» و«° ٥٩»
        // بدل «٣٤٪» و«٥٩°». (بلاغ ٢٠٢٦-٠٩-٠١ — ظاهرٌ في اللقطة.)
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: vital.value,
                style: AppType.rowValue(color: vital.tone.fill),
              ),
              if (vital.unit != null)
                TextSpan(
                  text: vital.unit!,
                  style: AppType.muted(color: vital.tone.fill),
                ),
            ]),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.tone, this.dim = false});
  final String text;
  final AppTone tone;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
      child: Opacity(
        opacity: dim ? 0.6 : 1,
        child: Text(text,
            textAlign: TextAlign.center, style: AppType.muted(color: tone.fill)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.tone, required this.text});
  final AppTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xxs),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.chip),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle),
          ),
          const SizedBox(width: Sp.x6),
          Text(text, style: AppType.muted(color: tone.fill)),
        ],
      ),
    );
  }
}

/// المطويّ المفتوح — المرحلة الأولى تعرض ما يعرفه الخادم بلا جلسة.
/// المرحلة الثانية تُضيف هنا حمولة الجلسة الحيّة نفسها.
/// المطويّ المفتوح.
///
/// ⚠️ لا نداء شبكة هنا: [detail] يأتي من **نفس الحمولة** التي ملأت
/// الخانات الثلاث. كنّا نجلبها كاملةً ونقرأ منها ثلاثة أرقام ونرمي
/// الباقي — المرور والمتّصلون والنظام كانوا في اليد طوال الوقت.
class _CardDetails extends StatelessWidget {
  const _CardDetails({required this.device, this.detail});
  final NetworkDevice device;
  final DeviceDetail? detail;

  /// كم منفذاً نعرض. المنافذ المطفأة تُطوى في سطر واحد.
  static const _maxPorts = 4;

  /// كم متّصلاً نعرض قبل «وآخرون».
  static const _maxPeers = 5;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final live = <Widget>[];

    if (d != null) {
      // ── المرور ──
      // المنافذ العاملة فقط، والأكثر مروراً أوّلاً: منفذٌ مطفأ في
      // مقسمٍ ذي ستّة عشر منفذاً يُغرق ما يهمّ.
      final up = d.ports.where((p) => p.up).toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      final off = d.ports.length - up.length;
      if (up.isNotEmpty) {
        live.add(const _DetailHeading('المرور'));
        for (final p in up.take(_maxPorts)) {
          live.add(_PortRow(p));
        }
        if (up.length > _maxPorts || off > 0) {
          live.add(_DetailFoot(isoJoin([
            if (up.length > _maxPorts) 'و${up.length - _maxPorts} منفذاً آخر',
            if (off > 0) '$off مطفأ',
          ], ' · ')));
        }
      }

      // ── الوصلة ──
      // قبل المتّصلين: على وصلة نقطة-لنقطة لا متّصلين أصلاً، وهذه هي
      // كلّ ما يُشخّص بها.
      if (d.link.isNotEmpty) {
        live.add(const _DetailHeading('الوصلة اللاسلكيّة'));
        for (final e in d.link) {
          live.add(_InfoRow(e.k, e.v));
        }
      }

      // ── المتّصلون ──
      if (d.peers.isNotEmpty) {
        // الأضعف إشارةً أوّلاً — من يفتح هذه القائمة يبحث عن الشكوى.
        final peers = [...d.peers]
          ..sort((a, b) => (a.signal ?? 0).compareTo(b.signal ?? 0));
        live.add(_DetailHeading('${d.peersLabel} (${d.peers.length})'));
        for (final p in peers.take(_maxPeers)) {
          live.add(_PeerRow(p));
        }
        if (peers.length > _maxPeers) {
          live.add(_DetailFoot(iso('و${peers.length - _maxPeers} آخرين')));
        }
      }
    }

    // ── النظام ── (يجمع ما جاء من الجلسة وما تعرفه قاعدة البيانات)
    final info = <({String k, String v})>[
      if (d?.uptime != null) (k: 'التشغيل', v: d!.uptime!),
      if (d?.firmware != null) (k: 'الإصدار', v: d!.firmware!),
      (k: 'الطراز', v: d?.model ?? device.model ?? device.brand),
      if (device.mac?.isNotEmpty ?? false) (k: 'MAC', v: device.mac!),
      if (device.location?.isNotEmpty ?? false)
        (k: 'الموقع', v: device.location!),
      ...?d?.extras,
      if (device.lastProbedAt != null)
        (k: 'آخر فحص', v: _clock(device.lastProbedAt!)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: AppColors.divider),
          ...live,
          const _DetailHeading('النظام'),
          for (final r in info) _InfoRow(r.k, r.v),
          if (device.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: Sp.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(device.notes!, style: AppType.muted()),
            ),
          ],
        ],
      ),
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xxs),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text(k, style: AppType.muted())),
          Expanded(
            // ⚠️ عزل: «23.1 V» تظهر «V 23.1» بلا هذا — راجع [iso].
            child: Text(iso(v),
                style: AppType.body(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _DetailHeading extends StatelessWidget {
  const _DetailHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Sp.md, 0, Sp.xs),
      child: Text(text,
          style: AppType.muted(color: AppColors.brandAccent)),
    );
  }
}

class _DetailFoot extends StatelessWidget {
  const _DetailFoot(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xxs),
      child: Text(text, style: AppType.muted()),
    );
  }
}

class _PortRow extends StatelessWidget {
  const _PortRow(this.port);
  final PortTraffic port;

  @override
  Widget build(BuildContext context) {
    // ⚠️ الشرطة لا الصفر حين لا معدّل بعد: العيّنة الأولى بلا سابقة
    // فلا فارق يُقسَم، و«٠ بت» يوحي بمنفذٍ صامت وهو يحمل غيغابت.
    final has = port.rxBps != null || port.txBps != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            // القوس الزاويّ في أسماء ppp يُمثَّل معكوساً في السياق
            // العربيّ: «<pppoe-x» تظهر «pppoe-x>».
            child: Text(iso(port.name),
                style: AppType.body(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (!has)
            Text('يقيس…', style: AppType.muted())
          else ...[
            Icon(LucideIcons.arrowDown, size: 12, color: AppColors.success),
            const SizedBox(width: 2),
            Text(iso(DeviceVitals.fmtBps(port.rxBps)),
                style: AppType.rowValue(color: AppColors.success)),
            const SizedBox(width: Sp.md),
            Icon(LucideIcons.arrowUp, size: 12, color: AppColors.info),
            const SizedBox(width: 2),
            Text(iso(DeviceVitals.fmtBps(port.txBps)),
                style: AppType.rowValue(color: AppColors.info)),
          ],
          const Spacer(),
          if (port.linkSpeed != null)
            Text(iso(port.linkSpeed!), style: AppType.muted()),
        ],
      ),
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow(this.peer);
  final PeerLink peer;

  @override
  Widget build(BuildContext context) {
    final sig = peer.signal;
    final sigTone = sig == null || sig == 0 ? null : Grade.signal(sig);
    // ⚠️ CCQ سلّمه «الأعلى أفضل» عكس المعالج والذاكرة. تمريره على
    // `percentLowerBetter` يقلب الحكم: وصلةٌ بجودة ٩٦٪ تُصبَغ حمراء.
    final ccqTone = peer.hasCcq ? Grade.percentHigherBetter(peer.ccq) : null;

    // 🐛 بلاغ ٢٠٢٦-٠٩-٠١: «86/78 Mbps · 10 يوماً» كانت تظهر
    // «86/78 10 Mbps · يوماً» — كلمة «يوماً» تسحب رقمها إلى المقطع
    // اللاتينيّ المجاور. العزل لكلّ مقطع لا للناتج مجتمعاً.
    final sub = isoJoin([
      if (peer.rxRate != null && peer.txRate != null)
        '${peer.rxRate}/${peer.txRate} Mbps',
      if (peer.uptimeSec != null && peer.uptimeSec! > 0)
        DeviceVitals.fmtUptime(peer.uptimeSec!),
    ], ' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(iso(peer.name),
                    style: AppType.body(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              // الجودة قبل الإشارة: الإشارة وحدها تكذب — وصلةٌ قويّة
              // وسط تداخلٍ شديد تبدو ممتازةً وهي تُعيد الإرسال باستمرار.
              if (ccqTone != null) ...[
                _MiniChip(text: '${peer.ccq}٪', tone: ccqTone),
                const SizedBox(width: Sp.x6),
              ],
              if (sigTone != null)
                _MiniChip(text: '$sig', tone: sigTone),
            ],
          ),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(sub, style: AppType.muted()),
            ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.tone});
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: Sp.xxs),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.chip),
        border: Border.all(color: tone.softBorder),
      ),
      child: Text(text, style: AppType.muted(color: tone.fill)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.tone,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final AppTone tone;
  final String title;
  final String? body;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tone.fill),
            const SizedBox(height: Sp.md),
            Text(title,
                style: AppType.cardTitle(), textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: Sp.xs),
              Text(body!, style: AppType.muted(), textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: Sp.lg),
              FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
            ],
          ],
        ),
      ),
    );
  }
}
