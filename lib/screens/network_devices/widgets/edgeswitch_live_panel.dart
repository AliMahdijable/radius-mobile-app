import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/edgeswitch_api.dart';
import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/device_stats_cache.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '_grade.dart';
import 'device_image.dart';
import 'expandable_section.dart';

/// لوحة مراقبة حيّة لسويتشات **Ubiquiti EdgeSwitch** — قراءة فقط.
///
/// **بنيتها مطابقة للوحتي Mikrotik وCisco** عمداً: البطاقة الرئيسة
/// (رأس + شريط اللوحة + كروت المقاييس + منحنى الترفك) ثمّ أقسامٌ
/// قابلة للطيّ. المستخدم ينتقل بين جهازٍ وآخر في الشاشة نفسها،
/// فاختلاف اللغة البصريّة بين براندٍ وآخر يُقرأ عطلاً لا تنوّعاً.
///
/// وما يخصّ EdgeSwitch وحده — الحرارة وطاقة PoE — موضوعٌ داخل
/// القوالب نفسها لا بجانبها.
class EdgeSwitchLivePanel extends StatefulWidget {
  const EdgeSwitchLivePanel({super.key, required this.device});
  final NetworkDevice device;

  @override
  State<EdgeSwitchLivePanel> createState() => _EdgeSwitchLivePanelState();
}

class _EdgeSwitchLivePanelState extends State<EdgeSwitchLivePanel>
    with WidgetsBindingObserver {
  EdgeSwitchStats? _stats;
  DateTime? _lastFetch;
  String? _error;
  Timer? _timer;
  bool _loading = false;
  bool _monitoring = true;
  bool _foreground = true;
  bool _connectedOnly = false;
  String _query = '';
  int _generation = 0;

  final List<_TrafficSample> _history = [];

  /// أسرع من سسكو (١٥ث) لأنّ هذه أربعة نداءات REST متوازية لا جلسة
  /// طرفيّة — ردّها أجزاء ثانية. وأبطأ من مايكروتك لأنّ الجهاز يحدّ
  /// الجلسات المتزامنة، ونبضةٌ أسرع من زمن الجلسة تُنتج طابوراً.
  static const _refreshInterval = Duration(seconds: 8);
  static const _maxHistory = 30;

  @override
  void initState() {
    super.initState();
    // ── بذرةٌ من المخزن ────────────────────────────────────────────
    //
    // ⚡ بلا بذرٍ تُدفَع جلسةٌ كاملة في **كلّ** فتحةٍ للجهاز ولو أُغلق
    // قبل ثوانٍ، فيرى المدير دوّارةً على بياناتٍ كانت بين يديه.
    //
    // (طلب المستخدم ٢٠٢٦-١٠-٠١: «أهمّ شي عندي سرعة الاستجابة وعرض
    // البيانات وتحديثها… وهلشي بجميع الأجهزة»)
    _stats = DeviceStatsCache.instance.seedFor<EdgeSwitchStats>(widget.device.id);
    // وعمرُها معها: رقمٌ قديمٌ تحت شارة «مباشر» كذبة.
    final seedAge = DeviceStatsCache.instance.ageOf(widget.device.id);
    if (_stats != null && seedAge != null) {
      _lastFetch = DateTime.now().subtract(seedAge);
    }
    WidgetsBinding.instance.addObserver(this);
    _fetch();
    _arm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _generation++; // يُبطل أيّ ردٍّ في الطريق
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    // لا نستجوب الجهاز والتطبيق في الخلفيّة — استنزافٌ بلا قارئ.
    if (fg) {
      _fetch();
      _arm();
    } else {
      _timer?.cancel();
    }
  }

  void _arm() {
    _timer?.cancel();
    if (!_monitoring || !_foreground) return;
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
  }

  Future<void> _fetch({bool manual = false}) async {
    if (_loading) return;
    final d = widget.device;
    final gen = ++_generation;
    if (mounted) setState(() => _loading = true);

    // الاعتماد لا يُحمَل مع الموديل — يُجلب عند الحاجة من التخزين
    // الآمن، كما في لوحة سسكو. النموذج يحمل `hasCredentials` فقط.
    final creds = await NetworkDevicesApi.getCredentials(d.id);
    if (!mounted || gen != _generation) return;
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (d.ip.isEmpty || user.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'أدخل اسم مستخدم السويتش من إعدادات الجهاز';
      });
      return;
    }

    final s = await EdgeSwitchApi.fetchStats(
      host: d.ip,
      user: user,
      pass: pass,
      port: _restPort(d.apiPort),
    );

    // الردّ الذي تجاوزه الزمن يُهمَل — وإلّا رسمنا لقطةً أقدم فوق أحدث.
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      if (s == null) {
        _error = 'تعذّر الاتّصال — تحقّق من العنوان وبيانات الدخول';
      } else {
        _error = null;
        _stats = s;
        DeviceStatsCache.instance.putRaw(widget.device.id, s);
        _lastFetch = DateTime.now();
        _pushSample(s);
      }
    });
  }

  /// منفذ REST — لا منفذ الجهاز كما سُجِّل حرفيّاً.
  ///
  /// نموذج إضافة الجهاز يقترح **٢٢** لكلّ UBNT ويكتب تحته «‏UBNT يستعمل
  /// SSH (port 22)» — وهو صحيحٌ لراديوات airOS. لكنّ EdgeSwitch يُدار
  /// بـREST على 443، و٢٢ عنده منفذ طرفيّةٍ لا واجهة. فمن يسجّل سويتشه
  /// متّبعاً إرشاد النموذج كان يحصل على لوحةٍ فارغةٍ بلا سببٍ ظاهر.
  /// ٢٢ ليس منفذ REST في أيّ حالة، فتحويله إلى الافتراضيّ لا يُضيّع خياراً.
  static int _restPort(int? p) =>
      (p == null || p == 22) ? EdgeSwitchApi.defaultPort : p;

  /// المعدّلات تأتي جاهزةً من الجهاز (بت/ث) فلا نشتقّها من فروق
  /// العدّادات كما في سسكو — ولا نحتاج خزن العدّادات السابقة أصلاً.
  void _pushSample(EdgeSwitchStats s) {
    _history.add(_TrafficSample(
      at: DateTime.now(),
      tx: s.txRateTotal,
      rx: s.rxRateTotal,
    ));
    if (_history.length > _maxHistory) {
      _history.removeRange(0, _history.length - _maxHistory);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // البناء
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null && _error == null) {
      return Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Text('جاري الاتصال بـEdgeSwitch…',
              style: AppType.body(color: AppColors.textMid)),
        ]),
      );
    }

    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _header(),
          if (_error != null) _errorBox(),
          if (stats != null) ...[
            RepaintBoundary(child: _boardBanner(stats)),
            RepaintBoundary(child: _metricsRow(stats)),
            if (_history.length >= 2) ...[
              const SizedBox(height: 4),
              _trafficGraph(),
            ],
            const SizedBox(height: Sp.md),
          ],
        ]),
      ),
      if (stats != null) ..._buildExpandables(stats),
    ]);
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(Sp.md),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(LucideIcons.activity, size: 16, color: AppColors.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مراقبة حيّة (EdgeSwitch)', style: AppType.bodyBold()),
            const SizedBox(height: 2),
            Row(children: [
              if (_monitoring) ...[
                _pulseDot(),
                const SizedBox(width: 4),
              ],
              Text(
                _monitoring
                    ? 'مباشر · كل ${_refreshInterval.inSeconds}s'
                    : 'متوقّف',
                style: TextStyle(
                    fontSize: 10.5, height: 1.3, color: AppColors.textMid),
              ),
              if (_lastFetch != null) ...[
                Text(' • ',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
                Text('آخر: ${_clock(_lastFetch!)}',
                    style: TextStyle(
                        fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
              ],
            ]),
          ]),
        ),
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          onPressed: _loading ? null : () => _fetch(manual: true),
          tooltip: 'تحديث الآن',
          color: AppColors.brand,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: Icon(_monitoring ? LucideIcons.pause : LucideIcons.play,
              size: 16),
          onPressed: () {
            setState(() => _monitoring = !_monitoring);
            _arm();
            if (_monitoring) _fetch();
          },
          tooltip: _monitoring ? 'إيقاف المراقبة' : 'استئناف',
          color: AppColors.textMid,
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
      margin: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
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
              style: AppType.micro(color: AppColors.error)),
        ),
      ]),
    );
  }

  Widget _boardBanner(EdgeSwitchStats s) {
    final model = s.model ?? widget.device.model;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        DeviceImage(brand: 'ubnt', model: model, size: 28),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              s.hostname?.isNotEmpty == true ? s.hostname! : widget.device.name,
              style: TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textHi),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                if (model != null && model.isNotEmpty) model,
                if (s.firmware != null) 'v${s.firmware}',
              ].join(' • '),
              style: AppType.micro(color: AppColors.textMid),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        if (s.uptimeText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.clock, size: 9, color: AppColors.brand),
              const SizedBox(width: 3),
              Text(s.uptimeText!,
                  style: AppType.microBold(color: AppColors.brand)),
            ]),
          ),
      ]),
    );
  }

  Widget _metricsRow(EdgeSwitchStats s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.cpu,
                label: 'CPU',
                percent: s.cpuPercent?.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _percentCard(
                icon: LucideIcons.memoryStick,
                label: 'RAM',
                percent: s.ramPercent?.toDouble(),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.ethernetPort,
                label: 'منافذ',
                value: '${s.portsUp}',
                unit: '/${s.portsTotal}',
                color:
                    s.portsUp > 0 ? AppColors.success : AppColors.textLow,
              )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.thermometer,
                label: 'حرارة',
                value: s.temperatureC == null
                    ? '—'
                    : s.temperatureC!.toStringAsFixed(0),
                unit: s.temperatureC == null ? '' : '°',
                color: _tempColor(s.temperatureC),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.zap,
                label: 'PoE',
                // صفر واط ليس «لا يوجد»: السويتش قد يكون يغذّي ولا
                // يبلّغ. نفرّق بالعدد لا بالطاقة وحدها.
                value: s.poePorts == 0
                    ? '—'
                    : s.poeTotalWatts.toStringAsFixed(1),
                unit: s.poePorts == 0 ? '' : 'W',
                color: s.poePorts > 0 ? AppColors.warning : AppColors.textLow,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _valueCard(
                icon: LucideIcons.arrowUpDown,
                label: 'حِمل المنافذ',
                value: _fmtRate(s.txRateTotal + s.rxRateTotal),
                unit: '',
                color: AppColors.brand,
              )),
            ],
          ),
        ),
      ]),
    );
  }

  Color _tempColor(num? t) {
    if (t == null) return AppColors.textLow;
    if (t >= 70) return AppColors.error;
    if (t >= 55) return AppColors.warning;
    return AppColors.success;
  }

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
            Text(label, style: AppType.microBold(color: AppColors.textMid)),
          ]),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: value == '—' ? AppColors.textLow : color,
                        height: 1)),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Text(unit, style: AppType.muted()),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// نسبةٌ قد تكون غير متاحة — و«غير متاح» ليست صفراً: شريطٌ فارغ عند
  /// `null` يوحي بمعالجٍ خاملٍ بينما الجهاز لم يُعطِ الرقم أصلاً.
  Widget _percentCard({
    required IconData icon,
    required String label,
    required double? percent,
  }) {
    final has = percent != null;
    final color =
        has ? Grade.percentLowerBetter(percent).fill : AppColors.textLow;
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
          Text(label, style: AppType.microBold(color: AppColors.textMid)),
        ]),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(has ? '${percent.round()}' : '—',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: has ? AppColors.textHi : AppColors.textLow,
                    height: 1)),
            if (has) ...[
              const SizedBox(width: 2),
              Text('%',
                  style: TextStyle(
                      fontSize: 10.5, height: 1.3, color: AppColors.textLow)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: has ? (percent / 100).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // منحنى الترفك
  // ══════════════════════════════════════════════════════════════

  Widget _trafficGraph() {
    final tx = <FlSpot>[];
    final rx = <FlSpot>[];
    for (var i = 0; i < _history.length; i++) {
      tx.add(FlSpot(i.toDouble(), _history[i].tx.toDouble()));
      rx.add(FlSpot(i.toDouble(), _history[i].rx.toDouble()));
    }
    final peak = math.max(
      _history.fold<int>(0, (m, s) => math.max(m, s.tx)),
      _history.fold<int>(0, (m, s) => math.max(m, s.rx)),
    );
    final last = _history.last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 8, Sp.md, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ⚠️ هذا **مجموع المنافذ** لا ترفك وصلةٍ واحدة.
        //
        // البايت يدخل منفذاً ويخرج من آخر، فيُعَدّ مرّتين في المجموع.
        // وتسميته «تنزيلاً» و«رفعاً» كذبٌ على سويتش: ما هو صادرٌ على
        // منفذٍ هو واردٌ على جاره. فنُسمّيه بما هو — حِملَ لوحةٍ لا
        // اتّجاهَ إنترنت. (بلاغ المستخدم ٢٠٢٦-٠٩-٢٨ على لوحة روجي،
        // والعلّة هنا نفسها.)
        Row(children: [
          Text('حِمل المنافذ (المجموع)', style: AppType.microBold()),
          const Spacer(),
          _legendChip('صادر', _fmtRate(last.tx), AppColors.brand),
          const SizedBox(width: 6),
          _legendChip('وارد', _fmtRate(last.rx), AppColors.success),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 64,
          child: LineChart(
            LineChartData(
              minY: 0,
              // سقفٌ أعلى بقليل من الذروة — وإلّا لامس المنحنى الحافّة
              // فبدا مشبعاً دائماً.
              maxY: peak == 0 ? 1 : peak * 1.15,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                _line(tx, AppColors.brand),
                _line(rx, AppColors.success),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  LineChartBarData _line(List<FlSpot> spots, Color color) {
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
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text('$arrow $value', style: AppType.microBold(color: color)),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // الأقسام القابلة للطيّ
  // ══════════════════════════════════════════════════════════════

  List<Widget> _buildExpandables(EdgeSwitchStats s) {
    final all = s.ports;
    final shown = all.where(_matchesFilter).toList();
    return [
      if (all.isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        ExpandableSection(
          key: PageStorageKey('es-${widget.device.id}-map'),
          initiallyExpanded: true,
          header: Row(children: [
            Icon(LucideIcons.layoutGrid, size: 14, color: AppColors.brand),
            const SizedBox(width: 6),
            Text('خريطة المنافذ (${s.portsUp}/${all.length})',
                style: AppType.bodyBold()),
          ]),
          content: RepaintBoundary(child: _portMap(all)),
        ),
      ],
      const SizedBox(height: Sp.md),
      ExpandableSection(
        key: PageStorageKey('es-${widget.device.id}-ports'),
        initiallyExpanded: true,
        header: Row(children: [
          Icon(LucideIcons.network, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text('تفاصيل المنافذ (${shown.length})', style: AppType.bodyBold()),
        ]),
        content: RepaintBoundary(child: _portsContent(all, shown)),
      ),
    ];
  }

  bool _matchesFilter(EdgeSwitchPort p) {
    if (_connectedOnly && !p.up) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${p.id} ${p.name ?? ''} ${p.description ?? ''}'
        .toLowerCase()
        .contains(q);
  }

  /// صفّ المنافذ كما تراه العين على اللوحة — مربّعٌ لكلّ منفذ بلونه.
  Widget _portMap(List<EdgeSwitchPort> ports) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in ports) _portTile(p),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _mapLegend(AppColors.success, 'يعمل'),
        const SizedBox(width: 10),
        _mapLegend(AppColors.textLow, 'فارغ'),
        const SizedBox(width: 10),
        _mapLegend(AppColors.error, 'مُعطَّل'),
        const SizedBox(width: 10),
        _mapLegend(AppColors.warning, 'PoE'),
      ]),
    ]);
  }

  Widget _portTile(EdgeSwitchPort p) {
    // ثلاث حالاتٍ لا اثنتان: «مُعطَّل إداريّاً» ليس «فارغاً». خلطهما
    // يجعل المشغّل يبحث عن كابلٍ مقطوعٍ بينما المنفذ مُغلَقٌ بأمر.
    final Color c;
    if (!p.enabled) {
      c = AppColors.error;
    } else if (!p.plugged) {
      c = AppColors.textLow;
    } else {
      c = p.poeActive ? AppColors.warning : AppColors.success;
    }
    return Container(
      width: 30,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(p.shortLabel, style: AppType.microBold(color: c)),
    );
  }

  Widget _mapLegend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: c),
            ),
          ),
          const SizedBox(width: 4),
          Text(label, style: AppType.micro(color: AppColors.textMid)),
        ],
      );

  Widget _portsContent(
      List<EdgeSwitchPort> all, List<EdgeSwitchPort> shown) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 34,
            child: TextField(
              style: AppType.micro(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ابحث برقم المنفذ أو وصفه…',
                hintStyle: AppType.micro(color: AppColors.textLow),
                prefixIcon:
                    Icon(LucideIcons.search, size: 14, color: AppColors.textLow),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text('الموصولة فقط', style: AppType.micro()),
          selected: _connectedOnly,
          onSelected: (v) => setState(() => _connectedOnly = v),
          visualDensity: VisualDensity.compact,
        ),
      ]),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('لا منافذ مطابقة',
              style: AppType.micro(color: AppColors.textLow)),
        )
      else
        for (final p in shown) _portRow(p),
    ]);
  }

  Widget _portRow(EdgeSwitchPort p) {
    final on = p.up;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 26,
          alignment: Alignment.center,
          child: Text(p.shortLabel,
              style: AppType.microBold(
                  color: on ? AppColors.success : AppColors.textLow)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              p.name?.isNotEmpty == true
                  ? p.name!
                  : (p.description ?? (on ? 'موصول' : 'غير موصول')),
              style: AppType.micro(color: AppColors.textHi),
              overflow: TextOverflow.ellipsis,
            ),
            if (p.txBytes != null || p.rxBytes != null)
              Text(
                '▲ ${_fmtBytes(p.txBytes)}  ▼ ${_fmtBytes(p.rxBytes)}',
                style: AppType.micro(color: AppColors.textLow),
              ),
          ]),
        ),
        if (p.poeActive) ...[
          Icon(LucideIcons.zap, size: 11, color: AppColors.warning),
          const SizedBox(width: 2),
          Text('${p.poeWatts!.toStringAsFixed(1)}W',
              style: AppType.microBold(color: AppColors.warning)),
          const SizedBox(width: 8),
        ],
        if ((p.errors ?? 0) > 0) ...[
          Icon(LucideIcons.triangleAlert, size: 11, color: AppColors.error),
          const SizedBox(width: 2),
          Text('${p.errors}',
              style: AppType.microBold(color: AppColors.error)),
          const SizedBox(width: 8),
        ],
        // السرعة إلى اليسار كبقيّة الحقول — طلب المستخدم ٢٠٢٦-٠٩.
        Text(
          !p.enabled ? 'مُعطَّل' : (p.speed == null ? '—' : _fmtSpeed(p.speed!)),
          style: AppType.microBold(
              color: !p.enabled
                  ? AppColors.error
                  : (on ? AppColors.textMid : AppColors.textLow)),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // تنسيق
  // ══════════════════════════════════════════════════════════════

  static String _fmtSpeed(int mbps) =>
      mbps >= 1000 ? '${(mbps / 1000).toStringAsFixed(0)}G' : '${mbps}M';

  static String _fmtRate(int bps) {
    if (bps <= 0) return '0';
    if (bps >= 1000000000) return '${(bps / 1e9).toStringAsFixed(1)}Gb';
    if (bps >= 1000000) return '${(bps / 1e6).toStringAsFixed(1)}Mb';
    if (bps >= 1000) return '${(bps / 1e3).toStringAsFixed(0)}Kb';
    return '$bps';
  }

  static String _fmtBytes(int? b) {
    if (b == null || b <= 0) return '0';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)}${u[i]}';
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

class _TrafficSample {
  const _TrafficSample({required this.at, required this.tx, required this.rx});
  final DateTime at;
  final int tx;
  final int rx;
}
