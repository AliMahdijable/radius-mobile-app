import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/schedules_provider.dart';
import '../models/schedule_model.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';

class SchedulesScreen extends ConsumerStatefulWidget {
  const SchedulesScreen({super.key});

  @override
  ConsumerState<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends ConsumerState<SchedulesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(schedulesProvider.notifier).loadSchedules();
    });
  }

  void _showEditScheduleSheet(ScheduleModel? schedule) {
    final typeController = TextEditingController(
      text: schedule?.scheduleType ?? 'debt_reminder',
    );
    final timeController = TextEditingController(
      text: schedule?.scheduledTime ?? '12:00:00',
    );
    final daysBeforeController = TextEditingController(
      text: schedule?.daysBefore?.toString() ?? '3',
    );
    List<int> activeDays = schedule?.activeDays ?? [0, 1, 2, 3, 4, 5, 6];
    String selectedType = schedule?.scheduleType ?? 'debt_reminder';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                schedule == null ? 'إضافة جدولة' : 'تعديل الجدولة',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 20),

              if (schedule == null) ...[
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'نوع الجدولة'),
                  items: const [
                    DropdownMenuItem(
                      value: 'debt_reminder',
                      child: Text('تذكير ديون'),
                    ),
                    DropdownMenuItem(
                      value: 'expiry_warning',
                      child: Text('تحذير انتهاء'),
                    ),
                  ],
                  onChanged: (v) =>
                      setSheetState(() => selectedType = v ?? selectedType),
                ),
                const SizedBox(height: 16),
              ],

              // Time picker
              InkWell(
                onTap: () async {
                  final parts = timeController.text.split(':');
                  final initial = TimeOfDay(
                    hour: int.tryParse(parts[0]) ?? 12,
                    minute: int.tryParse(parts[1]) ?? 0,
                  );
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: initial,
                  );
                  if (picked != null) {
                    setSheetState(() {
                      timeController.text =
                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'وقت التنفيذ (بتوقيت بغداد)',
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  child: Text(timeController.text),
                ),
              ),
              const SizedBox(height: 16),

              // Days
              Text('أيام التنفيذ',
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final isSelected = activeDays.contains(i);
                  return FilterChip(
                    label: Text(AppHelpers.getArabicWeekday(i)),
                    selected: isSelected,
                    onSelected: (v) {
                      setSheetState(() {
                        if (v) {
                          activeDays.add(i);
                        } else {
                          activeDays.remove(i);
                        }
                      });
                    },
                  );
                }),
              ),

              if (selectedType == 'expiry_warning') ...[
                const SizedBox(height: 16),
                TextField(
                  controller: daysBeforeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد الأيام قبل الانتهاء',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final adminId = schedule?.adminId ?? '';
                  final newSchedule = ScheduleModel(
                    id: schedule?.id,
                    adminId: adminId,
                    scheduleType: selectedType,
                    isEnabled: schedule?.isEnabled ?? true,
                    scheduledTime: timeController.text,
                    activeDays: activeDays..sort(),
                    daysBefore: selectedType == 'expiry_warning'
                        ? int.tryParse(daysBeforeController.text)
                        : null,
                    executionCount: schedule?.executionCount ?? 0,
                  );
                  final ok = await ref
                      .read(schedulesProvider.notifier)
                      .saveSchedule(newSchedule);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text(ok ? 'تم حفظ الجدولة' : 'فشل حفظ الجدولة'),
                    ));
                  }
                },
                child: const Text('حفظ'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(schedulesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('الجدولة')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditScheduleSheet(null),
        child: const Icon(Icons.add),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.schedules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule,
                          size: 64,
                          color: theme.colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      const Text('لا توجد جدولة'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(schedulesProvider.notifier).loadSchedules(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.schedules.length,
                    itemBuilder: (context, index) {
                      final schedule = state.schedules[index];
                      final typeColor = schedule.scheduleType == 'debt_reminder'
                          ? AppTheme.warningColor
                          : AppTheme.dangerColor;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color:
                              theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  schedule.scheduleType == 'debt_reminder'
                                      ? Icons.credit_card
                                      : Icons.warning_amber,
                                  color: typeColor,
                                ),
                              ),
                              title: Text(
                                ScheduleModel.getArabicType(
                                    schedule.scheduleType),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'الوقت: ${schedule.scheduledTime} • التنفيذ: ${schedule.executionCount}',
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: Switch.adaptive(
                                value: schedule.isEnabled,
                                activeColor: AppTheme.successColor,
                                onChanged: (v) {
                                  ref
                                      .read(schedulesProvider.notifier)
                                      .toggleSchedule(
                                          schedule.scheduleType, v);
                                },
                              ),
                              onTap: () =>
                                  _showEditScheduleSheet(schedule),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  ...List.generate(7, (i) {
                                    final active =
                                        schedule.activeDays.contains(i);
                                    return Container(
                                      width: 30,
                                      height: 30,
                                      margin: const EdgeInsets.only(left: 4),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? typeColor.withOpacity(0.15)
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                          color: active
                                              ? typeColor.withOpacity(0.3)
                                              : theme.colorScheme.onSurface
                                                  .withOpacity(0.1),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          AppHelpers.getArabicWeekday(i)[0],
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: active
                                                ? typeColor
                                                : theme
                                                    .colorScheme.onSurface
                                                    .withOpacity(0.3),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_outline,
                                        size: 20),
                                    onPressed: () async {
                                      final ok = await ref
                                          .read(schedulesProvider.notifier)
                                          .triggerSchedule(
                                              schedule.scheduleType);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(ok
                                              ? 'تم تشغيل الجدولة'
                                              : 'فشل التشغيل'),
                                        ));
                                      }
                                    },
                                    tooltip: 'تشغيل الآن',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
