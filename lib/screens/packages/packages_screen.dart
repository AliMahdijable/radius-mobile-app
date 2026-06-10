import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/managers_api.dart';
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
  /// مطلب 2026-06-12: عمودان قابلان للتحرير (مطابق screenshots v1).
  /// `_userPriceEdits` = سعر البيع للمشترك (user_price).
  /// `_priceEdits` = السعر (price) — سعر شراء المدير من الأب.
  /// `cost` = الكلفة (cost) — للقراءة فقط، تعرض كـreference.
  final Map<int, int> _userPriceEdits = {};
  final Map<int, int> _priceEdits = {};
  final Map<int, TextEditingController> _userPriceCtrl = {};
  final Map<int, TextEditingController> _priceCtrl = {};
  bool _loading = true;
  bool _saving = false;
  int? _myManagerId;
  String _myDisplayName = '…';

  /// مطلب 2026-06-12: السوبر/المدير الفرعي يقدر يعدّل تسعير
  /// أي مدير من قائمة منسدلة. null = الـadmin يعدّل تسعيره الخاص
  /// (السلوك الأصلي). الـlabel يبدأ بـ"…" ويحدّث عند bootstrap باسم
  /// الـadmin الحالي الفعلي (مطلب 2026-06-12: 'بدل تسعيري الخاص').
  int? _selectedManagerId;
  String _selectedManagerLabel = '…';
  List<({int id, String username, String displayName})>? _managers;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final c in _userPriceCtrl.values) {
      c.dispose();
    }
    for (final c in _priceCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final idStr = await AuthStorage.readAdminId();
    final id = int.tryParse(idStr ?? '');
    if (id != null) _myManagerId = id;
    // اسم المدير الحالي — username فقط (admin@xxx) مطابق طلب 2026-06-12.
    final username = await AuthStorage.readAdminUsername();
    final displayName = await AuthStorage.readDisplayName();
    final myLabel = (username != null && username.isNotEmpty)
        ? username
        : (displayName ?? '…');
    if (mounted) {
      setState(() {
        _myDisplayName = myLabel;
        _selectedManagerLabel = myLabel;
      });
    }
    // قائمة المدراء الفرعيين — لو موجودة، السوبر افتراضياً يفتح
    // الشاشة على تسعير أول مدير فرعي (مطلب 2026-06-12: 'تظهر فارغه
    // الا ابدل بين المدراء'). تسعير المدير الأب نفسه نادراً ما يكون
    // مضبوطاً — لذا نختار فرعي بدلاً من ترك كل الحقول صفر.
    final mgrs = await ManagersApi.lite();
    if (!mounted) return;
    setState(() => _managers = mgrs ?? const []);
    if ((mgrs ?? const []).isNotEmpty) {
      final first = mgrs!.first;
      setState(() {
        _selectedManagerId = first.id;
        _selectedManagerLabel = first.username;
      });
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // عرض تسعير مدير محدّد لما الـpicker مختار،
    // وإلا عرض تسعير الـadmin الحالي.
    final pkgs = _selectedManagerId != null
        ? await PackagesApi.listForManager(_selectedManagerId!)
        : await PackagesApi.list();
    if (!mounted) return;
    setState(() {
      _packages = pkgs;
      _userPriceEdits.clear();
      _priceEdits.clear();
      for (final p in pkgs) {
        final initialUser = (p.userPrice ?? 0).toInt();
        final initialPrice = (p.basePrice ?? 0).toInt();
        _userPriceCtrl
            .putIfAbsent(p.id, () => TextEditingController())
            .text = initialUser > 0 ? _fmt(initialUser) : '';
        _priceCtrl
            .putIfAbsent(p.id, () => TextEditingController())
            .text = initialPrice > 0 ? _fmt(initialPrice) : '';
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

  bool get _hasChanges {
    for (final p in _packages) {
      final originalUser = (p.userPrice ?? 0).toInt();
      final originalPrice = (p.basePrice ?? 0).toInt();
      if ((_userPriceEdits[p.id] ?? originalUser) != originalUser) return true;
      if ((_priceEdits[p.id] ?? originalPrice) != originalPrice) return true;
    }
    return false;
  }

  int _changedCount() {
    var c = 0;
    for (final p in _packages) {
      final originalUser = (p.userPrice ?? 0).toInt();
      final originalPrice = (p.basePrice ?? 0).toInt();
      final userChanged =
          (_userPriceEdits[p.id] ?? originalUser) != originalUser;
      final priceChanged =
          (_priceEdits[p.id] ?? originalPrice) != originalPrice;
      if (userChanged || priceChanged) c++;
    }
    return c;
  }

  Future<void> _save() async {
    if (_saving) return;
    final targetManagerId = _selectedManagerId ?? _myManagerId;
    if (targetManagerId == null) return;
    setState(() => _saving = true);
    final payload = <Map<String, dynamic>>[];
    for (final p in _packages) {
      final userEdit = _userPriceEdits[p.id];
      final priceEdit = _priceEdits[p.id];
      final userPrice = userEdit ?? (p.userPrice ?? 0).toInt();
      final price = priceEdit ?? (p.basePrice ?? 0).toInt();
      payload.add({
        'profile_id': p.id,
        'profile_name': p.name,
        'user_price': userPrice,
        'price': price,
        'cost': (p.cost ?? 0).toInt(),
      });
    }
    final r = await PackagesApi.savePrices(
      managerId: targetManagerId,
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
    final changedCount = _changedCount();
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
              const SizedBox(height: Sp.sm),
              if ((_managers ?? []).isNotEmpty) ...[
                _managerPicker(accent),
                const SizedBox(height: Sp.sm),
              ],
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
                        userPriceCtrl: _userPriceCtrl[p.id]!,
                        priceCtrl: _priceCtrl[p.id]!,
                        onUserPriceChanged: (v) =>
                            _handleEdit(p.id, v, _userPriceEdits, _userPriceCtrl[p.id]!),
                        onPriceChanged: (v) => _handleEdit(
                            p.id, v, _priceEdits, _priceCtrl[p.id]!),
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

  void _handleEdit(
    int packageId,
    String value,
    Map<int, int> editsMap,
    TextEditingController ctrl,
  ) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    setState(() => editsMap[packageId] = parsed);
    final formatted = _fmt(parsed);
    if (formatted != ctrl.text) {
      ctrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
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

  Widget _managerPicker(Color accent) {
    final managers = _managers ?? const [];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final picked = await showModalBottomSheet<int?>(
            context: context,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Sp.lg, Sp.md, Sp.lg, Sp.sm),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.userCog,
                            size: 16, color: AppColors.textMid),
                        const SizedBox(width: 6),
                        Text(
                          'اختر تسعير من؟',
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Icon(LucideIcons.user, color: accent),
                    title: Text(_selectedManagerLabel == '…'
                        ? 'تسعيري الخاص'
                        : _selectedManagerLabel),
                    onTap: () => Navigator.of(context).pop(-1),
                    trailing: _selectedManagerId == null
                        ? Icon(LucideIcons.check, color: accent)
                        : null,
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: managers.length,
                      itemBuilder: (_, i) {
                        final m = managers[i];
                        final selected = _selectedManagerId == m.id;
                        return ListTile(
                          leading: const Icon(LucideIcons.userCog),
                          title: Text(m.displayName),
                          onTap: () => Navigator.of(context).pop(m.id),
                          trailing: selected
                              ? Icon(LucideIcons.check, color: accent)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
          if (picked == null) return;
          setState(() {
            if (picked == -1) {
              _selectedManagerId = null;
              _selectedManagerLabel = _myDisplayName;
            } else {
              _selectedManagerId = picked;
              _selectedManagerLabel = managers
                      .firstWhere((m) => m.id == picked,
                          orElse: () => (
                                id: picked,
                                username: '',
                                displayName: '#$picked'
                              ))
                      .displayName;
            }
            _userPriceEdits.clear();
            _priceEdits.clear();
          });
          _load();
        },
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.userCog, size: 14, color: accent),
              const SizedBox(width: 7),
              Text(
                'مدير: ',
                style: AppType.muted().copyWith(fontSize: 11),
              ),
              Expanded(
                child: Text(
                  _selectedManagerLabel,
                  style: AppType.label(color: accent)
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(LucideIcons.chevronDown,
                  size: 14, color: AppColors.textMid),
            ],
          ),
        ),
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

/// مطلب 2026-06-12 (screenshot v1): كل باقة كرت كامل بـheader اسم
/// الباقة + أيقونة wifi، تحته 3 أعمدة (سعر البيع | السعر | الكلفة).
/// `سعر البيع` و`السعر` قابلان للتحرير، `الكلفة` للقراءة فقط.
class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.userPriceCtrl,
    required this.priceCtrl,
    required this.onUserPriceChanged,
    required this.onPriceChanged,
  });
  final Package package;
  final TextEditingController userPriceCtrl;
  final TextEditingController priceCtrl;
  final ValueChanged<String> onUserPriceChanged;
  final ValueChanged<String> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final cost = package.cost ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: اسم الباقة + icon
          Row(
            children: [
              Expanded(
                child: Text(
                  package.name,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.wifi,
                    size: 16, color: AppColors.brand),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3 cols
          Row(
            children: [
              Expanded(
                child: _priceField(
                  label: 'سعر البيع',
                  ctrl: userPriceCtrl,
                  onChanged: onUserPriceChanged,
                  highlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _priceField(
                  label: 'السعر',
                  ctrl: priceCtrl,
                  onChanged: onPriceChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _readOnly(
                  label: 'الكلفة',
                  value: cost > 0 ? cost.toInt().toString() : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceField({
    required String label,
    required TextEditingController ctrl,
    required ValueChanged<String> onChanged,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2, bottom: 4),
          child: Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: AppType.label(
                  color: highlight ? AppColors.brand : AppColors.textHi)
              .copyWith(fontSize: 14, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: AppType.input(color: AppColors.textLow),
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(
                color: highlight
                    ? AppColors.brand.withValues(alpha: 0.4)
                    : AppColors.border.withValues(alpha: 0.5),
                width: highlight ? 1.5 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: BorderSide(
                color: highlight
                    ? AppColors.brand.withValues(alpha: 0.4)
                    : AppColors.border.withValues(alpha: 0.5),
                width: highlight ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.sm),
              borderSide: const BorderSide(
                  color: AppColors.brand, width: 1.8),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _readOnly({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 2, bottom: 4),
          child: Text(
            label,
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Text(
            value,
            style: AppType.label(color: AppColors.textMid)
                .copyWith(fontSize: 13, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
