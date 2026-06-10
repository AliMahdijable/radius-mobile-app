import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/packages_api.dart';
import '../../core/util/format.dart';
import '../../services/auth_storage.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// مديول تسعير الباقات. شاشة في-المكان: قائمة الباقات، كل باقة فيها
/// حقل سعر بيع قابل للتعديل. أسفل الشاشة زر "حفظ" واحد ينفّذ
/// POST /api/v2/price-list بكل التعديلات دفعة واحدة (مثل v1 web).
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  List<Package> _packages = const [];
  /// Map<profileId, edited userPrice>. أيّ index غير موجود = ما اتعدّل.
  final Map<int, int> _edits = {};
  /// Controllers per package id لتجنّب إعادة إنشاءها في كل rebuild.
  final Map<int, TextEditingController> _controllers = {};
  bool _loading = true;
  bool _saving = false;
  int? _myManagerId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final idStr = await AuthStorage.readAdminId();
    final id = int.tryParse(idStr ?? '');
    if (id != null) _myManagerId = id;
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final pkgs = await PackagesApi.list();
    if (!mounted) return;
    setState(() {
      _packages = pkgs;
      _edits.clear();
      for (final p in pkgs) {
        final initial = (p.userPrice ?? 0).toInt();
        final ctrl = _controllers.putIfAbsent(
          p.id,
          () => TextEditingController(),
        );
        ctrl.text = initial > 0 ? _fmt(initial) : '';
      }
      _loading = false;
    });
  }

  static String _fmt(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  bool get _hasChanges => _edits.values.any((v) => _hasDelta(v));

  bool _hasDelta(int newValue) {
    final originals = {
      for (final p in _packages) p.id: (p.userPrice ?? 0).toInt(),
    };
    return _edits.entries.any((e) {
      final original = originals[e.key] ?? 0;
      return e.value != original;
    });
  }

  Future<void> _save() async {
    if (_saving || _myManagerId == null) return;
    setState(() => _saving = true);
    final payload = <Map<String, dynamic>>[];
    for (final p in _packages) {
      final edited = _edits[p.id];
      final original = (p.userPrice ?? 0).toInt();
      final value = edited ?? original;
      payload.add({
        'profile_id': p.id,
        'profile_name': p.name,
        'user_price': value,
        'price': (p.basePrice ?? value).toInt(),
        'cost': (p.cost ?? 0).toInt(),
      });
    }
    final r = await PackagesApi.savePrices(
      managerId: _myManagerId!,
      priceList: payload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم حفظ الأسعار' : (r.message ?? 'تعذّر الحفظ')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8B5CF6);
    final changedCount = _edits.entries.where((e) {
      final original = _packages
              .firstWhere((p) => p.id == e.key,
                  orElse: () => const Package(id: -1, name: ''))
              .userPrice
              ?.toInt() ??
          0;
      return e.value != original;
    }).length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'تسعير الباقات',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _hasChanges ? 80 : 0,
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.save, size: 16),
              label: Text(
                _saving
                    ? 'جاري الحفظ...'
                    : 'حفظ التغييرات ($changedCount باقة)',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.md),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: accent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              _hero(accent, _packages.length),
              const SizedBox(height: Sp.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_packages.isEmpty)
                _empty()
              else
                Column(
                  children: [
                    for (final p in _packages) ...[
                      _PackageTile(
                        package: p,
                        controller: _controllers[p.id]!,
                        onChanged: (v) {
                          final digits =
                              v.replaceAll(RegExp(r'[^0-9]'), '');
                          final parsed = int.tryParse(digits) ?? 0;
                          setState(() {
                            _edits[p.id] = parsed;
                          });
                          // re-format with thousands separator
                          final formatted = _fmt(parsed);
                          final ctrl = _controllers[p.id]!;
                          if (formatted != ctrl.text) {
                            ctrl.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                  offset: formatted.length),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(Color accent, int count) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(LucideIcons.package, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count باقة',
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 20, letterSpacing: -0.4),
                ),
                Text(
                  'سعر البيع للمشترك يطبع على الوصل',
                  style: AppType.muted().copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.packageX,
              size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            'لا توجد باقات متاحة',
            style: AppType.muted(color: AppColors.textHi)
                .copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.controller,
    required this.onChanged,
  });
  final Package package;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: const Icon(LucideIcons.package,
                size: 16, color: Color(0xFF8B5CF6)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.name,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((package.cost ?? 0) > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'الكلفة ${formatIQD(package.cost!)} د.ع',
                    style: AppType.muted().copyWith(fontSize: 10.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppType.label(color: AppColors.textHi).copyWith(
                  fontSize: 13, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 8),
                suffixText: 'د.ع',
                suffixStyle: AppType.muted().copyWith(fontSize: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
