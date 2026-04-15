import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/whatsapp_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../widgets/status_badge.dart';

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
      ref.read(whatsappProvider.notifier).fetchStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wa = ref.watch(whatsappProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('اتصال واتساب')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(whatsappProvider.notifier).fetchStatus(),
        child: ListView(
          padding: const EdgeInsets.all(20),
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
                          ? Icons.check_circle
                          : Icons.link_off,
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
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Loading
            if (wa.isConnecting && wa.qrCode == null) ...[
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
                    const Icon(Icons.error_outline, color: Colors.red),
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

            // Action Buttons
            if (!wa.status.connected) ...[
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: wa.isConnecting
                      ? null
                      : () =>
                          ref.read(whatsappProvider.notifier).startSession(),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('بدء جلسة جديدة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.whatsappGreen,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: wa.isConnecting
                      ? null
                      : () => ref.read(whatsappProvider.notifier).reconnect(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة اتصال'),
                ),
              ),
            ] else ...[
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(whatsappProvider.notifier).disconnect(),
                  icon: const Icon(Icons.link_off, color: Colors.red),
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
