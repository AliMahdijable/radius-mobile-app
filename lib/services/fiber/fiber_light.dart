import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'fiber_band.dart';
import 'fiber_onu.dart';
import 'fiber_tree.dart';

/// يوم بغداد (UTC+3، بلا توقيتٍ صيفيّ) «YYYY-MM-DD».
String fiberDay(DateTime t) {
  final b = t.toUtc().add(const Duration(hours: 3));
  String p(int n) => n.toString().padLeft(2, '0');
  return '${b.year}-${p(b.month)}-${p(b.day)}';
}

/// اليوم السابق لـ«YYYY-MM-DD».
String fiberDayBefore(String day, [int n = 1]) {
  final d = DateTime.utc(int.parse(day.substring(0, 4)), int.parse(day.substring(5, 7)), int.parse(day.substring(8, 10)));
  return fiberDay(d.subtract(Duration(days: n)).subtract(const Duration(hours: 3)));
}

/// قراءات الضوء ليومٍ واحد لـONU واحدة.
@immutable
class RxDay {
  const RxDay({required this.day, required this.min, required this.avg, required this.max, required this.n});

  final String day;
  final double min, avg, max;
  final int n;

  RxDay add(double rx) => RxDay(
        day: day,
        min: math.min(min, rx),
        max: math.max(max, rx),
        avg: (avg * n + rx) / (n + 1),
        n: n + 1,
      );

  /// يدمج يوماً من جهازٍ آخر (أو من الخادم) — متوسّطٌ موزون بالعيّنات.
  RxDay merge(RxDay o) => RxDay(
        day: day,
        min: math.min(min, o.min),
        max: math.max(max, o.max),
        avg: (avg * n + o.avg * o.n) / (n + o.n),
        n: n + o.n,
      );

  static RxDay? fromJson(Object? j) {
    if (j is! Map) return null;
    final day = j['day'];
    double? d(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    final mn = d(j['min']), av = d(j['avg']), mx = d(j['max']);
    final n = j['n'] is int ? j['n'] as int : int.tryParse('${j['n']}');
    if (day is! String || !RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(day)) return null;
    if (mn == null || av == null || mx == null || n == null || n <= 0) return null;
    if (!FiberBands.plausible(av) || mn > av + 0.01 || mx < av - 0.01) return null;
    return RxDay(day: day, min: mn, avg: av, max: mx, n: n);
  }

  Map<String, dynamic> toJson() => {
        'day': day,
        'min': double.parse(min.toStringAsFixed(2)),
        'avg': double.parse(avg.toStringAsFixed(2)),
        'max': double.parse(max.toStringAsFixed(2)),
        'n': n,
      };
}

/// دفتر الضوء اليوميّ لأولتٍ واحد: لكلّ ONU أيّامها (حتى [keepDays]). يُسجَّل فيه كلّ قراءة ويُرفع للخادم.
class RxDailyBook {
  RxDailyBook({Map<String, Map<String, RxDay>>? data}) : _data = data ?? {};

  static const keepDays = 35;

  final Map<String, Map<String, RxDay>> _data;

  /// أيّامٌ تغيّرت منذ آخر رفع: `key|day`.
  final Set<String> _dirty = {};

  Map<String, Map<String, RxDay>> get data => _data;
  bool get hasDirty => _dirty.isNotEmpty;

  void record(String key, double rx, DateTime at) {
    if (!FiberBands.plausible(rx)) return;
    final day = fiberDay(at);
    final days = _data.putIfAbsent(key, () => {});
    final cur = days[day];
    days[day] = cur == null ? RxDay(day: day, min: rx, avg: rx, max: rx, n: 1) : cur.add(rx);
    _dirty.add('$key|$day');
  }

  /// يدمج ما رجع من الخادم: الأيّام الماضية من الخادم (مجموع الأجهزة)، واليوم يبقى المحلّيّ ما لم يكن الخادم أغنى.
  void mergeServer(String key, RxDay d, {required String today}) {
    final days = _data.putIfAbsent(key, () => {});
    final cur = days[d.day];
    if (cur == null || d.day != today || d.n > cur.n) days[d.day] = d;
  }

  /// صفوف الرفع وتفريغ العلامة. الخادم يدمج (أدنى/أعلى/متوسّطٌ موزون) فلا تُكرَّر العيّنات: نرسل اليوم كاملاً ويستبدله.
  List<Map<String, dynamic>> takeDirty() {
    final out = <Map<String, dynamic>>[];
    for (final k in _dirty) {
      final i = k.lastIndexOf('|');
      final key = k.substring(0, i);
      final day = k.substring(i + 1);
      final d = _data[key]?[day];
      if (d != null) out.add({'key': key, ...d.toJson()});
    }
    _dirty.clear();
    return out;
  }

  /// رفعٌ فشل: الصفوف تبقى معلَّمةً للمرّة القادمة (بلا إعادة تسجيل عيّناتها).
  void restoreDirty(Iterable<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final key = r['key'];
      final day = r['day'];
      if (key is String && day is String && (_data[key]?.containsKey(day) ?? false)) _dirty.add('$key|$day');
    }
  }

  void prune(String today) {
    final cutoff = fiberDayBefore(today, keepDays);
    for (final days in _data.values) {
      days.removeWhere((d, _) => d.compareTo(cutoff) < 0);
    }
    _data.removeWhere((_, days) => days.isEmpty);
  }

  /// متوسّطات الأيّام [from]..[to] (شاملة) مرتّبةً — للرسم الصغير.
  List<RxDay> series(String key, {required String today, int days = 7}) {
    final d = _data[key];
    if (d == null) return const [];
    final from = fiberDayBefore(today, days - 1);
    return [
      for (final e in d.entries)
        if (e.key.compareTo(from) >= 0 && e.key.compareTo(today) <= 0) e.value,
    ]..sort((a, b) => a.day.compareTo(b.day));
  }

  Map<String, dynamic> toJson() => {
        for (final e in _data.entries) e.key: [for (final d in e.value.values) d.toJson()],
      };

  static RxDailyBook fromJson(Object? j) {
    final data = <String, Map<String, RxDay>>{};
    if (j is Map) {
      for (final e in j.entries) {
        final list = e.value;
        if (e.key is! String || list is! List) continue;
        final days = <String, RxDay>{};
        for (final x in list) {
          final d = RxDay.fromJson(x);
          if (d != null) days[d.day] = d;
        }
        if (days.isNotEmpty) data[e.key as String] = days;
      }
    }
    return RxDailyBook(data: data);
  }
}

/// جهازٌ نزل ضوءه عن خطّ أساسه (متوسّط الأيّام السبعة السابقة).
@immutable
class RxDrop {
  const RxDrop({required this.key, required this.current, required this.baseline, required this.series});
  final String key;
  final double current, baseline;
  final List<RxDay> series;
  double get drop => baseline - current;
}

/// صندوقٌ نزلت أجهزته معاً — الخلل بالصندوق (رطوبة، وصلة الدخول) لا بالبيوت.
@immutable
class RxBoxDrop {
  const RxBoxDrop({required this.boxId, required this.drops, required this.boxOnusWithData});
  final int boxId;
  final List<RxDrop> drops;
  final int boxOnusWithData;
  double get avgDrop => drops.isEmpty ? 0 : drops.map((d) => d.drop).reduce((a, b) => a + b) / drops.length;
}

/// ضعيفٌ منذ أيّام بلا تغيّر — من المسافة أو تصميم الخطّ، لا خللٌ جديد.
@immutable
class RxStableWeak {
  const RxStableWeak({required this.key, required this.current, required this.days, required this.series});
  final String key;
  final double current;
  final int days;
  final List<RxDay> series;
}

@immutable
class FiberLightReport {
  const FiberLightReport({
    required this.histogram,
    required this.good,
    required this.marginal,
    required this.weak,
    required this.strong,
    required this.noReading,
    required this.suddenDrops,
    required this.boxDrops,
    required this.stableWeak,
    required this.historyDays,
  });

  /// خانة ⌈rx⌉ ← عدد الأجهزة.
  final Map<int, int> histogram;
  final int good, marginal, weak, strong, noReading;
  final List<RxDrop> suddenDrops;
  final List<RxBoxDrop> boxDrops;
  final List<RxStableWeak> stableWeak;

  /// أكثر عددٍ من الأيّام المسجّلة لجهازٍ واحد — «التاريخ يتجمّع» حين يقلّ.
  final int historyDays;

  int get attention => marginal + weak + strong;
}

class FiberLightAnalysis {
  FiberLightAnalysis._();

  static const suddenDropDb = 2.0;
  static const boxDropDb = 1.5;
  static const boxShare = 0.6;
  static const stableSpreadDb = 1.0;
  static const stableMinDays = 5;

  static double? _median(List<double> v) {
    if (v.isEmpty) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  /// خطّ الأساس: وسيط متوسّطات الأيّام السبعة قبل اليوم (يومان على الأقلّ).
  static double? baseline(RxDailyBook book, String key, String today) {
    final d = book.data[key];
    if (d == null) return null;
    final from = fiberDayBefore(today, 7);
    final vals = [
      for (final e in d.entries)
        if (e.key.compareTo(from) >= 0 && e.key.compareTo(today) < 0) e.value.avg,
    ];
    return vals.length >= 2 ? _median(vals) : null;
  }

  static FiberLightReport analyze({
    required List<FiberOnuLive> onus,
    required RxDailyBook book,
    required DateTime now,
    List<FiberPonTree> trees = const [],
  }) {
    final today = fiberDay(now);
    final hist = <int, int>{};
    var good = 0, marginal = 0, weak = 0, strong = 0, none = 0;
    final drops = <String, RxDrop>{};
    final stable = <RxStableWeak>[];
    var maxDays = 0;
    for (final o in onus) {
      final days = book.data[o.key]?.length ?? 0;
      if (days > maxDays) maxDays = days;
      final rx = o.rx;
      if (rx == null) {
        none++;
        continue;
      }
      hist.update(FiberBands.bin(rx), (n) => n + 1, ifAbsent: () => 1);
      switch (FiberBands.of(rx)!) {
        case FiberBand.good:
          good++;
        case FiberBand.marginal:
          marginal++;
        case FiberBand.weak:
          weak++;
        case FiberBand.strong:
          strong++;
      }
      final base = baseline(book, o.key, today);
      final series = book.series(o.key, today: today);
      if (base != null && base - rx >= boxDropDb) {
        drops[o.key] = RxDrop(key: o.key, current: rx, baseline: base, series: series);
      }
      if (FiberBands.of(rx) == FiberBand.weak) {
        final week = book.series(o.key, today: today);
        if (week.length >= stableMinDays) {
          final avgs = week.map((d) => d.avg);
          final spread = avgs.reduce(math.max) - avgs.reduce(math.min);
          if (spread < stableSpreadDb && (base == null || (base - rx).abs() < stableSpreadDb)) {
            stable.add(RxStableWeak(key: o.key, current: rx, days: week.length, series: week));
          }
        }
      }
    }

    // صناديق نزلت أغلب أجهزتها معاً (≥٣ و≥٦٠٪ ممّن لها تاريخ).
    final boxDrops = <RxBoxDrop>[];
    final inBox = <String>{};
    for (final t in trees) {
      for (final b in t.nodes.values) {
        final under = t.onusUnder(b.id).where((o) => o.rx != null && baseline(book, o.key, today) != null).toList();
        if (under.length < 3) continue;
        final dropped = [
          for (final o in under)
            if (drops[o.key] case final d?) d,
        ];
        if (dropped.length >= 3 && dropped.length >= (under.length * boxShare).ceil()) {
          // الصندوق الأدنى يكفي: لا نعدّ الموزّع فوقه مرّةً ثانية إن كان كلّ ما نزل تحت صندوقٍ واحد.
          boxDrops.add(RxBoxDrop(boxId: b.id, drops: dropped, boxOnusWithData: under.length));
        }
      }
    }
    // أبقِ الأدنى: موزّعٌ نزوله كلّه من صندوقٍ تحته لا يُعرض مرّتين.
    boxDrops.removeWhere((parent) => boxDrops.any((child) =>
        child.boxId != parent.boxId &&
        child.drops.length == parent.drops.length &&
        trees.any((t) => t.pathTo(child.boxId).any((p) => p.id == parent.boxId))));
    for (final b in boxDrops) {
      inBox.addAll(b.drops.map((d) => d.key));
    }
    final sudden = [
      for (final d in drops.values)
        if (d.drop >= suddenDropDb && !inBox.contains(d.key)) d,
    ]..sort((a, b) => b.drop.compareTo(a.drop));
    stable.sort((a, b) => a.current.compareTo(b.current));
    boxDrops.sort((a, b) => b.drops.length.compareTo(a.drops.length));
    return FiberLightReport(
      histogram: Map.unmodifiable(hist),
      good: good,
      marginal: marginal,
      weak: weak,
      strong: strong,
      noReading: none,
      suddenDrops: List.unmodifiable(sudden),
      boxDrops: List.unmodifiable(boxDrops),
      stableWeak: List.unmodifiable(stable),
      historyDays: maxDays,
    );
  }
}
