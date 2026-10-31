import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/olt_profile.dart';
import '../../../core/util/bidi.dart';
import '../../../models/network_device.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../device_vitals.dart';
import '_grade.dart';
import 'brand_badge.dart';
import 'desk_device_kit.dart' show deskUptimeAr;
import 'device_image.dart';
import 'device_ip_link.dart';

/// «البطاقات الكبيرة» بقسم الأجهزة — بدل «النظرة العامّة» (المالك ٣١ أكتوبر: «نظرة عامه ع الاجهز نلغيها ونستبدل بدالها تغير
/// نوع العرض مثل الي بالحاسوب، نخلي عرض كارتات كبار بيها المعلومات المهمّة وملوّنة: للسكتر المعلومات الحسّاسة وعدد المتصلين
/// وتفاصيلهن بشكل مختصر، السويجات، اللنكات، الأولتي… بدقّة»).
///
/// ── ما تحمله البطاقة ───────────────────────────────────────────────
/// لونُ **دورها** (سكتر · لنك · سويتش · أولت · راوتر) في رأسها ومربّع أيقونتها — ومعه اسمه دائماً، فلا يحمل اللون المعنى وحده.
/// ثلاث خاناتٍ كبيرة بأهمّ أرقام الدور ملوّنةً بسلّم [Grade] نفسه، ثمّ قسمٌ مختصر بتفاصيل الدور (أضعف المتّصلين، أرقام الوصلة،
/// المنافذ، منافذ PON)، ثمّ سطر المرور ومدّة التشغيل وعمر القراءة.
///
/// ⚠️ كلّ رقمٍ من حمولة الجلسة نفسها ([DeviceGlance] · [DeviceDetail]) — لا جلسة إضافيّة هنا. وما لا يقرؤه الجهاز «—» لا صفر،
/// وقائمةٌ لم تُقرأ بعد («…») غير قائمةٍ فارغة («لا متّصلين الآن»).

/// دور الجهاز: لونه وأيقونته واسمه. الأولت بـ[OltProfile] (سجلّاتٌ قديمة `vsol`/`other` وطرازها يقول BDCOM…)، وغيره بنوعه.
enum DeviceRole {
  sector('sector', 'سكتر'),
  link('link', 'لنك'),
  switchRole('switch', 'سويتش'),
  olt('olt', 'أولت'),
  router('router', 'راوتر'),
  other('other', 'جهاز');

  const DeviceRole(this.key, this.label);
  final String key;
  final String label;

  IconData get icon => switch (this) {
        DeviceRole.olt => LucideIcons.cable,
        DeviceRole.other => LucideIcons.circuitBoard,
        _ => TypeIcon.iconFor(key),
      };

  /// الدور الذي تُعرض به البطاقة: المسجّل، إلّا جهاز بثٍّ يعمل AP وعليه أكثر من لاسلكيٍّ متّصل فهو سكتر أيّاً كان نوعه المسجّل
  /// (المالك ٣١ أكتوبر: «اجهزه البث الي تكون ap اكثر من وايرلس متصل بجهاز واحد مثلا مايكروتيك يوبنتي» — «سكتر 1» عنده مسجّلٌ
  /// «راوتر» فلم تظهر متّصلوه). والأولت يبقى أولتاً.
  static DeviceRole live(NetworkDevice d, DeviceDetail? detail) {
    final base = of(d);
    if (base == DeviceRole.olt || base == DeviceRole.sector) return base;
    if (detail != null && detail.glance.isAp == true && detail.peers.length >= 2) return DeviceRole.sector;
    return base;
  }

  static DeviceRole of(NetworkDevice d) {
    if (OltProfile.fromDevice(d).opensOltPanel) return DeviceRole.olt;
    return switch (d.type) {
      'sector' || 'ap' => DeviceRole.sector,
      'link' => DeviceRole.link,
      'switch' => DeviceRole.switchRole,
      'router' => DeviceRole.router,
      // سجلٌّ بلا نوعٍ مختار: سسكو سويتشٌ في كلّ ما نراه منه.
      _ => d.brand == 'cisco' ? DeviceRole.switchRole : DeviceRole.other,
    };
  }
}

/// حالة الجهاز من جولة الفحص (TCP/SNMP/ping) — شارة البطاقة. نُقلت من «النظرة العامّة» كما هي.
class DeviceLiveStatus {
  DeviceLiveStatus._();

  /// أرضيّة مطلقة: تحت هذه لا يُوصف جهاز بالبطء مهما بلغ وسيط جولته.
  /// شبكةٌ كلّها تحت ٨٠ms شبكةٌ سليمة، ولو تفاوتت أضعافاً.
  static const slowFloorMs = 80;

  /// كم ضِعفاً من الوسيط يُعدّ شذوذاً.
  static const slowFactor = 2;

  /// هل هذا الجهاز بطيءٌ **قياساً بأقرانه في الجولة نفسها**؟
  ///
  /// ⚠️ لا عتبة مطلقة. الجولة تفحص العشرات معاً، فيحمل كلّ رقم إزاحةَ ازدحامٍ مشتركة — وعتبةٌ ثابتة تُسمّي الجميع بطيئاً أو
  /// لا أحد. المقارنة بالوسيط تُسقط الإزاحة وتُبقي التمايز.
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

  static String labelFor(String status, int? ms, int? medianMs) => switch (status) {
        'offline' => 'غير متّصل',
        'unknown' => 'لم يُفحص',
        _ => ms == null ? 'حيّ' : (isSlow(ms, medianMs) ? 'بطيء · ${ms}ms' : '${ms}ms'),
      };

  /// «منذ ٤ دقائق» — من `status_since` الذي يتحرّك عند التحوّل فقط.
  static String? sinceText(DateTime? since, {DateTime? now}) => NetworkDeviceLabels.since(since, now: now);
}

/// البطاقة الكبيرة — عرضٌ خالص: الحالة تأتي من [state] (البطاقة الحيّة تملؤها، والاختبارات تبذرها).
class DeviceBigCard extends StatelessWidget {
  const DeviceBigCard({
    super.key,
    required this.device,
    required this.state,
    this.medianMs,
    this.onOpen,
    this.rows = 4,
    this.now,
  });

  final NetworkDevice device;
  final VitalsState state;
  final int? medianMs;
  final VoidCallback? onOpen;

  /// كم سطراً في قسم التفاصيل (متّصلون/منافذ/PON) قبل «و N آخرين».
  final int rows;

  /// «الآن» لعمر القراءة — للاختبار.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final role = DeviceRole.live(device, state.detail);
    final down = device.lastStatus == 'offline';
    final tone = DeviceLiveStatus.toneFor(device.lastStatus, device.lastResponseMs, medianMs);
    final radius = BorderRadius.circular(R.lg);
    return Container(
      decoration: BoxDecoration(
        color: down ? AppTone.danger.softBg : AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: down ? AppTone.danger.softBorder : AppColors.border),
        // ارتفاعٌ هادئ (ظلّ بطاقات الحاسبة) — المالك يريد البطاقة «بحدّ وظلّ» لا أرقاماً على الخلفيّة.
        boxShadow: AppColors.isDark ? Sh.deskRestDark : Sh.deskRest,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: radius,
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(device: device, role: role, tone: tone, medianMs: medianMs, down: down),
                if (down)
                  _DownLine(device: device, now: now)
                else ...[
                  _Body(device: device, role: role, state: state, rows: rows),
                  _Footer(state: state, now: now),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════ الرأس ═══════════════════════════════

class _Header extends StatelessWidget {
  const _Header({required this.device, required this.role, required this.tone, required this.medianMs, required this.down});
  final NetworkDevice device;
  final DeviceRole role;
  final AppTone tone;
  final int? medianMs;
  final bool down;

  @override
  Widget build(BuildContext context) {
    // بلا ألوان أدوار (المالك ٣١ أكتوبر: «الالوان الكارتات الغيها لان صايره نشاز») — الدور اسمٌ وأيقونة، واللون للحالة وحدها.
    return Container(
      color: down ? null : AppColors.surfaceSunken,
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
      child: Row(
        children: [
          // صورة الجهاز (بلاغ ٢٠٢٦-٠٩-٠٢: «صورة الجهاز مو معروضة») وشارة دوره بلونه في زاويتها.
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: DeviceImage(brand: device.brand, model: device.model, size: 40),
                  ),
                ),
                PositionedDirectional(
                  bottom: -4,
                  end: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: Icon(role.icon, size: 11, color: AppColors.onBrand),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: AppType.cardTitleBold(), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(role.label, style: AppType.pillBold(color: AppColors.textMid)),
                    Text(' · ', style: AppType.muted()),
                    // العنوان رابطٌ يفتح الجهاز بالمتصفّح (المالك ٣٠ أكتوبر)، والمطوّل ينسخه.
                    Flexible(child: DeviceIpLink(device.ip, style: AppType.muted())),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          _StatusPill(tone: tone, text: DeviceLiveStatus.labelFor(device.lastStatus, device.lastResponseMs, medianMs)),
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
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xxs + 1),
      decoration: BoxDecoration(
        color: tone == AppTone.neutral ? AppColors.surface : tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: tone.fill, shape: BoxShape.circle)),
          const SizedBox(width: Sp.x6),
          Text(iso(text), style: AppType.pillBold(color: tone.fill)),
        ],
      ),
    );
  }
}

/// المعطّل: سطرٌ واحد بلا خانات — لا معنى لقراءة معالجٍ لجهازٍ لا يردّ، و«آخر ظهور» أنفع. سطرٌ لا صندوق: حين تسقط منطقةٌ
/// كاملة تصير الشاشة صناديق فارغة.
class _DownLine extends StatelessWidget {
  const _DownLine({required this.device, this.now});
  final NetworkDevice device;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final since = DeviceLiveStatus.sinceText(device.statusSince, now: now);
    final fill = AppTone.danger.fill;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.md),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 13, color: fill),
          const SizedBox(width: Sp.xs),
          Expanded(
            child: Text(
              since == null ? 'لا يردّ على الفحص' : 'آخر ظهور $since',
              style: AppType.labelBold(color: fill),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════ الجسم ═══════════════════════════════

class _Body extends StatelessWidget {
  const _Body({required this.device, required this.role, required this.state, required this.rows});
  final NetworkDevice device;
  final DeviceRole role;
  final VitalsState state;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    final vitals = state.vitals;

    // لا قراءة بعد: السبب الصريح (بلا بيانات دخول، اختر SNMP…) أو «يقرأ…».
    if (vitals == null && detail == null) {
      final err = state.error;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xs),
        child: err != null
            ? _Notice(icon: err == 'بلا بيانات دخول' ? LucideIcons.keyRound : LucideIcons.info, text: _noticeText(err))
            : _Tiles(tiles: [for (final t in _pendingTiles(role)) t]),
      );
    }

    final g = detail?.glance ?? const DeviceGlance();
    final tiles = _tilesFor(role, g, detail, vitals ?? const []);
    final section = _sectionFor(role, g, detail);
    return Opacity(
      // القيم القديمة تبهت أثناء التحديث بدل أن تختفي.
      opacity: state.loading && state.at == null ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Tiles(tiles: tiles),
            if (section != null) ...[const SizedBox(height: Sp.md), section],
          ],
        ),
      ),
    );
  }

  static String _noticeText(String err) => switch (err) {
        'بلا بيانات دخول' => 'أضف بيانات الدخول من تعديل الجهاز لتظهر قراءته الحيّة',
        'لا مقاييس لهذه العلامة' => 'لا قراءة حيّة لهذا النوع — الحالة وزمن الاستجابة فقط',
        'تعذّر الاتّصال' => 'تعذّر الاتّصال بالجهاز — يعيد المحاولة تلقائيّاً',
        _ => err,
      };

  // ── الخانات الثلاث لكلّ دور ──────────────────────────────────────

  List<_TileData> _pendingTiles(DeviceRole role) => switch (role) {
        DeviceRole.sector => const [
            _TileData.pending('المتّصلون', LucideIcons.users),
            _TileData.pending('متوسّط الإشارة', LucideIcons.signal),
            _TileData.pending('أضعف إشارة', LucideIcons.signalLow),
          ],
        DeviceRole.link => const [
            _TileData.pending('الإشارة', LucideIcons.signal),
            _TileData.pending('الجودة', LucideIcons.activity),
            _TileData.pending('سرعة الربط', LucideIcons.gauge),
          ],
        DeviceRole.switchRole => const [
            _TileData.pending('المنافذ', LucideIcons.network),
            _TileData.pending('الأعلى حِملاً', LucideIcons.arrowDownUp),
            _TileData.pending('المعالج', LucideIcons.cpu),
          ],
        DeviceRole.olt => const [
            _TileData.pending('المشتركون', LucideIcons.users),
            _TileData.pending('منافذ PON', LucideIcons.splitSquareVertical),
            _TileData.pending('المعالج', LucideIcons.cpu),
          ],
        _ => const [
            _TileData.pending('المعالج', LucideIcons.cpu),
            _TileData.pending('الذاكرة', LucideIcons.memoryStick),
            _TileData.pending('الحرارة', LucideIcons.thermometer),
          ],
      };

  List<_TileData> _tilesFor(DeviceRole role, DeviceGlance g, DeviceDetail? detail, List<Vital> vitals) {
    final peers = detail?.peers ?? const <PeerLink>[];
    switch (role) {
      case DeviceRole.sector:
        // سكتر يعمل محطّةً (أو بلا جدول عملاء): أرقام وصلته هو.
        if (g.isAp == false || (!g.peersKnown && peers.isEmpty && g.signal != null)) return _linkTiles(g, peers);
        final sig = [for (final p in peers) if (p.signal != null && p.signal != 0) p.signal!];
        final avg = sig.isEmpty ? null : (sig.reduce((a, b) => a + b) / sig.length).round();
        final worst = sig.isEmpty ? null : sig.reduce((a, b) => a < b ? a : b);
        final known = g.peersKnown || peers.isNotEmpty;
        return [
          known
              ? _TileData('المتّصلون', LucideIcons.users, '${peers.length}', null,
                  peers.isEmpty ? AppTone.warning : AppTone.brand)
              : const _TileData.pending('المتّصلون', LucideIcons.users),
          avg == null
              ? _TileData.empty('متوسّط الإشارة', LucideIcons.signal, measuring: !known)
              : _TileData('متوسّط الإشارة', LucideIcons.signal, '$avg', 'dBm', Grade.signal(avg)),
          worst == null
              ? _TileData.empty('أضعف إشارة', LucideIcons.signalLow, measuring: !known)
              : _TileData('أضعف إشارة', LucideIcons.signalLow, '$worst', 'dBm', Grade.signal(worst)),
        ];
      case DeviceRole.link:
        return _linkTiles(g, peers);
      case DeviceRole.switchRole:
        final ports = _wired(detail?.ports);
        final up = ports.where((p) => p.up).length;
        final busiest = _busiest(ports);
        return [
          ports.isEmpty
              ? const _TileData.empty('المنافذ', LucideIcons.network)
              : _TileData('المنافذ', LucideIcons.network, '$up', '/${ports.length}', AppTone.brand),
          busiest == null
              ? _TileData.empty('الأعلى حِملاً', LucideIcons.arrowDownUp, measuring: ports.any((p) => p.up))
              : _TileData('الأعلى حِملاً', LucideIcons.arrowDownUp, _bpsValue(busiest.total), _bpsUnit(busiest.total),
                  AppTone.info, foot: busiest.port.name),
          _thirdTile(g, vitals),
        ];
      case DeviceRole.olt:
        // خانات الأولت هي خانات بطاقته في كلّ القسم (oltProbeResult) — لا حسابٌ ثانٍ يختلف.
        return [for (final v in vitals) _TileData.fromVital(v)];
      case DeviceRole.router:
      case DeviceRole.other:
        return [for (final v in vitals) _TileData.fromVital(v)];
    }
  }

  List<_TileData> _linkTiles(DeviceGlance g, List<PeerLink> peers) {
    // الطرف الآخر وحده في جدول المحطّة — إشارته وجودته هي الوصلة (ميكروتك محطّةً تُعيدها في glance نفسها).
    final peer = peers.length == 1 ? peers.first : null;
    final signal = g.signal ?? peer?.signal;
    final ccq = g.ccq ?? peer?.ccq;
    int? pos(int? v) => v != null && v > 0 ? v : null;
    final rx = pos(g.rxRateMbps ?? peer?.rxRate);
    final tx = pos(g.txRateMbps ?? peer?.txRate);
    // رقمٌ واحد كبير: الاستقبال إن عُرف وإلّا الإرسال، والآخر تحته حين يُعرف الاثنان (لا نسخه).
    final rate = rx ?? tx;
    final _TileData quality;
    if (ccq != null && ccq > 0) {
      quality = _TileData('الجودة CCQ', LucideIcons.activity, '$ccq', '%', Grade.percentHigherBetter(ccq));
    } else if (g.snr != null) {
      quality = _TileData('SNR', LucideIcons.activity, '${g.snr}', 'dB', Grade.snr(g.snr));
    } else if (g.signalPct != null) {
      quality = _TileData('جودة الإشارة', LucideIcons.activity, '${g.signalPct}', '%', Grade.percentHigherBetter(g.signalPct));
    } else {
      quality = const _TileData.empty('الجودة', LucideIcons.activity);
    }
    return [
      signal == null || signal == 0
          ? const _TileData.empty('الإشارة', LucideIcons.signal)
          : _TileData('الإشارة', LucideIcons.signal, '$signal', 'dBm', Grade.signal(signal)),
      quality,
      rate == null
          ? const _TileData.empty('سرعة الربط', LucideIcons.gauge)
          : _TileData('سرعة الربط', LucideIcons.gauge, '$rate', 'Mbps', Grade.speedMbps(rate),
              foot: (rx != null && tx != null) ? 'إرسال $tx' : null),
    ];
  }

  /// الخانة الثالثة للسويتش: استهلاك PoE حين يقرؤه (netPower)، وإلّا الحرارة، وإلّا المعالج.
  _TileData _thirdTile(DeviceGlance g, List<Vital> vitals) {
    if (g.poeWatts != null) {
      return _TileData('استهلاك PoE', LucideIcons.plug, g.poeWatts!.toStringAsFixed(1), 'W', AppTone.info);
    }
    if (g.temp != null) return _TileData('الحرارة', LucideIcons.thermometer, '${g.temp}', '°', Grade.temperature(g.temp));
    if (g.cpu != null) return _TileData('المعالج', LucideIcons.cpu, '${g.cpu}', '%', Grade.percentLowerBetter(g.cpu));
    return vitals.isNotEmpty ? _TileData.fromVital(vitals.first) : const _TileData.empty('المعالج', LucideIcons.cpu);
  }

  // ── قسم التفاصيل لكلّ دور ────────────────────────────────────────

  Widget? _sectionFor(DeviceRole role, DeviceGlance g, DeviceDetail? detail) {
    final peers = detail?.peers ?? const <PeerLink>[];
    final ports = _wired(detail?.ports);
    switch (role) {
      case DeviceRole.sector:
        if (g.isAp == false) return _LinkFacts(g: g, peers: peers);
        if (!g.peersKnown && peers.isEmpty) return null;
        return _PeersSection(peers: peers, rows: rows, label: detail?.peersLabel ?? 'المتّصلون');
      case DeviceRole.link:
        return _LinkFacts(g: g, peers: peers);
      case DeviceRole.switchRole:
        if (ports.isEmpty) return null;
        return _PortsSection(ports: ports, rows: rows, map: true);
      case DeviceRole.olt:
        if (g.pons.isEmpty) return null;
        return _PonSection(g: g, rows: rows);
      case DeviceRole.router:
      case DeviceRole.other:
        final facts = <_Fact>[
          if (g.ppp != null) _Fact('جلسات PPP', '${g.ppp}', LucideIcons.users),
          if (g.voltage != null) _Fact('الفولتيّة', '${g.voltage!.toStringAsFixed(1)} V', LucideIcons.zap, Grade.voltage(g.voltage)),
          if (g.poeWatts != null) _Fact('PoE', '${g.poeWatts!.toStringAsFixed(1)} W', LucideIcons.plug),
        ];
        final hasPorts = ports.any((p) => p.up);
        if (facts.isEmpty && !hasPorts && peers.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (facts.isNotEmpty) _FactsWrap(facts: facts),
            if (facts.isNotEmpty && hasPorts) const SizedBox(height: Sp.sm),
            if (hasPorts) _PortsSection(ports: ports, rows: rows > 3 ? 3 : rows, map: false),
            if (!hasPorts && peers.isNotEmpty) _PeersSection(peers: peers, rows: rows > 3 ? 3 : rows, label: detail!.peersLabel),
          ],
        );
    }
  }
}

/// منافذ الإيثرنت الفعليّة وحدها (لا جلسات PPP ولا أنفاق ولا جسر ولا VLAN ولا لاسلكيّ — «سيرفر التوزيع» عرض ١٤٣ منفذاً
/// أغلبها pppoe-in). جهازٌ لا يُعرف نوع واجهاته (كلّها غير معلَّمة) يبقى بها كلّها.
List<PortTraffic> _wired(List<PortTraffic>? ports) {
  final all = ports ?? const <PortTraffic>[];
  final wired = [for (final p in all) if (p.physical) p];
  return wired.isEmpty ? all : wired;
}

/// أعلى منفذٍ حِملاً بمعدّلٍ معروف (لا مجموع المنافذ: الجسر والإيثر واللاسلكيّ تحمل المرور نفسه فيُعدّ مرّتين).
({PortTraffic port, int total})? _busiest(List<PortTraffic> ports) {
  ({PortTraffic port, int total})? best;
  for (final p in ports) {
    if (p.rxBps == null && p.txBps == null) continue;
    final t = (p.rxBps ?? 0) + (p.txBps ?? 0);
    if (best == null || t > best.total) best = (port: p, total: t);
  }
  return best;
}

String _bpsValue(int bps) {
  if (bps < 1000000) return (bps / 1000).toStringAsFixed(0);
  if (bps < 1000000000) return (bps / 1000000).toStringAsFixed(bps < 100000000 ? 1 : 0);
  return (bps / 1000000000).toStringAsFixed(2);
}

String _bpsUnit(int bps) => bps < 1000000 ? 'Kbps' : (bps < 1000000000 ? 'Mbps' : 'Gbps');

String _bpsShort(int? bps) => bps == null ? '—' : '${_bpsValue(bps)} ${_bpsUnit(bps)}';

// ═══════════════════════════════ الخانات ═══════════════════════════════

@immutable
class _TileData {
  const _TileData(this.label, this.icon, this.value, this.unit, this.tone, {this.foot});
  const _TileData.pending(this.label, this.icon)
      : value = '…',
        unit = null,
        tone = AppTone.neutral,
        foot = null;
  const _TileData.empty(this.label, this.icon, {bool measuring = false})
      : value = measuring ? '…' : '—',
        unit = null,
        tone = AppTone.neutral,
        foot = null;

  factory _TileData.fromVital(Vital v) => _TileData(v.label, v.icon, v.value, v.unit == '٪' ? '%' : v.unit, v.tone);

  final String label;
  final IconData icon;
  final String value;
  final String? unit;
  final AppTone tone;
  final String? foot;
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});
  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: Sp.sm),
            Expanded(child: _Tile(tiles[i])),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.t);
  final _TileData t;

  @override
  Widget build(BuildContext context) {
    final neutral = t.tone == AppTone.neutral;
    final fg = neutral ? AppColors.textHi : t.tone.fill;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, Sp.sm),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surfaceSunken : t.tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: neutral ? AppColors.border : t.tone.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(t.icon, size: 13, color: neutral ? AppColors.textMid : t.tone.fill),
            const SizedBox(width: Sp.xs),
            Expanded(
              child: Text(t.label, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: Sp.x6),
          // ⚠️ اتّجاهٌ صريح: الرقم ووحدته وحدةٌ لاتينيّة داخل صفحةٍ عربيّة — بلا هذا يظهر «٪ ٣٤» بدل «٣٤٪».
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: t.value, style: AppType.daysNumber(color: fg)),
                    if (t.unit != null) TextSpan(text: ' ${t.unit}', style: AppType.microBold(color: fg)),
                  ]),
                  maxLines: 1,
                ),
              ),
            ),
          ),
          if (t.foot != null) ...[
            const SizedBox(height: 2),
            Text(iso(t.foot!), style: AppType.daysWord(color: AppColors.textLow), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════ الأقسام ═══════════════════════════════

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.x6),
      child: Row(children: [
        Expanded(
          child: Text(text, style: AppType.labelBold(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (trailing != null) Text(iso(trailing!), style: AppType.micro(color: AppColors.textLow)),
      ]),
    );
  }
}

/// المتّصلون — **الأضعف أوّلاً**، باختصار: الاسم وإشارته، خليّتان بالسطر (المالك ٣١ أكتوبر: «جالب بي المتصلين اسمائهم واشارته
/// وبشكل مختصر»). من يراقب سكتراً يريد من يوشك أن ينقطع، لا من إشارته ممتازة.
class _PeersSection extends StatelessWidget {
  const _PeersSection({required this.peers, required this.rows, required this.label});
  final List<PeerLink> peers;

  /// أسطر الخلايا (خليّتان بالسطر).
  final int rows;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const _Notice(icon: LucideIcons.userX, text: 'لا متّصلين الآن');
    }
    final sorted = [...peers]..sort((a, b) => (a.signal ?? 0).compareTo(b.signal ?? 0));
    final shown = sorted.take(rows * 2).toList();
    final more = peers.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionTitle('$label · الأضعف أوّلاً', trailing: '${peers.length}'),
        for (var i = 0; i < shown.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.x6),
            child: Row(
              children: [
                Expanded(child: _PeerCell(shown[i])),
                const SizedBox(width: Sp.x6),
                Expanded(child: i + 1 < shown.length ? _PeerCell(shown[i + 1]) : const SizedBox.shrink()),
              ],
            ),
          ),
        if (more > 0) _MoreLine(more == 1 ? 'وواحدٌ آخر' : 'و$more آخرون'),
      ],
    );
  }
}

/// خليّة متّصل: اسمه (الأطول يُقصّ) وإشارته بلون سلّمها.
class _PeerCell extends StatelessWidget {
  const _PeerCell(this.p);
  final PeerLink p;

  @override
  Widget build(BuildContext context) {
    final known = p.signal != null && p.signal != 0;
    final tone = Grade.signal(p.signal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(iso(p.name), style: AppType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Sp.x6),
          Text(iso(known ? '${p.signal}' : '—'), style: AppType.bodyBold(color: known ? tone.fill : AppColors.textMid)),
        ],
      ),
    );
  }
}

/// أرقام الوصلة كما يراها الجهاز — كلّ رقمٍ في رقاقةٍ باسمه، وما لا يقرؤه لا يظهر (لا «—» مكدّسة).
class _LinkFacts extends StatelessWidget {
  const _LinkFacts({required this.g, required this.peers});
  final DeviceGlance g;
  final List<PeerLink> peers;

  @override
  Widget build(BuildContext context) {
    final peer = peers.length == 1 ? peers.first : null;
    final facts = <_Fact>[
      if (g.snr != null && !(g.ccq == null && (peer?.ccq ?? 0) <= 0)) _Fact('SNR', '${g.snr} dB', LucideIcons.activity, Grade.snr(g.snr)),
      if (g.noise != null) _Fact('الضجيج', '${g.noise} dBm', LucideIcons.audioWaveform),
      if (g.freqMhz != null) _Fact('التردّد', '${g.freqMhz} MHz', LucideIcons.radio),
      if (g.widthMhz != null) _Fact('عرض القناة', '${g.widthMhz} MHz', LucideIcons.moveHorizontal),
      if (g.distanceM != null) _Fact('المسافة', _distance(g.distanceM!), LucideIcons.ruler),
      if (peer != null) _Fact('الطرف الآخر', peer.name, LucideIcons.link2),
      if (g.ssid != null) _Fact('الشبكة', g.ssid!, LucideIcons.wifi),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return _FactsWrap(facts: facts);
  }

  static String _distance(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} كم' : '$m م';
}

@immutable
class _Fact {
  const _Fact(this.label, this.value, this.icon, [this.tone]);
  final String label;
  final String value;
  final IconData icon;
  final AppTone? tone;
}

class _FactsWrap extends StatelessWidget {
  const _FactsWrap({required this.facts});
  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        for (final f in facts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
            decoration: BoxDecoration(
              color: f.tone?.softBg ?? AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: f.tone?.softBorder ?? AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(f.icon, size: 12, color: f.tone?.fill ?? AppColors.textMid),
                const SizedBox(width: Sp.xs),
                Text('${f.label} ', style: AppType.micro(color: AppColors.textMid)),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(iso(f.value),
                      style: AppType.microBold(color: f.tone?.fill ?? AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// المنافذ: خريطةٌ بمربّعٍ لكلّ منفذ (متّصل/مطفأ) ثمّ الأعلى حِملاً بمعدّليه.
class _PortsSection extends StatelessWidget {
  const _PortsSection({required this.ports, required this.rows, required this.map});
  final List<PortTraffic> ports;
  final int rows;
  final bool map;

  @override
  Widget build(BuildContext context) {
    final up = ports.where((p) => p.up).length;
    final busy = [for (final p in ports) if (p.up && (p.rxBps != null || p.txBps != null)) p]
      ..sort((a, b) => ((b.rxBps ?? 0) + (b.txBps ?? 0)).compareTo((a.rxBps ?? 0) + (a.txBps ?? 0)));
    final shown = busy.take(rows).toList();
    final measuring = busy.isEmpty && up > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (map) ...[
          _SectionTitle('المنافذ', trailing: '$up متّصل من ${ports.length}'),
          Wrap(
            spacing: 3,
            runSpacing: 3,
            children: [
              for (final p in ports)
                Tooltip(
                  message: p.name,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: p.up ? AppTone.success.fill : AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(R.check / 2),
                      border: Border.all(color: p.up ? AppTone.success.fill : AppColors.borderStrong),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Sp.sm),
        ],
        _SectionTitle(map ? 'الأعلى حِملاً' : 'المنافذ الأعلى حِملاً'),
        if (measuring)
          Text('يُحسب المعدّل…', style: AppType.micro(color: AppColors.textLow))
        else if (shown.isEmpty)
          Text('لا منفذ متّصل', style: AppType.micro(color: AppColors.textLow))
        else
          for (final p in shown) _PortRow(p),
      ],
    );
  }
}

class _PortRow extends StatelessWidget {
  const _PortRow(this.p);
  final PortTraffic p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(iso(p.name), style: AppType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (p.linkSpeed != null) ...[
            _ValuePill(text: p.linkSpeed!, tone: Grade.linkSpeedText(p.linkSpeed!)),
            const SizedBox(width: Sp.sm),
          ],
          Text(iso('↓ ${_bpsShort(p.rxBps)}'), style: AppType.micro(color: AppColors.chartLine)),
          const SizedBox(width: Sp.sm),
          Text(iso('↑ ${_bpsShort(p.txBps)}'), style: AppType.micro(color: AppColors.info)),
        ],
      ),
    );
  }
}

/// منافذ PON: كلّ منفذٍ بشريط نسبة متّصليه من مشتركيه — الأقلّ نسبةً أوّلاً (العطل يظهر قبل السليم)، والمطفأ أحمر.
class _PonSection extends StatelessWidget {
  const _PonSection({required this.g, required this.rows});
  final DeviceGlance g;
  final int rows;

  @override
  Widget build(BuildContext context) {
    double pct(PonGlance p) => p.total == 0 ? 1 : p.online / p.total;
    final sorted = [...g.pons]
      ..sort((a, b) {
        if (a.up != b.up) return a.up ? 1 : -1;
        return pct(a).compareTo(pct(b));
      });
    final used = sorted.where((p) => p.total > 0 || !p.up).toList();
    final list = used.isEmpty ? sorted : used;
    final shown = list.take(rows).toList();
    final more = list.length - shown.length;
    final offline = (g.onusTotal ?? 0) - (g.onusOnline ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionTitle(
          'منافذ PON · الأضعف أوّلاً',
          trailing: [
            if (offline > 0) '$offline غير متّصل',
            if (g.uplinksTotal != null && g.uplinksTotal! > 0) 'الربط ${g.uplinksUp}/${g.uplinksTotal}',
          ].join(' · '),
        ),
        for (final p in shown) _PonRow(p),
        if (more > 0) _MoreLine('و$more منافذ أخرى'),
      ],
    );
  }
}

class _PonRow extends StatelessWidget {
  const _PonRow(this.p);
  final PonGlance p;

  @override
  Widget build(BuildContext context) {
    final ratio = p.total == 0 ? 0.0 : p.online / p.total;
    final tone = !p.up ? AppTone.danger : (p.total == 0 ? AppTone.neutral : Grade.percentHigherBetter(ratio * 100));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(iso(p.label), style: AppType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: Container(
                height: 8,
                color: AppColors.surfaceSunken,
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: p.up ? ratio.clamp(0.0, 1.0) : 1,
                  child: Container(color: p.up ? tone.fill : AppTone.danger.softBorder),
                ),
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          SizedBox(
            width: 64,
            child: Text(
              p.up ? iso('${p.online}/${p.total}') : 'مطفأ',
              style: AppType.microBold(color: p.up ? tone.fill : AppTone.danger.fill),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text, required this.tone});
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final neutral = tone == AppTone.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 1),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surfaceSunken : tone.softBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: neutral ? AppColors.border : tone.softBorder),
      ),
      child: Text(iso(text), style: AppType.microBold(color: neutral ? AppColors.textMid : tone.fill)),
    );
  }
}

class _MoreLine extends StatelessWidget {
  const _MoreLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: AppType.micro(color: AppColors.textLow)),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: AppColors.textMid),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text(text, style: AppType.body(color: AppColors.textMid))),
      ]),
    );
  }
}

// ═══════════════════════════════ التذييل ═══════════════════════════════

/// المرور الآن (أعلى منفذ) · مدّة التشغيل · عمر القراءة — سطرٌ واحد.
class _Footer extends StatelessWidget {
  const _Footer({required this.state, this.now});
  final VitalsState state;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    if (state.vitals == null && detail == null) {
      // بلا قراءة: لا عمر يُعرض («الآن» فوق سببٍ صريح يكذب)، و«يقرأ…» ما دامت الأولى جارية.
      if (!state.loading) return const SizedBox(height: Sp.md);
      return Padding(
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
        child: Row(children: [
          SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textLow)),
          const SizedBox(width: Sp.x6),
          Text('يقرأ الجهاز…', style: AppType.micro(color: AppColors.textLow)),
        ]),
      );
    }
    final g = detail?.glance ?? const DeviceGlance();
    final busiest = _busiest(_wired(detail?.ports));
    final up = g.uptimeSec;
    final age = state.at == null ? null : (now ?? DateTime.now()).difference(state.at!);
    final stale = age != null && age > const Duration(seconds: 60);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.md),
      child: Row(
        children: [
          if (busiest != null) ...[
            Icon(LucideIcons.arrowDown, size: 12, color: AppColors.chartLine),
            Text(iso(_bpsShort(busiest.port.rxBps)), style: AppType.microBold(color: AppColors.chartLine)),
            const SizedBox(width: Sp.x6),
            Icon(LucideIcons.arrowUp, size: 12, color: AppColors.info),
            Text(iso(_bpsShort(busiest.port.txBps)), style: AppType.microBold(color: AppColors.info)),
            const SizedBox(width: Sp.sm),
          ],
          if (up != null && up > 0)
            Expanded(
              child: Text(
                '${g.linkUptime ? 'الوصلة منذ' : 'يعمل منذ'} ${deskUptimeAr(Duration(seconds: up))}',
                style: AppType.micro(color: AppColors.textLow),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (state.loading)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textLow),
            )
          else if (state.error != null && state.vitals != null)
            Text('تعذّر التحديث', style: AppType.micro(color: AppTone.warning.fill))
          else if (age != null)
            Text(_ageText(age), style: AppType.micro(color: stale ? AppTone.warning.fill : AppColors.textLow)),
        ],
      ),
    );
  }

  static String _ageText(Duration a) {
    if (a.inSeconds < 5) return 'الآن';
    if (a.inSeconds < 60) return 'قبل ${a.inSeconds} ث';
    if (a.inMinutes < 60) return 'قبل ${a.inMinutes} د';
    return 'قبل ${a.inHours} س';
  }
}
