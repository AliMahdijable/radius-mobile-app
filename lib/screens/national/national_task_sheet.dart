import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_labels.dart';
import 'national_ticket_write.dart';
import 'national_widgets.dart';

/// تفاصيل المهمّة وتعليقاتها، وتعليقات الطلب — والتعليق عليهما (المشروع الوطنيّ، ١ نوفمبر — «اقسام البوابة البقية… تكملها»).
/// كصفحة المهمّة في البوّابة: الحالة والتواريخ والمكلَّف والمشترك والتذكرة المرتبطة، ثمّ «التعليقات». التعليق يظهر حين يقول الخادم
/// `can.comment` (مفتاح الكتابة + المفتاح التجريبيّ + صلاحيّة البوّابة)، نداءٌ واحد بلا إعادة، و«غير مؤكَّد» يُعرض كما هو.
/// إغلاق المهمّة وإنشاء الطلبات خارج هذا الجزء (من البوّابة).

Future<void> showNationalTaskSheet(BuildContext context, NationalTask t) {
  return showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => NationalTaskSheet(row: t),
  );
}

class NationalTaskSheet extends StatefulWidget {
  const NationalTaskSheet({super.key, required this.row});
  final NationalTask row;

  @override
  State<NationalTaskSheet> createState() => _NationalTaskSheetState();
}

class _NationalTaskSheetState extends State<NationalTaskSheet> {
  NationalTaskDetail? _d;
  String? _error;
  NationalLock? _lock;

  /// سببا قفل التعليقات وإضافتها الجاهزان من الخادم (`portal_locks.task_comments` / `task_comment_add`) — إن وُجدا.
  String? _commentsWhy;
  String? _addWhy;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _load();
    NationalSheetApi.beta().then((b) {
      if (!mounted || b == null) return;
      setState(() {
        _commentsWhy = b.lockOf('task_comments');
        _addWhy = b.lockOf('task_comment_add');
      });
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final r = await NationalSheetApi.task(widget.row.id!);
    if (!mounted) return;
    if (r.locked) {
      setState(() {
        _lock = r.lock;
        _error = null;
      });
      return;
    }
    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    if (r.data == null) {
      // الخادم ما زال يجلبها من البوّابة: اسأل ثانيةً (حتى دقيقة)
      if (_polls++ < 15) _poll = Timer(const Duration(seconds: 4), _load);
      return;
    }
    setState(() {
      _d = r.data;
      _error = null;
      _lock = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final d = _d;
    final row = widget.row;
    final st = nationalTaskStatus(d?.status.isNotEmpty == true ? d!.status : row.status);
    final title = nationalTaskTitle(d != null && d.label.isNotEmpty ? d.label : row.title);
    final customer = (d?.customer ?? row.customer)?.name;
    final Widget body;
    if (_lock != null) {
      body = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (_error != null) {
      body = NationalStateBox.error(text: _error!, onRetry: () {
        setState(() => _error = null);
        _load();
      });
    } else if (d == null) {
      body = const NationalStateBox.loading();
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.status.isNotEmpty || row.status.isNotEmpty)
            Align(alignment: AlignmentDirectional.centerStart, child: ToneChip(label: st.label, tone: st.tone)),
          const SizedBox(height: Sp.md),
          NationalInfoGroup(children: [
            NationalInfoRow(icon: LucideIcons.user, label: 'المشترك', value: customer ?? '—'),
            if ((d.zone ?? row.zone)?.name.isNotEmpty == true)
              NationalInfoRow(icon: LucideIcons.mapPin, label: 'الزون', value: (d.zone ?? row.zone)!.name, ltr: true),
            if (d.address != null) NationalInfoRow(icon: LucideIcons.house, label: 'العنوان', value: d.address!),
            NationalInfoRow(icon: LucideIcons.clock, label: 'أُنشئت', value: nationalTime(d.createdAt), ltr: true),
            if (d.modifiedAt != null) NationalInfoRow(icon: LucideIcons.refreshCw, label: 'آخر تحديث', value: nationalTime(d.modifiedAt), ltr: true),
            if (d.closedAt != null) NationalInfoRow(icon: LucideIcons.calendarCheck, label: 'أُغلقت', value: nationalTime(d.closedAt), ltr: true),
            if (d.ticket != null)
              NationalInfoRow(
                icon: LucideIcons.headset,
                label: 'تذكرة مرتبطة',
                value: d.ticket!.name.isNotEmpty ? d.ticket!.name : (d.ticket!.id ?? '—'),
                ltr: true,
              ),
          ]),
          if (d.description != null) ...[
            const SizedBox(height: Sp.lg),
            Text('الوصف', style: AppType.label(color: AppColors.textLabel)),
            const SizedBox(height: Sp.sm),
            SelectableText(d.description!, style: AppType.body(color: AppColors.textBody)),
          ],
          const SizedBox(height: Sp.lg),
          _CommentsTitle(total: d.commentsTotal ?? d.comments?.length),
          const SizedBox(height: Sp.sm),
          if (d.commentsLocked)
            NationalPortalLockBox(
              text: _commentsWhy ?? 'المستخدم الذي دخلت به في المشروع الوطني لا يملك صلاحيّة «تعليقات المهامّ» في البوّابة',
            )
          else
            NationalCommentList(comments: d.comments, emptyText: 'لا توجد تعليقات على المهمّة حتى الآن.'),
          if (d.canComment) ...[
            const SizedBox(height: Sp.sm),
            NationalCommentBox.to(send: (text) => NationalSheetApi.commentTask(row.id!, text), onSent: _load),
          ] else if (_addWhy != null) ...[
            // التعليق مقفلٌ بمكانه بسببه (صلاحيّة البوّابة) — لا يختفي بلا تفسير
            const SizedBox(height: Sp.sm),
            NationalPortalLockBox(title: 'إضافة تعليق', text: _addWhy!),
          ],
        ],
      );
    }
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.clipboardList,
        title: title,
        subtitle: customer ?? 'مهمّة',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: body,
    );
  }
}

class _CommentsTitle extends StatelessWidget {
  const _CommentsTitle({this.total});
  final int? total;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Text(total == null || total == 0 ? 'التعليقات' : 'التعليقات ($total)', style: AppType.label(color: AppColors.textLabel));
  }
}

/// تعليقاتٌ بالترتيب الذي يرسله الخادم: الكاتب ووقته ثمّ النصّ. null = تعذّر جلبها الآن (لا «لا تعليقات» كاذبة).
class NationalCommentList extends StatelessWidget {
  const NationalCommentList({super.key, required this.comments, required this.emptyText});
  final List<NationalComment>? comments;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final cs = comments;
    if (cs == null) return Text('تعذّر جلب التعليقات الآن.', style: AppType.muted());
    if (cs.isEmpty) return Text(emptyText, style: AppType.muted());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in cs) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.by.isEmpty ? '—' : c.by, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
                    ),
                    Text(nationalTime(c.at), textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(c.text.isEmpty ? '—' : c.text, style: AppType.body(color: AppColors.textBody)),
              ],
            ),
          ),
          const SizedBox(height: Sp.sm),
        ],
      ],
    );
  }
}

/// «لا صلاحيّة في البوّابة» بمكان القسم: قفلٌ وعنوانه وسببه، بلا «إعادة» (لا تتغيّر بالمحاولة).
class NationalPortalLockBox extends StatelessWidget {
  const NationalPortalLockBox({super.key, this.title = 'لا صلاحيّة في البوّابة', required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.lock, size: 16, color: AppColors.textLow)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.label(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text(text, style: AppType.body(color: AppColors.textMid).copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «التعليقات» داخل ورقة الطلب (§6.3–§6.4): تُجلب مع فتح الورقة (بطيئةٌ عند البوّابة ~٩ث ⇒ «جارٍ» ثمّ تصل وحدها)، صفحةً صفحة،
/// والتعليق حين يقول الخادم `can.comment` — بنوع الطلب كما في صفّه (البوّابة تحتاجه).
class NationalRequestComments extends StatefulWidget {
  const NationalRequestComments({super.key, required this.requestId, required this.type});
  final String requestId;
  final String type;

  @override
  State<NationalRequestComments> createState() => _NationalRequestCommentsState();
}

class _NationalRequestCommentsState extends State<NationalRequestComments> {
  final _p = NationalPaged<NationalComment>();
  NationalLock? _lock;

  /// سبب قفل «إضافة تعليق» الجاهز من الخادم (`portal_locks.request_comment_add`) — إن وُجد.
  String? _addWhy;

  @override
  void initState() {
    super.initState();
    _next();
    NationalSheetApi.beta().then((b) {
      if (mounted && b != null) setState(() => _addWhy = b.lockOf('request_comment_add'));
    });
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _next() => _p.next(
        (page) async {
          final r = await NationalSheetApi.requestComments(widget.requestId, page: page);
          if (r.locked) {
            _lock = r.lock;
            return NationalResult.fail(r.lock!.message);
          }
          return r.ok ? NationalResult.ok(r.data) : NationalResult.fail(r.error, relogin: r.relogin);
        },
        onChange: _changed,
        alive: () => mounted,
      );

  void _reload() {
    _p.reset();
    _lock = null;
    setState(() {});
    _next();
  }

  bool get _canComment {
    final can = _p.raw['can'];
    return can is Map && can['comment'] == true;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final p = _p;
    final Widget list;
    if (_lock != null) {
      list = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (p.rows.isEmpty && p.error != null) {
      list = Row(
        children: [
          Expanded(child: Text(p.error!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.muted())),
          TextButton.icon(onPressed: _reload, icon: const Icon(LucideIcons.refreshCw, size: 15), label: const Text('إعادة')),
        ],
      );
    } else if (p.rows.isEmpty && (p.pending || p.loading || p.page == 0)) {
      list = Text(p.pending ? 'جارٍ جلب التعليقات من البوّابة…' : 'جارٍ التحميل…', style: AppType.muted());
    } else {
      list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NationalCommentList(comments: p.rows, emptyText: 'لا توجد تعليقات على الطلب حتى الآن.'),
          if (p.hasMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: p.loading ? null : _next,
                child: Text(p.total == null ? 'المزيد' : 'المزيد (${p.rows.length} من ${p.total})'),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CommentsTitle(total: _lock == null ? p.total : null),
        const SizedBox(height: Sp.sm),
        list,
        if (_lock == null && _canComment) ...[
          const SizedBox(height: Sp.sm),
          NationalCommentBox.to(send: (text) => NationalSheetApi.commentRequest(widget.requestId, widget.type, text), onSent: _reload),
        ] else if (_lock == null && _addWhy != null && p.page > 0) ...[
          const SizedBox(height: Sp.sm),
          NationalPortalLockBox(title: 'إضافة تعليق', text: _addWhy!),
        ],
      ],
    );
  }
}
