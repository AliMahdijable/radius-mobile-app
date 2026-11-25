import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «باركود الدفع» (٢٥ نوفمبر): صورة الباركود مصغّرةً على خلفيّةٍ بيضاء (تُقرأ بالوضع الداكن أيضاً)، والنقر يفتحها بملء الشاشة —
/// تُعرض للصيرفة من الهاتف وتُكبَّر بالأصابع. تعذّر تحميلها ⇒ [onBroken] (المستدعي يُظهر الرقم احتياطاً).
class PayQrTile extends StatelessWidget {
  const PayQrTile({super.key, required this.url, required this.title, this.onBroken});

  final String url;
  final String title;
  final VoidCallback? onBroken;

  /// للاختبار: صورةٌ بلا شبكة (null ⇒ Image.network) — ومعاينة بطاقة الإعداد تستعملها أيضاً.
  static Widget Function(String url)? debugImage;

  static const _ink = Color(0xFF0F172A);
  static const _link = Color(0xFF1D4ED8);

  Widget _image(BuildContext context, {BoxFit fit = BoxFit.contain}) {
    final d = debugImage;
    if (d != null) return d(url);
    return Image.network(
      url,
      fit: fit,
      errorBuilder: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onBroken?.call());
        return const SizedBox(height: 48);
      },
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PayQrViewer(title: title, image: Builder(builder: (c) => _image(c))),
    ));
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: () => _open(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(children: [
              ConstrainedBox(constraints: const BoxConstraints(maxHeight: 220), child: _image(context)),
              const SizedBox(height: Sp.sm),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.maximize2, size: 14, color: _link),
                const SizedBox(width: Sp.xs),
                Flexible(child: Text('اضغط للتكبير — اعرضه بالصيرفة', style: AppType.micro(color: _link).copyWith(fontWeight: FontWeight.w700))),
              ]),
            ]),
          ),
        ),
      );
}

class _PayQrViewer extends StatelessWidget {
  const _PayQrViewer({required this.title, required this.image});
  final String title;
  final Widget image;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: PayQrTile._ink,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: Text(title, maxLines: 2, style: AppType.bodyBold(color: PayQrTile._ink)),
        ),
        body: SafeArea(
          child: InteractiveViewer(
            key: const ValueKey('pay-qr-viewer'),
            maxScale: 5,
            child: Center(child: Padding(padding: const EdgeInsets.all(Sp.lg), child: image)),
          ),
        ),
      );
}
