import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/broadcast_api.dart';
import '../../api/whatsapp_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../models/whatsapp_schedule.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/debt_filter_panel.dart';
import '../../widgets/list_kit.dart';
import '../desktop/desk_widgets.dart';

/// جدولة إشعارات WhatsApp — كارت لكل نوع (تحذير قرب انتهاء + تذكير ديون).
/// نُعدّل الوقت + الأيام + الوضع (weekly/monthly)، ونحفظ عبر
/// POST /api/whatsapp/save-schedule. مطابق تماماً لـv1 mobile
/// (schedules_screen.dart) + v1 web (WhatsAppSettings.js).
class WhatsAppSchedulesScreen extends StatefulWidget {
  const WhatsAppSchedulesScreen({super.key});

  @override
  State<WhatsAppSchedulesScreen> createState() =>
      _WhatsAppSchedulesScreenState();
}

class _WhatsAppSchedulesScreenState extends State<WhatsAppSchedulesScreen> {
  bool _loading = true;
  String? _adminId;

  // Expiry Warning state
  bool _expiryEnabled = false;
  String _expiryTime = '10:00:00';
  List<int> _expiryDays = const [0, 1, 2, 3, 4, 5, 6];
  int _daysBefore = 3;
  String _expiryChannel = 'auto';
  final _daysBeforeCtrl = TextEditingController(text: '3');
  bool _savingExpiry = false;
  // Server-side row existence — نحتاجه للـtoggle. لو null → لسّة ما
  // أُنشئت جدولة على السيرفر، فالـPATCH toggle سيفشل. نستعمل SAVE بدلها
  // (نفس نمط v1 mobile _toggleOrCreateSchedule).
  int? _expiryScheduleId;

  // Debt Reminder state
  bool _debtEnabled = false;
  String _debtTime = '11:00:00';
  List<int> _debtDays = const [0, 1, 2, 3, 4, 5, 6];
  String _debtMode = 'weekly';
  List<int> _debtMonthDays = const [1];
  String _debtChannel = 'auto';
  bool _savingDebt = false;
  int? _debtScheduleId;

  // «تحديد المدينين» داخل تذكير الديون (المالك ١٢ نوفمبر: الفلتر الذي في «التبليغات» يُضاف هنا بضبطه). اللوحة تظهر بما يعلنه
  // الخادم وحده (_debtCap — خادمٌ أقدم ⇒ لا لوحة والحفظ كما كان). _debtFilterSaved = ما على الخادم؛ المفتاح يُرسَل مع الحفظ
  // حين يختلف عنه _debtFilter وحده، فحفظُ الوقت أو الأيّام لا يمسّ التحديد. العدّ («يطابق الآن») من الخادم: مدينو المجدول أنفسهم.
  DebtFilterCapability? _debtCap;
  DebtFilter _debtFilter = DebtFilter.none;
  DebtFilter _debtFilterSaved = DebtFilter.none;
  bool _debtFilterInvalid = false;
  BroadcastPreview? _dfPreview;
  bool _dfBusy = false;
  String? _dfError;
  Timer? _dfTimer;
  int _dfSeq = 0;

  static const _dfCountDown = 'تعذّر العدّ الآن — التحديد يُطبَّق عند كلّ تنفيذ';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _dfTimer?.cancel();
    _daysBeforeCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AuthStorage.readAdminId(),
      WhatsAppApi.loadSchedulesBundle(),
    ]);
    if (!mounted) return;
    _adminId = results[0] as String?;
    final bundle = results[1] as ({List<WhatsAppSchedule> schedules, DebtFilterCapability? debtCap})?;
    _debtCap = bundle?.debtCap;
    _hydrateFromSchedules(bundle?.schedules ?? const []);
    setState(() => _loading = false);
    _queueDebtPreview(now: true);
  }

  /// Silent reload — نستعمله بعد save/toggle عشان نحصل على schedule id
  /// بدون spinner كامل يمسح الشاشة. الـUI يبقى مرئي أثناء إعادة الجلب.
  Future<void> _silentReload() async {
    final bundle = await WhatsAppApi.loadSchedulesBundle();
    if (!mounted) return;
    if (bundle != null) _debtCap = bundle.debtCap;
    _hydrateFromSchedules(bundle?.schedules ?? const []);
    setState(() {}); // لتحديث IDs في الـstate
    _queueDebtPreview(now: true);
  }

  static DebtFilter _filterOf(Map<String, int> m) =>
      DebtFilter(minAgeDays: m['minAgeDays'], minAmount: m['minAmount'], maxAmount: m['maxAmount']);

  bool get _debtFilterDirty => _debtCap != null && (_debtFilterInvalid || _debtFilter != _debtFilterSaved);

  void _onDebtFilterChanged(DebtFilter f) {
    setState(() => _debtFilter = f);
    _queueDebtPreview();
  }

  /// يعدّ من يطابق التحديد الحاليّ — بتأخيرٍ قصير أثناء الكتابة. بلا تحديدٍ (أو بتحديدٍ فيه خطأ) لا عدّ.
  void _queueDebtPreview({bool now = false}) {
    _dfTimer?.cancel();
    _dfSeq++;
    final cap = _debtCap;
    final f = _debtFilter;
    if (!mounted) return;
    if (cap == null || !f.active || f.problem(maxAgeDays: cap.maxAgeDays) != null) {
      setState(() {
        _dfPreview = null;
        _dfBusy = false;
        _dfError = null;
      });
      return;
    }
    // عمرٌ محفوظ والدفتر غير متاحٍ لحظيّاً (أو الشركة بلا مصدر أعمار): لا عدّ الآن — المحفوظ يُطبَّق عند التنفيذ
    if (!cap.age && f.minAgeDays != null) {
      setState(() {
        _dfPreview = null;
        _dfBusy = false;
        _dfError = 'عمر الدين المحفوظ يُطبَّق عند التنفيذ — العدّ غير متاحٍ الآن';
      });
      return;
    }
    setState(() {
      _dfBusy = true;
      _dfError = null;
    });
    final seq = _dfSeq;
    _dfTimer = Timer(now ? Duration.zero : const Duration(milliseconds: 600), () => _loadDebtPreview(seq, f));
  }

  Future<void> _loadDebtPreview(int seq, DebtFilter f) async {
    final r = await WhatsAppApi.scheduleDebtPreview(f);
    if (!mounted || seq != _dfSeq) return;
    setState(() {
      _dfBusy = false;
      _dfPreview = r.preview;
      // العدّ للاطّلاع وحده: تعذّره لا يعطّل التحديد — سطرٌ قصير يقول ذلك (ونصّ الخادم لما سواه)
      _dfError = r.preview != null
          ? null
          : (r.code == 'SCHEDULE_DEBT_PREVIEW_UNAVAILABLE' ? _dfCountDown : (r.message ?? _dfCountDown));
    });
  }

  void _hydrateFromSchedules(List<WhatsAppSchedule> list) {
    for (final s in list) {
      if (s.scheduleType == 'expiry_warning') {
        _expiryScheduleId = s.id;
        _expiryEnabled = s.isEnabled;
        _expiryTime = s.scheduledTime;
        _expiryDays = List<int>.from(s.activeDays);
        _daysBefore = s.daysBefore ?? 3;
        _daysBeforeCtrl.text = _daysBefore.toString();
        _expiryChannel = s.channelPreference;
      } else if (s.scheduleType == 'debt_reminder') {
        _debtScheduleId = s.id;
        _debtEnabled = s.isEnabled;
        _debtTime = s.scheduledTime;
        _debtDays = List<int>.from(s.activeDays);
        _debtMode = s.scheduleMode == 'monthly' ? 'monthly' : 'weekly';
        _debtMonthDays =
            s.monthDays.isNotEmpty ? List<int>.from(s.monthDays) : const [1];
        _debtChannel = s.channelPreference;
        _debtFilterSaved = _filterOf(s.debtFilter);
        _debtFilter = _debtFilterSaved;
        _debtFilterInvalid = s.debtFilterInvalid;
      }
    }
  }

  Future<void> _pickTime({
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 10,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    onPicked(formatted);
  }

  Future<void> _saveExpiry() async {
    if (_adminId == null) return;
    if (!_validateDaysBefore()) return;
    setState(() => _savingExpiry = true);
    final schedule = WhatsAppSchedule(
      id: _expiryScheduleId,
      adminId: _adminId!,
      scheduleType: 'expiry_warning',
      isEnabled: _expiryEnabled,
      scheduledTime: _expiryTime,
      activeDays: List<int>.from(_expiryDays)..sort(),
      daysBefore: _daysBefore,
      channelPreference: _expiryChannel,
    );
    final r = await WhatsAppApi.saveSchedule(schedule);
    if (!mounted) return;
    setState(() => _savingExpiry = false);
    if (r.ok) {
      // إعادة تحميل — نحصل على schedule id لو كانت أول مرّة
      await _silentReload();
      if (!mounted) return;
    }
    _showSnack(
        r.ok
            ? 'wa_schedules.saved'.tr()
            : (r.message ?? 'wa_schedules.save_failed'.tr()),
        error: !r.ok);
  }

  Future<void> _saveDebt() async {
    if (_adminId == null) return;
    // تحديدٌ فيه خطأ (حدٌّ أدنى أكبر من الأعلى…) لا يُحفظ — يُقال قبل الطلب (والخادم يرفضه أيضاً)
    final cap = _debtCap;
    if (cap != null && _debtFilterDirty && _debtFilter.active) {
      final problem = _debtFilter.problem(maxAgeDays: cap.maxAgeDays);
      if (problem != null) {
        _showSnack(problem, error: true);
        return;
      }
    }
    setState(() => _savingDebt = true);
    final schedule = WhatsAppSchedule(
      id: _debtScheduleId,
      adminId: _adminId!,
      scheduleType: 'debt_reminder',
      isEnabled: _debtEnabled,
      scheduledTime: _debtTime,
      activeDays: List<int>.from(_debtDays)..sort(),
      scheduleMode: _debtMode,
      monthDays: _debtMode == 'monthly'
          ? (List<int>.from(_debtMonthDays)..sort())
          : const [],
      channelPreference: _debtChannel,
      // يُرسَل حين تغيّر وحده (كائنٌ أو null للمسح) — وإلّا يبقى المحفوظ على الخادم كما هو
      debtFilter: _debtFilter.toJson(),
      sendDebtFilter: _debtFilterDirty,
    );
    final r = await WhatsAppApi.saveSchedule(schedule);
    if (!mounted) return;
    setState(() => _savingDebt = false);
    if (r.ok) {
      await _silentReload();
      if (!mounted) return;
    }
    _showSnack(
        r.ok
            ? 'wa_schedules.saved'.tr()
            : (r.message ?? 'wa_schedules.save_failed'.tr()),
        error: !r.ok);
  }

  /// Toggle مع fallback ذكي — لو الجدولة ما زالت غير موجودة على السيرفر
  /// (أول مرّة يفعّلها المدير)، PATCH schedule-toggle يفشل ("الجدولة غير
  /// موجودة"). نستعمل SAVE بدلها لإنشاء الصف. مطابق v1 mobile
  /// (_toggleOrCreateSchedule).
  Future<void> _toggleExpiry(bool v) async {
    if (_adminId == null) return;
    setState(() => _expiryEnabled = v);

    // لو ما في صف بعد + تعطيل → no-op (لا شي لتعطيله)
    if (_expiryScheduleId == null && !v) return;

    // لو ما في صف + تفعيل → أنشئه عبر SAVE (نفس v1)
    if (_expiryScheduleId == null && v) {
      if (!_validateDaysBefore()) {
        setState(() => _expiryEnabled = false);
        return;
      }
      final schedule = WhatsAppSchedule(
        adminId: _adminId!,
        scheduleType: 'expiry_warning',
        isEnabled: true,
        scheduledTime: _expiryTime,
        activeDays: List<int>.from(_expiryDays)..sort(),
        daysBefore: _daysBefore,
        channelPreference: _expiryChannel,
      );
      final r = await WhatsAppApi.saveSchedule(schedule);
      if (!mounted) return;
      if (r.ok) {
        await _silentReload();
        if (!mounted) return;
        _showSnack('wa_schedules.enabled'.tr());
      } else {
        setState(() => _expiryEnabled = false);
        _showSnack(r.message ?? 'wa_schedules.toggle_failed'.tr(), error: true);
      }
      return;
    }

    // الحالة العاديّة — الصف موجود، PATCH toggle
    final r = await WhatsAppApi.toggleSchedule(
      scheduleType: 'expiry_warning',
      isEnabled: v,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _expiryEnabled = !v);
      _showSnack(r.message ?? 'wa_schedules.toggle_failed'.tr(), error: true);
    }
  }

  Future<void> _toggleDebt(bool v) async {
    if (_adminId == null) return;
    setState(() => _debtEnabled = v);
    if (_debtScheduleId == null && !v) return;
    if (_debtScheduleId == null && v) {
      final schedule = WhatsAppSchedule(
        adminId: _adminId!,
        scheduleType: 'debt_reminder',
        isEnabled: true,
        scheduledTime: _debtTime,
        activeDays: List<int>.from(_debtDays)..sort(),
        scheduleMode: _debtMode,
        monthDays: _debtMode == 'monthly'
            ? (List<int>.from(_debtMonthDays)..sort())
            : const [],
        channelPreference: _debtChannel,
        // أوّل تفعيلٍ ينشئ الصفّ: بالتحديد الذي على الشاشة إن كان سليماً — لا يُفعَّل تذكيرٌ لكلّ المدينين والمدير حدّد غيرهم
        debtFilter: _debtFilter.toJson(),
        sendDebtFilter: _debtCap != null &&
            _debtFilter.active &&
            _debtFilter.problem(maxAgeDays: _debtCap!.maxAgeDays) == null,
      );
      final r = await WhatsAppApi.saveSchedule(schedule);
      if (!mounted) return;
      if (r.ok) {
        await _silentReload();
        if (!mounted) return;
        _showSnack('wa_schedules.enabled'.tr());
      } else {
        setState(() => _debtEnabled = false);
        _showSnack(r.message ?? 'wa_schedules.toggle_failed'.tr(), error: true);
      }
      return;
    }
    final r = await WhatsAppApi.toggleSchedule(
      scheduleType: 'debt_reminder',
      isEnabled: v,
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _debtEnabled = !v);
      _showSnack(r.message ?? 'wa_schedules.toggle_failed'.tr(), error: true);
    }
  }

  bool _validateDaysBefore() {
    final n = int.tryParse(_daysBeforeCtrl.text.trim());
    if (n == null || n < 1 || n > 30) {
      _showSnack('wa_schedules.days_before_invalid'.tr(), error: true);
      return false;
    }
    _daysBefore = n;
    return true;
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg,
              style: AppType.label(color: AppColors.onBrand)
                  .copyWith(fontWeight: FontWeight.w600)),
          backgroundColor: error ? AppColors.error : AppColors.brand,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(Sp.md),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'wa_schedules.title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brand,
          onRefresh: _bootstrap,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _expiryCard(),
                const SizedBox(height: Sp.md),
                _debtCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _cardHeader({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: AppType.label(color: AppColors.textMid)
                      .copyWith(fontSize: 12.5)),
            ],
          ),
        ),
        Switch.adaptive(
          value: enabled,
          onChanged: onToggle,
          activeThumbColor: color,
        ),
      ],
    );
  }

  Widget _timeRow({
    required String time,
    required VoidCallback onTap,
  }) {
    final display = time.length >= 5 ? time.substring(0, 5) : time;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, size: 18, color: AppColors.textMid),
            const SizedBox(width: 10),
            Text('wa_schedules.execution_time'.tr(),
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 13)),
            const Spacer(),
            Text(display,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 15, fontFeatures: [
                  const FontFeature.tabularFigures(),
                ])),
          ],
        ),
      ),
    );
  }

  Widget _weekdayChips({
    required List<int> selected,
    required ValueChanged<List<int>> onChanged,
    required Color color,
  }) {
    // ترتيب عربي: السبت (6) أولاً؟ أم الأحد (0)؟ نتّبع v1: الأحد أولاً.
    // 0=الأحد ... 6=السبت. المستخدم يعرف الترتيب من v1.
    const labels = ['أحد', 'اثن', 'ثلا', 'أرب', 'خمي', 'جمع', 'سبت'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(7, (i) {
        final isSelected = selected.contains(i);
        return FilterChip(
          label: Text(labels[i],
              style: AppType.bodyStrong(
                  color: isSelected ? AppColors.onBrand : AppColors.textMid)),
          selected: isSelected,
          onSelected: (_) {
            final next = List<int>.from(selected);
            if (isSelected) {
              next.remove(i);
            } else {
              next.add(i);
              next.sort();
            }
            onChanged(next);
          },
          backgroundColor: AppColors.surfaceInput,
          selectedColor: color,
          checkmarkColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.card),
            side: BorderSide(
              color: isSelected ? color : AppColors.border,
            ),
          ),
        );
      }),
    );
  }

  Widget _saveButton({
    required bool saving,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: saving ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.sm),
          ),
        ),
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: AppColors.onBrand,
                ),
              )
            : Text(
                'wa_schedules.save'.tr(),
                style: AppType.cardTitleBold(color: AppColors.onBrand),
              ),
      ),
    );
  }

  // ─── Expiry Warning Card ────────────────────────────────
  Widget _expiryCard() {
    final color = AppColors.brand;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: LucideIcons.circleAlert,
            color: color,
            title: 'wa_schedules.expiry_title'.tr(),
            subtitle: 'wa_schedules.expiry_subtitle'.tr(),
            enabled: _expiryEnabled,
            onToggle: _toggleExpiry,
          ),
          const SizedBox(height: Sp.md),
          _timeRow(
            time: _expiryTime,
            onTap: () => _pickTime(
              current: _expiryTime,
              onPicked: (v) => setState(() => _expiryTime = v),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text('wa_schedules.days_before_label'.tr(),
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _daysBeforeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textDirection: ui.TextDirection.ltr,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              hintText: '3',
              filled: true,
              fillColor: AppColors.surfaceInput,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: color, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text('wa_schedules.weekly_days'.tr(),
              style: AppType.label(color: AppColors.textMid)
                  .copyWith(fontSize: 12.5)),
          const SizedBox(height: 8),
          _weekdayChips(
            selected: _expiryDays,
            onChanged: (v) => setState(() => _expiryDays = v),
            color: color,
          ),
          const SizedBox(height: Sp.md),
          _channelPicker(
            current: _expiryChannel,
            onChanged: (v) => setState(() => _expiryChannel = v),
          ),
          const SizedBox(height: Sp.md),
          _saveButton(
            saving: _savingExpiry,
            onPressed: _saveExpiry,
            color: color,
          ),
        ],
      ),
    );
  }

  // ─── Debt Reminder Card ────────────────────────────────
  Widget _debtCard() {
    final color = AppColors.warning; // amber — تمييز عن expiry
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            icon: LucideIcons.wallet,
            color: color,
            title: 'wa_schedules.debt_title'.tr(),
            subtitle: 'wa_schedules.debt_subtitle'.tr(),
            enabled: _debtEnabled,
            onToggle: _toggleDebt,
          ),
          const SizedBox(height: Sp.md),
          _timeRow(
            time: _debtTime,
            onTap: () => _pickTime(
              current: _debtTime,
              onPicked: (v) => setState(() => _debtTime = v),
            ),
          ),
          const SizedBox(height: Sp.md),
          // Mode toggle (weekly / monthly)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _modeChip(
                    label: 'wa_schedules.mode_weekly'.tr(),
                    selected: _debtMode == 'weekly',
                    color: color,
                    onTap: () => setState(() => _debtMode = 'weekly'),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _modeChip(
                    label: 'wa_schedules.mode_monthly'.tr(),
                    selected: _debtMode == 'monthly',
                    color: color,
                    onTap: () => setState(() => _debtMode = 'monthly'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          if (_debtMode == 'weekly') ...[
            Text('wa_schedules.weekly_days'.tr(),
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 12.5)),
            const SizedBox(height: 8),
            _weekdayChips(
              selected: _debtDays,
              onChanged: (v) => setState(() => _debtDays = v),
              color: color,
            ),
          ] else ...[
            Text('wa_schedules.monthly_days'.tr(),
                style: AppType.label(color: AppColors.textMid)
                    .copyWith(fontSize: 12.5)),
            const SizedBox(height: 8),
            _monthDayChips(color: color),
          ],
          const SizedBox(height: Sp.md),
          _channelPicker(
            current: _debtChannel,
            onChanged: (v) => setState(() => _debtChannel = v),
          ),
          if (_debtCap != null) ...[
            const SizedBox(height: Sp.md),
            ..._debtFilterSection(_debtCap!),
          ],
          const SizedBox(height: Sp.md),
          _saveButton(
            saving: _savingDebt,
            onPressed: _saveDebt,
            color: color,
          ),
        ],
      ),
    );
  }

  // ─── «تحديد المدينين» داخل تذكير الديون ────────────────
  // اللوحة نفسها التي في «التبليغات» (DebtFilterPanel) + ما يقوله المحفوظ + قائمة من يطابق الآن.
  List<Widget> _debtFilterSection(DebtFilterCapability cap) {
    final pv = _dfPreview;
    final showList = _debtFilter.active && !_dfBusy && _dfError == null && pv != null && pv.rows.isNotEmpty;
    return [
      if (_debtFilterInvalid) ...[
        Container(
          key: const ValueKey('sched-df-invalid'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.dangerSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.dangerSoftBorder),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(LucideIcons.circleAlert, size: 14, color: AppColors.dangerOnSoft),
            const SizedBox(width: 6),
            Expanded(
              child: Text('التحديد المحفوظ غير مقروء — تذكير الديون متوقّف حتى تحفظ من جديد.',
                  style: AppType.micro(color: AppColors.dangerOnSoft).copyWith(height: 1.5, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: Sp.sm),
      ],
      if (_debtFilterSaved.active) ...[
        Text('يصل الآن لمن: ${_debtFilterSaved.describe()}',
            key: const ValueKey('sched-df-saved'), style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5)),
        const SizedBox(height: Sp.sm),
      ],
      DebtFilterPanel(
        cap: cap,
        value: _debtFilter,
        onChanged: _onDebtFilterChanged,
        busy: _dfBusy,
        error: _dfError,
        preview: pv,
        // العمر المحجوب: السبب في قدرة الخادم لا في العدّ — يُعاد جلبها مع الجدولات
        onRetry: () => (!cap.age && _debtFilter.minAgeDays != null) ? _silentReload() : _queueDebtPreview(now: true),
      ),
      if (showList)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('sched-df-list'),
            onPressed: () => showScheduleDebtMatchesSheet(context, filter: _debtFilter, preview: pv),
            icon: Icon(LucideIcons.listChecks, size: 16, color: AppColors.brand),
            label: Text('عرض من يطابق الآن', style: AppType.labelBold(color: AppColors.brand)),
          ),
        )
      else
        const SizedBox(height: Sp.xs),
      Text(
        _debtFilter.active
            ? 'يُحسب من جديد عند كلّ تنفيذ: من سدّد يخرج، ومن قدُم دينه أو كبر يدخل.'
            : 'بلا تحديد: يصل التذكير لكلّ من عليه دين.',
        key: const ValueKey('sched-df-hint'),
        style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5),
      ),
    ];
  }

  Widget _modeChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Text(
          label,
          style: AppType.rowLabelBold(
              color: selected ? AppColors.onBrand : AppColors.textMid),
        ),
      ),
    );
  }

  Widget _monthDayChips({required Color color}) {
    // 3 خيارات فقط (بداية/منتصف/نهاية الشهر) مطابق v1
    // 31 = sentinel لآخر يوم في الشهر
    final options = <(int, String)>[
      (1, 'wa_schedules.day_start'.tr()),
      (15, 'wa_schedules.day_middle'.tr()),
      (31, 'wa_schedules.day_end'.tr()),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final day = opt.$1;
        final label = opt.$2;
        final selected = _debtMonthDays.contains(day);
        return FilterChip(
          label: Text(label,
              style: AppType.bodyStrong(
                  color: selected ? AppColors.onBrand : AppColors.textMid)),
          selected: selected,
          onSelected: (_) {
            setState(() {
              final next = List<int>.from(_debtMonthDays);
              if (selected) {
                next.remove(day);
              } else {
                next.add(day);
                next.sort();
              }
              // نضمن دائماً وجود قيمة واحدة على الأقل
              _debtMonthDays = next.isEmpty ? const [1] : next;
            });
          },
          backgroundColor: AppColors.surfaceInput,
          selectedColor: color,
          checkmarkColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.card),
            side: BorderSide(
              color: selected ? color : AppColors.border,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Channel Preference Picker ─────────────────────────
  // 2026-08-26: قناة الإرسال المفضّلة (auto/whatsapp/telegram).
  // مطابق _defaultChannelPicker في whatsapp_templates_screen.
  Widget _channelPicker({
    required String current,
    required ValueChanged<String> onChanged,
  }) {
    final options = [
      (
        value: 'auto',
        label: 'تلقائي',
        icon: LucideIcons.split,
        color: AppColors.brand,
        hint: 'يحترم ربط المشترك (تلغرام لو مربوط، وإلا واتساب)',
      ),
      (
        value: 'whatsapp',
        label: 'واتساب فقط',
        icon: LucideIcons.messageCircle,
        color: AppColors.channelWhatsApp,
        hint: 'يجبر الواتساب حتى للمربوطين بتلغرام',
      ),
      (
        value: 'telegram',
        label: 'تلغرام فقط',
        icon: LucideIcons.send,
        color: AppColors.channelTelegram,
        hint: 'يجبر تلغرام — يفشل للمشترك غير المربوط',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('قناة الإرسال', style: AppType.bodyBold()),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _channelChip(
                    label: options[i].label,
                    icon: options[i].icon,
                    color: options[i].color,
                    selected: current == options[i].value,
                    onTap: () => onChanged(options[i].value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            options.firstWhere((o) => o.value == current).hint,
            style: TextStyle(
              fontFamily: AppType.family,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMid,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.14) : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: selected ? color : AppColors.textMid),
            const SizedBox(width: 4),
            // ⚠️ يتقلّص ولا يُقصّ: ثلاث حبّاتٍ في صفٍّ واحد لا تترك
            // للتسمية إلّا ٤٧ نقطة عند ٣٢٠، و«واتساب فقط» تحتاج ٥٧٫٣.
            // و«واتسا…» لا تعني شيئاً؛ الحجم الأصغر يُقرأ.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: AppType.pillBold(
                        color: selected ? color : AppColors.textMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// من يطابق تحديد تذكير الديون **الآن** — للاطّلاع: الاسم واليوزر والدين وعمر أقدم دينٍ لم يُسدَّد («دين قديم» = أقدم من سجلّاتنا).
Future<void> showScheduleDebtMatchesSheet(BuildContext context, {required DebtFilter filter, required BroadcastPreview preview}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _DebtMatchesSheet(filter: filter, preview: preview),
  );
}

class _DebtMatchesSheet extends StatelessWidget {
  const _DebtMatchesSheet({required this.filter, required this.preview});
  final DebtFilter filter;
  final BroadcastPreview preview;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pv = preview;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.funnel,
        title: 'من يطابق التحديد الآن',
        subtitle: filter.describe(),
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(R.md)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < pv.rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppColors.border),
                ListSubscriberRow(
                  title: pv.rows[i].name ?? pv.rows[i].username,
                  subtitle: pv.rows[i].name == null ? '' : pv.rows[i].username,
                  subtitleLtr: true,
                  selectable: false,
                  selected: false,
                  trailing: ListAmountCell(
                    amount: AmountShorthand.format(pv.rows[i].debt.round()).isEmpty ? '0' : AmountShorthand.format(pv.rows[i].debt.round()),
                    amountColor: AppColors.warningOnSoft,
                    badge: pv.rows[i].legacy
                        ? 'دين قديم'
                        : (pv.rows[i].days == null ? null : (pv.rows[i].days == 0 ? 'اليوم' : arDaysCount(pv.rows[i].days!))),
                    badgeTone: pv.rows[i].legacy ? ListTone.info : ((pv.rows[i].days ?? 0) > 30 ? ListTone.danger : ListTone.warning),
                  ),
                ),
              ],
            ]),
          ),
          if (pv.truncated) ...[
            const SizedBox(height: Sp.xs),
            Text('تُعرض أوّل ${pv.rows.length} من ${pv.audience}',
                textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }
}
