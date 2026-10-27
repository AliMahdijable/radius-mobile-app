import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/network_devices_api.dart';
import '../../../core/util/bidi.dart';
import '../../../models/fiber_network.dart';
import '../../../models/network_device.dart';
import '../../../models/subscriber.dart';
import '../../../services/fiber/fiber_band.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'fiber_diagnosis_screen.dart';
import 'fiber_widgets.dart';

/// «جهاز الألياف» بصفحة المشترك المربوط: جهازه على الأولت وصندوقه، وحالته وضوؤه الآن، وزرّ التشخيص. غير المربوط بلا كرت.
///
/// يقرأ الأولت ما دام الكرت ظاهراً (مراقبٌ مشترك مع شاشات الألياف — لا مسحٌ ثانٍ إن كانت مفتوحة)؛ بلا صلاحيّة مراقبة
/// الأجهزة يبقى الكرت بقفله.
class FiberSubscriberCard extends StatefulWidget {
  const FiberSubscriberCard({super.key, required this.sub});

  final Subscriber sub;

  /// للاختبار: قائمة الأجهزة.
  @visibleForTesting
  static Future<List<NetworkDevice>> Function() devices = NetworkDevicesApi.list;

  static List<NetworkDevice>? _cache;
  static DateTime? _cacheAt;

  static Future<NetworkDevice?> _device(int id) async {
    final live = FiberMonitor.existing(id)?.device;
    if (live != null) return live;
    if (_cache == null || _cacheAt == null || DateTime.now().difference(_cacheAt!) > const Duration(minutes: 5)) {
      try {
        _cache = await devices();
        _cacheAt = DateTime.now();
      } catch (_) {
        return null;
      }
    }
    return _cache!.where((d) => d.id == id).firstOrNull;
  }

  @visibleForTesting
  static void debugReset() {
    _cache = null;
    _cacheAt = null;
    devices = NetworkDevicesApi.list;
  }

  @override
  State<FiberSubscriberCard> createState() => _FiberSubscriberCardState();
}

class _FiberSubscriberCardState extends State<FiberSubscriberCard> {
  FiberOnuRecord? _rec;
  FiberMonitor? _m;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    FiberStore.layout.addListener(_layoutChanged);
    unawaited(_init());
  }

  @override
  void dispose() {
    FiberStore.layout.removeListener(_layoutChanged);
    _detach();
    super.dispose();
  }

  FiberOnuRecord? _find() {
    final u = widget.sub.username.toLowerCase();
    for (final r in FiberStore.layout.value.onus.values) {
      if (r.username?.toLowerCase() == u) return r;
    }
    return null;
  }

  Future<void> _init() async {
    try {
      await FiberStore.ensureLoaded();
    } catch (_) {
      return; // بلا شبكة ألياف محفوظة لا كرت
    }
    if (!mounted) return;
    await _attach(_find());
  }

  void _layoutChanged() {
    final r = _find();
    if (r?.oltId != _rec?.oltId || r?.key != _rec?.key) {
      unawaited(_attach(r));
    } else if (mounted) {
      setState(() => _rec = r);
    }
  }

  Future<void> _attach(FiberOnuRecord? r) async {
    if (r?.oltId != _rec?.oltId) _detach();
    _rec = r;
    if (r != null && _m == null && Perms.has('devices.monitor')) {
      final d = await FiberSubscriberCard._device(r.oltId);
      if (!mounted || _rec?.oltId != r.oltId) return;
      if (d != null) {
        _m = FiberMonitor.of(d)
          ..addListener(_changed)
          ..acquire();
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  void _detach() {
    _m
      ?..removeListener(_changed)
      ..release();
    _m = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rec = _rec;
    if (!_ready || rec == null) return const SizedBox.shrink();
    final locked = !Perms.has('devices.monitor');
    final m = _m;
    final layout = FiberStore.layout.value;
    final box = rec.boxId == null ? null : layout.boxes[rec.boxId];
    final live = m?.onus.where((o) => o.key == rec.key || (rec.ident != null && o.ident == rec.ident)).firstOrNull;
    final (String pill, AppTone tone) = locked
        ? ('لا صلاحيّة', AppTone.neutral)
        : m == null
            ? ('الأولت غير موجود', AppTone.neutral)
            : live == null
                ? (m.error != null ? 'ما نوصل للأولت' : 'يقرأ…', m.error != null ? AppTone.warning : AppTone.neutral)
                : live.online
                    ? ('متّصل', AppTone.success)
                    : (live.reason == null ? 'مفصول' : 'مفصول · ${fiberReasonLabel(live.reason!)}',
                        live.reason == FiberDropReason.power ? AppTone.warning : AppTone.danger);
    final where = [
      live?.display ?? fiberOnuKeyDisplay(rec.key),
      if (box != null) box.name,
      if (m != null) m.device.name,
    ].join(' · ');
    final rx = live?.rx;
    final band = FiberBands.of(rx);
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Container(
        padding: const EdgeInsets.all(Sp.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(locked ? LucideIcons.lock : LucideIcons.cable, size: 18, color: locked ? AppColors.textLow : AppColors.brandAccent),
            const SizedBox(width: Sp.sm),
            Expanded(child: Text('جهاز الألياف', style: AppType.cardTitle())),
            FiberPill(pill, tone: tone, dot: !locked && live != null),
          ]),
          const SizedBox(height: 10),
          Text(iso(where), style: AppType.body(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (rx != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Text('الضوء', style: AppType.muted(color: AppColors.textMid)),
              const SizedBox(width: Sp.sm),
              FiberRx(rx, unit: true, style: AppType.rowValue()),
              const SizedBox(width: Sp.sm),
              if (band != null) FiberPill(FiberBands.label(band), tone: FiberBands.tone(rx)),
            ]),
          ],
          const SizedBox(height: Sp.md),
          OutlinedButton.icon(
            onPressed: locked || m == null ? null : () => openFiberDiagnosisFor(context, monitor: m, sub: widget.sub),
            icon: Icon(locked ? LucideIcons.lock : LucideIcons.stethoscope, size: 16),
            label: Text(locked ? 'لا صلاحيّة' : 'تشخيص الجهاز'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ]),
      ),
    );
  }
}
