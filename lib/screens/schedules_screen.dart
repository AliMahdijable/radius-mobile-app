import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedules_provider.dart';
import '../models/schedule_model.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../core/services/storage_service.dart';
import '../core/network/dio_client.dart';
import '../widgets/app_snackbar.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  String _expiryTime = '10:00:00';
  String _debtTime = '11:00:00';
  List<int> _expiryDays = [0, 1, 2, 3, 4, 5, 6];
  List<int> _debtDays = [0, 1, 2, 3, 4, 5, 6];
  int _daysBefore = 3;
  final _daysBeforeController = TextEditingController(text: '3');
  // Monthly mode: only applied to debt_reminder. 'weekly' = use
  // _debtDays, 'monthly' = use _debtMonthDays (1..31 with 31 = last day).
  String _debtMode = 'weekly';
  List<int> _debtMonthDays = [1];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(schedulesProvider.notifier).loadSchedules();
    });
  }

  @override
  void dispose() {
    _daysBeforeController.dispose();
    super.dispose();
  }

  void _syncFromState(SchedulesState state) {
    for (final s in state.schedules) {
      if (s.scheduleType == 'expiry_warning') {
        _expiryTime = s.scheduledTime;
        _expiryDays = List<int>.from(s.activeDays);
        _daysBefore = s.daysBefore ?? 3;
        _daysBeforeController.text = _daysBefore.toString();
      } else if (s.scheduleType == 'debt_reminder') {
        _debtTime = s.scheduledTime;
        _debtDays = List<int>.from(s.activeDays);
        _debtMode = s.scheduleMode == 'monthly' ? 'monthly' : 'weekly';
        _debtMonthDays = s.monthDays.isNotEmpty ? List<int>.from(s.monthDays) : [1];
      }
    }
  }

  bool _didSync = false;

  ScheduleModel? _findSchedule(SchedulesState state, String type) {
    try {
      return state.schedules.firstWhere((s) => s.scheduleType == type);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickTime(String currentTime, ValueChanged<String> onPicked) async {
    final parts = currentTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 10,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      onPicked(formatted);
    }
  }

  /// Called from the card switch. If the schedule row already exists we just
  /// flip its is_enabled column. If it doesn't, the backend's UPDATE would
  /// hit 0 rows and return a "الجدولة غير موجودة" error — so we transparently
  /// save a new schedule with the current form values and enabled=true.
  /// That way the first toggle works without forcing the user to press
  /// "Save" first.
  Future<void> _toggleOrCreateSchedule(String type, bool enable) async {
    final state = ref.read(schedulesProvider);
    final existing = _findSchedule(state, type);

    if (existing != null) {
      final err = await ref
          .read(schedulesProvider.notifier)
          .toggleSchedule(type, enable);
      if (!mounted) return;
      if (err == null) {
        AppSnackBar.success(
          context,
          enable ? 'تم تفعيل الجدولة' : 'تم تعطيل الجدولة',
        );
      } else {
        AppSnackBar.error(context, err);
      }
      return;
    }

    // No row yet. Turning off when there's no row is a no-op; anything else
    // should create the schedule so the switch reflects reality.
    if (!enable) return;

    final storage = ref.read(storageServiceProvider);
    final adminId = await storage.getAdminId() ?? '';
    if (adminId.isEmpty) {
      if (mounted) {
        AppSnackBar.error(
          context,
          'معرّف المدير غير متوفر. سجّل الخروج والدخول ثم أعد المحاولة.',
        );
      }
      return;
    }

    final schedule = ScheduleModel(
      adminId: adminId,
      scheduleType: type,
      isEnabled: true,
      scheduledTime: type == 'expiry_warning' ? _expiryTime : _debtTime,
      activeDays: List<int>.from(
        type == 'expiry_warning' ? _expiryDays : _debtDays,
      )..sort(),
      daysBefore: type == 'expiry_warning'
          ? (int.tryParse(_daysBeforeController.text) ?? _daysBefore)
          : null,
      executionCount: 0,
      scheduleMode: type == 'debt_reminder' ? _debtMode : 'weekly',
      monthDays: type == 'debt_reminder' && _debtMode == 'monthly'
          ? (List<int>.from(_debtMonthDays)..sort())
          : const [],
    );

    final err =
        await ref.read(schedulesProvider.notifier).saveSchedule(schedule);
    if (!mounted) return;
    if (err == null) {
      AppSnackBar.success(context, 'تم تفعيل الجدولة');
    } else {
      AppSnackBar.error(context, err);
    }
  }

  Future<void> _saveSchedule(String type) async {
    final state = ref.read(schedulesProvider);
    final existing = _findSchedule(state, type);

    final storage = ref.read(storageServiceProvider);
    final adminId = await storage.getAdminId() ?? existing?.adminId ?? '';
    if (adminId.isEmpty) {
      if (mounted) {
        AppSnackBar.error(
          context,
          'معرّف المدير غير متوفر. سجّل الخروج والدخول ثم أعد المحاولة.',
        );
      }
      return;
    }

    final schedule = ScheduleModel(
      id: existing?.id,
      adminId: adminId,
      scheduleType: type,
      // Match web default (WhatsAppSettings.js): new schedules start disabled so save works without WA.
      isEnabled: existing?.isEnabled ?? false,
      scheduledTime: type == 'expiry_warning' ? _expiryTime : _debtTime,
      activeDays: List<int>.from(
        type == 'expiry_warning' ? _expiryDays : _debtDays,
      )..sort(),
      daysBefore: type == 'expiry_warning'
          ? (int.tryParse(_daysBeforeController.text) ?? _daysBefore)
          : null,
      executionCount: existing?.executionCount ?? 0,
      scheduleMode: type == 'debt_reminder' ? _debtMode : 'weekly',
      monthDays: type == 'debt_reminder' && _debtMode == 'monthly'
          ? (List<int>.from(_debtMonthDays)..sort())
          : const [],
    );

    final err = await ref.read(schedulesProvider.notifier).saveSchedule(schedule);
    if (mounted) {
      if (err == null) {
        AppSnackBar.success(context, 'تم حفظ الجدولة');
      } else {
        AppSnackBar.error(context, err);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(schedulesProvider);
    final theme = Theme.of(context);

    if (!_didSync && !state.isLoading && state.schedules.isNotEmpty) {
      _didSync = true;
      Future.microtask(() {
        if (mounted) setState(() => _syncFromState(state));
      });
    }

    final expirySchedule = _findSchedule(state, 'expiry_warning');
    final debtSchedule = _findSchedule(state, 'debt_reminder');

    return Scaffold(
      appBar: AppBar(title: const Text('الجدولة')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                _didSync = false;
                await ref.read(schedulesProvider.notifier).loadSchedules();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _ScheduleCard(
                      icon: Icons.warning_amber_rounded,
                      accentColor: AppTheme.warningColor,
                      title: 'تنبيه قرب انتهاء الاشتراك',
                      isEnabled: expirySchedule?.isEnabled ?? false,
                      onToggle: (v) =>
                          _toggleOrCreateSchedule('expiry_warning', v),
                      time: _expiryTime,
                      onTimeTap: () => _pickTime(_expiryTime, (t) {
                        setState(() => _expiryTime = t);
                      }),
                      activeDays: _expiryDays,
                      onDayToggled: (day, selected) {
                        setState(() {
                          if (selected) {
                            _expiryDays.add(day);
                          } else {
                            _expiryDays.remove(day);
                          }
                        });
                      },
                      daysBeforeController: _daysBeforeController,
                      showDaysBefore: true,
                      onSave: () => _saveSchedule('expiry_warning'),
                    ),
                    const SizedBox(height: 16),
                    _ScheduleCard(
                      icon: Icons.credit_card_rounded,
                      accentColor: AppTheme.infoColor,
                      title: 'تذكير بالديون المستحقة',
                      isEnabled: debtSchedule?.isEnabled ?? false,
                      onToggle: (v) =>
                          _toggleOrCreateSchedule('debt_reminder', v),
                      time: _debtTime,
                      onTimeTap: () => _pickTime(_debtTime, (t) {
                        setState(() => _debtTime = t);
                      }),
                      activeDays: _debtDays,
                      onDayToggled: (day, selected) {
                        setState(() {
                          if (selected) {
                            _debtDays.add(day);
                          } else {
                            _debtDays.remove(day);
                          }
                        });
                      },
                      showDaysBefore: false,
                      onSave: () => _saveSchedule('debt_reminder'),
                      mode: _debtMode,
                      onModeChanged: (m) => setState(() {
                        _debtMode = m;
                        if (m == 'monthly' && _debtMonthDays.isEmpty) {
                          _debtMonthDays = [1];
                        }
                      }),
                      monthDays: _debtMonthDays,
                      onMonthDayToggled: (day, selected) {
                        setState(() {
                          if (selected) {
                            if (!_debtMonthDays.contains(day)) {
                              _debtMonthDays = [..._debtMonthDays, day];
                            }
                          } else {
                            _debtMonthDays =
                                _debtMonthDays.where((d) => d != day).toList();
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final bool isEnabled;
  final ValueChanged<bool> onToggle;
  final String time;
  final VoidCallback onTimeTap;
  final List<int> activeDays;
  final void Function(int day, bool selected) onDayToggled;
  final TextEditingController? daysBeforeController;
  final bool showDaysBefore;
  final VoidCallback onSave;
  // Monthly mode (currently only surfaced for debt_reminder). When
  // mode is null the card renders the regular weekly weekday picker.
  // When set, the card renders the mode switcher + the month-day
  // presets (1 / 15 / last day).
  final String? mode;
  final ValueChanged<String>? onModeChanged;
  final List<int> monthDays;
  final void Function(int day, bool selected)? onMonthDayToggled;

  const _ScheduleCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.isEnabled,
    required this.onToggle,
    required this.time,
    required this.onTimeTap,
    required this.activeDays,
    required this.onDayToggled,
    this.daysBeforeController,
    required this.showDaysBefore,
    required this.onSave,
    this.mode,
    this.onModeChanged,
    this.monthDays = const [],
    this.onMonthDayToggled,
  });

  String get _displayTime {
    final parts = time.split(':');
    if (parts.length < 2) return time;
    return '${parts[0]}:${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: isEnabled,
                  activeColor: AppTheme.successColor,
                  onChanged: onToggle,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildBody(context, theme),
            crossFadeState:
                isEnabled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: theme.dividerTheme.color, height: 1),
          const SizedBox(height: 16),
          Text(
            'وقت التنفيذ',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onTimeTap,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.access_time_rounded),
                hintText: 'اختر الوقت',
              ),
              child: Text(
                _displayTime,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (showDaysBefore) ...[
            const SizedBox(height: 16),
            Text(
              'عدد الأيام قبل الانتهاء',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: daysBeforeController,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.calendar_today_rounded),
                hintText: '1 - 30',
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Mode toggle (only rendered when the card opts in). Debt
          // reminder uses this to switch between weekday-based and
          // monthly day-of-month scheduling.
          if (mode != null && onModeChanged != null) ...[
            Text(
              'نوع التكرار',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ModeOption(
                    label: 'أسبوعي',
                    icon: Icons.date_range_rounded,
                    selected: mode == 'weekly',
                    accent: accentColor,
                    onTap: () => onModeChanged!('weekly'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeOption(
                    label: 'شهري',
                    icon: Icons.calendar_month_rounded,
                    selected: mode == 'monthly',
                    accent: accentColor,
                    onTap: () => onModeChanged!('monthly'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (mode == 'monthly') ...[
            Text(
              'أيام الشهر',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر متى يُرسل خلال الشهر. يمكن اختيار أكثر من خيار.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MonthDayOption(
                  label: 'بداية الشهر (1)',
                  value: 1,
                  selected: monthDays.contains(1),
                  accent: accentColor,
                  onToggle: (v) => onMonthDayToggled?.call(1, v),
                ),
                _MonthDayOption(
                  label: 'منتصف الشهر (15)',
                  value: 15,
                  selected: monthDays.contains(15),
                  accent: accentColor,
                  onToggle: (v) => onMonthDayToggled?.call(15, v),
                ),
                _MonthDayOption(
                  label: 'نهاية الشهر',
                  value: 31,
                  selected: monthDays.contains(31),
                  accent: accentColor,
                  onToggle: (v) => onMonthDayToggled?.call(31, v),
                ),
              ],
            ),
          ] else ...[
            Text(
              'أيام التنفيذ',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(7, (i) {
                final selected = activeDays.contains(i);
                return FilterChip(
                  label: Text(AppHelpers.getArabicWeekday(i)),
                  selected: selected,
                  selectedColor: accentColor.withOpacity(0.15),
                  checkmarkColor: accentColor,
                  onSelected: (v) => onDayToggled(i, v),
                );
              }),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_rounded, size: 20),
            label: const Text('حفظ الجدولة'),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? accent
                : theme.colorScheme.onSurface.withOpacity(0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected
                    ? accent
                    : theme.colorScheme.onSurface.withOpacity(0.55)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Cairo',
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? accent
                    : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthDayOption extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final Color accent;
  final ValueChanged<bool> onToggle;

  const _MonthDayOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.accent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent.withOpacity(0.15),
      checkmarkColor: accent,
      onSelected: onToggle,
    );
  }
}
