import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../services/notification_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/big_subscribers_api.dart';
import '../../api/company_route.dart';
import '../../api/subscribers_api.dart';
import '../../models/app_notification.dart';
import '../../models/subscriber.dart';
import '../../services/alerts_service.dart';
import '../../services/inbox_service.dart';
import '../../services/merged_mode.dart';
import '../../widgets/company_tag.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../national/national_ticket_push.dart';
import '../whatsapp/connection_auto_widgets.dart';
import '../subscribers/subscriber_detail_screen.dart';
import '../desktop/desk_widgets.dart';
import '../renew/renew_widgets.dart';
import '../tickets/ticket_widgets.dart';
import '../../api/renew_requests_api.dart';

/// شاشة inbox — تعرض 3 أقسام (نفس منطق v1 mobile-app):
///   1. **إشعارات التطبيق** — FCM inbox items (المستلمة).
///   2. **انتهى اليوم** — قائمة مشتركين انتهى اشتراكهم اليوم (name+detail،
///      tap يفتح كارت المشترك).
///   3. **قريب الانتهاء** — قائمة مشتركين متبقّي لهم 0..3 أيام
///      (مطلوب من المستخدم 2026-07-11: يظهروا لغاية ما ينتهي اشتراكهم).
/// كل صف مشترك قابل للنقر ويفتح SubscriberDetailScreen مثل v1.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.onTapNotification});

  /// callback خارجي عند النقر على إشعار FCM: يُستدعى فقط لو ما نعرف
  /// مشترك محدد من payload (لو نعرفه، نفتح كارته مباشرة).
  final void Function(AppNotification n)? onTapNotification;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Subscriber> _expiredToday = const [];
  List<Subscriber> _nearExpiry = const [];
  bool _loaded = false;

  /// القائمتان معروضتان من آخر قائمةٍ معروفة والطازجة في الطريق — مؤشّرٌ صغير بالعنوان لا شاشة انتظار.
  bool _refreshing = false;

  /// كم ينتظر الجرس جلسات المتّصلين قبل أن يعرض القائمة الطازجة بدونها (ثمّ يدمجها حين تصل).
  static const Duration onlineBudget = Duration(seconds: 3);

  // ── الحسابات الكبيرة (≥ ٥٠٠٠): القائمتان من الساس صفحةً صفحة (expired_today / expiring_24h) بالتعريفين نفسيهما،
  // والعنوان يحمل مجموع كلٍّ منهما لا ما حُمِّل. ──
  static const int _kBigInboxPage = 100;
  bool _big = false;
  int _expiredTotal = 0, _nearTotal = 0;
  int _expiredPage = 0, _nearPage = 0;
  int _expiredLast = 1, _nearLast = 1;
  bool _expiredMore = false, _nearMore = false;

  /// «كل الشركات» وفيها كبيرة: العنوان بالمجموع الحقيقيّ ([_expiredTotal]/[_nearTotal]) لا بما حُمِّل من صفحتها الأولى.
  bool _mergedTotals = false;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  // ٨ نوفمبر (المالك: «الاشعارات زر… الي يظهر المنتهي وقريب الانتهاء يتاخر بشكل مو طبيعي»): كان الجرس ينتظر القائمة الكاملة
  // والمتّصلين معاً قبل أيّ شيء (المتّصلون p99 ‏٥٫٦ث وأقصاه ٢٢ث بسجلّ الخادم). الآن: ① آخر قائمةٍ معروفة (≤١٥ د) فوراً،
  // ② القائمة الطازجة حين تصل ولا تنتظر المتّصلين أكثر من [onlineBudget]، ③ حال الاتّصال حين يصل.
  Future<void> _loadLists() async {
    if (MergedMode.active.value) return _loadMerged();
    if (await BigSubscribersApi.probe() > 0) return _loadBig();
    if (!mounted) return;
    final snap = SubscribersApi.lastWithOnline();
    if (snap != null) _apply(snap, refreshing: true);
    final onlineF = SubscribersApi.loadOnline();
    final base = await SubscribersApi.loadAll();
    if (!mounted) return;
    if (base == null) {
      // تعذّر الجلب: ما عُرض يبقى (إن وُجد)
      setState(() {
        _loaded = true;
        _refreshing = false;
      });
      return;
    }
    Map<String, OnlineSessionInfo>? online;
    var late = false;
    try {
      online = await onlineF.timeout(onlineBudget);
    } on TimeoutException {
      late = true;
    }
    if (!mounted) return;
    _apply(SubscribersApi.withOnline(base, online), refreshing: late);
    if (late) {
      final o = await onlineF;
      if (!mounted) return;
      _apply(SubscribersApi.withOnline(base, o), refreshing: false);
    }
  }

  /// «كل الشركات» (٨ نوفمبر — الفحص العامّ: «طبق مبدا الخدمتين»): القائمتان من قوائم الشركات المدموجة — «الكل» أو المختارة
  /// في الشريط — كلّ صفٍّ بشارة شركته والفتح موجَّهٌ لها، لا قائمة المفتوحة وحدها. الكبيرة: أوّل صفحةٍ من تبويبيها موجَّهةً
  /// لها، والعنوان بمجموعها الحقيقيّ.
  Future<void> _loadMerged() async {
    final focus = MergedMode.focused?.key;
    final last = MergedSubscribers.last.value;
    if (last != null && _expiredToday.isEmpty && _nearExpiry.isEmpty) _apply(last.rowsFor(focus), refreshing: true);
    MergedListResult r;
    try {
      r = await MergedSubscribers.withSessions(await MergedSubscribers.load());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _refreshing = false;
      });
      return;
    }
    if (!mounted) return;
    final rows = <Subscriber>[...r.rowsFor(focus)];
    var extraExpired = 0, extraNear = 0;
    for (final p in r.big) {
      if (focus != null && p.company.key != focus) continue;
      final key = p.company.key;
      try {
        final pages = await CompanyRoute.run(key, () => Future.wait([
              BigSubscribersApi.page(page: 1, size: _kBigInboxPage, tab: 'expired_today'),
              BigSubscribersApi.page(page: 1, size: _kBigInboxPage, tab: 'expiring_24h'),
            ]));
        for (final pg in pages) {
          rows.addAll(pg.rows.map((s) => s.withCompany(key)));
        }
        extraExpired += pages[0].total - pages[0].rows.length;
        extraNear += pages[1].total - pages[1].rows.length;
      } catch (_) {/* كبيرةٌ تعذّرت: البقيّة تُعرض */}
      if (!mounted) return;
    }
    _apply(rows, refreshing: false);
    if (extraExpired > 0 || extraNear > 0) {
      final e = _expiredToday.length + extraExpired, n = _nearExpiry.length + extraNear;
      AlertsService.setCounts(near: n, expiredToday: e);
      setState(() {
        _mergedTotals = true;
        _expiredTotal = e;
        _nearTotal = n;
      });
    } else if (_mergedTotals) {
      setState(() => _mergedTotals = false);
    }
  }

  /// القائمة ⇒ «انتهوا اليوم» و«أقلّ من ٢٤ ساعة» بتوقيت الآن.
  void _apply(List<Subscriber> list, {required bool refreshing}) {
    // منطق 2026-07-11:
    // • expiredToday = expDay == today && expDate.isBefore(now)
    // • nearExpiry = متبقّي < 24 ساعة (حتى دقيقة/ثانية) && لم ينتهِ بعد.
    //   المستخدم يريد بالضبط < 24h — يختفي فور الانتهاء.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiredToday = <Subscriber>[];
    final nearExpiry = <Subscriber>[];
    for (final s in list) {
      final exp = s.parsedExpiration;
      if (exp == null) continue;
      final expDay = DateTime(exp.year, exp.month, exp.day);
      if (expDay == today && exp.isBefore(now)) {
        expiredToday.add(s);
        continue;
      }
      if (exp.isAfter(now) && exp.difference(now).inHours < 24) {
        nearExpiry.add(s);
      }
    }
    // فرز تصاعدي حسب المتبقّي الفعلي (بالثواني) — أقرب مشترك للانتهاء
    // يظهر أوّلاً.
    nearExpiry.sort((a, b) {
      final ea = a.parsedExpiration!;
      final eb = b.parsedExpiration!;
      return ea.compareTo(eb);
    });
    // اتّفاق مع الجرس فوق الـDashboard على نفس العدّاد.
    AlertsService.updateFrom(list);
    setState(() {
      _expiredToday = expiredToday;
      _nearExpiry = nearExpiry;
      _loaded = true;
      _refreshing = refreshing;
    });
  }

  Future<void> _loadBig() async {
    // آخر صفحتين معروفتين (≤١٠ د) فوراً، والطازجتان في الطريق (٨ نوفمبر)
    final e0 = BigSubscribersApi.lastFirstPage('expired_today', _kBigInboxPage);
    final n0 = BigSubscribersApi.lastFirstPage('expiring_24h', _kBigInboxPage);
    if (e0 != null && n0 != null && mounted) _applyBig(e0, n0, refreshing: true);
    try {
      final r = await Future.wait([
        BigSubscribersApi.page(page: 1, size: _kBigInboxPage, tab: 'expired_today'),
        BigSubscribersApi.page(page: 1, size: _kBigInboxPage, tab: 'expiring_24h'),
      ]);
      BigSubscribersApi.remember('expired_today', _kBigInboxPage, r[0]);
      BigSubscribersApi.remember('expiring_24h', _kBigInboxPage, r[1]);
      if (!mounted) return;
      // حمّل المدير صفحاتٍ أخرى من المعروضة أثناء التحديث ⇒ لا تُمسح، والطازج يحدّث العدّاد وحده
      if (_expiredPage > 1 || _nearPage > 1) {
        AlertsService.setCounts(near: r[1].total, expiredToday: r[0].total);
        setState(() {
          _expiredTotal = r[0].total;
          _nearTotal = r[1].total;
          _refreshing = false;
        });
        return;
      }
      _applyBig(r[0], r[1], refreshing: false);
    } on BigListException catch (_) {
      if (!mounted) return;
      setState(() {
        _big = true;
        _loaded = true;
        _refreshing = false;
      });
    }
  }

  void _applyBig(BigPage expired, BigPage near, {required bool refreshing}) {
    AlertsService.setCounts(near: near.total, expiredToday: expired.total);
    setState(() {
      _big = true;
      _expiredToday = expired.rows;
      _nearExpiry = near.rows;
      _expiredTotal = expired.total;
      _nearTotal = near.total;
      _expiredPage = _nearPage = 1;
      _expiredLast = expired.lastPage;
      _nearLast = near.lastPage;
      _loaded = true;
      _refreshing = refreshing;
    });
  }

  /// الصفحة التالية لإحدى القائمتين (بلا تكرار صفٍّ ظهر).
  Future<void> _loadBigMore({required bool expired}) async {
    if (expired ? _expiredMore : _nearMore) return;
    setState(() => expired ? _expiredMore = true : _nearMore = true);
    try {
      final p = await BigSubscribersApi.page(
        page: (expired ? _expiredPage : _nearPage) + 1,
        size: _kBigInboxPage,
        tab: expired ? 'expired_today' : 'expiring_24h',
      );
      if (!mounted) return;
      setState(() {
        final cur = expired ? _expiredToday : _nearExpiry;
        final seen = cur.map((s) => s.idx ?? s.username).toSet();
        final next = [...cur, ...p.rows.where((s) => !seen.contains(s.idx ?? s.username))];
        if (expired) {
          _expiredToday = next;
          _expiredPage++;
          _expiredLast = p.lastPage;
          _expiredMore = false;
        } else {
          _nearExpiry = next;
          _nearPage++;
          _nearLast = p.lastPage;
          _nearMore = false;
        }
      });
    } on BigListException catch (_) {
      if (!mounted) return;
      setState(() => expired ? _expiredMore = false : _nearMore = false);
    }
  }

  Widget _bigMoreButton({required bool expired}) {
    final loading = expired ? _expiredMore : _nearMore;
    return Align(
      alignment: AlignmentDirectional.center,
      child: TextButton(
        onPressed: loading ? null : () => _loadBigMore(expired: expired),
        child: loading
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
            : Text('notifications.show_more'.tr(), style: AppType.bodyBold(color: AppColors.brand)),
      ),
    );
  }

  void _openSubscriber(Subscriber s) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ),
    );
  }

  /// عند النقر على إشعار: لو الـpayload يحمل اسم مشترك محدد
  /// (`username` / `subscriber_username` / `subscriber_id`)، نفتح كارت
  /// المشترك مباشرة — كأن المستخدم بحث عنه من overlay البحث. لو ما
  /// عندنا هوية، نستخدم onTapNotification callback الخارجي (fallback).
  Future<void> _handleNotificationTap(AppNotification n) async {
    InboxService.markRead(n.id);
    // تذكرة المشروع الوطني: «التذاكر» وورقتها — من الصندوق كما من شاشة القفل (الموجِّه نفسه).
    if (n.kind == NotificationKind.nationalTicket) {
      await openNationalTicketPush(Navigator.of(context), n.data);
      return;
    }
    if (await openConnAlertPush(Navigator.of(context), n.data)) return;
    // «طلب تجديد اشتراك» ⇒ الطلب نفسه بصورته وإجراءاته (لا كرت المشترك)
    if (!mounted) return;
    if (await openRenewRequestPush(Navigator.of(context), n.data)) return;
    // «التذاكر» ⇒ المحادثة نفسها (الحمولة تحمل يوزر المشترك لنسخٍ أقدم — لا كرته هنا)
    if (!mounted) return;
    if (await openTicketPush(Navigator.of(context), n.data)) return;
    final username = _extractUsername(n);
    if (username != null && username.isNotEmpty) {
      final sub = await _findSubscriber(username);
      if (!mounted) return;
      if (sub != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubscriberDetailScreen(sub: sub),
            fullscreenDialog: true,
          ),
        );
        return;
      }
    }
    // Fallback: لا نعرف مشترك محدد → مرّر للـcallback الخارجي (لو موجود).
    widget.onTapNotification?.call(n);
  }

  /// نبحث في payload عن أشهر الـkeys اللي backend يمرّرها لتحديد
  /// المشترك. تُعاد قيمة string غير فارغة أو null.
  /// مُفوَّضةٌ إلى [NotificationRouter] — مصدرٌ واحد للحقيقة مع نقرة
  /// النظام، وإلّا تفرّع منطقان يختلفان بصمت.
  String? _extractUsername(AppNotification n) =>
      NotificationRouter.extractUsername(n);

  Future<Subscriber?> _findSubscriber(String usernameOrId) =>
      NotificationRouter.findSubscriber(usernameOrId);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'notifications.title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
          actions: [
            // القائمتان من آخر قائمةٍ معروفة والطازجة في الطريق
            if (_refreshing)
              Padding(
                key: const ValueKey('inbox-refreshing'),
                padding: const EdgeInsetsDirectional.only(end: Sp.md),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
                  ),
                ),
              ),
            ValueListenableBuilder<int>(
              valueListenable: InboxService.changes,
              builder: (context, _, __) {
                final unread = InboxService.unreadCount;
                if (unread == 0) return const SizedBox.shrink();
                return TextButton.icon(
                  onPressed: () => InboxService.markAllRead(),
                  icon: Icon(LucideIcons.checkCheck,
                      size: 16, color: AppColors.brand),
                  label: Text(
                    'notifications.mark_all_read'.tr(),
                    style: AppType.bodyBold(color: AppColors.brand),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([_loadLists(), RenewRequestsState.ensureFresh(force: true)]),
          color: AppColors.brand,
          child: ValueListenableBuilder<int>(
            valueListenable: InboxService.changes,
            builder: (context, _, __) {
              final items = InboxService.all;
              final hasApp = items.isNotEmpty;
              final hasExpiredToday = _expiredToday.isNotEmpty;
              final hasNearExpiry = _nearExpiry.isNotEmpty;
              final hasRenew = RenewRequestsState.on && (RenewRequestsState.gate.value?.items.isNotEmpty ?? false);
              final allEmpty =
                  _loaded && !hasApp && !hasExpiredToday && !hasNearExpiry && !hasRenew;
              return ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: [
                  // «طلبات التجديد» بالأعلى — حين يوجد طلبٌ مفتوح وحده
                  const RenewInboxSection(),
                  if (hasApp) ...[
                    _SectionHeader(
                      title: 'notifications.app_notifications'.tr(),
                      count: items.length,
                      color: AppColors.brand,
                      icon: LucideIcons.bell,
                    ),
                    ..._buildGroups(items),
                    const SizedBox(height: Sp.md),
                  ],
                  if (hasExpiredToday) ...[
                    _SectionHeader(
                      title: 'notifications.expired_today'.tr(),
                      count: _big || _mergedTotals ? _expiredTotal : _expiredToday.length,
                      color: AppColors.error,
                      icon: LucideIcons.circleAlert,
                    ),
                    for (final s in _expiredToday) ...[
                      _SubscriberAlertRow(
                        sub: s,
                        detail: 'notifications.sub_expired_today'.tr(),
                        color: AppColors.error,
                        icon: LucideIcons.timerOff,
                        onTap: () => _openSubscriber(s),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_big && _expiredPage < _expiredLast) _bigMoreButton(expired: true),
                    const SizedBox(height: Sp.md),
                  ],
                  if (hasNearExpiry) ...[
                    _SectionHeader(
                      title: 'notifications.near_expiry_section'.tr(),
                      count: _big || _mergedTotals ? _nearTotal : _nearExpiry.length,
                      color: AppColors.warning,
                      icon: LucideIcons.triangleAlert,
                    ),
                    for (final s in _nearExpiry) ...[
                      _SubscriberAlertRow(
                        sub: s,
                        detail: _formatRemaining(s.parsedExpiration),
                        color: AppColors.warning,
                        icon: LucideIcons.clock,
                        onTap: () => _openSubscriber(s),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_big && _nearPage < _nearLast) _bigMoreButton(expired: false),
                  ],
                  if (!_loaded && !hasApp)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Sp.huge),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (allEmpty) _empty(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroups(List<AppNotification> items) {
    final groups = _groupByDay(items);
    final widgets = <Widget>[];
    for (int gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      widgets.add(Padding(
        padding: EdgeInsets.only(top: gi == 0 ? 0 : Sp.md, bottom: 6, right: 4),
        child: Text(
          g.label,
          style: AppType.label(color: AppColors.textMid)
              .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ));
      for (final n in g.items) {
        widgets.add(Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => InboxService.remove(n.id),
          background: Container(
            // `direction` أعلاه اتّجاهيّ (`endToStart`) فيجب أن تكون
            // المحاذاة كذلك: أيقونة الحذف تظهر في الجهة التي تُسحب
            // البطاقة نحوها، وهي تنعكس مع اللغة.
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.dangerSoftBg,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(LucideIcons.trash2, size: 18, color: AppColors.error),
          ),
          child: _NotificationRow(
            n: n,
            onTap: () => _handleNotificationTap(n),
          ),
        ));
        widgets.add(const SizedBox(height: 4));
      }
    }
    return widgets;
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.bellOff, size: 40, color: AppColors.textLow),
              const SizedBox(height: 12),
              Text('notifications.empty_title'.tr(),
                  style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: 4),
              Text('notifications.empty_hint'.tr(),
                  style: AppType.muted().copyWith(fontSize: 12.5)),
            ],
          ),
        ),
      );

  List<_Group> _groupByDay(List<AppNotification> items) {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final yStart = todayStart.subtract(const Duration(days: 1));
    final map = <String, List<AppNotification>>{};
    final order = <String>[];
    for (final n in items) {
      final at = n.receivedAt;
      String label;
      if (at.isAfter(todayStart) || at.isAtSameMomentAs(todayStart)) {
        label = 'reports.today'.tr();
      } else if (at.isAfter(yStart) || at.isAtSameMomentAs(yStart)) {
        label = 'reports.yesterday'.tr();
      } else {
        label =
            '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
      }
      if (!map.containsKey(label)) {
        map[label] = <AppNotification>[];
        order.add(label);
      }
      map[label]!.add(n);
    }
    return [
      for (final l in order) _Group(label: l, items: map[l]!),
    ];
  }
}

// ────────────────────────────────────────────
// v1 helper: صياغة "متبقّي X يوم و Y ساعة" لصف قريب الانتهاء.
String _formatRemaining(DateTime? exp) {
  if (exp == null) return 'notifications.expires_soon'.tr();
  final diff = exp.difference(DateTime.now());
  if (diff.isNegative) return 'notifications.remaining_expired'.tr();
  final days = diff.inDays;
  final hours = diff.inHours % 24;
  final minutes = diff.inMinutes % 60;
  final remaining = 'notifications.remaining'.tr();
  final andWord = 'notifications.and'.tr();
  final dayU = 'subscribers.day_unit'.tr();
  final hrU = 'subscribers.hour_unit'.tr();
  final minU = 'subscribers.minute_unit'.tr();
  if (days > 0) {
    return '$remaining $days $dayU${hours > 0 ? ' $andWord $hours $hrU' : ''}';
  }
  if (hours > 0) {
    return '$remaining $hours $hrU${minutes > 0 ? ' $andWord $minutes $minU' : ''}';
  }
  if (minutes > 0) return '$remaining $minutes $minU';
  return 'notifications.expires_now'.tr();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
    required this.icon,
  });
  final String title;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: AppType.label(color: AppColors.textHi)
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriberAlertRow extends StatelessWidget {
  const _SubscriberAlertRow({
    required this.sub,
    required this.detail,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final Subscriber sub;
  final String detail;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final fullName = '${sub.firstname} ${sub.lastname}'.trim();
    final displayName = fullName.isEmpty ? sub.username : fullName;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style:
                                AppType.label(color: AppColors.textHi).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // شارة حالة الاتصال — كانت مفقودة كلياً قبل
                        // 2026-07-14 فالمدير ما يعرف من الـInbox هل
                        // المشترك متصل أم لا بدون فتح البطاقة.
                        _OnlineDot(isOnline: sub.isOnline),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub.username,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // «كل الشركات»: شركة المشترك بلونها (الفتح موجَّهٌ لها)
                    if (sub.companyKey != null && MergedMode.active.value) ...[
                      const SizedBox(height: 2),
                      CompanyTag(companyKey: sub.companyKey!, fontSize: 11),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    // 2026-07-16: آخر اتصال للأوف لاين فقط (SAS4).
                    if (!sub.isOnline &&
                        (sub.lastOnline?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      _InboxInfoChip(
                        icon: LucideIcons.history,
                        text:
                            'آخر اتصال: ${_formatLastOnlineInbox(sub.lastOnline!)}',
                      ),
                    ],
                    // معلومات الجلسة الحيّة (تظهر فقط لو المشترك online).
                    if (sub.isOnline &&
                        ((sub.downloadBytes ?? 0) > 0 ||
                            (sub.uploadBytes ?? 0) > 0 ||
                            (sub.ipAddress?.isNotEmpty ?? false) ||
                            (sub.deviceVendor?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if ((sub.downloadBytes ?? 0) > 0 ||
                              (sub.uploadBytes ?? 0) > 0)
                            _InboxInfoChip(
                              icon: LucideIcons.arrowDownUp,
                              text:
                                  '${_fmtBytesInbox(sub.downloadBytes ?? 0)} ↓ / ${_fmtBytesInbox(sub.uploadBytes ?? 0)} ↑',
                            ),
                          if (sub.ipAddress?.isNotEmpty ?? false)
                            _InboxInfoChip(
                              icon: LucideIcons.globe,
                              text: sub.ipAddress!,
                            ),
                          if (sub.deviceVendor?.isNotEmpty ?? false)
                            _InboxInfoChip(
                              icon: LucideIcons.router,
                              text: sub.deviceVendor!,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.brand : AppColors.textLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline ? 'متصل' : 'غير متصل',
            style: AppType.muted(color: color).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxInfoChip extends StatelessWidget {
  const _InboxInfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: AppColors.brand),
          const SizedBox(width: 3),
          Text(
            text,
            style: AppType.muted(color: AppColors.brand).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2026-07-16: تنسيق last_online مختصر للـInbox.
String _formatLastOnlineInbox(String raw) {
  final t = DateTime.tryParse(raw) ?? DateTime.tryParse(raw.split(' ').first);
  if (t == null) return raw.split(' ').first;
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
  if (diff.inDays < 365) return 'قبل ${(diff.inDays / 30).round()} شهر';
  return 'قبل سنة+';
}

String _fmtBytesInbox(int bytes) {
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

class _Group {
  const _Group({required this.label, required this.items});
  final String label;
  final List<AppNotification> items;
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final meta = _metaFor(n.kind);
    return Material(
      color: n.isRead ? AppColors.surface : AppColors.brandSoftBg,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: n.isRead ? AppColors.border : AppColors.brandSoftBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(meta.icon, size: 16, color: meta.color),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n.title.isEmpty ? meta.fallbackTitle : n.title,
                            style:
                                AppType.label(color: AppColors.textHi).copyWith(
                              fontSize: 13,
                              fontWeight:
                                  n.isRead ? FontWeight.w700 : FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!n.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (n.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        n.body,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 12.5, height: 1.4),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(n.receivedAt),
                      style:
                          AppType.muted().copyWith(fontSize: 10.5, height: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _KindMeta _metaFor(NotificationKind k) {
    switch (k) {
      case NotificationKind.nearExpiryDigest:
        return _KindMeta(
          icon: LucideIcons.alarmClock,
          color: AppColors.warning,
          fallbackTitle: 'notifications.digest_near_expiry'.tr(),
        );
      case NotificationKind.expiredTodayDigest:
        return _KindMeta(
          icon: LucideIcons.circleAlert,
          color: AppColors.error,
          fallbackTitle: 'notifications.digest_expired_today'.tr(),
        );
      case NotificationKind.managerDebt:
        return _KindMeta(
          icon: LucideIcons.creditCard,
          color: AppColors.error,
          fallbackTitle: 'notifications.mgr_debt'.tr(),
        );
      case NotificationKind.managerBalance:
        return _KindMeta(
          icon: LucideIcons.banknote,
          color: AppColors.success,
          fallbackTitle: 'notifications.mgr_balance_update'.tr(),
        );
      case NotificationKind.nationalTicket:
        return _KindMeta(
          icon: LucideIcons.headset,
          color: AppColors.info,
          fallbackTitle: 'notifications.national_ticket'.tr(),
        );
      case NotificationKind.other:
        return _KindMeta(
          icon: LucideIcons.bell,
          color: AppColors.brand,
          fallbackTitle: 'notifications.other'.tr(),
        );
    }
  }

  static String _formatTime(DateTime dt) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} ${p(dt.hour)}:${p(dt.minute)}';
  }
}

class _KindMeta {
  const _KindMeta({
    required this.icon,
    required this.color,
    required this.fallbackTitle,
  });
  final IconData icon;
  final Color color;
  final String fallbackTitle;
}
