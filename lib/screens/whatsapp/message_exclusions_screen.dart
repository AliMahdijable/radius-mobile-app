import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/message_exclusions_api.dart';
import '../desktop/desk_widgets.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/widgets/message_exclusion_card.dart';

/// «المستثنون من الرسائل» (المالك ١٤ نوفمبر: «نسوي مثل القسم الريجكتد مسج، يعني ذولا ما تروح لهم رسائل»): قائمة من أوقف الوكيل
/// رسائل النظام عنهم — ما أُوقف لكلٍّ، ملاحظته، من أوقفها ومتى؛ بحثٌ، تعديلٌ، و«السماح بالرسائل». الإضافة من صفحة المشترك
/// («المزيد» ⇐ «إيقاف الرسائل») أو من شريط تحديد المشتركين. الحال في [MessageExclusionsState] (تتشاركه القائمة وصفحة المشترك).
class MessageExclusionsScreen extends StatefulWidget {
  const MessageExclusionsScreen({super.key});

  @override
  State<MessageExclusionsScreen> createState() => _MessageExclusionsScreenState();
}

class _MessageExclusionsScreenState extends State<MessageExclusionsScreen> {
  final TextEditingController _search = TextEditingController();
  String? _removing;

  @override
  void initState() {
    super.initState();
    unawaited(MessageExclusionsState.ensureFresh(force: true));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MxEntry> _rows(MxSnapshot snap) {
    final all = snap.entries.values.toList()
      ..sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((e) => [e.username, e.name ?? '', e.phone ?? '', e.note ?? '', e.label].any((v) => v.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _edit(MxEntry e) async {
    await showMessageExclusionSheet(
      context,
      subject: MxSubject(username: e.username, idx: e.idx),
      title: e.name == null ? e.username : '${e.name} — ${e.username}',
    );
  }

  Future<void> _allow(MxEntry e) async {
    if (_removing != null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('السماح بالرسائل', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text('تعود رسائل النظام تصل «${e.display}»؟', style: AppType.body(color: AppColors.textHi)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          TextButton(
            key: const ValueKey('mx-allow-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('السماح'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = e.username);
    final r = await MessageExclusionsState.remove(e.username);
    if (!mounted) return;
    setState(() => _removing = null);
    showSheetSnack(context, r.ok ? 'عادت تصله الرسائل' : (r.message ?? 'تعذّر الحفظ'), isError: !r.ok);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('المستثنون من الرسائل', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<MxSnapshot?>(
          valueListenable: MessageExclusionsState.snapshot,
          builder: (context, snap, _) {
            if (snap == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snap.enabled ? _rows(snap) : const <MxEntry>[];
            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: () => MessageExclusionsState.ensureFresh(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  Text(
                    'مشتركون لا تصلهم رسائل النظام — كلّها أو أنواعٌ منها. للإضافة: افتح المشترك ثمّ «المزيد» ثمّ «إيقاف الرسائل»، '
                    'أو حدّد عدّة مشتركين واضغط الجرس المشطوب.',
                    style: AppType.muted(),
                  ),
                  const SizedBox(height: Sp.md),
                  if (!snap.enabled)
                    _empty('هذه الميزة لم تُفتح لحسابك بعد.')
                  else if (snap.count == 0)
                    _empty('لا أحد مستثنى — الرسائل تصل للجميع.')
                  else ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.pill)),
                          child: Text('${snap.count} مستثنى', style: AppType.micro(color: AppColors.textMid)),
                        ),
                      ],
                    ),
                    if (snap.count > 6) ...[
                      const SizedBox(height: Sp.sm),
                      TextField(
                        key: const ValueKey('mx-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: AppType.input(color: AppColors.textHi),
                        decoration: InputDecoration(
                          hintText: 'بحث بالاسم أو اليوزر أو الرقم',
                          hintStyle: AppType.input(color: AppColors.textPlaceholder),
                          prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.surfaceInput,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
                        ),
                      ),
                    ],
                    const SizedBox(height: Sp.sm),
                    if (rows.isEmpty)
                      _empty('لا نتيجة لهذا البحث.')
                    else
                      for (final e in rows) ...[
                        _tile(e, canManage: snap.canManage),
                        const SizedBox(height: Sp.sm),
                      ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text, textAlign: TextAlign.center, style: AppType.muted()),
      );

  static String _when(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _tile(MxEntry e, {required bool canManage}) {
    final meta = [
      if (e.by != null) e.by!,
      if (e.at != null) _when(e.at!),
    ].join(' · ');
    final labels = e.label.split('، ');
    return Container(
      key: ValueKey('mx-row-${e.username}'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.bellOff, size: 16, color: AppColors.textLabel),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.display, style: AppType.listName(), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (e.name != null)
                  Text(
                    e.username,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textLabel),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final g in labels)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.warningSoftBg, borderRadius: BorderRadius.circular(R.pill)),
                        child: Text(g, style: AppType.micro(color: AppColors.warningOnSoft)),
                      ),
                  ],
                ),
                if (e.note != null) ...[
                  const SizedBox(height: 4),
                  Text(e.note!, style: AppType.muted()),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'تعديل',
              visualDensity: VisualDensity.compact,
              onPressed: _removing != null ? null : () => _edit(e),
              icon: Icon(LucideIcons.pencil, size: 17, color: AppColors.brandAccent),
            ),
            IconButton(
              key: ValueKey('mx-allow-${e.username}'),
              tooltip: 'السماح بالرسائل',
              visualDensity: VisualDensity.compact,
              onPressed: _removing != null ? null : () => _allow(e),
              icon: _removing == e.username
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(LucideIcons.bellRing, size: 17, color: AppColors.success),
            ),
          ],
        ],
      ),
    );
  }
}
