import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
    extends ConsumerState<WhatsAppConnectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _phoneController = TextEditingController();
  bool _requestingPair = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref.read(whatsappProvider.notifier).fetchStatus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _shareQr(String qrDataUrl) async {
    final bytes = AppHelpers.decodeQrImage(qrDataUrl);
    if (bytes == null) {
      if (mounted) AppSnackBar.error(context, 'تعذّر تحميل الصورة');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/whatsapp_qr_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'رمز ربط واتساب — صالح لدقيقة واحدة فقط',
      );
    } catch (_) {
      if (mounted) AppSnackBar.error(context, 'تعذّر مشاركة الصورة');
    }
  }

  Future<void> _requestPairCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      AppSnackBar.warning(context, 'أدخل رقم الهاتف مع رمز الدولة');
      return;
    }
    setState(() => _requestingPair = true);
    final result = await ref
        .read(whatsappProvider.notifier)
        .requestPairCode(phone);
    if (!mounted) return;
    setState(() => _requestingPair = false);
    if (!result.success) {
      AppSnackBar.error(context, result.error ?? 'فشل توليد رمز الربط');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wa = ref.watch(whatsappProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('اتصال واتساب'),
        bottom: wa.status.connected
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'رمز QR', icon: Icon(Icons.qr_code_rounded)),
                  Tab(text: 'رمز الهاتف', icon: Icon(Icons.pin_rounded)),
                ],
              ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(whatsappProvider.notifier).fetchStatus(),
        child: wa.status.connected
            ? _buildConnectedView(theme, wa)
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildQrTab(theme, isDark, wa),
                  _buildPairCodeTab(theme, wa),
                ],
              ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, WhatsAppState wa, bool isDark) {
    return Container(
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
              wa.status.connected ? Icons.check_circle : Icons.link_off,
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
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
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
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildQrTab(ThemeData theme, bool isDark, WhatsAppState wa) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatusCard(theme, wa, isDark),
        const SizedBox(height: 24),
        if (wa.qrCode != null) ...[
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
                    if (bytes == null) return const Text('فشل تحميل QR');
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => _shareQr(wa.qrCode!),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
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
                Text('جاري الاتصال...', style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (wa.error != null) _buildErrorBanner(wa.error!),
        SizedBox(
          height: AppTheme.actionButtonHeight,
          child: ElevatedButton.icon(
            onPressed: wa.isConnecting
                ? null
                : () => ref.read(whatsappProvider.notifier).startSession(),
            icon: const Icon(Icons.qr_code_scanner),
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
                : () => ref.read(whatsappProvider.notifier).reconnect(),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة اتصال'),
          ),
        ),
      ],
    );
  }

  Widget _buildPairCodeTab(ThemeData theme, WhatsAppState wa) {
    final chars = (wa.pairCode ?? '').replaceAll('-', '').split('');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.whatsappGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.whatsappGreen.withOpacity(0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_rounded,
                      color: AppTheme.whatsappGreen, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'ربط بدون هاتف ثاني',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'أدخل رقم هاتف الواتساب مع رمز الدولة. ستحصل على رمز مكوَّن من 8 أحرف. افتح واتساب ثم: الإعدادات → الأجهزة المرتبطة → ربط جهاز → الربط برقم الهاتف بدلاً من ذلك → أدخل الرمز.',
                style: TextStyle(fontSize: 12.5, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
          ],
          decoration: const InputDecoration(
            labelText: 'رقم الهاتف (مثال: 9647XXXXXXXX)',
            prefixIcon: Icon(Icons.phone_android),
            hintText: '9647XXXXXXXX',
            border: OutlineInputBorder(),
          ),
          enabled: !_requestingPair && wa.pairCode == null,
        ),
        const SizedBox(height: 14),
        if (wa.pairCode != null) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF128C7E)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'رمز الربط',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < chars.length; i++) ...[
                      if (i == 4)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('-',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold)),
                        ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          chars[i],
                          style: const TextStyle(
                            color: Color(0xFF075E54),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: wa.pairCode ?? ''));
                        AppSnackBar.success(context, 'تم نسخ الرمز');
                      },
                      icon: const Icon(Icons.copy_rounded,
                          color: Colors.white, size: 18),
                      label: const Text('نسخ',
                          style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _requestPairCode,
                      icon: const Icon(Icons.refresh,
                          color: Colors.white, size: 18),
                      label: const Text('رمز جديد',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'الرمز صالح لمدة 3 دقائق تقريباً',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ] else ...[
          SizedBox(
            height: AppTheme.actionButtonHeight,
            child: ElevatedButton.icon(
              onPressed: _requestingPair ? null : _requestPairCode,
              icon: _requestingPair
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.pin_rounded),
              label: Text(_requestingPair ? 'جاري التوليد...' : 'توليد رمز الربط'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.whatsappGreen,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (wa.error != null) _buildErrorBanner(wa.error!),
      ],
    );
  }

  Widget _buildConnectedView(ThemeData theme, WhatsAppState wa) {
    final isDark = theme.brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatusCard(theme, wa, isDark),
        const SizedBox(height: 24),
        SizedBox(
          height: AppTheme.actionButtonHeight,
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
    );
  }
}
