import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/subscribers_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/app_resumed_signal.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/account_statement_screen.dart';
import 'sheets/activate_sheet.dart';
import 'sheets/add_debt_sheet.dart';
import 'sheets/location_sheets.dart';
import 'sheets/edit_subscriber_sheet.dart';
import 'sheets/extend_sheet.dart';
import 'sheets/movements_sheet.dart';
import 'sheets/consumption_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'sheets/qr_login_sheet.dart';
import 'sheets/quick_discount_sheet.dart';
import 'widgets/balance_card.dart';
import 'widgets/device_probe_card.dart';
import 'widgets/subscriber_actions.dart';

/// Subscriber details — v2 visual shell over v1's structure. Layout
/// top→bottom (info → operations):
///   1. Header — avatar + status + name + username + close.
///   2. Live session card (when online) — IP / MAC / duration + DL/UL.
///   3. Subscription card — package + price + expiry + parent + phone.
///   4. Balance hero card (when non-zero).
///   5. Operations card AT THE BOTTOM — every action v1 surfaces in
///      its FAB sheet, in a single 3-column grid: تعديل / تفعيل /
///      تمديد / إضافة دين / تسديد دين / خصم سريع / سجل الحركات /
///      تذكير دين / تذكير انتهاء / إرسال المعلومات /
///      حذف / تعطيل-تفعيل حساب / اتصال / واتساب / فصل المستخدم.
///
/// Info cards are intentionally tight (smaller padding, 4px row gaps)
/// so the operations grid has room to breathe without scrolling on
/// most phones.
class SubscriberDetailScreen extends StatefulWidget {
  const SubscriberDetailScreen({super.key, required this.sub});
  final Subscriber sub;

  @override
  State<SubscriberDetailScreen> createState() => _SubscriberDetailScreenState();
}

class _SubscriberDetailScreenState extends State<SubscriberDetailScreen> {
  late Subscriber sub = widget.sub;
  bool _disconnecting = false;
  bool _toggling = false;

  /// Currently in-flight template send, or null. Drives the tile
  /// 'جاري...' label so the admin sees activity for the right chip
  /// (the operations grid has 3 template chips — debt reminder /
  /// expiry warning / subscriber info).
  String? _sendingTemplate;

  /// True while the generate-info-link round-trip + WhatsApp send
  /// are in flight. Same single-flight pattern as the toggle and
  /// disconnect — the chip label flips and the busy guard locks
  /// the rest of the grid.

  /// True while the DELETE round-trip is in flight.
  bool _deleting = false;

  /// Password المشترك — يُحمَّل asynchronously من backend عند فتح الشاشة
  /// (SAS4 يحجبه في list endpoint، يرجعه فقط في /user/overview/{idx}).
  /// null = قيد التحميل أو فشل. non-null = جاهز للعرض في _PasswordRow.
  String? _subscriberPassword;

  /// Any operation (toggle / disconnect / template send / link gen)
  /// currently awaiting a server response. Drives the operations
  /// card's progress bar + chip-disable overlay so the admin can't
  /// fire a second action while the first is mid-flight — مطلب
  /// المستخدم 2026-06-09: لا شيء يدل على التحميل وكل الأزرار تبقى
  /// فعّالة.
  bool get _isBusy =>
      _disconnecting || _toggling || _sendingTemplate != null || _deleting;

  @override
  void initState() {
    super.initState();
    // Keep the open detail screen in sync with backend state. Any
    // mutation done from the operations grid (activate / extend /
    // pay-debt / add-debt / discount / disconnect / toggle / …)
    // fires SubscriberEvents.notifyChange, which we use here to
    // re-locate this subscriber in the refreshed cache and rebuild
    // with the new debt / discount / expiry / online flags. Without
    // this, the screen sits on its widget.sub copy and shows stale
    // numbers until the admin closes and re-opens it.
    SubscriberEvents.dataChanged.addListener(_onDataChanged);
    // إعادة الجلب لمّا التطبيق يرجع من الخلفيّة — نفس _onDataChanged،
    // لأن الشاشة تبقى مركّبة في stack الـnavigation حتى بعد resume
    // فما تنطلق initState ثانية.
    AppResumedSignal.tick.addListener(_onDataChanged);
    // 2026-08-18: جلب password (non-blocking) — لعرضه في هيرو الكارت مع
    // زرّ copy.
    // 2026-08-25: أُزيلت صلاحيّة الحجب — الباسورد يظهر لكل موظّف مصادَق
    // (بلا اشتراط subscribers.view_credentials أو subscribers.edit).
    // السبب: قفل التعديل كان يشلّ إمكان مساعدة المشترك في تسجيل الدخول،
    // وهذه خدمة أساسيّة يحتاجها كل موظّف داعم.
    _loadPassword();
  }

  Future<void> _loadPassword() async {
    final idx = sub.idx;
    if (idx == null) return;
    final pass = await SubscribersApi.fetchPassword(idx.toString());
    if (!mounted || pass == null || pass.isEmpty) return;
    setState(() => _subscriberPassword = pass);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    AppResumedSignal.tick.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _onDataChanged() async {
    if (!mounted) return;
    // Safety timeout — لمّا نُستدعى من AppResumedSignal بعد فترة
    // غياب طويلة، الـbackend ممكن يتأخّر (SubscribersApi.loadAll
    // يحمّل قائمة ثقيلة). بدون timeout، الـFuture يعلق ويبقى الصف
    // stale بلا مؤشّر بصري.
    List<Subscriber>? list;
    try {
      list =
          await SubscribersApi.loadAll().timeout(const Duration(seconds: 20));
    } catch (_) {
      list = null;
    }
    if (!mounted || list == null) return;
    // Match by idx first (canonical, survives username renames),
    // then fall back to username for any rows where idx didn't land.
    Subscriber? fresh;
    for (final s in list) {
      if (s.idx != null && s.idx == sub.idx) {
        fresh = s;
        break;
      }
    }
    fresh ??= list.cast<Subscriber?>().firstWhere(
          (s) => s?.username == sub.username,
          orElse: () => null,
        );
    if (fresh == null) return;
    // Preserve the live online overlay (IP / DL/UL / session time)
    // — the refreshed row comes from /api/v2/subscribers and doesn't
    // carry online state. Without this, an open detail screen of a
    // currently-connected subscriber would lose its session card.
    setState(() {
      sub = fresh!.copyWithOnline(
        online: sub.isOnline,
        ip: sub.ipAddress,
        session: sub.sessionTime,
        dl: sub.downloadBytes,
        ul: sub.uploadBytes,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // مطلب 2026-06-12: AppBar نظيف بالاسم العربي (مطابق screenshot v1)
            _SimpleAppBar(
              title: 'subscribers.detail_title'.tr(),
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Sp.lg,
                  Sp.sm,
                  Sp.lg,
                  Sp.huge,
                ),
                children: [
                  // الهيرو الجديد — كرت teal كبير مع 3 إحصاءات.
                  _SubscriberHero(sub: sub, password: _subscriberPassword),
                  // بلوك الدين مباشرةً تحت بطاقة الهويّة كما في المخطّط
                  // (كان أسفل الصفحة بعد كارت الجهاز).
                  // ⚠️ تظهر دائماً — حتّى عند الصفر.
                  //
                  // 🐛 طلب المستخدم ٢٠٢٦-٠٩-٠٢: «بدل حقّ دين على
                  // المشترك يظهر رصيده إن كان عنده رصيد، ويصير إضافة
                  // دين».
                  //
                  // وكانت تختفي عند الصفر كلّيّاً، فيبقى المدير بلا
                  // جواب عن سؤالٍ يسأله في كلّ زيارة: «كم له وكم
                  // عليه؟». والصفر جوابٌ لا فراغ.
                  //
                  // ومعها مدخل «إضافة دين» على البطاقة نفسها بدل أن
                  // يبقى مدفوناً في «إجراءات أخرى».
                  const SizedBox(height: Sp.md),
                  BalanceCard(
                    sub: sub,
                    onRemind: sub.hasDebt &&
                            _sendingTemplate == null &&
                            sub.displayPhone.isNotEmpty
                        ? () => _sendTemplate('debt_reminder')
                        : null,
                    onPay: sub.balanceAmount != 0 &&
                            Perms.has('subscribers.pay_debt')
                        ? () => showPayDebtSheet(context, sub)
                        : null,
                    onAddDebt: Perms.has('subscribers.add_debt')
                        ? () => showAddDebtSheet(context, sub)
                        : null,
                  ),
                  // صفّ الإجراءات الأربعة — المخطّط يضعه مباشرةً تحت
                  // بلوك الدين وفوق كارت الاتصال. الباقي انتقل إلى شيت
                  // «إجراءات أخرى» خلف بلاطة «المزيد».
                  const SizedBox(height: Sp.md),
                  SubscriberActionTiles(actions: _quickActions()),
                  const SizedBox(height: Sp.md),
                  // معلومات الجلسة الحية (IP + مدّة + DL/UL) فقط عند الاتصال
                  // النشط الفعلي — أي RADIUS session قائم. مشترك online في
                  // SAS4 بلا session data (عادة تأخّر sync online-users)
                  // ما نعرض له كارت فارغ.
                  if (sub.isOnline &&
                      ((sub.ipAddress ?? '').isNotEmpty ||
                          (sub.sessionTime ?? 0) > 0 ||
                          (sub.downloadBytes ?? 0) > 0 ||
                          (sub.uploadBytes ?? 0) > 0)) ...[
                    _LiveSessionCard(sub: sub),
                    const SizedBox(height: Sp.sm),
                  ],
                  // معلومات الجهاز (ONT/UBNT) — تظهر لأي مشترك غير معطَّل
                  // ولم ينتهِ اشتراكه. الـcard يجرّب:
                  //   1) SAS4 IP لو موجود
                  //   2) customIp من DeviceConfig (يشتغل حتى بدون RADIUS session)
                  //   3) placeholder "لم يُتمكّن من الوصول" + زر إعدادات
                  // مطابق v1 (subscriber_details_screen.dart:2666-2685) —
                  // كان v2 يشترط sub.isOnline + IP نشط، يخفي كل الكارت
                  // للمشتركين اللي مفروض المدير يفحصهم أو يضبطهم
                  // (بلاغ 2026-07-13).
                  //
                  // ⚠️ ٢٠٢٦-٠٩-٠٢: وسقط الشرطان الباقيان أيضاً.
                  //
                  // بلاغ المستخدم: «معلومات الاتصال مال النانو مفروض
                  // حتّى لو معطّل تظهر». وهو محقّ، والسبب أعمق من
                  // الراحة: **التعطيل قرارٌ في الفوترة، والنانو جهازٌ
                  // على سطح بيت**. تعطيلُ الخدمة لا يُطفئ الجهاز ولا
                  // يُنزله.
                  //
                  // ومن يُعطَّل هو بالضبط من تحتاج فحص جهازه: هل
                  // ما زال في مكانه؟ هل نُقل إلى جارٍ؟ هل يُسحب منه
                  // إنترنت؟ وإخفاءُ الكارت عنه يمنع السؤال الذي
                  // يُطرح لأجله.
                  DeviceProbeCard(
                    ip: sub.ipAddress ?? '',
                    username: sub.username,
                  ),
                  const SizedBox(height: Sp.sm),
                  // مطلب 2026-06-12: _SubscriptionCard المنفصل أُلغي
                  // — كل معلوماته (الباقة/السعر/الانتهاء/التابع/الهاتف)
                  // صارت داخل _SubscriberHero. كرت الرصيد لا يزال يظهر
                  // مستقلاً لما الـbalance != 0.
                  //
                  // 2026-08-29 (S4): شبكة العمليّات ذات الـ18 بلاطة
                  // أُلغيت. المخطّط يوزّعها على ثلاث طبقات: أربع بلاطات
                  // فوق · زرّ تجديد أساسي هنا · والباقي في شيت «المزيد».
                  if (Perms.has('subscribers.activate')) ...[
                    const SizedBox(height: Sp.md),
                    SubscriberPrimaryAction(
                      icon: LucideIcons.refreshCw,
                      label: 'subscribers.renew_subscription'.tr(),
                      busy: _isBusy,
                      onTap: () => showActivateSheet(context, sub),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'subscribers.disconnect_user'.tr(),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'subscribers.disconnect_session_body'
              .tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('subscribers.disconnect'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runDisconnect();
  }

  Future<void> _runDisconnect() async {
    final id = sub.idx;
    if (id == null) return;
    setState(() => _disconnecting = true);
    final result = await SubscribersApi.disconnect(id);
    final success = result.ok;
    if (!mounted) return;
    setState(() {
      _disconnecting = false;
      if (success) sub = sub.copyWithOnline(online: false);
    });
    if (success) SubscriberEvents.notifyChange();
    // 2026-08-18: overlay بدل ScaffoldMessenger → يظهر فوق أي modal مفتوح.
    showSheetSnack(
      context,
      success
          ? 'subscribers.disconnect_ok_user'.tr()
          : 'subscribers.disconnect_failed'.tr(),
      isError: !success,
    );
  }

  Future<void> _confirmToggleEnabled() async {
    final wantEnable = sub.isDisabled;
    final action =
        wantEnable ? 'subscribers.enable'.tr() : 'subscribers.disable'.tr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'subscribers.confirm_action'.tr(namedArgs: {'action': action}),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          wantEnable
              ? 'subscribers.enable_body'.tr(namedArgs: {'name': sub.fullName})
              : 'subscribers.disable_body'
                  .tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: wantEnable ? AppColors.brand : AppColors.warning,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runToggleEnabled(wantEnable);
  }

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    // Front-line guard — backend rejects deletes for subs in debt
    // with a specific message, but warning the admin BEFORE the
    // round-trip is cheaper than waiting for the API to reject and
    // matches v1's flow.
    if (sub.hasDebt) {
      showSheetSnack(
        context,
        'subscribers.delete_debt_block'
            .tr(namedArgs: {'amt': formatIQD(sub.debtAbs.round())}),
        isError: true,
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'subscribers.delete_confirm_title'.tr(),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'subscribers.delete_confirm_body'
              .tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runDelete();
  }

  Future<void> _runDelete() async {
    final idx = sub.idx;
    if (idx == null) return;
    setState(() => _deleting = true);
    final result = await SubscribersApi.delete(idx);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (result.ok) {
      SubscriberEvents.notifyChange();
      showSheetSnack(context, 'subscribers.delete_ok'.tr());
      // Pop back to the list — the subscriber no longer exists and
      // the underlying state will refresh from dataChanged.
      Navigator.of(context).pop();
    } else {
      showSheetSnack(
        context,
        result.message ?? 'subscribers.delete_failed'.tr(),
        isError: true,
      );
    }
  }

  Future<void> _sendTemplate(String templateType) async {
    if (_sendingTemplate != null) return; // single flight per screen
    setState(() => _sendingTemplate = templateType);
    // 2026-08-26: sendTemplateWithPreview يعرض preview + chip قبل الإرسال.
    // يقرأ ManualWaPrefs الافتراضي ويسمح للمدير بتبديل الوضع لهذه العمليّة.
    final result = await WhatsAppApi.sendTemplateWithPreview(
      context: context,
      sub: sub,
      templateType: templateType,
    );
    if (!mounted) return;
    setState(() => _sendingTemplate = null);
    // reason='cancelled' → المدير أغلق الـpreview sheet، لا snackbar.
    if (result.reason == 'cancelled') return;
    final ok = result.ok;
    final defaultOkMsg = switch (templateType) {
      'debt_reminder' => 'subscribers.wa_debt_reminder_sent'.tr(),
      'expiry_warning' => 'subscribers.wa_expiry_warning_sent'.tr(),
      'subscriber_info' => 'subscribers.wa_subscriber_info_sent'.tr(),
      _ => 'subscribers.wa_message_sent'.tr(),
    };
    final chArabic = result.channelArabic;
    // للوضع اليدوي: result.message يحمل تعليمة "افتح واتساب واضغط إرسال"
    // — نعرضها كـsuccess (isError=false) رغم إن الإرسال لسّه ما تمّ فعلاً.
    final msg = ok
        ? (result.message ??
            (chArabic != null ? '$defaultOkMsg · عبر $chArabic' : defaultOkMsg))
        : (result.message ?? 'subscribers.wa_message_send_failed'.tr());
    showSheetSnack(context, msg, isError: !ok);
  }

  Future<void> _runToggleEnabled(bool wantEnable) async {
    final id = sub.idx;
    if (id == null) return;
    setState(() => _toggling = true);
    final success = await SubscribersApi.toggle(id, enable: wantEnable);
    if (!mounted) return;
    // The backend disconnects any live session on disable (matches v1 —
    // see /api/v2/subscribers/:idx/toggle-enabled in server.js). Reflect
    // that locally so the live session card disappears immediately
    // without waiting for the dataChanged refresh.
    setState(() {
      _toggling = false;
      if (success && !wantEnable && sub.isOnline) {
        sub = sub.copyWithOnline(online: false);
      }
    });
    if (success) SubscriberEvents.notifyChange();
    if (!mounted) return;
    showSheetSnack(
      context,
      success
          ? (wantEnable
              ? 'subscribers.enable_ok'.tr()
              : 'subscribers.disable_ok'.tr())
          : (wantEnable
              ? 'subscribers.enable_failed'.tr()
              : 'subscribers.disable_failed'.tr()),
      isError: !success,
    );
  }

  // ═══════════ الشريحة 4 — بناء الإجراءات ═══════════
  //
  // الشبكة القديمة كانت تبني `List<_Op>` واحدة بـ18 عنصراً وتعرضها
  // دفعةً واحدة. المخطّط يوزّعها: أربع بلاطات + زرّ تجديد + شيت.
  // البوّابات (`Perms.has`) نُقلت كما هي حرفيّاً — لا إجراء يظهر لمن
  // لا يملكه، ولا إجراء سقط في النقل.

  /// البلاطات الأربع: تمديد · تعديل · تعطيل/تفعيل · المزيد.
  /// «المزيد» حاضرة دائماً — هي المدخل الوحيد لباقي العمليّات.
  List<SubAction> _quickActions() {
    return <SubAction>[
      if (Perms.has('subscribers.extend'))
        SubAction(
          icon: LucideIcons.calendarPlus,
          label: 'subscribers.op_extend'.tr(),
          onTap: _isBusy ? null : () => showExtendSheet(context, sub),
        ),
      if (Perms.has('subscribers.edit'))
        SubAction(
          icon: LucideIcons.pencil,
          label: 'subscribers.op_edit'.tr(),
          onTap: _isBusy ? null : () => showEditSubscriberSheet(context, sub),
        ),
      if (Perms.has('subscribers.toggle'))
        SubAction(
          icon: sub.isDisabled ? LucideIcons.circleCheck : LucideIcons.ban,
          label: sub.isDisabled
              ? 'subscribers.enable'.tr()
              : 'subscribers.disable'.tr(),
          color: sub.isDisabled ? AppColors.success : AppColors.warningFill,
          busy: _toggling,
          onTap: (sub.idx == null || _isBusy) ? null : _confirmToggleEnabled,
        ),
      SubAction(
        icon: LucideIcons.ellipsis,
        label: 'subscribers.more_actions'.tr(),
        color: AppColors.textMid,
        onTap: () => showMoreActionsSheet(
          context,
          subtitle: sub.username,
          groups: _moreGroups(),
        ),
      ),
    ];
  }

  /// مجموعات شيت «إجراءات أخرى». ما ظهر كبلاطة أعلاه (تمديد/تعديل/
  /// تعطيل) وما ظهر كزرّ أساسي (تجديد) لا يتكرّر هنا.
  List<SubActionGroup> _moreGroups() {
    final phone = sub.displayPhone;
    return <SubActionGroup>[
      SubActionGroup('subscribers.group_money'.tr(), [
        if (Perms.has('subscribers.add_debt'))
          SubAction(
            icon: LucideIcons.plus,
            label: 'subscribers.op_add_debt'.tr(),
            color: AppColors.warningFill,
            onTap: () => showAddDebtSheet(context, sub),
          ),
        // 2026-08-29: الشرط صار `balanceAmount != 0` بدل `hasDebt` —
        // صاحب الرصيد الدائن يحتاج المدخل أيضاً، ومَن رصيده صفر لا
        // يستفيد من فتح شيت يقول له «لا يوجد دين».
        if (sub.balanceAmount != 0 && Perms.has('subscribers.pay_debt'))
          SubAction(
            icon: LucideIcons.banknote,
            label: 'subscribers.op_pay_debt'.tr(),
            color: AppColors.brandAccent,
            meta: sub.balanceAmount != 0
                ? formatIQD(sub.balanceAmount.abs())
                : null,
            onTap: () => showPayDebtSheet(context, sub),
          ),
        if (Perms.has('discounts.manage'))
          SubAction(
            icon: LucideIcons.tag,
            label: 'subscribers.op_quick_discount'.tr(),
            onTap: () => showQuickDiscountSheet(context, sub),
          ),
      ]),
      SubActionGroup('subscribers.group_contact'.tr(), [
        if (sub.hasDebt && Perms.has('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.bellRing,
            label: 'subscribers.op_debt_reminder'.tr(),
            color: AppColors.warningFill,
            busy: _sendingTemplate == 'debt_reminder',
            onTap: () => _sendTemplate('debt_reminder'),
          ),
        if (sub.isNearExpiry && Perms.has('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.alarmClock,
            label: 'subscribers.op_expiry_warning'.tr(),
            color: AppColors.warningFill,
            busy: _sendingTemplate == 'expiry_warning',
            onTap: () => _sendTemplate('expiry_warning'),
          ),
        if (Perms.has('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.info,
            label: 'subscribers.op_send_info'.tr(),
            busy: _sendingTemplate == 'subscriber_info',
            onTap: () => _sendTemplate('subscriber_info'),
          ),
        if (Perms.has('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.qrCode,
            label: 'subscribers.op_qr_login'.tr(),
            onTap: () => showQrLoginSheet(context, sub),
          ),
        if (phone.isNotEmpty)
          SubAction(
            icon: LucideIcons.phone,
            label: 'subscribers.call'.tr(),
            meta: phone,
            onTap: () => _launchUri(Uri.parse('tel:$phone')),
          ),
        if (phone.isNotEmpty)
          SubAction(
            icon: LucideIcons.messageCircle,
            label: 'subscribers.op_whatsapp'.tr(),
            color: AppColors.success,
            onTap: () =>
                _launchUri(Uri.parse('https://wa.me/${_digits(phone)}')),
          ),
      ]),
      SubActionGroup('subscribers.group_records'.tr(), [
        // ⚠️ لا شرطَ اتّصال.
        //
        // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «الاستهلاك مفروض يظهر حتّى لو طافي
        // المشترك». والاستهلاك **تاريخٌ** يقرأه SAS4 من سجلّاته
        // (يوميّ ٣١ خانة · شهريّ ١٢)، لا قياسٌ لحظيّ من الجلسة.
        //
        // بل هو أنفع للمنقطع: من يشكو انقطاعاً تُسأل عن استهلاكه
        // أمس، ومن يُخفيه الشرطُ عنك هو بالضبط من تحتاج بياناته.
        SubAction(
          icon: LucideIcons.chartLine,
          label: 'subscribers.op_consumption'.tr(),
          onTap: () => showConsumptionSheet(context, sub),
        ),
        if (Perms.has('subscribers.view_activity'))
          SubAction(
            icon: LucideIcons.history,
            label: 'subscribers.op_movements'.tr(),
            onTap: () => showMovementsSheet(context, sub),
          ),
        if (Perms.has('reports.account_statement'))
          SubAction(
            icon: LucideIcons.fileText,
            label: 'subscribers.account_statement'.tr(),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AccountStatementScreen(
                  username: sub.username,
                  // firstname/lastname غير قابلين للـnull في الموديل —
                  // نمرّر null فقط حين يكونان فارغين معاً.
                  displayName:
                      sub.fullName.trim().isEmpty ? null : sub.fullName.trim(),
                  phone: sub.phone,
                ),
              ),
            ),
          ),
        // 2026-08-26: يظهر إذا الموقع مُعيَّن (أيّ موظّف يفتحه بالخرائط)
        // أو الموظّف يملك صلاحيّة تعديله.
        if (sub.hasLocation || Perms.has('subscribers.edit_location'))
          SubAction(
            icon: LucideIcons.mapPin,
            label: sub.hasLocation
                ? 'subscribers.op_location'.tr()
                : 'subscribers.op_location_add'.tr(),
            onTap: () async {
              if (!sub.hasLocation) {
                await showLocationEditSheet(context, sub: sub);
                return;
              }
              await showLocationSheet(context, sub: sub);
            },
          ),
      ]),
      SubActionGroup('subscribers.group_danger'.tr(), [
        if (sub.isOnline && sub.idx != null)
          SubAction(
            icon: LucideIcons.power,
            label: 'subscribers.disconnect_user'.tr(),
            color: AppColors.error,
            busy: _disconnecting,
            onTap: _confirmDisconnect,
          ),
        if (Perms.has('subscribers.delete'))
          SubAction(
            icon: LucideIcons.trash2,
            label: 'common.delete'.tr(),
            color: AppColors.error,
            busy: _deleting,
            onTap: sub.idx == null ? null : _confirmDelete,
          ),
      ]),
    ];
  }

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  Future<void> _launchUri(Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!mounted) return;
    if (!ok) {
      showSheetSnack(context, 'لا يمكن فتح الرابط', isError: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// كارت «معلومات الاتصال» — كارت أبيض r20 بحدّ 1px وبلا ظلّ، رأسه
/// أيقونة 18 بلون الـaccent + عنوان 14/w600 وحبّة «متصل منذ …» في
/// الطرف، وجسمه ثلاث بلاطات غاطسة (#F7F8F5 / r14): تحميل · رفع · IP.
class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ip = sub.ipAddress ?? '';
    final secs = sub.sessionTime ?? 0;
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⚠️ لا `Spacer` هنا — بل `Expanded` يلفّ الشارة و`Align` يدفعها.
          //
          // 🐛 كان الصفّ: أيقونة + عنوان **ثابت** + `Spacer` + شارةٌ ثابتة،
          // فلا مرنَ فيه يمتصّ الضيق. قِيس بالخطّ الحقيقيّ عند ٣٢٠:
          //   ١٨ + ٨ + عنوان ٩٢٫٥ + شارة ١٧٤٫٨ = ٢٩٣٫٣ في ٢٥٦ متاحة
          // → **فيضٌ أحمر بمقدار ٣٧ نقطة**. وعند ٣٦٠ يمرّ بفارق ٢٫٧ نقطة
          // فقط — فجلسةٌ أطول («100 يوم») تُفيضه هناك أيضاً.
          //
          // والعنوان يبقى ثابتاً عمداً: نصٌّ واحدٌ معلوم لا يحتاج مرونة.
          // والشارة داخل `Expanded` + `Align.centerEnd` تنال الطرف كما
          // كانت مع `Spacer`، لكنّها الآن **محدودةٌ بالمتاح** فتقصّ مدّتها
          // بدل أن تفيض. راجع `test/text_truncation_test.dart`.
          Row(
            children: [
              Icon(Icons.wifi_rounded, size: 18, color: AppColors.brandAccent),
              const SizedBox(width: Sp.sm),
              Text('subscribers.section_connection'.tr(),
                  style: AppType.cardTitle()),
              const SizedBox(width: Sp.sm),
              if (secs > 0)
                Expanded(
                    child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.brandSoftBg,
                            borderRadius: BorderRadius.circular(R.pill),
                            border:
                                Border.all(color: AppColors.brandSoftBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: AppColors.successDot,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'متصل منذ ${_formatDuration(secs)}',
                                  style: AppType.bodyStrong(
                                          color: AppColors.brandOnSoft)
                                      .copyWith(fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ))),
            ],
          ),
          const SizedBox(height: 14),
          // 🐛 بلاغ 2026-08-31: عنوان الـIP مقصوص — «10.100.11…».
          //
          // كان ثلاث بلاطات في صفّ، فالعنوان يأخذ الثلث:
          //   المتاح @430dp ≈ 91 نقطة · @414 ≈ 86 · @360 ≈ 68 · @320 ≈ 55
          //   «192.168.100.254» يحتاج 113.8 نقطة
          // فلم يتّسع على **أيّ** جهاز قطّ. والقصّ يأكل آخر العنوان —
          // أي رقم المضيف نفسه، وهو الجزء الوحيد الذي يميّز جهازاً عن
          // آخر. والبلاطة قابلة للنقر لفتح الجهاز، فالمدير ينقر عنواناً
          // لا يستطيع قراءته.
          //
          // التحميل والرفع قصيران وثابتا الشكل («4.9 GB») فيبقيان
          // شريكَين؛ والعنوان ينزل صفّاً كاملاً — 348 نقطة على 414dp،
          // أي 3× حاجته.
          Row(
            children: [
              Expanded(
                child: _SunkenTile(
                  icon: Icons.south_rounded,
                  label: 'subscribers.label_download'.tr(),
                  value: _formatBytes(sub.downloadBytes ?? 0),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _SunkenTile(
                  icon: Icons.north_rounded,
                  label: 'subscribers.label_upload'.tr(),
                  value: _formatBytes(sub.uploadBytes ?? 0),
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          if (ip.isNotEmpty) ...[
            const SizedBox(height: 9),
            _SunkenTile(
              icon: Icons.open_in_new_rounded,
              label: 'IP',
              value: ip,
              color: AppColors.textHi,
              onTap: () => launchUrl(
                Uri.parse('http://$ip'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// «11 يوم 6س 28د». النسخة السابقة كانت ساعات فقط فتعرض «270س».
  static String _formatDuration(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$d يوم $hس $mد';
    if (h > 0) return '$hس $mد';
    return '$mد';
  }

  /// 🐛 كان يقفز إلى الميغابايت دائماً، فـ20 كيلوبايت تُعرَض «0.0 MB» —
  /// وهي بصريّاً «لا شيء». مشتركٌ فتح جلسةً وسحب قليلاً يبدو كمن لم
  /// يسحب أبداً، وهو الفرق بين «الخطّ يعمل» و«الخطّ ميّت».
  ///
  /// الدرجات الأصغر تُضاف لأنّ الصدق أهمّ من ثبات الوحدة، والبلاطة
  /// تتّسع لها («512 KB» ليست أطول من «0.0 MB»).
  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    const kb = 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

/// البلاطة الغاطسة — تسمية 10.5 فوق قيمة 14/w700 ملوّنة دلاليّاً.
class _SunkenTile extends StatelessWidget {
  const _SunkenTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.textLabel),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: AppType.micro(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textDirection: ui.TextDirection.ltr,
            style: AppType.cardTitle(color: color)
                .copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.icon),
      child: body,
    );
  }
}

/// Slim one-line balance card — wrapping the section header pattern
/// would duplicate the 'دين على المشترك' label inside the title, so we
/// render a single inline row: icon + label on the leading edge, the
/// amount as a colored chip on the trailing edge. Reads at-a-glance
/// without dominating the screen like the previous hero number did.

/// مطلب 2026-06-12: AppBar نظيف مطابق screenshot v1 — الاسم العربي
/// مركزي + سهم رجوع يميني (RTL يعكس). بدون ظل.
/// ترويسة صفحة المشترك — المخطّط يجعلها خفيفة عمداً: زرّ رجوع 38×38
/// أبيض بحدّ و r14، وعنوان عامّ 14/w600 في الوسط، ومساحة مكافئة يساراً
/// ليبقى العنوان متمركزاً بصريّاً.
///
/// العنوان **عامّ** («تفاصيل المشترك») لا اسم المشترك: الاسم يظهر
/// بحجم 20/w700 في بطاقة الهويّة تحته مباشرةً، وتكراره يزاحمها.
class _SimpleAppBar extends StatelessWidget {
  const _SimpleAppBar({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.x6, Sp.lg, Sp.x6),
      color: AppColors.bg,
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.icon),
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(R.icon),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.icon),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                width: H.iconBtn,
                height: H.iconBtn,
                child: Icon(LucideIcons.arrowRight,
                    size: 20, color: AppColors.textBody),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: AppType.cardTitle(color: AppColors.textBody),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: H.iconBtn),
        ],
      ),
    );
  }
}

/// مطلب 2026-06-12 (screenshot v1): كرت هيرو teal كبير في أعلى
/// صفحة المشترك. يعرض: أيقونة دائرة بيضاء كبيرة مع حرف/رقم الباقة
/// + الاسم الكامل + username + 3 إحصاءات بالأسفل (الدين / الباقة
/// / الأيام المتبقية).
/// بطاقة الهويّة — البلوك الأوّل في صفحة المشترك حسب المخطّط.
///
/// بطاقة داكنة واحدة `#103D2E` بنصف قطر 26 تجمع خمس طبقات كانت مبعثرة:
/// الاسم وشارة الاتصال · صفّ بيانات الدخول · شبكة إحصاءات ثلاثيّة ·
/// صفّ الهاتف · تذييل التابعيّة والانتهاء.
///
/// الطبقات مبنيّة على أبيض شفّاف فوق الأخضر (`onBrandFill1` = .09
/// للأسطح، `.14` للحبّات والفواصل) — وهذا هو سبب عدم حاجتها لأيّ تعديل
/// في الوضع الداكن: سطحها داكن أصلاً في الحالتين.
///
/// ⚠️ فرق مقصود عن المخطّط: المخطّط يلوّن البطاقة أخضر ثابتاً دائماً،
/// بينما التنفيذ السابق كان يلوّنها حسب الحالة (طلب المستخدم 2026-07-16:
/// «تمييز فوري للحالة»). حَفِظنا القصد داخل لغة المخطّط: البطاقة تبقى
/// خضراء، وحالة المشترك تُقرأ من **حبّة الحالة** أعلى اليسار (نقطة
/// نعناعيّة + تسمية) ومن لون بلاطة الأيّام.
class _SubscriberHero extends StatelessWidget {
  const _SubscriberHero({required this.sub, this.password});
  final Subscriber sub;

  /// null = لم تصل بعد من الـbackend. الباسورد **بلا بوّابة صلاحيّات**
  /// (قرار 2026-08-25): هو بيانات خدمة يحتاجها الدعم لمساعدة المشترك.
  final String? password;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final phone = sub.displayPhone;
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        // `brandSurface` لا `brand`: كلّ طبقات onBrand* داخل البطاقة
        // معايرة على #103D2E الثابت. راجع تعليقه في colors.dart.
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(),
          const SizedBox(height: Sp.md),
          _credentialsRow(context),
          const SizedBox(height: Sp.lg),
          _statsGrid(),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            _phoneRow(context, phone),
          ],
          const SizedBox(height: Sp.md),
          _footer(),
        ],
      ),
    );
  }

  // ───────── الاسم + حبّة الحالة ─────────

  Widget _titleRow() {
    final st = _statusPill();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                normalizeDigits(sub.fullName) ?? sub.username,
                style: AppType.heroName(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'بيانات الدخول',
                style: AppType.muted(color: AppColors.onBrandTertiary)
                    .copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: Sp.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.onBrandFill2,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: st.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                st.$1,
                style: AppType.body(color: AppColors.onBrand)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// (التسمية، لون النقطة). الحالة تُقرأ من هنا بدل تلوين البطاقة كلّها.
  (String, Color) _statusPill() {
    if (sub.isDisabled) return ('معطّل', AppColors.onBrandDanger);
    if (sub.isExpired) return ('منتهي', AppColors.onBrandDanger);
    if (sub.isOnline) return ('متصل', AppColors.onBrandMint);
    return ('غير متصل', AppColors.onBrandTertiary);
  }

  // ───────── بيانات الدخول ─────────

  Widget _credentialsRow(BuildContext context) {
    final pass = password;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.onBrandFill1,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Row(
        children: [
          // ⚠️ وزنٌ بحسب المحتوى: اسم المستخدم أطول من كلمة السرّ عادةً.
          //
          // 🐛 كانا `Flexible(1)` و`Expanded(1)` — أي مناصفةً. وعند ٣٢٠
          // يبقى للطرفين ١٧٥ نقطة، فيُحدّ الاسم بـ٨٧٫٥ بينما
          // «unc.thaaer@popq» يحتاج نحو ١٠٥. والاثنان بيانات دخولٍ
          // تُنسخ، فقصُّ أحدهما يُفقده معناه.
          //
          // ٣:٢ يعطي الاسم ١٠٥ وكلمة السرّ ٧٠ — يكفيان المقيس.
          Flexible(
            flex: 3,
            child: Text(
              sub.username,
              textDirection: ui.TextDirection.ltr,
              style: AppType.body(color: AppColors.onBrand)
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          _OnBrandIcon(
            icon: Icons.content_copy_rounded,
            size: 16,
            onTap: () => _copy(context, sub.username, 'تمّ نسخ اسم المستخدم'),
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: AppColors.onBrandFill3,
          ),
          if (pass == null)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.onBrandTertiary,
              ),
            )
          else
            Expanded(flex: 2, child: _HeroPassword(password: pass)),
        ],
      ),
    );
  }

  // ───────── شبكة الإحصاءات الثلاثيّة ─────────

  Widget _statsGrid() {
    final debt = sub.balanceAmount;
    final price = sub.price;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.onBrandFill1,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              value: debt == 0 ? '—' : formatIQD(debt.abs()),
              // ⚠️ ثلاث حالات لا اثنتان: من رصيده صفر لا دين عليه،
              // ووسمُه بـ«الدين» يجعل الشاشة تتّهمه بما ليس فيه.
              label: debt > 0
                  ? 'رصيد دائن'
                  : debt < 0
                      ? 'الدين'
                      : 'الرصيد',
              color: debt < 0 ? AppColors.onBrandDanger : AppColors.onBrand,
            ),
          ),
          _divider(),
          Expanded(
            child: _stat(
              value: sub.profileName ?? '—',
              label: price != null && price > 0
                  ? 'الباقة · ${formatIQD(price)}'
                  : 'الباقة',
              valueSize: 15,
            ),
          ),
          _divider(),
          Expanded(
            child: _stat(
              value: _remaining().$1,
              label: _remaining().$2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        color: AppColors.onBrandFill2,
      );

  Widget _stat({
    required String value,
    required String label,
    Color? color,
    double valueSize = 17,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ يتقلّص ولا يُقصّ.
        //
        // 🐛 الأعمدة الثلاثة `Expanded` متساوية = ٧٦٫٧ نقطة لكلٍّ عند
        // ٣٢٠. واسم الباقة أطولها بكثير («10M-Unlimited-30D» = ١٤٠
        // نقطة) فيُقصّ **عند كلّ العروض حتّى ٤٣٠**.
        //
        // والوزن غير المتساوي يحلّ الباقة ويكسر الرصيد. و`scaleDown`
        // يحلّ الثلاثة معاً: كلٌّ يتقلّص بقدر حاجته ويبقى مقروءاً
        // كاملاً — واسم باقةٍ ناقصٌ لا يُعرف صاحبه.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textDirection: ui.TextDirection.ltr,
            style: AppType.statValue(color: color ?? AppColors.onBrand)
                .copyWith(fontSize: valueSize),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppType.muted(color: AppColors.onBrandSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// (القيمة الكبيرة، التسمية). محسوبة من `parsedExpiration` — لا من
  /// `remainingDays` (SAS4 يقرّب لأعلى فيعطي 31 لباقة 30).
  (String, String) _remaining() {
    final exp = sub.parsedExpiration;
    if (exp == null) return ('—', 'الأيام المتبقية');
    final diff = exp.difference(DateTime.now());
    if (diff.isNegative) return ('0', 'منتهي');
    final d = diff.inDays;
    final h = diff.inHours.remainder(24);
    final m = diff.inMinutes.remainder(60);
    if (d > 0) return ('$d يوم', '$hس $mد');
    if (h > 0) return ('$hس', '$mد');
    return ('$mد', 'أقل من ساعة');
  }

  // ───────── الهاتف ─────────

  Widget _phoneRow(BuildContext context, String phone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.onBrandFill1,
        borderRadius: BorderRadius.circular(R.icon),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_rounded,
              size: 17, color: AppColors.onBrandSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _openUri(context, Uri.parse('tel:$phone')),
              child: Text(
                phone,
                textDirection: ui.TextDirection.ltr,
                style: AppType.body(color: AppColors.onBrand)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _OnBrandIcon(
            icon: Icons.content_copy_rounded,
            size: 16,
            onTap: () => _copy(context, phone, 'تمّ نسخ الرقم'),
          ),
          const SizedBox(width: 12),
          _OnBrandIcon(
            icon: Icons.chat_rounded,
            size: 17,
            color: AppColors.onBrandMint,
            onTap: () => _openUri(
              context,
              Uri.parse(
                  'https://wa.me/${phone.replaceAll(RegExp(r"[^0-9]"), "")}'),
            ),
          ),
        ],
      ),
    );
  }

  // ───────── التذييل ─────────

  Widget _footer() {
    final parent = sub.parentUsername;
    final exp = sub.parsedExpiration;
    String two(int n) => n.toString().padLeft(2, '0');
    return Row(
      children: [
        // ⚠️ `Flexible` و`Spacer` شقيقان بنفس الـflex الافتراضيّ (1)،
        // فيتقاسمان الفراغ **مناصفةً** — والفضفاض (loose) لا يستطيع
        // مطالبة الضيّق (tight) بنصفه ولو كان فارغاً. فاسم المدير
        // محبوسٌ في نصف الصفّ مهما اتّسع الباقي:
        //   «تابع إلى najaf650» يحتاج 100.9 نقطة، والنصف يعطيه أقلّ
        //   على 320 و360 — فيُقصّ إلى «تابع إلى naja…».
        //
        // الحلّ إعطاء الاسم `Expanded` (tight) فيأخذ كلّ ما تبقّى بعد
        // التاريخ. و`Spacer` تبقى في فرع «لا مدير أب» — وهي ليست
        // اختياريّة هناك: المشتركون تحت الأدمن الأعلى `parentUsername`
        // فيهم null وهي الحالة الشائعة، وبلا الفراغ يلتصق التاريخ
        // بالطرف الخطأ.
        if (parent != null && parent.isNotEmpty) ...[
          const Icon(Icons.shield_rounded,
              size: 15, color: AppColors.onBrandSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'تابع إلى $parent',
              style: AppType.muted(color: AppColors.onBrandSecondary)
                  .copyWith(fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Sp.sm),
        ] else
          const Spacer(),
        if (exp != null)
          Text(
            '${exp.year}/${two(exp.month)}/${two(exp.day)} '
            '${two(exp.hour)}:${two(exp.minute)}',
            textDirection: ui.TextDirection.ltr,
            style: AppType.muted(color: AppColors.onBrandSecondary)
                .copyWith(fontSize: 11.5),
          ),
      ],
    );
  }

  static Future<void> _openUri(BuildContext ctx, Uri uri) async {
    if (!await canLaunchUrl(uri)) {
      if (!ctx.mounted) return;
      showSheetSnack(ctx, 'لا يمكن فتح الرابط', isError: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _copy(
      BuildContext context, String value, String msg) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    showSheetSnack(context, msg, duration: const Duration(seconds: 2));
  }
}

/// أيقونة تفاعليّة فوق البطاقة الداكنة — بلا خلفيّة، بلون أبيض شفّاف
/// كما في المخطّط (لا كبسولة دائريّة كالنسخة السابقة).
class _OnBrandIcon extends StatelessWidget {
  const _OnBrandIcon({
    required this.icon,
    required this.onTap,
    this.size = 16,
    this.color,
  });
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Icon(icon, size: size, color: color ?? AppColors.onBrandSecondary),
    );
  }
}

/// نقاط كلمة السرّ + عين الإظهار + النسخ. النسخ يعمل والباس مخفي.
/// `letterSpacing: 2.7` مطلوب وإلّا التصقت النقاط (المخطّط: 0.2em).
class _HeroPassword extends StatefulWidget {
  const _HeroPassword({required this.password});
  final String password;

  @override
  State<_HeroPassword> createState() => _HeroPasswordState();
}

class _HeroPasswordState extends State<_HeroPassword> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final shown =
        _visible ? widget.password : '•' * widget.password.length.clamp(4, 12);
    return Row(
      children: [
        Flexible(
          child: Text(
            shown,
            textDirection: ui.TextDirection.ltr,
            style: _visible
                ? AppType.body(color: AppColors.onBrandStrong)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600)
                : AppType.password(color: AppColors.onBrandStrong),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _OnBrandIcon(
          icon: _visible
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          size: 17,
          onTap: () => setState(() => _visible = !_visible),
        ),
        const SizedBox(width: 10),
        _OnBrandIcon(
          icon: Icons.content_copy_rounded,
          size: 17,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.password));
            if (!context.mounted) return;
            showSheetSnack(context, 'تمّ نسخ كلمة المرور',
                duration: const Duration(seconds: 2));
          },
        ),
      ],
    );
  }
}

class _CopyChip extends StatefulWidget {
  const _CopyChip({required this.value, required this.context});
  final String value;
  // ignore: avoid_field_initializers_in_const_classes
  final BuildContext context;

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    // `widget.context` سياق ويدجت أخرى: `mounted` أعلاه يخصّ هذه
    // الحالة لا تلك، فقد تكون تلك ماتت وهذه حيّة.
    if (!widget.context.mounted) return;
    showSheetSnack(
      widget.context,
      'تم نسخ ${widget.value}',
      duration: const Duration(seconds: 2),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: _copy,
        radius: 16,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.onBrand.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.onBrand.withValues(alpha: 0.3), width: 1),
          ),
          child: Icon(
            _copied ? LucideIcons.check : LucideIcons.copy,
            size: 12,
            color: AppColors.onBrand,
          ),
        ),
      ),
    );
  }
}

/// صفّ الباسورد في الهيرو — عين إظهار/إخفاء + زرّ copy.
/// النسخ يعمل حتى والباس مخفي بالنجوم. أُضيف 2026-08-18 لتوفير
/// نسخ سريع دون فتح شاشة التعديل.
class _PasswordRow extends StatefulWidget {
  const _PasswordRow({required this.password});
  final String password;

  @override
  State<_PasswordRow> createState() => _PasswordRowState();
}

class _PasswordRowState extends State<_PasswordRow> {
  bool _visible = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.password));
    if (!mounted) return;
    setState(() => _copied = true);
    showSheetSnack(
      context,
      'تمّ نسخ كلمة المرور',
      duration: const Duration(seconds: 2),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final display =
        _visible ? widget.password : '•' * widget.password.length.clamp(4, 12);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.lock,
            size: 11, color: AppColors.onBrand.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            display,
            style: TextStyle(
              color: AppColors.onBrand.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: _visible ? 0 : 2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        _MiniHeroIconButton(
          icon: _visible ? LucideIcons.eyeOff : LucideIcons.eye,
          onTap: () => setState(() => _visible = !_visible),
        ),
        const SizedBox(width: 4),
        _MiniHeroIconButton(
          icon: _copied ? LucideIcons.check : LucideIcons.copy,
          onTap: _copy,
        ),
      ],
    );
  }
}

/// زرّ أيقونة صغير دائري بخلفيّة أبيض شفّاف — يُستعمل في هيرو
/// الكارت للعين والنسخ. حجم 24 (أصغر من _CopyChip=28 لأنّه بجنب
/// حقل نص محدود).
class _MiniHeroIconButton extends StatelessWidget {
  const _MiniHeroIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: onTap,
        radius: 14,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.onBrand.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.onBrand.withValues(alpha: 0.3), width: 1),
          ),
          child: Icon(icon, size: 11, color: AppColors.onBrand),
        ),
      ),
    );
  }
}
