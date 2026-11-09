import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/company_route.dart';
import '../../api/tickets_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/notification_router.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../subscribers/subscriber_detail_screen.dart';
import 'ticket_image.dart';
import 'ticket_widgets.dart';

/// محادثة تذكرة (المالك ٩ نوفمبر): رسائل المشترك والوكيل وأحداث الحالة، والردّ، وأزرار الحالة (قيد المعالجة · تمّ الحلّ · إغلاق ·
/// إعادة فتح). الموظّف يردّ ويغيّر الحالة بـ«التذاكر — الردّ» وحدها؛ «كل الشركات» لشركةٍ غير المفتوحة للعرض.
/// الصور (٩ نوفمبر): زرّ إرفاقٍ بجانب الردّ (الكاميرا أو المعرض، والحاسبة ملفٌّ من الجهاز) يضغطها (ticket_image.dart) ويعرضها
/// بزرّ إزالة قبل الإرسال، والنصّ اختياريٌّ معها؛ وصور المحادثة مصغّرةٌ في فقاعاتها وبالنقر ملء الشاشة.
class TicketThreadScreen extends StatefulWidget {
  const TicketThreadScreen(
      {super.key, required this.ticketId, this.initial, this.viewOnly = false, this.openCompany = false, this.companyKey});
  final int ticketId;

  /// ما عُرف من القائمة — يُرسم فوراً حتى تصل المحادثة.
  final Ticket? initial;

  /// «كل الشركات»: شركةٌ غير المفتوحة — قراءةٌ وحدها (لا ردّ ولا حالة ولا صفحة مشترك).
  final bool viewOnly;

  /// تذكرة الشركة المفتوحة (من الجرس أو الإشعار — ٩ نوفمبر): كلّ طلباتها لها صراحةً ([CompanyRoute.runOpen]) ولو بقي تحتها قسمٌ
  /// موجَّهٌ لشركةٍ أخرى ببادئةٍ تطابق (التذاكر أو «بوابة المشترك» على الحاسبة، أو صفحةٌ تحت الإشعار) — فلا تُقرأ ولا يُردّ عليها
  /// بشركةٍ غير شركتها.
  final bool openCompany;

  /// شركة المحادثة كما كانت لحظة فتحها من القائمة («كل الشركات»، ٩ نوفمبر — مراجعة 179): كلّ طلباتها — والقراءة الدوريّة —
  /// لها صراحةً (null = المفتوحة)، فلا تقرأ تذكرة شركةٍ أخرى برقمها إن أُخفي قسمها أو غطّته صفحةٌ وهي مفتوحة.
  final String? companyKey;

  /// قراءةٌ دوريّة ما دامت المحادثة مفتوحة (احتياطاً لإشعارٍ لم يصل). null في الاختبارات.
  @visibleForTesting
  static Duration? pollEvery = const Duration(seconds: 30);

  /// اختيار الصورة وضغطها — يُبدَّل في الاختبار.
  @visibleForTesting
  static TicketImagePicker pickImage = pickTicketImage;

  /// جلب صور الفقاعات — يُبدَّل في الاختبار (null = الخادم).
  @visibleForTesting
  static TicketImageLoader? imageLoader;

  @override
  State<TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends State<TicketThreadScreen> {
  Ticket? _ticket;
  List<TicketMessage> _messages = const [];
  bool _loading = true;
  bool _failed = false;
  bool _gone = false;
  String? _goneMessage;
  bool _sending = false;
  String? _busy;

  /// يرتفع مع كلّ ردٍّ أو تغيير حالة قبل إرساله — قراءةٌ بدأت قبله لقطتها أقدم منه ([_load]).
  int _writeGen = 0;
  Timer? _poll;
  final _ctl = TextEditingController();

  /// الصورة المختارة (مضغوطةً) قبل الإرسال، و«تجهيزها» أثناء الضغط.
  Uint8List? _attach;
  bool _preparing = false;

  bool get _canWrite => !widget.viewOnly && Perms.has('tickets.view') && Perms.has('tickets.reply');

  /// طلبٌ للتذكرة — لشركتها صراحةً: المفتوحة حين [TicketThreadScreen.openCompany]، وإلّا شركتها لحظة الفتح
  /// ([TicketThreadScreen.companyKey]؛ null = المفتوحة).
  Future<T> _api<T>(Future<T> Function() call) =>
      widget.openCompany ? CompanyRoute.runOpen(call) : CompanyRoute.pin(widget.companyKey, call);

  /// صور الفقاعات بالقاعدة نفسها (null = الافتراضيّ: الخادم كما هو).
  TicketImageLoader? get _imageLoader {
    final custom = TicketThreadScreen.imageLoader;
    final load = custom ?? TicketsApi.imageBytes;
    return (ticketId, messageId) => _api(() => load(ticketId, messageId));
  }

  @override
  void initState() {
    super.initState();
    _ticket = widget.initial;
    _load();
    final every = TicketThreadScreen.pollEvery;
    if (every != null) _poll = Timer.periodic(every, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (quiet && (_sending || _busy != null)) return;
    final gen = _writeGen;
    // كتابةٌ جاريةٌ لحظة بدء القراءة (السحب للتحديث أثناء الردّ أو «إغلاق»): الخادم قد يقرأ قبل حفظها ويصل ردّه بعد ردّها —
    // فلقطتها أقدم منها وإن لم يتغيّر العدّاد بعدها
    final writing = _sending || _busy != null;
    final r = await _api(() => TicketsApi.thread(widget.ticketId));
    if (!mounted) return;
    // ردٌّ أو تغيير حالةٍ بدأ أثناء هذه القراءة أو قبلها ولم ينتهِ: لقطتها قد تسبقه — الدوريّة تُسقَط (التالية تجلب الجديد)، واليدويّة
    // تضمّ رسائلها بالمعرّف ولا تُرجع التذكرة لحالها القديمة (كانت تمحو الردّ المُرسَل أو تعيد المغلقة مفتوحة حتى القراءة التالية).
    final stale = writing || gen != _writeGen || _sending || _busy != null;
    if (stale && quiet) return;
    final wasUnread = _ticket?.unread ?? true;
    setState(() {
      _loading = false;
      if (r.thread != null) {
        if (stale) {
          final fetched = r.thread!.messages;
          final ids = {for (final m in fetched) m.id};
          _messages = [...fetched, ..._messages.where((m) => !ids.contains(m.id))];
          _ticket ??= r.thread!.ticket;
        } else {
          _ticket = r.thread!.ticket;
          _messages = r.thread!.messages;
        }
        _failed = false;
        _gone = false;
      } else if (r.gone) {
        _gone = true;
        _goneMessage = r.message;
      } else if (!quiet) {
        _failed = true;
      }
    });
    // قُرئت ⇒ شارة «قوائم أخرى» تنقص (للمفتوحة وحدها — المعروضة للعرض لا تمسّ شارتها)
    if (r.thread != null && wasUnread && !widget.viewOnly) unawaited(TicketsState.ensureFresh(force: true));
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final text = _ctl.text.trim();
    final image = _attach;
    if ((text.isEmpty && image == null) || _sending || _preparing) return;
    if (text.characters.length > 2000) {
      _snack('الرسالة أطول من ٢٠٠٠ حرف');
      return;
    }
    _writeGen++;
    setState(() => _sending = true);
    final r = await _api(() => TicketsApi.reply(widget.ticketId, text, image: image));
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r.ticket != null) _ticket = r.ticket;
      if (r.ok) {
        _ctl.clear();
        _attach = null;
        final m = r.posted;
        if (m != null && !_messages.any((x) => x.id == m.id)) _messages = [..._messages, m];
      }
    });
    if (!r.ok) _snack(r.message ?? 'تعذّر الإرسال');
  }

  /// إرفاق صورة: المصدر (الكاميرا/المعرض) ثمّ الاختيار والضغط — الإلغاء لا يفعل شيئاً.
  Future<void> _pickImage() async {
    if (_sending || _preparing) return;
    final camera = await askTicketImageSource(context);
    if (camera == null || !mounted) return;
    setState(() => _preparing = true);
    try {
      final b = await TicketThreadScreen.pickImage(camera: camera);
      if (!mounted) return;
      setState(() {
        _preparing = false;
        if (b != null) _attach = b;
      });
    } on TicketImageError catch (e) {
      if (!mounted) return;
      setState(() => _preparing = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _preparing = false);
      _snack(const TicketImageError('decode').message);
    }
  }

  Future<void> _act(String action) async {
    if (_busy != null) return;
    if (action == 'closed') {
      final yes = await showConfirmSheet(
        context,
        title: 'إغلاق التذكرة؟',
        message: 'لن يستطيع المشترك الردّ عليها بعد الإغلاق — وتستطيع إعادة فتحها متى احتجت.',
        confirmLabel: 'أغلق',
        icon: LucideIcons.archive,
      );
      if (yes != true || !mounted) return;
    }
    _writeGen++;
    setState(() => _busy = action);
    final r = await _api(() => action == 'reopen' ? TicketsApi.reopen(widget.ticketId) : TicketsApi.setStatus(widget.ticketId, action));
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ticket != null) _ticket = r.ticket;
      final m = r.posted;
      if (r.ok && m != null && !_messages.any((x) => x.id == m.id)) _messages = [..._messages, m];
    });
    if (!r.ok) _snack(r.message ?? 'تعذّر الآن');
  }

  Future<void> _openSubscriber() async {
    final t = _ticket;
    if (t == null) return;
    final nav = Navigator.of(context);
    final sub = await NotificationRouter.findSubscriber(t.subscriber.username ?? t.subscriber.idx);
    if (!mounted) return;
    if (sub == null) {
      _snack('تعذّر إيجاد المشترك الآن — ابحث عنه من «المشتركين»');
      return;
    }
    await nav.push(MaterialPageRoute(builder: (_) => SubscriberDetailScreen(sub: sub), fullscreenDialog: true));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = _ticket;
    final title = t?.subscriber.title ?? 'تذكرة #${widget.ticketId}';
    final sub = t == null ? '' : '#${t.id} · ${ticketCategoryLabel(t.category)}';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            if (sub.isNotEmpty) Text(sub, style: AppType.micro(color: AppColors.textMid)),
          ]),
        ),
        title: title,
        subtitle: sub.isEmpty ? null : sub,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final t = _ticket;
    if (_gone) {
      return _center(LucideIcons.ticket, 'التذكرة غير متاحة', _goneMessage ?? 'لم تعد لهذا الحساب أو لا تملك صلاحيّتها');
    }
    if (t == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _center(LucideIcons.wifiOff, 'تعذّر جلب التذكرة الآن', 'حاول مرّة ثانية');
    }
    return Column(children: [
      _header(t),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading && _messages.isEmpty
              ? ListView(children: const [SizedBox(height: Sp.mega), Center(child: CircularProgressIndicator())])
              : ListView.builder(
                  key: const ValueKey('ticket-messages'),
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
                  itemCount: _messages.length + (_failed ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (_failed && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Sp.sm),
                        child: Text('تعذّر تحديث المحادثة — اسحب للأسفل',
                            textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textLow)),
                      );
                    }
                    final m = _messages[_messages.length - 1 - (i - (_failed ? 1 : 0))];
                    return m.isEvent ? _EventRow(message: m) : _Bubble(message: m, ticketId: widget.ticketId, loader: _imageLoader);
                  },
                ),
        ),
      ),
      _footer(t),
    ]);
  }

  Widget _header(Ticket t) {
    final acts = [
      if (_canWrite) ...t.actions,
      if (_canWrite && t.canReopen) 'reopen',
    ];
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          TicketStatusChip(status: t.status, moved: t.moved),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              isoJoin([t.subscriber.username ?? '', if ((t.subject ?? '').isNotEmpty) t.subject!], ' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid),
            ),
          ),
          if (!widget.viewOnly)
            TextButton.icon(
              key: const ValueKey('ticket-open-subscriber'),
              onPressed: _openSubscriber,
              icon: Icon(LucideIcons.userRound, size: 16, color: AppColors.brand),
              label: const Text('المشترك'),
            ),
        ]),
        if (acts.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Wrap(spacing: Sp.sm, runSpacing: Sp.xs, children: [
            for (final a in acts)
              OutlinedButton.icon(
                key: ValueKey('ticket-action-$a'),
                onPressed: _busy == null ? () => _act(a) : null,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  foregroundColor: a == 'closed' ? AppColors.textBody : AppColors.brand,
                ),
                icon: _busy == a
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_actionIcon(a), size: 16),
                label: Text(a == 'reopen' ? 'إعادة فتح' : ticketActionLabel(a)),
              ),
          ]),
        ],
      ]),
    );
  }

  IconData _actionIcon(String a) => switch (a) {
        'in_progress' => LucideIcons.wrench,
        'resolved' => LucideIcons.circleCheck,
        'closed' => LucideIcons.archive,
        _ => LucideIcons.rotateCcw,
      };

  Widget _footer(Ticket t) {
    String? note;
    if (widget.viewOnly) {
      note = 'للعرض هنا — الردّ وتغيير الحالة من صفحة الشركة نفسها';
    } else if (t.moved) {
      note = 'انتقل المشترك لوكيلٍ آخر — التذكرة للقراءة فقط';
    } else if (!_canWrite) {
      note = 'الردّ يحتاج صلاحيّة «التذاكر — الردّ وتغيير الحالة والإغلاق» — اطلبها من مديرك';
    } else if (t.status == 'cancelled') {
      note = 'ألغى المشترك هذه التذكرة';
    } else if (!t.canReply) {
      note = 'التذكرة مغلقة — أعد فتحها للردّ';
    }
    if (note != null) {
      return SafeArea(
        top: false,
        child: Container(
          key: const ValueKey('ticket-footer-note'),
          width: double.infinity,
          color: AppColors.surface,
          padding: const EdgeInsets.all(Sp.md),
          child: Text(note, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
        ),
      );
    }
    final attach = _attach;
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.sm, Sp.sm),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (attach != null) ...[
            TicketAttachPreview(bytes: attach, onRemove: _sending ? null : () => setState(() => _attach = null)),
            const SizedBox(height: Sp.xs),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              key: const ValueKey('ticket-attach'),
              tooltip: 'إرفاق صورة',
              onPressed: _sending || _preparing ? null : _pickImage,
              icon: _preparing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(LucideIcons.imagePlus, color: AppColors.textMid),
            ),
            Expanded(
              child: TextField(
                key: const ValueKey('ticket-composer'),
                controller: _ctl,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                style: AppType.body(color: AppColors.textHi),
                decoration: InputDecoration(
                  hintText: attach == null ? 'اكتب ردّك للمشترك…' : 'أضف نصّاً مع الصورة (اختياريّ)…',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.lg), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: Sp.xs),
            IconButton(
              key: const ValueKey('ticket-send'),
              tooltip: 'إرسال',
              onPressed: _sending || _preparing ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.send_rounded, color: AppColors.brand),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _center(IconData icon, String title, String sub) => ListView(
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          const SizedBox(height: Sp.mega),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.brandSoftBg, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: AppColors.brand),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
        ],
      );
}

/// فقاعة رسالة: المشترك في جهة البداية، والوكيل (المدير/الموظّف باسمه) في الجهة الأخرى بلون العلامة؛ وصورتها فوق نصّها.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.ticketId, this.loader});
  final TicketMessage message;
  final int ticketId;
  final TicketImageLoader? loader;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = !m.fromSubscriber;
    final meta = isoJoin([if (mine && (m.author ?? '').isNotEmpty) m.author!, timeAgoAr(m.createdAt)], ' · ');
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          key: ValueKey('ticket-msg-${m.id}'),
          margin: const EdgeInsets.only(bottom: Sp.sm),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandSoftBg : AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: mine ? AppColors.brandSoftBorder : AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (m.image != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
                child: TicketImageThumb(
                  ticketId: ticketId,
                  messageId: m.id,
                  image: m.image!,
                  loader: loader,
                ),
              ),
              if (m.hasText) const SizedBox(height: Sp.xs),
            ],
            if (m.hasText || m.image == null)
              SelectableText(m.body ?? '', style: AppType.body(color: AppColors.textHi).copyWith(height: 1.5)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta, style: AppType.micro(color: AppColors.textLow)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// سطر حدثٍ وسط المحادثة: «صارت قيد المعالجة — من فعلها · متى».
class _EventRow extends StatelessWidget {
  const _EventRow({required this.message});
  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final who = m.fromSubscriber ? '' : (m.author ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Center(
        child: Container(
          key: ValueKey('ticket-event-${m.id}'),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.pill)),
          child: Text(
            isoJoin([ticketEventLabel(m.event), who, timeAgoAr(m.createdAt)], ' · '),
            style: AppType.micro(color: AppColors.textMid),
          ),
        ),
      ),
    );
  }
}
