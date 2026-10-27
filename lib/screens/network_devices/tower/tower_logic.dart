import 'package:flutter/foundation.dart';

import '../../../api/olt_profile.dart';
import '../../../models/network_device.dart';
import '../../../models/tower_layout.dart';
import '../../../theme/colors.dart';
import '../widgets/_grade.dart';
import 'tower_reading.dart';

/// ما يفعله الجهاز على البرج — يحدّد مستواه: اللنك في القمّة، السكتر على الحلقات، نقطة الوصول الصغيرة بالوسط،
/// والسلكيّ (راوتر/سويج/أولت) في الكابينة.
enum TowerRole { link, sector, ap, cabinet }

/// من أين جاء الشكل: حفظه الوكيل، أو الموديل، أو العلامة، أو النوع المكتوب، أو ما قرأناه من الجهاز.
enum ShapeSource { saved, model, brand, type, reading }

/// من أين جاء الاتّجاه: ثبّته الوكيل، أو محفوظٌ تقريبيّ، أو من اسم الجهاز، أو توزيعٌ تلقائيّ.
enum AzimuthSource { fixed, saved, name, auto }

/// شكل الجهاز من موديله — نفس الموديل يُرسم بنفس الشكل عند كلّ وكيل.
///
/// النوع الذي يكتبه الوكيل لا يُعتمد أوّلاً: عند popq سُجّلت الـBaseBox «راوتر» وهي سكاتر. الموديل أوّلاً،
/// ثمّ العلامة، ثمّ النوع المكتوب — وما قرأناه من الجهاز يصحّح الأضعف ([refine]).
class TowerShapes {
  TowerShapes._();

  static List<String> tokens(String s) =>
      RegExp(r'[a-z0-9]+').allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

  /// القواعد بالترتيب (الأوّل يفوز). الكلمة من 3 أحرف فأكثر تطابق **بداية** كلمةٍ من الموديل، والأقصر تطابقها كلّها.
  /// الصحن قبل السكتر (RocketDish ليس Rocket)، واللوحة قبل السكتر (SXT SA5 لوحة، لا Mimosa A5).
  static const rules = <(TowerShape, List<String>)>[
    (TowerShape.olt, ['olt', 'v1600', 'v1601', 'v2802', 'v2808', 'p3600', 'p3608', 'p3616', 'gp3600', 'p3310', 'epon', 'gpon']),
    (TowerShape.omni, ['omnitik', 'rbomnitik', 'groove', 'rbgroove', 'omni']),
    (TowerShape.panel, ['sxt', 'rbsxt', 'nanostation', 'nsm', 'loco', 'liteap', 'qrt', 'rbqrt', 'est']),
    (TowerShape.dish, [
      'powerbeam', 'pbe', 'nanobeam', 'nbe', 'litebeam', 'lbe', 'airfiber', 'af', 'af5', 'af24', 'af60', 'af11', 'gbe',
      'lhg', 'rblhg', 'ldf', 'rbldf', 'dynadish', 'disc', 'rbdisc', 'rocketdish', 'cube', 'b5', 'b5c', 'b5x', 'b11', 'b24',
      'c5', 'c5c', 'c5x',
    ]),
    (TowerShape.sector, ['basebox', 'rb912uag', 'mantbox', 'rb921gs', 'netbox', 'netmetal', 'rocket', 'prism', 'a5', 'a5c', 'a5x', 'sector']),
    (TowerShape.router, [
      'ccr', 'rb4011', 'rb5009', 'rb3011', 'rb2011', 'rb1100', 'rb750', 'rb760', 'rb951', 'rbd52g', 'rbd53', 'hex', 'hap',
      'l009', 'edgerouter', 'er', 'chr', 'x86', 'router',
    ]),
    (TowerShape.sw, ['crs', 'css', 'edgeswitch', 'usw', 'switch', 'catalyst', 'ws', 'sg', 'cbs', 's2528', 's5750', 's2910', 'rg']),
  ];

  static bool _hit(List<String> tokens, String key) =>
      key.length >= 3 ? tokens.any((t) => t.startsWith(key)) : tokens.contains(key);

  static ({TowerShape shape, ShapeSource source}) detect(NetworkDevice d) {
    final t = tokens(d.model ?? '');
    if (t.isNotEmpty) {
      for (final (shape, keys) in rules) {
        if (keys.any((k) => _hit(t, k))) return (shape: shape, source: ShapeSource.model);
      }
    }
    final brand = d.brand.toLowerCase();
    if (brand == 'vsol' || brand == 'bdcom' || OltProfile.fromDevice(d).opensOltPanel) {
      return (shape: TowerShape.olt, source: ShapeSource.brand);
    }
    if (brand == 'cisco' || brand == 'ruijie') return (shape: TowerShape.sw, source: ShapeSource.brand);
    final byType = switch (d.type) {
      'sector' => TowerShape.sector,
      'link' => TowerShape.dish,
      'ap' => TowerShape.panel,
      'router' => TowerShape.router,
      'switch' => TowerShape.sw,
      _ => TowerShape.other,
    };
    return (shape: byType, source: ShapeSource.type);
  }

  /// ما قرأناه يصحّح الشكل حين جاء من العلامة أو النوع المكتوب وحدهما (الموديل والمحفوظ لا يُمسّان).
  static ({TowerShape shape, ShapeSource source}) refine(
    ({TowerShape shape, ShapeSource source}) base,
    TowerReading? r,
  ) {
    if (r == null || base.source == ShapeSource.model || base.source == ShapeSource.saved) return base;
    if (base.shape == TowerShape.olt) return base;
    const radios = {TowerShape.sector, TowerShape.dish, TowerShape.panel, TowerShape.omni};
    if (!r.wireless) {
      return radios.contains(base.shape) ? (shape: TowerShape.router, source: ShapeSource.reading) : base;
    }
    final c = r.clients ?? 0;
    if (r.isAccessPoint && c >= 3) return (shape: TowerShape.sector, source: ShapeSource.reading);
    if (c <= 1) return (shape: TowerShape.dish, source: ShapeSource.reading);
    return (shape: TowerShape.panel, source: ShapeSource.reading);
  }

  static TowerRole roleOf(TowerShape shape, TowerReading? r) {
    if (r != null && r.wireless) {
      final c = r.clients ?? 0;
      if (r.isStation) return TowerRole.link;
      if (c == 1 && shape == TowerShape.dish) return TowerRole.link;
      if (c >= 3 && r.isAccessPoint) {
        return shape == TowerShape.panel || shape == TowerShape.omni ? TowerRole.ap : TowerRole.sector;
      }
    }
    return switch (shape) {
      TowerShape.dish => TowerRole.link,
      TowerShape.sector => TowerRole.sector,
      TowerShape.panel || TowerShape.omni => TowerRole.ap,
      _ => TowerRole.cabinet,
    };
  }

  /// عرض الحزمة الافتراضيّ بالرسم.
  static int defaultBeam(TowerShape s) => switch (s) {
        TowerShape.sector => 90,
        TowerShape.panel => 60,
        TowerShape.omni => 360,
        TowerShape.dish => 8,
        _ => 0,
      };
}

/// اتّجاهٌ مكتوب في اسم الجهاز أو موقعه أو ملاحظته: «45°» · «شمال شرق» · «north». تلميحٌ تقريبيّ لا تثبيت.
int? hintAzimuthFromText(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll(RegExp('[ً-ْـ]'), '');
  t = t.replaceAll(RegExp('[أإآ]'), 'ا');
  t = t.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}');
  final deg = RegExp(r'(\d{1,3})\s*(?:°|درجه|درجة|deg)').firstMatch(t);
  if (deg != null) {
    final v = int.parse(deg.group(1)!);
    if (v <= 360) return v % 360;
  }
  final n = t.contains('شمال') || RegExp(r'\bnorth').hasMatch(t);
  final s = t.contains('جنوب') || RegExp(r'\bsouth').hasMatch(t);
  final e = t.contains('شرق') || RegExp(r'\beast').hasMatch(t);
  final w = t.contains('غرب') || RegExp(r'\bwest').hasMatch(t);
  if ((n && s) || (e && w)) return null;
  if (n && e) return 45;
  if (s && e) return 135;
  if (s && w) return 225;
  if (n && w) return 315;
  if (n) return 0;
  if (e) return 90;
  if (s) return 180;
  if (w) return 270;
  final pair = RegExp(r'\b(ne|nw|se|sw)\b').firstMatch(t)?.group(1);
  return switch (pair) { 'ne' => 45, 'se' => 135, 'sw' => 225, 'nw' => 315, _ => null };
}

/// ترتيبٌ طبيعيّ للأسماء: «جهاز 3» قبل «جهاز 10».
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

int normDeg(num a) => ((a.round() % 360) + 360) % 360;

int angleGap(int a, int b) {
  final d = (normDeg(a) - normDeg(b)).abs();
  return d > 180 ? 360 - d : d;
}

/// جهازٌ بمكانه النهائيّ على البرج — من المحفوظ، وإلّا من الترتيب التلقائيّ.
@immutable
class ArrangedDevice {
  const ArrangedDevice({
    required this.device,
    required this.shape,
    required this.shapeSource,
    required this.role,
    required this.level,
    required this.azimuth,
    required this.beamwidth,
    required this.azimuthSource,
    required this.placement,
  });

  final NetworkDevice device;
  final TowerShape shape;
  final ShapeSource shapeSource;
  final TowerRole role;
  final TowerLevel level;

  /// `null` للكابينة — لا اتّجاه لها.
  final int? azimuth;
  final int beamwidth;
  final AzimuthSource azimuthSource;

  /// ما يُحفظ لو ضغط «رتّبها لي» أو عدّل.
  final TowerPlacement placement;

  bool get fixed => placement.fixed;
  bool get onTower => level != TowerLevel.base;

  /// الاسم يقول «سكتر» والجهاز لنك — يُذكر للوكيل في «رتّبها لي».
  bool get nameSaysSectorButLink {
    final n = device.name.toLowerCase();
    return role == TowerRole.link && (n.contains('سكتر') || n.contains('sector'));
  }
}

class TowerArrange {
  TowerArrange._();

  /// يرتّب أجهزة برجٍ واحد. حتميّ: نفس الأجهزة والقراءات ⇒ نفس الرسم على كلّ هاتف (فلا يُحفظ شيءٌ دون طلب).
  ///
  /// [rearrange] = «رتّبها من جديد»: يتجاهل المحفوظ التقريبيّ، ويُبقي ما ثبّته الوكيل وما اختاره من شكل.
  static Map<int, ArrangedDevice> arrange(
    List<NetworkDevice> devices, {
    Map<int, TowerReading> readings = const {},
    Map<int, TowerPlacement> saved = const {},
    bool rearrange = false,
  }) {
    final ordered = [...devices]..sort((a, b) => naturalCompare(a.name, b.name));
    final shapes = <int, ({TowerShape shape, ShapeSource source})>{};
    final roles = <int, TowerRole>{};
    final keepSaved = <int, bool>{};
    for (final d in ordered) {
      final sp = saved[d.id];
      final reading = readings[d.id];
      final s = sp?.shape != null
          ? (shape: sp!.shape!, source: ShapeSource.saved)
          : TowerShapes.refine(TowerShapes.detect(d), reading);
      shapes[d.id] = s;
      roles[d.id] = TowerShapes.roleOf(s.shape, reading);
      keepSaved[d.id] = sp != null && (sp.fixed || !rearrange);
    }

    // ── الاتّجاه: المحفوظ ⇒ المكتوب في الاسم ⇒ توزيعٌ متساوٍ لكلّ مجموعة ──────────────────────
    final azimuth = <int, int?>{};
    final azSource = <int, AzimuthSource>{};
    for (final role in [TowerRole.link, TowerRole.sector, TowerRole.ap]) {
      final group = ordered.where((d) => roles[d.id] == role).toList();
      final known = <int>[];
      final unknown = <NetworkDevice>[];
      for (final d in group) {
        final sp = saved[d.id];
        if (keepSaved[d.id]! && sp?.azimuth != null) {
          azimuth[d.id] = sp!.azimuth;
          azSource[d.id] = sp.fixed ? AzimuthSource.fixed : AzimuthSource.saved;
          known.add(sp.azimuth!);
          continue;
        }
        final hint = hintAzimuthFromText('${d.name} ${d.location ?? ''} ${d.notes ?? ''}');
        if (hint != null) {
          azimuth[d.id] = hint;
          azSource[d.id] = AzimuthSource.name;
          known.add(hint);
        } else {
          unknown.add(d);
        }
      }
      if (unknown.isEmpty) continue;
      final total = unknown.length + known.length;
      final offset = switch (role) { TowerRole.link => 135, TowerRole.ap => 20, _ => 0 };
      final slots = [for (var i = 0; i < total; i++) normDeg(offset + i * 360 / total)];
      for (final k in known) {
        if (slots.length <= unknown.length) break;
        var best = 0;
        for (var i = 1; i < slots.length; i++) {
          if (angleGap(slots[i], k) < angleGap(slots[best], k)) best = i;
        }
        slots.removeAt(best);
      }
      for (var i = 0; i < unknown.length; i++) {
        azimuth[unknown[i].id] = slots[i];
        azSource[unknown[i].id] = AzimuthSource.auto;
      }
    }

    // ── المستوى: المحفوظ، وإلّا من الدور؛ والسكاتر حلقتان متناوبتان بترتيب الاتّجاه ──────────────
    final level = <int, TowerLevel>{};
    for (final d in ordered) {
      final sp = saved[d.id];
      if (keepSaved[d.id]! && sp?.level != null) {
        level[d.id] = sp!.level!;
        continue;
      }
      switch (roles[d.id]!) {
        case TowerRole.link:
          level[d.id] = TowerLevel.top;
        case TowerRole.ap:
          level[d.id] = TowerLevel.mid;
        case TowerRole.cabinet:
          level[d.id] = TowerLevel.base;
        case TowerRole.sector:
          break;
      }
    }
    final ring = ordered.where((d) => roles[d.id] == TowerRole.sector && !level.containsKey(d.id)).toList()
      ..sort((a, b) {
        final c = (azimuth[a.id] ?? 0).compareTo(azimuth[b.id] ?? 0);
        return c != 0 ? c : naturalCompare(a.name, b.name);
      });
    for (var i = 0; i < ring.length; i++) {
      level[ring[i].id] = i.isEven ? TowerLevel.upper : TowerLevel.lower;
    }

    final out = <int, ArrangedDevice>{};
    for (final d in ordered) {
      final sp = saved[d.id];
      final s = shapes[d.id]!;
      final role = roles[d.id]!;
      final lv = level[d.id]!;
      final az = role == TowerRole.cabinet && lv == TowerLevel.base ? null : (azimuth[d.id] ?? 0);
      final beam = (keepSaved[d.id]! ? sp?.beamwidth : null) ?? TowerShapes.defaultBeam(s.shape);
      final fixed = sp?.fixed ?? false;
      out[d.id] = ArrangedDevice(
        device: d,
        shape: s.shape,
        shapeSource: s.source,
        role: role,
        level: lv,
        azimuth: az,
        beamwidth: beam,
        azimuthSource: az == null ? (fixed ? AzimuthSource.fixed : AzimuthSource.auto) : (azSource[d.id] ?? AzimuthSource.auto),
        placement: TowerPlacement(
          deviceId: d.id,
          level: lv,
          azimuth: az,
          beamwidth: beam == 0 ? null : beam,
          fixed: fixed,
          shape: sp?.shape,
        ),
      );
    }
    return out;
  }
}

/// ما يحتاج انتباه الوكيل على البرج — من قراءاتٍ حقيقيّة فقط، وبسلّم القسم الموحّد ([Grade]).
@immutable
class TowerAlert {
  const TowerAlert({
    required this.deviceId,
    required this.tone,
    required this.chip,
    required this.detail,
    this.otherId,
  });

  final int deviceId;
  final AppTone tone;

  /// نصٌّ قصير لشريط «يحتاج انتباهاً».
  final String chip;

  /// السطر الكامل في بطاقة الجهاز.
  final String detail;

  /// الجهاز الثاني في تداخل التردّد.
  final int? otherId;
}

class TowerAttention {
  TowerAttention._();

  /// مشتركون على سكترٍ واحد يُعدّ عندها مزدحماً.
  static const crowdedClients = 40;

  static List<TowerAlert> compute(
    Map<int, ArrangedDevice> arranged,
    Map<int, TowerReading> readings,
  ) {
    // المطفأ أوّلاً دائماً — جهازٌ لا يردّ أخطر من أيّ رقمٍ ضعيف.
    final down = <TowerAlert>[];
    final out = <TowerAlert>[];
    final list = arranged.values.toList();
    for (final a in list) {
      final d = a.device;
      final r = readings[d.id];
      if (d.lastStatus == 'offline') {
        down.add(TowerAlert(
          deviceId: d.id,
          tone: AppTone.danger,
          chip: '${d.name} · لا يردّ',
          detail: 'الجهاز لا يردّ${_since(d.statusSince)}',
        ));
        continue;
      }
      if (r == null) continue;
      final radio = a.role != TowerRole.cabinet && r.wireless;
      if (radio && (r.clients ?? 0) > 0 && r.quality != null) {
        final tone = Grade.percentHigherBetter(r.quality);
        if (tone == AppTone.danger || tone == AppTone.warning) {
          out.add(TowerAlert(
            deviceId: d.id,
            tone: tone,
            chip: '${d.name} · CCQ ${r.quality}٪',
            detail: tone == AppTone.danger
                ? 'جودة الاتّصال CCQ ضعيفة (${r.quality}٪) — تداخلٌ أو مشتركون بإشارةٍ ضعيفة'
                : 'جودة الاتّصال CCQ متوسّطة (${r.quality}٪)',
          ));
        }
      }
      if (a.role == TowerRole.link && r.signal != null) {
        final tone = Grade.signal(r.signal);
        if (tone == AppTone.danger || tone == AppTone.warning) {
          out.add(TowerAlert(
            deviceId: d.id,
            tone: tone,
            chip: '${d.name} · إشارة ${r.signal}',
            detail: 'إشارة اللنك ${r.signal} dBm',
          ));
        }
      }
      if ((a.role == TowerRole.sector || a.role == TowerRole.ap) && (r.clients ?? 0) >= crowdedClients) {
        out.add(TowerAlert(
          deviceId: d.id,
          tone: AppTone.warning,
          chip: '${d.name} · مزدحم ${r.clients}',
          detail: 'مزدحم: ${r.clients} مشتركاً على جهازٍ واحد',
        ));
      }
    }

    // تردّدان متداخلان على البرج نفسه — يُستثنى ما ثبّت الوكيل أنّهما متعاكسان.
    final radios = list
        .where((a) => (a.role == TowerRole.sector || a.role == TowerRole.ap) && readings[a.device.id]?.frequency != null)
        .toList();
    for (var i = 0; i < radios.length; i++) {
      for (var j = i + 1; j < radios.length; j++) {
        final a = radios[i];
        final b = radios[j];
        final ra = readings[a.device.id]!;
        final rb = readings[b.device.id]!;
        final wa = ra.channelWidth ?? 20;
        final wb = rb.channelWidth ?? 20;
        if ((ra.frequency! - rb.frequency!).abs() >= (wa + wb) / 2) continue;
        if (a.fixed && b.fixed && a.azimuth != null && b.azimuth != null && angleGap(a.azimuth!, b.azimuth!) > 120) {
          continue;
        }
        out.add(TowerAlert(
          deviceId: b.device.id,
          otherId: a.device.id,
          tone: AppTone.warning,
          chip: '${a.device.name} و${b.device.name} · تردّد متداخل',
          detail: 'تردّده ${rb.frequency} قريبٌ من ${a.device.name} (${ra.frequency}) — غيّر تردّد أحدهما',
        ));
      }
    }

    int rank(AppTone t) => t == AppTone.danger ? 0 : (t == AppTone.warning ? 1 : 2);
    final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
    indexed.sort((x, y) {
      final c = rank(x.$2.tone).compareTo(rank(y.$2.tone));
      return c != 0 ? c : x.$1.compareTo(y.$1);
    });
    return [...down, for (final e in indexed) e.$2];
  }

  static String _since(DateTime? at) {
    final s = NetworkDeviceLabels.since(at);
    return s == null ? '' : ' $s';
  }
}

/// نصوص البرج الثابتة.
class TowerText {
  TowerText._();

  static const _dirs = ['شمال', 'شمال شرق', 'شرق', 'جنوب شرق', 'جنوب', 'جنوب غرب', 'غرب', 'شمال غرب'];

  static String dir(int az) => _dirs[(normDeg(az) / 45).round() % 8];

  static String level(TowerLevel l) => switch (l) {
        TowerLevel.top => 'القمّة',
        TowerLevel.upper => 'المستوى العلوي',
        TowerLevel.mid => 'المستوى الأوسط',
        TowerLevel.lower => 'المستوى السفلي',
        TowerLevel.base => 'كابينة الأرض',
      };

  static String levelShort(TowerLevel l) => switch (l) {
        TowerLevel.top => 'القمّة',
        TowerLevel.upper => 'العلوي',
        TowerLevel.mid => 'الأوسط',
        TowerLevel.lower => 'السفلي',
        TowerLevel.base => 'الكابينة',
      };

  static String shape(TowerShape s) => switch (s) {
        TowerShape.sector => 'سكتر',
        TowerShape.dish => 'صحن لنك',
        TowerShape.panel => 'لوحة مسطّحة',
        TowerShape.omni => 'أومني',
        TowerShape.router => 'راوتر',
        TowerShape.sw => 'سويج',
        TowerShape.olt => 'أولت',
        TowerShape.other => 'جهاز آخر',
      };

  static String role(TowerRole r) => switch (r) {
        TowerRole.link => 'لنك',
        TowerRole.sector => 'سكتر',
        TowerRole.ap => 'نقطة وصول',
        TowerRole.cabinet => 'في الكابينة',
      };

  static String type(TowerType t) => switch (t) {
        TowerType.lattice => 'برج شبكي',
        TowerType.pole => 'عمود',
        TowerType.roof => 'سطح بناية',
      };

  /// «14 Mbps» · «820 Kbps» · «—».
  static String bps(int? bps) {
    if (bps == null) return '—';
    if (bps >= 1000000000) return '${(bps / 1e9).toStringAsFixed(bps >= 10e9 ? 0 : 1)} Gbps';
    if (bps >= 1000000) return '${(bps / 1e6).toStringAsFixed(bps >= 10e6 ? 0 : 1)} Mbps';
    if (bps >= 1000) return '${(bps / 1e3).round()} Kbps';
    return '$bps bps';
  }

  static String source(AzimuthSource s) => switch (s) {
        AzimuthSource.fixed => 'مثبّت',
        AzimuthSource.saved => 'تقريبيّ',
        AzimuthSource.name => 'من الاسم',
        AzimuthSource.auto => 'تقريبيّ',
      };
}
