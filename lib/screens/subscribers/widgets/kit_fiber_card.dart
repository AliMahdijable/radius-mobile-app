import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/api_client.dart';
import '../../../core/util/bidi.dart';
import '../../../models/subscriber.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/permissions_service.dart';
import '../../../services/provider_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../network_devices/fiber/fiber_widgets.dart';

/// قراءة «الليف والموقع» من الخادم (GET /api/v2/subscribers/:idx/fiber) — الحقول كما يرسلها محوّل الشركة.
class KitFiberInfo {
  const KitFiberInfo({
    this.rx,
    this.ontStatus,
    this.down = false,
    this.ontError,
    this.opticsAt,
    this.serial,
    this.fdt,
    this.fat,
    this.fatPort,
    this.lat,
    this.lng,
    this.address,
    this.nearest,
    this.zone,
  });

  /// قدرة الضوء المستلمة (dBm) — null بلا قياس (لا 0).
  final double? rx;
  final String? ontStatus;

  /// لا ضوء (الـONT مفصول) — يُقال صراحةً بدل رقمٍ كاذب.
  final bool down;

  /// busy | forbidden | failed — تعذّرت قراءة الضوء وحدها.
  final String? ontError;
  final String? opticsAt;
  final String? serial;
  final String? fdt;
  final String? fat;
  final int? fatPort;
  final double? lat;
  final double? lng;
  final String? address;
  final String? nearest;
  final String? zone;

  static String? _str(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  factory KitFiberInfo.fromJson(Map<dynamic, dynamic> m) {
    final loc = m['location'] is Map ? m['location'] as Map : const {};
    return KitFiberInfo(
      rx: _num(m['rxDbm']),
      ontStatus: _str(m['ontStatus']),
      down: m['ontDown'] == true,
      ontError: _str(m['ontError']),
      opticsAt: _str(m['opticsAt']),
      serial: _str(m['serial']),
      fdt: _str(m['fdt']),
      fat: _str(m['fat']),
      fatPort: _num(m['fatPort'])?.round(),
      lat: _num(loc['lat']),
      lng: _num(loc['lng']),
      address: _str(loc['text']),
      nearest: _str(loc['nearestPoint']),
      zone: _str(loc['zone']),
    );
  }

  /// المسار كما في الموقع: FDT ← FAT (منفذ N).
  String get path => [
        if (fdt != null) fdt!,
        if (fat != null) fatPort != null ? '$fat (منفذ $fatPort)' : fat!,
      ].join(' ← ');

  String get place => [if (address != null) address!, if (nearest != null) 'قرب $nearest'].join(' — ');

  bool get hasMap => lat != null && lng != null;
}

/// «الليف والموقع» بصفحة مشترك الشركة المُضافة التي يقرأ خادمها ضوء الـONT وعنوان الزبون (المشروع الوطنيّ، ٣١ أكتوبر — المالك:
/// «الباور والموقع مال مشترك مايظهر»). مطويٌّ كـ«جهاز الألياف»: العنوان يحمل الضوء بقيمته ولونه (أو «لا ضوء»)، والنقر يفتح المسار
/// والجهاز والعنوان وزرّ الخريطة. مزوّدٌ لا يقرؤها (409) أو بلا بيانات ⇒ لا كرت.
class KitFiberCard extends StatefulWidget {
  const KitFiberCard({super.key, required this.sub});

  final Subscriber sub;

  /// للاختبار: جلب القراءة.
  @visibleForTesting
  static Future<KitFiberInfo?> Function(String idx) fetch = _fetch;

  /// للاختبار: فتح الخريطة.
  @visibleForTesting
  static Future<bool> Function(Uri uri) openMap = _openMap;

  static Future<KitFiberInfo?> _fetch(String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/subscribers/${Uri.encodeComponent(idx)}/fiber');
      final b = r.data ?? const {};
      if (b['success'] != true || b['data'] is! Map) return null;
      return KitFiberInfo.fromJson(b['data'] as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _openMap(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @visibleForTesting
  static void debugReset() {
    fetch = _fetch;
    openMap = _openMap;
  }

  /// يظهر لشركةٍ مُضافة خارج «كل الشركات»: لصاحب الحساب بقدرة شركته (`subscribers.fiber_info` من الخادم)، ولموظّفنا بعرض المشتركين
  /// (والكرت يختفي إن قالت الشركة إنّها لا تقرؤها).
  static bool shownFor(Subscriber sub) =>
      ProviderService.isKit &&
      sub.companyKey == null &&
      (sub.idx ?? '').isNotEmpty &&
      (Perms.isEmployee ? Perms.has('subscribers.view') : Perms.has('subscribers.fiber_info'));

  @override
  State<KitFiberCard> createState() => _KitFiberCardState();
}

class _KitFiberCardState extends State<KitFiberCard> {
  KitFiberInfo? _info;
  bool _loading = true;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final idx = widget.sub.idx;
    final info = idx == null ? null : await KitFiberCard.fetch(idx);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  Future<void> _map(KitFiberInfo d) async {
    final ok = await KitFiberCard.openMap(Uri.parse('https://www.google.com/maps?q=${d.lat},${d.lng}'));
    if (!ok && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('تعذّر فتح الخريطة')));
    }
  }

  Widget _row(IconData icon, String label, String value, {bool ltr = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: AppColors.textLow),
        const SizedBox(width: Sp.sm),
        Text(label, style: AppType.muted(color: AppColors.textMid), maxLines: 1),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(
            ltr ? iso(value) : value,
            style: AppType.rowValue(),
            textAlign: TextAlign.end,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _info;
    if (!_loading && d == null) return const SizedBox.shrink();
    final rx = d?.rx;
    final band = FiberBands.of(rx);
    final Widget pill = _loading
        ? const FiberPill('يقرأ…', tone: AppTone.neutral)
        : rx != null
            ? FiberPill('${iso('${rx.toStringAsFixed(1)} dBm')}${band != null ? ' · ${FiberBands.label(band)}' : ''}',
                tone: FiberBands.tone(rx))
            : d!.down
                ? const FiberPill('لا ضوء — مفصول', tone: AppTone.danger)
                : FiberPill(d.ontError == 'busy' ? 'البوّابة مشغولة' : 'لا قياس', tone: AppTone.neutral);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.card),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: d == null ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Row(children: [
                Icon(LucideIcons.cable, size: 18, color: AppColors.brandAccent),
                const SizedBox(width: Sp.sm),
                Expanded(child: Text('الليف والموقع', style: AppType.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Flexible(child: pill),
                const SizedBox(width: Sp.xs),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(LucideIcons.chevronDown, size: 18, color: AppColors.textLow),
                ),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: !_open || d == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (d.down) _row(LucideIcons.signal, 'الإشارة', 'لا ضوء — الجهاز مفصول'),
                      if (d.path.isNotEmpty) _row(LucideIcons.cable, 'المسار', d.path, ltr: true),
                      if (d.serial != null) _row(LucideIcons.cpu, 'جهاز الـONT', d.serial!, ltr: true),
                      if (d.zone != null) _row(LucideIcons.mapPin, 'المنطقة', d.zone!),
                      if (d.place.isNotEmpty) _row(LucideIcons.mapPin, 'العنوان', d.place),
                      if (rx != null && d.opticsAt != null) _row(LucideIcons.clock, 'وقت القياس', d.opticsAt!, ltr: true),
                      if (d.hasMap) ...[
                        const SizedBox(height: Sp.md),
                        OutlinedButton.icon(
                          onPressed: () => _map(d),
                          icon: const Icon(LucideIcons.navigation, size: 16),
                          label: const Text('افتح الموقع على الخريطة'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                        ),
                      ],
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }
}
