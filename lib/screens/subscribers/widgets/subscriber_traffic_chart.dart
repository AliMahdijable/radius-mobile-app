import 'dart:math' as math;

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
    if (_samples.isNotEmpty && sample.at.isBefore(_samples.last.at))
      _samples.clear();
    if (_samples.isNotEmpty && sample.at == _samples.last.at)
      _samples.removeLast();
    _samples.add(sample);
    final cutoff = sample.at.subtract(window);
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    if (_samples.length > capacity)
      _samples.removeRange(0, _samples.length - capacity);
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

/// Mirrored download/upload bars from device polls; no extra requests or invented history.
class SubscriberTrafficChart extends StatelessWidget {
  const SubscriberTrafficChart(
      {super.key,
      required this.samples,
      required this.downBps,
      required this.upBps,
      this.unavailable = false});
  final List<SubscriberTrafficSample> samples;
  final int? downBps;
  final int? upBps;
  final bool unavailable;

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
            Row(children: [
              Expanded(
                  child: _rate(Icons.arrow_downward_rounded, downBps,
                      AppColors.chartLine, 22)),
              const SizedBox(width: Sp.sm),
              Expanded(
                  child: _rate(
                      Icons.arrow_upward_rounded, upBps, AppColors.textHi, 18)),
            ]),
            const SizedBox(height: Sp.sm),
            SizedBox(
                height: 78,
                child: readings.length < 2
                    ? Center(
                        child: Text(
                            unavailable
                                ? 'بانتظار إعادة المحاولة'
                                : readings.isEmpty
                                    ? 'يظهر الرسم عند وصول القراءات'
                                    : 'تجميع القراءات…',
                            textAlign: TextAlign.center,
                            style: AppType.micro(color: AppColors.textLabel)))
                    : Stack(children: [
                        Positioned.fill(
                            child: ClipRect(
                                child: CustomPaint(
                                    painter: _TrafficPainter(
                          samples: samples,
                          maxY: maxY,
                          downColor: AppColors.chartLine
                              .withValues(alpha: live ? 1 : 0.45),
                          upColor: AppColors.textHi
                              .withValues(alpha: live ? 0.7 : 0.35),
                          gridColor: AppColors.border,
                        )))),
                        Positioned(
                            left: 0,
                            top: 0,
                            child: Text(subscriberTrafficRate(maxY.round()),
                                textDirection: TextDirection.ltr,
                                style:
                                    AppType.micro(color: AppColors.textLabel))),
                      ])),
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
          ]),
    );
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

class _TrafficPainter extends CustomPainter {
  const _TrafficPainter(
      {required this.samples,
      required this.maxY,
      required this.downColor,
      required this.upColor,
      required this.gridColor});
  final List<SubscriberTrafficSample> samples;
  final double maxY;
  final Color downColor, upColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, size.height * fraction),
            Offset(math.min(x + 3, size.width), size.height * fraction), grid);
      }
    }
    if (samples.length < 2) return;
    final start = samples.first.at;
    final duration = samples.last.at.difference(start).inMilliseconds;
    if (duration <= 0) return;
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
      old.maxY != maxY ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.gridColor != gridColor;
}
