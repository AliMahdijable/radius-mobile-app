import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/managers_api.dart';
import '../../../api/whatsapp_api.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// صفيحة ربط المدير الفرعيّ ببوت تلغرام الأب.
///
/// ── لماذا رابطٌ أصلاً ───────────────────────────────────────────
/// بوت تلغرام **لا يستطيع بدء محادثة**: يجب أن يفتحها المستقبِل بضغط
/// START. فلا سبيل لربط التابع من طرفنا وحدنا مهما ملكنا من بياناته —
/// الرابط ليس اختصاراً بل الطريق الوحيد.
///
/// ── ولماذا بوتُ الأب لا بوتُ التابع ─────────────────────────────
/// قِيس على الإنتاج أنّ **١١ مديراً من ٨٥٠** أنشأوا بوتاً عبر BotFather
/// وربطوا حساباتهم. فبناءُ القناة على بوت التابع يعني ألّا تصل الميزة
/// ٩٨٪ منهم. أمّا رابط الأب فضغطةٌ واحدة عند التابع: يفتح، يضغط
/// START، انتهى — بلا BotFather ولا توكن ولا إعداد.
///
/// ⚠️ والرابط **يخصّ هذا الزوج وحده**: توقيعه HMAC على (سرّ الأب ·
/// معرّف الأب · معرّف التابع). فتسريبه لا يربط غير صاحبه، وتبديل
/// المعرّف فيه يُبطله. مُختبَر: حمولةٌ بمعرّفٍ مبدَّل وتوقيعٍ صحيح
/// رُفضت.
Future<bool?> showTelegramLinkSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    barrierColor: AppColors.scrim,
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TelegramLinkSheet(manager: m),
  );
}

class _TelegramLinkSheet extends StatefulWidget {
  const _TelegramLinkSheet({required this.manager});
  final Manager manager;

  @override
  State<_TelegramLinkSheet> createState() => _TelegramLinkSheetState();
}

class _TelegramLinkSheetState extends State<_TelegramLinkSheet> {
  bool _loading = true;
  bool _busy = false;
  String? _link;
  String? _bot;
  bool _bound = false;
  String? _error;

  /// هل تغيّر شيءٌ يستوجب إعادة تحميل القائمة عند الإغلاق.
  bool _dirty = false;

  /// ── استجواب حالة الربط ──────────────────────────────────────
  /// ⚠️ **الربط يقع في تلغرام لا في التطبيق**: التابع يفتح الرابط
  /// ويضغط START على جهازه هو. فلا حدثٌ يصل التطبيق ولا شيء يُخطره.
  ///
  /// وبلا هذا الاستجواب تبقى الراية `telegramLinked` قديمةً حتّى
  /// يسحب المدير القائمة يدويّاً — فيفتح «شحن» ويجد مفتاح تلغرام
  /// معطّلاً مكتوباً عليه «لم يربط حسابه» بينما التابع ربط تواً.
  /// حدث ذلك فعلاً قبل هذا الإصلاح.
  Timer? _poll;
  int _polls = 0;

  /// حدٌّ زمنيّ لا عدديّ في المعنى: ٤ ثوانٍ × ٧٥ = خمس دقائق. وهي
  /// أطول ممّا يحتاجه من يضغط رابطاً وصله تواً، وأقصر من أن تستنزف
  /// بطّاريّةً لصفيحةٍ نُسيت مفتوحة.
  static const _pollEvery = Duration(seconds: 4);
  static const _maxPolls = 75;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    if (_bound) return; // مرتبطٌ سلفاً — لا شيء ننتظره
    _poll = Timer.periodic(_pollEvery, (t) async {
      if (!mounted) { t.cancel(); return; }
      if (++_polls > _maxPolls) { t.cancel(); return; }
      final st = await ManagersApi.telegramStatus(widget.manager.id);
      if (!mounted) { t.cancel(); return; }
      // ⚠️ `st.ok` شرطٌ لازم: الفشل يعني «لا نعرف» لا «غير مرتبط».
      // وبدونه يمحو انقطاعُ شبكةٍ لحظيّ حالةَ ربطٍ صحيحة.
      if (st.ok && st.bound) {
        t.cancel();
        HapticFeedback.mediumImpact();
        setState(() { _bound = true; _dirty = true; });
      }
    });
  }

  Future<void> _checkNow() async {
    setState(() => _busy = true);
    final st = await ManagersApi.telegramStatus(widget.manager.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (st.ok && st.bound) { _bound = true; _dirty = true; _poll?.cancel(); }
    });
    if (!(st.ok && st.bound)) {
      showSheetSnack(context, 'لم يضغط START بعد', isError: true);
    }
  }

  Future<void> _fetch() async {
    final r = await ManagersApi.fetchTelegramLink(widget.manager.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _link = r.link;
      _bot = r.bot;
      _bound = r.bound;
      _error = r.ok ? null : r.message;
    });
    if (r.ok && !r.bound) _startPolling();
  }

  String get _invite {
    final bot = _bot ?? 'البوت';
    return 'مرحبا ${widget.manager.username} 👋\n\n'
        'حتى توصلك إشعارات الشحن والسحب وتسديد الديون على حسابك '
        'مباشرةً عبر تلغرام، افتح الرابط التالي واضغط START:\n\n'
        '${_link ?? ''}\n\n'
        'خطوة لمرّة واحدة فقط — بعدها الإشعارات توصلك تلقائيّاً من بوت "$bot".';
  }

  Future<void> _sendViaWhatsApp() async {
    final phone = widget.manager.mobile.trim();
    if (phone.isEmpty) {
      showSheetSnack(context, 'لا يوجد رقم واتساب لهذا المدير', isError: true);
      return;
    }
    setState(() => _busy = true);
    final r = await WhatsAppApi.sendMessage(
      to: phone,
      message: _invite,
      intent: 'manual',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showSheetSnack(
      context,
      r.ok ? 'أُرسل الرابط عبر واتساب' : (r.message ?? 'تعذّر الإرسال'),
      isError: !r.ok,
    );
  }

  Future<void> _share() async {
    // sharePositionOrigin مطلوب لـiPad — بدونه يرمي
    // NSInvalidArgumentException. مُتجاهَل على iPhone وأندرويد.
    Rect origin = Rect.zero;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    // ignore: deprecated_member_use
    await Share.share(_invite, sharePositionOrigin: origin);
  }

  Future<void> _unlink() async {
    setState(() => _busy = true);
    final r = await ManagersApi.unlinkTelegram(widget.manager.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _bound = false;
        _dirty = true;
        _polls = 0;
      }
    });
    if (r.ok) _startPolling();
    showSheetSnack(
      context,
      r.ok ? 'فُكّ الربط' : (r.message ?? 'تعذّر فكّ الربط'),
      isError: !r.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.send,
        title: 'ربط تلغرام',
        subtitle: widget.manager.username,
        onClose: () => Navigator.of(context).pop(_dirty),
        tint: AppColors.channelTelegram,
        tintBg: AppColors.channelTelegramSoftBg,
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: Sp.xl),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : _error != null
              ? _errorBody()
              : _body(),
    );
  }

  Widget _errorBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note(
            icon: LucideIcons.triangleAlert,
            tone: AppTone.warning,
            // ⚠️ نعرض رسالة الخادم حرفيّاً: هو وحده يعرف السبب («بوتك
            // غير متّصل» مثلاً)، وتعميمُنا فوقها يُخفي الحلّ.
            text: _error!,
          ),
          const SizedBox(height: Sp.md),
          _note(
            icon: LucideIcons.info,
            tone: AppTone.info,
            text: 'الربط يحتاج بوت تلغرام متّصلاً على حسابك أنت. '
                'أعدّه من الإعدادات ← تلغرام، ثمّ عُد إلى هنا.',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final ownBot = widget.manager.telegramChannel == 'own_bot';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_bound)
            _note(
              icon: LucideIcons.circleCheck,
              tone: AppTone.success,
              text: 'مرتبط ببوتك — الإشعارات تصله عبر "@${_bot ?? ''}".',
            )
          else if (ownBot)
            // ⚠️ حالةٌ مميَّزة لا مخفيّة: له بوته فالرسائل تصله اليوم،
            // لكنّها تصله من بوتٍ لا تملكه أنت. والربط ببوتك يجعلها
            // تمرّ منك — وهو ما يفضّله الخادم عند وجود الاثنين.
            _note(
              icon: LucideIcons.info,
              tone: AppTone.info,
              text: 'هذا المدير له بوت تلغرام خاصّ به، والإشعارات تصله '
                  'عبره. وإن ربطته ببوتك صارت تصله منك.',
            )
          else
            _waitingNote(),
          const SizedBox(height: Sp.md),
          _linkBox(),
          const SizedBox(height: Sp.md),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: LucideIcons.messageCircle,
                  label: 'إرسال بواتساب',
                  color: AppColors.channelWhatsApp,
                  // ⚠️ معطّلٌ بسببٍ ظاهر لا مخفيّ: الإخفاء يجعل المدير
                  // يظنّ الميزة غير منشورة (حدث سلفاً).
                  enabled: widget.manager.mobile.trim().isNotEmpty,
                  onTap: _sendViaWhatsApp,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _actionBtn(
                  icon: LucideIcons.copy,
                  label: 'نسخ',
                  color: AppColors.brand,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await Clipboard.setData(ClipboardData(text: _link ?? ''));
                    if (mounted) showSheetSnack(context, 'نُسخ الرابط');
                  },
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _actionBtn(
                  icon: LucideIcons.share2,
                  label: 'مشاركة',
                  color: AppColors.channelTelegram,
                  onTap: _share,
                ),
              ),
            ],
          ),
          if (widget.manager.mobile.trim().isEmpty) ...[
            const SizedBox(height: Sp.sm),
            Text(
              'لا رقم واتساب لهذا المدير — انسخ الرابط أو شاركه.',
              style: AppType.muted(color: AppColors.textLow),
            ),
          ],
          if (!_bound) ...[
            const SizedBox(height: Sp.sm),
            // ⚠️ زرٌّ يدويّ **إلى جانب** الاستجواب لا بديلاً عنه: من
            // أرسل الرابط ثمّ خرج من التطبيق وعاد بعد ساعة لا يُدركه
            // الاستجواب (خمس دقائق)، فيحتاج سؤالاً صريحاً.
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _checkNow,
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: const Text('تحقّق الآن'),
                style: TextButton.styleFrom(foregroundColor: AppColors.brand),
              ),
            ),
          ],
          if (_bound) ...[
            const SizedBox(height: Sp.md),
            TextButton.icon(
              onPressed: _busy ? null : _unlink,
              icon: const Icon(LucideIcons.link2Off, size: 16),
              label: const Text('فكّ الربط'),
              style: TextButton.styleFrom(foregroundColor: AppTone.danger.fill),
            ),
          ],
        ],
      ),
    );
  }

  /// ملاحظة الانتظار — تقول للمدير إنّ التطبيق **يراقب** فلا يظنّ
  /// أنّه مطالبٌ بالخروج والعودة. والمؤشّر الدوّار هو الفرق بين
  /// «انتظِر» و«لا شيء يحدث».
  Widget _waitingNote() {
    final watching = _poll?.isActive == true;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppTone.info.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppTone.info.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: watching
                ? CircularProgressIndicator(
                    strokeWidth: 1.8, color: AppTone.info.fill)
                : Icon(LucideIcons.send, size: 16, color: AppTone.info.fill),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              watching
                  ? 'أرسل له الرابط. يفتحه ويضغط START مرّةً واحدة — '
                      'وسنُبلّغك هنا فور ارتباطه.'
                  : 'أرسل له الرابط. يفتحه ويضغط START مرّةً واحدة، '
                      'ثمّ اضغط «تحقّق الآن».',
              style: AppType.muted(color: AppTone.info.onSoft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        _link ?? '',
        // الرابط لاتينيّ في واجهةٍ عربيّة — بلا `ltr` ينقلب ترتيب
        // مقاطعه بصريّاً فيُنسخ صحيحاً ويُقرأ خطأً.
        textDirection: TextDirection.ltr,
        style: AppType.muted(color: AppColors.textBody),
      ),
    );
  }

  Widget _note({
    required IconData icon,
    required AppTone tone,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: tone.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text, style: AppType.muted(color: tone.onSoft)),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Future<void> Function() onTap,
    bool enabled = true,
  }) {
    final live = enabled && !_busy;
    return Material(
      color: live ? color.withValues(alpha: 0.10) : AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: live ? () => onTap() : null,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: live ? color : AppColors.textPlaceholder),
              const SizedBox(height: Sp.x6),
              Text(
                label,
                style: AppType.muted(
                  color: live ? AppColors.textBody : AppColors.textPlaceholder,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
