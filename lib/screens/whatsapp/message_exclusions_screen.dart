import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/message_exclusions_api.dart';
import '../../services/merged_mode.dart';
import '../../widgets/company_tag.dart';
import '../desktop/desk_widgets.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/widgets/message_exclusion_card.dart';
import '../../services/employee_visibility.dart';

/// صفٌّ في القائمة: المستثنى، وشركته في «كل الشركات» (مفتاحها؛ null = الصفحة المفتوحة)، وهل يُدار فيها.
typedef _MxRow = ({MxEntry entry, String? companyKey, bool canManage});

/// «المستثنون من الرسائل» (المالك ١٤ نوفمبر: «نسوي مثل القسم الريجكتد مسج، يعني ذولا ما تروح لهم رسائل»): قائمة من أوقف الوكيل
/// رسائل النظام عنهم — ما أُوقف لكلٍّ، ملاحظته، من أوقفها ومتى؛ بحثٌ، تعديلٌ، و«السماح بالرسائل». الإضافة من صفحة المشترك
/// («المزيد» ثمّ «إيقاف الرسائل») أو من شريط تحديد المشتركين. الحال في [MessageExclusionsState] (تتشاركه القائمة وصفحة المشترك).
///
/// «كل الشركات» (١٥ نوفمبر — المالك: «نعم هم سويها»): مستثنو كلّ الشركات معاً، كلٌّ باسم شركته — والتعديل والسماح لشركة الصفّ
/// نفسها (المسار ذو الرقم بغلافها). الوضع العاديّ كما كان: قائمة الصفحة المفتوحة.
class MessageExclusionsScreen extends StatefulWidget {
  const MessageExclusionsScreen({super.key});

  @override
  State<MessageExclusionsScreen> createState() => _MessageExclusionsScreenState();
}

class _MessageExclusionsScreenState extends State<MessageExclusionsScreen> {
  final TextEditingController _search = TextEditingController();
  String? _removing;

  /// انتهت أوّل قراءة (نجحت أم تعذّرت) — قبلها دائرة التحميل، وبعدها بلا قائمةٍ «تعذّر» لا دائرةٌ أبديّة.
  bool _settled = false;

  /// مجموع ما يسمعه الرسم: الحال، ودخول «كل الشركات»/خروجه، وشركاته.
  late final Listenable _listen = Listenable.merge([MessageExclusionsState.changes, MergedMode.active, MergedMode.data]);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh().whenComplete(() {
      if (mounted) setState(() => _settled = true);
    }));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// شركات «كل الشركات» التي تُقرأ قوائمها (السليمة التي يخدمها التطبيق) — null في الوضع العاديّ (الصفحة المفتوحة وحدها).
  List<String>? get _keys => MergedMode.active.value ? [for (final c in MergedMode.usable) c.key] : null;

  Future<void> _refresh() {
    final keys = _keys;
    return keys == null ? MessageExclusionsState.ensureFresh(force: true) : MessageExclusionsState.ensureCompanies(keys, force: true);
  }

  static String _id(_MxRow r) => r.companyKey == null ? r.entry.username : '${r.companyKey}|${r.entry.username}';

  /// صفوف ما قُرئ: الأحدث أوّلاً، ثمّ البحث (بالاسم واليوزر والرقم والملاحظة والنوع — واسم الشركة في «كل الشركات»).
  List<_MxRow> _rows(List<({String? key, MxSnapshot snap})> view) {
    final all = <_MxRow>[
      for (final v in view)
        if (v.snap.enabled)
          for (final e in v.snap.entries.values)
            (
              entry: e,
              companyKey: v.key,
              // «كل الصفحات» للموظّف: صفحةٌ موقوفة الكتابة ⇒ صفوفها للعرض (الخادم يرفضها على كلّ حال)
              canManage: v.snap.canManage && MergedOps.writeLockAt(v.key) == null,
            ),
    ]..sort((a, b) => (b.entry.at ?? DateTime(2000)).compareTo(a.entry.at ?? DateTime(2000)));
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((r) {
      final e = r.entry;
      final co = r.companyKey == null ? '' : (MergedMode.companyOf(r.companyKey)?.name ?? '');
      return [e.username, e.name ?? '', e.phone ?? '', e.note ?? '', e.label, co].any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _edit(_MxRow row) async {
    final e = row.entry;
    await showMessageExclusionSheet(
      context,
      subject: MxSubject(username: e.username, idx: e.idx),
      title: !Sees.usernames ? Sees.nameOf(e.name, e.username) : (e.name == null ? e.username : '${e.name} — ${e.username}'),
      companyKey: row.companyKey,
    );
  }

  Future<void> _allow(_MxRow row) async {
    if (_removing != null) return;
    final e = row.entry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('السماح بالرسائل', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text('تعود رسائل النظام تصل «${MergedOps.withCompany(e.display, row.companyKey)}»؟', style: AppType.body(color: AppColors.textHi)),
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
    setState(() => _removing = _id(row));
    final r = await _allowRow(row);
    if (!mounted) return;
    setState(() => _removing = null);
    showSheetSnack(context, r.ok ? 'عادت تصله الرسائل' : (r.message ?? 'تعذّر الحفظ'), isError: !r.ok);
  }

  /// الصفحة المفتوحة كما كانت (المسار بلا رقم)؛ وصفّ شركةٍ في «كل الشركات» بالمسار ذي الرقم بغلاف شركته (مرجع نافذته أوّلاً).
  Future<({bool ok, String? message})> _allowRow(_MxRow row) async {
    final e = row.entry;
    if (row.companyKey == null) return MessageExclusionsState.remove(e.username);
    final idx = MessageExclusionsApi.routedIdx(e.idx);
    if (idx == null) return (ok: false, message: MessageExclusionsApi.noRoutedIdx);
    final r = await MergedOps.writeAt(row.companyKey, idx, () => MessageExclusionsApi.removeAt(idx, e.username));
    if (r.ok) MessageExclusionsState.applySavedFor(row.companyKey, e.username, null);
    return r;
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
        child: ListenableBuilder(
          listenable: _listen,
          builder: (context, _) {
            final keys = _keys;
            final merged = keys != null;
            final view = MessageExclusionsState.viewFor(keys);
            if (view.isEmpty && !_settled) {
              return const Center(child: CircularProgressIndicator());
            }
            final enabled = view.any((v) => v.snap.enabled);
            final count = view.fold<int>(0, (n, v) => n + (v.snap.enabled ? v.snap.count : 0));
            final rows = enabled ? _rows(view) : const <_MxRow>[];
            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  Text(
                    'مشتركون لا تصلهم رسائل النظام — كلّها أو أنواعٌ منها. للإضافة: افتح المشترك ثمّ «المزيد» ثمّ «إيقاف الرسائل»، '
                    'أو حدّد عدّة مشتركين واضغط الجرس المشطوب.',
                    style: AppType.muted(),
                  ),
                  if (merged) ...[
                    const SizedBox(height: 4),
                    Text('«كل الشركات»: مستثنو شركاتك معاً — كلٌّ باسم شركته.', key: const ValueKey('mx-merged-note'), style: AppType.muted()),
                  ],
                  const SizedBox(height: Sp.md),
                  if (view.isEmpty)
                    _empty('تعذّر جلب القائمة الآن — اسحب للتحديث.')
                  else if (!enabled)
                    _empty('هذه الميزة لم تُفتح لحسابك بعد.')
                  else if (count == 0)
                    _empty('لا أحد مستثنى — الرسائل تصل للجميع.')
                  else ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.pill)),
                          child: Text('$count مستثنى', style: AppType.micro(color: AppColors.textMid)),
                        ),
                      ],
                    ),
                    if (count > 6) ...[
                      const SizedBox(height: Sp.sm),
                      TextField(
                        key: const ValueKey('mx-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        style: AppType.input(color: AppColors.textHi),
                        decoration: InputDecoration(
                          hintText: merged ? 'بحث بالاسم أو اليوزر أو الرقم أو الشركة' : 'بحث بالاسم أو اليوزر أو الرقم',
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
                      for (final r in rows) ...[
                        _tile(r),
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

  Widget _tile(_MxRow row) {
    final e = row.entry;
    final id = _id(row);
    final meta = [
      if (e.by != null) e.by!,
      if (e.at != null) _when(e.at!),
    ].join(' · ');
    final labels = e.label.split('، ');
    return Container(
      key: ValueKey('mx-row-$id'),
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
                // «كل الشركات»: شركة المستثنى (نقطتها بلونها واسمها — كصفوف القائمة المدموجة)
                if (row.companyKey != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: CompanyTag(key: ValueKey('mx-co-$id'), companyKey: row.companyKey!),
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
          if (row.canManage) ...[
            IconButton(
              key: ValueKey('mx-edit-$id'),
              tooltip: 'تعديل',
              visualDensity: VisualDensity.compact,
              onPressed: _removing != null ? null : () => _edit(row),
              icon: Icon(LucideIcons.pencil, size: 17, color: AppColors.brandAccent),
            ),
            IconButton(
              key: ValueKey('mx-allow-$id'),
              tooltip: 'السماح بالرسائل',
              visualDensity: VisualDensity.compact,
              onPressed: _removing != null ? null : () => _allow(row),
              icon: _removing == id
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(LucideIcons.bellRing, size: 17, color: AppColors.success),
            ),
          ],
        ],
      ),
    );
  }
}
