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
import '../../services/manual_wa_sender.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/manual_wa_chip.dart';
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
import 'widgets/device_probe_card.dart';

/// Subscriber details — v2 visual shell over v1's structure. Layout
/// top→bottom (info → operations):
///   1. Header — avatar + status + name + username + close.
///   2. Live session card (when online) — IP / MAC / duration + DL/UL.
///   3. Subscription card — package + price + expiry + parent + phone.
///   4. Balance hero card (when non-zero).
///   5. Operations card AT THE BOTTOM — every action v1 surfaces in
///      its FAB sheet, in a single 3-column grid: تعديل / تفعيل /
///      تمديد / إضافة دين / تسديد دين / خصم سريع / سجل الحركات /
///      تذكير دين / تذكير انتهاء / توليد رابط / إرسال المعلومات /
///      حذف / تعطيل-تفعيل حساب / اتصال / واتساب / فصل المستخدم.
///
/// Info cards are intentionally tight (smaller padding, 4px row gaps)
/// so the operations grid has room to breathe without scrolling on
/// most phones.
class SubscriberDetailScreen extends StatefulWidget {
  const SubscriberDetailScreen({super.key, required this.sub});
  final Subscriber sub;

  @override
  State<SubscriberDetailScreen> createState() =>
      _SubscriberDetailScreenState();
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
  bool _generatingLink = false;
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
      _disconnecting ||
      _toggling ||
      _sendingTemplate != null ||
      _generatingLink ||
      _deleting;

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
      list = await SubscribersApi.loadAll()
          .timeout(const Duration(seconds: 20));
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
              title: sub.fullName,
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
                  if (sub.balanceAmount != 0) ...[
                    const SizedBox(height: Sp.md),
                    _BalanceCard(
                      sub: sub,
                      onRemind: sub.hasDebt &&
                              _sendingTemplate == null &&
                              sub.displayPhone.isNotEmpty
                          ? () => _sendTemplate('debt_reminder')
                          : null,
                      onPay: Perms.has('subscribers.pay_debt')
                          ? () => showPayDebtSheet(context, sub)
                          : null,
                    ),
                  ],
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
                  if (!sub.isExpired && !sub.isDisabled) ...[
                    DeviceProbeCard(
                      ip: sub.ipAddress ?? '',
                      username: sub.username,
                    ),
                    const SizedBox(height: Sp.sm),
                  ],
                  // مطلب 2026-06-12: _SubscriptionCard المنفصل أُلغي
                  // — كل معلوماته (الباقة/السعر/الانتهاء/التابع/الهاتف)
                  // صارت داخل _SubscriberHero. كرت الرصيد لا يزال يظهر
                  // مستقلاً لما الـbalance != 0.
                  const SizedBox(height: Sp.md),
                  _OperationsCard(
                    sub: sub,
                    disconnecting: _disconnecting,
                    onDisconnect: sub.isOnline && sub.idx != null
                        ? _confirmDisconnect
                        : null,
                    toggling: _toggling,
                    onToggleEnabled:
                        sub.idx != null ? _confirmToggleEnabled : null,
                    sendingTemplate: _sendingTemplate,
                    onSendTemplate: _sendTemplate,
                    generatingLink: _generatingLink,
                    onGenerateLink: _generateInfoLink,
                    onQrLogin: () => showQrLoginSheet(context, sub),
                    deleting: _deleting,
                    onDelete: sub.idx != null ? _confirmDelete : null,
                    busy: _isBusy,
                  ),
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
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'subscribers.disconnect_session_body'.tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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
      success ? 'subscribers.disconnect_ok_user'.tr() : 'subscribers.disconnect_failed'.tr(),
      isError: !success,
    );
  }

  Future<void> _confirmToggleEnabled() async {
    final wantEnable = sub.isDisabled;
    final action = wantEnable ? 'subscribers.enable'.tr() : 'subscribers.disable'.tr();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'subscribers.confirm_action'.tr(namedArgs: {'action': action}),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          wantEnable
              ? 'subscribers.enable_body'.tr(namedArgs: {'name': sub.fullName})
              : 'subscribers.disable_body'.tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  wantEnable ? AppColors.brand : const Color(0xFFCD8B00),
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
        'subscribers.delete_debt_block'.tr(namedArgs: {'amt': formatIQD(sub.debtAbs.round())}),
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
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'subscribers.delete_confirm_body'.tr(namedArgs: {'name': sub.fullName}),
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
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

  Future<void> _generateInfoLink() async {
    if (_generatingLink) return;
    // Phone required — the user-info URL is delivered through
    // WhatsApp. Without a phone we can't deliver it anywhere.
    if (sub.displayPhone.isEmpty) {
      showSheetSnack(context, 'subscribers.no_phone'.tr(), isError: true);
      return;
    }
    setState(() => _generatingLink = true);
    final linkResult = await SubscribersApi.generateInfoLink(sub: sub);
    if (!mounted) return;
    if (!linkResult.ok || linkResult.url == null) {
      setState(() => _generatingLink = false);
      showSheetSnack(
        context,
        linkResult.message ?? 'subscribers.wa_link_gen_failed'.tr(),
        isError: true,
      );
      return;
    }
    // Build the message body locally — v1's text verbatim minus the
    // greeting whitespace tweak. Falls back to username when the
    // Arabic name is missing so admins with sparse name data still
    // get a readable greeting.
    final greetName =
        sub.fullName.trim().isNotEmpty ? sub.fullName.trim() : sub.username;
    // ملاحظة: نص رسالة الواتساب يبقى دائماً عربي — يذهب لعميل المشترك،
    // لا يتأثر بلغة تطبيق الأدمن.
    final body =
        'مرحباً $greetName 👋\n\n'
        'يمكنك الاطلاع على معلومات اشتراكك من خلال الرابط التالي:\n\n'
        '${linkResult.url}\n\n'
        '⚠️ ملاحظة: هذا الرابط صالح لمدة ساعة واحدة فقط.\n'
        'في حال تجديد الاشتراك أو تسديد الدين، يرجى طلب رابط جديد للبيانات المحدثة.\n\n'
        'شكراً لك 🙏';
    // 2026-08-26: preview sheet + chip للـmanual mode.
    setState(() => _generatingLink = false);
    if (!mounted) return;
    final choice = await showManualWaPreviewSheet(
      context,
      title: 'رابط بيانات المشترك',
      phone: sub.displayPhone,
      messagePreview: body,
    );
    if (!mounted || choice == null || !choice.confirmed) return;

    if (choice.manualMode) {
      final ok = await openManualWa(
        phone: sub.displayPhone,
        message: body,
        context: context,
      );
      if (!mounted) return;
      showSheetSnack(
        context,
        ok
            ? 'افتح واتساب واضغط "إرسال" لإتمام العمليّة'
            : 'تعذّر فتح واتساب',
        isError: !ok,
      );
      return;
    }

    final sendResult = await WhatsAppApi.sendMessage(
      to: sub.displayPhone,
      message: body,
      intent: 'subscriber_info',
      sas4Idx: sub.idx,
    );
    if (!mounted) return;
    final ok = sendResult.ok;
    final okMsg = 'subscribers.wa_link_sent'.tr();
    final chArabic = sendResult.channelArabic;
    showSheetSnack(
      context,
      ok
          ? (chArabic != null ? '$okMsg · عبر $chArabic' : okMsg)
          : (sendResult.message ?? 'subscribers.wa_link_send_failed'.tr()),
      isError: !ok,
    );
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
          ? (wantEnable ? 'subscribers.enable_ok'.tr() : 'subscribers.disable_ok'.tr())
          : (wantEnable ? 'subscribers.enable_failed'.tr() : 'subscribers.disable_failed'.tr()),
      isError: !success,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sub, required this.onClose});
  final Subscriber sub;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final statusColor = _statusColor(sub);
    final statusLabel = _statusLabel(sub);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Icon(_statusIcon(sub), color: statusColor, size: 22),
              ),
              if (sub.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: AppColors.surface, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sub.fullName,
                  style: AppType.title(color: AppColors.textHi).copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text(
                        statusLabel,
                        style: AppType.muted(color: statusColor).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        sub.username,
                        style: AppType.muted(color: AppColors.textLow)
                            .copyWith(
                                fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }

  // Same 7-state visual matrix as the list card —
  // mobile-app/lib/widgets/subscriber_card.dart:478-520.
  static Color _statusColor(Subscriber s) {
    if (s.isDisabled) return const Color(0xFF94A3B8);
    if (s.isOnline) {
      if (s.isExpired) return const Color(0xFF8B5CF6); // purple
      if (s.isNearExpiry) return const Color(0xFFF59E0B);
      return const Color(0xFF2563EB);
    }
    if (s.isExpired) return const Color(0xFFEF4444);
    if (s.isNearExpiry) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  static String _statusLabel(Subscriber s) {
    if (s.isDisabled) return 'subscribers.status_disabled'.tr();
    if (s.isOnline) {
      if (s.isExpired) return 'subscribers.status_online_expired'.tr();
      if (s.isNearExpiry) return 'subscribers.status_online_near'.tr();
      return 'subscribers.status_online'.tr();
    }
    if (s.isExpired) return 'subscribers.status_expired'.tr();
    if (s.isNearExpiry) return 'subscribers.status_near_expiry'.tr();
    return 'subscribers.status_active'.tr();
  }

  static IconData _statusIcon(Subscriber s) {
    if (s.isDisabled) return LucideIcons.ban;
    return s.isOnline ? LucideIcons.wifi : LucideIcons.wifiOff;
  }
}

class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _SectionCard(
      icon: LucideIcons.wifi,
      title: 'subscribers.section_connection'.tr(),
      accent: const Color(0xFF3B82F6),
      children: [
        if ((sub.ipAddress ?? '').isNotEmpty)
          _InfoRow(
            icon: LucideIcons.network,
            label: 'IP',
            value: sub.ipAddress!,
            valueColor: const Color(0xFF3B82F6),
            onTap: () => launchUrl(
              Uri.parse('http://${sub.ipAddress}'),
              mode: LaunchMode.externalApplication,
            ),
            trailing: LucideIcons.externalLink,
          ),
        if (sub.sessionTime != null && sub.sessionTime! > 0)
          _InfoRow(
            icon: LucideIcons.timer,
            label: 'subscribers.label_session_time'.tr(),
            value: _formatDuration(sub.sessionTime!),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.download,
                label: 'subscribers.label_download'.tr(),
                bytes: sub.downloadBytes ?? 0,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.upload,
                label: 'subscribers.label_upload'.tr(),
                bytes: sub.uploadBytes ?? 0,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}س ${m}د';
    return '${m}د';
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return _SectionCard(
      icon: LucideIcons.package,
      title: 'subscribers.section_subscription'.tr(),
      accent: AppColors.brand,
      children: [
        _InfoRow(
          icon: LucideIcons.idCard,
          label: 'subscribers.label_package'.tr(),
          value: (sub.profileName?.isNotEmpty ?? false)
              ? sub.profileName!
              : 'subscribers.label_no_package'.tr(),
        ),
        if (sub.price != null)
          _InfoRow(
            icon: LucideIcons.tag,
            label: 'subscribers.label_price'.tr(),
            value: '${formatIQD(sub.price!.round())} د.ع',
            valueColor: const Color(0xFFE08F2D),
          ),
        // Show the active discount as its own row so it reads cleanly
        // alongside السعر — admin sees: السعر (X), الخصم (-Y), السعر
        // بعد الخصم (X-Y). Renders only when a discount is set;
        // refreshes live via the dataChanged listener above.
        if ((sub.discount ?? 0) > 0) ...[
          _InfoRow(
            icon: LucideIcons.percent,
            label: 'subscribers.label_discount'.tr(),
            value: '-${formatIQD(sub.discount!.round())} د.ع',
            valueColor: const Color(0xFF14B8A6),
          ),
          if (sub.price != null)
            _InfoRow(
              icon: LucideIcons.banknote,
              label: 'subscribers.label_price_after_discount'.tr(),
              value: '${formatIQD((sub.price! - sub.discount!).round())} د.ع',
              valueColor: AppColors.brand,
            ),
        ],
        _InfoRow(
          icon: LucideIcons.calendar,
          label: 'subscribers.label_expiration'.tr(),
          value: _expirationText(sub.expiration),
        ),
        // 2026-08-18: استعمل نفس منطق الهيرو (parsedExpiration - now, inDays floor)
        // بدل sub.remainingDays (SAS4 يقرّبه لأعلى فيعطي 31 بدل 30).
        _InfoRow(
          icon: LucideIcons.clock,
          label: 'subscribers.label_remaining_days'.tr(),
          value: _remainingDaysText(sub),
          valueColor: sub.isExpired
              ? AppColors.error
              : sub.isNearExpiry
                  ? const Color(0xFFE08F2D)
                  : AppColors.brand,
        ),
        if ((sub.parentUsername ?? '').isNotEmpty)
          _InfoRow(
            icon: LucideIcons.userCog,
            label: 'subscribers.label_parent_admin'.tr(),
            value: sub.parentUsername!,
          ),
        if (sub.displayPhone.isNotEmpty)
          _InfoRow(
            icon: LucideIcons.phone,
            label: 'subscribers.label_phone'.tr(),
            value: sub.displayPhone,
            onTap: () =>
                Clipboard.setData(ClipboardData(text: sub.displayPhone)),
            trailing: LucideIcons.copy,
          ),
        // 'آخر اتصال' for offline subscribers. v1 fetches the precise
        // last-session timestamp from SAS4's encrypted /index/UserSessions
        // endpoint — without client-side encryption in v2, the best we
        // can do until a backend wrapper lands is fall back to the
        // expiry-derived signal. Shown only for offline rows so the
        // live session block doesn't have a redundant 'آخر اتصال'.
        if (!sub.isOnline)
          _InfoRow(
            icon: LucideIcons.history,
            label: 'آخر اتصال',
            value: _lastSeenText(sub),
            valueColor: AppColors.textMid,
          ),
      ],
    );
  }

  static String _lastSeenText(Subscriber s) {
    // 2026-07-16: نستخدم SAS4 last_online إذا كان موجوداً (تاريخ ووقت
    // دقيقان). backend يمرّرها في /api/v2/subscribers منذ 2026-07-13.
    // نعرض الاثنين: تقدير نسبيّ + التاريخ الدقيق (زي الويب) —
    // "قبل 3 أيام · 2026/07/13 14:32".
    final lastRaw = s.lastOnline?.trim();
    if (lastRaw != null && lastRaw.isNotEmpty) {
      final rel = _formatLastOnline(lastRaw);
      final exact = _expirationText(lastRaw); // نفس صيغة تاريخ الانتهاء
      return exact == '—' || exact == lastRaw ? rel : '$rel · $exact';
    }
    // Fallback القديم:
    if (!s.isExpired) return 'subscribers.ago_not_available'.tr();
    final raw = s.expiration?.trim();
    if (raw == null || raw.isEmpty) return 'subscribers.ago_unknown'.tr();
    final t = DateTime.tryParse(raw) ??
        DateTime.tryParse(raw.split(' ').first);
    if (t == null) return raw.split(' ').first;
    final diff = DateTime.now().difference(t);
    if (diff.inDays > 365) return 'subscribers.ago_over_year'.tr();
    if (diff.inDays > 30) return 'subscribers.ago_months'.tr(namedArgs: {'n': '${(diff.inDays / 30).round()}'});
    if (diff.inDays > 0) return 'subscribers.ago_days'.tr(namedArgs: {'n': '${diff.inDays}'});
    if (diff.inHours > 0) return 'subscribers.ago_hours'.tr(namedArgs: {'n': '${diff.inHours}'});
    return 'subscribers.ago_minutes'.tr();
  }

  /// 2026-07-16: تنسيق last_online كـ"قبل X" بأسلوب طبيعي. يحوّل SAS4
  /// timestamp إلى تعبير نسبيّ (منذ 5 دقائق / 3 ساعات / يومين...).
  static String _formatLastOnline(String raw) {
    final t = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.split(' ').first);
    if (t == null) return raw.split(' ').first;
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'subscribers.ago_now'.tr();
    if (diff.inMinutes < 60) return 'subscribers.ago_minutes_n'.tr(namedArgs: {'n': '${diff.inMinutes}'});
    if (diff.inHours < 24) return 'subscribers.ago_hours'.tr(namedArgs: {'n': '${diff.inHours}'});
    if (diff.inDays < 30) return 'subscribers.ago_days'.tr(namedArgs: {'n': '${diff.inDays}'});
    if (diff.inDays < 365) return 'subscribers.ago_months'.tr(namedArgs: {'n': '${(diff.inDays / 30).round()}'});
    return 'subscribers.ago_over_year'.tr();
  }

  static String _expirationText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.split(' ').first);
    if (t == null) return s.split(' ').first;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// حساب "الأيام المتبقيّة" لصف الـinfo (تحت "تاريخ الانتهاء").
  /// 2026-08-18: نفس منطق الهيرو — يستعمل parsedExpiration - now للحصول
  /// على floor(diff/day) بدل sub.remainingDays الذي يقرّبه SAS4 لأعلى.
  /// يعرض "Nيوم Hس" لو أقل من يوم كامل، أو "منتهي" لو مضى الوقت.
  static String _remainingDaysText(Subscriber sub) {
    final exp = sub.parsedExpiration;
    if (exp != null) {
      final diff = exp.difference(DateTime.now());
      if (diff.isNegative) return 'subscribers.label_expired_short'.tr();
      final d = diff.inDays;
      final h = diff.inHours.remainder(24);
      if (d > 0 && h > 0) return '$d يوم و $h ساعة';
      if (d > 0) return '$d يوم';
      if (h > 0) return '$h ساعة';
      final m = diff.inMinutes.remainder(60);
      if (m > 0) return '$m دقيقة';
      return 'أقل من دقيقة';
    }
    // fallback على remainingDays حين لا يوجد تاريخ نصّي
    final r = sub.remainingDays;
    if (r == null) return '—';
    if (sub.isExpired) return 'subscribers.label_expired_short'.tr();
    return '$r يوم';
  }
}

/// Slim one-line balance card — wrapping the section header pattern
/// would duplicate the 'دين على المشترك' label inside the title, so we
/// render a single inline row: icon + label on the leading edge, the
/// amount as a colored chip on the trailing edge. Reads at-a-glance
/// without dominating the screen like the previous hero number did.
/// بلوك «الدين المستحقّ» — البلوك الثاني في المخطّط، مباشرةً تحت بطاقة
/// الهويّة. كارت أبيض r20 بحدّ أحمر خافت، فيه مربّع أيقونة 40×40 والمبلغ
/// بارزاً، ومقابله زرّان: «تذكير» شبحي كهرماني و«تسديد» مملوء أحمر.
///
/// يظهر أيضاً للرصيد الدائن (بلغة خضراء) لأنّ `pay_debt_sheet` يدعمه
/// صراحةً — والمخطّط لا يوفّر مدخلاً آخر للتسديد خارج هذا البلوك.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.sub, this.onRemind, this.onPay});
  final Subscriber sub;

  /// null = الزرّ يختفي (لا صلاحيّة أو لا رقم هاتف أو إرسال جارٍ).
  final VoidCallback? onRemind;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = sub.hasDebt;
    final accent = isDebt ? AppColors.error : AppColors.success;
    final softBg = isDebt ? AppColors.dangerSoftBg : AppColors.successSoftBg;
    final borderCol =
        isDebt ? AppColors.dangerBorderCard : AppColors.successSoftBorder;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: softBg,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: Icon(
              isDebt ? Icons.credit_card_rounded : Icons.savings_rounded,
              size: 21,
              color: accent,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isDebt
                      ? 'subscribers.label_debt_on_sub'.tr()
                      : 'subscribers.label_balance_credit'.tr(),
                  style: AppType.body(color: AppColors.textLabel),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatIQD(sub.debtAbs.round())} د.ع',
                  textDirection: ui.TextDirection.ltr,
                  style: AppType.statValue(color: accent),
                ),
              ],
            ),
          ),
          if (onRemind != null) ...[
            _DebtButton(
              label: 'تذكير',
              icon: Icons.notifications_active_rounded,
              filled: false,
              color: AppColors.warning,
              borderColor: AppColors.warningSoftBorder,
              onTap: onRemind!,
            ),
            const SizedBox(width: 7),
          ],
          if (onPay != null)
            _DebtButton(
              label: 'تسديد',
              icon: Icons.payments_rounded,
              filled: true,
              color: isDebt ? AppColors.errorFill : AppColors.successFill,
              onTap: onPay!,
            ),
        ],
      ),
    );
  }
}

/// زرّ داخل بلوك الدين — height 36 · r12 · font 12.5/w600 · أيقونة 16.
class _DebtButton extends StatelessWidget {
  const _DebtButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onTap,
    this.borderColor,
  });
  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: H.chip,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: filled
                ? null
                : Border.all(color: borderColor ?? AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: filled ? AppColors.onBrand : color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.bodyStrong(
                  color: filled ? AppColors.onBrand : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dedicated operations card at the bottom — every action v1 surfaces
/// in its FAB sheet, rendered as a 3-column grid of small tinted
/// chips. Stubbed actions snack 'قيد التطوير' until the matching
/// sheet/dialog is built in the later phases; live actions (call,
/// WhatsApp, disconnect) are wired now.
class _OperationsCard extends StatelessWidget {
  const _OperationsCard({
    required this.sub,
    required this.disconnecting,
    required this.onDisconnect,
    required this.toggling,
    required this.onToggleEnabled,
    required this.sendingTemplate,
    required this.onSendTemplate,
    required this.generatingLink,
    required this.onGenerateLink,
    this.onQrLogin,
    required this.deleting,
    required this.onDelete,
    required this.busy,
  });

  final Subscriber sub;
  final bool disconnecting;
  final VoidCallback? onDisconnect;
  /// True while the toggle (تعطيل/تفعيل) round-trip is in flight —
  /// the tile label flips to 'جاري...' so the admin sees activity.
  final bool toggling;
  /// null when sub.idx is missing — the chip stays in the grid but
  /// taps no-op. Otherwise shows the confirm dialog + runs the
  /// toggle through SubscribersApi (backend also kicks any live
  /// session on disable, see toggle-enabled endpoint).
  final VoidCallback? onToggleEnabled;
  /// Which template send is in flight ('debt_reminder' /
  /// 'expiry_warning' / 'subscriber_info'), or null. Drives the
  /// matching chip's 'جاري الإرسال…' label.
  final String? sendingTemplate;
  final ValueChanged<String> onSendTemplate;
  /// True while the generate-info-link round-trip + WhatsApp send
  /// are in flight. Flips the link chip's label to 'جاري التوليد…'.
  final bool generatingLink;
  final VoidCallback onGenerateLink;
  final VoidCallback? onQrLogin;
  /// True while the DELETE round-trip is in flight. Flips the
  /// chip to 'جاري الحذف…'.
  final bool deleting;
  /// null when sub.idx is missing — chip stays in the grid but
  /// taps no-op. Otherwise opens the confirm dialog + runs the
  /// delete. Front-line guard against deleting subs in debt.
  final VoidCallback? onDelete;
  /// True when ANY async operation owned by this card is pending —
  /// togglesa, disconnect, or a template send. While busy the card
  /// shows a thin progress strip + dims every tile and intercepts
  /// taps so the admin can't queue a second action mid-flight (the
  /// network round-trip is ~1-3s and v1 had the same lock-out).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final phone = sub.displayPhone;
    // مطلب 2026-06-11: كل زر يختفي إذا الموظف ما عنده الصلاحية.
    // الـactions كثيرة، فنبني list مع شرط لكل عنصر بدل nested if.
    final ops = <_Op>[
      if (Perms.has('subscribers.edit'))
        _Op(LucideIcons.pencil, 'subscribers.op_edit'.tr(), const Color(0xFF2D5F47),
            () => showEditSubscriberSheet(context, sub)),
      if (Perms.has('subscribers.activate'))
        _Op(LucideIcons.zap, 'subscribers.op_activate_sub'.tr(), const Color(0xFF14B8A6),
            () => showActivateSheet(context, sub)),
      if (Perms.has('subscribers.extend'))
        _Op(LucideIcons.repeat, 'subscribers.op_extend'.tr(), const Color(0xFF3B82F6),
            () => showExtendSheet(context, sub)),
      if (Perms.has('subscribers.add_debt'))
        _Op(LucideIcons.plus, 'subscribers.op_add_debt'.tr(), const Color(0xFFE08F2D),
            () => showAddDebtSheet(context, sub)),
      if (sub.hasDebt && Perms.has('subscribers.pay_debt'))
        _Op(LucideIcons.banknote, 'subscribers.op_pay_debt'.tr(), const Color(0xFF14B8A6),
            () => showPayDebtSheet(context, sub)),
      // 2026-08-29: انتقل من كارت القائمة (المخطّط الجديد لا يضع
      // أزراراً في الكارت). الشريحة 3 تدمجه inline في كارت «معلومات
      // الاتصال» كما يفعل المخطّط، ويُحذف من هنا حينها.
      if (sub.isOnline)
        _Op(LucideIcons.chartLine, 'الاستهلاك', const Color(0xFF14B8A6),
            () => showConsumptionSheet(context, sub)),
      // 2026-08-26: الموقع — يظهر إذا:
      //  - الموقع مُعيَّن (يقدر أيّ موظّف يفتحه بالخرائط)، أو
      //  - الموظّف/المدير يقدر يعدّله (subscribers.edit_location).
      if (sub.hasLocation || Perms.has('subscribers.edit_location'))
        _Op(
          LucideIcons.mapPin,
          sub.hasLocation ? 'الموقع' : 'إضافة موقع',
          const Color(0xFF14B8A6),
          () async {
            if (!sub.hasLocation) {
              await showLocationEditSheet(context, sub: sub);
              return;
            }
            // الموقع مُعيَّن → chooser (يعرض خيار "تعديل" لو الصلاحية).
            await showLocationSheet(context, sub: sub);
          },
        ),
      if (Perms.has('discounts.manage'))
        _Op(LucideIcons.tag, 'subscribers.op_quick_discount'.tr(), const Color(0xFF14B8A6),
            () => showQuickDiscountSheet(context, sub)),
      if (Perms.has('subscribers.view_activity'))
        _Op(LucideIcons.history, 'subscribers.op_movements'.tr(), const Color(0xFF26A69A),
            () => showMovementsSheet(context, sub)),
      if (Perms.has('reports.account_statement'))
        _Op(LucideIcons.fileText, 'subscribers.account_statement'.tr(), const Color(0xFF0EA5E9),
            () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AccountStatementScreen(
                      username: sub.username,
                      displayName: (sub.firstname == null && sub.lastname == null)
                          ? null
                          : [sub.firstname, sub.lastname]
                              .where((s) => s != null && s.isNotEmpty)
                              .join(' ')
                              .trim(),
                      phone: sub.phone,
                    ),
                  ),
                )),
      if (sub.hasDebt && Perms.has('subscribers.send_whatsapp'))
        _Op(
          LucideIcons.bellRing,
          sendingTemplate == 'debt_reminder'
              ? 'subscribers.op_sending'.tr()
              : 'subscribers.op_debt_reminder'.tr(),
          Colors.orange,
          () => onSendTemplate('debt_reminder'),
        ),
      if (sub.isNearExpiry && Perms.has('subscribers.send_whatsapp'))
        _Op(
          LucideIcons.alarmClock,
          sendingTemplate == 'expiry_warning'
              ? 'subscribers.op_sending'.tr()
              : 'subscribers.op_expiry_warning'.tr(),
          Colors.deepOrange,
          () => onSendTemplate('expiry_warning'),
        ),
      if (Perms.has('subscribers.generate_link'))
        _Op(
          LucideIcons.link,
          generatingLink ? 'subscribers.op_generating'.tr() : 'subscribers.op_gen_link'.tr(),
          Colors.indigo,
          onGenerateLink,
        ),
      // 2026-07-13: QR دخول 30 يوم — يُعرض للأدمن ليعطي المشترك رمز
      // دخول سريع للتطبيق البورتال بلا كتابة username/password.
      if (Perms.has('subscribers.send_whatsapp') && onQrLogin != null)
        _Op(
          LucideIcons.qrCode,
          'subscribers.op_qr_login'.tr(),
          const Color(0xFF7C3AED),
          onQrLogin!,
        ),
      if (Perms.has('subscribers.send_whatsapp'))
        _Op(
          LucideIcons.info,
          sendingTemplate == 'subscriber_info'
              ? 'subscribers.op_sending'.tr()
              : 'subscribers.op_send_info'.tr(),
          Colors.blueAccent,
          () => onSendTemplate('subscriber_info'),
        ),
      if (Perms.has('subscribers.toggle'))
        _Op(
          sub.isDisabled ? LucideIcons.circleCheck : LucideIcons.ban,
          toggling
              ? 'subscribers.op_busy'.tr()
              : (sub.isDisabled ? 'subscribers.enable'.tr() : 'subscribers.disable'.tr()),
          sub.isDisabled ? Colors.green : const Color(0xFFE08F2D),
          onToggleEnabled ?? () {},
        ),
      if (Perms.has('subscribers.delete'))
        _Op(
          LucideIcons.trash2,
          deleting ? 'subscribers.op_deleting'.tr() : 'common.delete'.tr(),
          AppColors.error,
          onDelete ?? () {},
        ),
      if (phone.isNotEmpty)
        _Op(LucideIcons.phone, 'subscribers.call'.tr(), const Color(0xFF14B8A6),
            () => _launchUri(context, Uri.parse('tel:$phone'))),
      if (phone.isNotEmpty)
        _Op(
          LucideIcons.messageCircle,
          'subscribers.op_whatsapp'.tr(),
          const Color(0xFF25D366),
          () => _launchUri(
              context, Uri.parse('https://wa.me/${_digits(phone)}')),
        ),
      if (sub.isOnline && sub.idx != null)
        _Op(LucideIcons.power, disconnecting ? 'subscribers.op_disconnecting'.tr() : 'subscribers.disconnect_user'.tr(),
            AppColors.error, onDisconnect ?? () {}),
    ];

    return _SectionCard(
      icon: LucideIcons.layers,
      title: 'subscribers.actions'.tr(),
      accent: AppColors.brand,
      children: [
        // Thin progress strip while busy — gives the admin an
        // immediate signal that the tap registered and a request is
        // mid-flight, instead of the previous silent freeze.
        if (busy) ...[
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.brand,
              backgroundColor: AppColors.border,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Card-style tiles — white surface, border + soft shadow, tinted
        // icon-box on top, label underneath. Same visual language as
        // the section cards above so the whole screen reads as one
        // family. 3-column grid keeps tiles tappable on mid-size phones.
        //
        // IgnorePointer + Opacity wrap so the whole grid blocks taps
        // while busy without re-laying-out (children just dim, no
        // shifting/repaint chains).
        IgnorePointer(
          ignoring: busy,
          child: Opacity(
            opacity: busy ? 0.55 : 1,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // 2026-08-26: مسافات مضغوطة أكثر — صفر بين الأزرار
              // (crossAxisSpacing=0) + طول childAspect أقصر (1.05)
              // ليقارب الشبكة عمودياً. طلب المستخدم "قلّص المسافات".
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 0,
                crossAxisSpacing: 0,
                childAspectRatio: 1.05,
              ),
              itemCount: ops.length,
              itemBuilder: (_, i) => _OpCard(op: ops[i]),
            ),
          ),
        ),
      ],
    );
  }

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static void _todo(BuildContext ctx, String msg) {
    showSheetSnack(ctx, msg);
  }

  static Future<void> _launchUri(BuildContext ctx, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!ctx.mounted) return;
      showSheetSnack(ctx, 'لا يمكن فتح الرابط', isError: true);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _Op {
  const _Op(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// مطلب 2026-06-12 (screenshots reference): زر دائري ملوّن مع
/// أيقونة بيضاء + label تحت الزر بلون نصّ عادي. مطابق v1
/// (operations grid screenshot). الـcircle 56dp، الـicon white 22dp،
/// ظل ناعم بلون الزر يعطي توهّج خفيف.
class _OpCard extends StatelessWidget {
  const _OpCard({required this.op});
  final _Op op;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // 2026-08-26: أيقونات مربّعة (rounded 12dp) بدل دائريّة + مسافات
    // مضغوطة. المستخدم فضّل الشبكة المسطّحة الأصليّة مع لمسة modern.
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        op.onTap();
      },
      radius: 34,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: op.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: op.color.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(op.icon, color: Colors.white, size: 21),
          ),
          const SizedBox(height: 1),
          Flexible(
            child: Text(
              op.label,
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// مطلب 2026-06-11: كرت قابل للطي/التوسيع.
///  • فونتات +1 درجة على القيم والعناوين والأيقونات (كانت صغيرة).
///  • سهم chevron في الـheader يقلب الطيّ. تأثير AnimatedCrossFade
///    ينعّم الانتقال بين الحالتين.
///  • الـheader وحده قابل للنقر — التفاعل مع الصفوف بالداخل
///    لا يقلب الطي بالخطأ.
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final List<Widget> children;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Icon(widget.icon, color: widget.accent, size: 13),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMid,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // مطلب 2026-06-11: فونت/icon +1 على كل قيمة وعنوان في صفوف
    // كروت التفاصيل — كان 11/12/13 ضعيف الوضوح، صار 12/13/14.
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMid, size: 14),
          const SizedBox(width: 7),
          Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: AppType.label(
                color: valueColor ?? AppColors.textHi,
              ).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Icon(trailing, color: AppColors.textLow, size: 13),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: row,
    );
  }
}

class _BytesCard extends StatelessWidget {
  const _BytesCard({
    required this.icon,
    required this.label,
    required this.bytes,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _formatBytes(bytes),
            style: AppType.title(color: color).copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var v = bytes.toDouble();
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
  }
}

/// مطلب 2026-06-12: AppBar نظيف مطابق screenshot v1 — الاسم العربي
/// مركزي + سهم رجوع يميني (RTL يعكس). بدون ظل.
class _SimpleAppBar extends StatelessWidget {
  const _SimpleAppBar({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      color: AppColors.bg,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.chevronRight, size: 22),
            color: AppColors.textHi,
            onPressed: onClose,
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 17, letterSpacing: -0.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 48),
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
        color: AppColors.brand,
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
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
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
          Flexible(
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
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.onBrandTertiary,
              ),
            )
          else
            Expanded(child: _HeroPassword(password: pass)),
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              value: debt == 0 ? '—' : formatIQD(debt.abs()),
              label: debt > 0 ? 'رصيد دائن' : 'الدين',
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
        Text(
          value,
          textDirection: ui.TextDirection.ltr,
          style: AppType.statValue(color: color ?? AppColors.onBrand)
              .copyWith(fontSize: valueSize),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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
    if (d > 0) return ('$d يوم', '${h}س ${m}د');
    if (h > 0) return ('${h}س', '${m}د');
    return ('${m}د', 'أقل من ساعة');
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
          Icon(Icons.call_rounded, size: 17, color: AppColors.onBrandSecondary),
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
        if (parent != null && parent.isNotEmpty) ...[
          Icon(Icons.shield_rounded,
              size: 15, color: AppColors.onBrandSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'تابع إلى $parent',
              style: AppType.muted(color: AppColors.onBrandSecondary)
                  .copyWith(fontSize: 11.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
    final shown = _visible
        ? widget.password
        : '•' * widget.password.length.clamp(4, 12);
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
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 1),
          ),
          child: Icon(
            _copied ? LucideIcons.check : LucideIcons.copy,
            size: 12,
            color: Colors.white,
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
    final display = _visible ? widget.password : '•' * widget.password.length.clamp(4, 12);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.lock, size: 11,
            color: Colors.white.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            display,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
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
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 1),
          ),
          child: Icon(icon, size: 11, color: Colors.white),
        ),
      ),
    );
  }
}
