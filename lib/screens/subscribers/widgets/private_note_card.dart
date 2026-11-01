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

/// حال ملاحظة مشتركٍ واحد: تُجلب مرّة، وتُضاف/تُعدَّل/تُحذف بورقتها. تملكه شاشة المشترك فيبقى حيّاً حين تطوي القائمة الكرت
/// خارج الشاشة، ويقرؤه «المزيد» («إضافة ملاحظة» أو «تعديل الملاحظة» — المالك ١ نوفمبر: «اضافة الملاحظة حولها بالمزيد»).
class PrivateNoteController extends ChangeNotifier {
  PrivateNoteController(this.sub);
  final Subscriber sub;
  PrivateNote? note;
  bool loaded = false;
  bool failed = false;
  bool _loading = false;
  bool _disposed = false;

  /// جُلبت بنجاح — قبلها (أو بعد تعذّرٍ) لا إضافة: حفظٌ على ملاحظةٍ لم تُقرأ قد يمحوها.
  bool get ready => loaded && !failed;

  Future<void> load() async {
    final idx = sub.idx;
    if (idx == null || idx.isEmpty || _loading) return;
    _loading = true;
    final r = await MergedOps.run(sub, () => PrivateNotesApi.get(idx));
    _loading = false;
    if (_disposed) return;
    loaded = true;
    failed = !r.ok;
    note = r.note;
    notifyListeners();
  }

  /// ورقة الملاحظة (إضافة/تعديل/حذف) — وما حُفظ يظهر في الكرت مباشرةً.
  Future<void> edit(BuildContext context) async {
    if (!ready) return;
    final saved = await showAppSheet<({PrivateNote? note})>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PrivateNoteSheet(sub: sub, initial: note),
    );
    if (saved == null || _disposed) return;
    note = saved.note;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// «ملاحظة» خاصّة بكرت المشترك (المالك ٣١ أكتوبر: «زر ملاحظات خاص بنظامنا… الملاحظة تنعرض بكارت المشترك فقط، لكل الساسات»):
/// نصٌّ على خادمنا وحده — يُعرض هنا فقط (لا القوائم ولا الرسائل). القراءة لمن يرى المشترك؛ الإضافة والتعديل والحذف
/// بـ`subscribers.private_note`. «كل الشركات»: بنداء شركة المشترك (MergedOps).
/// الكرت للملاحظة القائمة وحدها (بـ«تعديل»)؛ «إضافة ملاحظة» في «المزيد» (المالك ١ نوفمبر) — والموظّف بلا مفتاحها يراها هناك مقفلة.
class PrivateNoteCard extends StatefulWidget {
  const PrivateNoteCard({super.key, required this.sub, this.controller});
  final Subscriber sub;

  /// من شاشة المشترك (يبقى حيّاً بطيّ القائمة ويقرؤه «المزيد»)؛ غائبٌ ⇒ الكرت يملك واحداً.
  final PrivateNoteController? controller;

  @override
  State<PrivateNoteCard> createState() => _PrivateNoteCardState();
}

class _PrivateNoteCardState extends State<PrivateNoteCard> {
  PrivateNoteController? _own;

  PrivateNoteController get _c => widget.controller ?? (_own ??= PrivateNoteController(widget.sub));

  bool get _canEdit => Perms.has('subscribers.private_note');

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(PrivateNoteCard old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_changed);
      _attach();
    }
  }

  void _attach() {
    _c.addListener(_changed);
    if (!_c.loaded) _c.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final idx = widget.sub.idx;
    // ردٌّ تعذّر (الجدول قيد التجهيز أو خطأ): لا قسمٌ يوهم بملاحظةٍ فارغة. ولا ملاحظة ⇒ لا شيء (الإضافة من «المزيد»).
    final note = _c.note;
    if (idx == null || idx.isEmpty || !_c.ready || note == null) return const SizedBox.shrink();
    final locked = !_canEdit;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Container(
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
                    onPressed: locked ? null : () => _c.edit(context),
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
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
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
