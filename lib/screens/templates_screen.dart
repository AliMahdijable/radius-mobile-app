import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/templates_provider.dart';
import '../providers/auth_provider.dart';
import '../models/template_model.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/bottom_sheet_utils.dart';
import '../widgets/app_snackbar.dart';

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(templatesProvider.notifier).loadTemplates();
    });
  }

  // قوالب جاهزة لكل نوع — النقر على زر "توليد" يُعبِّئ محتوى الرسالة بهذه النصوص
  // مع المتغيرات المدعومة حتى يكتمل النص تلقائياً عند الإرسال.
  String _generateTemplate(String type) {
    switch (type) {
      case 'debt_reminder':
        return 'عزيزي {firstname} 🙏\n'
            'نود تذكيركم بوجود مبلغ دين قدره {debt_amount} IQD على حسابكم.\n'
            'الباقة: {package_name}\n'
            'تاريخ الانتهاء: {expiry_date}\n'
            'المتبقي: {days_remaining}\n\n'
            'يرجى التواصل معنا للتسديد. شكراً لتعاونكم 💚';
      case 'expiry_warning':
        return 'تنبيه — اشتراكك على وشك الانتهاء ⏰\n\n'
            'عزيزي {firstname}،\n'
            'باقتكم ({package_name}) ستنتهي خلال {days_remaining}.\n'
            'تاريخ الانتهاء: {expiry_date}\n'
            'سعر التجديد: {package_price} IQD\n\n'
            'يرجى التجديد قبل الانقطاع.';
      case 'service_end':
        return 'انتهاء الاشتراك 🚫\n\n'
            'عزيزي {firstname}،\n'
            'انتهت صلاحية اشتراكك في باقة {package_name} بتاريخ {expiry_date}.\n'
            'سعر التجديد: {package_price} IQD\n\n'
            'نرجو التواصل لتجديد الخدمة.';
      case 'activation_notice':
        return 'تم التفعيل بنجاح ✅\n\n'
            'أهلاً {firstname}،\n'
            'تم تفعيل اشتراكك في {package_name}.\n'
            'السعر: {package_price} IQD\n'
            'المبلغ المدفوع: {paid_amount} IQD\n'
            'تاريخ الانتهاء: {expiry_date}\n'
            'المتبقي: {days_remaining}\n\n'
            'نتمنى لك تجربة ممتازة 🌐';
      case 'renewal':
        return 'تم تمديد الاشتراك 🔄\n\n'
            'عزيزي: {firstname}\n'
            '{username}\n\n'
            'تم تمديد اشتراكك في {package_name}.\n'
            'تاريخ الانتهاء الجديد: {expiry_date}\n'
            'المتبقي: {days_remaining}\n'
            'السعر: {package_price} IQD\n'
            'المبلغ المدفوع: {paid_amount} IQD\n'
            'الدين الحالي: {debt_amount} IQD\n\n'
            'شكراً لاستمراركم معنا 💚';
      case 'payment_confirmation':
        return 'تم استلام تسديد 💳\n\n'
            'عزيزي {firstname}،\n'
            'استلمنا منكم مبلغ {paid_amount} IQD.\n'
            'الدين الحالي: {debt_amount} IQD\n'
            'الرصيد الحالي: {credit_amount} IQD\n\n'
            'شكراً لكم 🙏';
      case 'welcome_message':
        return 'أهلاً بك في خدماتنا 🎉\n\n'
            'مرحباً {firstname}،\n'
            'الباقة: {package_name}\n'
            'اسم المستخدم: {username}\n'
            'رقم الهاتف: {phone}\n'
            'تاريخ الانتهاء: {expiry_date}\n\n'
            'نتمنى لك تجربة رائعة 🌐';
      case 'manager_agent':
        return 'عزيزي المدير {manager_name} 👋\n\n'
            'تم تسجيل حركة مالية على حسابك:\n'
            'النوع: {action_type}\n'
            'المبلغ: {amount} IQD\n'
            'الوصف: {movement_description}\n\n'
            'الرصيد السابق: {previous_credit} IQD\n'
            'الرصيد الحالي: {current_credit} IQD\n'
            'الدين السابق: {previous_debt} IQD\n'
            'الدين الحالي: {current_debt} IQD';
      default:
        return '';
    }
  }

  void _showEditSheet(TemplateModel? template) {
    // Template name is no longer user-entered — it's always the Arabic
    // label of the selected type (مثلاً "إشعار تفعيل"). We keep a controller
    // around only so _saveTemplate has a string to pass, but the UI doesn't
    // render a name field anymore.
    final contentController =
        TextEditingController(text: template?.messageContent ?? '');
    String selectedType = template?.templateType ?? 'debt_reminder';
    final authUser = ref.read(authProvider).user;
    final adminId = authUser?.id ?? '';
    final canManageManagers = authUser?.canAccessManagers ?? false;
    final typeOptions = <String>[
      'debt_reminder', 'expiry_warning', 'service_end',
      'activation_notice', 'renewal', 'payment_confirmation',
      'welcome_message',
      if (canManageManagers) 'manager_agent',
    ];

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final keyboardH = MediaQuery.of(ctx).viewInsets.bottom;
            final safeBottom = bottomSheetBottomInset(ctx, extra: 0) - keyboardH;
            final screenH = MediaQuery.of(ctx).size.height;
            final keyboardOpen = keyboardH > 50;

            void insertVar(String v) {
              final text = contentController.text;
              final sel = contentController.selection;
              final start = sel.isValid ? sel.start : text.length;
              final end = sel.isValid ? sel.end : text.length;
              contentController.text = text.replaceRange(start, end, v);
              contentController.selection =
                  TextSelection.collapsed(offset: start + v.length);
            }

            Widget varChip(String v, {bool compact = false}) {
              final label = TemplateModel.variableLabels[v] ?? v;
              final icon  = TemplateModel.variableIcons[v] ?? '';
              final primary = Theme.of(ctx).colorScheme.primary;
              return GestureDetector(
                onTap: () => insertVar(v),
                child: Container(
                  margin: EdgeInsets.only(left: compact ? 6 : 0),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 8,
                    vertical:   compact ? 6  : 5,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: primary.withOpacity(0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon.isNotEmpty) ...[
                        Text(icon, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: compact ? 12 : 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Sheet peeks at 93% of the screen. With `isScrollControlled`
            // true, Flutter already lifts the sheet above the keyboard —
            // so we don't also subtract keyboardH from the inner padding
            // (that was double-compressing the content and hiding the
            // chips + save button).
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenH * 0.93),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: keyboardOpen ? 0 : safeBottom.clamp(0, 40),
                  left: 20,
                  right: 20,
                  top: 16,
                ),
                // Structure:
                //   [fixed header]  drag handle, title, dropdown
                //   [Expanded scroll] text area + chips — scrollable so
                //                     nothing is clipped by the keyboard
                //   [fixed footer]  save button + keyboard-aware bottom pad
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      template == null ? 'إنشاء قالب' : 'تعديل القالب',
                      style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [

                    // Dropdown (إنشاء فقط)
                    if (template == null) ...[
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'نوع القالب',
                          isDense: true,
                        ),
                        dropdownColor: Theme.of(ctx).scaffoldBackgroundColor,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                        items: typeOptions.map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            TemplateModel.getArabicType(t),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Theme.of(ctx).colorScheme.onSurface,
                            ),
                          ),
                        )).toList(),
                        onChanged: (v) =>
                            setSheetState(() => selectedType = v ?? selectedType),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // زر توليد القالب الجاهز
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'محتوى الرسالة',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            final preset = _generateTemplate(selectedType);
                            if (preset.isEmpty) return;
                            final current = contentController.text.trim();
                            if (current.isNotEmpty) {
                              showDialog<bool>(
                                context: ctx,
                                builder: (dCtx) => AlertDialog(
                                  title: const Text('استبدال المحتوى؟'),
                                  content: const Text(
                                    'المحتوى الحالي سيُستبدل بالقالب الجاهز. هل تريد المتابعة؟',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dCtx, false),
                                      child: const Text('إلغاء'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(dCtx, true),
                                      child: const Text('استبدال'),
                                    ),
                                  ],
                                ),
                              ).then((confirm) {
                                if (confirm == true) {
                                  contentController.text = preset;
                                  setSheetState(() {});
                                }
                              });
                            } else {
                              contentController.text = preset;
                              setSheetState(() {});
                            }
                          },
                          icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                          label: const Text(
                            'توليد قالب جاهز',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // محتوى الرسالة — minLines:5 بدل expands:true عشان
                    // يشتغل داخل الـ SingleChildScrollView؛ يتكبر لو
                    // المحتوى طويل.
                    TextField(
                      controller: contentController,
                      maxLines: null,
                      minLines: 5,
                      textAlignVertical: TextAlignVertical.top,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: 14, height: 1.6, fontFamily: 'Cairo',
                      ),
                      decoration: const InputDecoration(
                        hintText: 'مرحبا {firstname}...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // شريط المتغيرات
                    if (keyboardOpen) ...[
                      // كيبورد مفتوح: شريط أفقي مدمج
                      Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.primary.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(ctx).colorScheme.primary.withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '{ }',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(ctx).colorScheme.primary.withOpacity(0.6),
                                ),
                              ),
                            ),
                            Container(width: 1, height: 24,
                              color: Theme.of(ctx).colorScheme.primary.withOpacity(0.15)),
                            Expanded(
                              child: Builder(builder: (_) {
                                final vars = TemplateModel.variablesForType(selectedType);
                                return ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  itemCount: vars.length,
                                  itemBuilder: (_, i) => varChip(
                                    vars[i],
                                    compact: true,
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // كيبورد مغلق: عنوان + شبكة كاملة
                      Row(children: [
                        const Text('{ }', style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                        const SizedBox(width: 6),
                        Text('المتغيرات', style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          fontFamily: 'Cairo',
                          color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5),
                        )),
                      ]),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: TemplateModel.variablesForType(selectedType)
                            .map((v) => varChip(v))
                            .toList(),
                      ),
                    ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // زر الحفظ — ثابت أسفل الشيت، ما يختفي تحت الكيبورد
                    SizedBox(
                      height: AppTheme.actionButtonHeight,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (contentController.text.isEmpty) {
                            AppSnackBar.warning(
                                context, 'يرجى كتابة محتوى الرسالة');
                            return;
                          }
                          final effectiveType =
                              template?.templateType ?? selectedType;
                          // Auto-name from the type's Arabic label so the
                          // manager doesn't have to type one. Preserve any
                          // previously-saved custom name on edit.
                          final existingName =
                              template?.templateName.trim() ?? '';
                          final autoName = existingName.isNotEmpty
                              ? existingName
                              : TemplateModel.getArabicType(effectiveType);
                          final newTemplate = TemplateModel(
                            id: template?.id,
                            adminId: adminId,
                            templateType: effectiveType,
                            templateName: autoName,
                            messageContent: contentController.text,
                            isActive: template?.isActive ?? true,
                          );
                          final ok = await ref
                              .read(templatesProvider.notifier)
                              .saveTemplate(newTemplate);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            if (ok) {
                              AppSnackBar.success(context, 'تم حفظ القالب');
                            } else {
                              AppSnackBar.error(context, 'فشل حفظ القالب');
                            }
                          }
                        },
                        child: const Text('حفظ القالب'),
                      ),
                    ),
                    SizedBox(height: safeBottom + 6),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templatesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('قوالب الرسائل')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditSheet(null),
        child: const Icon(Icons.add),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.templates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined,
                          size: 64,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      const Text('لا توجد قوالب'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showEditSheet(null),
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء قالب'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(templatesProvider.notifier).loadTemplates(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.templates.length,
                    itemBuilder: (context, index) {
                      final tmpl = state.templates[index];
                      return GestureDetector(
                        onTap: () => _showEditSheet(tmpl),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.description, size: 18,
                                    color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(tmpl.templateName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700, fontSize: 13)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4)),
                                        child: Text(
                                          TemplateModel.getArabicType(tmpl.templateType),
                                          style: TextStyle(fontSize: 9,
                                              color: theme.colorScheme.primary)),
                                      ),
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(tmpl.messageContent,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11,
                                            color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: tmpl.isActive,
                                activeColor: AppTheme.successColor,
                                onChanged: (v) {
                                  ref.read(templatesProvider.notifier)
                                      .toggleTemplate(tmpl.templateType, v);
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: theme.colorScheme.error, size: 20),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 34, minHeight: 34),
                                tooltip: 'حذف القالب',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('حذف القالب'),
                                      content: Text(
                                          'هل تريد حذف القالب "${tmpl.templateName}"؟'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dCtx, false),
                                          child: const Text('إلغاء'),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                theme.colorScheme.error,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(dCtx, true),
                                          child: const Text('حذف'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true) return;
                                  final ok = await ref
                                      .read(templatesProvider.notifier)
                                      .deleteTemplate(tmpl.templateType);
                                  if (!context.mounted) return;
                                  if (ok) {
                                    AppSnackBar.success(
                                        context, 'تم حذف القالب');
                                  } else {
                                    AppSnackBar.error(
                                        context, 'فشل حذف القالب');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
