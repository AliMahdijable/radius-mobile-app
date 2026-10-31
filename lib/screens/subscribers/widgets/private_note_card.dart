import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/private_notes_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «ملاحظة» خاصّة بكرت المشترك (المالك ٣١ أكتوبر: «زر ملاحظات خاص بنظامنا… الملاحظة تنعرض بكارت المشترك فقط، لكل الساسات»):
/// نصٌّ على خادمنا وحده — يُعرض هنا فقط (لا القوائم ولا الرسائل). القراءة لمن يرى المشترك؛ الإضافة والتعديل والحذف
/// بـ`subscribers.private_note` — الموظّف بلاها يرى الزرّ بمكانه مقفلاً. «كل الشركات»: بنداء شركة المشترك (MergedOps).
class PrivateNoteCard extends StatefulWidget {
  const PrivateNoteCard({super.key, required this.sub});
  final Subscriber sub;

  @override
  State<PrivateNoteCard> createState() => _PrivateNoteCardState();
}

class _PrivateNoteCardState extends State<PrivateNoteCard> {
  PrivateNote? _note;
  bool _loaded = false;
  bool _failed = false;

  bool get _canEdit => Perms.has('subscribers.private_note');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final idx = widget.sub.idx;
    if (idx == null || idx.isEmpty) return;
    final r = await MergedOps.run(widget.sub, () => PrivateNotesApi.get(idx));
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _failed = !r.ok;
      _note = r.note;
    });
  }

  Future<void> _edit() async {
    final saved = await showAppSheet<({PrivateNote? note})>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PrivateNoteSheet(sub: widget.sub, initial: _note),
    );
    if (saved != null && mounted) setState(() => _note = saved.note);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final idx = widget.sub.idx;
    // ردٌّ تعذّر (الجدول قيد التجهيز أو خطأ): لا قسمٌ يوهم بملاحظةٍ فارغة.
    if (idx == null || idx.isEmpty || !_loaded || _failed) return const SizedBox.shrink();
    final note = _note;
    final locked = !_canEdit;
    if (note == null && locked && !Perms.isEmployee) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: note == null
          ? _addButton(locked)
          : Container(
              decoration: BoxDecoration(
                color: AppColors.warningSoftBg,
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.warningSoftBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Row(
                      children: [
                        Icon(LucideIcons.notebookPen, size: 16, color: AppColors.warningOnSoft),
                        const SizedBox(width: Sp.sm),
                        Text('ملاحظة', style: AppType.label(color: AppColors.warningOnSoft)),
                        const Spacer(),
                        Text('خاصّة بك — لا يراها المشترك', style: AppType.micro(color: AppColors.textMid)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SelectableText(note.note, style: AppType.body(color: AppColors.textHi).copyWith(height: 1.55)),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: AppColors.warningSoftBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (note.updatedAt != null) 'آخر تعديل ${_time(note.updatedAt!)}',
                              if (note.updatedBy != null) note.updatedBy!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.micro(color: AppColors.textMid),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: locked ? null : _edit,
                          icon: Icon(locked ? LucideIcons.lock : LucideIcons.pencil, size: 15),
                          label: const Text('تعديل'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _addButton(bool locked) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: locked ? null : _edit,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.borderStrong, style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(locked ? LucideIcons.lock : LucideIcons.notebookPen, size: 17, color: AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Text(locked ? 'إضافة ملاحظة — لا صلاحيّة' : 'إضافة ملاحظة', style: AppType.label(color: AppColors.textMid)),
            ],
          ),
        ),
      ),
    );
  }

  /// ISO من الخادم ⇒ «YYYY-MM-DD HH:MM» بالتوقيت المحلّيّ.
  static String _time(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _PrivateNoteSheet extends StatefulWidget {
  const _PrivateNoteSheet({required this.sub, this.initial});
  final Subscriber sub;
  final PrivateNote? initial;

  @override
  State<_PrivateNoteSheet> createState() => _PrivateNoteSheetState();
}

class _PrivateNoteSheetState extends State<_PrivateNoteSheet> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial?.note ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _len => _ctrl.text.trim().runes.length;
  bool get _changed => _ctrl.text.trim() != (widget.initial?.note ?? '').trim();

  Future<void> _save(String text) async {
    final idx = widget.sub.idx;
    if (idx == null || _busy) return;
    setState(() => _busy = true);
    final r = await MergedOps.write(widget.sub, () => PrivateNotesApi.save(idx, text));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر حفظ الملاحظة', isError: true);
      return;
    }
    showSheetSnack(context, text.trim().isEmpty ? 'حُذفت الملاحظة' : 'حُفظت الملاحظة');
    Navigator.of(context).pop((note: r.note));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final name = widget.sub.fullName.trim().isNotEmpty ? widget.sub.fullName : widget.sub.username;
    final over = _len > PrivateNotesApi.maxChars;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.notebookPen,
        title: 'ملاحظة',
        subtitle: name,
        tint: AppColors.warningOnSoft,
        tintBg: AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('خاصّة بك — تظهر في كرت المشترك فقط، ولا تُرسل له ولا تُكتب في الساس.', style: AppType.muted()),
          const SizedBox(height: Sp.md),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
            style: AppType.input(color: AppColors.textHi).copyWith(height: 1.5),
            decoration: InputDecoration(
              hintText: 'مثلاً: يدفع آخر الشهر · الراوتر عند الجيران · اتّصل قبل الزيارة',
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_len/${PrivateNotesApi.maxChars}',
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            style: AppType.micro(color: over ? AppColors.error : AppColors.textMid),
          ),
        ],
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: !over && _changed && _ctrl.text.trim().isNotEmpty,
        onPressed: () => _save(_ctrl.text.trim()),
        leading: widget.initial == null
            ? null
            : SheetFooterIconButton(
                icon: LucideIcons.trash2,
                color: AppColors.error,
                onTap: _busy ? null : () => _save(''),
              ),
      ),
    );
  }
}
