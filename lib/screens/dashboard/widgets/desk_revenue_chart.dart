import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/dashboard_api.dart';
import '../../../core/util/format.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_widgets.dart';

/// «الإيرادات — آخر ٣٠ يوماً» على رئيسيّة الحاسبة (كالموقع): مساحةٌ بخطٍّ واحد (٢px، غسلٌ ١٠٪)، شبكةٌ
/// خافتة بثلاثة خطوط، وعند المرور خطٌّ رأسيّ ونقطةٌ وبطاقة اليوم ومبلغه. سلسلةٌ واحدة: العنوان يسمّيها
/// فلا مفتاح. الأيّام بلا حركة صفرٌ لا فجوة. المصدر طلب الشهر نفسه (`reports/finance` → `timeseries`).
class DeskRevenueChart extends StatefulWidget {
  const DeskRevenueChart({super.key});

  @override
  State<DeskRevenueChart> createState() => _DeskRevenueChartState();
}

class _DeskRevenueChartState extends State<DeskRevenueChart> {
  List<RevenuePoint>? _days;
  int? _total;
  bool _failed = false;
  int? _hover;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    SubscriberEvents.dataChanged.addListener(_onChange);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onChange);
    _debounce?.cancel();
    super.dispose();
  }

  /// عمليّةٌ غيّرت المال (تفعيل، تسديد…) ⇒ يُعاد الجلب بعد هدوءٍ قصير، ولا أكثر من مرّةٍ كلّ ٢٠ث.
  void _onChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      if (DateTime.now().difference(_lastLoad) > const Duration(seconds: 20)) _load();
    });
  }

  Future<void> _load() async {
    _lastLoad = DateTime.now();
    final r = await DashboardApi.fetchRevenue(RevenuePeriod.month);
    if (!mounted) return;
    if (r == null) {
      setState(() => _failed = _days == null);
      return;
    }
    // ثلاثون يوماً كاملة تنتهي اليوم — الأيّام بلا حركة صفر.
    final byDay = {for (final p in r.series) DateTime(p.date.year, p.date.month, p.date.day): p.amount};
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    setState(() {
      _failed = false;
      _total = r.amount;
      _days = [
        for (var i = 29; i >= 0; i--)
          () {
            final d = end.subtract(Duration(days: i));
            return RevenuePoint(date: d, amount: byDay[d] ?? 0);
          }(),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final currency = 'common.currency'.tr();
    final days = _days;
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: DeskCard.decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('desktop.revenue_30d'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.label(color: AppColors.textHi)
                            .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _total == null ? ' ' : '${'desktop.total'.tr()} ${formatIQD(_total!)} $currency',
                      maxLines: 1,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'desktop.refresh'.tr(),
                onPressed: _load,
                icon: Icon(LucideIcons.refreshCw, size: 17, color: AppColors.textMid),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          SizedBox(
            height: 220,
            child: days == null
                ? Center(
                    child: _failed
                        ? Text('desktop.chart_failed'.tr(), style: AppType.muted(color: AppColors.textMid))
                        : SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand)),
                  )
                : LayoutBuilder(builder: (context, c) => _chart(days, c.biggest, currency)),
          ),
        ],
      ),
    );
  }

  static const double _axisW = 64;
  static const double _axisH = 22;

  Widget _chart(List<RevenuePoint> days, Size size, String currency) {
    final maxV = days.fold<int>(0, (m, p) => math.max(m, p.amount));
    final top = _niceCeil(maxV);
    final plotW = size.width - _axisW;
    final plotH = size.height - _axisH;
    double xOf(int i) => _axisW + (days.length == 1 ? plotW / 2 : plotW * i / (days.length - 1));
    double yOf(int v) => top == 0 ? plotH : plotH - plotH * v / top;
    final h = _hover;
    return MouseRegion(
      onHover: (e) {
        final x = e.localPosition.dx - _axisW;
        final i = ((x / plotW) * (days.length - 1)).round().clamp(0, days.length - 1);
        if (i != _hover) setState(() => _hover = i);
      },
      onExit: (_) => setState(() => _hover = null),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // الرسم يُرسم يساراً→يميناً (الزمن يتقدّم يميناً كما يقرأه الجميع في الرسوم) — لا يُعكس.
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: CustomPaint(
                painter: _AreaPainter(
                  values: [for (final p in days) p.amount],
                  top: top,
                  axisW: _axisW,
                  axisH: _axisH,
                  hover: h,
                  line: AppColors.chartLine,
                  grid: AppColors.border,
                  surface: AppColors.surface,
                  labelStyle: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 11),
                  // من اليوم رجوعاً كلّ أسبوع — فآخر يومٍ موسومٌ دائماً ولا يتلاصق تاريخان.
                  xLabels: {
                    for (var i = days.length - 1; i >= 0; i -= 7)
                      i: DateFormat('MM/dd').format(days[i].date),
                  },
                  yLabel: (v) => _compact(v),
                ),
              ),
            ),
          ),
          if (h != null)
            Positioned(
              left: (xOf(h) + 12 + 170 > size.width) ? xOf(h) - 12 - 170 : xOf(h) + 12,
              top: math.max(0, yOf(days[h].amount) - 30),
              child: IgnorePointer(
                child: Container(
                  width: 170,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: AppColors.border),
                    boxShadow: Sh.sheet,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('yyyy/MM/dd').format(days[h].date),
                          textDirection: TextDirection.ltr,
                          style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text('${formatIQD(days[h].amount)} $currency',
                          style: AppType.label(color: AppColors.textHi)
                              .copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// سقف المحور = ٤ × خطوةٍ «مستديرة» (١ · ٢ · ٢٫٥ · ٥ × ١٠ⁿ): ١٨٠ ألفاً ⇒ ٥٠ ألفاً × ٤ = ٢٠٠ ألف —
  /// فخطوط الشبكة الأربعة على أرقامٍ تُقرأ (٥٠K · ١٠٠K · ١٥٠K · ٢٠٠K).
  static int _niceCeil(int v) {
    if (v <= 0) return 0;
    final raw = v / _AreaPainter.gridLines;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1, 2, 2.5, 5, 10]) {
      final step = m * mag;
      if (step >= raw) return (step * _AreaPainter.gridLines).round();
    }
    return (10 * mag * _AreaPainter.gridLines).round();
  }

  static String _compact(int v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m == m.roundToDouble() ? m.toInt() : m.toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)}K';
    }
    return '$v';
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.values,
    required this.top,
    required this.axisW,
    required this.axisH,
    required this.hover,
    required this.line,
    required this.grid,
    required this.surface,
    required this.labelStyle,
    required this.xLabels,
    required this.yLabel,
  });

  final List<int> values;
  final int top;
  final double axisW;
  final double axisH;
  final int? hover;
  final Color line;
  final Color grid;
  final Color surface;
  final TextStyle labelStyle;
  final Map<int, String> xLabels;
  final String Function(int) yLabel;

  /// خطوط الشبكة فوق القاعدة.
  static const int gridLines = 4;

  void _text(Canvas c, String s, Offset at, {bool right = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    var o = at;
    if (right) o = Offset(at.dx - tp.width, at.dy - tp.height / 2);
    if (center) o = Offset(at.dx - tp.width / 2, at.dy);
    tp.paint(c, o);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - axisW;
    final plotH = size.height - axisH;
    final n = values.length;
    double xOf(int i) => axisW + (n == 1 ? plotW / 2 : plotW * i / (n - 1));
    double yOf(num v) => top == 0 ? plotH : plotH - plotH * v / top;

    // الشبكة: أربعة خطوط شعريّة متّصلة (لا متقطّعة) + خطّ القاعدة.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= gridLines; k++) {
      final v = top * k / gridLines;
      final y = yOf(v);
      canvas.drawLine(Offset(axisW, y), Offset(size.width, y), gridPaint);
      if (top > 0 || k == 0) _text(canvas, yLabel(v.round()), Offset(axisW - 8, y), right: true);
    }
    xLabels.forEach((i, s) => _text(canvas, s, Offset(xOf(i), plotH + 6), center: true));

    if (n == 0) return;
    final path = Path()..moveTo(xOf(0), yOf(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(xOf(i), yOf(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(xOf(n - 1), plotH)
      ..lineTo(xOf(0), plotH)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final h = hover;
    if (h != null) {
      final x = xOf(h);
      canvas.drawLine(Offset(x, 0), Offset(x, plotH), Paint()
        ..color = grid
        ..strokeWidth = 1);
      final p = Offset(x, yOf(values[h]));
      // نقطة ≥ ٨px بحلقةٍ بلون السطح تفصلها عن الخطّ.
      canvas.drawCircle(p, 6, Paint()..color = surface);
      canvas.drawCircle(p, 4.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.values != values || old.hover != hover || old.top != top || old.line != line;
}
