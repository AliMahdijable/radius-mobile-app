import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/whatsapp_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../widgets/app_snackbar.dart';

class WhatsAppConnectionScreen extends ConsumerStatefulWidget {
  const WhatsAppConnectionScreen({super.key});

  @override
  ConsumerState<WhatsAppConnectionScreen> createState() =>
      _WhatsAppConnectionScreenState();
}

class _WhatsAppConnectionScreenState
    extends ConsumerState<WhatsAppConnectionScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(whatsappProvider.notifier).refreshStatusOnOpen();
    });
  }

  Future<void> _shareQr(String qrDataUrl) async {
    final bytes = AppHelpers.decodeQrImage(qrDataUrl);
    if (bytes == null) {
      if (mounted) AppSnackBar.error(context, 'تعذّر تحميل الصورة');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/whatsapp_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'رمز ربط واتساب — صالح لدقيقة واحدة فقط',
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'تعذّر مشاركة الصورة');
    }
  }

  // عرض الكود بصيغة XXXX-XXXX لسهولة القراءة
  String _formatPairCode(String code) {
    final c = code.trim();
    if (c.length == 8) return '${c.substring(0, 4)}-${c.substring(4)}';
    return c;
  }

  Future<void> _promptPairCode() async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الربط برقم الهاتف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل رقم واتساب بالصيغة الدولية بدون + أو صفر '
              '(مثال: 9647700000000)',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '9647700000000',
                prefixIcon: Icon(LucideIcons.phone),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.whatsappGreen,
            ),
            child: const Text('اطلب الكود'),
          ),
        ],
      ),
    );
    if (phone != null && phone.isNotEmpty) {
      ref.read(whatsappProvider.notifier).startSessionWithCode(phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wa = ref.watch(whatsappProvider);
    final user = ref.watch(authProvider).user;
    final canConnect = user?.hasEmployeePermission('whatsapp.connect') ?? true;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('اتصال واتساب')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(whatsappProvider.notifier).fetchStatus(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: wa.status.connected
                      ? [const Color(0xFF25D366), const Color(0xFF128C7E)]
                      : [Colors.grey.shade300, Colors.grey.shade400],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (wa.status.connected
                            ? AppTheme.whatsappGreen
                            : Colors.grey)
                        .withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(
                        wa.status.connected ? 0.2 : 0.1,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      wa.status.connected
                          ? LucideIcons.circleCheck
                          : LucideIcons.unlink,
                      size: 48,
                      color: wa.status.connected
                          ? Colors.white
                          : (isDark ? Colors.white54 : Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    wa.status.connected ? 'متصل' : 'غير متصل',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: wa.status.connected
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.grey.shade700),
                    ),
                  ),
                  if (wa.status.connected && wa.status.phone != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      AppHelpers.formatPhone(wa.status.phone),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // QR Code
            if (wa.qrCode != null && !wa.status.connected) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      'امسح رمز QR من واتساب',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final bytes = AppHelpers.decodeQrImage(wa.qrCode);
                        if (bytes == null) {
                          return const Text('فشل تحميل QR');
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            bytes,
                            width: 260,
                            height: 260,
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'افتح واتساب > الأجهزة المرتبطة > ربط جهاز',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => _shareQr(wa.qrCode!),
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: const Text('مشاركة / حفظ الصورة'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Pair Code (الربط برقم الهاتف)
            if (wa.pairCode != null && !wa.status.connected) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      'كود الربط برقم الهاتف',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 24),
                      decoration: BoxDecoration(
                        color: AppTheme.whatsappGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppTheme.whatsappGreen.withOpacity(0.4)),
                      ),
                      child: Text(
                        _formatPairCode(wa.pairCode!),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                          color: AppTheme.whatsappGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'افتح واتساب ← الأجهزة المرتبطة ← ربط جهاز ← '
                      '"الربط برقم الهاتف بدلاً من ذلك" ← أدخل الكود',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: wa.pairCode!));
                        AppSnackBar.success(context, 'تم نسخ الكود');
                      },
                      icon: const Icon(LucideIcons.copy, size: 18),
                      label: const Text('نسخ الكود'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Loading
            if (wa.isConnecting && wa.qrCode == null && wa.pairCode == null) ...[
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'جاري الاتصال...',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Error
            if (wa.error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.circleAlert, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        wa.error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action Buttons — مخفية تماماً للموظف اللي ما عنده whatsapp.connect.
            // الباكند يرفض الاستدعاء أصلاً لكن إخفاء الأزرار يمنع توست
            // "لا تملك صلاحية" ويعكس الحالة الصحيحة في الواجهة.
            if (canConnect && !wa.status.connected) ...[
              SizedBox(
                height: AppTheme.actionButtonHeight,
                child: ElevatedButton.icon(
                  onPressed: wa.isConnecting
                      ? null
                      : () =>
                          ref.read(whatsappProvider.notifier).startSession(),
                  icon: const Icon(LucideIcons.scanLine),
                  label: const Text('بدء جلسة جديدة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.whatsappGreen,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: AppTheme.actionButtonHeight,
                child: OutlinedButton.icon(
                  onPressed: wa.isConnecting
                      ? null
                      : () => _promptPairCode(),
                  icon: const Icon(LucideIcons.smartphone),
                  label: const Text('ربط بالكود (بدل المسح)'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: AppTheme.actionButtonHeight,
                child: OutlinedButton.icon(
                  onPressed: wa.isConnecting
                      ? null
                      : () => ref.read(whatsappProvider.notifier).reconnect(),
                  icon: const Icon(LucideIcons.refreshCw),
                  label: const Text('إعادة اتصال'),
                ),
              ),
            ] else if (canConnect) ...[
              SizedBox(
                height: AppTheme.actionButtonHeight,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(whatsappProvider.notifier).disconnect(),
                  icon: const Icon(LucideIcons.unlink, color: Colors.red),
                  label: const Text(
                    'قطع الاتصال',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
