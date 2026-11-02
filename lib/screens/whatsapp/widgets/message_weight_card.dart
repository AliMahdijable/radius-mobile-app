import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/message_style_api.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// نصٌّ بعلامات واتساب ⇒ مقاطع: `*x*` عريض، والباقي كما هو.
List<TextSpan> waBoldSpans(String text, TextStyle base) {
  final out = <TextSpan>[];
  final re = RegExp(r'\*([^*\n]+)\*');
  var i = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > i) out.add(TextSpan(text: text.substring(i, m.start), style: base));
    out.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w700)));
    i = m.end;
  }
  if (i < text.length) out.add(TextSpan(text: text.substring(i), style: base));
  return out;
}

/// «سُمك خطّ الرسائل» (٢ نوفمبر — المالك: «خاصيه تتحكم بسمك وثخن خط الرسالة الواتساب والتلي كرام»): ثلاث درجات بمعاينةٍ حيّة من
/// الخادم، والحفظ فور الاختيار. الموظّف بلا «قوالب الواتساب» يراها مقفلةً بمكانها. خادمٌ أقدم ⇒ لا بطاقة.
class MessageWeightCard extends StatefulWidget {
  const MessageWeightCard({super.key});

  @override
  State<MessageWeightCard> createState() => _MessageWeightCardState();
}

class _MessageWeightCardState extends State<MessageWeightCard> {
  MessageStyle? _style;
  String? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    MessageStyleApi.load().then((s) {
      if (mounted && s != null) setState(() => _style = s);
    });
  }

  bool get _locked => Perms.isEmployee && !Perms.has('whatsapp.templates');

  Future<void> _select(String w) async {
    final s = _style;
    if (s == null || _saving || w == (_picked ?? s.weight)) return;
    if (_locked) {
      showSheetSnack(context, 'لا صلاحيّة لتعديل قوالب الواتساب', isError: true);
      return;
    }
    setState(() {
      _picked = w;
      _saving = true;
    });
    final r = await MessageStyleApi.save(w);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.ok) _style = MessageStyle(weight: w, options: s.options, previews: s.previews);
      _picked = null;
    });
    showSheetSnack(
      context,
      r.ok ? (w == 'normal' ? 'الرسائل بخطٍّ عادي' : w == 'values' ? 'القيم في الرسائل بخطٍّ عريض' : 'الرسائل كلّها بخطٍّ عريض') : (r.error ?? 'تعذّر الحفظ'),
      isError: !r.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _style;
    if (s == null) return const SizedBox.shrink();
    final w = _picked ?? s.weight;
    final base = AppType.body(color: AppColors.textBody).copyWith(height: 1.6);
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_locked ? LucideIcons.lock : LucideIcons.bold, size: 18, color: _locked ? AppColors.textLow : AppColors.channelWhatsApp),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('سُمك خطّ الرسائل', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi))),
          if (_saving) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: Sp.xs),
        Text('لكلّ رسائلك في واتساب وتلغرام — التذكيرات والتفعيل والتسديد والجماعيّة. التطبيقان لا يغيّران حجم الخطّ؛ العريض وحده.',
            style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5)),
        const SizedBox(height: Sp.sm),
        Opacity(
          opacity: _locked ? 0.55 : 1,
          child: SheetSegmented(
            labels: [for (final o in s.options) MessageStyle.labels[o] ?? o],
            selectedIndex: s.options.indexOf(w).clamp(0, s.options.length - 1),
            onSelect: (i) => _select(s.options[i]),
          ),
        ),
        const SizedBox(height: Sp.sm),
        Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
          child: Semantics(
            liveRegion: true,
            child: Text.rich(TextSpan(children: waBoldSpans(s.previews[w] ?? '', base))),
          ),
        ),
      ]),
    );
  }
}
