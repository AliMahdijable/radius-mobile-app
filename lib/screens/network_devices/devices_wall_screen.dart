import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../services/device_alerts_service.dart';
import '../../services/device_sweep_coordinator.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'network_device_details_screen.dart';

/// جدار الأجهزة — كلّ الأجهزة في صفحة واحدة، مجموعةً حسب المنطقة.
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

    final queue = Queue<NetworkDevice>.from(_all);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final d = queue.removeFirst();
        attempted++;
        try {
          final r = await NetworkDevicesApi.localIcmpPing(
            ip: d.ip,
            tcpPort: d.apiPort ?? d.port,
          );
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

    if (!mounted) return;
    setState(() {
      _sweeping = false;
      _offNetwork = reachable == 0 && attempted >= _offNetworkThreshold;
      _all = [for (final d in _all) updates[d.id] ?? d];
    });
  }

  // ── ترتيب وتجميع ───────────────────────────────────────────────

  /// المعطّل أوّلاً، والمجهول قبل السليم: لم يُفحص بعدُ فقد يكون ساقطاً.
  /// تفتح هذه الصفحة لتجد العطل، لا لتتصفّح.
  static int _rank(NetworkDevice d) => switch (d.lastStatus) {
        'offline' => 0,
        'unknown' => 1,
        _ => 2,
      };

  static int _compare(NetworkDevice a, NetworkDevice b) {
    final r = _rank(a).compareTo(_rank(b));
    if (r != 0) return r;
    // ثمّ الأبطأ أوّلاً — البطء يسبق السقوط.
    final ms = (b.lastResponseMs ?? 0).compareTo(a.lastResponseMs ?? 0);
    return ms != 0 ? ms : a.name.compareTo(b.name);
  }

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
    // المنطقة الأكثر عطلاً أوّلاً.
    out.sort((a, b) {
      final ao = a.devices.where((d) => d.lastStatus == 'offline').length;
      final bo = b.devices.where((d) => d.lastStatus == 'offline').length;
      return bo.compareTo(ao);
    });
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
            Text('جدار الأجهزة', style: AppType.cardTitle()),
            if (!_loading && _all.isNotEmpty)
              Text(
                down == 0
                    ? '${_all.length} جهازاً · الكلّ سليم'
                    : '$down معطّل من ${_all.length}',
                style: AppType.muted(
                    color: down == 0 ? AppColors.success : AppColors.error),
              ),
          ],
        ),
        actions: [
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

    final groups = _groups;
    final lead = _offNetwork ? 1 : 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.mega),
        itemCount: groups.length + lead,
        itemBuilder: (context, i) {
          if (_offNetwork && i == 0) return const _OffNetworkBanner();
          final g = groups[i - lead];
          return _RegionGroup(
            region: g.region,
            devices: g.devices,
            expanded: _expanded,
            onToggle: (id) => setState(() {
              if (_expanded.contains(id)) {
                _expanded.remove(id);
              } else {
                _expanded.add(id);
              }
            }),
            onOpen: (d) async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NetworkDeviceDetailsScreen(device: d),
                ),
              );
              if (mounted) _load(silent: true);
            },
          );
        },
      ),
    );
  }
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

class _RegionGroup extends StatelessWidget {
  const _RegionGroup({
    required this.region,
    required this.devices,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
  });

  final DeviceRegion? region;
  final List<NetworkDevice> devices;
  final Set<int> expanded;
  final ValueChanged<int> onToggle;
  final ValueChanged<NetworkDevice> onOpen;

  @override
  Widget build(BuildContext context) {
    final down = devices.where((d) => d.lastStatus == 'offline').length;
    final tone = down == 0 ? AppTone.success : AppTone.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.md, Sp.xs, Sp.sm),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  region?.name ?? 'بلا منطقة',
                  style: AppType.bodyStrong(color: AppColors.textMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(child: Container(height: 1, color: AppColors.divider)),
              const SizedBox(width: Sp.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Sp.sm, vertical: Sp.xxs),
                decoration: BoxDecoration(
                  color: tone.softBg,
                  borderRadius: BorderRadius.circular(R.chip),
                  border: Border.all(color: tone.softBorder),
                ),
                child: Text(
                  down == 0 ? 'الكلّ سليم' : '$down من ${devices.length} معطّل',
                  style: AppType.muted(color: tone.fill),
                ),
              ),
            ],
          ),
        ),
        for (final d in devices)
          _DeviceCard(
            device: d,
            open: expanded.contains(d.id),
            onToggle: () => onToggle(d.id),
            onOpen: () => onOpen(d),
          ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.open,
    required this.onToggle,
    required this.onOpen,
  });

  final NetworkDevice device;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  /// عتبة «بطيء» — فوقها الجهاز حيٌّ رقميّاً ومريضٌ فعليّاً.
  static const slowMs = 150;

  /// النغمة من الحالة **وزمن الاستجابة معاً**.
  ///
  /// «حيّ» و«معطّل» لا تكفيان: الجهاز الذي يردّ بعد ٢٠٠ملي‌ثانية على
  /// شبكة محلّيّة في الطريق إلى السقوط، ويستحقّ لوناً ثالثاً قبل أن يقع.
  static AppTone toneFor(String status, int? ms) {
    if (status == 'offline') return AppTone.danger;
    if (status == 'unknown') return AppTone.neutral;
    if (ms != null && ms >= slowMs) return AppTone.warning;
    return AppTone.success;
  }

  static String labelFor(String status, int? ms) => switch (status) {
        'offline' => 'معطّل',
        'unknown' => 'لم يُفحص',
        _ => ms == null
            ? 'حيّ'
            : (ms >= slowMs ? 'بطيء · ${ms}ms' : 'حيّ · ${ms}ms'),
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
  Widget build(BuildContext context) {
    final tone = toneFor(device.lastStatus, device.lastResponseMs);
    final since = sinceText(device.statusSince);
    final isDown = device.lastStatus == 'offline';

    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      decoration: BoxDecoration(
        color: isDown ? tone.softBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: isDown ? tone.softBorder : AppColors.border),
      ),
      child: Column(
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
                              ? '${device.ip} · ${device.model}'
                              : device.ip,
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
                    text: labelFor(device.lastStatus, device.lastResponseMs),
                  ),
                ],
              ),
            ),
          ),
          if (isDown && since != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: tone.softBorder),
              ),
              child: Text(
                'آخر ظهور $since',
                textAlign: TextAlign.center,
                style: AppType.muted(color: tone.fill),
              ),
            ),
          if (open) _CardDetails(device: device),
        ],
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
class _CardDetails extends StatelessWidget {
  const _CardDetails({required this.device});
  final NetworkDevice device;

  @override
  Widget build(BuildContext context) {
    final rows = <({String k, String v})>[
      (k: 'العلامة', v: device.brand),
      (k: 'النوع', v: device.type),
      if (device.mac?.isNotEmpty ?? false) (k: 'MAC', v: device.mac!),
      if (device.location?.isNotEmpty ?? false)
        (k: 'الموقع', v: device.location!),
      if (device.lastProbedAt != null)
        (k: 'آخر فحص', v: _clock(device.lastProbedAt!)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
      child: Column(
        children: [
          Container(height: 1, color: AppColors.divider),
          const SizedBox(height: Sp.sm),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.xxs),
              child: Row(
                children: [
                  SizedBox(width: 78, child: Text(r.k, style: AppType.muted())),
                  Expanded(
                    child: Text(r.v,
                        style: AppType.body(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
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
