import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/network_devices_api.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/device_region.dart';
import '../../models/network_device.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import 'regions_screen.dart';
import '../../theme/typography.dart';

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
  int? _regionId;
  List<DeviceRegion> _regions = const [];
  bool _regionsLoaded = false;

  bool _obscurePassword = true;
  bool _submitting = false;

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
    _regionId = e?.regionId;

    if (e != null && e.hasCredentials) _loadCredentials(e.id);
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final list = await NetworkDevicesApi.listRegions();
      if (!mounted) return;
      setState(() {
        _regions = list;
        _regionsLoaded = true;
      });
    } catch (_) {
      // silent — dropdown يبقى فاضي، المستخدم يضيف يدوياً من شاشة المناطق
      if (mounted) setState(() => _regionsLoaded = true);
    }
  }

  /// يفتح شاشة إدارة المناطق ثم يُعيد تحميل القائمة عند العودة.
  Future<void> _openRegionsAndReload() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RegionsScreen()),
    );
    if (mounted) await _loadRegions();
  }

  Future<void> _loadCredentials(int deviceId) async {
    try {
      final creds = await NetworkDevicesApi.getCredentials(deviceId);
      if (!mounted) return;
      setState(() {
        _userCtrl.text = (creds['user'] ?? '').toString();
        _passCtrl.text = (creds['pass'] ?? '').toString();
        _communityCtrl.text = (creds['community'] ?? 'public').toString();
        _snmpVersion = (creds['version'] ?? 'v2c').toString();
      });
    } catch (_) {
      // فشل جلب بيانات الدخول: الحقول تبقى فارغة والمستخدم يملؤها يدويّاً.
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
        'region_id': _regionId,
        'model': _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        'mac': _macCtrl.text.trim().isEmpty ? null : _macCtrl.text.trim(),
        'location': _locationCtrl.text.trim().isEmpty
            ? null
            : _locationCtrl.text.trim(),
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'credentials': _buildCredentials(),
      };
      final saved = widget.existing == null
          ? await NetworkDevicesApi.create(body)
          : await NetworkDevicesApi.update(widget.existing!.id, body);
      // 2026-08-18: invalidate credentials cache — قد يكون المستخدم غيّرها
      if (widget.existing != null) {
        NetworkDevicesApi.invalidateCredentialsCache(widget.existing!.id);
      }
      if (!mounted) return;
      showSheetSnack(
          context, widget.existing == null ? 'تم إضافة الجهاز' : 'تم الحفظ');
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      showSheetSnack(context, e.toString().replaceFirst('Exception: ', ''),
          isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onProtocolChanged(String? v) {
    setState(() {
      _protocol = v;
      if (v != null) {
        // المنفذ يعتمد على البراند + البروتوكول (Mikrotik≠UBNT للـapi)
        _apiPortCtrl.text =
            NetworkDeviceLabels.portForBrandProtocol(_brand, v).toString();
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
    return DesignSheet(
      header: SheetHeaderBar(
        icon: widget.existing == null ? LucideIcons.plus : LucideIcons.pencil,
        title: widget.existing == null ? 'إضافة جهاز جديد' : 'تعديل الجهاز',
        subtitle: '',
        onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: widget.existing == null ? 'إضافة الجهاز' : 'حفظ التعديلات',
        icon: LucideIcons.check,
        busy: _submitting,
        onPressed: _submit,
      ),
      maxHeightFactor: 0.95,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
          children: [
            _sectionTitle('المعلومات الأساسيّة'),
            const SizedBox(height: 8),
            _textField(_nameCtrl, 'اسم الجهاز *',
                hint: 'مثلاً: راوتر الطابق الثاني',
                icon: LucideIcons.tag,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _dropdown(
                      'النوع *',
                      _type,
                      NetworkDeviceLabels.types.entries.toList(),
                      (v) => setState(() => _type = v))),
              const SizedBox(width: 10),
              Expanded(
                  child: _dropdown(
                      'البراند *',
                      _brand,
                      NetworkDeviceLabels.brands.entries.toList(),
                      _onBrandChanged)),
            ]),
            const SizedBox(height: 10),
            // 2026-08-18: dropdown مخصّص لأجهزة UBNT — يحدّد الموديل
            // بشكل حاسم فيحدّد أي Live Panel نعرض (AF60 vs classic).
            // الأنواع الأخرى تبقى بحقل نصّي حرّ كما كانت.
            if (_brand == 'ubnt')
              _ubntModelPicker()
            else
              _textField(_modelCtrl, 'الموديل',
                  hint: 'مثلاً: RB4011، PBE-5AC، A5c', icon: LucideIcons.info),
            const SizedBox(height: 10),
            _textField(_locationCtrl, 'الموقع (اختياري)',
                hint: 'مثلاً: البرج الشمالي - قطاع 3',
                icon: LucideIcons.mapPin),
            const SizedBox(height: 10),
            _regionDropdown(),

            const SizedBox(height: Sp.xl),
            _sectionTitle('الشبكة'),
            const SizedBox(height: 8),
            _textField(_ipCtrl, 'عنوان IP *',
                hint: '192.168.1.1',
                icon: LucideIcons.globe,
                // 2026-08-25: numberWithOptions(decimal:true) يُظهر نقطة
                // على iOS numeric keypad — TextInputType.number لا يُظهرها
                // (يظهر فقط 0-9 كأنّه رقم تلفون).
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false), validator: (v) {
              if (v == null || v.trim().isEmpty) return 'مطلوب';
              if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(v.trim())) {
                return 'IP غير صالح';
              }
              return null;
            }),
            const SizedBox(height: 10),
            _textField(_macCtrl, 'MAC (اختياري)',
                hint: 'AA:BB:CC:DD:EE:FF', icon: LucideIcons.fingerprint),

            const SizedBox(height: Sp.xl),
            _sectionTitle('بروتوكول الإدارة (اختياري — للمرحلة القادمة)'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(color: AppColors.brandSoftBorder),
              ),
              child: Row(children: [
                Icon(LucideIcons.info, size: 14, color: AppColors.info),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(
                  'الفحص (ICMP ping) يعمل تلقائيّاً بدون credentials. هذا القسم فقط لإدارة الجهاز في المرحلة القادمة (interfaces / traffic / reboot).',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textMid, height: 1.4),
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
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(R.pill),
            )),
        const SizedBox(width: 8),
        Text(text,
            style: AppType.rowLabelBold()),
      ]);

  Widget _protocolSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brand : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: active ? AppColors.brand : AppColors.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14, color: active ? AppColors.onBrand : AppColors.textMid),
          const SizedBox(width: 6),
          Text(label,
              style: AppType.bodyStrong(color: active ? AppColors.onBrand : AppColors.textHi)),
        ]),
      ),
    );
  }

  Widget _credentialsSection() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.keyRound, size: 14, color: AppColors.brand),
          const SizedBox(width: 6),
          Text(
            'بيانات الاتصال (${NetworkDeviceLabels.protocolLabel(_protocol!)})',
            style: AppType.pillBold(color: AppColors.textHi),
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
              'mikrotik' =>
                '💡 Mikrotik API الافتراضي 8728 — فعّله بـ/ip service enable api',
              'ubnt' =>
                '💡 UBNT يستعمل SSH (port 22) — يعمل على airOS 5/6/7/8 كلها. نفس user/pass للـweb.',
              'mimosa' => '💡 Mimosa يستعمل HTTPS 443 — أدخل admin credentials',
              _ => '💡 تأكّد من تفعيل API service على الجهاز',
            },
            style: TextStyle(fontSize: 9.5, height: 1.2, color: AppColors.textLow),
          ),
        ],
        const SizedBox(height: 10),
        if (_protocol == 'snmp') ..._snmpFields() else ..._userPassFields(),
      ]),
    );
  }

  List<Widget> _userPassFields() => [
        _textField(_userCtrl, 'اسم المستخدم (اختياري لبعض UBNT)',
            hint: 'admin أو ubnt', icon: LucideIcons.user),
        const SizedBox(height: 10),
        TextFormField(
          controller: _passCtrl,
          obscureText: _obscurePassword,
          decoration:
              _inputDecoration('كلمة المرور', icon: LucideIcons.lock).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                  _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                  size: 18),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ];

  List<Widget> _snmpFields() => [
        Row(children: [
          Text('SNMP version:',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textMid)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('v2c', style: TextStyle(fontSize: 11, height: 1.35)),
            selected: _snmpVersion == 'v2c',
            onSelected: (_) => setState(() => _snmpVersion = 'v2c'),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('v3', style: TextStyle(fontSize: 11, height: 1.35)),
            selected: _snmpVersion == 'v3',
            onSelected: (_) => setState(() => _snmpVersion = 'v3'),
          ),
        ]),
        const SizedBox(height: 10),
        _textField(_communityCtrl, 'Community string',
            hint: 'public', icon: LucideIcons.key),
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

  InputDecoration _inputDecoration(String label,
      {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon:
          icon != null ? Icon(icon, size: 18, color: AppColors.textLow) : null,
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceInput,
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
      initialValue: value,
      isExpanded: true,
      decoration: _inputDecoration(label),
      items: items
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  /// UBNT model picker — يحدّد الموديل بشكل حاسم فيقرّر أي Live Panel نعرض.
  /// - "airFiber 60 LR/XR/GP/Lite" → AirFiber60LivePanel (بانل 60 GHz)
  /// - "AF-60-XG" → UbntLivePanel (رغم اسمه — لأنه 5 GHz backhaul!)
  /// - "AirMax classic" أو "أخرى" → UbntLivePanel (airOS العادي)
  ///
  /// 2026-08-18: أُضيف لأنّ اسم الجهاز وحده (مثل "لنك 12") لا يكفي للتخمين.
  Widget _ubntModelPicker() {
    // خيارات موحّدة — key = القيمة الي تُحفظ في model field
    // (كلها تحوي "AF-60" أو "airMax" الي يفهمها _isAirFiber60)
    const presets = <MapEntry<String, String>>[
      MapEntry('', 'لم يُحدَّد — اكتب أدناه'),
      MapEntry('AF-60-LR', 'AirFiber 60 LR (60 GHz — Long Range)'),
      MapEntry('AF-60-XR', 'AirFiber 60 XR (60 GHz — Extreme Range)'),
      MapEntry('AF-60-GP', 'AirFiber 60 GP (60 GHz)'),
      MapEntry('AF-60-Lite', 'AirFiber 60 Lite (60 GHz)'),
      MapEntry('AF-60-XG', 'AF-60-XG (5 GHz backhaul ⚠️ ليس 60 GHz)'),
      MapEntry('AirMax', 'AirMax classic (PBE / NanoBeam / LiteBeam ...)'),
    ];
    // القيمة الحاليّة — نطابقها مع presets، وإلا نعتبرها "أخرى/مخصّص"
    // 2026-08-18: normalization مهم — items تستعمل null للـempty (لأن
    // Flutter DropdownButton يرفض قيمتَين متطابقتَين). لذا نضمن أن
    // matchedKey null للفارغ + للـcustom text (الي مو في presets).
    final current = _modelCtrl.text.trim();
    final String? matchedKey = current.isEmpty
        ? null
        : (presets.skip(1).any((p) => p.key == current) ? current : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: matchedKey,
          isExpanded: true,
          decoration: _inputDecoration('موديل UBNT'),
          hint: current.isEmpty
              ? const Text('اختر الموديل')
              : Text('مخصّص: $current', overflow: TextOverflow.ellipsis),
          items: [
            for (final p in presets)
              DropdownMenuItem<String?>(
                value: p.key.isEmpty ? null : p.key,
                child: Text(p.value,
                    style: const TextStyle(fontSize: 13, height: 1.45),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            _modelCtrl.text = v ?? '';
          }),
        ),
        // حقل نصّي حرّ للـmodels غير المدرجة
        const SizedBox(height: 8),
        _textField(_modelCtrl, 'أو اكتب الموديل يدوياً',
            hint: 'مثلاً: PBE-5AC-500، NBE-5AC-Gen2', icon: LucideIcons.info),
      ],
    );
  }

  /// dropdown المنطقة — null = بدون منطقة. القائمة تُحمَّل asynchronously من backend.
  ///
  /// 3 حالات:
  /// 1. قيد التحميل → dropdown مبسّط ("بدون منطقة" فقط)
  /// 2. مُحمَّلة وفارغة → CTA card "أنشئ منطقة أوّلاً" بدل الـdropdown
  /// 3. مُحمَّلة وفيها مناطق → dropdown كامل + item "+ إدارة المناطق" بالنهاية
  Widget _regionDropdown() {
    // Empty state — لا مناطق موجودة
    if (_regionsLoaded && _regions.isEmpty) {
      return InkWell(
        onTap: _openRegionsAndReload,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: AppColors.brandSoftBorder,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.brandSoftBg,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.mapPinPlus,
                  size: 18, color: AppColors.brand),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('لا توجد مناطق بعد',
                      style: AppType.bodyBold()),
                  const SizedBox(height: 2),
                  Text('اضغط لإنشاء منطقة (مثل: كرخ / رصافة / ...)',
                      style: AppType.muted(color: AppColors.textMid)),
                ],
              ),
            ),
            Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.brand),
          ]),
        ),
      );
    }

    // Dropdown عادي
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Row(children: [
          Icon(LucideIcons.slash, size: 14, color: AppColors.textLow),
          const SizedBox(width: 6),
          Text('بدون منطقة',
              style: AppType.subtitle()),
        ]),
      ),
      for (final r in _regions)
        DropdownMenuItem<int?>(
          value: r.id,
          child: Row(children: [
            Icon(LucideIcons.mapPin,
                size: 14, color: _parseRegionColor(r.color) ?? AppColors.brand),
            const SizedBox(width: 6),
            Expanded(child: Text(r.name, overflow: TextOverflow.ellipsis)),
            if (r.deviceCount > 0)
              Text(' (${r.deviceCount})',
                  style: AppType.muted()),
          ]),
        ),
    ];
    // لو الجهاز الحالي عنده region_id ما موجود في القائمة (لسّه تُحمَّل، أو
    // المستخدم حذف منطقة من شاشة أخرى) → أضف item مؤقّت بنفس الـid لتفادي assertion.
    // 2026-08-18: نميّز بين "قيد التحميل" و"محذوفة" — لو التحميل تمّ ولم نجدها
    // فهي محذوفة فعلاً، نعرض label واضح مع لون تحذيري.
    if (_regionId != null && !_regions.any((r) => r.id == _regionId)) {
      items.add(DropdownMenuItem<int?>(
        value: _regionId,
        child: Row(children: [
          Icon(
            _regionsLoaded ? LucideIcons.triangleAlert : LucideIcons.loader,
            size: 14,
            color: _regionsLoaded ? AppColors.warning : AppColors.textLow,
          ),
          const SizedBox(width: 6),
          Text(
            _regionsLoaded ? 'منطقة محذوفة' : 'قيد التحميل...',
            style: AppType.subtitle(color: _regionsLoaded ? AppColors.warning : AppColors.textLow),
          ),
        ]),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int?>(
          initialValue: _regionId,
          isExpanded: true,
          decoration: _inputDecoration('المنطقة'),
          items: items,
          onChanged: (v) => setState(() => _regionId = v),
        ),
        // زرّ صغير أسفل الـdropdown لإدارة المناطق (إضافة/تعديل/حذف)
        if (_regionsLoaded && _regions.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _openRegionsAndReload,
              icon:
                  Icon(LucideIcons.settings2, size: 14, color: AppColors.brand),
              label: Text('إدارة المناطق',
                  style: TextStyle(color: AppColors.brand, fontSize: 12.5, height: 1.4)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
      ],
    );
  }
}

Color? _parseRegionColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}
