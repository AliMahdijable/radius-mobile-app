import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/subscribers_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/util/format.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/account_statement_screen.dart';
import 'sheets/activate_sheet.dart';
import 'sheets/add_debt_sheet.dart';
import 'sheets/edit_subscriber_sheet.dart';
import 'sheets/extend_sheet.dart';
import 'sheets/movements_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
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
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _onDataChanged() async {
    if (!mounted) return;
    final list = await SubscribersApi.loadAll();
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
                  _SubscriberHero(sub: sub),
                  const SizedBox(height: Sp.md),
                  if (sub.isOnline) ...[
                    _LiveSessionCard(sub: sub),
                    const SizedBox(height: Sp.sm),
                    // مطلب 2026-06-11: عرض معلومات الاتصال (ONT/UBNT)
                    // مثل v1 — تظهر بطاقة منفصلة تحت كرت الجلسة الحية
                    // مع بور/سيغنال/LAN حسب نوع الجهاز.
                    if ((sub.ipAddress ?? '').isNotEmpty) ...[
                      DeviceProbeCard(
                        ip: sub.ipAddress!,
                        username: sub.username,
                      ),
                      const SizedBox(height: Sp.sm),
                    ],
                  ],
                  // مطلب 2026-06-12: _SubscriptionCard المنفصل أُلغي
                  // — كل معلوماته (الباقة/السعر/الانتهاء/التابع/الهاتف)
                  // صارت داخل _SubscriberHero. كرت الرصيد لا يزال يظهر
                  // مستقلاً لما الـbalance != 0.
                  if (sub.balanceAmount != 0) ...[
                    const SizedBox(height: Sp.sm),
                    _BalanceCard(sub: sub),
                  ],
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
          'فصل المستخدم',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'سيتم قطع جلسة ${sub.fullName} الحالية من الشبكة. سيحتاج '
          'لإعادة الاتصال يدوياً.',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('فصل'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'تم فصل المستخدم' : 'تعذّر الفصل'),
        backgroundColor: success ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmToggleEnabled() async {
    final wantEnable = sub.isDisabled;
    final action = wantEnable ? 'تفعيل حساب' : 'تعطيل';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'تأكيد $action',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          wantEnable
              ? 'هل تريد تفعيل حساب "${sub.fullName}"؟'
              : 'سيُمنع "${sub.fullName}" من الاتصال، وإن كان متصلاً '
                  'الآن سيُفصل فوراً. يبقى الحساب في النظام.\n\nهل تريد المتابعة؟',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن حذف مشترك عليه دين: ${formatIQD(sub.debtAbs.round())} د.ع',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'تأكيد الحذف',
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'هل أنت متأكد من حذف المشترك "${sub.fullName}"؟\n'
          'لا يمكن التراجع عن هذا الإجراء.',
          style: AppType.subtitle(color: AppColors.textMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف المشترك'),
          backgroundColor: AppColors.brand,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Pop back to the list — the subscriber no longer exists and
      // the underlying state will refresh from dataChanged.
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'تعذّر الحذف'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _generateInfoLink() async {
    if (_generatingLink) return;
    // Phone required — the user-info URL is delivered through
    // WhatsApp. Without a phone we can't deliver it anywhere.
    if (sub.displayPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد رقم هاتف للمشترك'),
          backgroundColor: Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _generatingLink = true);
    final linkResult = await SubscribersApi.generateInfoLink(sub: sub);
    if (!mounted) return;
    if (!linkResult.ok || linkResult.url == null) {
      setState(() => _generatingLink = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(linkResult.message ?? 'فشل توليد الرابط'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Build the message body locally — v1's text verbatim minus the
    // greeting whitespace tweak. Falls back to username when the
    // Arabic name is missing so admins with sparse name data still
    // get a readable greeting.
    final greetName =
        sub.fullName.trim().isNotEmpty ? sub.fullName.trim() : sub.username;
    final body =
        'مرحباً $greetName 👋\n\n'
        'يمكنك الاطلاع على معلومات اشتراكك من خلال الرابط التالي:\n\n'
        '${linkResult.url}\n\n'
        '⚠️ ملاحظة: هذا الرابط صالح لمدة ساعة واحدة فقط.\n'
        'في حال تجديد الاشتراك أو تسديد الدين، يرجى طلب رابط جديد للبيانات المحدثة.\n\n'
        'شكراً لك 🙏';
    final sendResult = await WhatsAppApi.sendMessage(
      to: sub.displayPhone,
      message: body,
      intent: 'subscriber_info',
    );
    if (!mounted) return;
    setState(() => _generatingLink = false);
    final ok = sendResult.ok;
    final color = ok ? const Color(0xFF25D366) : AppColors.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'تم إرسال رابط معلومات المشترك'
              : (sendResult.message ?? 'فشل إرسال الرابط'),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendTemplate(String templateType) async {
    if (_sendingTemplate != null) return; // single flight per screen
    setState(() => _sendingTemplate = templateType);
    final result = await WhatsAppApi.sendTemplateForSubscriber(
      sub: sub,
      templateType: templateType,
    );
    if (!mounted) return;
    setState(() => _sendingTemplate = null);
    // Map the structured result to a per-state snackbar — admins want
    // to see why a send failed (missing template / inactive /
    // disconnected) so they can fix it inline.
    final ok = result.ok;
    final color = ok
        ? const Color(0xFF25D366)
        : (result.reason == 'no_template' ||
                result.reason == 'inactive' ||
                result.reason == 'no_phone')
            ? const Color(0xFFE08F2D) // warning, not error
            : AppColors.error;
    final defaultOkMsg = switch (templateType) {
      'debt_reminder' => 'تم إرسال تذكير الدين',
      'expiry_warning' => 'تم إرسال تذكير الانتهاء',
      'subscriber_info' => 'تم إرسال معلومات المشترك',
      _ => 'تم إرسال الرسالة',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? defaultOkMsg
              : (result.message ?? 'تعذّر إرسال الرسالة'),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (wantEnable ? 'تم تفعيل الحساب' : 'تم تعطيل الحساب')
              : (wantEnable ? 'تعذّر التفعيل' : 'تعذّر التعطيل'),
        ),
        backgroundColor: success
            ? (wantEnable ? AppColors.brand : const Color(0xFFCD8B00))
            : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
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
    if (s.isDisabled) return 'معطّل';
    if (s.isOnline) {
      if (s.isExpired) return 'متصل / منتهي';
      if (s.isNearExpiry) return 'متصل / قارب';
      return 'متصل';
    }
    if (s.isExpired) return 'منتهي';
    if (s.isNearExpiry) return 'قارب الانتهاء';
    return 'نشط';
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
      title: 'معلومات الاتصال',
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
            label: 'مدة الجلسة',
            value: _formatDuration(sub.sessionTime!),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.download,
                label: 'تحميل',
                bytes: sub.downloadBytes ?? 0,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _BytesCard(
                icon: LucideIcons.upload,
                label: 'رفع',
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
      title: 'معلومات الاشتراك',
      accent: AppColors.brand,
      children: [
        _InfoRow(
          icon: LucideIcons.idCard,
          label: 'الباقة',
          value: (sub.profileName?.isNotEmpty ?? false)
              ? sub.profileName!
              : 'بدون باقة',
        ),
        if (sub.price != null)
          _InfoRow(
            icon: LucideIcons.tag,
            label: 'السعر',
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
            label: 'الخصم',
            value: '-${formatIQD(sub.discount!.round())} د.ع',
            valueColor: const Color(0xFF14B8A6),
          ),
          if (sub.price != null)
            _InfoRow(
              icon: LucideIcons.banknote,
              label: 'السعر بعد الخصم',
              value: '${formatIQD((sub.price! - sub.discount!).round())} د.ع',
              valueColor: AppColors.brand,
            ),
        ],
        _InfoRow(
          icon: LucideIcons.calendar,
          label: 'تاريخ الانتهاء',
          value: _expirationText(sub.expiration),
        ),
        _InfoRow(
          icon: LucideIcons.clock,
          label: 'الأيام المتبقية',
          value: sub.remainingDays == null
              ? '—'
              : sub.isExpired
                  ? 'منتهي'
                  : '${sub.remainingDays} يوم',
          valueColor: sub.isExpired
              ? AppColors.error
              : sub.isNearExpiry
                  ? const Color(0xFFE08F2D)
                  : AppColors.brand,
        ),
        if ((sub.parentUsername ?? '').isNotEmpty)
          _InfoRow(
            icon: LucideIcons.userCog,
            label: 'تابع إلى',
            value: sub.parentUsername!,
          ),
        if (sub.displayPhone.isNotEmpty)
          _InfoRow(
            icon: LucideIcons.phone,
            label: 'رقم الهاتف',
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
    // Best-effort: when SAS4 isn't giving us a last-session ts, infer
    // a coarse signal from the expiration field. If the sub is expired,
    // last contact was at-or-before the expiry; otherwise we don't know
    // precisely and surface 'غير متاح'.
    if (!s.isExpired) return 'غير متاح';
    final raw = s.expiration?.trim();
    if (raw == null || raw.isEmpty) return 'غير معروف';
    final t = DateTime.tryParse(raw) ??
        DateTime.tryParse(raw.split(' ').first);
    if (t == null) return raw.split(' ').first;
    final diff = DateTime.now().difference(t);
    if (diff.inDays > 365) return 'منذ أكثر من سنة';
    if (diff.inDays > 30) return 'منذ ${(diff.inDays / 30).round()} شهر';
    if (diff.inDays > 0) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours > 0) return 'منذ ${diff.inHours} س';
    return 'منذ دقائق';
  }

  static String _expirationText(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.split(' ').first);
    if (t == null) return s.split(' ').first;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// Slim one-line balance card — wrapping the section header pattern
/// would duplicate the 'دين على المشترك' label inside the title, so we
/// render a single inline row: icon + label on the leading edge, the
/// amount as a colored chip on the trailing edge. Reads at-a-glance
/// without dominating the screen like the previous hero number did.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = sub.hasDebt;
    final color = isDebt ? AppColors.error : AppColors.brand;
    final label = isDebt ? 'دين على المشترك' : 'رصيد للمشترك';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(
              isDebt ? LucideIcons.creditCard : LucideIcons.wallet,
              color: color,
              size: 13,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.pill),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${formatIQD(sub.debtAbs.round())} د.ع',
              style: AppType.label(color: color).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
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
        _Op(LucideIcons.pencil, 'تعديل', const Color(0xFF2D5F47),
            () => showEditSubscriberSheet(context, sub)),
      // 'تجديد اشتراك' — sheet renews the package (same as v1's
      // _activateSubscriber). The label avoids collision with the
      // separate 'تعطيل/تفعيل حساب' toggle below which manages the
      // enabled flag.
      if (Perms.has('subscribers.activate'))
        _Op(LucideIcons.zap, 'تجديد اشتراك', const Color(0xFF14B8A6),
            () => showActivateSheet(context, sub)),
      if (Perms.has('subscribers.extend'))
        _Op(LucideIcons.repeat, 'تمديد', const Color(0xFF3B82F6),
            () => showExtendSheet(context, sub)),
      if (Perms.has('subscribers.add_debt'))
        _Op(LucideIcons.plus, 'إضافة دين', const Color(0xFFE08F2D),
            () => showAddDebtSheet(context, sub)),
      if (sub.hasDebt && Perms.has('subscribers.pay_debt'))
        _Op(LucideIcons.banknote, 'تسديد دين', const Color(0xFF14B8A6),
            () => showPayDebtSheet(context, sub)),
      if (Perms.has('discounts.manage'))
        _Op(LucideIcons.tag, 'خصم سريع', const Color(0xFF14B8A6),
            () => showQuickDiscountSheet(context, sub)),
      if (Perms.has('subscribers.view_activity'))
        _Op(LucideIcons.history, 'سجل الحركات', const Color(0xFF26A69A),
            () => showMovementsSheet(context, sub)),
      if (Perms.has('reports.account_statement'))
        _Op(LucideIcons.fileText, 'كشف الحساب', const Color(0xFF0EA5E9),
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
              ? 'جاري الإرسال…'
              : 'تذكير دين',
          Colors.orange,
          () => onSendTemplate('debt_reminder'),
        ),
      if (sub.isNearExpiry && Perms.has('subscribers.send_whatsapp'))
        _Op(
          LucideIcons.alarmClock,
          sendingTemplate == 'expiry_warning'
              ? 'جاري الإرسال…'
              : 'تذكير انتهاء',
          Colors.deepOrange,
          () => onSendTemplate('expiry_warning'),
        ),
      if (Perms.has('subscribers.generate_link'))
        _Op(
          LucideIcons.link,
          generatingLink ? 'جاري التوليد…' : 'توليد رابط',
          Colors.indigo,
          onGenerateLink,
        ),
      if (Perms.has('subscribers.send_whatsapp'))
        _Op(
          LucideIcons.info,
          sendingTemplate == 'subscriber_info'
              ? 'جاري الإرسال…'
              : 'إرسال المعلومات',
          Colors.blueAccent,
          () => onSendTemplate('subscriber_info'),
        ),
      if (Perms.has('subscribers.toggle'))
        _Op(
          sub.isDisabled ? LucideIcons.circleCheck : LucideIcons.ban,
          toggling
              ? 'جاري...'
              : (sub.isDisabled ? 'تفعيل حساب' : 'تعطيل'),
          sub.isDisabled ? Colors.green : const Color(0xFFE08F2D),
          onToggleEnabled ?? () {},
        ),
      if (Perms.has('subscribers.delete'))
        _Op(
          LucideIcons.trash2,
          deleting ? 'جاري الحذف…' : 'حذف',
          AppColors.error,
          onDelete ?? () {},
        ),
      if (phone.isNotEmpty)
        _Op(LucideIcons.phone, 'اتصال', const Color(0xFF14B8A6),
            () => _launchUri(context, Uri.parse('tel:$phone'))),
      if (phone.isNotEmpty)
        _Op(
          LucideIcons.messageCircle,
          'واتساب',
          const Color(0xFF25D366),
          () => _launchUri(
              context, Uri.parse('https://wa.me/${_digits(phone)}')),
        ),
      if (sub.isOnline && sub.idx != null)
        _Op(LucideIcons.power, disconnecting ? 'جاري الفصل' : 'فصل المستخدم',
            AppColors.error, onDisconnect ?? () {}),
    ];

    return _SectionCard(
      icon: LucideIcons.layers,
      title: 'العمليات',
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
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
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
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.textHi,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> _launchUri(BuildContext ctx, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('لا يمكن فتح الرابط')),
      );
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
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        op.onTap();
      },
      radius: 36,
      highlightShape: BoxShape.circle,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: op.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: op.color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(op.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 7),
          Flexible(
            child: Text(
              op.label,
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 11.5,
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
class _SubscriberHero extends StatelessWidget {
  const _SubscriberHero({required this.sub});
  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = AppColors.brand;
    final remaining = sub.remainingDays;
    String remainingTop = '—';
    String remainingSub = 'الأيام المتبقية';
    if (remaining != null && remaining > 0) {
      remainingTop = '$remaining';
      final exp = sub.parsedExpiration;
      if (exp != null) {
        final diff = exp.difference(DateTime.now());
        final h = diff.inHours.remainder(24);
        final m = diff.inMinutes.remainder(60);
        if (h > 0 || m > 0) {
          remainingSub = '${h}س ${m}د';
        }
      }
    } else if (remaining != null && remaining <= 0) {
      remainingTop = '—';
      remainingSub = 'منتهي';
    }
    final hasDebt = sub.balanceAmount < 0;
    // مطلب 2026-06-12: شيلنا الـicon الرقمي اللي كان جوه الهيرو.
    // الاسم والـusername يظهرون مباشرة بأعلى الهيرو. كل معلومات
    // الاشتراك (الباقة/السعر/الانتهاء/التابع/الهاتف) منقولة لأسفل
    // الـhero بـ rows صغيرة بدل _SubscriptionCard المنفصل.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // العنوان: اسم عربي كبير + username تحته
          Text(
            sub.fullName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          // مطلب 2026-06-12: اليوزر نيم قابل للنسخ — نلفّه في Row
          // مع _CopyChip بنفس النمط المستعمل في rows المعلومات.
          Builder(
            builder: (ctx) => Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    sub.username,
                    style: const TextStyle(
                      color: Color(0xFFCBE4D7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _CopyChip(value: sub.username, context: ctx),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 3-stat strip (الدين / الباقة / الأيام)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _heroStat(
                  big: hasDebt ? formatIQD(sub.balanceAmount.abs()) : 'لا يوجد',
                  small: 'الدين',
                ),
              ),
              _heroDivider(),
              Expanded(
                child: _heroStat(
                  big: (sub.profileName ?? '—'),
                  small: 'الباقة',
                  bigSize: 13,
                ),
              ),
              _heroDivider(),
              Expanded(
                child: _heroStat(
                  big: remainingTop,
                  small: remainingSub,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // فاصل أبيض شفاف ثم rows تفصيلية
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 10),
          // مطلب 2026-06-12: عرض الـrows بعرض ثابت للـlabel + value
          // يلتزم بحاشية مستقيمة. الـicon والـlabel في عمود واحد
          // عرضه 105dp فالقيم كلها تبدأ من نفس النقطة.
          if ((sub.price ?? 0) > 0)
            _infoRow(
              icon: LucideIcons.dollarSign,
              label: 'السعر',
              value: '${formatIQD(sub.price!)} د.ع',
            ),
          if ((sub.expiration ?? '').isNotEmpty)
            _infoRow(
              icon: LucideIcons.calendar,
              label: 'تاريخ الانتهاء',
              value: _formatExpiration(sub.expiration),
            ),
          if ((sub.parentUsername ?? '').isNotEmpty)
            _infoRow(
              icon: LucideIcons.shield,
              label: 'تابع إلى',
              value: sub.parentUsername!,
            ),
          if (sub.displayPhone.isNotEmpty)
            _infoRow(
              icon: LucideIcons.phone,
              label: 'رقم الهاتف',
              value: sub.displayPhone,
              copyable: true,
              context: context,
            ),
        ],
      ),
    );
  }

  String _formatExpiration(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _heroStat({
    required String big,
    required String small,
    double bigSize = 18,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          big,
          style: TextStyle(
            color: Colors.white,
            fontSize: bigSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Text(
          small,
          style: const TextStyle(
            color: Color(0xFFCBE4D7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _heroDivider() {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    bool copyable = false,
    BuildContext? context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // label column (fixed width = 110dp) — icon + label محاذيان
          // على اليمين، فالقيم كلها تبدأ بعدها بحاشية ثابتة.
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFFCBE4D7), size: 14),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFFCBE4D7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // value column — يأخذ بقية العرض، نص نهاية ثم زر النسخ
          // (إن وجد) ملتصق به.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                if (copyable && context != null) ...[
                  const SizedBox(width: 6),
                  _CopyChip(value: value, context: context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// زر نسخ صغير دائري — يستعمل ضمن الـhero لأي قيمة قابلة للنسخ
/// (الهاتف / IP / username). يعرض ✓ لحظياً بعد النسخ.
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
    ScaffoldMessenger.of(widget.context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ ${widget.value}'),
        backgroundColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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
