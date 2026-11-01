import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_labels.dart';

/// الكتابة في بوّابة المشروع الوطنيّ من التطبيق (watani، المرحلة ٢ — ٣١ أكتوبر؛ المالك: «كيف ينشى طلب وكيف ينشى تذكره والعمليات
/// عليها»): فتح تذكرة (لمشترك بزون اشتراكه، أو للزون)، والتعليق، وموعد الزيارة، وإلغاء الطلب — نسخة الموقع
/// (`client-v2/src/components/ftth/FtthTicketWrite.tsx`). تظهر حين يقول الخادم `can_write`/`can`، والموظّف بلا «تعديل المشترك»
/// يراها مقفلةً بمكانها. لا إعادة تلقائيّة: «غير مؤكَّد» يُعرض كما هو، و«تحقّق» يعيد النموذج نفسه بمرجعه (لا تذكرة ثانية).

/// الموظّف بلا «تعديل المشترك»: الأزرار بمكانها مقفلة. صاحب الحساب لا يُقفل بهذا المفتاح أبداً (١ نوفمبر): قدراته من الخادم تجعله false
/// لأنّ الوطنيّ لا «يعدّل المشترك» عند البوّابة — وكتابته هنا يحرسها مفتاح الكتابة للحساب (`can_write`/`can`) لا هذا المفتاح.
bool get nationalWriteLocked => Perms.isEmployee && !Perms.has('subscribers.edit');

/// تذكرةٌ فُتحت للتوّ — لتُفتح ورقتها.
typedef NationalCreatedTicket = ({String id, String? displayId, String title, String status});

String _failText(NationalWrite r) =>
    [r.message ?? 'تعذّر التنفيذ — لم يتغيّر شيء', if (r.portalMessage != null) r.portalMessage!].join('\n');

/// «غير مؤكَّد»: لا «فشل» ولا «أعد المحاولة» — النتيجة ربّما وصلت.
class NationalUnconfirmedBox extends StatelessWidget {
  const NationalUnconfirmedBox({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.warningSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.warningOnSoft),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.body(color: AppColors.warningOnSoft).copyWith(height: 1.5))),
        ],
      ),
    );
  }
}

/* ───────────────────────────── فتح تذكرة ───────────────────────────── */

Future<NationalCreatedTicket?> showNationalNewTicket(BuildContext context, NationalLookups lookups) {
  return showAppSheet<NationalCreatedTicket>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => NationalNewTicketSheet(lookups: lookups),
  );
}

class NationalNewTicketSheet extends StatefulWidget {
  const NationalNewTicketSheet({super.key, required this.lookups});
  final NationalLookups lookups;

  @override
  State<NationalNewTicketSheet> createState() => _NationalNewTicketSheetState();
}

class _NationalNewTicketSheetState extends State<NationalNewTicketSheet> {
  int _kind = 0; // 0 لمشترك · 1 للزون
  final _search = TextEditingController();
  final _summary = TextEditingController();
  final _details = TextEditingController();
  List<NationalTarget> _hits = const [];
  bool _searching = false;
  bool _searchFailed = false;
  NationalTarget? _target;
  String _zone = '';
  String _category = '';
  bool _busy = false;
  String? _unconfirmed;
  final String _ref = NationalPortalApi.newRef();
  Timer? _debounce;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _summary.addListener(_changed);
    _details.addListener(_changed);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _summary.dispose();
    _details.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _onSearch(String v) {
    _debounce?.cancel();
    final gen = ++_gen;
    if (v.trim().length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await NationalPortalApi.searchTargets(v);
      if (!mounted || gen != _gen) return;
      setState(() {
        _searching = false;
        _searchFailed = r == null;
        _hits = r ?? const [];
      });
    });
  }

  /// زون الاشتراك: معرّفه من البحث، وإلّا بالاسم من قائمة الزونات.
  String? get _targetZone {
    final t = _target;
    if (t == null) return null;
    if (t.zoneId != null) return t.zoneId;
    final z = (widget.lookups.zones ?? const <NationalLookupItem>[]).where((z) => z.name == t.zone || z.id == t.zone);
    return z.isEmpty ? null : z.first.id;
  }

  String get _zoneId => _kind == 0 ? (_targetZone ?? '') : _zone;

  bool get _ready =>
      _category.isNotEmpty &&
      _zoneId.isNotEmpty &&
      _summary.text.trim().isNotEmpty &&
      _details.text.trim().isNotEmpty &&
      (_kind == 1 || (_target?.customerId?.isNotEmpty ?? false));

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final r = await NationalPortalApi.createTicket(
      ref: _ref,
      category: _category,
      summary: _summary.text,
      details: _details.text,
      zone: _zoneId,
      customerId: _kind == 0 ? _target?.customerId : null,
      subscriber: _kind == 0 ? _target?.idx : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final id = (r.data['id'] ?? '').toString();
      final shown = r.data['display_id']?.toString();
      showSheetSnack(context, shown == null || shown.isEmpty ? 'فُتحت التذكرة' : 'فُتحت التذكرة $shown');
      Navigator.of(context).pop<NationalCreatedTicket>(
        id.isEmpty
            ? null
            : (id: id, displayId: shown, title: (r.data['title'] ?? _summary.text.trim()).toString(), status: (r.data['status'] ?? '').toString()),
      );
      return;
    }
    if (r.unconfirmed) {
      setState(() => _unconfirmed = r.message);
      return;
    }
    showSheetSnack(context, _failText(r), isError: true);
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_unconfirmed != null) {
      final go = await showConfirmSheet(
        context,
        title: 'التذكرة لم تتأكّد',
        message: 'إن أغلقت الآن فتحقّق من قائمة التذاكر قبل فتح غيرها.',
        confirmLabel: 'إغلاق',
        cancelLabel: 'البقاء',
        icon: LucideIcons.triangleAlert,
        tone: AppTone.warning,
      );
      if (go != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final frozen = _busy || _unconfirmed != null;
    final cats = widget.lookups.ticketCategories ?? const <NationalLookupItem>[];
    final zones = widget.lookups.zones ?? const <NationalLookupItem>[];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.headset,
        title: 'تذكرة جديدة',
        subtitle: 'تُفتح باسم حسابك في بوّابة الوطني',
        onClose: _close,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSegmented(
            labels: const ['لمشترك', 'للزون'],
            icons: const [LucideIcons.user, LucideIcons.building2],
            selectedIndex: _kind,
            onSelect: (i) {
              if (frozen) return;
              setState(() => _kind = i);
            },
          ),
          const SizedBox(height: Sp.lg),
          if (_kind == 0) ..._targetPicker(frozen) else ..._zonePicker(zones, frozen),
          const SizedBox(height: Sp.lg),
          Text('نوع التذكرة', style: AppType.label(color: AppColors.textLabel)),
          const SizedBox(height: Sp.sm),
          if (cats.isEmpty)
            Text('الأنواع غير متاحة الآن — أعد فتح الصفحة', style: AppType.muted())
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in cats) _chip(nationalTicketCategory(c.name), _category == c.id, frozen ? null : () => setState(() => _category = c.id))],
            ),
          const SizedBox(height: Sp.lg),
          _labelWithCount('العنوان', _summary.text.trim().runes.length, NationalPortalApi.summaryMax),
          const SizedBox(height: Sp.sm),
          SheetNoteField(
            controller: _summary,
            hint: 'مثلاً: انقطاع الخدمة عن المشترك',
            maxLength: NationalPortalApi.summaryMax,
            maxLines: 2,
            enabled: !frozen,
            icon: LucideIcons.type,
          ),
          const SizedBox(height: Sp.lg),
          _labelWithCount('وصف المشكلة', _details.text.trim().runes.length, NationalPortalApi.detailsMax),
          const SizedBox(height: Sp.sm),
          SheetNoteField(
            controller: _details,
            hint: 'ما الذي حدث ومتى، وما جرّبته',
            maxLength: NationalPortalApi.detailsMax,
            minLines: 4,
            maxLines: 8,
            enabled: !frozen,
            icon: LucideIcons.alignRight,
          ),
          if (_unconfirmed != null) ...[
            const SizedBox(height: Sp.lg),
            NationalUnconfirmedBox(text: _unconfirmed!),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: _unconfirmed != null ? 'تحقّق' : 'فتح التذكرة',
        icon: _unconfirmed != null ? LucideIcons.refreshCw : LucideIcons.plus,
        busy: _busy,
        enabled: _ready,
        onPressed: _submit,
      ),
    );
  }

  List<Widget> _targetPicker(bool frozen) {
    final t = _target;
    if (t != null) {
      final zone = _targetZone;
      return [
        Text('المشترك', style: AppType.label(color: AppColors.textLabel)),
        const SizedBox(height: Sp.sm),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
                    const SizedBox(height: 2),
                    Text(t.username, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                    const SizedBox(height: 2),
                    zone == null
                        ? Text('زونه غير معروف — حدّث قائمة المشتركين', style: AppType.micro(color: AppColors.error))
                        : Row(
                            children: [
                              Text('الزون: ', style: AppType.micro(color: AppColors.textMid)),
                              Flexible(
                                child: Text(t.zone ?? zone,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تغيير المشترك',
                onPressed: frozen ? null : () => setState(() => _target = null),
                icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ];
    }
    final q = _search.text.trim();
    return [
      Text('المشترك', style: AppType.label(color: AppColors.textLabel)),
      const SizedBox(height: Sp.sm),
      SheetSearchField(controller: _search, hint: 'الاسم أو اليوزر أو الهاتف', onChanged: _onSearch),
      const SizedBox(height: Sp.sm),
      if (q.length >= 2 && _searching)
        Text('جارٍ البحث…', style: AppType.muted())
      else if (q.length >= 2 && _searchFailed)
        Text('تعذّر البحث الآن — أعد المحاولة', style: AppType.muted())
      else if (q.length >= 2 && _hits.isEmpty)
        Text('لا مشترك بهذا البحث', style: AppType.muted())
      else
        for (final h in _hits)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                _target = h;
                _search.clear();
                _hits = const [];
              }),
              borderRadius: BorderRadius.circular(R.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    Icon(LucideIcons.user, size: 16, color: AppColors.textMid),
                    const SizedBox(width: Sp.sm),
                    Expanded(child: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textHi))),
                    const SizedBox(width: Sp.sm),
                    Text(h.zone ?? h.username, maxLines: 1, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
            ),
          ),
    ];
  }

  List<Widget> _zonePicker(List<NationalLookupItem> zones, bool frozen) => [
        Text('الزون', style: AppType.label(color: AppColors.textLabel)),
        const SizedBox(height: Sp.sm),
        if (zones.isEmpty)
          Text('قائمة الزونات غير متاحة الآن — أعد فتح الصفحة', style: AppType.muted())
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final z in zones) _chip(z.name.isEmpty ? z.id : z.name, _zone == z.id, frozen ? null : () => setState(() => _zone = z.id))],
          ),
      ];

  Widget _labelWithCount(String label, int n, int max) => Row(
        children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textLabel))),
          Text('$n/$max', textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
        ],
      );

  Widget _chip(String label, bool on, VoidCallback? onTap) => ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: onTap == null ? null : (_) => onTap(),
        labelStyle: AppType.label(color: on ? AppColors.brand : AppColors.textHi),
        selectedColor: AppColors.brandSoftBg,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: on ? AppColors.brandSoftBorder : AppColors.border),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
      );
}

/* ───────────────────────────── التعليق ───────────────────────────── */

class NationalCommentBox extends StatefulWidget {
  const NationalCommentBox({super.key, required String this.ticketId, required this.onSent, this.onUnconfirmed}) : send = null;

  /// تعليقٌ على غير التذكرة (المهمّة، الطلب — ١ نوفمبر): [send] يرسله مرّةً واحدة (لا إعادة تلقائيّة) والصندوق نفسه.
  const NationalCommentBox.to({
    super.key,
    required Future<NationalWrite> Function(String text) this.send,
    required this.onSent,
    this.onUnconfirmed,
  }) : ticketId = null;
  final String? ticketId;
  final Future<NationalWrite> Function(String text)? send;
  final VoidCallback onSent;

  /// «غير مؤكَّد» يحفظه صاحب الصندوق (ورقة المهمّة والطلب) ويعرضه فوق تعليقاته — فيبقى بعد إعادة الجلب ولو أُزيل الصندوق أثناءها
  /// (مراجعة ١ نوفمبر: كان يضيع فيُعاد التعليق فيتكرّر في البوّابة). يُستدعى بنصّه، وبـnull بعد إرسالٍ ناجح. null ⇒ الصندوق يعرضه
  /// تحته بنفسه (التذكرة كما كانت).
  final ValueChanged<String?>? onUnconfirmed;

  @override
  State<NationalCommentBox> createState() => _NationalCommentBoxState();
}

class _NationalCommentBoxState extends State<NationalCommentBox> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _unconfirmed;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (nationalWriteLocked) {
      showNoPermission(context, action: true);
      return;
    }
    if (_busy || _text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final send = widget.send;
    final r = await (send != null ? send(_text.text) : NationalPortalApi.comment(widget.ticketId!, _text.text));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(context, 'أُرسل التعليق');
      _text.clear();
      setState(() => _unconfirmed = null);
      widget.onUnconfirmed?.call(null);
      widget.onSent();
      return;
    }
    if (r.unconfirmed) {
      // قبل إعادة الجلب: صاحب الصندوق يحفظه أوّلاً (يبقى ولو أُزيل الصندوق أثناءها)، وإلّا تحته هنا
      final text = r.message ?? 'لم يتأكّد إرسال التعليق — حدّث التعليقات وتحقّق قبل إعادته';
      final lifted = widget.onUnconfirmed;
      if (lifted != null) {
        lifted(text);
      } else {
        setState(() => _unconfirmed = text);
      }
      widget.onSent();
      return;
    }
    showSheetSnack(context, _failText(r), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final locked = nationalWriteLocked;
    final n = _text.text.trim().runes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetNoteField(
          controller: _text,
          hint: locked ? 'التعليق — لا صلاحيّة' : 'اكتب تعليقاً للشركة…',
          maxLength: NationalPortalApi.commentMax,
          minLines: 2,
          maxLines: 5,
          enabled: !_busy && !locked,
          icon: LucideIcons.messageSquare,
        ),
        const SizedBox(height: Sp.sm),
        Row(
          children: [
            Text('$n/${NationalPortalApi.commentMax}', textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
            const Spacer(),
            FilledButton.icon(
              onPressed: locked ? () => showNoPermission(context, action: true) : (_busy || n == 0 ? null : _send),
              icon: Icon(locked ? LucideIcons.lock : LucideIcons.send, size: 16),
              label: Text(_busy ? 'جارٍ الإرسال…' : 'إرسال'),
              style: FilledButton.styleFrom(
                backgroundColor: locked ? AppColors.surfaceDisabled : AppColors.brand,
                foregroundColor: locked ? AppColors.textHint : AppColors.onBrand,
              ),
            ),
          ],
        ),
        if (_unconfirmed != null) ...[
          const SizedBox(height: Sp.sm),
          NationalUnconfirmedBox(text: _unconfirmed!),
        ],
      ],
    );
  }
}

/* ───────────────────────────── موعد الزيارة ───────────────────────────── */

/// ورقة الموعد — ترجع true حين حُفظ (أو لم يتأكّد: الورقة تُحدَّث في الحالين).
Future<bool?> showNationalSchedule(BuildContext context, {required String ticketId, String? current}) {
  if (nationalWriteLocked) {
    showNoPermission(context, action: true);
    return Future.value(false);
  }
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ScheduleSheet(ticketId: ticketId, current: current),
  );
}

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.ticketId, this.current});
  final String ticketId;
  final String? current;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  final _reason = TextEditingController();
  bool _busy = false;
  String? _unconfirmed;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  String get _dateStr => _date == null ? '' : '${_date!.year}-${_two(_date!.month)}-${_two(_date!.day)}';
  String get _timeStr => '${_two(_time.hour)}:${_two(_time.minute)}';
  bool get _inHours {
    final m = _time.hour * 60 + _time.minute;
    return m >= 9 * 60 && m <= 23 * 60;
  }

  bool get _ready => _date != null && _inHours && _reason.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 60)),
      helpText: 'يوم الزيارة',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'ساعة الزيارة',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _save() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final r = await NationalPortalApi.schedule(widget.ticketId, date: _dateStr, time: _timeStr, reason: _reason.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      showSheetSnack(context, 'حُفظ موعد الزيارة');
      Navigator.of(context).pop(true);
      return;
    }
    if (r.unconfirmed) {
      setState(() => _unconfirmed = r.message);
      return;
    }
    showSheetSnack(context, _failText(r), isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.calendarClock,
        title: widget.current == null ? 'تحديد موعد الزيارة' : 'تغيير موعد الزيارة',
        subtitle: 'بتوقيت بغداد',
        onClose: () => Navigator.of(context).pop(_unconfirmed != null),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _pickBox(LucideIcons.calendar, 'اليوم', _date == null ? 'اختر اليوم' : _dateStr, _busy ? null : _pickDate)),
              const SizedBox(width: Sp.sm),
              Expanded(child: _pickBox(LucideIcons.clock, 'الساعة', _timeStr, _busy ? null : _pickTime)),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text(
            'بين ٩ صباحاً و١١ ليلاً — وتسمح البوّابة بثلاثة تعديلاتٍ في اليوم.',
            style: AppType.micro(color: _inHours ? AppColors.textMid : AppColors.error),
          ),
          const SizedBox(height: Sp.lg),
          Text('السبب', style: AppType.label(color: AppColors.textLabel)),
          const SizedBox(height: Sp.sm),
          SheetNoteField(
            controller: _reason,
            hint: 'مثلاً: المشترك بالبيت عصراً',
            maxLength: NationalPortalApi.reasonMax,
            maxLines: 2,
            enabled: !_busy,
          ),
          if (_unconfirmed != null) ...[
            const SizedBox(height: Sp.lg),
            NationalUnconfirmedBox(text: _unconfirmed!),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'حفظ الموعد',
        icon: LucideIcons.calendarCheck,
        busy: _busy,
        enabled: _ready && _unconfirmed == null,
        onPressed: _save,
      ),
    );
  }

  Widget _pickBox(IconData icon, String label, String value, VoidCallback? onTap) => Material(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.md), border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textMid),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppType.micro(color: AppColors.textMid)),
                      Text(value, maxLines: 1, textDirection: TextDirection.ltr, style: AppType.label(color: AppColors.textHi)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/* ───────────────────────────── إلغاء طلب ───────────────────────────── */

/// تأكيدٌ ثمّ الإلغاء — يرجع true حين أُلغي أو لم يتأكّد (فتُحدَّث القائمة في الحالين).
Future<bool> nationalCancelRequest(BuildContext context, {required String id, required String type, required String label}) async {
  if (nationalWriteLocked) {
    showNoPermission(context, action: true);
    return false;
  }
  final go = await showConfirmSheet(
    context,
    title: 'إلغاء الطلب',
    message: 'إلغاء «$label» في بوّابة المشروع الوطني؟ لا رجوع بعد الإلغاء.',
    confirmLabel: 'إلغاء الطلب',
    cancelLabel: 'تراجع',
    icon: LucideIcons.circleX,
    tone: AppTone.danger,
  );
  if (go != true || !context.mounted) return false;
  final r = await NationalPortalApi.cancelRequest(id, type);
  if (!context.mounted) return r.ok || r.unconfirmed;
  if (r.ok) {
    showSheetSnack(context, 'أُلغي الطلب');
    return true;
  }
  if (r.unconfirmed) {
    showSheetSnack(context, r.message ?? 'لم يتأكّد الإلغاء — افتح الطلب لترى حالته', isError: true, autoExplain: false);
    return true;
  }
  showSheetSnack(context, _failText(r), isError: true);
  return false;
}
