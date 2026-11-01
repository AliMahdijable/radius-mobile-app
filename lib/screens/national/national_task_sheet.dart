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

  /// سبب تعذّر الجلب: يحلّ محلّ الورقة قبل أن تُحمَّل وحده؛ بعدها (إعادة الجلب بعد تعليق) سطرٌ صغير بـ«إعادة» والتفاصيل باقية —
  /// «غير مؤكَّد» يعني أنّ البوّابة تعثّرت، فالجلب التالي يتعثّر غالباً أيضاً (مراجعة ١ نوفمبر: كان يمحو الورقة كلّها وتنبيهها).
  String? _error;
  NationalLock? _lock;

  /// «غير مؤكَّد» آخر تعليق — بحالة الورقة لا الصندوق، فيبقى بعد إعادة الجلب (وإن أُزيل الصندوق أو تعذّر الجلب) حتى إرسالٍ ناجح.
  String? _unconfirmed;

  /// سببا قفل التعليقات وإضافتها الجاهزان من الخادم (`portal_locks.task_comments` / `task_comment_add`) — إن وُجدا.
  String? _commentsWhy;
  String? _addWhy;
  Timer? _poll;
  int _polls = 0;

  /// ردُّ جلبٍ أقدم (سبقه جلبٌ أحدث: تعليقٌ ثمّ «إعادة») يُهمل.
  int _gen = 0;

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

  /// جلبٌ جديد (بعد تعليق، أو «إعادة»): بمهلة «جارٍ» كاملة من جديد.
  void _reload() {
    _polls = 0;
    _load();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final gen = ++_gen;
    final r = await NationalSheetApi.task(widget.row.id!);
    if (!mounted || gen != _gen) return;
    if (r.locked) {
      setState(() {
        _lock = r.lock;
        _error = null;
      });
      return;
    }
    if (!r.ok) {
      // الورقة المحمَّلة تبقى بتفاصيلها وتعليقاتها وصندوقها — الخطأ سطرٌ فوق التعليقات ([build])
      setState(() => _error = r.error ?? 'تعذّر تحديث المهمّة الآن — أعد المحاولة');
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
    final unconfirmed = _unconfirmed;
    final Widget body;
    if (_lock != null) {
      final lock = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
      body = unconfirmed == null
          ? lock
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [NationalUnconfirmedBox(text: unconfirmed), const SizedBox(height: Sp.sm), lock],
            );
    } else if (d == null && _error != null) {
      body = NationalStateBox.error(text: _error!, onRetry: () {
        setState(() => _error = null);
        _reload();
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
          if (_error != null) ...[
            _ReloadErrorRow(text: _error!, onRetry: () {
              setState(() => _error = null);
              _reload();
            }),
            const SizedBox(height: Sp.sm),
          ],
          if (unconfirmed != null) ...[
            NationalUnconfirmedBox(text: unconfirmed),
            const SizedBox(height: Sp.sm),
          ],
          if (d.commentsLocked)
            NationalPortalLockBox(
              text: _commentsWhy ?? 'المستخدم الذي دخلت به في المشروع الوطني لا يملك صلاحيّة «تعليقات المهامّ» في البوّابة',
            )
          else
            NationalCommentList(comments: d.comments, emptyText: 'لا توجد تعليقات على المهمّة حتى الآن.'),
          if (d.canComment) ...[
            const SizedBox(height: Sp.sm),
            NationalCommentBox.to(
              key: const ValueKey('national-task-comment-box'),
              send: (text) => NationalSheetApi.commentTask(row.id!, text),
              onSent: _reload,
              onUnconfirmed: (t) {
                if (mounted) setState(() => _unconfirmed = t);
              },
            ),
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

/// تعذّر جلبٌ بعد أن حُمّلت الورقة: سطرٌ صغير بـ«إعادة» — التفاصيل والتعليقات والصندوق باقية تحته.
class _ReloadErrorRow extends StatelessWidget {
  const _ReloadErrorRow({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Row(
      children: [
        Icon(LucideIcons.circleAlert, size: 16, color: AppColors.error),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid))),
        TextButton.icon(onPressed: onRetry, icon: const Icon(LucideIcons.refreshCw, size: 15), label: const Text('إعادة')),
      ],
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

  /// آخر `can.comment` عرفناه من ردٍّ كامل — لا يُصفَّر بإعادة الجلب ولا بـ«المزيد» (ردّ pending بلا `can`): كان الصندوق يختفي ثوانيَ
  /// الجلب البطيء (~٩ث) فيضيع ما كُتب فيه ومعه «غير مؤكَّد» (مراجعة ١ نوفمبر).
  bool _can = false;

  /// «غير مؤكَّد» آخر تعليق — بحالة القسم لا الصندوق، فوق القائمة، حتى إرسالٍ ناجح.
  String? _unconfirmed;

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
    // من الردّ الكامل وحده: ردّ «جارٍ» لا يحمل `can` فلا يغيّر آخر ما عُرف
    final can = _p.raw['can'];
    if (can is Map && can.containsKey('comment')) _can = can['comment'] == true;
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
          if (p.hasMore || p.error != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                // والصفحة التالية «جارٍ» (pending، تُسأل وحدها بعد ٤ث): لا نداءٌ ثانٍ لها؛ وفشلها «إعادة» بنصّه (مراجعة ١ نوفمبر)
                onPressed: p.loading || p.pending ? null : _next,
                child: Text(p.error != null
                    ? 'تعذّر جلب المزيد — إعادة'
                    : (p.total == null ? 'المزيد' : 'المزيد (${p.rows.length} من ${p.total})')),
              ),
            ),
        ],
      );
    }
    final unconfirmed = _unconfirmed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CommentsTitle(total: _lock == null ? p.total : null),
        const SizedBox(height: Sp.sm),
        if (unconfirmed != null) ...[
          NationalUnconfirmedBox(text: unconfirmed),
          const SizedBox(height: Sp.sm),
        ],
        list,
        if (_lock == null && _can) ...[
          const SizedBox(height: Sp.sm),
          NationalCommentBox.to(
            key: const ValueKey('national-request-comment-box'),
            send: (text) => NationalSheetApi.commentRequest(widget.requestId, widget.type, text),
            onSent: _reload,
            onUnconfirmed: (t) {
              if (mounted) setState(() => _unconfirmed = t);
            },
          ),
        ] else if (_lock == null && _addWhy != null && p.page > 0) ...[
          const SizedBox(height: Sp.sm),
          NationalPortalLockBox(title: 'إضافة تعليق', text: _addWhy!),
        ],
      ],
    );
  }
}
