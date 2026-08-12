import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';

/// bottom sheet لإضافة/تعديل جهاز شبكة — مع اختيار protocol + credentials.
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
  late final TextEditingController _apiPortCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _macCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _communityCtrl;

  late String _type;
  late String _brand;
  String? _protocol;
  String _snmpVersion = 'v2c';

  bool _obscurePassword = true;
  bool _submitting = false;
  bool _loadingCreds = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _ipCtrl = TextEditingController(text: e?.ip ?? '');
    _portCtrl = TextEditingController(text: e?.port.toString() ?? '80');
    _apiPortCtrl = TextEditingController(text: e?.apiPort?.toString() ?? '');
    _modelCtrl = TextEditingController(text: e?.model ?? '');
    _macCtrl = TextEditingController(text: e?.mac ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _communityCtrl = TextEditingController(text: 'public');
    _type = e?.type ?? 'router';
    _brand = e?.brand ?? 'mikrotik';
    _protocol = e?.protocol;

    if (e != null && e.hasCredentials) _loadCredentials(e.id);
  }

  Future<void> _loadCredentials(int deviceId) async {
    setState(() => _loadingCreds = true);
    try {
      final creds = await NetworkDevicesApi.getCredentials(deviceId);
      if (!mounted) return;
      setState(() {
        _userCtrl.text = (creds['user'] ?? '').toString();
        _passCtrl.text = (creds['pass'] ?? '').toString();
        _communityCtrl.text = (creds['community'] ?? 'public').toString();
        _snmpVersion = (creds['version'] ?? 'v2c').toString();
        _loadingCreds = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCreds = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _apiPortCtrl.dispose();
    _modelCtrl.dispose();
    _macCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _communityCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _buildCredentials() {
    if (_protocol == null) return null;
    if (_protocol == 'snmp') {
      final community = _communityCtrl.text.trim();
      if (community.isEmpty) return null;
      return {'community': community, 'version': _snmpVersion};
    }
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    // نحفظ حتى لو user فارغ (بعض UBNT airFiber بلا user) — يكفي password
    if (u.isEmpty && p.isEmpty) return null;
    return {'user': u, 'pass': p};
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
        'api_port': int.tryParse(_apiPortCtrl.text.trim()),
        'protocol': _protocol,
        'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        'mac': _macCtrl.text.trim().isEmpty ? null : _macCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'credentials': _buildCredentials(),
      };
      final saved = widget.existing == null
          ? await NetworkDevicesApi.create(body)
          : await NetworkDevicesApi.update(widget.existing!.id, body);
      if (!mounted) return;
      showSheetSnack(context, widget.existing == null ? 'تم إضافة الجهاز' : 'تم الحفظ');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      showSheetSnack(context, e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onProtocolChanged(String? v) {
    setState(() {
      _protocol = v;
      if (v != null) {
        // المنفذ يعتمد على البراند + البروتوكول (Mikrotik≠UBNT للـapi)
        _apiPortCtrl.text = NetworkDeviceLabels.portForBrandProtocol(_brand, v).toString();
      }
    });
  }

  /// عند تغيير البراند: نحدّث المنفذ الافتراضي **فقط** لو المستخدم لم يعدّله
  /// يدوياً. لو الحقل فاضي أو يحمل قيمة default معروفة → نُحدّثها.
  /// وإلا نحترم اختيار المستخدم (كان يمسحه بلا سؤال — طلب مستخدم 2026-08-13).
  static const _defaultApiPorts = {'8728', '22', '443', '80', '161', '23'};

  void _onBrandChanged(String v) {
    setState(() {
      _brand = v;
      if (_protocol == 'api') {
        final current = _apiPortCtrl.text.trim();
        final isDefault = current.isEmpty || _defaultApiPorts.contains(current);
        if (isDefault) {
          _apiPortCtrl.text =
              NetworkDeviceLabels.portForBrandProtocol(v, _protocol).toString();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          _dragHandle(),
          _header(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(Sp.lg),
                children: [
                  _sectionTitle('المعلومات الأساسيّة'),
                  const SizedBox(height: 8),
                  _textField(_nameCtrl, 'اسم الجهاز *',
                      hint: 'مثلاً: راوتر الطابق الثاني',
                      icon: LucideIcons.tag,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _dropdown('النوع *', _type,
                        NetworkDeviceLabels.types.entries.toList(),
                        (v) => setState(() => _type = v))),
                    const SizedBox(width: 10),
                    Expanded(child: _dropdown('البراند *', _brand,
                        NetworkDeviceLabels.brands.entries.toList(),
                        _onBrandChanged)),
                  ]),
                  const SizedBox(height: 10),
                  _textField(_modelCtrl, 'الموديل',
                      hint: 'مثلاً: RB4011، PBE-5AC، A5c',
                      icon: LucideIcons.info),
                  const SizedBox(height: 10),
                  _textField(_locationCtrl, 'الموقع (اختياري)',
                      hint: 'مثلاً: البرج الشمالي - قطاع 3',
                      icon: LucideIcons.mapPin),

                  const SizedBox(height: Sp.xl),
                  _sectionTitle('الشبكة'),
                  const SizedBox(height: 8),
                  _textField(_ipCtrl, 'عنوان IP *',
                      hint: '192.168.1.1',
                      icon: LucideIcons.globe,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'مطلوب';
                        if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(v.trim())) {
                          return 'IP غير صالح';
                        }
                        return null;
                      }),
                  const SizedBox(height: 10),
                  _textField(_macCtrl, 'MAC (اختياري)',
                      hint: 'AA:BB:CC:DD:EE:FF',
                      icon: LucideIcons.fingerprint),

                  const SizedBox(height: Sp.xl),
                  _sectionTitle('بروتوكول الإدارة (اختياري — للمرحلة القادمة)'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(LucideIcons.info, size: 14, color: const Color(0xFF06B6D4)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        'الفحص (ICMP ping) يعمل تلقائيّاً بدون credentials. هذا القسم فقط لإدارة الجهاز في المرحلة القادمة (interfaces / traffic / reboot).',
                        style: TextStyle(fontSize: 11, color: AppColors.textMid, height: 1.4),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  _protocolSelector(),
                  const SizedBox(height: 12),
                  if (_protocol != null) _credentialsSection(),

                  const SizedBox(height: Sp.xl),
                  _sectionTitle('ملاحظات (اختياري)'),
                  const SizedBox(height: 8),
                  _textField(_notesCtrl, 'ملاحظات', maxLines: 3),

                  const SizedBox(height: Sp.xl),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(LucideIcons.check, size: 18),
                      label: Text(widget.existing == null ? 'إضافة الجهاز' : 'حفظ التعديلات'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.lg),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dragHandle() => Container(
        margin: const EdgeInsets.only(top: 8),
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: AppColors.textLow.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
        child: Row(children: [
          Icon(widget.existing == null ? LucideIcons.plus : LucideIcons.pencil,
              color: AppColors.brand, size: 20),
          const SizedBox(width: 8),
          Text(
            widget.existing == null ? 'إضافة جهاز جديد' : 'تعديل الجهاز',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textHi),
          ),
          const Spacer(),
          if (_loadingCreds)
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand),
            ),
        ]),
      );

  Widget _sectionTitle(String text) => Row(children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(
          color: AppColors.brand, borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textHi)),
      ]);

  Widget _protocolSelector() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        _protoOption(null, 'ICMP فقط (افتراضي)', LucideIcons.zap),
        _protoOption('api', 'API', LucideIcons.globe),
        _protoOption('ssh', 'SSH', LucideIcons.terminal),
        _protoOption('telnet', 'Telnet', LucideIcons.monitor),
        _protoOption('snmp', 'SNMP', LucideIcons.activity),
      ],
    );
  }

  Widget _protoOption(String? value, String label, IconData icon) {
    final active = _protocol == value;
    return InkWell(
      onTap: () => _onProtocolChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.brand : AppColors.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? Colors.white : AppColors.textMid),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textHi,
          )),
        ]),
      ),
    );
  }

  Widget _credentialsSection() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.keyRound, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(
            'بيانات الاتصال (${NetworkDeviceLabels.protocolLabel(_protocol!)})',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textHi),
          ),
        ]),
        const SizedBox(height: 10),
        _textField(_apiPortCtrl, 'المنفذ',
            icon: LucideIcons.plug,
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly]),
        if (_protocol == 'api') ...[
          const SizedBox(height: 4),
          Text(
            switch (_brand) {
              'mikrotik' => '💡 Mikrotik API الافتراضي 8728 — فعّله بـ/ip service enable api',
              'ubnt' => '💡 UBNT يستعمل SSH (port 22) — يعمل على airOS 5/6/7/8 كلها. نفس user/pass للـweb.',
              'mimosa' => '💡 Mimosa يستعمل HTTPS 443 — أدخل admin credentials',
              _ => '💡 تأكّد من تفعيل API service على الجهاز',
            },
            style: TextStyle(fontSize: 9, color: AppColors.textLow),
          ),
        ],
        const SizedBox(height: 10),
        if (_protocol == 'snmp') ..._snmpFields() else ..._userPassFields(),
      ]),
    );
  }

  List<Widget> _userPassFields() => [
        _textField(_userCtrl, 'اسم المستخدم (اختياري لبعض UBNT)', hint: 'admin أو ubnt', icon: LucideIcons.user),
        const SizedBox(height: 10),
        TextFormField(
          controller: _passCtrl,
          obscureText: _obscurePassword,
          decoration: _inputDecoration('كلمة المرور', icon: LucideIcons.lock).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ];

  List<Widget> _snmpFields() => [
        Row(children: [
          Text('SNMP version:', style: TextStyle(fontSize: 12, color: AppColors.textMid)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('v2c', style: TextStyle(fontSize: 11)),
            selected: _snmpVersion == 'v2c',
            onSelected: (_) => setState(() => _snmpVersion = 'v2c'),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('v3', style: TextStyle(fontSize: 11)),
            selected: _snmpVersion == 'v3',
            onSelected: (_) => setState(() => _snmpVersion = 'v3'),
          ),
        ]),
        const SizedBox(height: 10),
        _textField(_communityCtrl, 'Community string', hint: 'public', icon: LucideIcons.key),
      ];

  Widget _textField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    IconData? icon,
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
      decoration: _inputDecoration(label, hint: hint, icon: icon),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: AppColors.textLow) : null,
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceInput,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.brand, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      decoration: _inputDecoration(label),
      items: items.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}
