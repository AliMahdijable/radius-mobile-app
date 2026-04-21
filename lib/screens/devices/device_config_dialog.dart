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
    // Tight field style — compact density + dense padding so three inputs
    // + a picker + a note all fit without scrolling on typical phones.
    InputDecoration _dec(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: const OutlineInputBorder(),
        );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      title: const Text('إعدادات جهاز المشترك', style: TextStyle(fontSize: 15)),
      content: _loading
          ? const SizedBox(
              width: 40, height: 40,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اتركه تلقائياً ليُجرَّب ONT ثم Ubiquiti.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.2),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<DeviceKind?>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(value: null, label: Text('تلقائي', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: DeviceKind.ont, label: Text('ONT', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: DeviceKind.ubiquiti, label: Text('Ubiquiti', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _user,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(
                      'اسم المستخدم',
                      _kind == DeviceKind.ubiquiti ? 'ubnt' : 'telecomadmin',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pass,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(
                      'كلمة السر',
                      _kind == DeviceKind.ubiquiti ? 'ubnt' : 'admintelecom',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ip,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec('IP مخصص (اختياري)', 'يستخدم IP الساس إذا فارغ'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'IP المخصص مفيد لـ Ubiquiti خلف NAT.',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
      actions: [
        if (!_loading)
          TextButton(
            onPressed: _saving ? null : _reset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('استعادة الافتراضي', style: TextStyle(fontSize: 12)),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
        ),
        FilledButton(
          onPressed: (_loading || _saving) ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: _saving
              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
