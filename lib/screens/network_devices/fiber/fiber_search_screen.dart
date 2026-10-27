import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/fiber_network.dart';
import '../../../services/fiber/fiber_monitor.dart';
import '../../../services/fiber/fiber_onu.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'fiber_diagnosis_screen.dart';
import 'fiber_sheets.dart';
import 'fiber_widgets.dart';

/// بحثٌ في أجهزة الأولت: يوزر المشترك المربوط، اسم الجهاز، رقمه (3:7)، ماكه أو SN — فيفتح تشخيصه، أو يُرجع مفتاحه
/// لمن طلب الاختيار ([pick] — وضع الفنّي).
class FiberSearchScreen extends StatefulWidget {
  const FiberSearchScreen({super.key, required this.monitor, this.pick = false});

  final FiberMonitor monitor;
  final bool pick;

  @override
  State<FiberSearchScreen> createState() => _FiberSearchScreenState();
}

class _FiberSearchScreenState extends State<FiberSearchScreen> {
  final _q = TextEditingController();

  FiberMonitor get _m => widget.monitor;

  @override
  void initState() {
    super.initState();
    _m
      ..addListener(_changed)
      ..acquire();
  }

  @override
  void dispose() {
    _m
      ..removeListener(_changed)
      ..release();
    _q.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// يطابق نصّ البحث مع الجهاز: الماك بلا فواصل، والرقم «3:7» و«ONU 3:7».
  static bool matches(FiberLayout layout, int oltId, FiberOnuLive o, String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return false;
    final hexQ = q.replaceAll(RegExp(r'[:\-.\s]'), '');
    final rec = layout.recordFor(oltId, o.key, o.ident);
    final hay = <String>[
      o.key.toLowerCase(),
      o.display.toLowerCase(),
      '${o.onu.ponPort}:${o.onu.onuId}',
      if (o.onu.name != null) o.onu.name!.toLowerCase(),
      if (rec?.username != null) rec!.username!.toLowerCase(),
      if (o.onu.serial != null) o.onu.serial!.toLowerCase(),
    ];
    if (hay.any((h) => h.contains(q))) return true;
    if (hexQ.length >= 4 && RegExp(r'^[0-9a-f]+$').hasMatch(hexQ)) {
      final macs = [o.ident, ...o.onu.learnedMacs.map((m) => fiberIdent(m))];
      return macs.any((m) => m != null && m.contains(hexQ));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final layout = FiberStore.layout.value;
    final q = _q.text;
    final hits = q.trim().isEmpty ? const <FiberOnuLive>[] : _m.onus.where((o) => matches(layout, _m.oltId, o, q)).take(60).toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textHi,
        elevation: 0,
        leading: IconButton(icon: const Icon(LucideIcons.arrowRight, size: 20), onPressed: () => Navigator.pop(context)),
        title: TextField(
          controller: _q,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          style: AppType.input(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: 'يوزر، اسم، رقم الجهاز، ماك أو SN',
            hintStyle: AppType.input(color: AppColors.textPlaceholder),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (q.isNotEmpty)
            IconButton(tooltip: 'مسح', icon: const Icon(LucideIcons.x, size: 20), onPressed: () => setState(_q.clear)),
        ],
      ),
      body: FiberPage(
        maxWidth: 820,
        children: [
          if (q.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Text(
                'اكتب يوزر المشترك أو اسم جهازه على الأولت، أو رقمه مثل 3:7، أو جزءاً من ماكه${widget.pick ? '.' : ' — ويفتح تشخيصه.'}',
                textAlign: TextAlign.center,
                style: AppType.body(color: AppColors.textMid),
              ),
            )
          else if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Text('ما لقينا جهازاً يطابق «${q.trim()}» على هذا الأولت.',
                  textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
              child: FiberCard(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
                child: Column(children: [
                  for (final o in hits)
                    FiberOnuRow(
                      oltId: _m.oltId,
                      onu: o,
                      onTap: () => widget.pick
                          ? Navigator.of(context).pop(o.key)
                          : Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => FiberDiagnosisScreen(monitor: _m, onuKey: o.key)),
                            ),
                    ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
