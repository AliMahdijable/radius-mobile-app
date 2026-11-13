import 'package:flutter/material.dart';

import '../../../api/device_config_api.dart';
import '../../../theme/spacing.dart';
import 'device_probe_card.dart';
import 'foldable_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// «الجهاز الثاني» (نانو + راوتر، ١٢ نوفمبر — المالك: «المشترك اكو عدهم نانو وراوتر… فالكارت يطلع معلومات نانو ومعلومات راوترته»):
/// كرت معلومات جهازٍ ثانٍ تحت كرت الجهاز، يظهر حين يحفظ الوكيل عنواناً ثانياً في إعداد المشترك (زرّ الإعدادات في الكرت) — ويختفي
/// حين يمسحه، بلا إعادة فتح الصفحة ([DeviceConfigApi.revision]).
class SecondDeviceSlot extends StatefulWidget {
  const SecondDeviceSlot({super.key, required this.ip, required this.username, this.company});

  final String ip;
  final String username;
  final String? company;

  @override
  State<SecondDeviceSlot> createState() => _SecondDeviceSlotState();
}

class _SecondDeviceSlotState extends State<SecondDeviceSlot> {
  bool _has = false;

  /// رقم آخر حفظٍ للإعداد — جزءٌ من مفتاح الكرت: حفظٌ جديد (عنوانٌ أو اعتمادٌ آخر) يعيد بناءه فيفحص بالإعداد الجديد.
  int _rev = DeviceConfigApi.revision.value;

  @override
  void initState() {
    super.initState();
    _has = DeviceConfigApi.peekConfig(widget.username, company: widget.company)?.hasSecond ?? false;
    DeviceConfigApi.revision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(SecondDeviceSlot old) {
    super.didUpdateWidget(old);
    if (old.username != widget.username || old.company != widget.company) _load();
  }

  @override
  void dispose() {
    DeviceConfigApi.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await DeviceConfigApi.fetchConfig(widget.username, company: widget.company);
    if (!mounted) return;
    final has = cfg?.hasSecond ?? false;
    final rev = DeviceConfigApi.revision.value;
    if (has != _has || rev != _rev) {
      setState(() {
        _has = has;
        _rev = rev;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_has) return const SizedBox.shrink();
    // ينطوي كبقيّة أقسام الصفحة — ومطويٌّ افتراضاً (SectionFold): كرته لا يُبنى فلا يُفحص جهازه حتى يفتحه الوكيل.
    return Padding(
      padding: const EdgeInsets.only(top: Sp.md),
      child: FoldableSection(
        id: 'dev2',
        title: 'الجهاز الثاني',
        icon: LucideIcons.router,
        builder: (fold) => DeviceProbeCard(
          key: ValueKey('second-device-${widget.company ?? ''}-${widget.username}-$_rev'),
          ip: widget.ip,
          username: widget.username,
          company: widget.company,
          slot: 2,
          onFold: fold,
        ),
      ),
    );
  }
}
