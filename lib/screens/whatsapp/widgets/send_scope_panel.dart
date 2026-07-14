import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/send_scope_api.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Panel "نطاق الإرسال" — يطابق [client-v2/pages/WhatsApp.tsx:SendScopePanel].
///
/// الغاية: المدير الرئيسي يقرّر إذا التذكيرات (دين/انتهاء/قرب انتهاء) +
/// التبليغات تُرسَل لكل مشتركي المدراء الفرعيين، أو فقط مدراء محدَّدين.
///
/// يظهر فقط إذا `subManagers` غير فارغة (أي المدير عنده تسلسل هرمي).
/// إذا مدير بدون sub-managers → الـpanel يختفي كلياً (مثل الويب).
class SendScopePanel extends StatefulWidget {
  const SendScopePanel({super.key});

  @override
  State<SendScopePanel> createState() => _SendScopePanelState();
}

class _SendScopePanelState extends State<SendScopePanel> {
  SendScope? _scope;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await SendScopeApi.fetch();
    if (!mounted) return;
    setState(() {
      _scope = s;
      _loading = false;
    });
  }

  Future<void> _save({
    required bool sendToAll,
    required List<String> managedUsernames,
  }) async {
    setState(() => _saving = true);
    final r = await SendScopeApi.update(
      sendToAll: sendToAll,
      managedUsernames: managedUsernames,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'فشل الحفظ'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _scope;
    // أخفِ Panel لو المدير بلا مدراء فرعيين (يطابق سلوك الويب).
    if (!_loading && (s == null || s.subManagers.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users, size: 14, color: AppColors.brand),
              const SizedBox(width: 6),
              Text(
                'نطاق الإرسال',
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 13),
              ),
              const Spacer(),
              if (_saving)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            _body(s!),
        ],
      ),
    );
  }

  Widget _body(SendScope s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch: cover-all
        Row(
          children: [
            Switch(
              value: s.sendToAll,
              activeColor: AppColors.brand,
              onChanged: _saving
                  ? null
                  : (v) => _save(
                        sendToAll: v,
                        managedUsernames: s.managedUsernames,
                      ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تغطية كل المدراء الفرعيين',
                    style: AppType.label(color: AppColors.textHi)
                        .copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'يشمل أيّ مدير يُضاف لاحقاً',
                    style: AppType.muted().copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Sub-managers grid — يظهر لمّا sendToAll=false
        if (!s.sendToAll) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 8),
          Text(
            'المدراء المشمولون (${s.managedUsernames.length}/${s.subManagers.length})',
            style: AppType.muted().copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          _managersGrid(s),
        ],
      ],
    );
  }

  Widget _managersGrid(SendScope s) {
    final managedLower = s.managedUsernames.map((m) => m.toLowerCase()).toSet();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final u in s.subManagers)
          _managerChip(
            username: u,
            checked: managedLower.contains(u.toLowerCase()),
            onToggle: (nowChecked) {
              final next = Set<String>.from(managedLower);
              final uLower = u.toLowerCase();
              if (nowChecked) {
                next.add(uLower);
              } else {
                next.remove(uLower);
              }
              _save(
                sendToAll: s.sendToAll,
                managedUsernames: next.toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _managerChip({
    required String username,
    required bool checked,
    required ValueChanged<bool> onToggle,
  }) {
    return Material(
      color: checked
          ? AppColors.brand.withValues(alpha: 0.1)
          : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _saving ? null : () => onToggle(!checked),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: checked
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
              width: checked ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                checked ? LucideIcons.squareCheck : LucideIcons.square,
                size: 13,
                color: checked ? AppColors.brand : AppColors.textLow,
              ),
              const SizedBox(width: 5),
              Text(
                username,
                style: AppType.button(
                  color: checked ? AppColors.brand : AppColors.textMid,
                ).copyWith(fontSize: 11, fontFamily: 'monospace'),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
