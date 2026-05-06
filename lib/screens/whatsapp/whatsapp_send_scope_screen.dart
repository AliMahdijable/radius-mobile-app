import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_snackbar.dart';

/// WhatsApp send-scope configuration screen. Lets the signed-in admin
/// pick which sub-managers' subscribers should be messaged through
/// THIS session's WhatsApp. Direct subscribers are always included;
/// this screen only changes which sub-managers are covered on top.
class WhatsAppSendScopeScreen extends ConsumerStatefulWidget {
  const WhatsAppSendScopeScreen({super.key});

  @override
  ConsumerState<WhatsAppSendScopeScreen> createState() =>
      _WhatsAppSendScopeScreenState();
}

class _WhatsAppSendScopeScreenState
    extends ConsumerState<WhatsAppSendScopeScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _adminUsername;
  bool _sendToAll = false;
  Set<String> _managedUsernames = {};
  List<String> _availableSubManagers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final adminId = await ref.read(storageServiceProvider).getAdminId();
    if (adminId == null) {
      setState(() {
        _loading = false;
        _error = 'معرف المدير غير متوفر';
      });
      return;
    }
    try {
      final res = await ref
          .read(backendDioProvider)
          .get('/api/whatsapp/send-scope/$adminId');
      final data = res.data;
      if (data is Map && data['success'] == true) {
        setState(() {
          _adminUsername = data['adminUsername']?.toString();
          _sendToAll = data['sendToAll'] == true;
          _managedUsernames = (data['managedUsernames'] as List? ?? [])
              .map((e) => e.toString())
              .toSet();
          _availableSubManagers = (data['subManagers'] as List? ?? [])
              .map((e) => e.toString())
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = data is Map
              ? (data['message']?.toString() ?? 'تعذر جلب الإعدادات')
              : 'تعذر جلب الإعدادات';
        });
      }
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? e.message)
          : e.message;
      setState(() {
        _loading = false;
        _error = msg ?? 'تعذر جلب الإعدادات';
      });
    } catch (e) {
      dev.log('loadSendScope error: $e', name: 'SCOPE');
      setState(() {
        _loading = false;
        _error = 'تعذر جلب الإعدادات';
      });
    }
  }

  Future<void> _save() async {
    final adminId = await ref.read(storageServiceProvider).getAdminId();
    if (adminId == null) return;
    setState(() => _saving = true);
    try {
      final res = await ref.read(backendDioProvider).patch(
        '/api/whatsapp/send-scope',
        data: {
          'adminId': adminId,
          'sendToAll': _sendToAll,
          'managedUsernames': _managedUsernames.toList(),
        },
        options: Options(validateStatus: (_) => true),
      );
      final data = res.data;
      final ok = res.statusCode == 200 && data is Map && data['success'] == true;
      if (!mounted) return;
      if (ok) {
        AppSnackBar.success(context, 'تم حفظ نطاق الإرسال');
      } else {
        AppSnackBar.error(
          context,
          data is Map ? (data['message']?.toString() ?? 'فشل الحفظ') : 'فشل الحفظ',
        );
      }
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'فشل الحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('نطاق الإرسال عبر الواتساب'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.circleAlert,
                            size: 48,
                            color: theme.colorScheme.error.withOpacity(0.6)),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(LucideIcons.refreshCw),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _intro(theme),
        const SizedBox(height: 16),
        _allToggleTile(theme),
        const SizedBox(height: 16),
        Text(
          'المدراء الفرعيون تحتك',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'اختر الذين تريد تغطية مشتركيهم من هذا الرقم.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
        ),
        const SizedBox(height: 8),
        if (_availableSubManagers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'لا يوجد مدراء فرعيون تحتك حالياً.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          )
        else
          ..._availableSubManagers.map((u) => _managerTile(theme, u)),
      ],
    );
  }

  Widget _intro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_adminUsername != null)
                  Text(
                    'حسابك: $_adminUsername',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'يرسل هذا الرقم دائماً لمشتركيك المباشرين. اختر أي مدراء فرعيين تريد تغطيتهم أيضاً. لا تختر مديراً فرعياً ربط واتسابه الخاص — لتجنب وصول الرسالة مرتين.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _allToggleTile(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _sendToAll
              ? AppTheme.whatsappGreen.withOpacity(0.35)
              : theme.colorScheme.onSurface.withOpacity(0.08),
          width: _sendToAll ? 1.5 : 1,
        ),
      ),
      child: SwitchListTile.adaptive(
        value: _sendToAll,
        activeColor: AppTheme.whatsappGreen,
        onChanged: _saving
            ? null
            : (v) {
                setState(() => _sendToAll = v);
                _save();
              },
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.whatsappGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(LucideIcons.users,
              color: AppTheme.whatsappGreen, size: 20),
        ),
        title: const Text(
          'الجميع (كل المدراء الفرعيين)',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        subtitle: const Text(
          'يشمل المدراء الفرعيين الحاليين وأي مدير ينضم لاحقاً. قد يسبب تكرار لو ربط الفرعي واتسابه.',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, height: 1.5),
        ),
      ),
    );
  }

  Widget _managerTile(ThemeData theme, String username) {
    final isChecked = _sendToAll || _managedUsernames.contains(username);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: CheckboxListTile.adaptive(
        value: isChecked,
        activeColor: AppTheme.whatsappGreen,
        controlAffinity: ListTileControlAffinity.trailing,
        onChanged: (_sendToAll || _saving)
            ? null
            : (v) {
                setState(() {
                  if (v == true) {
                    _managedUsernames.add(username);
                  } else {
                    _managedUsernames.remove(username);
                  }
                });
                _save();
              },
        secondary: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.user,
              size: 18, color: theme.colorScheme.primary),
        ),
        title: Text(
          username,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
        ),
        subtitle: Text(
          _sendToAll
              ? 'مشمول ضمن "الجميع"'
              : (isChecked
                  ? 'يُغطى من هذا الواتساب'
                  : 'لا يُغطى من هذا الواتساب'),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}
