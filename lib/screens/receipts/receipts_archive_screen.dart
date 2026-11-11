import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/big_subscribers_api.dart';
import '../../api/receipts_archive_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/print_feedback.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/list_kit.dart';
import '../../widgets/merged_section.dart';
import '../desktop/desk_widgets.dart';

/// «أرشيف الوصولات» (١١ نوفمبر ٢٠٢٦ — المالك: «مرّات المدراء ينسون طباعته أو يفقدونه، بحيث يبحث على رقم الوصل أو اسم المشترك
/// ويقدر يعيد طباعته»).
///
/// القائمة = كلّ تفعيلٍ وتمديدٍ وتسديد ومعه وصله: ما طُبع يُعاد برقمه وتاريخه («نسخة»)، وما لم يُطبع يُطبع الآن فيأخذ رقماً
/// ويُحفظ. بحثٌ واحد «رقم الوصل أو اسم المشترك» — سطر العمليّة في الخادم بلا اسم المشترك، فالاسم (عرضاً وبحثاً) من قائمة
/// المشتركين هنا: يوزرات من طابق الاسم تُرسل للخادم. الموظّف بلا «عرض المشتركين» يراها مقفلةً في «قوائم أخرى».
class ReceiptsArchiveScreen extends StatefulWidget {
  const ReceiptsArchiveScreen({super.key});

  static const title = 'أرشيف الوصولات';

  /// «كل الشركات»: وصولات الشركة المختارة في الشريط بمكانها — القائمة والإصدار والإعادة موجَّهة لها (الخادم:
  /// receipts-archive · receipt-issue/reprint).
  static Widget mergedPage() => const MergedSection(
      prefixes: ['/api/printed-receipts'],
      perms: ['subscribers.view'],
      lockTitle: title,
      child: ReceiptsArchiveScreen());

  @override
  State<ReceiptsArchiveScreen> createState() => _ReceiptsArchiveScreenState();
}

/// المدّة: أيّام، أو null لكلّ المدّة.
const _spans = <(int?, String)>[
  (7, 'آخر ٧ أيّام'),
  (30, 'آخر ٣٠ يوماً'),
  (90, 'آخر ٩٠ يوماً'),
  (180, 'آخر ٦ أشهر'),
  (null, 'كلّ المدّة'),
];

const _types = <(ArchiveOp?, String)>[
  (null, 'كلّ الأنواع'),
  (ArchiveOp.activate, 'تفعيل'),
  (ArchiveOp.extend, 'تمديد'),
  (ArchiveOp.payDebt, 'تسديد دين'),
];

/// «2026-11-11 21:43» بتوقيت بغداد مهما كانت منطقة الجهاز (كالوصل نفسه).
String archiveStamp(DateTime at) => intl.DateFormat('yyyy-MM-dd HH:mm', 'en_US').format(at.toUtc().add(const Duration(hours: 3)));

String _iqd(num n) => '${formatIQD(n)} د.ع';

IconData _iconOf(ArchiveOp t) => switch (t) {
      ArchiveOp.activate => LucideIcons.zap,
      ArchiveOp.extend => LucideIcons.calendarPlus,
      ArchiveOp.payDebt => LucideIcons.banknote,
      ArchiveOp.addDebt => LucideIcons.arrowDownToLine,
    };

ListTone _toneOf(ArchiveOp t) => switch (t) {
      ArchiveOp.activate => ListTone.brand,
      ArchiveOp.extend => ListTone.info,
      ArchiveOp.payDebt => ListTone.success,
      ArchiveOp.addDebt => ListTone.warning,
    };

class _ReceiptsArchiveScreenState extends State<ReceiptsArchiveScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  ArchiveState _state = ArchiveState.all;
  ArchiveOp? _type;
  int? _spanDays = 30;

  List<ArchiveItem> _items = const [];
  String? _next;
  bool _available = true;
  bool _ownOnly = false;
  bool _loading = true;
  bool _more = false;
  String? _error;
  String? _busyKey;

  /// رقم الطلب الجاري — ردٌّ أقدم (بحثٌ سبقه آخر) يُهمَل.
  int _seq = 0;

  /// شركة القسم لحظة فتحه («كل الشركات») — null: المفتوحة.
  String? _companyKey;
  bool _companyRead = false;

  /// مشتركو الشركة المفتوحة باليوزر (للاسم عرضاً وبحثاً). فارغٌ لحسابٍ كبير أو لشركةٍ غير المفتوحة.
  Map<String, Subscriber> _known = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_companyRead) return;
    _companyRead = true;
    _companyKey = MergedSection.routeKeyOf(context);
    _loadNames();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// قائمة المشتركين من الذاكرة ثمّ الشبكة — للشركة المفتوحة وحدها (قائمة شركةٍ أخرى لا تُكتب فوق كاش المفتوحة).
  Future<void> _loadNames() async {
    if (_companyKey != null) return;
    final list = SubscribersApi.knownList() ?? await SubscribersApi.loadAll();
    if (!mounted || list == null) return;
    setState(() => _known = {for (final s in list) s.username.toLowerCase(): s});
  }

  Subscriber? _subOf(ArchiveItem it) => it.username == null ? null : _known[it.username!.toLowerCase()];

  String _nameOf(ArchiveItem it) {
    final n = (it.name ?? '').trim();
    if (n.isNotEmpty) return n;
    final s = _subOf(it);
    final f = s?.fullName.trim() ?? '';
    return f == it.username ? '' : f;
  }

  /// يوزرات من طابق اسمه أو هاتفه نصَّ البحث: من القائمة المخبّأة، وللحساب الكبير من بحث الساس (صفحةٌ واحدة).
  Future<List<String>> _usersFor(String q) async {
    if (q.trim().length < 2 || _companyKey != null) return const [];
    if (_known.isNotEmpty) {
      return archiveUsersMatching(
          _known.values.map((s) => (username: s.username, name: s.fullName, phone: s.displayPhone)), q);
    }
    if (!BigSubscribersApi.knownBig) return const [];
    try {
      final page = await BigSubscribersApi.page(page: 1, size: 50, tab: 'all', query: q);
      if (mounted && page.rows.isNotEmpty) {
        setState(() => _known = {..._known, for (final s in page.rows) s.username.toLowerCase(): s});
      }
      return [for (final s in page.rows) if (s.username.isNotEmpty) s.username];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final q = _search.text.trim();
    final users = await _usersFor(q);
    if (!mounted || seq != _seq) return;
    final r = await ReceiptsArchiveApi.page(
        companyKey: _companyKey, query: q, users: users, type: _type, state: _state, spanDays: _spanDays);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      final p = r.page;
      if (p == null) {
        _error = r.error ?? 'تعذّر تحميل الوصولات الآن';
        _items = const [];
        _next = null;
        return;
      }
      _available = p.available;
      _ownOnly = p.ownOnly;
      _items = p.items;
      _next = p.next;
    });
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _more || _loading) return;
    final seq = _seq;
    setState(() => _more = true);
    final q = _search.text.trim();
    final users = await _usersFor(q);
    final r = await ReceiptsArchiveApi.page(
        companyKey: _companyKey, query: q, users: users, type: _type, state: _state, spanDays: _spanDays, cursor: cursor);
    if (!mounted || seq != _seq) return;
    setState(() {
      _more = false;
      final p = r.page;
      if (p == null) return;
      final have = {for (final i in _items) i.key};
      _items = [..._items, for (final i in p.items) if (!have.contains(i.key)) i];
      _next = p.next;
    });
    if (r.page == null && mounted) showSheetSnack(context, r.error ?? 'تعذّر تحميل المزيد', isError: true);
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void _set(VoidCallback change) {
    setState(change);
    _reload();
  }

  /// يطبع وصل الصفّ: المؤرشف يُعاد («نسخة»)، وغير المطبوع يصدر الآن برقمه — ثمّ يُحدَّث الصفّ بمكانه.
  Future<void> _print(ArchiveItem it) async {
    if (_busyKey != null) return;
    final blocked = it.blockedReason;
    if (blocked != null) {
      showSheetSnack(context, blocked, isError: true);
      return;
    }
    setState(() => _busyKey = it.key);
    final key = _companyKey;
    final s = _subOf(it);
    final reply = it.printed
        ? await ReceiptsArchiveApi.reprint(companyKey: key, receiptId: it.receiptId!)
        : await ReceiptsArchiveApi.issue(
            companyKey: key,
            activityId: it.activityId!,
            hint: s == null
                ? null
                : ArchiveHint(
                    name: s.fullName.trim(),
                    phone: s.displayPhone.trim(),
                    expiration: s.expiration,
                    packageName: s.profileName,
                  ),
          );
    if (!mounted) return;
    final receipt = reply.receipt;
    if (receipt == null) {
      setState(() => _busyKey = null);
      showSheetSnack(context, reply.message ?? 'تعذّرت الطباعة — أعد المحاولة', isError: true);
      return;
    }
    // الصفّ صار له وصل (أو زاد عدّ إعادته) — قبل الطباعة: الرقم حُجز في الخادم ولو أُلغيت نافذة الطباعة
    setState(() => _items = [for (final i in _items) i.key == it.key ? i.afterPrint(receipt) : i]);
    final result = await ReceiptService.printArchived(receipt);
    if (!mounted) return;
    setState(() => _busyKey = null);
    await showPrintResult(context, result);
  }

  Future<void> _open(ArchiveItem it) async {
    final go = await showReceiptArchiveSheet(context, it, name: _nameOf(it));
    if (go == true && mounted) {
      // الصفّ كما هو الآن في القائمة (قد يكون طُبع وهذه النافذة مفتوحة)
      final now = _items.firstWhere((i) => i.key == it.key, orElse: () => it);
      await _print(now);
    }
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
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text(ReceiptsArchiveScreen.title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: ReceiptsArchiveScreen.title,
      ),
      body: MergedSectionBody(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              ListSearchField(controller: _search, hint: 'رقم الوصل أو اسم المشترك', onChanged: _onSearch),
              const SizedBox(height: Sp.sm),
              _filters(),
              if (_ownOnly) ...[
                const SizedBox(height: Sp.sm),
                Text('تظهر لك عمليّاتك وما طبعته أنت.', style: AppType.micro(color: AppColors.textMid)),
              ],
              const SizedBox(height: Sp.md),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    final typeLabel = _types.firstWhere((t) => t.$1 == _type).$2;
    final spanLabel = _spans.firstWhere((s) => s.$1 == _spanDays).$2;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ListFilterChip(label: 'الكلّ', active: _state == ArchiveState.all, onTap: () => _set(() => _state = ArchiveState.all)),
          const SizedBox(width: Sp.xs),
          ListFilterChip(
              label: 'لم تُطبع',
              tone: ListTone.warning,
              active: _state == ArchiveState.unprinted,
              onTap: () => _set(() => _state = ArchiveState.unprinted)),
          const SizedBox(width: Sp.xs),
          ListFilterChip(
              label: 'المطبوعة',
              tone: ListTone.success,
              active: _state == ArchiveState.printed,
              onTap: () => _set(() => _state = ArchiveState.printed)),
          const SizedBox(width: Sp.sm),
          _MenuChip<ArchiveOp?>(
            key: const ValueKey('archive-type'),
            label: typeLabel,
            active: _type != null,
            options: _types,
            onPick: (v) => _set(() => _type = v),
          ),
          const SizedBox(width: Sp.xs),
          _MenuChip<int?>(
            key: const ValueKey('archive-span'),
            label: spanLabel,
            active: false,
            options: _spans,
            onPick: (v) => _set(() => _spanDays = v),
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (_loading && _items.isEmpty) {
      return const [Padding(padding: EdgeInsets.only(top: Sp.huge), child: Center(child: CircularProgressIndicator()))];
    }
    if (_error != null) {
      return [ListEmptyNote(icon: LucideIcons.wifiOff, title: _error!, hint: 'اسحب للأسفل لإعادة المحاولة')];
    }
    if (!_available) {
      return const [ListEmptyNote(icon: LucideIcons.receiptText, title: '«أرشيف الوصولات» غير مفعّل لهذا الحساب بعد')];
    }
    if (_items.isEmpty) {
      if (_search.text.trim().isNotEmpty) {
        return const [
          ListEmptyNote(icon: LucideIcons.search, title: 'لا نتيجة', hint: 'جرّب رقم الوصل أو يوزر المشترك أو اسمه، أو وسّع المدّة'),
        ];
      }
      return [
        _state == ArchiveState.unprinted
            ? const ListEmptyNote(icon: LucideIcons.receiptText, title: 'كلّ عمليّات هذه المدّة مطبوعة')
            : const ListEmptyNote(
                icon: LucideIcons.receiptText,
                title: 'لا عمليّات في هذه المدّة',
                hint: 'كلّ تفعيلٍ أو تمديدٍ أو تسديد يظهر هنا — طُبع وصله أم لا'),
      ];
    }
    return [
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
              ArchiveRowTile(
                item: _items[i],
                name: _nameOf(_items[i]),
                busy: _busyKey == _items[i].key,
                onTap: () => _open(_items[i]),
                onPrint: _busyKey == null ? () => _print(_items[i]) : null,
              ),
            ],
          ],
        ),
      ),
      if (_next != null) ...[
        const SizedBox(height: Sp.md),
        Center(
          child: OutlinedButton(
            onPressed: _more ? null : _loadMore,
            child: Text(_more ? 'جاري التحميل…' : 'تحميل المزيد'),
          ),
        ),
      ],
    ];
  }
}

/// شريحةٌ تفتح قائمة اختيارٍ قصيرة (النوع، المدّة) — بشكل شرائح التصفية نفسه.
class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({super.key, required this.label, required this.active, required this.options, required this.onPick});
  final String label;
  final bool active;
  final List<(T, String)> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = active ? AppColors.brand : AppColors.textBody;
    final radius = BorderRadius.circular(R.pill);
    return PopupMenuButton<int>(
      tooltip: label,
      color: AppColors.surface,
      onSelected: (i) => onPick(options[i].$1),
      itemBuilder: (_) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem<int>(value: i, child: Text(options[i].$2, style: AppType.label(color: AppColors.textHi))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: H.chip),
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        decoration: BoxDecoration(
          color: active ? AppColors.brandSoftBg : AppColors.surface,
          borderRadius: radius,
          border: Border.all(color: active ? AppColors.brandSoftBorder : AppColors.border, width: active ? BW.selected : BW.normal),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppType.labelBold(color: fg)),
            const SizedBox(width: Sp.xs),
            Icon(LucideIcons.chevronDown, size: 14, color: fg),
          ],
        ),
      ),
    );
  }
}

/// شارةٌ صغيرة بلون عائلتها («No. 00012» · «لم يُطبع» · «ملغى»).
class _Tag extends StatelessWidget {
  const _Tag(this.text, this.tone, {this.ltr = false});
  final String text;
  final ListTone? tone;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: t == null ? AppColors.surfaceSunken : t.soft,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(text,
          textDirection: ltr ? TextDirection.ltr : null,
          style: AppType.pillBold(color: t == null ? AppColors.textMid : t.fg)),
    );
  }
}

/// «No. 00012» (وعدد الإعادات) لما طُبع، و«لم يُطبع» لغيره.
List<Widget> archiveReceiptTags(ArchiveItem it) => [
      if (!it.printed)
        const _Tag('لم يُطبع', ListTone.warning)
      else ...[
        _Tag(it.receiptNo == null ? 'No. —' : 'No. ${it.receiptNo.toString().padLeft(5, '0')}', ListTone.success, ltr: true),
        if (it.reprints > 0) _Tag('أُعيد ${it.reprints}', null),
      ],
    ];

/// صفّ عمليّةٍ ووصلها: [أيقونة النوع] الاسم · العمليّة والمبلغ · رقم الوصل والتاريخ … [طباعة].
class ArchiveRowTile extends StatelessWidget {
  const ArchiveRowTile({super.key, required this.item, required this.name, required this.onTap, required this.onPrint, this.busy = false});
  final ArchiveItem item;

  /// اسم المشترك إن عُرف (من الوصل أو قائمة المشتركين) — وإلّا يُعرض اليوزر.
  final String name;
  final VoidCallback onTap;

  /// null: طباعةٌ أخرى جارية.
  final VoidCallback? onPrint;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = item;
    final title = name.isNotEmpty ? name : (it.username ?? '—');
    final blocked = it.blockedReason != null;
    // المبلغ قبل اسم الباقة: السطر يُقصّ من آخره — فيُقصّ الاسم الطويل لا المبلغ
    final facts = isoJoin([
      it.type.label,
      if (it.amount != null) _iqd(it.amount!),
      if ((it.package ?? '').isNotEmpty) it.package!,
    ], ' · ');
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, 10, Sp.xs, 10),
          child: Row(
            children: [
              ListIconBox(icon: _iconOf(it.type), tone: it.voided ? ListTone.danger : _toneOf(it.type)),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitle(color: AppColors.textHi)),
                      ),
                      if (it.voided) ...[const SizedBox(width: Sp.xs), const _Tag('ملغى', ListTone.danger)],
                    ]),
                    const SizedBox(height: 2),
                    Text(facts, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                    const SizedBox(height: Sp.xs),
                    Wrap(
                      spacing: Sp.xs,
                      runSpacing: Sp.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...archiveReceiptTags(it),
                        Text(archiveStamp(it.at),
                            textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textLow)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: busy
                    ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        tooltip: it.printed ? 'إعادة طباعة الوصل' : 'طباعة الوصل',
                        onPressed: blocked ? null : onPrint,
                        icon: Icon(LucideIcons.printer,
                            size: 20, color: blocked ? AppColors.textHint : (it.printed ? AppColors.textBody : AppColors.brand)),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// نافذة تفاصيل الصفّ — تُرجع `true` حين يطلب المدير الطباعة (الشاشة تنفّذها وتحدّث صفّها).
Future<bool?> showReceiptArchiveSheet(BuildContext context, ArchiveItem item, {required String name}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _ArchiveSheet(item: item, name: name),
  );
}

class _ArchiveSheet extends StatelessWidget {
  const _ArchiveSheet({required this.item, required this.name});
  final ArchiveItem item;
  final String name;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = item;
    final blocked = it.blockedReason;
    final nb = it.newBalance;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.receiptText,
        title: it.printed ? 'وصل ${it.type.label}' : '${it.type.label} — لم يُطبع وصله',
        subtitle: blocked != null
            ? 'للعرض فقط.'
            : it.printed
                ? 'يُعاد بالرقم والتاريخ والمحتوى كما طُبع أوّل مرّة، وعليه «نسخة».'
                : 'يُطبع الآن بتاريخ العمليّة، فيأخذ رقماً ويُحفظ في الأرشيف.',
        onClose: () => Navigator.of(context).pop(false),
      ),
      footer: SheetFooterBar(
        label: it.printed ? 'إعادة طباعة' : 'طباعة الوصل',
        icon: LucideIcons.printer,
        enabled: blocked == null,
        onPressed: () => Navigator.of(context).pop(true),
        leading: SheetSecondaryButton(label: 'إغلاق', onTap: () => Navigator.of(context).pop(false)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetRowsGroup(rows: [
            // قيم الصفوف تُرسم LTR (للأرقام واليوزرات): النصّ العربيّ يُعزل فلا ينقلب ترتيبه
            SheetRowData(label: 'المشترك', value: iso(name.isNotEmpty ? name : (it.username ?? '—')), strong: true),
            if (name.isNotEmpty && (it.username ?? '').isNotEmpty) SheetRowData(label: 'اسم المستخدم', value: it.username!),
            if ((it.phone ?? '').isNotEmpty) SheetRowData(label: 'الهاتف', value: it.phone!),
            SheetRowData(label: 'تاريخ العمليّة', value: archiveStamp(it.at)),
            if ((it.package ?? '').isNotEmpty) SheetRowData(label: 'الباقة', value: iso(it.package!)),
            if (it.amount != null)
              SheetRowData(label: it.type == ArchiveOp.payDebt ? 'المبلغ المسدَّد' : 'المبلغ', value: iso(_iqd(it.amount!)), strong: true),
            if (it.pay != null) SheetRowData(label: 'طريقة الدفع', value: iso(it.pay!.label)),
            if (it.partialAmount != null) SheetRowData(label: 'المدفوع نقداً', value: iso(_iqd(it.partialAmount!))),
            if (nb != null && nb != 0) SheetRowData(label: nb < 0 ? 'الدين بعدها' : 'الرصيد بعدها', value: iso(_iqd(nb.abs()))),
            if ((it.byUsername ?? '').isNotEmpty)
              SheetRowData(label: it.activityId != null ? 'نفّذها' : 'طبعه', value: it.byUsername!),
            SheetRowData(
              label: 'الوصل',
              value: it.printed
                  ? isoJoin([
                      it.receiptNo == null ? 'No. —' : 'No. ${it.receiptNo.toString().padLeft(5, '0')}',
                      if (it.reprints > 0) 'أُعيد ${it.reprints}',
                    ], ' · ')
                  : iso('لم يُطبع'),
              valueColor: it.printed ? AppColors.success : AppColors.warning,
            ),
            if (it.printed && it.printedAt != null)
              SheetRowData(label: it.late ? 'صدر من الأرشيف' : 'طُبع', value: archiveStamp(it.printedAt!)),
          ]),
          if (blocked != null) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: AppColors.dangerSoftBorder),
              ),
              child: Text(blocked, style: AppType.label(color: AppColors.error).copyWith(height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}
