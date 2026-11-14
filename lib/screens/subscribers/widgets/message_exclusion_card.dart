import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/message_exclusions_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «المستثنون من الرسائل» في صفحة المشترك (المالك ١٤ نوفمبر: «ذولا ما تروح لهم رسائل… التفعيل، التنبيهات، التذكير، التبليغات»).
/// الكرت للمشترك الموقوفة رسائله وحده («لا تصله: …» بمن أوقفها ومتى، و«تعديل»)؛ «إيقاف الرسائل» في «المزيد» — كالملاحظة
/// وأرقام التواصل. الحال في [MessageExclusionsState] (تتشاركه القائمة). «كل الشركات» (صفٌّ من شركةٍ أخرى) لا يُعرض له شيء.

/// المشترك كما يُحفظ معه الاستثناء.
MxSubject mxSubjectOf(Subscriber sub) => MxSubject(
      username: sub.username,
      idx: sub.idx,
      name: sub.fullName.trim().isEmpty ? null : sub.fullName.trim(),
      phone: sub.phone,
    );

String _when(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

class MessageExclusionCard extends StatelessWidget {
  const MessageExclusionCard({super.key, required this.sub, required this.onEdit, this.pageLocked = false});
  final Subscriber sub;
  final VoidCallback onEdit;

  /// الصفحة موقوفة التنفيذ الآن («كل الشركات» وما شابه) ⇒ «تعديل» مقفل. ومن لا يُدير (موظّفٌ بلا صلاحيّتها — يقوله الخادم)
  /// يراه بمكانه مقفلاً كذلك.
  final bool pageLocked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return ValueListenableBuilder<MxSnapshot?>(
      valueListenable: MessageExclusionsState.snapshot,
      builder: (context, snap, _) {
        final e = sub.companyKey == null ? snap?.of(sub.username) : null;
        if (snap == null || !snap.enabled || e == null) return const SizedBox.shrink();
        final canEdit = snap.canManage && !pageLocked;
        final meta = [
          if (e.by != null) e.by!,
          if (e.at != null) _when(e.at!),
        ].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Container(
            key: const ValueKey('mx-card'),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(LucideIcons.bellOff, size: 16, color: AppColors.warningOnSoft),
                      ),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'لا تصله: ', style: AppType.body(color: AppColors.textHi)),
                            TextSpan(
                              text: e.label,
                              style: AppType.body(color: AppColors.warningOnSoft).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                if (e.note != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(38, 0, 14, 4),
                    child: Text(e.note!, style: AppType.muted()),
                  ),
                const SizedBox(height: 4),
                Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.micro(color: AppColors.textMid),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: canEdit ? onEdit : null,
                        icon: Icon(canEdit ? LucideIcons.pencil : LucideIcons.lock, size: 15),
                        label: const Text('تعديل'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ورقة «إيقاف الرسائل» لمشتركٍ واحد — تحفظ عبر [MessageExclusionsState] (فترسم القائمة والكرت فوراً). ⇒ true إن تغيّر شيء.
Future<bool?> showMessageExclusionSheet(BuildContext context, {required MxSubject subject, String? title}) {
  final snap = MessageExclusionsState.snapshot.value;
  if (snap == null || !snap.enabled) return Future<bool?>.value(null);
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExclusionSheet(
      subjects: [subject],
      current: snap.of(subject.username),
      groups: snap.groups,
      subtitle: title ?? ((subject.name ?? '').trim().isNotEmpty ? subject.name!.trim() : subject.username),
    ),
  );
}

/// ورقة الجماعيّ (شريط تحديد المشتركين): إيقاف الرسائل عن المحدَّدين، أو السماح بها لمن أُوقفت عنه منهم. ⇒ true إن نُفّذ.
Future<bool?> showBulkMessageExclusionSheet(BuildContext context, {required List<MxSubject> subjects}) {
  final snap = MessageExclusionsState.snapshot.value;
  if (snap == null || !snap.enabled || subjects.isEmpty) return Future<bool?>.value(null);
  final already = subjects.where((s) => snap.of(s.username) != null).length;
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExclusionSheet(
      subjects: subjects,
      current: null,
      groups: snap.groups,
      alreadyExcluded: already,
      subtitle: already > 0 ? '${subjects.length} مشترك — $already منهم موقوفةٌ عنه من قبل' : '${subjects.length} مشترك محدَّد',
    ),
  );
}

class _ExclusionSheet extends StatefulWidget {
  const _ExclusionSheet({
    required this.subjects,
    required this.current,
    required this.groups,
    required this.subtitle,
    this.alreadyExcluded = 0,
  });

  /// واحدٌ (صفحة المشترك أو القائمة) أو عدّة (الجماعيّ).
  final List<MxSubject> subjects;
  final MxEntry? current;
  final List<MxGroup> groups;
  final String subtitle;
  final int alreadyExcluded;

  @override
  State<_ExclusionSheet> createState() => _ExclusionSheetState();
}

class _ExclusionSheetState extends State<_ExclusionSheet> {
  late bool _all = widget.current == null || widget.current!.all;
  late final Set<String> _picked = {
    if (widget.current != null && !widget.current!.all) ...widget.current!.groups,
  };
  late final TextEditingController _note = TextEditingController(text: widget.current?.note ?? '');
  bool _busy = false;

  bool get _bulk => widget.subjects.length > 1;
  List<MxGroup> get _parts => [for (final g in widget.groups) if (!g.isAll) g];
  MxGroup? get _allDef {
    for (final g in widget.groups) {
      if (g.isAll) return g;
    }
    return null;
  }

  List<String> get _chosen => _all ? const [MxGroup.allKey] : [for (final g in _parts) if (_picked.contains(g.key)) g.key];
  bool get _valid => _all || _picked.isNotEmpty;

  bool get _changed {
    final cur = widget.current;
    if (cur == null) return true;
    final now = _chosen;
    return now.length != cur.groups.length || !now.every(cur.groups.contains) || _note.text.trim() != (cur.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    if (_bulk) {
      final r = await MessageExclusionsState.bulk(add: true, items: widget.subjects, groups: _chosen, note: _note.text);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!r.ok) {
        showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
        return;
      }
      showSheetSnack(context, 'أُوقفت الرسائل عن ${r.done} مشترك');
      Navigator.of(context).pop(true);
      return;
    }
    final r = await MessageExclusionsState.save(widget.subjects.single, groups: _chosen, note: _note.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
      return;
    }
    showSheetSnack(context, r.entry == null ? 'عادت تصله الرسائل' : 'أُوقفت عنه: ${r.entry!.label}');
    Navigator.of(context).pop(true);
  }

  /// «السماح بالرسائل»: إزالة الاستثناء (واحدٌ أو المحدَّدون).
  Future<void> _allow() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_bulk) {
      final r = await MessageExclusionsState.bulk(add: false, items: widget.subjects);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!r.ok) {
        showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
        return;
      }
      showSheetSnack(context, 'عادت الرسائل لـ${r.done} مشترك');
      Navigator.of(context).pop(true);
      return;
    }
    final r = await MessageExclusionsState.remove(widget.subjects.single.username);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
      return;
    }
    showSheetSnack(context, 'عادت تصله الرسائل');
    Navigator.of(context).pop(true);
  }

  Widget _tile({
    required Key key,
    required String title,
    required String hint,
    required bool on,
    required VoidCallback onTap,
    required Widget control,
  }) =>
      Material(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(R.md),
          onTap: _busy ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: on ? AppColors.brand.withValues(alpha: 0.45) : AppColors.border),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppType.label(color: AppColors.textHi)),
                      if (hint.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(hint, style: AppType.micro(color: AppColors.textMid)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                IgnorePointer(child: control),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final existing = widget.current != null;
    final allDef = _allDef;
    final canAllow = existing || widget.alreadyExcluded > 0;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.bellOff,
        title: existing ? 'الرسائل الموقوفة' : 'إيقاف الرسائل',
        subtitle: widget.subtitle,
        tint: AppColors.warningOnSoft,
        tintBg: AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ما تُوقفه هنا لا يُرسَل له من النظام — على خادمنا لا المزوّد، ولا يُبلَّغ المشترك.', style: AppType.muted()),
          const SizedBox(height: Sp.md),
          _tile(
            key: const ValueKey('mx-all'),
            title: allDef?.label ?? 'كلّ الرسائل',
            hint: allDef?.hint ?? 'لا تصله أيّ رسالة من النظام — ولا اليدويّة',
            on: _all,
            onTap: () => setState(() => _all = !_all),
            control: Switch(value: _all, onChanged: (_) {}),
          ),
          if (!_all) ...[
            const SizedBox(height: Sp.md),
            Text('أو أنواعٌ بعينها:', style: AppType.micro(color: AppColors.textMid)),
            const SizedBox(height: 6),
            for (final g in _parts) ...[
              _tile(
                key: ValueKey('mx-group-${g.key}'),
                title: g.label,
                hint: g.hint,
                on: _picked.contains(g.key),
                onTap: () => setState(() => _picked.contains(g.key) ? _picked.remove(g.key) : _picked.add(g.key)),
                // مربّع الاختيار بمقاس مربّعات التطبيق الأخرى (كـ«اطبع وصلاً») — الصفّ كلّه هو الزرّ
                control: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _picked.contains(g.key),
                      onChanged: (_) {},
                      activeColor: AppColors.brand,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (!_valid) Text('اختر نوعاً واحداً على الأقلّ، أو فعّل «كلّ الرسائل».', style: AppType.micro(color: AppColors.error)),
          ],
          const SizedBox(height: Sp.md),
          TextField(
            key: const ValueKey('mx-note'),
            controller: _note,
            maxLength: 200,
            maxLines: 1,
            onChanged: (_) => setState(() {}),
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: 'ملاحظة (اختياريّ) — مثلاً: طلب عدم الإزعاج',
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
            ),
          ),
          if (canAllow) ...[
            const SizedBox(height: Sp.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('mx-allow'),
                onPressed: _busy ? null : _allow,
                style: TextButton.styleFrom(foregroundColor: AppColors.success),
                icon: const Icon(LucideIcons.bellRing, size: 16),
                label: Text(_bulk ? 'السماح بالرسائل لمن أُوقفت عنه منهم' : 'السماح بالرسائل — تعود تصله'),
              ),
            ),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: existing ? 'حفظ' : (_bulk ? 'إيقاف الرسائل عنهم' : 'إيقاف الرسائل'),
        icon: LucideIcons.check,
        busy: _busy,
        enabled: _valid && _changed,
        onPressed: _save,
      ),
    );
  }
}
