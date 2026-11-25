import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/pay_qr.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/pay_qr_tile.dart';

/// حال باركود طريقةٍ بنموذج «طلب التجديد من التطبيق»: المحفوظ ([url])، أو صورةٌ جديدة لم تُحفظ ([image])، و«الباركود وحده».
@immutable
class PayQrDraft {
  const PayQrDraft({this.url, this.image, this.qrOnly = false});
  final String? url;
  final PayQrImage? image;
  final bool qrOnly;
  bool get has => url != null || image != null;

  PayQrDraft withImage(PayQrImage img) => PayQrDraft(url: url, image: img, qrOnly: qrOnly);
  PayQrDraft withQrOnly(bool v) => PayQrDraft(url: url, image: image, qrOnly: v);
  static const empty = PayQrDraft();
}

/// ما تغيّر من الباركود ⇒ حقول الحفظ: صورةٌ جديدة (data URL) أو إزالة (null)، وطريقة الظهور لمن بقيت له صورة. لا تغيير ⇒ {}.
Map<String, Object?> payQrPatch(Map<String, PayQrDraft> now, Map<String, PayQrDraft> base) {
  final out = <String, Object?>{};
  for (final m in payQrMethods) {
    final q = now[m] ?? PayQrDraft.empty;
    final b = base[m] ?? PayQrDraft.empty;
    if (q.image != null) {
      out['${m}_qr'] = q.image!.dataUrl;
    } else if (q.url == null && b.url != null) {
      out['${m}_qr'] = null;
    }
    if (q.has && (q.image != null || q.qrOnly != b.qrOnly)) out['${m}_show'] = q.qrOnly ? 'qr' : 'both';
  }
  return out;
}

/// «باركود الدفع» في بطاقة الإعداد (٢٥ نوفمبر): صورة باركود الطريقة (اختياريّة) + «يظهر للمشترك: مع الرقم · الباركود وحده».
/// الصورة تُجهَّز هنا ([pickPayQr]: خلفيّةٌ بيضاء، PNG ثمّ JPEG، ≤ ٤٥٠ ك.ب) وتُرسل مع «حفظ» البطاقة نفسه.
class PayQrField extends StatefulWidget {
  const PayQrField({
    super.key,
    required this.method,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.picker,
  });

  final String method;
  final String label;
  final String hint;
  final PayQrDraft value;
  final ValueChanged<PayQrDraft> onChanged;
  final bool enabled;

  /// للاختبار: اختيار الصورة بلا معرض.
  final PayQrPicker? picker;

  @override
  State<PayQrField> createState() => _PayQrFieldState();
}

class _PayQrFieldState extends State<PayQrField> {
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final img = await (widget.picker ?? pickPayQr)();
      if (img != null && mounted) widget.onChanged(widget.value.withImage(img));
    } on PayQrError catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.errorFill));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview() {
    final v = widget.value;
    final img = v.image;
    if (img != null) return Image.memory(img.bytes, fit: BoxFit.contain, key: ValueKey('pay-qr-preview-${widget.method}'));
    final d = PayQrTile.debugImage;
    if (d != null) return KeyedSubtree(key: ValueKey('pay-qr-preview-${widget.method}'), child: d(v.url!));
    return Image.network(v.url!, fit: BoxFit.contain, key: ValueKey('pay-qr-preview-${widget.method}'),
        errorBuilder: (_, __, ___) => Icon(LucideIcons.imageOff, size: 22, color: AppColors.textLow));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final v = widget.value;
    final m = widget.method;
    final on = widget.enabled && !_busy;
    final hint = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.qrCode, size: 13, color: AppColors.textLow)),
      const SizedBox(width: Sp.xs),
      Expanded(child: Text(widget.hint, style: AppType.micro(color: AppColors.textLow))),
    ]);
    if (!v.has) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        OutlinedButton.icon(
          key: ValueKey('pay-qr-add-$m'),
          onPressed: on ? _pick : null,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(LucideIcons.imagePlus, size: 16),
          label: const Text('رفع صورة الباركود'),
        ),
        const SizedBox(height: Sp.xs),
        hint,
      ]);
    }
    return Container(
      key: ValueKey('pay-qr-field-$m'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: _preview(),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: AppType.subtitle(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
              if (v.image != null) ...[
                const SizedBox(height: 2),
                Text('جديدة ${payQrSizeLabel(v.image!.length)} — تُحفظ بـ«حفظ»', style: AppType.micro(color: AppColors.textMid)),
              ],
              const SizedBox(height: Sp.sm),
              Wrap(spacing: Sp.sm, runSpacing: Sp.xs, children: [
                OutlinedButton(
                  key: ValueKey('pay-qr-change-$m'),
                  onPressed: on ? _pick : null,
                  child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تغيير'),
                ),
                TextButton(
                  key: ValueKey('pay-qr-remove-$m'),
                  onPressed: on ? () => widget.onChanged(PayQrDraft.empty) : null,
                  child: const Text('إزالة'),
                ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.md),
        Text('يظهر للمشترك:', style: AppType.micro(color: AppColors.textMid)),
        const SizedBox(height: Sp.xs),
        Row(children: [
          for (final (qrOnly, text) in const [(false, 'مع الرقم'), (true, 'الباركود وحده')]) ...[
            if (qrOnly) const SizedBox(width: Sp.sm),
            Expanded(
              child: _ShowChoice(
                key: ValueKey('pay-qr-show-$m-${qrOnly ? 'qr' : 'both'}'),
                text: text,
                selected: v.qrOnly == qrOnly,
                onTap: widget.enabled ? () => widget.onChanged(v.withQrOnly(qrOnly)) : null,
              ),
            ),
          ],
        ]),
        const SizedBox(height: Sp.sm),
        hint,
      ]),
    );
  }
}

class _ShowChoice extends StatelessWidget {
  const _ShowChoice({super.key, required this.text, required this.selected, required this.onTap});
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? AppColors.brand.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(R.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.sm),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: selected ? AppColors.brand : AppColors.border),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: selected ? AppColors.brand : AppColors.textHi).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ),
        ),
      );
}
