import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// A missing reading separates runs; it must never look like zero traffic.
class SubscriberTrafficSample {
  const SubscriberTrafficSample(this.at, this.down, this.up);
  final DateTime at;
  final int? down;
  final int? up;
  bool get valid => down != null && up != null;
}

/// Only readings from the existing device poll are retained, for at most four minutes.
class SubscriberTrafficHistory {
  static const window = Duration(minutes: 4);
  static const capacity = 96;
  final _samples = <SubscriberTrafficSample>[];
  List<SubscriberTrafficSample> get samples => List.unmodifiable(_samples);

  void add(DateTime at, int down, int up) {
    if (down < 0 || up < 0) return;
    _append(SubscriberTrafficSample(at, down, up));
  }

  void gap(DateTime at) {
    if (_samples.isNotEmpty && _samples.last.valid) {
      _append(SubscriberTrafficSample(at, null, null));
    }
  }

  void _append(SubscriberTrafficSample sample) {
    // A clock correction must not draw a line backwards in time.
    if (_samples.isNotEmpty && sample.at.isBefore(_samples.last.at)) {
      _samples.clear();
    }
    if (_samples.isNotEmpty && sample.at == _samples.last.at) {
      _samples.removeLast();
    }
    _samples.add(sample);
    final cutoff = sample.at.subtract(window);
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
  }

  void clear() => _samples.clear();
}

String subscriberTrafficRate(int? bps) {
  if (bps == null) return '—';
  final (divisor, unit) = bps >= 1000000000
      ? (1000000000, 'Gbps')
      : bps >= 1000000
          ? (1000000, 'Mbps')
          : (1000, 'Kbps');
  final value = bps / divisor;
  return '${value == 0 ? '0' : value < 10 ? value.toStringAsFixed(1) : value.toStringAsFixed(0)} $unit';
}

enum SubscriberTrafficDesign { wave, bars, gauges, compact }

double _niceScale(int value) {
  final peak = math.max(1000, value);
  final magnitude =
      math.pow(10, (math.log(peak) / math.ln10).floor()).toDouble();
  return (peak * 1.1 / magnitude).ceil() * magnitude;
}

// Comparison APKs select only the presentation; polling and data stay identical.
const _buildDesign =
    String.fromEnvironment('TRAFFIC_DESIGN', defaultValue: 'wave');
const _defaultDesign = _buildDesign == 'bars'
    ? SubscriberTrafficDesign.bars
    : _buildDesign == 'gauges'
        ? SubscriberTrafficDesign.gauges
        : _buildDesign == 'compact'
            ? SubscriberTrafficDesign.compact
            : SubscriberTrafficDesign.wave;

/// Live device readings; no extra requests or invented history in any design.
class SubscriberTrafficChart extends StatelessWidget {
  const SubscriberTrafficChart(
      {super.key,
      required this.samples,
      required this.downBps,
      required this.upBps,
      this.design = _defaultDesign,
      this.unavailable = false});
  final List<SubscriberTrafficSample> samples;
  final int? downBps;
  final int? upBps;
  final bool unavailable;
  final SubscriberTrafficDesign design;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final readings = samples.where((s) => s.valid).toList();
    final live = downBps != null && upBps != null;
    final peakDown =
        readings.fold<int>(0, (peak, s) => math.max(peak, s.down!));
    final peak = readings.fold<int>(
        1000, (peak, s) => math.max(peak, math.max(s.down!, s.up!)));
    final magnitude =
        math.pow(10, (math.log(peak) / math.ln10).floor()).toDouble();
    final maxY = (peak * 1.1 / magnitude).ceil() * magnitude;
    final seconds = readings.length < 2
        ? 0
        : readings.last.at.difference(readings.first.at).inSeconds;
    final period = seconds >= 60 ? 'آخر ${seconds ~/ 60} د' : 'آخر $seconds ث';
    final status = live
        ? 'الترافيك الآن'
        : unavailable
            ? 'تعذّرت قراءة الترافيك'
            : readings.isEmpty
                ? 'بانتظار القراءة'
                : 'القراءة متوقفة';
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.icon)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: live ? AppColors.success : AppColors.textHint,
                  )),
              const SizedBox(width: Sp.x6),
              Expanded(
                  child: Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.microBold(color: AppColors.textMid))),
              if (seconds > 0)
                Text(period, style: AppType.micro(color: AppColors.textLabel)),
            ]),
            const SizedBox(height: Sp.sm),
            if (design == SubscriberTrafficDesign.gauges) ...[
              Row(children: [
                Expanded(
                    child: _gauge(
                        'تحميل',
                        downBps,
                        readings.isEmpty ? null : peakDown,
                        AppColors.chartLine)),
                const SizedBox(width: Sp.sm),
                Expanded(
                    child: _gauge(
                        'رفع',
                        upBps,
                        readings.isEmpty
                            ? null
                            : readings.fold<int>(
                                0, (p, s) => math.max(p, s.up!)),
                        AppColors.textHi)),
              ]),
              if (readings.length < 2) _waiting(readings.isEmpty),
            ] else if (design == SubscriberTrafficDesign.compact) ...[
              Row(children: [
                Expanded(child: _rates(18, 16)),
                const SizedBox(width: Sp.sm),
                SizedBox(
                    width: 70,
                    height: 28,
                    child: readings.length < 2
                        ? null
                        : _graph(maxY, live, compact: true)),
              ]),
              if (readings.length < 2) _waiting(readings.isEmpty),
            ] else ...[
              _rates(22, 18),
              const SizedBox(height: Sp.sm),
              SizedBox(
                  height: 78,
                  child: readings.length < 2
                      ? _waiting(readings.isEmpty)
                      : Stack(children: [
                          Positioned.fill(child: _graph(maxY, live)),
                          Positioned(
                              left: 0,
                              top: 0,
                              child: Text(subscriberTrafficRate(maxY.round()),
                                  textDirection: TextDirection.ltr,
                                  style: AppType.micro(
                                      color: AppColors.textLabel))),
                        ])),
            ],
            if (design == SubscriberTrafficDesign.wave ||
                design == SubscriberTrafficDesign.bars) ...[
              const SizedBox(height: Sp.x6),
              Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: Sp.sm,
                  runSpacing: Sp.xs,
                  children: [
                    Text(
                        'ذروة التحميل: \u2066${readings.isEmpty ? '—' : subscriberTrafficRate(peakDown)}\u2069',
                        style: AppType.micro(color: AppColors.textLabel)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _legend('تحميل', AppColors.chartLine),
                      const SizedBox(width: Sp.sm),
                      _legend('رفع', AppColors.textHi),
                    ]),
                  ]),
            ],
          ]),
    );
  }

  Widget _waiting(bool empty) => Center(
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.xs),
          child: Text(
              unavailable
                  ? 'بانتظار إعادة المحاولة'
                  : empty
                      ? 'يظهر الرسم عند وصول القراءات'
                      : 'تجميع القراءات…',
              textAlign: TextAlign.center,
              style: AppType.micro(color: AppColors.textLabel))));

  Widget _rates(double downSize, double upSize) => Row(children: [
        Expanded(
            child: _rate(Icons.arrow_downward_rounded, downBps,
                AppColors.chartLine, downSize)),
        const SizedBox(width: Sp.sm),
        Expanded(
            child: _rate(
                Icons.arrow_upward_rounded, upBps, AppColors.textHi, upSize)),
      ]);

  Widget _graph(double maxY, bool live, {bool compact = false}) => ClipRect(
      child: CustomPaint(
          painter: _TrafficPainter(
              samples: samples,
              maxY: maxY,
              bars: design == SubscriberTrafficDesign.bars,
              grid: !compact,
              downColor: AppColors.chartLine.withValues(alpha: live ? 1 : 0.45),
              upColor: AppColors.textHi.withValues(alpha: live ? 0.7 : 0.35),
              gridColor: AppColors.border)));

  Widget _gauge(String label, int? value, int? peak, Color color) {
    final actualPeak =
        peak == null && value == null ? null : math.max(peak ?? 0, value ?? 0);
    final scale = _niceScale(actualPeak ?? 0);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
          width: double.infinity,
          height: 60,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            Positioned.fill(
                child: CustomPaint(
                    painter: _GaugePainter(
                        fraction: value == null ? null : value / scale,
                        color: color,
                        trackColor: AppColors.border))),
            Padding(
                padding: const EdgeInsets.only(bottom: Sp.xs),
                child: Text(label,
                    style: AppType.microBold(color: AppColors.textMid))),
          ])),
      const SizedBox(height: Sp.x6),
      FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(subscriberTrafficRate(value),
              textDirection: TextDirection.ltr,
              style: AppType.statValue(color: color).copyWith(fontSize: 18))),
      const SizedBox(height: Sp.xs),
      Text('ذروة: \u2066${subscriberTrafficRate(actualPeak)}\u2069',
          textAlign: TextAlign.center,
          style: AppType.micro(color: AppColors.textLabel)),
      Text(
          'المقياس: \u2066${subscriberTrafficRate(actualPeak == null ? null : scale.round())}\u2069',
          textAlign: TextAlign.center,
          style: AppType.micro(color: AppColors.textLabel)),
    ]);
  }

  Widget _rate(IconData icon, int? value, Color color, double size) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.ltr,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: Sp.xs),
              Text(subscriberTrafficRate(value),
                  textDirection: TextDirection.ltr,
                  style: AppType.statValue(color: color)
                      .copyWith(fontSize: size, fontWeight: FontWeight.w700)),
            ]),
      );

  Widget _legend(String label, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 3,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(R.pill))),
        const SizedBox(width: Sp.xs),
        Text(label, style: AppType.micro(color: AppColors.textLabel)),
      ]);
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter(
      {required this.fraction, required this.color, required this.trackColor});
  final double? fraction;
  final Color color, trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final radius = math.min(size.width / 2, size.height) - stroke / 2 - 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height - 4), radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, paint..color = trackColor);
    // Missing and true-zero readings never draw a positive filled segment.
    if (fraction != null && fraction! > 0) {
      canvas.drawArc(rect, math.pi, math.pi * fraction!.clamp(0, 1), false,
          paint..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor;
}

class _TrafficPainter extends CustomPainter {
  const _TrafficPainter(
      {required this.samples,
      required this.maxY,
      required this.downColor,
      required this.upColor,
      required this.gridColor,
      this.bars = false,
      this.grid = true});
  final List<SubscriberTrafficSample> samples;
  final double maxY;
  final Color downColor, upColor, gridColor;
  final bool bars, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in grid ? [0.0, 0.5, 1.0] : <double>[]) {
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(
            Offset(x, size.height * fraction),
            Offset(math.min(x + 3, size.width), size.height * fraction),
            gridPaint);
      }
    }
    if (samples.length < 2) return;
    final start = samples.first.at;
    final duration = samples.last.at.difference(start).inMilliseconds;
    if (duration <= 0) return;
    if (bars) {
      _paintBars(canvas, size, start, duration);
      return;
    }
    final runs = <List<SubscriberTrafficSample>>[];
    var run = <SubscriberTrafficSample>[];
    for (final sample in samples) {
      if (!sample.valid) {
        if (run.isNotEmpty) runs.add(run);
        run = [];
      } else {
        run.add(sample);
      }
    }
    if (run.isNotEmpty) runs.add(run);
    double x(SubscriberTrafficSample p) =>
        p.at.difference(start).inMilliseconds / duration * size.width;
    double y(int bps) => size.height * (1 - (bps / maxY).clamp(0, 1));
    for (final points in runs) {
      for (final download in [true, false]) {
        final color = download ? downColor : upColor;
        int value(SubscriberTrafficSample p) => download ? p.down! : p.up!;
        final path = Path()..moveTo(x(points.first), y(value(points.first)));
        for (var i = 1; i < points.length; i++) {
          final a = points[i - 1], b = points[i];
          final middle = (x(a) + x(b)) / 2;
          path.cubicTo(
              middle, y(value(a)), middle, y(value(b)), x(b), y(value(b)));
        }
        if (download && points.length > 1) {
          final fill = Path.from(path)
            ..lineTo(x(points.last), size.height)
            ..lineTo(x(points.first), size.height)
            ..close();
          canvas.drawPath(
              fill,
              Paint()
                ..shader =
                    ui.Gradient.linear(Offset.zero, Offset(0, size.height), [
                  color.withValues(alpha: color.a * 0.28),
                  color.withValues(alpha: color.a * 0.02),
                ]));
        }
        canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = download ? 2.2 : 1.5
              ..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(x(points.last), y(value(points.last))),
            download ? 2.5 : 1.5, Paint()..color = color);
      }
    }
  }

  void _paintBars(Canvas canvas, Size size, DateTime start, int duration) {
    final baseline = size.height / 2;
    final halfHeight = baseline - 4;
    final barWidth =
        math.min(6.0, math.max(1.0, size.width / samples.length * 0.64));
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (!sample.valid) continue; // A missing reading stays a gap, not zero.
      final x = sample.at.difference(start).inMilliseconds /
          duration *
          (size.width - barWidth);
      final opacity = 0.45 + 0.55 * i / (samples.length - 1);
      void bar(int value, bool download) {
        if (value <= 0) return;
        final height = math.max(1.0, value / maxY * halfHeight);
        final rect = Rect.fromLTWH(x,
            download ? baseline - 2 - height : baseline + 2, barWidth, height);
        final color = download ? downColor : upColor;
        canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
            Paint()..color = color.withValues(alpha: color.a * opacity));
      }

      bar(sample.down!, true);
      bar(sample.up!, false);
    }
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter old) =>
      old.samples != samples ||
      old.bars != bars ||
      old.grid != grid ||
      old.maxY != maxY ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.gridColor != gridColor;
}
