import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/portal_settings_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/server_time.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../services/permissions_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// تطبيق المشترك كما يجده في المتجر — المصدر الوحيد لنصّ «مشاركة».
abstract final class SubscriberApp {
  /// اسمه على هاتف المشترك (2.0.7: «MyServices»، وكان «MySub»).
  static const name = 'MyServices';

  /// Play — الحزمة `com.myservices.mysub` نفسها؛ 2.0.7 يحمل الاسم الجديد عليها.
  static const androidUrl =
      'https://play.google.com/store/apps/details?id=com.myservices.mysub';

  /// App Store — **لا رابط بعد**: 2.0.7 بانتظار مراجعة أبل (رُفض قبله
  /// بـ5.2.1). يُملأ هنا متى قُبل؛ وإلى ذلك يقول سطر الآيفون «ابحث عن
  /// MyServices في App Store» (بديلٌ لا رابطٌ ميّت) — كنصّ الويب حرفيّاً
  /// (`SUBSCRIBER_APP_LINKS` في client-v2 `components/portal/agent-portal.ts`).
  static const String? iosUrl = null;
}

/// نصّ «مشاركة» الجاهز — ما يصل المشترك حرفيّاً (واتساب، رسالة…).
///
/// بالعربيّة دائماً كنصّ رمز QR: يُرسَل لمشتركين لا لواجهة المدير. ومطابقٌ
/// حرفيّاً لنصّ الويب (`agentShareText`) — المشترك يصله النصّ نفسه أيّاً كان
/// مصدره: سطرٌ لكلّ متجر، برابطه إن عُرف وإلّا «ابحث عن MyServices في …».
String agentCodeShareText(
  String code, {
  String? androidUrl = SubscriberApp.androidUrl,
  String? iosUrl = SubscriberApp.iosUrl,
}) {
  String link(String? url, String store) => url != null && url.isNotEmpty
      ? url
      : 'ابحث عن ${SubscriberApp.name} في $store';
  final head = 'حمّل تطبيق ${SubscriberApp.name} وادخل برمز الوكيل: $code '
      'واسم المستخدم وكلمة المرور';
  return '$head\n\n'
      'أندرويد: ${link(androidUrl, 'Google Play')}\n'
      'آيفون: ${link(iosUrl, 'App Store')}';
}

/// متى حاول المشترك — «منذ ٥ دقيقة» لليوم، وإلّا «17/10 21:05».
String portalLoginWhen(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  final n = now ?? DateTime.now();
  if (n.difference(at).inHours < 24) return timeAgoAr(at, now: n);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
}

/// تبويب «رمز الوكيل» في «بوابة المشترك» — لكلّ فاعلٍ ولكلّ المزوّدين.
///
/// ── ما فيه ──────────────────────────────────────────────────────────
/// • بطاقة الرمز: ستّة أرقام كبيرة، «نسخ» و«مشاركة» (نصٌّ جاهز للمشترك)،
///   و«تغيير الرمز» لصاحب الحساب وحده (الخادم يردّ الموظّف ٤٠٣ OWNER_ONLY).
/// • تلميح المتغيّر [kAgentCodeVariable] لرسائل الواتساب.
/// • مفتاح «تفعيل بوابة مشتركيّ» (مفتوحةٌ افتراضاً) — `settings.edit`.
/// • «آخر دخول المشتركين» (آخر ٢٠) — `subscribers.view`.
///
/// ── الموظّف (المقفل لا المخفيّ) ─────────────────────────────────────
/// يرى الرمز وينسخه ويشاركه (الخادم يعطيه بلا صلاحيّة: رمز مديره)، ولا يرى
/// «تغيير الرمز» (لصاحب الحساب وحده ⇒ مخفيّ). والمفتاح والسجلّ بمكانهما
/// مقفلَين بلا صلاحيّتهما — ولا يُطلب السجلّ أصلاً. موظّف ايرث لنك لا يُمنح
/// `settings.edit` أبداً، فيقول قفله «لصاحب الحساب» لا «اطلبها من مديرك».
class AgentCodeTab extends StatefulWidget {
  const AgentCodeTab({super.key});

  /// منفذ «مشاركة» — ورقة النظام افتراضاً، ويُستبدل في الاختبار (لا قناة
  /// منصّة في `flutter test`). [origin] لآيباد: بدونه ترمي ورقة المشاركة.
  @visibleForTesting
  static Future<void> Function(String text, Rect origin) shareText =
      _systemShare;

  static Future<void> _systemShare(String text, Rect origin) =>
      // ignore: deprecated_member_use
      Share.share(text, sharePositionOrigin: origin);

  @override
  State<AgentCodeTab> createState() => _AgentCodeTabState();
}

class _AgentCodeTabState extends State<AgentCodeTab> {
  PortalAccess? _access;
  bool _loading = true;
  bool _savingSwitch = false;
  bool _rotating = false;

  /// ورقة تأكيدٍ مفتوحة — فنقرتان سريعتان لا تفتحان ورقتين.
  bool _asking = false;

  List<PortalLogin>? _logins;
  bool _loginsLoading = false;

  /// ٤٠٣ على السجلّ: صلاحيّةٌ سُحبت ولم تتحدّث صلاحيّات الجهاز بعد — يُقفل
  /// القسم بمكانه كمن لا يملكها، لا «تعذّر التحميل» لصلاحيّةٍ ناقصة.
  bool _loginsDenied = false;

  /// الصلاحيّات تُقرأ مرّة عند الفتح — كبقيّة الشاشات المدفوعة.
  late final bool _isOwner = !Perms.isEmployee;
  late final bool _canToggle = Perms.has('settings.edit');
  late final bool _canSeeLogins = Perms.has('subscribers.view');

  /// تلميح المتغيّر لمن يحرّر القوالب وحده (المالك، أو موظّفٌ بإدارة القوالب)
  /// — كالويب (`portalCaps.templatesHint`): لا يُقال لموظّفٍ «تقدر تضيف»
  /// ما لا يقدر عليه (وموظّف ايرث لنك لا يُمنح القوالب أصلاً).
  late final bool _showVarHint = _isOwner || Perms.has('whatsapp.templates');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logins = _canSeeLogins && !_loginsDenied;
    setState(() {
      _loading = _access == null;
      if (logins) _loginsLoading = _logins == null;
    });
    await Future.wait([
      _loadAccess(),
      if (logins) _loadLogins(),
    ]);
  }

  Future<void> _loadAccess() async {
    final a = await PortalSettingsApi.getAccess();
    if (!mounted) return;
    setState(() {
      // سحبٌ للتحديث فشل: يبقى آخر ما عُرف بدل أن تختفي البطاقة.
      if (a != null || _access == null) _access = a;
      _loading = false;
    });
  }

  Future<void> _loadLogins() async {
    final r = await PortalSettingsApi.getLogins(limit: 20);
    if (!mounted) return;
    setState(() {
      if (r.denied) {
        _loginsDenied = true;
        _logins = null;
      } else if (r.rows != null || _logins == null) {
        _logins = r.rows;
      }
      _loginsLoading = false;
    });
  }

  Future<void> _retryAccess() async {
    setState(() => _loading = true);
    await _loadAccess();
  }

  Future<void> _retryLogins() async {
    setState(() => _loginsLoading = true);
    await _loadLogins();
  }

  // ─── الإجراءات ───

  /// نسخٌ + اهتزازة + إشعار — رسالته مترجمة كاملةً (`copyToClipboard` العامّ
  /// يلصق «تمّ نسخ» العربيّة بتسميةٍ قد تكون إنجليزيّة).
  Future<void> _copy(String text, String done) async {
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack(done);
  }

  Future<void> _share(BuildContext from, String code) async {
    HapticFeedback.selectionClick();
    Rect origin = Rect.zero;
    final box = from.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await AgentCodeTab.shareText(agentCodeShareText(code), origin);
    } catch (e) {
      if (kDebugMode) debugPrint('[AgentCodeTab] share: $e');
      if (!mounted) return;
      _snack('portal.agent_share_failed'.tr(), error: true);
    }
  }

  Future<void> _rotate() async {
    if (_rotating) return;
    final ok = await _confirm(
      title: 'portal.agent_rotate_title'.tr(),
      message: 'portal.agent_rotate_body'.tr(),
      confirmLabel: 'portal.agent_rotate_confirm'.tr(),
      icon: LucideIcons.refreshCw,
    );
    if (!ok || !mounted) return;
    setState(() => _rotating = true);
    final r = await PortalSettingsApi.rotateAgentCode();
    if (!mounted) return;
    setState(() {
      _rotating = false;
      if (r.code != null) _access = _access?.copyWith(agentCode: r.code);
    });
    if (r.code != null) {
      _snack('portal.agent_rotated'.tr());
    } else {
      _snack(r.message ?? 'portal.agent_rotate_failed'.tr(), error: true);
    }
  }

  Future<void> _setEnabled(bool next) async {
    final cur = _access;
    if (cur == null || _savingSwitch || next == cur.enabled) return;
    if (!next) {
      // الإيقاف يُغلق الباب على كلّ المشتركين دفعةً — يُسأل قبله.
      final ok = await _confirm(
        title: 'portal.switch_off_title'.tr(),
        message: 'portal.switch_off_body'.tr(),
        confirmLabel: 'portal.switch_off_confirm'.tr(),
        icon: LucideIcons.powerOff,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _savingSwitch = true;
      _access = cur.copyWith(enabled: next); // متفائل — ويُعاد عند الرفض
    });
    final r = await PortalSettingsApi.setPortalEnabled(next);
    if (!mounted) return;
    setState(() {
      _savingSwitch = false;
      _access = (_access ?? cur).copyWith(
        enabled: r.ok ? (r.enabled ?? next) : cur.enabled,
      );
    });
    if (r.denied) {
      showNoPermission(context, action: true);
    } else if (!r.ok) {
      _snack(r.message ?? 'portal.switch_failed'.tr(), error: true);
    }
  }

  /// تأكيدٌ بنغمة التحذير (لا الحذف: لا رجعة لكن لا شيء يُمحى). `false`
  /// لورقةٍ مفتوحةٍ أصلاً أو لإلغاء.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
  }) async {
    if (_asking) return false;
    _asking = true;
    try {
      final ok = await showConfirmSheet(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        icon: icon,
        tone: AppTone.warning,
      );
      return ok == true;
    } finally {
      _asking = false;
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.errorFill : AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ─── الرسم ───

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = _access;
    final code = a?.agentCode;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            Sp.lg, Sp.lg, Sp.lg, Inset.route(context) + Sp.lg),
        children: [
          _AgentCodeCard(
            loading: _loading,
            access: a,
            showRotate: _isOwner,
            rotating: _rotating,
            onRetry: _retryAccess,
            onCopy: code == null
                ? null
                : () => _copy(code, 'portal.agent_copied'.tr()),
            onShare: code == null ? null : (from) => _share(from, code),
            onRotate: _rotate,
          ),
          if (code != null && _showVarHint) ...[
            const SizedBox(height: Sp.md),
            _VariableHint(
              onCopy: () =>
                  _copy(kAgentCodeVariable, 'portal.agent_var_copied'.tr()),
            ),
          ],
          if (a != null) ...[
            const SizedBox(height: Sp.lg),
            _PortalSwitchRow(
              value: a.enabled,
              busy: _savingSwitch,
              locked: !_canToggle,
              onChanged: _setEnabled,
              onLockedTap: () => permShown(const ['settings.edit'])
                  ? showNoPermission(context, action: true)
                  : showNoPermission(context,
                      message: 'portal.switch_owner_only'.tr()),
            ),
          ],
          const SizedBox(height: Sp.xl),
          if (!_canSeeLogins || _loginsDenied)
            // بلا `subscribers.view`: إطارٌ هادئ بقفل (عنوانه فيه) — ولا طلب
            // (الخادم ٤٠٣). وصلاحيّةٌ سُحبت بعد الفتح (٤٠٣) تُقفل مثلها.
            LockedCard(
              title: 'portal.logins_title'.tr(),
              icon: LucideIcons.history,
              block: true,
            )
          else ...[
            _SectionLabel(
              text: 'portal.logins_title'.tr(),
              icon: LucideIcons.history,
            ),
            const SizedBox(height: Sp.sm),
            _LoginsCard(
              loading: _loginsLoading,
              rows: _logins,
              onRetry: _retryLogins,
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// بطاقة الرمز
// ═════════════════════════════════════════════

/// البطاقة البارزة — `brandSurface` الثابت بالوضعين، فكلّ ما فوقها من رتب
/// `onBrand*` (كبطاقة هويّة المشترك ورصيد ايرث لنك).
class _AgentCodeCard extends StatelessWidget {
  const _AgentCodeCard({
    required this.loading,
    required this.access,
    required this.showRotate,
    required this.rotating,
    required this.onRetry,
    required this.onCopy,
    required this.onShare,
    required this.onRotate,
  });

  final bool loading;
  final PortalAccess? access;
  final bool showRotate;
  final bool rotating;
  final VoidCallback onRetry;
  final VoidCallback? onCopy;
  final void Function(BuildContext from)? onShare;
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final a = access;
    final code = a?.agentCode;
    return Container(
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titleRow(a),
          const SizedBox(height: Sp.lg),
          if (loading)
            const SizedBox(
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onBrand,
                  ),
                ),
              ),
            )
          else if (a == null)
            _notice(
              icon: LucideIcons.wifiOff,
              text: 'portal.agent_load_failed'.tr(),
              action: _OnBrandButton(
                icon: LucideIcons.refreshCw,
                label: 'common.retry'.tr(),
                onTap: onRetry,
              ),
            )
          else if (code == null)
            _notice(
              icon: LucideIcons.info,
              text: 'portal.agent_unavailable'.tr(),
            )
          else ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _Digits(key: ValueKey(code), code: code),
            ),
            if (!a.enabled) ...[
              const SizedBox(height: Sp.md),
              _pausedLine(),
            ],
            const SizedBox(height: Sp.lg),
            Row(
              children: [
                Expanded(
                  child: _OnBrandButton(
                    icon: LucideIcons.copy,
                    label: 'portal.agent_copy'.tr(),
                    onTap: onCopy,
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Builder(
                    builder: (from) => _OnBrandButton(
                      icon: LucideIcons.share2,
                      label: 'portal.agent_share'.tr(),
                      filled: true,
                      onTap: onShare == null ? null : () => onShare!(from),
                    ),
                  ),
                ),
              ],
            ),
            if (showRotate) ...[
              const SizedBox(height: Sp.sm),
              Center(child: _rotateButton()),
            ],
          ],
        ],
      ),
    );
  }

  /// الأيقونة والعنوان والحالة في صفّ، والشرح تحتها بعرض البطاقة كلّه — كان
  /// بجانب الأيقونة والحبّة فيلتفّ ثلاثة أسطر حتى ٣٦٠.
  Widget _titleRow(PortalAccess? a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: H.iconBox,
              height: H.iconBox,
              decoration: BoxDecoration(
                color: AppColors.onBrandFill2,
                borderRadius: BorderRadius.circular(R.icon),
              ),
              child: const Icon(LucideIcons.keyRound,
                  color: AppColors.onBrand, size: 20),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Text(
                'portal.agent_title'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.sheetTitle(color: AppColors.onBrand),
              ),
            ),
            if (a != null) ...[
              const SizedBox(width: Sp.sm),
              _StatePill(enabled: a.enabled),
            ],
          ],
        ),
        const SizedBox(height: Sp.md),
        Text(
          'portal.agent_sub'.tr(),
          style: AppType.body(color: AppColors.onBrandSecondary)
              .copyWith(height: 1.55),
        ),
      ],
    );
  }

  Widget _pausedLine() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.onBrandFill1,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.triangleAlert,
              size: 15, color: AppColors.onBrandDanger),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'portal.agent_paused'.tr(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong(color: AppColors.onBrandStrong),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice({
    required IconData icon,
    required String text,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.onBrandFill1,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.onBrandSecondary),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.onBrandStrong),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: Sp.md),
            action,
          ],
        ],
      ),
    );
  }

  Widget _rotateButton() {
    return TextButton.icon(
      onPressed: rotating ? null : onRotate,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.onBrandSecondary,
        disabledForegroundColor: AppColors.onBrandTertiary,
        minimumSize: const Size(0, H.chip),
        padding: const EdgeInsets.symmetric(horizontal: Sp.md),
        textStyle: AppType.bodyStrong(),
      ),
      icon: rotating
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppColors.onBrandSecondary,
              ),
            )
          : const Icon(LucideIcons.refreshCw, size: 15),
      label: Text('portal.agent_rotate'.tr()),
    );
  }
}

/// الأرقام الستّة — كبيرةً ومتباعدة بخانتين من ثلاث (123 456)، **من اليسار
/// دائماً**: الرمز يُقرأ ويُكتب كما هو ولو كانت الواجهة عربيّة.
class _Digits extends StatelessWidget {
  const _Digits({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Semantics(
      label: '${'portal.agent_title'.tr()}: ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        const gap = 6.0;
        const middle = 14.0;
        final w = ((c.maxWidth - gap * 4 - middle) / code.length)
            .clamp(28.0, 46.0);
        final digits = code.split('');
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < digits.length; i++) ...[
                if (i > 0) SizedBox(width: i == 3 ? middle : gap),
                Container(
                  width: w,
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.onBrandFill1,
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(color: AppColors.onBrandFill2),
                  ),
                  child: Text(
                    digits[i],
                    style: AppType.amount(color: AppColors.onBrand).copyWith(
                      fontSize: (w * 0.62).clamp(20.0, 28.0),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

/// حبّة الحالة أعلى البطاقة — نقطةٌ نعناعيّة للمفعّلة، وحمراء للموقوفة.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            decoration: BoxDecoration(
              color: enabled ? AppColors.onBrandMint : AppColors.onBrandDanger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            (enabled ? 'portal.state_on' : 'portal.state_off').tr(),
            style: AppType.pillBold(color: AppColors.onBrand),
          ),
        ],
      ),
    );
  }
}

/// زرّ فوق البطاقة الداكنة: [filled] أبيض بنصٍّ أخضر (الإجراء الأوّل)،
/// وإلّا شفّافٌ خفيف بنصٍّ أبيض.
class _OnBrandButton extends StatelessWidget {
  const _OnBrandButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final fg = filled ? AppColors.brandSurface : AppColors.onBrand;
    return SizedBox(
      height: H.segment,
      child: Material(
        color: filled ? AppColors.onBrand : AppColors.onBrandFill2,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: Sp.x6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.button(color: fg).copyWith(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// تلميح المتغيّر
// ═════════════════════════════════════════════

/// «تقدر تضيف رمزك لرسائل الواتساب بالمتغيّر {agent_code}» — والمتغيّر حبّةٌ
/// تُنسخ بنقرة، فيُلصق في القالب كما هو (الخادم يملؤه برمز المُرسِل).
class _VariableHint extends StatelessWidget {
  const _VariableHint({required this.onCopy});
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.channelWhatsAppSoftBg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(LucideIcons.messageCircle,
                size: 15, color: AppColors.channelWhatsApp),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${'portal.agent_wa_hint'.tr()} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Semantics(
                    button: true,
                    label: 'portal.agent_var_copy_a11y'.tr(),
                    child: InkWell(
                      onTap: onCopy,
                      borderRadius: BorderRadius.circular(R.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.x6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              kAgentCodeVariable,
                              textDirection: TextDirection.ltr,
                              style: AppType.bodyStrong(
                                  color: AppColors.textHi),
                            ),
                            const SizedBox(width: Sp.xs),
                            Icon(LucideIcons.copy,
                                size: 12, color: AppColors.textLow),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              style: AppType.body(color: AppColors.textBody)
                  .copyWith(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// مفتاح البوّابة
// ═════════════════════════════════════════════

/// «تفعيل بوابة مشتركيّ» — بشكل [SheetSwitchRow] داخل إطاره، ومقفلاً لمن لا
/// يملك `settings.edit`: الحالة حبّةً (مفعّلة/موقوفة) والقفل مكان المفتاح —
/// فيعرف الموظّف أنّ البوّابة تعمل ولا يقدر يبدّلها.
class _PortalSwitchRow extends StatelessWidget {
  const _PortalSwitchRow({
    required this.value,
    required this.busy,
    required this.locked,
    required this.onChanged,
    required this.onLockedTap,
  });

  final bool value;
  final bool busy;
  final bool locked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onLockedTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final title = 'portal.switch_title'.tr();
    final row = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: locked
                  ? LockedStyle.box
                  : (value ? AppTone.success.softBg : AppTone.warning.softBg),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(
              value ? LucideIcons.power : LucideIcons.powerOff,
              size: 18,
              color: locked
                  ? LockedStyle.glyph
                  : (value ? AppTone.success.fill : AppTone.warning.fill),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowValue(
                      color: locked ? LockedStyle.title : AppColors.textHi),
                ),
                const SizedBox(height: Sp.xxs),
                Text(
                  (value ? 'portal.switch_on_hint' : 'portal.switch_off_hint')
                      .tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(
                      color:
                          locked ? LockedStyle.subtitle : AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          if (locked) ...[
            ToneChip(
              label: (value ? 'portal.state_on' : 'portal.state_off').tr(),
              tone: value ? AppTone.success : AppTone.warning,
              dense: true,
            ),
            const SizedBox(width: Sp.x6),
            const PermLockIcon(),
          ] else if (busy)
            const SizedBox(
              width: 52,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppColors.onBrand,
              activeTrackColor: AppColors.brand,
            ),
        ],
      ),
    );
    // المفتاح وتسميته عنصرٌ واحد لقارئ الشاشة (كـSwitchListTile).
    if (!locked) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      label: 'locked.a11y'.tr(args: [title]),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onLockedTap,
          borderRadius: BorderRadius.circular(R.lg),
          child: row,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// آخر دخول المشتركين
// ═════════════════════════════════════════════

class _LoginsCard extends StatelessWidget {
  const _LoginsCard({
    required this.loading,
    required this.rows,
    required this.onRetry,
  });

  final bool loading;
  final List<PortalLogin>? rows;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final list = rows;
    final Widget body;
    if (loading && list == null) {
      body = const Padding(
        padding: EdgeInsets.all(Sp.xl),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (list == null) {
      body = _state(
        icon: LucideIcons.circleAlert,
        title: 'portal.logins_failed'.tr(),
        action: TextButton(
          onPressed: onRetry,
          child: Text('common.retry'.tr()),
        ),
      );
    } else if (list.isEmpty) {
      body = _state(
        icon: LucideIcons.userRound,
        title: 'portal.logins_empty'.tr(),
        hint: 'portal.logins_empty_hint'.tr(),
      );
    } else {
      final now = DateTime.now();
      body = Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            _LoginRow(row: list[i], now: now),
          ],
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: body,
    );
  }

  Widget _state({
    required IconData icon,
    required String title,
    String? hint,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.xl),
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppColors.textLow),
          const SizedBox(height: Sp.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.bodyBold(color: AppColors.textHi),
          ),
          if (hint != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid),
            ),
          ],
          if (action != null) ...[const SizedBox(height: Sp.xs), action],
        ],
      ),
    );
  }
}

class _LoginRow extends StatelessWidget {
  const _LoginRow({required this.row, required this.now});
  final PortalLogin row;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final (resultLabel, tone) = _result(row.result);
    final via = switch (row.via) {
      PortalLoginVia.password => 'portal.via_password'.tr(),
      PortalLoginVia.qr => 'portal.via_qr'.tr(),
      PortalLoginVia.unknown => '',
    };
    final when = portalLoginWhen(row.at, now: now);
    final meta = isoJoin([via, when], ' · ');
    // ٣٢٠: الصفّ أضيق ما يكون — الحشوة والأيقونة مقتصدتان كي يسع اليوزر
    // (`noor.alhuda@popq` نموذجاً) بجانب أطول حبّة («كلمة مرور خاطئة»).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tone.softBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              row.via == PortalLoginVia.qr
                  ? LucideIcons.qrCode
                  : LucideIcons.keyRound,
              size: 15,
              color: tone.fill,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // اليوزر لاتينيّ: يُقصّ (إن طال) من آخره يميناً لا من أوّله —
                // في فقرةٍ عربيّة كانت النقاط تسبقه فيبدو مقطوع البداية.
                Text(
                  iso(row.username ?? '—'),
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.rowValue().copyWith(fontSize: 13),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: Sp.xxs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textMid),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          ToneChip(label: resultLabel, tone: tone, dense: true),
        ],
      ),
    );
  }

  static (String, AppTone) _result(PortalLoginResult r) => switch (r) {
        PortalLoginResult.ok => ('portal.res_ok'.tr(), AppTone.success),
        PortalLoginResult.badPassword => (
            'portal.res_bad_password'.tr(),
            AppTone.danger
          ),
        PortalLoginResult.unverifiable => (
            'portal.res_unverifiable'.tr(),
            AppTone.warning
          ),
        PortalLoginResult.disabled => (
            'portal.res_disabled'.tr(),
            AppTone.neutral
          ),
        PortalLoginResult.unavailable => (
            'portal.res_unavailable'.tr(),
            AppTone.neutral
          ),
        PortalLoginResult.other => ('portal.res_other'.tr(), AppTone.neutral),
      };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.brand),
        const SizedBox(width: Sp.xs),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
