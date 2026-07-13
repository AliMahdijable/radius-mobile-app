import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/portal_settings_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشة "بوابة المشترك" — مطابقة PortalSettings.tsx في client-v2.
/// tabs:
///   • معلومات الشركة (branding: اسم، شعار، تواصل، نبذة)
///   • وصف الباقات (list of packages مع override للاسم/الوصف/الصورة/الترتيب/إخفاء)
class PortalSettingsScreen extends StatefulWidget {
  const PortalSettingsScreen({super.key});

  @override
  State<PortalSettingsScreen> createState() => _PortalSettingsScreenState();
}

class _PortalSettingsScreenState extends State<PortalSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'portal.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.brand,
          labelColor: AppColors.brand,
          unselectedLabelColor: AppColors.textMid,
          labelStyle: AppType.button().copyWith(fontSize: 13),
          tabs: [
            Tab(text: 'portal.tab_info'.tr()),
            Tab(text: 'portal.tab_packages'.tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _InfoTab(),
          _PackagesTab(),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// معلومات الشركة (Branding)
// ═════════════════════════════════════════════
class _InfoTab extends StatefulWidget {
  const _InfoTab();
  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  Branding? _draft;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  final _displayName = TextEditingController();
  final _logoUrl = TextEditingController();
  final _about = TextEditingController();
  final _supportPhone = TextEditingController();
  final _whatsappNumber = TextEditingController();
  final _facebookUrl = TextEditingController();
  final _instagramUrl = TextEditingController();
  final _telegramUrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _logoUrl.dispose();
    _about.dispose();
    _supportPhone.dispose();
    _whatsappNumber.dispose();
    _facebookUrl.dispose();
    _instagramUrl.dispose();
    _telegramUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final b = await PortalSettingsApi.getBranding();
    if (!mounted) return;
    setState(() {
      _draft = b;
      _displayName.text = b.displayName ?? '';
      _logoUrl.text = b.logoUrl ?? '';
      _about.text = b.aboutText ?? '';
      _supportPhone.text = b.supportPhone ?? '';
      _whatsappNumber.text = b.whatsappNumber ?? '';
      _facebookUrl.text = b.facebookUrl ?? '';
      _instagramUrl.text = b.instagramUrl ?? '';
      _telegramUrl.text = b.telegramUrl ?? '';
      _loading = false;
      _dirty = false;
    });
  }

  void _mark() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final b = Branding(
      displayName: _nullIfEmpty(_displayName.text),
      logoUrl: _nullIfEmpty(_logoUrl.text),
      aboutText: _nullIfEmpty(_about.text),
      supportPhone: _nullIfEmpty(_supportPhone.text),
      whatsappNumber: _nullIfEmpty(_whatsappNumber.text),
      facebookUrl: _nullIfEmpty(_facebookUrl.text),
      instagramUrl: _nullIfEmpty(_instagramUrl.text),
      telegramUrl: _nullIfEmpty(_telegramUrl.text),
    );
    final ok = await PortalSettingsApi.saveBranding(b);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _draft = b;
        _dirty = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'portal.saved'.tr() : 'portal.save_failed'.tr()),
        backgroundColor: ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge + 64),
          children: [
            // preview
            _PreviewCard(
              logoUrl: _logoUrl.text.trim(),
              displayName: _displayName.text.trim(),
            ),
            const SizedBox(height: Sp.lg),

            _sectionLabel('portal.info_basic'.tr(), LucideIcons.info),
            const SizedBox(height: Sp.sm),
            _labeledField(
              label: 'portal.display_name'.tr(),
              hint: 'portal.display_name_hint'.tr(),
              controller: _displayName,
              onChanged: (_) => _mark(),
              maxLength: 200,
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.logo_url'.tr(),
              hint: 'https://example.com/logo.png',
              controller: _logoUrl,
              onChanged: (_) => _mark(),
              maxLength: 500,
              keyboardType: TextInputType.url,
              helperText: 'portal.logo_hint'.tr(),
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.about'.tr(),
              hint: 'portal.about_hint'.tr(),
              controller: _about,
              onChanged: (_) => _mark(),
              maxLength: 5000,
              maxLines: 4,
            ),

            const SizedBox(height: Sp.lg),
            _sectionLabel('portal.info_contact'.tr(), LucideIcons.phone),
            const SizedBox(height: Sp.sm),
            _labeledField(
              label: 'portal.support_phone'.tr(),
              hint: '07XXXXXXXXX',
              controller: _supportPhone,
              onChanged: (_) => _mark(),
              maxLength: 30,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.whatsapp_number'.tr(),
              hint: '07XXXXXXXXX',
              controller: _whatsappNumber,
              onChanged: (_) => _mark(),
              maxLength: 30,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.telegram'.tr(),
              hint: '@channel or https://t.me/...',
              controller: _telegramUrl,
              onChanged: (_) => _mark(),
              maxLength: 500,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.facebook'.tr(),
              hint: 'https://facebook.com/...',
              controller: _facebookUrl,
              onChanged: (_) => _mark(),
              maxLength: 500,
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: Sp.md),
            _labeledField(
              label: 'portal.instagram'.tr(),
              hint: 'https://instagram.com/...',
              controller: _instagramUrl,
              onChanged: (_) => _mark(),
              maxLength: 500,
              keyboardType: TextInputType.url,
            ),
          ],
        ),

        // Save button pinned to bottom
        if (_dirty)
          Positioned(
            left: Sp.lg,
            right: Sp.lg,
            bottom: Sp.lg,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: Material(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(R.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _saving ? null : _save,
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text(
                              'portal.save'.tr(),
                              style: AppType.button(color: Colors.white),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.logoUrl, required this.displayName});
  final String logoUrl;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.06),
        border: Border.all(color: AppColors.brand.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.brand.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: logoUrl.isEmpty
                ? Icon(LucideIcons.image, size: 20, color: AppColors.textMid)
                : Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(LucideIcons.image, size: 20, color: AppColors.textMid),
                  ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isEmpty ? 'portal.preview_empty'.tr() : displayName,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'portal.preview_sub'.tr(),
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// وصف الباقات
// ═════════════════════════════════════════════
class _PackagesTab extends StatefulWidget {
  const _PackagesTab();
  @override
  State<_PackagesTab> createState() => _PackagesTabState();
}

class _PackagesTabState extends State<_PackagesTab> {
  List<PortalPackage> _packages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PortalSettingsApi.getPackages();
    if (!mounted) return;
    setState(() {
      _packages = list;
      _loading = false;
    });
  }

  Future<void> _editPackage(PortalPackage p) async {
    final result = await showModalBottomSheet<PortalPackage?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageEditorSheet(pkg: p),
    );
    if (result != null && mounted) {
      setState(() {
        _packages = _packages
            .map((x) => x.profileId == result.profileId ? result : x)
            .toList();
      });
    }
  }

  Future<void> _toggleHidden(PortalPackage p) async {
    final next = !p.isHidden;
    setState(() {
      _packages = _packages
          .map((x) =>
              x.profileId == p.profileId ? x.copyWith(isHidden: next) : x)
          .toList();
    });
    final ok = await PortalSettingsApi.updatePackage(p.profileId, isHidden: next);
    if (!mounted) return;
    if (!ok) {
      // rollback
      setState(() {
        _packages = _packages
            .map((x) =>
                x.profileId == p.profileId ? x.copyWith(isHidden: p.isHidden) : x)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('portal.save_failed'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_packages.isEmpty) {
      return _empty();
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.brand,
      child: ListView.separated(
        padding: const EdgeInsets.all(Sp.lg),
        itemCount: _packages.length,
        separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
        itemBuilder: (_, i) {
          final p = _packages[i];
          return _PackageRow(
            pkg: p,
            onEdit: () => _editPackage(p),
            onToggleHidden: () => _toggleHidden(p),
          );
        },
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.package,
                size: 48, color: AppColors.textMid.withOpacity(0.5)),
            const SizedBox(height: Sp.md),
            Text(
              'portal.packages_empty'.tr(),
              textAlign: TextAlign.center,
              style: AppType.subtitle(color: AppColors.textMid),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
    required this.pkg,
    required this.onEdit,
    required this.onToggleHidden,
  });
  final PortalPackage pkg;
  final VoidCallback onEdit;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final hasOverride = pkg.displayName != null && pkg.displayName!.isNotEmpty;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textMid.withOpacity(0.15)),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              // thumbnail
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: pkg.imageUrl != null && pkg.imageUrl!.isNotEmpty
                    ? Image.network(
                        pkg.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(LucideIcons.image, color: AppColors.brand),
                      )
                    : Icon(LucideIcons.package, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pkg.effectiveName,
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pkg.isHidden)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: Sp.sm, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                            child: Text(
                              'portal.hidden'.tr(),
                              style: AppType.button(color: AppColors.error)
                                  .copyWith(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (hasOverride) ...[
                          Text(
                            pkg.sasName,
                            style: AppType.subtitle(color: AppColors.textMid)
                                .copyWith(fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: Sp.sm),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.textMid,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: Sp.sm),
                        ],
                        Text(
                          '${pkg.price} د.ع',
                          style: AppType.button(color: AppColors.brand)
                              .copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  pkg.isHidden ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 18,
                  color: pkg.isHidden ? AppColors.error : AppColors.brand,
                ),
                tooltip: pkg.isHidden
                    ? 'portal.show_to_subs'.tr()
                    : 'portal.hide_from_subs'.tr(),
                onPressed: onToggleHidden,
              ),
              Icon(LucideIcons.chevronLeft,
                  size: 18, color: AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// Package Editor (Bottom Sheet)
// ═════════════════════════════════════════════
class _PackageEditorSheet extends StatefulWidget {
  const _PackageEditorSheet({required this.pkg});
  final PortalPackage pkg;

  @override
  State<_PackageEditorSheet> createState() => _PackageEditorSheetState();
}

class _PackageEditorSheetState extends State<_PackageEditorSheet> {
  late final TextEditingController _displayName;
  late final TextEditingController _description;
  late final TextEditingController _imageUrl;
  late int _order;
  late bool _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(text: widget.pkg.displayName ?? '');
    _description = TextEditingController(text: widget.pkg.description ?? '');
    _imageUrl = TextEditingController(text: widget.pkg.imageUrl ?? '');
    _order = widget.pkg.displayOrder;
    _hidden = widget.pkg.isHidden;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _description.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await PortalSettingsApi.updatePackage(
      widget.pkg.profileId,
      displayName: _nullIfEmpty(_displayName.text),
      description: _nullIfEmpty(_description.text),
      imageUrl: _nullIfEmpty(_imageUrl.text),
      displayOrder: _order,
      isHidden: _hidden,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(widget.pkg.copyWith(
        displayName: _nullIfEmpty(_displayName.text),
        description: _nullIfEmpty(_description.text),
        imageUrl: _nullIfEmpty(_imageUrl.text),
        displayOrder: _order,
        isHidden: _hidden,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('portal.save_failed'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('portal.reset_title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text('portal.reset_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.confirm'.tr(),
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    final ok = await PortalSettingsApi.resetPackage(widget.pkg.profileId);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(PortalPackage(
        profileId: widget.pkg.profileId,
        sasName: widget.pkg.sasName,
        price: widget.pkg.price,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('portal.save_failed'.tr()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xl)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // grabber
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMid.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
              Text(
                widget.pkg.sasName,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                '${'portal.original_price'.tr()}: ${widget.pkg.price} د.ع',
                style: AppType.subtitle(color: AppColors.textMid),
              ),
              const SizedBox(height: Sp.lg),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _labeledField(
                        label: 'portal.pkg_display_name'.tr(),
                        hint: widget.pkg.sasName,
                        controller: _displayName,
                        maxLength: 200,
                        helperText: 'portal.pkg_display_name_hint'.tr(),
                      ),
                      const SizedBox(height: Sp.md),
                      _labeledField(
                        label: 'portal.pkg_description'.tr(),
                        hint: 'portal.pkg_description_hint'.tr(),
                        controller: _description,
                        maxLength: 5000,
                        maxLines: 4,
                      ),
                      const SizedBox(height: Sp.md),
                      _labeledField(
                        label: 'portal.pkg_image_url'.tr(),
                        hint: 'https://example.com/pkg.png',
                        controller: _imageUrl,
                        maxLength: 500,
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: Sp.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text('portal.pkg_display_order'.tr(),
                                style:
                                    AppType.subtitle(color: AppColors.textMid)),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.minus, size: 16),
                            onPressed: () =>
                                setState(() => _order = (_order - 10).clamp(0, 999)),
                          ),
                          Container(
                            width: 48,
                            alignment: Alignment.center,
                            child: Text('$_order',
                                style: AppType.title(color: AppColors.textHi)),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.plus, size: 16),
                            onPressed: () =>
                                setState(() => _order = (_order + 10).clamp(0, 999)),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        value: _hidden,
                        onChanged: (v) => setState(() => _hidden = v),
                        title: Text('portal.pkg_hidden'.tr(),
                            style: AppType.subtitle(color: AppColors.textHi)),
                        subtitle: Text('portal.pkg_hidden_hint'.tr(),
                            style: AppType.subtitle(color: AppColors.textMid)
                                .copyWith(fontSize: 10)),
                        activeColor: AppColors.brand,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Sp.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _reset,
                      icon: Icon(LucideIcons.rotateCcw,
                          size: 16, color: AppColors.error),
                      label: Text('portal.reset'.tr(),
                          style: TextStyle(color: AppColors.error)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(R.md)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : Text('portal.save'.tr(),
                              style: AppType.button(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// helpers
// ═════════════════════════════════════════════
Widget _sectionLabel(String text, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 14, color: AppColors.brand),
      const SizedBox(width: Sp.xs),
      Text(text,
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 12)),
    ],
  );
}

Widget _labeledField({
  required String label,
  required String hint,
  required TextEditingController controller,
  ValueChanged<String>? onChanged,
  int? maxLength,
  int? maxLines = 1,
  TextInputType? keyboardType,
  String? helperText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: controller,
        onChanged: onChanged,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: AppType.subtitle(color: AppColors.textHi),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppType.subtitle(color: AppColors.textMid.withOpacity(0.5)),
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.textMid.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.textMid.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide: BorderSide(color: AppColors.brand),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          counterText: '',
        ),
      ),
      if (helperText != null) ...[
        const SizedBox(height: 4),
        Text(helperText,
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(fontSize: 10, height: 1.4)),
      ],
    ],
  );
}

String? _nullIfEmpty(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}
