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
                      onToggle: (v) {
                        ref
                            .read(schedulesProvider.notifier)
                            .toggleSchedule('expiry_warning', v);
                      },
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
                      onToggle: (v) {
                        ref
                            .read(schedulesProvider.notifier)
                            .toggleSchedule('debt_reminder', v);
                      },
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
