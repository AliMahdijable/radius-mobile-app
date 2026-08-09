import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// bottom sheet لإضافة/تعديل جهاز شبكة. راجع project_devices_monitoring_plan.
class NetworkDeviceFormSheet extends StatefulWidget {
  final NetworkDevice? existing;
  const NetworkDeviceFormSheet({super.key, this.existing});

  @override
  State<NetworkDeviceFormSheet> createState() => _NetworkDeviceFormSheetState();
}

class _NetworkDeviceFormSheetState extends State<NetworkDeviceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _macCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;

  late String _type;
  late String _brand;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _ipCtrl = TextEditingController(text: e?.ip ?? '');
    _portCtrl = TextEditingController(text: e?.port.toString() ?? '80');
    _modelCtrl = TextEditingController(text: e?.model ?? '');
    _macCtrl = TextEditingController(text: e?.mac ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _type = e?.type ?? 'router';
    _brand = e?.brand ?? 'mikrotik';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _modelCtrl.dispose();
    _macCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'type': _type,
        'brand': _brand,
        'ip': _ipCtrl.text.trim(),
        'port': int.tryParse(_portCtrl.text.trim()) ?? 80,
        'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        'mac': _macCtrl.text.trim().isEmpty ? null : _macCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };
      final saved = widget.existing == null
          ? await NetworkDevicesApi.create(body)
          : await NetworkDevicesApi.update(widget.existing!.id, body);
      if (!mounted) return;
      showSheetSnack(context,
          widget.existing == null ? 'تم إضافة الجهاز' : 'تم الحفظ');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      showSheetSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(widget.existing == null ? LucideIcons.plus : LucideIcons.pencil,
                      color: AppColors.brand, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    widget.existing == null ? 'إضافة جهاز جديد' : 'تعديل جهاز',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _textField(_nameCtrl, 'اسم الجهاز *',
                        hint: 'مثلاً: راوتر الطابق الثاني',
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
                    const SizedBox(height: 12),

                    // النوع + البراند side by side
                    Row(children: [
                      Expanded(child: _dropdown('النوع *', _type,
                          NetworkDeviceLabels.types.entries.toList(),
                          (v) => setState(() => _type = v))),
                      const SizedBox(width: 12),
                      Expanded(child: _dropdown('البراند *', _brand,
                          NetworkDeviceLabels.brands.entries.toList(),
                          (v) => setState(() => _brand = v))),
                    ]),
                    const SizedBox(height: 12),

                    // IP + Port
                    Row(children: [
                      Expanded(flex: 3, child: _textField(_ipCtrl, 'عنوان IP *',
                          hint: '192.168.1.1',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'مطلوب';
                            if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(v.trim())) {
                              return 'IP غير صالح';
                            }
                            return null;
                          })),
                      const SizedBox(width: 12),
                      Expanded(child: _textField(_portCtrl, 'المنفذ',
                          hint: '80',
                          keyboardType: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly])),
                    ]),
                    const SizedBox(height: 12),

                    _textField(_modelCtrl, 'الموديل', hint: 'مثلاً: RB4011, PBE-5AC'),
                    const SizedBox(height: 12),
                    _textField(_macCtrl, 'MAC (اختياري)', hint: 'AA:BB:CC:DD:EE:FF'),
                    const SizedBox(height: 12),
                    _textField(_locationCtrl, 'الموقع (اختياري)',
                        hint: 'مثلاً: المكتب - طابق 2'),
                    const SizedBox(height: 12),
                    _textField(_notesCtrl, 'ملاحظات (اختياري)', maxLines: 3),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(LucideIcons.check, size: 18),
                        label: Text(widget.existing == null ? 'إضافة' : 'حفظ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    int? maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<MapEntry<String, String>> items,
    ValueChanged<String> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}
