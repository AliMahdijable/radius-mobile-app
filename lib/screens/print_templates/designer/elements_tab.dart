import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/permission_locked.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';
import 'designer_controller.dart';
import 'designer_elements.dart';

/// «العناصر»: كلّ ما في الوصل بترتيب طباعته — الحاويات والأقسام وصفوفها تحتها. كلّ سطر: الاسم، وما غُيّر فيه
/// («12 · عريض · وسط · تحت بعض»)، ومفتاح الظهور. ما لا يظهر في النوع المعروض خافتٌ بسببه. النقر يفتح خصائصه.
class ElementsTab extends StatelessWidget {
  const ElementsTab({
    super.key,
    required this.controller,
    required this.kind,
    required this.qrAvailable,
    required this.onOpen,
    this.selected,
    this.padding = const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
  });

  final ReceiptDesignController controller;
  final String kind;
  final bool qrAvailable;
  final ValueChanged<String> onOpen;

  /// العنصر المفتوح (الحاسبة: الخصائص في عمودٍ بجانب القائمة).
  final String? selected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final items = controller.elements(qrAvailable: qrAvailable);
    final rows = <Widget>[];
    var saleHeader = false;
    for (final e in items) {
      if (e.id == 'qr_note') {
        rows.add(const _QrNote());
        continue;
      }
      if (e.type == DesignerElType.sale && !saleHeader) {
        saleHeader = true;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.md, Sp.xs, Sp.xs),
          child: Text('فاتورة البيع — عناوين أقسامها', style: AppType.label()),
        ));
      }
      rows.add(_ElementRow(
        controller: controller,
        element: e,
        kind: kind,
        selected: selected == e.id,
        onTap: () => onOpen(e.id),
      ));
    }
    return ListView(padding: padding, children: rows);
  }
}

class _QrNote extends StatelessWidget {
  const _QrNote();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xs),
      child: Row(
        children: [
          Icon(LucideIcons.qrCode, size: 14, color: AppColors.textLow),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'رمز QR غير متاح لهذه الشركة — لا يُطبع على وصلها',
              style: AppType.muted(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ElementRow extends StatelessWidget {
  const _ElementRow({
    required this.controller,
    required this.element,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final ReceiptDesignController controller;
  final DesignerElement element;
  final String kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = controller;
    final id = element.id;
    final head = element.type != DesignerElType.field;
    final shown = c.shown(id);
    final dim = c.dimReason(id, kind);
    final summary = c.summary(id);
    final sub = dim ?? (shown == false ? 'مخفيّ' : (summary.isEmpty ? null : summary));
    final locked = DesignerLockScope.lockedOf(context);
    final faded = dim != null || shown == false;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: element.depth * Sp.lg, top: head ? Sp.sm : 0),
      child: Material(
        color: selected ? AppColors.brandSoftBg : (head ? AppColors.surface : Colors.transparent),
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(R.sm),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.x6, Sp.xs, Sp.x6),
            child: Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: faded ? 0.55 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          element.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: head ? AppType.bodyStrong(color: AppColors.textHi) : AppType.body(color: AppColors.textHi),
                        ),
                        if (sub != null)
                          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted()),
                      ],
                    ),
                  ),
                ),
                if (shown != null)
                  locked
                      ? const Padding(padding: EdgeInsets.all(Sp.md), child: PermLockIcon(size: 14))
                      : Switch.adaptive(
                          value: shown,
                          activeTrackColor: AppColors.brand,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => c.setShown(id, v),
                        )
                else
                  Padding(
                    padding: const EdgeInsets.all(Sp.md),
                    child: Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
