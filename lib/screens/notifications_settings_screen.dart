import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/agent_alerts_api.dart';
import '../api/agent_notifs_api.dart';
import '../api/notifications_api.dart';
import '../core/platform/app_platform.dart';
import '../core/widgets/permission_locked.dart';
import '../services/active_company.dart';
import '../services/provider_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'desktop/desk_widgets.dart';
import 'my_alerts/employee_ops_pick_sheet.dart';
import 'my_alerts/money_alerts_section.dart';
import 'my_alerts/notif_sounds_screen.dart';
import 'network_devices/agent_alerts_screen.dart';
import 'network_devices/device_alerts_screen.dart';

/// اسم الشاشة وصفّها بالإعدادات (٢٠ نوفمبر): ما يصل الوكيلَ نفسه — المال والأجهزة والاشتراكات وأوقات السكون.
const kMyAlertsTitle = 'إشعاراتي';

/// تنبيه «دين على مدير فرعي» لهذه الجلسة؟ شركات SAS4 نعم، وايرث لنك نعم منذ صار لها «المدراء» و«ديون أخرى» على حساباتها
/// التابعة (المالك ٢٣ نوفمبر: «ايرث لنك ممابيها هاي الميزه… تاكد هاي ميزه موجوده لكل انواع الساسات» — الخادم يرسله لحسابها
/// التابع كالساس: /api/admin/manager-debts ⇒ sendFcmToAdmin(earthlink:<idx>)). المشروع الوطنيّ القديم (FTTH) بلا مدراء فرعيّين.
@visibleForTesting
bool showManagerDebtToggle() {
  // والشركة المفتوحة احتياطاً قبل أن يصل `/api/auth/me` بالمزوّد.
  final code = ActiveCompany.current?.sasCode;
  return !ProviderService.isFtth && code != 'ftth-iq';
}

/// «تذاكر المشروع الوطني»: الوطنيّ على providerKit (`watani`) وحده — FTTH القديم وبقيّة الشركات بلا هذا التنبيه.
bool showNationalTicketToggle() => ProviderService.isKit && ProviderService.parentIsZone;

/// «عمليّات الموظّفين» — نصوص الموقع نفسها (MyAlerts.tsx، W25).
const kEmployeeOpsLabel = 'عمليّات الموظّفين';
const kEmployeeOpsHint = 'إشعارٌ بكلّ عمليّةٍ يجريها موظّفوك — تفعيل، تسديد، تعديل… — مجمّعاً بالدقيقة، ويحترم أوقات السكون';
const kEmployeeOpsLocked = 'لصاحب الحساب وحده — يصله إشعارٌ بعمليّات الموظّفين';

/// «إشعاراتي» — ما يصل الوكيلَ نفسه: «تنبيهات المال» (٢٠ نوفمبر، حين يقدّمها الخادم)، «تنبيهات الأجهزة»، toggles إشعارات FCM،
/// وأوقات السكون (DND) التي تؤجّل كلّ ذلك. كل تغيير يُحفظ تلقائياً بـPUT مع snackbar.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  NotificationPrefs? _prefs;
  bool _loading = true;
  bool _saving = false;

  /// «تنبيهات المال» — null: الخادم لا يقدّمها لهذا الحساب (أو تعذّرت) ⇒ لا قسم لها.
  AgentNotifs? _money;
  bool _moneyBusy = false;
  bool _moneyLoading = true;

  /// قراءةٌ لم تصل خلال مهلة الخادم (pending) ⇒ سؤالٌ ثانٍ بعد ٤ث، ستّ مرّاتٍ على الأكثر — لا رقم قديم بانتظارها.
  Timer? _poll;
  int _polls = 0;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // الشاشة لا تنتظر قراءات المال (قد تأخذ ثوانٍ): التفضيلات أوّلاً، والمال يصل بمكانه
    unawaited(_loadMoney());
    final p = await NotificationsApi.load();
    if (!mounted) return;
    setState(() {
      _prefs = p ?? NotificationPrefs.defaults;
      _loading = false;
    });
  }

  Future<void> _loadMoney() async {
    final m = await AgentNotifsApi.load();
    if (!mounted) return;
    setState(() {
      // سؤالٌ ثانٍ فشل (شبكة) بعد أن عُرض القسم ⇒ يبقى ما عُرض لا يختفي
      if (m != null || _money == null) _money = m;
      _moneyLoading = false;
    });
    _poll?.cancel();
    if (m != null && m.anyPending && _polls < 6) {
      _polls += 1;
      _poll = Timer(const Duration(seconds: 4), () {
        if (mounted && !_moneyBusy) unawaited(_loadMoney());
      });
    }
  }

  /// حفظ جزءٍ من «تنبيهات المال» — الخادم يردّ الإعداد كلّه بحاله الآن؛ الرفض يبقي القديم ويقول السبب.
  Future<bool> _patchMoney(Map<String, Object?> patch) async {
    if (_moneyBusy) return false;
    setState(() => _moneyBusy = true);
    final r = await AgentNotifsApi.save(patch);
    if (!mounted) return r.ok;
    setState(() {
      if (r.ok && r.data != null) _money = r.data;
      _moneyBusy = false;
    });
    if (r.ok && r.data != null && r.data!.anyPending) {
      _polls = 0;
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 4), () {
        if (mounted && !_moneyBusy) unawaited(_loadMoney());
      });
    }
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'notifs.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return r.ok;
  }

  /// «تنبيهات الأجهزة»: تنبيهات الخادم إن كانت مفتوحةً لهذه الشركة، وإلّا تنبيهات الهاتف — كزرّ التنبيهات بقسم الأجهزة.
  /// «أصوات الإشعارات» (٢٥ نوفمبر): نغمةٌ لكلّ نوع، والطلبات تنطق نوعها.
  Future<void> _openSounds() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotifSoundsScreen()));
  }

  Future<void> _openDeviceAlerts() async {
    final st = AgentAlertsApi.cached ?? await AgentAlertsApi.status();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => st?.available == true ? const AgentAlertsScreen() : const DeviceAlertsScreen(),
    ));
  }

  /// كل تعديل يُحفظ optimistically — نحدّث الـlocal state فوراً ثم
  /// نضرب PUT. لو فشل، نُرجِع القديم ونطبع snackbar.
  Future<void> _patch(NotificationPrefs Function(NotificationPrefs) op) async {
    if (_prefs == null || _saving) return;
    final old = _prefs!;
    final next = op(old);
    setState(() {
      _prefs = next;
      _saving = true;
    });
    final r = await NotificationsApi.save(next);
    if (!mounted) return;
    setState(() {
      _prefs = r.prefs ?? (r.ok ? next : old);
      _saving = false;
    });
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'notifs.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// «من موظّفيك»: الورقة ثمّ حفظ الاختيار وحده (PUT employeeOpsIds) — الرفض يبقي القديم ويقول السبب.
  Future<void> _pickEmployees() async {
    final p = _prefs;
    final list = p?.employeeOpsEmployees;
    if (p == null || list == null || _saving) return;
    final r = await showEmployeeOpsPickSheet(context, employees: list, initial: p.employeeOpsIds);
    if (r == null || !mounted) return;
    setState(() => _saving = true);
    final res = await NotificationsApi.saveEmployeeOpsIds(r.ids);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.ok && _prefs != null) _prefs = _prefs!.withEmployeeOpsIds(res.ids);
    });
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'notifs.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final p = _prefs;
    if (p == null) return;
    final current = _parseTime(isStart ? p.quietHoursStart : p.quietHoursEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final formatted = '$hh:$mm';
    await _patch((p) => isStart
        ? p.copyWith(quietHoursStart: formatted)
        : p.copyWith(quietHoursEnd: formatted));
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(':');
    final h = int.tryParse(parts[0]) ?? 22;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = _prefs;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(kMyAlertsTitle,
              style:
                  AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: _loading || p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                // «أصوات الإشعارات»: للهاتف وحده — الحاسبة بلا قنوات إشعار ولا FCM
                if (!AppPlatform.isDesktop) ...[
                  const _SectionLabel('الأصوات'),
                  _LinkRow(
                    key: const ValueKey('my-alerts-sounds'),
                    icon: LucideIcons.volume2,
                    label: 'أصوات الإشعارات',
                    sub: 'نغمة لكل نوع، والطلبات تنطق نوعها بالصوت',
                    onTap: _openSounds,
                  ),
                  const SizedBox(height: Sp.md),
                ],
                if (_money != null) ...[
                  const _SectionLabel('تنبيهات المال'),
                  MoneyAlertsSection(data: _money!, onPatch: _patchMoney, busy: _moneyBusy),
                  const SizedBox(height: Sp.md),
                ] else if (_moneyLoading && AgentNotifsApi.lastAvailable == true) ...[
                  // كان القسم هنا من قبل ⇒ مكانه بانتظار القراءة (لا يقفز المحتوى حين يصل)
                  const _SectionLabel('تنبيهات المال'),
                  const Padding(
                    key: ValueKey('ma-loading'),
                    padding: EdgeInsets.symmetric(vertical: Sp.lg),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  ),
                  const SizedBox(height: Sp.md),
                ],
                const _SectionLabel('تنبيهات الأجهزة'),
                _LinkRow(
                  key: const ValueKey('my-alerts-devices'),
                  icon: LucideIcons.router,
                  label: 'انطفاء أجهزتي ورجوعها',
                  sub: 'الأبراج والسكترات والأولتات، والحرارة والفولتيّة',
                  onTap: _openDeviceAlerts,
                ),
                const SizedBox(height: Sp.md),
                _SectionLabel('notifs.types_section'.tr()),
                _Toggle(
                  icon: LucideIcons.clock,
                  label: 'notifs.near_expiry_label'.tr(),
                  sub: 'notifs.near_expiry_hint'.tr(),
                  value: p.pushNearExpiry,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(pushNearExpiry: v)),
                ),
                _Toggle(
                  icon: LucideIcons.calendarX,
                  label: 'notifs.expired_today_label'.tr(),
                  sub: 'notifs.expired_today_hint'.tr(),
                  value: p.pushExpiredToday,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(pushExpiredToday: v)),
                ),
                // «دين على مدير فرعي»: الساس وايرث لنك (٢٣ نوفمبر)؛ المشروع الوطنيّ القديم بلا مدراء
                // فرعيّين ولا ديون مدراء — تنبيهٌ لا يقع أبداً، فلا يُعرض (ما لا
                // يدعمه المزوّد يُخفى). قيمته المحفوظة تبقى كما هي في الحفظ.
                if (showManagerDebtToggle())
                  _Toggle(
                    icon: LucideIcons.creditCard,
                    label: 'notifs.mgr_debt_label'.tr(),
                    sub: 'notifs.mgr_debt_hint'.tr(),
                    value: p.pushManagerDebt,
                    onChanged: (v) =>
                        _patch((x) => x.copyWith(pushManagerDebt: v)),
                  ),
                // «تذاكر المشروع الوطني» (١ نوفمبر): للوطنيّ على providerKit وحده — غيره لا تصله هذه التنبيهات.
                if (showNationalTicketToggle())
                  _Toggle(
                    icon: LucideIcons.headset,
                    label: 'notifs.national_ticket_label'.tr(),
                    sub: 'notifs.national_ticket_hint'.tr(),
                    value: p.pushWataniTicket,
                    onChanged: (v) =>
                        _patch((x) => x.copyWith(pushWataniTicket: v)),
                  ),
                // «عمليّات الموظّفين» (المالك ٢٣ نوفمبر: «اي موظف يسوي عمليه يذهب اشعار للمدير») — حين يقدّمها الخادم لهذه
                // الصفحة (مفتاحها وموظّفون فعّالون). الإشعار لصاحب الصفحة وحده ⇒ الموظّف يراه بمكانه مقفلاً كالموقع.
                if (p.employeeOpsAvailable)
                  _Toggle(
                    key: const ValueKey('notifs-employee-ops'),
                    icon: LucideIcons.userCog,
                    label: kEmployeeOpsLabel,
                    sub: p.employeeOpsCanEdit ? kEmployeeOpsHint : kEmployeeOpsLocked,
                    value: p.pushEmployeeOps,
                    onChanged: p.employeeOpsCanEdit ? (v) => _patch((x) => x.copyWith(pushEmployeeOps: v)) : null,
                    onLockedTap: () => showNoPermission(context, message: kEmployeeOpsLocked),
                  ),
                // «من موظّفيك» (المالك ٢٣ نوفمبر: «يحدد اكثر من واحد او واحد مستقل او الكل») — لصاحب الصفحة حين تصل قائمة موظّفيها؛
                // خافتٌ والمفتاح مطفأ كالموقع
                if (p.employeeOpsAvailable && p.employeeOpsCanEdit && (p.employeeOpsEmployees?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Opacity(
                      opacity: p.pushEmployeeOps ? 1 : 0.6,
                      child: _LinkRow(
                        key: const ValueKey('notifs-employee-ops-pick'),
                        icon: LucideIcons.users,
                        label: 'من موظّفيك',
                        sub: employeeOpsPickText(p.employeeOpsIds, p.employeeOpsEmployees!),
                        onTap: _pickEmployees,
                      ),
                    ),
                  ),
                const SizedBox(height: Sp.md),
                _SectionLabel('notifs.dnd_section'.tr()),
                _Toggle(
                  icon: LucideIcons.moon,
                  label: 'notifs.mute_window_label'.tr(),
                  sub: p.quietHoursEnabled
                      ? 'notifs.mute_range'.tr(namedArgs: {
                          'from': p.quietHoursStart,
                          'to': p.quietHoursEnd
                        })
                      : 'notifs.no_mute_hint'.tr(),
                  value: p.quietHoursEnabled,
                  onChanged: (v) =>
                      _patch((x) => x.copyWith(quietHoursEnabled: v)),
                ),
                if (p.quietHoursEnabled) ...[
                  const SizedBox(height: Sp.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _TimePickerTile(
                          label: 'notifs.from'.tr(),
                          value: p.quietHoursStart,
                          onTap: () => _pickTime(true),
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: _TimePickerTile(
                          label: 'notifs.to'.tr(),
                          value: p.quietHoursEnd,
                          onTap: () => _pickTime(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'notifs.mute_deferred_hint'.tr(),
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 11, height: 1.5),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: Sp.lg),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'notifs.saving'.tr(),
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, 6),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// صفٌّ يفتح شاشة — بشكل [_Toggle] نفسه وسهمٍ مكان المفتاح.
class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.icon, required this.label, required this.sub, required this.onTap});

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, height: 1.4)),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronLeft, color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
    this.onLockedTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final bool value;

  /// null ⇒ مقفل: المفتاح خافتٌ بحاله، ولمس الصفّ يقول السبب ([onLockedTap]) ولا يغيّر شيئاً.
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final row = _row();
    if (onChanged != null || onLockedTap == null) return row;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onLockedTap, child: row);
  }

  Widget _row() {
    final locked = onChanged == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: value ? AppColors.brandSoftBg : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 16,
              color: value ? AppColors.brand : AppColors.textLow,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                if (locked)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(LucideIcons.lock, size: 11, color: AppColors.textLow),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11, height: 1.4)),
                      ),
                    ],
                  )
                else
                  Text(
                    sub,
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 11, height: 1.4),
                  ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  const _TimePickerTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(LucideIcons.clock, size: 14, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text(
                    value,
                    style: AppType.title(color: AppColors.textHi).copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
