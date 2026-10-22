import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/managers_api.dart';
import '../../api/packages_api.dart';
import '../../api/subscribers_api.dart';
import '../../services/auth_storage.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../core/util/amount_input.dart';
import '../desktop/desk_widgets.dart';
import '../../core/platform/desktop_layout.dart';

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

  /// المعرّف المحفوظ مؤهَّلٌ بساسه (`next-gen:175` لساسٍ بعيد، `earthlink:<idx>`)
  /// — والأصل (سوبرنت) عارٍ (`42`). المؤهَّل يُقرأ «تسعيري الخاص» من
  /// `/api/v2/price-list/<رقمه>` لا `/api/v2/packages` (انظر [_load]).
  bool _myIdQualified = false;
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
    // 🐛 ١٨ أكتوبر: `int.tryParse('next-gen:175')` = null — فمديرٌ على ساسٍ
    // بعيد (أو ايرث لنك) بلا مدراء فرعيّين كان «تسعيري الخاص» عنده فارغاً،
    // والحفظ يرجع بصمت (لا معرّف). الرقم بعد آخر «:».
    final idStr = (await AuthStorage.readAdminId())?.trim() ?? '';
    final id = int.tryParse(idStr.split(':').last);
    if (id != null) {
      _myManagerId = id;
      _myIdQualified = idStr.contains(':');
    }
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
    // عرض تسعير مدير محدّد لما الـpicker مختار، وإلا عرض تسعير الـadmin الحالي.
    //
    // «تسعيري الخاص» لمعرّفٍ مؤهَّل من `/api/v2/price-list/<رقمه>`: الخادم
    // يؤهّله بساس التوكن ويقرأ سعر البيع المحلّيّ (`user_price`) — وهو ما يحفظه
    // [_save] إلى المالك نفسه. أمّا `/api/v2/packages` فقائمة الإضافة/التفعيل:
    // بلا `user_price`، فيبدو الحقل فارغاً ويُحفظ صفراً لما لم يُلمس.
    // ايرث لنك يخدم المسارين بالعقد نفسه (يفرض المالك من الجلسة). وFTTH بلا
    // price-list (يردّ قائمةً فارغة) وتسعيره للعرض فقط ← يبقى على packages.
    final selfById =
        _myIdQualified && _myManagerId != null && !ProviderService.isFtth;
    final pkgs = _selectedManagerId != null
        ? await PackagesApi.listForManager(_selectedManagerId!)
        : selfById
            ? await PackagesApi.listForManager(_myManagerId!)
            : await PackagesApi.list();
    if (!mounted) return;
    setState(() {
      _packages = pkgs;
      _userPriceEdits.clear();
      _priceEdits.clear();
      for (final p in pkgs) {
        final initialUser = (p.userPrice ?? 0).toInt();
        final initialPrice = (p.basePrice ?? 0).toInt();
        _userPriceCtrl.putIfAbsent(p.id, () => TextEditingController()).text =
            initialUser > 0 ? _fmt(initialUser) : '';
        _priceCtrl.putIfAbsent(p.id, () => TextEditingController()).text =
            initialPrice > 0 ? _fmt(initialPrice) : '';
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
        content: Text(r.ok
            ? 'pkg.prices_saved'.tr()
            : (r.message ?? 'devices.save_failed'.tr())),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) {
      // 2026-08-09: invalidate cache حتى القائمة تجيب الأسعار الجديدة
      SubscribersApi.invalidatePackagesCache();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final changedCount = _changedCount();
    // مطلب 2026-06-11: لو الموظف عنده packages.view بدون
    // packages.edit_prices، تظهر القائمة كـread-only وزر الحفظ
    // مخفي تماماً.
    final canEdit = Perms.has('packages.edit_prices');
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'pkg.title'.tr(),
                style:
                    AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
              ),
              Text(
                'pkg.subtitle'.tr(),
                style: AppType.muted().copyWith(fontSize: 11),
              ),
            ],
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      bottomNavigationBar: !canEdit
          ? null
          : SafeArea(
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
                              color: AppColors.onBrand,
                            ),
                          )
                        : const Icon(LucideIcons.save, size: 16),
                    label: Text(
                      _saving
                          ? 'notifs.saving'.tr()
                          : 'pkg.save_changes'
                              .tr(namedArgs: {'n': '$changedCount'}),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14, height: 1.3),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: AppColors.onBrand,
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
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              // قسم المدير الفرعي — section بعنوان (مطابق screenshot v1 web)
              _sectionHeader(
                icon: LucideIcons.users,
                title: 'pkg.sub_manager'.tr(),
                accent: accent,
              ),
              const SizedBox(height: 6),
              // الحاسبة: قائمة المدير بعرض قائمةٍ لا بعرض الصفحة.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: DesktopScope.of(context) ? 460 : double.infinity),
                  child: _managerPicker(accent),
                ),
              ),
              const SizedBox(height: Sp.md),
              // مطلب 2026-06-12: شيل بانر التنبيه. سعر المدير المقفل
              // واضح من الحقل نفسه (لون رمادي + لا يقبل النقر)، فما
              // يحتاج بانر تنبيه فوقي.
              // قسم الباقات
              _sectionHeader(
                icon: LucideIcons.package,
                title: 'الباقات والأسعار',
                accent: accent,
              ),
              const SizedBox(height: 6),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_packages.isEmpty)
                _empty()
              else if (DesktopScope.of(context))
                // الحاسبة: الباقات في أعمدة بدل بطاقاتٍ بعرض الشاشة وحقلٍ ممدود.
                DeskGrid(
                  minTileWidth: 260,
                  maxColumns: 4,
                  children: [
                    for (final p in _packages)
                      _PackageTile(
                        package: p,
                        userPriceCtrl: _userPriceCtrl[p.id]!,
                        onUserPriceChanged: (v) => _handleEdit(
                            p.id, v, _userPriceEdits, _userPriceCtrl[p.id]!),
                      ),
                  ],
                )
              else
                Column(
                  children: [
                    for (final p in _packages) ...[
                      _PackageTile(
                        package: p,
                        userPriceCtrl: _userPriceCtrl[p.id]!,
                        onUserPriceChanged: (v) => _handleEdit(
                            p.id, v, _userPriceEdits, _userPriceCtrl[p.id]!),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              if (!_loading && _packages.isNotEmpty) ...[
                const SizedBox(height: Sp.md),
                // شاشة التسعير «سعر البيع» فقط — فالشرح يكتفي ببنده.
                _fieldExplainer(showCost: false),
              ],
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: accent),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _fieldExplainer({required bool showCost}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bookOpen, size: 14, color: AppColors.textMid),
              const SizedBox(width: 6),
              Text(
                'شرح الحقول:',
                style: AppType.label(color: AppColors.textHi)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (showCost) ...[
            _bullet('سعر المدير: سعر السوق المرجعي'),
            const SizedBox(height: 4),
          ],
          _bullet('سعر البيع: ما يدفعه المشترك النهائي'),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.textMid,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 11.5, height: 1.5),
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
            barrierColor: AppColors.scrim,
            context: context,
            backgroundColor: Colors.transparent,
            // مطلب 2026-06-12 (إصلاح): الـListTile داخل sheet مع
            // background DecoratedBox يخفي ink splashes. نلفّ بـMaterial
            // ونعطي اللون فيه ليتعامل مع الـink طبيعياً.
            builder: (_) => Material(
              color: AppColors.surfaceSheet,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(R.sheet)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 42,
                      height: H.grabber,
                      decoration: BoxDecoration(
                        color: AppColors.grabber,
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
                      child: Row(
                        children: [
                          Icon(LucideIcons.userCog,
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
                    // صفّ «تسعيري الخاص» باسم المدير نفسه — كان يعرض اسم
                    // المختار، فيظهر الفرعيّ المختار مرّتين ولا صفّ لصاحب الحساب.
                    ListTile(
                      leading: Icon(LucideIcons.user, color: accent),
                      title: Text(_myDisplayName == '…'
                          ? 'تسعيري الخاص'
                          : _myDisplayName),
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
                      orElse: () =>
                          (id: picked, username: '', displayName: '#$picked'))
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
                      .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textMid),
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
          Icon(LucideIcons.packageX, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            'لا توجد باقات متاحة',
            style:
                AppType.muted(color: AppColors.textHi).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Pro: كلّ صفّ باقة حقلٌ واحد — «سعر البيع» (ما يدفعه المشترك). لا «سعر
/// مدير»/كلفة على شاشة التسعير إطلاقاً (باتّفاق المستخدم)، حتى لتسعير المدير
/// الفرعيّ. سعر الشراء (الكلفة) يظهر كـهِنت عند تفعيل المشترك لا هنا.
class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.userPriceCtrl,
    required this.onUserPriceChanged,
  });
  final Package package;
  final TextEditingController userPriceCtrl;
  final ValueChanged<String> onUserPriceChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                      .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
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
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.wifi, size: 16, color: AppColors.brand),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Pro: شاشة التسعير تعرض «سعر البيع» فقط — حتى لتسعير المدير الفرعيّ
          // (باتّفاق المستخدم: لا «سعر مدير»/كلفة على هذه الشاشة إطلاقاً). سعر
          // الشراء (الكلفة) يظهر كـهِنت عند تفعيل المشترك لا هنا.
          _priceField(
            label: 'سعر البيع',
            ctrl: userPriceCtrl,
            onChanged: onUserPriceChanged,
            highlight: true,
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
        // ⚠️ `onExpanded` ليس اختياريّاً هنا: ضبط `controller.value`
        // برمجيّاً يُطلق الـlisteners لكنّه **لا يُطلق `onChanged`**،
        // فكانت القيمة الموسَّعة تظهر في الحقل ولا تصل حالة الشاشة —
        // يكتب المدير 25 فيرى 25,000 ويُحفظ 25. عطل مالي صامت.
        AmountShorthandBox(
            controller: ctrl,
            onExpanded: (v) => onChanged(v.toString()),
            child: TextField(
              controller: ctrl,
              onChanged: onChanged,
              // مطلب 2026-06-11: لو الموظف ما عنده packages.edit_prices،
              // كل الحقول read-only (مع gating إضافي لزر الحفظ).
              readOnly: !Perms.has('packages.edit_prices'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppType.label(
                      color: highlight ? AppColors.brand : AppColors.textHi)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(
                    color: highlight
                        ? AppColors.brandSoftBorder
                        : AppColors.borderSoft,
                    width: highlight ? 1.5 : 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(
                    color: highlight
                        ? AppColors.brandSoftBorder
                        : AppColors.borderSoft,
                    width: highlight ? 1.5 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.brand, width: 1.8),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
            )),
      ],
    );
  }

}
