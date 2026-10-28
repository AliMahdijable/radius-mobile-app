import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/device_probe_api.dart';
import '../../api/big_subscribers_api.dart';
import '../../api/sales_api.dart';
import '../../api/subscribers_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/platform/app_platform.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/util/format.dart';
import '../../core/util/phone.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/copyable.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/merged_mode.dart';
import '../../services/app_resumed_signal.dart';
import '../../services/connection_alerts.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../services/provider_limits.dart';
import '../../services/subscriber_events.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../reports/account_statement_screen.dart';
import '../reports/sessions_report_screen.dart';
import 'sheets/activate_sheet.dart';
import 'sheets/add_debt_sheet.dart';
import 'sheets/add_credit_sheet.dart';
import 'sheets/location_sheets.dart';
import 'sheets/edit_subscriber_sheet.dart';
import 'sheets/extend_sheet.dart';
import 'sheets/movements_sheet.dart';
import 'sheets/consumption_sheet.dart';
import 'sheets/pay_debt_sheet.dart';
import 'sheets/qr_login_sheet.dart';
import 'sheets/quick_discount_sheet.dart';
import 'sheets/subscriber_price_sheet.dart';
import 'widgets/balance_card.dart';
import '../../api/device_config_api.dart';
import 'widgets/device_chip_micro.dart';
import '../../services/subscriber_refresh_signal.dart';
import '../sales/sales_screen.dart' show showSellToSubscriber;
import 'widgets/device_probe_card.dart';
import 'widgets/last_seen_card.dart';
import 'widgets/subscriber_actions.dart';
import 'connection_alert_flow.dart';
import '../../services/receipt_service.dart';
import '../../core/widgets/print_feedback.dart';
import '../network_devices/fiber/fiber_subscriber_card.dart';

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
  bool _alerting = false;
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
  /// null = قيد التحميل أو فشل. non-null = جاهز للعرض في _HeroPassword.
  String? _subscriberPassword;

  /// كلمة السرّ ظاهرةٌ الآن (العين مفتوحة). تعيش هنا لا في صفّها: «نسخ كلّ
  /// المعلومات» يضمّها **حين تظهر وحدها** — من يرى النقاط لا يتوقّع أن
  /// يلصق كلمة السرّ في محادثةٍ مع غيره.
  bool _passwordVisible = false;

  /// كارت الجهاز — منه يقرأ «نسخ كلّ المعلومات» ما يرسمه الآن
  /// ([DeviceProbeCard.shownBy])، لا ما بقي في مخزن الفحص.
  final _deviceCardKey = GlobalKey();

  /// إعداد الجهاز الذي رُسم به كارت الاتّصال آخر مرّة (عنوانه المثبَّت).
  /// يكتبه بانيه بلا `setState` — لا يُرسم منه شيء، يُقرأ لحظة النسخ وحدها.
  DeviceConfig? _drawnConfig;

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
      _deleting ||
      _alerting;

  @override
  void initState() {
    super.initState();
    // حدود «تنبيه المشترك» وتفعيله — الكارت قد يُفتح من البحث لا من
    // القائمة، فلا نفترض أنّ أحداً جلبها قبلنا.
    ConnectionAlertSettings.ensureLoaded();
    // «بيع مادّة» يظهر حين تكون «المبيعات» مفعّلةً للحساب (مفتاحٌ بالخادم) — حالتها قد لم تُسأل بعد إن فُتح المشترك أوّلاً.
    unawaited(SalesState.ensureFresh());
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
    // 2026-08-25: أُزيلت صلاحيّة الحجب (app-level) لأنّها شلّت مساعدة المشترك.
    // Pro: أُعيدت البوّابة لكن بصلاحيّة **الساس** (subscribers.show_password):
    // أغلب الشركات العراقيّة لا تسمح بعرض الباسورد، ومن تسمح (=true) يبقى
    // متاحاً للدعم. لا نجلبه أصلاً إن مُنع — فلا يبقى في الذاكرة بلا داعٍ.
    if (Perms.has('subscribers.show_password')) {
      _loadPassword();
    }
    // «كل الشركات»: هويّته من ساس شركته أوّل الفتح — يسكّ عليها الخادم مرجع النافذة الذي تطلبه كلّ كتابة
    if (sub.companyKey != null) MergedOps.ensureSubject(sub);
    // جلب حالة الاتّصال مرّةً عند الفتح حين يكون المشترك متّصلاً بلا
    // عنوان في الصفّ — كالسحب للتحديث تماماً.
    //
    // 🐛 على الحاسبة (والفتح من البحث) يصل الصفّ أحياناً من
    // `/api/v2/subscribers` بلا طبقة الجلسة (العنوان/المدّة/التحميل)،
    // فتبقى بلاطة الاتّصال مخفيّة وكارت الجهاز بلا عنوانٍ يفحص عليه —
    // ولا onu/نانو ولا «ضمن الشبكة». المدير يراها على الهاتف من القائمة
    // (تدمجها بالخلفيّة) ويفتقدها على الحاسبة. نجعل الكارت يجلبها بنفسه.
    // المتّصل ذو العنوان أصلاً (قائمة الهاتف المدموجة) لا يُجبَر فلا جولة
    // زائدة، والمفصول لا شيء يُعرَض له.
    if (!AppPlatform.isUnderTest && sub.isOnline && (sub.ipAddress ?? '').trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _onDataChanged(force: true);
        // وصل العنوان الآن ⇒ كارت الجهاز يفحص عليه (لا didUpdateWidget فيه).
        if (mounted && (sub.ipAddress ?? '').trim().isNotEmpty) {
          SubscriberRefreshSignal.bump();
        }
      });
    }
  }

  Future<void> _loadPassword() async {
    final idx = sub.idx;
    if (idx == null) return;
    final pass = await MergedOps.run(sub, () => SubscribersApi.fetchPassword(idx.toString()));
    if (!mounted || pass == null || pass.isEmpty) return;
    setState(() => _subscriberPassword = pass);
  }

  @override
  void dispose() {
    SubscriberEvents.dataChanged.removeListener(_onDataChanged);
    AppResumedSignal.tick.removeListener(_onDataChanged);
    super.dispose();
  }

  /// [force] يتجاوز مخزن القائمة ويجلب حالة الاتّصال معها — للسحب
  /// اليدويّ. المستمعون (حدث تغيّر البيانات، والعودة من الخلفيّة)
  /// يتركونه `false`: مخزنهم مُبطَلٌ أصلاً، فالإجبار جولةٌ زائدة.
  Future<void> _onDataChanged({bool force = false}) async {
    if (!mounted) return;
    // Safety timeout — لمّا نُستدعى من AppResumedSignal بعد فترة
    // غياب طويلة، الـbackend ممكن يتأخّر (SubscribersApi.loadAll
    // يحمّل قائمة ثقيلة). بدون timeout، الـFuture يعلق ويبقى الصف
    // stale بلا مؤشّر بصري.
    List<Subscriber>? list;
    try {
      // السحب اليدويّ يتجاوز المخزن **ويجلب حالة الاتّصال معها**.
      //
      // 🐛 الجلب العاديّ يأتي من `/api/v2/subscribers` وهو لا يحمل
      // بيانات الجلسة، فكان الكود أدناه يُرجّع القديمة إلى مكانها —
      // فتتحدّث الباقة والانتهاء والدين، وتبقى مدّة الجلسة والتحميل
      // والرفع مجمَّدةً على ما كانت لحظة فتح الشاشة. وهي بالضبط
      // الأرقام التي يسحب المدير ليراها.
      // الحساب الكبير: صفّه وحده من الساس بيوزره — لا قائمة كاملة.
      // «كل الشركات»: صفّه من قائمة شركته الطازجة (لا قائمة الشركة المفتوحة)
      if (sub.companyKey != null) {
        final one = await MergedOps.refetch(sub).timeout(const Duration(seconds: 30));
        list = one == null ? null : [one];
      } else if (await BigSubscribersApi.probe() > 0) {
        final one = await BigSubscribersApi.findOne(idx: sub.idx, username: sub.username)
            .timeout(const Duration(seconds: 20));
        list = one == null ? null : [one];
      } else {
        list = await (force
                ? SubscribersApi.loadAllWithOnline()
                : SubscribersApi.loadAll())
            .timeout(const Duration(seconds: 20));
      }
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
      // عند الجلب المُجبَر يحمل الصفّ حالة اتّصالٍ حقيقيّة فنأخذها؛
      // وإلّا نحفظ القديمة كي لا يفقد المتّصل كرت جلسته.
      sub = force
          ? fresh!
          : fresh!.copyWithOnline(
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
              onCopyAll: _copyAll,
              onPrint: _printReceipt,
              printing: _printingReceipt,
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.brand,
                onRefresh: () async {
                  // الإشارة **أوّلاً**: كرت الجهاز يفحص بنفسه، فإطلاقها
                  // قبل `await` يجعل الجلبين متوازيين ولا يُطيل المؤشّر
                  // بانتظار فحص CPE بطيء. نفس ترتيب اللوحة.
                  SubscriberRefreshSignal.bump();
                  await _onDataChanged(force: true);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.lg,
                    Sp.sm,
                    Sp.lg,
                    Sp.huge,
                  ),
                  children: [
                    // الهيرو الجديد — كرت teal كبير مع 3 إحصاءات.
                    _SubscriberHero(
                      sub: sub,
                      password: _subscriberPassword,
                      passwordVisible: _passwordVisible,
                      onTogglePassword: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                    ),
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
                      // الصلاحيّة: إرسال قالب واتساب للمشترك مبوّبٌ بـ
                      // `subscribers.send_whatsapp` (مطابقةً لنظيره في شيت
                      // «المزيد»). بدونها كان زرّ التذكير يظهر لمديرٍ مُنِع
                      // المراسلة — فجوةُ تسرّبٍ أغلقها تدقيق ٢٠٢٦-١٠-٠٨.
                      //
                      // بلاغ ٢٠٢٦-١٠-١٤: الحالة (لا دين/لا هاتف/إرسال جارٍ)
                      // تُخفي الزرّ كما كانت؛ أمّا نقص المفتاح وحده فيُبقيه
                      // **مقفلاً** في مكانه — لا يختفي ولا يرسل شيئاً.
                      onRemind: _remindState &&
                              Perms.has('subscribers.send_whatsapp')
                          ? () => _sendTemplate('debt_reminder')
                          : null,
                      remindLocked:
                          _remindState && _locked('subscribers.send_whatsapp'),
                      // 2026-09-05: كان الشرط `balanceAmount != 0` فيفتح
                      // «تسديد» لصاحب الرصيد الدائن أيضاً — والتسديد يجمع
                      // على الرصيد لا يطرح منه، فمشتركٌ له ٣٠٬٠٠٠ يصير له
                      // ٦٠٬٠٠٠. ومَن أراد استهلاك رصيدٍ دائن فبابه «إضافة
                      // دين» وهو ظاهرٌ له أصلاً.
                      onPay: sub.hasDebt && Perms.has('subscribers.pay_debt')
                          ? () => showPayDebtSheet(context, sub)
                          : null,
                      payLocked:
                          sub.hasDebt && _locked('subscribers.pay_debt'),
                      onAddDebt: Perms.has('subscribers.add_debt')
                          ? () => showAddDebtSheet(context, sub)
                          : null,
                      addDebtLocked: _locked('subscribers.add_debt'),
                    ),
                    // صفّ الإجراءات الأربعة — المخطّط يضعه مباشرةً تحت
                    // بلوك الدين وفوق كارت الاتصال. الباقي انتقل إلى شيت
                    // «إجراءات أخرى» خلف بلاطة «المزيد».
                    const SizedBox(height: Sp.md),
                    // يُعاد بناؤه مع كلّ قراءةٍ للجهاز ومع وصول حدود المدير:
                    // بلاطة «تنبيه» تظهر وتختفي بحسبهما.
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        DeviceProbeBus.tick,
                        ConnectionAlertSettings.current
                      ]),
                      builder: (context, _) =>
                          SubscriberActionTiles(actions: _quickActions()),
                    ),
                    const SizedBox(height: Sp.md),
                    // كرتُ الاتّصال يقرّر ظهوره بنفسه: يظهر عند جلسةٍ
                    // قائمة، **أو** حين يوجد IP مثبَّت وإن كان مفصولاً —
                    // فالعنوان المثبَّت لا يزول بزوال الجلسة. وكان
                    // بطاقةً مستقلّة فأكل مساحةً لا يستحقّها لسطرٍ واحد.
                    _LiveSessionCard(
                      sub: sub,
                      onDrawn: (cfg) => _drawnConfig = cfg,
                    ),
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
                    //
                    // وفوقه «آخر اتصال» لغير المتّصل: متى وآخر جهاز (MAC) —
                    // كصفّ القائمة، لكلّ المزوّدين (المجموعة ② ١٨ أكتوبر).
                    LastSeenCard(sub: sub),
                    // جهاز الألياف (ONU) للمشترك المربوط بها من «شبكة الألياف» — حالته وضوؤه الآن والتشخيص.
                    FiberSubscriberCard(sub: sub),
                    DeviceProbeCard(
                      key: _deviceCardKey,
                      ip: sub.ipAddress ?? '',
                      username: sub.username,
                      company: sub.companyKey,
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
                    //
                    // ٢٠٢٦-١٠-١٤: بلا `subscribers.activate` يبقى الزرّ مقفلاً
                    // في مكانه (لا شيت تفعيل ولا طلب) بدل أن يختفي.
                    if (permShown(const ['subscribers.activate'])) ...[
                      const SizedBox(height: Sp.md),
                      SubscriberPrimaryAction(
                        icon: LucideIcons.refreshCw,
                        label: 'subscribers.renew_subscription'.tr(),
                        busy: _isBusy,
                        locked: _locked('subscribers.activate'),
                        onTap: _locked('subscribers.activate')
                            ? null
                            : () => showActivateSheet(context, sub),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «نسخ كلّ المعلومات» — سطر «التسمية: القيمة» لكلّ ما في الكارت.
  ///
  /// ⚠️ بلا أيّ جلبٍ لحظة النسخ: ما في الذاكرة وحده — المشترك، وكلمة السرّ
  /// إن جُلبت **وظهرت**، وما يرسمه كارتا الاتّصال والجهاز **الآن**. نسخٌ
  /// ينتظر الشبكة يضيع نصفه إن أُغلقت الشاشة.
  ///
  /// 🐛 والمرسوم لا المخزَّن: كارت الجهاز يُبقي آخر قراءةٍ ناجحة إن فشل فحصٌ
  /// بعدها والمخزن يحفظ الفشل، وجلبُ إعدادٍ فاشل يرسم الكارت بلا عنوانه
  /// المثبَّت ويُبقي المخزن القديم — فكان المنسوخ يُسقط ما على الشاشة أو
  /// يضيف ما ليس عليها. والمخزن احتياطٌ لكارتٍ لم يُركَّب بعد (خارج الشاشة):
  /// هو ما سيرسمه حين يُركَّب.
  /// «طباعة وصل» — بطاقة معلومات المشترك الآن، كزرّ الموقع (بلا صلاحيّة: يُطبع ما يُعرض له).
  /// الحاسبة بطابعةٍ مباشرة: تخرج فوراً بلا نافذة.
  bool _printingReceipt = false;

  Future<void> _printReceipt() async {
    if (_printingReceipt) return;
    setState(() => _printingReceipt = true);
    final r = await ReceiptService.printSubscriberCard(sub);
    if (!mounted) return;
    setState(() => _printingReceipt = false);
    showPrintResult(context, r);
  }

  Future<void> _copyAll() async {
    final ip = sub.ipAddress?.trim() ?? '';
    final config = _drawnConfig ??
        DeviceConfigApi.peekConfig(sub.username, company: sub.companyKey);
    final DeviceCardShown device;
    if (DeviceProbeCard.shownBy(_deviceCardKey) case final shown?) {
      device = shown;
    } else {
      final cached = DeviceProbeApi.peek(
          username: sub.username, ip: ip, company: sub.companyKey);
      device = (snap: cached?.snap, at: cached?.at, notes: config?.notes);
    }
    final fields = subscriberCopyFields(
      sub,
      password: _subscriberPassword,
      passwordVisible: _passwordVisible,
      deviceConfig: config,
      device: device,
    );
    final hasPassword = (_subscriberPassword ?? '').isNotEmpty;
    await copyToClipboard(
      context,
      copyFieldsText(fields),
      message: !hasPassword
          ? 'copy.all_done'.tr()
          : (_passwordVisible
              ? 'copy.all_done_password'.tr()
              : 'copy.all_done_password_hidden'.tr()),
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
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
    final result = await MergedOps.write(sub, () => SubscribersApi.disconnect(id));
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
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: wantEnable ? AppColors.brand : AppColors.warning,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
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
      builder: (dialogCtx) => AlertDialog(
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
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
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
    final result = await MergedOps.write(sub, () => SubscribersApi.delete(idx));
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
    // قوالب واتساب (المعاينة ثمّ الإرسال) خارج جدول التوجيه — في «كل الشركات» للشركة وحدها
    final blocked = MergedOps.unsupported(sub);
    if (blocked != null) {
      showSheetSnack(context, blocked, isError: true);
      return;
    }
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
    final success = await MergedOps.write(sub, () => SubscribersApi.toggle(id, enable: wantEnable));
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
  // البوّابات (`Perms.has`) نُقلت كما هي حرفيّاً — لا إجراء يُنفَّذ لمن
  // لا يملكه، ولا إجراء سقط في النقل.
  //
  // ── بلاغ ٢٠٢٦-١٠-١٤ (صاحب المشروع، لقطة موظّف): «القوائم تبقى بس
  // تظهر ما عنده صلاحيّة». فالإجراء الذي ينقصه مفتاحه **يبقى في مكانه
  // مقفلاً** (`locked: true`، ونداؤه null فلا شيت ولا طلب) بدل أن يختفي،
  // فلا تتبدّل البلاطات والمجموعات بين موظّفٍ وآخر. ويبقى مخفيّاً:
  //   • ما تحجبه الحالة (لا دين، غير متّصل، لا idx، لا هاتف…).
  //   • ما لا يدعمه المزوّد (ايرث لنك) — ليس صلاحيّة.
  //   • مفتاحٌ لا يُمنح لهذا الدور أصلاً (`permShown`) — «اطلبها من
  //     مديرك» لما لا يملك المدير منحه وعدٌ كاذب.
  // والمالك يملك كلّ شيء، فكلّ `locked` عنده false وشاشته كما هي.

  /// لا يملكه **ويمكن أن يُمنحه** → يُعرض مقفلاً. (لا يملكه ولا يُمنح
  /// لدوره → لا هذا ولا ذاك، فيبقى مخفيّاً.)
  static bool _locked(String key) => !Perms.has(key) && permShown([key]);

  /// يُعرض الإجراء أصلاً (حيّاً أو مقفلاً)؟
  static bool _shows(String key) => Perms.has(key) || _locked(key);

  /// حالة زرّ «تذكير بالدين» بمعزلٍ عن الصلاحيّة: دَينٌ + هاتف + لا إرسال
  /// جارٍ. غيابها يُخفي الزرّ للجميع؛ وحضورها بلا مفتاح يُقفله.
  bool get _remindState =>
      sub.hasDebt && _sendingTemplate == null && sub.displayPhone.isNotEmpty;

  /// البلاطات الأربع: تمديد · تعديل · تعطيل/تفعيل · المزيد.
  /// «المزيد» حاضرة دائماً — هي المدخل الوحيد لباقي العمليّات.
  List<SubAction> _quickActions() {
    return <SubAction>[
      if (_shows('subscribers.extend'))
        SubAction(
          icon: LucideIcons.calendarPlus,
          label: 'subscribers.op_extend'.tr(),
          locked: _locked('subscribers.extend'),
          onTap: (_isBusy || _locked('subscribers.extend'))
              ? null
              : () => showExtendSheet(context, sub),
        ),
      if (_shows('subscribers.edit'))
        SubAction(
          icon: LucideIcons.pencil,
          label: 'subscribers.op_edit'.tr(),
          locked: _locked('subscribers.edit'),
          onTap: (_isBusy || _locked('subscribers.edit'))
              ? null
              : () => showEditSubscriberSheet(context, sub),
        ),
      // التسمية تتبع الحالة (`isDisabled`) حتّى وهو مقفل.
      if (_shows('subscribers.toggle'))
        SubAction(
          icon: sub.isDisabled ? LucideIcons.circleCheck : LucideIcons.ban,
          label: sub.isDisabled
              ? 'subscribers.enable'.tr()
              : 'subscribers.disable'.tr(),
          color: sub.isDisabled ? AppColors.success : AppColors.warningFill,
          busy: _toggling,
          locked: _locked('subscribers.toggle'),
          onTap: (sub.idx == null || _isBusy || _locked('subscribers.toggle'))
              ? null
              : _confirmToggleEnabled,
        ),
      // فصل الجلسة إجراءٌ يوميّ يُطلَب والمشترك على الهاتف — ودفنُه
      // في «المزيد ← منطقة الخطر» يكلّف نقرتين وبحثاً. وهو مشروطٌ
      // بالاتّصال: لا معنى لفصل مفصول.
      // الصلاحيّة: نفس قدرة الفصل الجماعيّ (`subscribers.toggle` في
      // subscribers_screen.dart) — بدونها كان المقيَّد بـtoggle:false
      // يُحجَب عنه الفصل الجماعيّ ويبقى فصل التفصيل = تصعيد صلاحيّة
      // أغلقه تدقيق ٢٠٢٦-١٠-٠٨.
      // والحالة (متّصل + idx) تُخفيه للجميع؛ نقص المفتاح وحده يُقفله.
      if (_shows('subscribers.toggle') && sub.isOnline && sub.idx != null)
        SubAction(
          icon: LucideIcons.power,
          // «فصل» لا «فصل المستخدم»: البلاطات تتقاسم العرض، وخمسٌ منها
          // على شاشة ٣٢٠ تترك ~٥١ نقطة فتُقصّ الطويلة إلى «فصل الم…».
          // والأيقونة وحوار التأكيد يحملان بقيّة المعنى.
          label: 'subscribers.disconnect'.tr(),
          color: AppColors.error,
          busy: _disconnecting,
          locked: _locked('subscribers.toggle'),
          onTap: (_isBusy || _locked('subscribers.toggle'))
              ? null
              : _confirmDisconnect,
        ),
      // «تنبيه المشترك» — **عند المشكلة وحدها**، كشريط القائمة. لا تظهر
      // لمشتركٍ سليم، ولا لمن تعذّر الوصول إلى جهازه: لا مشكلةَ معروفة
      // نُنبّهه عليها. (طلب المستخدم ٢٠٢٦-١٠-٠١، بعد أن كان زرّاً دائماً
      // أسفل كارت الجهاز.)
      if (_connectionProblems().isNotEmpty)
        SubAction(
          icon: LucideIcons.bellRing,
          // قصيرة: البلاطات قد تصير ستّاً، وعلى شاشة ٣٢٠ يبقى للتسمية
          // نحو ثلاثين نقطة.
          label: 'conn_alerts.tile'.tr(),
          color: AppColors.warningFill,
          busy: _alerting,
          onTap: _isBusy ? null : _alertConnection,
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

  /// مشاكل آخر قراءةٍ **طازجة** لجهاز المشترك بحدود المدير، أو فارغة.
  ///
  /// الكاش يُقرأ بمهلة الخمس دقائق: قراءةٌ أقدم لا تُظهر البلاطة، فلا
  /// نُنبّه مشتركاً على حالٍ ربّما تغيّرت. وكارت الجهاز يُحدّثها ثمّ ينادي
  /// `DeviceProbeBus` فتظهر.
  List<ConnectionProblem> _connectionProblems() {
    if (!Perms.has('whatsapp.send') || sub.displayPhone.isEmpty) {
      return const [];
    }
    // «كل الشركات»: التنبيه (قوالب الشركة وإرسالها) للشركة وحدها — لا بلاطة تنتهي برفض. القراءة نفسها على كارت الجهاز.
    if (sub.companyKey != null) return const [];
    final settings = ConnectionAlertSettings.current.value;
    if (!settings.enabled) return const [];
    final ip = sub.ipAddress?.trim() ?? '';
    final snap = DeviceProbeApi.cachedForUser(sub.username) ??
        (ip.isEmpty ? null : DeviceProbeApi.cached(ip));
    if (snap == null) return const [];
    return ConnectionAlerts.detect(snap, settings);
  }

  Future<void> _alertConnection() async {
    if (_alerting) return;
    setState(() => _alerting = true);
    try {
      await showConnectionAlertFlow(context, sub);
    } finally {
      if (mounted) setState(() => _alerting = false);
    }
  }

  /// مجموعات شيت «إجراءات أخرى». ما ظهر كبلاطة أعلاه (تمديد/تعديل/
  /// تعطيل) وما ظهر كزرّ أساسي (تجديد) لا يتكرّر هنا.
  List<SubActionGroup> _moreGroups() {
    final phone = sub.displayPhone;
    // ايرث لنك لا تسمح بحذف المشترك ⇒ لا «حذف» أصلاً ([subscriberDeleteHidden]).
    final deleteHidden = subscriberDeleteHidden();
    return <SubActionGroup>[
      SubActionGroup('subscribers.group_money'.tr(), [
        if (_shows('subscribers.add_debt'))
          SubAction(
            icon: LucideIcons.plus,
            label: 'subscribers.op_add_debt'.tr(),
            color: AppColors.warningFill,
            locked: _locked('subscribers.add_debt'),
            onTap: _locked('subscribers.add_debt')
                ? null
                : () => showAddDebtSheet(context, sub),
          ),
        // عكس «إضافة الدين» — إضافة رصيدٍ دائن للمشترك (المالك ٢٧ أكتوبر).
        if (_shows('subscribers.add_credit'))
          SubAction(
            icon: LucideIcons.coins,
            label: 'إضافة رصيد',
            color: AppColors.successFill,
            locked: _locked('subscribers.add_credit'),
            onTap: _locked('subscribers.add_credit')
                ? null
                : () => showAddCreditSheet(context, sub),
          ),
        // 2026-08-29 وسّع الشرط إلى `balanceAmount != 0` ليصل المدخلُ
        // صاحبَ الرصيد الدائن. وكان ذلك خطأً: التسديد يجمع على الرصيد
        // (newBalance = balance + amount)، فصاحب ٣٠٬٠٠٠ دائن يخرج بـ
        // ٦٠٬٠٠٠، والشيت يسمّي رصيده «الدين الحالي» بالأحمر لأنّ
        // `debtAbs` قيمةٌ مطلقة لا دين. استهلاك الرصيد بابه «إضافة دين».
        // المقفل بلا `meta`: المبلغ والسعر بياناتٌ مبوّبة بالمفتاح نفسه.
        if (sub.hasDebt && _shows('subscribers.pay_debt'))
          SubAction(
            icon: LucideIcons.banknote,
            label: 'subscribers.op_pay_debt'.tr(),
            color: AppColors.brandAccent,
            locked: _locked('subscribers.pay_debt'),
            meta: _locked('subscribers.pay_debt')
                ? null
                : formatIQD(sub.debtAbs.round()),
            onTap: _locked('subscribers.pay_debt')
                ? null
                : () => showPayDebtSheet(context, sub),
          ),
        // «بيع مادّة» (المالك ٢٣ أكتوبر: «من صفحه المشتركين … الكه زر بيع ماده للمشترك») — «بيع جديد» والمشترك مختار.
        // حين تكون «المبيعات» مفعّلةً للحساب، وللشركة المفتوحة وحدها (مشترك شركةٍ أخرى في «كل الشركات» لا).
        if (SalesState.visible && sub.companyKey == null && sub.idx != null && _shows('sales.sell'))
          SubAction(
            icon: LucideIcons.shoppingCart,
            label: 'sales.sell_to_sub'.tr(),
            color: AppColors.brandAccent,
            locked: _locked('sales.sell') || SalesState.gate.value!.scoped,
            onTap: (_locked('sales.sell') || SalesState.gate.value!.scoped)
                ? null
                : () => showSellToSubscriber(
                      context,
                      idx: sub.idx!,
                      username: sub.username,
                      name: sub.fullName.trim(),
                      phone: sub.displayPhone.isEmpty ? null : sub.displayPhone,
                    ),
          ),
        if (_shows('discounts.manage'))
          SubAction(
            icon: LucideIcons.tag,
            label: 'subscribers.op_quick_discount'.tr(),
            locked: _locked('discounts.manage'),
            onTap: _locked('discounts.manage')
                ? null
                : () => showQuickDiscountSheet(context, sub),
          ),
        // «أسعار المشتركين» — بجانب الخصم لأنّه أخوه: الثابت يلغي الخصم.
        if (_shows('subscriber_prices.manage') && sub.idx != null)
          SubAction(
            icon: LucideIcons.banknote,
            label: 'sp.op_fixed_price'.tr(),
            locked: _locked('subscriber_prices.manage'),
            meta: _locked('subscriber_prices.manage')
                ? null
                : (sub.isFixedPrice && sub.price != null
                    ? formatIQD(sub.price!)
                    : (sub.needsRepricing
                        ? 'sp.needs_repricing_short'.tr()
                        : null)),
            onTap: _locked('subscriber_prices.manage')
                ? null
                : () => showSubscriberPriceSheet(
                      context,
                      idx: sub.idx!,
                      name: sub.fullName.trim().isNotEmpty
                          ? sub.fullName
                          : sub.username,
                      companyKey: sub.companyKey,
                    ),
          ),
      ]),
      SubActionGroup('subscribers.group_contact'.tr(), [
        if (sub.hasDebt && _shows('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.bellRing,
            label: 'subscribers.op_debt_reminder'.tr(),
            color: AppColors.warningFill,
            busy: _sendingTemplate == 'debt_reminder',
            locked: _locked('subscribers.send_whatsapp'),
            onTap: _locked('subscribers.send_whatsapp')
                ? null
                : () => _sendTemplate('debt_reminder'),
          ),
        if (sub.isNearExpiry && _shows('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.alarmClock,
            label: 'subscribers.op_expiry_warning'.tr(),
            color: AppColors.warningFill,
            busy: _sendingTemplate == 'expiry_warning',
            locked: _locked('subscribers.send_whatsapp'),
            onTap: _locked('subscribers.send_whatsapp')
                ? null
                : () => _sendTemplate('expiry_warning'),
          ),
        if (_shows('subscribers.send_whatsapp'))
          SubAction(
            icon: LucideIcons.info,
            label: 'subscribers.op_send_info'.tr(),
            busy: _sendingTemplate == 'subscriber_info',
            locked: _locked('subscribers.send_whatsapp'),
            onTap: _locked('subscribers.send_whatsapp')
                ? null
                : () => _sendTemplate('subscriber_info'),
          ),
        // «نسخ كلّ المعلومات» — أخو «إرسال المعلومات»: ذاك يرسلها بقالب،
        // وهذا يضعها في الحافظة لتُلصق أينما شاء. بلا صلاحيّة: لا يُنسخ إلّا
        // ما يُعرض له أصلاً (كلمة السرّ بمفتاحها وحين تظهر). وهو نفسه زرّ
        // النسخ في رأس الشاشة؛ هنا باسمه لمن لا يعرف الأيقونة.
        SubAction(
          icon: LucideIcons.copy,
          label: 'copy.all'.tr(),
          onTap: _copyAll,
        ),
        // «طباعة وصل» باسمه هنا أيضاً لمن لا يعرف أيقونة الرأس — كقائمة الموقع.
        SubAction(
          icon: LucideIcons.printer,
          label: 'printer.receipt'.tr(),
          busy: _printingReceipt,
          onTap: _printingReceipt ? null : _printReceipt,
        ),
        // رمز QR / رابط البوّابة — ايرث لنك وFTTH: مخفيّ (بطاقة الرابط SAS4
        // وحده، وQR ايرث لنك لتطبيق 2.0.7 وحده — [hasPortalQrCard]) — المزوّد
        // لا الصلاحيّة.
        if (_shows('subscribers.send_whatsapp') &&
            // «كل الشركات»: مزوّد شركة المشترك (بطاقة الرابط لساسٍ SAS4 وحده)
            (MergedOps.isEarthlink(sub) == null ? ProviderService.hasPortalQrCard : MergedOps.isEarthlink(sub) == false))
          SubAction(
            icon: LucideIcons.qrCode,
            label: 'subscribers.op_qr_login'.tr(),
            locked: _locked('subscribers.send_whatsapp'),
            onTap: _locked('subscribers.send_whatsapp')
                ? null
                : () => showQrLoginSheet(context, sub),
          ),
        if (phone.isNotEmpty)
          SubAction(
            icon: LucideIcons.phone,
            label: 'subscribers.call'.tr(),
            meta: localPhone(phone),
            onTap: () => _launchUri(Uri.parse('tel:${localPhone(phone)}')),
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
        if (_shows('subscribers.view_activity'))
          SubAction(
            icon: LucideIcons.history,
            label: 'subscribers.op_movements'.tr(),
            locked: _locked('subscribers.view_activity'),
            onTap: _locked('subscribers.view_activity')
                ? null
                : () => showMovementsSheet(context, sub),
          ),
        // «سجلّ الجلسات» — تقرير الجلسات مبحوثاً باسم دخوله (كلّ الجلسات):
        // SAS4 من UserSessions، وايرث لنك سجلّ هذا المشترك (usersession/user).
        if (_shows('reports.sessions'))
          SubAction(
            icon: LucideIcons.wifi,
            label: 'subscribers.op_sessions'.tr(),
            locked: _locked('reports.sessions'),
            onTap: _locked('reports.sessions')
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SessionsReportScreen(initialUsername: sub.username),
                      ),
                    ),
          ),
        if (_shows('reports.account_statement'))
          SubAction(
            icon: LucideIcons.fileText,
            label: 'subscribers.account_statement'.tr(),
            locked: _locked('reports.account_statement'),
            onTap: _locked('reports.account_statement')
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AccountStatementScreen(
                          username: sub.username,
                          // firstname/lastname غير قابلين للـnull في الموديل —
                          // نمرّر null فقط حين يكونان فارغين معاً.
                          displayName: sub.fullName.trim().isEmpty
                              ? null
                              : sub.fullName.trim(),
                          phone: sub.phone,
                        ),
                      ),
                    ),
          ),
        // 2026-08-26: يظهر إذا الموقع مُعيَّن (أيّ موظّف يفتحه بالخرائط)
        // أو الموظّف يملك صلاحيّة تعديله.
        // ٢٠٢٦-١٠-١٤: بلا موقعٍ ولا `subscribers.edit_location` يبقى صفّ
        // «إضافة موقع» مقفلاً. ١٨ أكتوبر: ولايرث لنك أيضاً — صار له مخزنٌ
        // محلّيّ على خادمنا، فالقفل بالصلاحيّة وحدها كباقي الشركات.
        if (sub.hasLocation ||
            canEditLocation() ||
            _locked('subscribers.edit_location'))
          SubAction(
            icon: LucideIcons.mapPin,
            label: sub.hasLocation
                ? 'subscribers.op_location'.tr()
                : 'subscribers.op_location_add'.tr(),
            locked: !sub.hasLocation && !canEditLocation(),
            onTap: !sub.hasLocation && !canEditLocation()
                ? null
                : () async {
                    if (!sub.hasLocation) {
                      await showLocationEditSheet(context, sub: sub);
                      return;
                    }
                    await showLocationSheet(context, sub: sub);
                  },
          ),
      ]),
      // «فصل المستخدم» صعد إلى البلاطات السريعة — ولا يتكرّر هنا،
      // كما لا يتكرّر التمديد والتعديل والتعطيل.
      SubActionGroup('subscribers.group_danger'.tr(), [
        // ايرث لنك لا تسمح بحذف المشترك (قرار المالك ١٩ أكتوبر): لا «حذف»
        // لمشتركيها أصلاً — فالمجموعة تفرغ ولا تُعرض. شركات SAS4 وFTTH: مقفلاً
        // بلا أحمر لمن لا يملك المفتاح (اللون للخطر الحيّ وحده)، ومخفيّاً لدورٍ
        // لا يُمنحه (`permShown`).
        if (!deleteHidden && _shows('subscribers.delete'))
          SubAction(
            icon: LucideIcons.trash2,
            label: 'common.delete'.tr(),
            color: _locked('subscribers.delete') ? null : AppColors.error,
            busy: _deleting,
            locked: _locked('subscribers.delete'),
            onTap: (sub.idx == null || _locked('subscribers.delete'))
                ? null
                : _confirmDelete,
          ),
      ]),
    ];
  }

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  /// ⚠️ **بلا `canLaunchUrl` على `tel:`** — انظر `_call`.
  ///
  /// الفحص يُرجع `false` على الآيفون لغياب `LSApplicationQueriesSchemes`،
  /// فتظهر «لا يمكن فتح الرابط» والهاتف قادر. وأمّا `https:` فالفحص
  /// عليه سليمٌ ويُبقى.
  Future<void> _launchUri(Uri uri) async {
    if (uri.scheme != 'tel') {
      final ok = await canLaunchUrl(uri);
      if (!mounted) return;
      if (!ok) {
        showSheetSnack(context, 'لا يمكن فتح الرابط', isError: true);
        return;
      }
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    showSheetSnack(context, 'لا يمكن فتح الرابط', isError: true);
  }
}

/// «نسخ كلّ المعلومات» — كلّ ما في كارت المشترك، سطر «التسمية: القيمة»
/// لكلّ معلومة، بالتسميات والصياغة نفسها التي ترسمها الكروت.
///
/// من الذاكرة وحدها، بلا أيّ جلب:
///   • [password] تُضمّ حين تظهر وحدها ([passwordVisible]) — من يرى النقاط
///     لا يتوقّع أن يلصق كلمة السرّ مع غيرها في محادثة.
///   • [deviceConfig] الإعداد الذي رُسم به كارت الاتّصال: عنوانه المثبَّت.
///   • [device] ما يرسمه كارت الجهاز: قراءته ووقتها وملاحظة المدير.
///
/// والترتيب ترتيب رسالة: المشترك والاشتراك أوّلاً، ثمّ الاتّصال والجهاز،
/// ثمّ الموقع. وما لا قيمة له لا يظهر سطراً فارغاً.
///
/// ⚠️ تسميات الحقول المشتركة وصياغة المال وترتيبها هي نفسها في الموقع
/// (`client-v2/src/lib/subscriber-info.ts`): السعر بعد الخصم، والرصيد
/// بحالاته الثلاث، و«تابع إلى»، و«IP الجلسة». من يغيّر هنا يغيّر هناك.
@visibleForTesting
List<CopyField> subscriberCopyFields(
  Subscriber sub, {
  String? password,
  bool passwordVisible = false,
  DeviceConfig? deviceConfig,
  DeviceCardShown? device,
  DateTime? now,
}) {
  final last = sub.isOnline ? null : parseSasLocal(sub.lastOnline);
  final notes = device?.notes?.trim() ?? '';
  final snap = device?.snap;
  return [
    ..._SubscriberHero.copyFields(
      sub,
      password: password,
      passwordVisible: passwordVisible,
      now: now,
    ),
    ..._LiveSessionCard.copyFields(
      sub,
      pinned: _LiveSessionCard.pinnedIp(sub, deviceConfig),
    ),
    // وقت آخر اتّصالٍ مطلقاً لا «قبل ساعتين»: النصّ المنسوخ يُقرأ لاحقاً.
    if (last != null)
      CopyField('آخر اتصال', _SubscriberHero._dateTimeText(last),
          noun: 'وقت آخر اتصال'),
    if (snap != null) ...deviceCopyFields(snap, at: device?.at),
    if (notes.isNotEmpty) deviceNoteField(notes),
    if (sub.hasLocation)
      CopyField(
        'الموقع',
        '${sub.latitude!.toStringAsFixed(6)},'
            '${sub.longitude!.toStringAsFixed(6)}',
        noun: 'الإحداثيّات',
      ),
    if (sub.hasManualAddressText) CopyField('العنوان', sub.addressRaw!.trim()),
  ];
}

/// كارت «معلومات الاتصال» — كارت أبيض r20 بحدّ 1px وبلا ظلّ، رأسه
/// أيقونة 18 بلون الـaccent + عنوان 14/w600 وحبّة «متصل منذ …» في
/// الطرف، وجسمه ثلاث بلاطات غاطسة (#F7F8F5 / r14): تحميل · رفع · IP.
class _LiveSessionCard extends StatelessWidget {
  const _LiveSessionCard({required this.sub, this.onDrawn});
  final Subscriber sub;

  /// يُبلَّغ في كلّ بناءٍ بالإعداد الذي رُسم به الكرت — فينسخ «نسخ كلّ
  /// المعلومات» العنوانَ المثبَّت الذي على الشاشة. (جلبٌ فاشلٌ بعد انقضاء
  /// مخزن الإعداد يرسم الثابت وحده ويُبقي في المخزن القديم.)
  final ValueChanged<DeviceConfig?>? onDrawn;

  /// العنوان المثبَّت: إعداد الجهاز أوّلاً، ثمّ الثابت المحجوز في الساس.
  static String pinnedIp(Subscriber sub, DeviceConfig? config) {
    final custom = config?.customIp?.trim() ?? '';
    return custom.isNotEmpty ? custom : (sub.staticIp?.trim() ?? '');
  }

  /// جلسةٌ قائمة تستحقّ أرقامها — لا «متّصل» بلا أيّ أثر.
  static bool hasSession(Subscriber sub) =>
      sub.isOnline &&
      ((sub.ipAddress ?? '').isNotEmpty ||
          (sub.sessionTime ?? 0) > 0 ||
          (sub.downloadBytes ?? 0) > 0 ||
          (sub.uploadBytes ?? 0) > 0);

  /// ما يرسمه الكرت بتسمياته — للنسخ المفرد والكلّيّ معاً.
  static List<CopyField> copyFields(Subscriber sub, {required String pinned}) {
    final live = hasSession(sub);
    final ip = sub.ipAddress?.trim() ?? '';
    final secs = live ? (sub.sessionTime ?? 0) : 0;
    return [
      if (secs > 0) _durationField(secs),
      if (live) ...[
        _downloadField(sub),
        _uploadField(sub),
        if (ip.isNotEmpty) _sessionIpField(ip),
      ],
      if (pinned.isNotEmpty) _pinnedIpField(pinned),
    ];
  }

  static CopyField _sessionIpField(String ip) => CopyField('IP الجلسة', ip);

  static CopyField _pinnedIpField(String ip) => CopyField('IP المثبَّت', ip);

  static CopyField _durationField(int secs) => CopyField(
        'subscribers.label_session_time'.tr(),
        _formatDuration(secs),
        noun: 'مدّة الاتصال',
      );

  static CopyField _downloadField(Subscriber sub) => CopyField(
        'subscribers.label_download'.tr(),
        _formatBytes(sub.downloadBytes ?? 0),
        noun: 'التحميل',
      );

  static CopyField _uploadField(Subscriber sub) => CopyField(
        'subscribers.label_upload'.tr(),
        _formatBytes(sub.uploadBytes ?? 0),
        noun: 'الرفع',
      );

  @override
  Widget build(BuildContext context) {
    // النبضة تُعيد القراءة بعد حفظ شيت الإعدادات (الحفظ يُبطل الكاش)،
    // فلا يبقى عنوانٌ قديم معروضاً بعد تغييره.
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (_, __, ___) => FutureBuilder<DeviceConfig?>(
        future: DeviceConfigApi.fetchConfig(sub.username,
            company: sub.companyKey),
        builder: (context, snap) {
          // ما يُرسم الآن بالضبط (أثناء جلبٍ جديد يبقى السابق مرسوماً).
          // تسجيلٌ في حقلٍ لا `setState` — لا يُعاد بناء شيء.
          onDrawn?.call(snap.data);
          final pinned = pinnedIp(sub, snap.data);
          final hasSession = _LiveSessionCard.hasSession(sub);
          // لا جلسةَ ولا عنوانَ مثبَّت ⇒ لا كرت. (كارتٌ فارغ يوحي
          // بقيمةٍ تعذّر جلبها، وهو أسوأ من غيابه.)
          if (!hasSession && pinned.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: _body(context, hasSession: hasSession, pinned: pinned),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context,
      {required bool hasSession, required String pinned}) {
    Theme.of(context); // theme-dep (dark-mode)
    final ip = sub.ipAddress ?? '';
    final secs = hasSession ? (sub.sessionTime ?? 0) : 0;
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
              Text(
                  hasSession
                      ? 'subscribers.section_connection'.tr()
                      : 'عنوان الجهاز',
                  style: AppType.cardTitle()),
              const SizedBox(width: Sp.sm),
              if (secs > 0)
                Expanded(
                    child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Copyable.field(
                          _durationField(secs),
                          radius: R.pill,
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
          // التحميل والرفع بيانات جلسة — لا معنى لهما لمفصولٍ نعرض
          // له عنوانه المثبَّت وحده.
          if (hasSession)
            Row(
              children: [
                Expanded(
                  child: _SunkenTile(
                    icon: Icons.south_rounded,
                    field: _downloadField(sub),
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _SunkenTile(
                    icon: Icons.north_rounded,
                    field: _uploadField(sub),
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
          // العنوانان صفّان كاملان لا نصفان: النصف على شاشة ٣٢٠ يترك
          // ٩٥ نقطة للنصّ و«192.168.100.254» يحتاج ١١٤ — فيُقصّ رقم
          // المضيف، وهو المميِّز الوحيد بين جهازٍ وآخر.
          ..._ipRow(hasSession: hasSession, ip: ip, pinned: pinned),
        ],
      ),
    );
  }

  /// العنوانان في **صفٍّ واحد عمودين** حين يتوفّران معاً، وعمودٌ
  /// كامل حين ينفرد أحدهما: عنوان الجلسة للمتّصل، والمثبَّت للمفصول.
  ///
  /// والقيمة تُصغَّر بـ`FittedBox` لا تُقصّ: النصف على شاشة ٣٢٠ يترك
  /// ~١١٥ نقطة و«192.168.100.254» يحتاج ~١١٤ — على الحافّة تماماً.
  /// والقصّ هنا يأكل رقم المضيف وهو المميِّز الوحيد بين جهازٍ وآخر،
  /// فالتصغير اليسير أهون من عنوانٍ ناقص.
  List<Widget> _ipRow({
    required bool hasSession,
    required String ip,
    required String pinned,
  }) {
    final tiles = <Widget>[
      // النقر يفتح الجهاز، والضغط المطوّل ينسخ العنوان — لا يتزاحمان.
      if (hasSession && ip.isNotEmpty)
        _SunkenTile(
          icon: Icons.open_in_new_rounded,
          field: _sessionIpField(ip),
          color: AppColors.textHi,
          shrinkValue: true,
          onTap: () => launchUrl(Uri.parse('http://$ip'),
              mode: LaunchMode.externalApplication),
        ),
      if (pinned.isNotEmpty)
        _SunkenTile(
          icon: Icons.push_pin_rounded,
          field: _pinnedIpField(pinned),
          color: AppColors.info,
          shrinkValue: true,
          onTap: () => launchUrl(Uri.parse('http://$pinned'),
              mode: LaunchMode.externalApplication),
        ),
    ];
    if (tiles.isEmpty) return const [];
    return [
      SizedBox(height: hasSession ? 9 : 0),
      if (tiles.length == 2)
        // `IntrinsicHeight` يسوّي ارتفاع العمودين؛ بدونه يتفاوتان لو
        // التفّ عنوانٌ دون الآخر.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 9),
              Expanded(child: tiles[1]),
            ],
          ),
        )
      else
        tiles.first,
    ];
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
/// تسميتها وقيمتها من [field] نفسه الذي يُنسخ، فالضغط المطوّل ينسخ ما يُرى.
class _SunkenTile extends StatelessWidget {
  const _SunkenTile({
    required this.icon,
    required this.field,
    required this.color,
    this.onTap,
    this.shrinkValue = false,
  });
  final IconData icon;
  final CopyField field;
  final Color color;
  final VoidCallback? onTap;

  /// يُصغّر القيمة لتتّسع بدل أن تُقصّ — للأعمدة الضيّقة.
  final bool shrinkValue;

  String get label => field.label;
  String get value => field.value;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          Builder(builder: (_) {
            final text = Text(
              value,
              textDirection: ui.TextDirection.ltr,
              style: AppType.cardTitle(color: color)
                  .copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
            if (!shrinkValue) return text;
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: text,
            );
          }),
        ],
      ),
    );
    // 🐛 كانت الخلفيّة على `Container` **داخل** الـInkWell، فتغطّي أثر
    // النقر فتبدو البلاطة ميّتة — والمستخدم يظنّ أنّ الأيقونة وحدها
    // هي الزرّ. الآن اللون على `Material` والـInkWell فوقه، فالموجة
    // تظهر على كامل المساحة وهي مساحة النقر نفسها.
    return Copyable.field(
      field,
      radius: R.icon,
      child: Material(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? body
            : InkWell(
                onTap: onTap,
                child: body,
              ),
      ),
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
///
/// والمساحة المكافئة يساراً صارت زرّ «نسخ كلّ المعلومات» بمقاس زرّ الرجوع
/// نفسه — فيبقى العنوان متمركزاً ولا يُضاف شريطٌ ولا صفّ.
class _SimpleAppBar extends StatelessWidget {
  const _SimpleAppBar({
    required this.title,
    required this.onClose,
    required this.onCopyAll,
    required this.onPrint,
    this.printing = false,
  });
  final String title;
  final VoidCallback onClose;
  final VoidCallback onCopyAll;

  /// «طباعة وصل» — بجانب النسخ، بمقاس زرّ الرجوع نفسه.
  final VoidCallback onPrint;
  final bool printing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.x6, Sp.lg, Sp.x6),
      color: AppColors.bg,
      child: Row(
        children: [
          _button(icon: LucideIcons.arrowRight, size: 20, onTap: onClose),
          // يقابل زرّ الطباعة يساراً فيبقى العنوان في الوسط.
          const SizedBox(width: H.iconBtn + Sp.sm),
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
          _button(
            icon: printing ? LucideIcons.loaderCircle : LucideIcons.printer,
            size: 18,
            onTap: printing ? () {} : onPrint,
            tooltip: 'printer.receipt'.tr(),
          ),
          const SizedBox(width: Sp.sm),
          _button(
            icon: LucideIcons.copy,
            size: 18,
            onTap: onCopyAll,
            tooltip: 'copy.all'.tr(),
          ),
        ],
      ),
    );
  }

  /// زرّ أيقونيّ 38×38 أبيض بحدّ و r14 — زرّ الرجوع وزرّ النسخ بشكلٍ واحد.
  Widget _button({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.icon),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.icon),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.icon),
            border: Border.all(color: AppColors.borderSoft),
          ),
          width: H.iconBtn,
          height: H.iconBtn,
          child: Icon(icon, size: size, color: AppColors.textBody),
        ),
      ),
    );
    // التلميح اسمُ الأيقونة: ضغطةٌ مطوّلة تقول ما يفعله الزرّ، وقارئ
    // الشاشة يقرؤه بدل «زرّ» مجرّد.
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
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
  const _SubscriberHero({
    required this.sub,
    this.password,
    required this.passwordVisible,
    required this.onTogglePassword,
  });
  final Subscriber sub;

  /// null = لم تصل بعد من الـbackend. الباسورد **بلا بوّابة صلاحيّات**
  /// (قرار 2026-08-25): هو بيانات خدمة يحتاجها الدعم لمساعدة المشترك.
  final String? password;

  /// العين مفتوحة — حالتها عند الشاشة لا هنا (انظر `_passwordVisible`).
  final bool passwordVisible;
  final VoidCallback onTogglePassword;

  // ───────── المعلومات كما تُنسخ ─────────
  //
  // كلّ معلومةٍ في البطاقة `CopyField` واحد: منه تُرسم تسميتها، ومنه
  // يُنسخ بالضغط المطوّل، ومنه يُبنى «نسخ كلّ المعلومات» — فلا تختلف
  // تسميةٌ ولا قيمةٌ بين ما يُرى وما يُلصق.

  /// معلومات البطاقة بترتيب قراءتها في رسالة لا بترتيب رسمها: الاسم
  /// وبيانات الدخول أوّلاً، ثمّ الاشتراك، ثمّ المال والحالة.
  static List<CopyField> copyFields(
    Subscriber sub, {
    String? password,
    bool passwordVisible = false,
    DateTime? now,
  }) {
    final name = _nameField(sub);
    final phone = sub.displayPhone;
    final price = _salePriceField(sub);
    final exp = sub.parsedExpiration;
    final parent = sub.parentUsername?.trim() ?? '';
    return [
      // بلا اسمٍ يُعرض المشترك باسم مستخدمه، وتكراره سطرين لا يُفيد.
      if (name.value.trim() != sub.username.trim()) name,
      _usernameField(sub),
      if (passwordVisible && (password ?? '').isNotEmpty)
        _passwordField(password!),
      if (phone.isNotEmpty) _phoneField(phone),
      _packageField(sub),
      if (price != null) price,
      if (exp != null) _expiryField(exp),
      _remainingField(_remaining(sub, now: now)),
      _balanceField(sub),
      _statusField(sub),
      if (parent.isNotEmpty) _parentField(parent),
    ];
  }

  static CopyField _nameField(Subscriber sub) =>
      CopyField('الاسم', normalizeDigits(sub.fullName) ?? sub.username);

  static CopyField _statusField(Subscriber sub) =>
      CopyField('الحالة', _statusPill(sub).$1);

  static CopyField _usernameField(Subscriber sub) =>
      CopyField('اسم المستخدم', sub.username);

  static CopyField _passwordField(String password) =>
      CopyField('كلمة المرور', password);

  /// الرقم **المحلّي** (‏07…) كما يُتّصل به — لا ‎9647… كما يخزّنه الساس.
  static CopyField _phoneField(String phone) =>
      CopyField('الهاتف', localPhone(phone), noun: 'الرقم');

  static CopyField _packageField(Subscriber sub) =>
      CopyField('الباقة', sub.profileName ?? '—', noun: 'اسم الباقة');

  /// «السعر» في نسخ الكلّ — ما يدفعه المشترك فعلاً لا سعر الباقة قبل خصمه:
  /// سعر البيع الحاليّ ([Subscriber.currentSalePrice] — الثابت إن سرى، وإلّا
  /// سعر الباقة ناقص خصمه)، ومعه «بعد خصم …» حين ينزل به خصمه.
  ///
  /// 🐛 كان سعر الباقة نفسه («25,000» لمن خصمه 5,000)، والمدير يلصق النصّ
  /// للمشترك في واتساب — فيقرأ سعراً غير الذي يدفعه، والموقع ينسخ للمشترك
  /// نفسه «20,000 د.ع بعد خصم 5,000». الصيغة هنا هي صيغة الموقع حرفاً بحرف
  /// (`subscriberPrice` في `client-v2/src/lib/subscriber-info.ts`).
  ///
  /// `null` حين لا يُعرف سعر الباقة (أو صفر) — كما يُخفيه الهيرو.
  static CopyField? _salePriceField(Subscriber sub) {
    final base = sub.price;
    if (base == null || base <= 0) return null;
    final sale = sub.currentSalePrice ?? base;
    final discount = sub.discount ?? 0;
    // الثابت الساري يُلغي الخصم (الخادم يرسله صفراً معه أصلاً).
    final discounted =
        discount > 0 && !(sub.isFixedPrice && !sub.needsRepricing);
    return CopyField(
      'السعر',
      discounted
          ? '${formatIQD(sale)} د.ع بعد خصم ${formatIQD(discount)}'
          : '${formatIQD(sale)} د.ع',
    );
  }

  /// الرقم الذي في تسمية بلاطة الباقة («الباقة · 25,000») — سعر الباقة قبل
  /// خصم المشترك. ضغطُها المطوّل ينسخه هو باسمه، فلا يُسمّى «السعر» وهو
  /// غير سعر «نسخ كلّ المعلومات» لمن عليه خصم.
  static CopyField _packagePriceField(num price) =>
      CopyField('سعر الباقة', '${formatIQD(price)} د.ع');

  /// ⚠️ ثلاث حالات لا اثنتان: من رصيده صفر لا دين عليه، ووسمُه بـ«الدين»
  /// يجعل الشاشة تتّهمه بما ليس فيه. والتسمية نفسها تحت رقم البلاطة.
  static CopyField _balanceField(Subscriber sub) {
    final debt = sub.balanceAmount;
    return CopyField(
      debt > 0
          ? 'رصيد دائن'
          : debt < 0
              ? 'الدين'
              : 'الرصيد',
      debt == 0 ? 'لا دين ولا رصيد' : '${formatIQD(debt.abs())} د.ع',
      noun: debt > 0 ? 'الرصيد الدائن' : null,
    );
  }

  static CopyField _remainingField(_Remaining r) =>
      CopyField('المتبقي', r.text, noun: 'المدّة المتبقية');

  static CopyField _parentField(String parent) =>
      CopyField('تابع إلى', parent, noun: 'اسم المدير');

  static CopyField _expiryField(DateTime exp) =>
      CopyField('تاريخ الانتهاء', _dateTimeText(exp));

  /// ‏`2026/10/15 10:00` — صيغة التذييل نفسها.
  static String _dateTimeText(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}/${two(t.month)}/${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

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
    final st = _statusPill(sub);
    final name = _nameField(sub);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Copyable.field(
                name,
                onBrandSurface: true,
                child: Text(
                  name.value,
                  style: AppType.heroName(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
        Copyable.field(
          _statusField(sub),
          onBrandSurface: true,
          radius: R.pill,
          child: Container(
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
                  decoration:
                      BoxDecoration(color: st.$2, shape: BoxShape.circle),
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
        ),
      ],
    );
  }

  /// (التسمية، لون النقطة). الحالة تُقرأ من هنا بدل تلوين البطاقة كلّها.
  static (String, Color) _statusPill(Subscriber sub) {
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
            child: Copyable.field(
              _usernameField(sub),
              onBrandSurface: true,
              child: Text(
                sub.username,
                textDirection: ui.TextDirection.ltr,
                style: AppType.body(color: AppColors.onBrand)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _OnBrandIcon(
            icon: Icons.content_copy_rounded,
            size: 16,
            onTap: () =>
                copyToClipboard(context, sub.username, label: 'اسم المستخدم'),
          ),
          // Pro: عرض كلمة المرور مُسيَّجٌ بصلاحيّة الساس — أغلب الشركات لا
          // تسمح به. show_password=false → يختفي الفاصل والباسورد معاً.
          if (Perms.has('subscribers.show_password')) ...[
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
              Expanded(
                flex: 2,
                child: _HeroPassword(
                  password: pass,
                  visible: passwordVisible,
                  onToggle: onTogglePassword,
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ───────── شبكة الإحصاءات الثلاثيّة ─────────

  Widget _statsGrid() {
    final debt = sub.balanceAmount;
    final price = sub.price;
    final balance = _balanceField(sub);
    final remaining = _remaining(sub);
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
              copy: balance,
              value: debt == 0 ? '—' : formatIQD(debt.abs()),
              label: balance.label,
              color: debt < 0 ? AppColors.onBrandDanger : AppColors.onBrand,
            ),
          ),
          _divider(),
          Expanded(
            child: _stat(
              copy: _packageField(sub),
              // السعر في تسمية البلاطة — فضغطها المطوّل ينسخه هو لا الباقة.
              labelCopy:
                  price != null && price > 0 ? _packagePriceField(price) : null,
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
              copy: _remainingField(remaining),
              value: remaining.big,
              label: remaining.small,
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

  /// [copy] ما ينسخه الضغط المطوّل على البلاطة، و[labelCopy] ما تنسخه
  /// تسميتها حين تحمل معلومةً غيرها (سعر الباقة).
  Widget _stat({
    required CopyField copy,
    required String value,
    required String label,
    CopyField? labelCopy,
    Color? color,
    double valueSize = 17,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // `stretch` لا التوسيط: هدفُ الضغط المطوّل عرضُ العمود كلّه لا حروف
      // الرقم وحدها. والتوسيط باقٍ كما هو — `FittedBox` يتوسّط افتراضاً،
      // والتسمية بـ`textAlign`.
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        Copyable.field(
          copy,
          onBrandSurface: true,
          child: FittedBox(
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
        ),
        const SizedBox(height: 3),
        Copyable.field(
          labelCopy ?? copy,
          onBrandSurface: true,
          child: Text(
            label,
            style: AppType.muted(color: AppColors.onBrandSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// المتبقّي: الرقم الكبير والتسمية تحته في البلاطة، ونصّه سطراً واحداً
  /// للنسخ. محسوبٌ من `parsedExpiration` — لا من `remainingDays` (SAS4
  /// يقرّب لأعلى فيعطي 31 لباقة 30).
  static _Remaining _remaining(Subscriber sub, {DateTime? now}) {
    final exp = sub.parsedExpiration;
    if (exp == null) return (big: '—', small: 'الأيام المتبقية', text: '—');
    final diff = exp.difference(now ?? DateTime.now());
    if (diff.isNegative) return (big: '0', small: 'منتهي', text: 'منتهي');
    final d = diff.inDays;
    final h = diff.inHours.remainder(24);
    final m = diff.inMinutes.remainder(60);
    if (d > 0) {
      return (big: '$d يوم', small: '$hس $mد', text: '$d يوم $hس $mد');
    }
    if (h > 0) return (big: '$hس', small: '$mد', text: '$hس $mد');
    return (big: '$mد', small: 'أقل من ساعة', text: '$mد');
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
          // 🐛 كانت `Icon` صامتةً بلا `onTap`: تبدو زرّاً ولا تفعل شيئاً.
          // (طلب المستخدم ٢٠٢٦-١٠-٠٥: «هذا الزرّ مفروض يتفعّل الاتصال»)
          _OnBrandIcon(
            icon: Icons.call_rounded,
            size: 17,
            onTap: () => _call(context, phone),
          ),
          const SizedBox(width: 10),
          Expanded(
            // النقر يتّصل والضغط المطوّل ينسخ — لا يتزاحمان.
            child: Copyable.field(
              _phoneField(phone),
              onBrandSurface: true,
              child: InkWell(
                onTap: () => _call(context, phone),
                child: Text(
                  phone,
                  textDirection: ui.TextDirection.ltr,
                  // ثلاث أيقوناتٍ تجاوره الآن (الاتصال والنسخ والواتساب)،
                  // فالنصّ بلا هذين يُسحق صامتاً على شاشةٍ ضيّقة.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: AppColors.onBrand)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          _OnBrandIcon(
            icon: Icons.content_copy_rounded,
            size: 16,
            onTap: () =>
                copyToClipboard(context, localPhone(phone), label: 'الرقم'),
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
    final parent = sub.parentUsername?.trim();
    final exp = sub.parsedExpiration;
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
            child: Copyable.field(
              _parentField(parent),
              onBrandSurface: true,
              child: Text(
                'تابع إلى $parent',
                style: AppType.muted(color: AppColors.onBrandSecondary)
                    .copyWith(fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
        ] else
          const Spacer(),
        if (exp != null)
          Copyable.field(
            _expiryField(exp),
            onBrandSurface: true,
            child: Text(
              _dateTimeText(exp),
              textDirection: ui.TextDirection.ltr,
              style: AppType.muted(color: AppColors.onBrandSecondary)
                  .copyWith(fontSize: 11.5),
            ),
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

  /// اتّصالٌ بالرقم **المحلّي** — ‏`07…` لا `9647…`.
  ///
  /// ⚠️ **بلا `canLaunchUrl`.**
  ///
  /// 🐛 `ios/Runner/Info.plist` لا يحمل `LSApplicationQueriesSchemes`،
  /// فقد يُرجع الفحص `false` لـ`tel:` على الآيفون والهاتف قادرٌ على
  /// الاتصال — فتظهر «لا يمكن فتح الرابط» كذباً. نُنادي الفتح مباشرةً
  /// ونُبلّغ عن فشله هو، لا عن فشل فحصٍ سابقٍ له.
  /// (`docs/subscriber-phone-call-prompt.md` §٢ و§٤-٧)
  static Future<void> _call(BuildContext ctx, String phone) async {
    final n = localPhone(phone);
    if (n.isEmpty) return;
    var ok = false;
    try {
      ok = await launchUrl(
        Uri.parse('tel:$n'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (ok || !ctx.mounted) return;
    showSheetSnack(ctx, 'لا يمكن فتح الرابط', isError: true);
  }
}

/// المتبقّي بأجزائه: [big] رقم البلاطة، [small] تسميتها، [text] سطره.
typedef _Remaining = ({String big, String small, String text});

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
///
/// الإظهار عند الشاشة ([visible] + [onToggle]) لا هنا: «نسخ كلّ المعلومات»
/// يضمّ كلمة السرّ حين تظهر وحدها، فيحتاج أن يعرف حالها.
class _HeroPassword extends StatelessWidget {
  const _HeroPassword({
    required this.password,
    required this.visible,
    required this.onToggle,
  });
  final String password;
  final bool visible;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final shown = visible ? password : '•' * password.length.clamp(4, 12);
    return Row(
      children: [
        Flexible(
          // الضغط المطوّل كأيقونة النسخ: ينسخها مخفيّةً أيضاً — من يملك
          // مفتاح عرضها يملك نسخها، والإشعار لا يكشفها.
          child: Copyable.field(
            _SubscriberHero._passwordField(password),
            onBrandSurface: true,
            child: Text(
              shown,
              textDirection: ui.TextDirection.ltr,
              style: visible
                  ? AppType.body(color: AppColors.onBrandStrong)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600)
                  : AppType.password(color: AppColors.onBrandStrong),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _OnBrandIcon(
          icon: visible
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          size: 17,
          onTap: onToggle,
        ),
        const SizedBox(width: 10),
        _OnBrandIcon(
          icon: Icons.content_copy_rounded,
          size: 17,
          onTap: () =>
              copyToClipboard(context, password, label: 'كلمة المرور'),
        ),
      ],
    );
  }
}
