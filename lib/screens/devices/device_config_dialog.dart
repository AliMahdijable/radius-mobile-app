import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/device_config.dart';
import '../../providers/device_provider.dart';

/// Edit modal for a subscriber's CPE credentials. Opened from the gear
/// icon on the connection-status card. Per-admin scope: saving affects
/// only the currently logged-in admin's view of this subscriber.
class DeviceConfigDialog extends ConsumerStatefulWidget {
  final String subscriberUsername;
  const DeviceConfigDialog({super.key, required this.subscriberUsername});

  @override
  ConsumerState<DeviceConfigDialog> createState() => _DeviceConfigDialogState();
}

class _DeviceConfigDialogState extends ConsumerState<DeviceConfigDialog> {
  DeviceKind? _kind;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _ip = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final cfg = await ref.read(deviceConfigProvider(widget.subscriberUsername).future);
    if (!mounted) return;
    setState(() {
      _kind = cfg?.deviceType;
      _user.text = cfg?.username ?? '';
      _pass.text = cfg?.password ?? '';
      _ip.text = cfg?.customIp ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cfg = DeviceConfig(
      deviceType: _kind,
      username: _user.text.trim().isEmpty ? null : _user.text.trim(),
      password: _pass.text.isEmpty ? null : _pass.text,
      customIp: _ip.text.trim().isEmpty ? null : _ip.text.trim(),
    );
    final ok = await saveDeviceConfig(ref, widget.subscriberUsername, cfg);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ')),
      );
    }
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    final ok = await resetDeviceConfig(ref, widget.subscriberUsername);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحذف')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('إعدادات جهاز المشترك'),
      content: _loading
          ? const SizedBox(width: 40, height: 40, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'حدد نوع الجهاز لتجربة الاتصال. اتركه فارغاً ليُجرَّب ONT ثم Ubiquiti بالافتراضي.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<DeviceKind?>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: null, label: Text('تلقائي')),
                        ButtonSegment(value: DeviceKind.ont, label: Text('ONT')),
                        ButtonSegment(value: DeviceKind.ubiquiti, label: Text('Ubiquiti')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _user,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        hintText: _kind == DeviceKind.ubiquiti ? 'ubnt' : 'telecomadmin',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pass,
                      obscureText: false,
                      decoration: InputDecoration(
                        labelText: 'كلمة السر',
                        hintText: _kind == DeviceKind.ubiquiti ? 'ubnt' : 'admintelecom',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ip,
                      decoration: const InputDecoration(
                        labelText: 'IP مخصص (اختياري)',
                        hintText: 'يُستخدم IP الساس تلقائياً إذا فارغ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ملاحظة: IP المخصص مفيد لأجهزة Ubiquiti الواقفة خلف NAT.',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        if (!_loading)
          TextButton.icon(
            onPressed: _saving ? null : _reset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('استعادة الافتراضي'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: (_loading || _saving) ? null : _save,
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
