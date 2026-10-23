import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/portal_settings_api.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'widgets/agent_code_tab.dart';
import 'widgets/link_image_preview.dart';
import '../desktop/desk_widgets.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/platform/desktop_layout.dart';

/// شاشة "بوابة المشترك" — مطابقة PortalSettings.tsx في client-v2.
/// tabs:
///   • رمز الوكيل (الرمز + نسخ/مشاركة/تغيير + مفتاح البوّابة + آخر دخول)
///     — أوّلاً: هو ما يحتاجه المشترك ليدخل تطبيق MyServices 2.0.7.
///   • معلومات الشركة (branding: اسم، شعار، تواصل، نبذة)
///   • وصف الباقات (list of packages مع override للاسم/الوصف/الصورة/الترتيب/إخفاء)
///
/// ١٨ أكتوبر (وسيط البوّابة): الشاشة لكلّ فاعل ولكلّ المزوّدين — الرمز يحتاجه
/// الموظّف أيضاً. والتبويبان الأخيران بـ`settings.edit`: مقفلان بمكانهما لموظّفٍ
/// يمكن أن يُمنحه، ومخفيّان عن موظّف ايرث لنك (لا يُمنح له — [permShown])،
/// فيبقى له تبويب الرمز وحده بلا شريط تبويبات.
class PortalSettingsScreen extends StatefulWidget {
  const PortalSettingsScreen({super.key});

  @override
  State<PortalSettingsScreen> createState() => _PortalSettingsScreenState();
}

class _PortalSettingsScreenState extends State<PortalSettingsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tab;

  /// تبويبا التخصيص ظاهران (مفتوحَين أو مقفلَين)؟ — يُقرأ مرّةً عند الفتح.
  late final bool _showCustomize = permShown(const ['settings.edit']);
  late final bool _canCustomize = Perms.has('settings.edit');

  @override
  void initState() {
    super.initState();
    if (_showCustomize) _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tab = _tab;
    return Scaffold(
      backgroundColor: DesktopScope.of(context) ? AppColors.bg : AppColors.surface,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: true,
          title: Text(
            'portal.title'.tr(),
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
          ),
          iconTheme: IconThemeData(color: AppColors.textHi),
          bottom: tab == null
              ? null
              : TabBar(
                  controller: tab,
                  indicatorColor: AppColors.brand,
                  labelColor: AppColors.brand,
                  unselectedLabelColor: AppColors.textMid,
                  labelStyle: AppType.button().copyWith(fontSize: 13),
                  // ٣٢٠: ثلاث تسمياتٍ بعرضٍ متساوٍ لا تُقصّ («معلومات الشركة»
                  // أطولها) — والحشوة الافتراضيّة ١٦ تأكل منها.
                  labelPadding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                  tabs: [
                    Tab(text: 'portal.tab_agent'.tr()),
                    Tab(text: 'portal.tab_info'.tr()),
                    Tab(text: 'portal.tab_packages'.tr()),
                  ],
                ),
        ),
      ),
      body: tab == null
          ? const AgentCodeTab()
          : TabBarView(
              controller: tab,
              children: [
                const AgentCodeTab(),
                if (_canCustomize) const _InfoTab() else const _LockedTab(),
                if (_canCustomize)
                  const _PackagesTab()
                else
                  const _LockedTab(),
              ],
            ),
    );
  }
}

/// تبويبٌ لا يملك الموظّف مفتاحه (`settings.edit`): بمكانه بقفلٍ هادئ — لا
/// طلب شبكة ولا «تعذّر الجلب» (الخادم لا يُسأل عمّا لا يُعرض).
class _LockedTab extends StatelessWidget {
  const _LockedTab();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(Sp.xxl),
        child: LockedNotice.block(),
      ),
    );
  }
}

/// قسمٌ لا يخدمه الخادم لشركتك بعد ([PortalLoad.unsupported]) أو تعذّر
/// تحميله ([PortalLoad.failed] — بزرّ «إعادة المحاولة»). يُسحب للتحديث.
class _TabNotice extends StatelessWidget {
  const _TabNotice({required this.state, required this.onRetry, this.what});
  final PortalLoad state;
  final Future<void> Function() onRetry;

  /// نصّ «غير متوفّر لشركتك بعد» الخاصّ بالقسم.
  final String? what;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final failed = state == PortalLoad.failed;
    return RefreshIndicator(
      onRefresh: onRetry,
      color: AppColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(Sp.xxl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(failed ? LucideIcons.circleAlert : LucideIcons.info,
                    size: 32, color: AppColors.textLow),
                const SizedBox(height: Sp.md),
                Text(
                  failed
                      ? 'portal.load_failed'.tr()
                      : (what ?? 'portal.unavailable_company'.tr()),
                  textAlign: TextAlign.center,
                  style: AppType.body(color: AppColors.textMid)
                      .copyWith(height: 1.6),
                ),
                if (failed) ...[
                  const SizedBox(height: Sp.sm),
                  TextButton(
                    onPressed: onRetry,
                    child: Text('common.retry'.tr()),
                  ),
                ],
              ],
            ),
          ),
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
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  /// ⚠️ لا نموذج إلّا بعد [PortalLoad.ok]: نموذجٌ فارغ بعد إخفاقٍ يرسل عند
  /// الحفظ الحقول كلّها null فيمسح ما خزّنه المدير.
  PortalLoad _state = PortalLoad.ok;

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
    final r = await PortalSettingsApi.loadBranding();
    if (!mounted) return;
    setState(() {
      _state = r.state;
      if (r.state == PortalLoad.ok) _fill(r.branding);
      _loading = false;
      _dirty = false;
    });
  }

  void _fill(Branding b) {
    _displayName.text = b.displayName ?? '';
    _logoUrl.text = b.logoUrl ?? '';
    _about.text = b.aboutText ?? '';
    _supportPhone.text = b.supportPhone ?? '';
    _whatsappNumber.text = b.whatsappNumber ?? '';
    _facebookUrl.text = b.facebookUrl ?? '';
    _instagramUrl.text = b.instagramUrl ?? '';
    _telegramUrl.text = b.telegramUrl ?? '';
  }

  Branding _form() => Branding(
        displayName: _nullIfEmpty(_displayName.text),
        logoUrl: _nullIfEmpty(_logoUrl.text),
        aboutText: _nullIfEmpty(_about.text),
        supportPhone: _nullIfEmpty(_supportPhone.text),
        whatsappNumber: _nullIfEmpty(_whatsappNumber.text),
        facebookUrl: _nullIfEmpty(_facebookUrl.text),
        instagramUrl: _nullIfEmpty(_instagramUrl.text),
        telegramUrl: _nullIfEmpty(_telegramUrl.text),
      );

  void _mark() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final b = _form();
    final r = await PortalSettingsApi.saveBranding(b);
    if (!mounted) return;
    setState(() {
      _saving = false;
      // ما كُتب **أثناء** الحفظ لم يُرسَل: يبقى الزرّ، ولا يُكتب فوقه.
      if (r.ok && _same(_form(), b)) {
        _dirty = false;
        // ما خزّنه الخادم فعلاً (قد يطبّع الصورة أو الرقم) — فتعرض الحقول
        // والمعاينة ما سيراه المشترك.
        final saved = r.saved;
        if (saved != null) _fill(saved);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // رفض الخادم بسببه («رابط صفحة لا صورة») — أدقّ من «فشل الحفظ».
        content: Text(r.ok
            ? 'portal.saved'.tr()
            : (r.message ?? 'portal.save_failed'.tr())),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: r.message == null ? 4 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state != PortalLoad.ok) {
      return _TabNotice(
        state: _state,
        onRetry: _load,
        what: 'portal.unsupported_info'.tr(),
      );
    }
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge + 64),
          children: [
            // preview — يتبع الحقلين مع كلّ حرف (كان يُرسم مرّةً عند أوّل
            // تعديل فقط، لأنّ `_mark` لا يعيد البناء بعدها).
            ListenableBuilder(
              listenable: Listenable.merge([_logoUrl, _displayName]),
              builder: (_, __) => _PreviewCard(
                logoUrl: _logoUrl.text.trim(),
                displayName: _displayName.text.trim(),
              ),
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
                                valueColor:
                                    AlwaysStoppedAnimation(AppColors.onBrand),
                              ),
                            )
                          : Text(
                              'portal.save'.tr(),
                              style: AppType.button(color: AppColors.onBrand),
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
    return LinkImagePreview(
      url: logoUrl,
      size: 48,
      builder: (context, image, state) {
        // رابطٌ ليس صورة (صفحة مشاركة · رابطٌ ميّت) يقولها صراحةً — كانت
        // أيقونة الحقل الفارغ نفسها، فلا يعرف المدير أنّ شعاره لن يظهر.
        final broken = state == LinkImageState.broken;
        return Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: AppColors.brandSoftBg,
            border: Border.all(color: AppColors.brandSoftBorder),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(
                      color: broken
                          ? AppColors.dangerSoftBorder
                          : AppColors.brandSoftBorder),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: image ??
                    Icon(broken ? LucideIcons.imageOff : LucideIcons.image,
                        size: 20,
                        color: broken ? AppColors.error : AppColors.textMid),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty
                          ? 'portal.preview_empty'.tr()
                          : displayName,
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      broken
                          ? 'portal.not_image'.tr()
                          : 'portal.preview_sub'.tr(),
                      style: AppType.subtitle(
                              color:
                                  broken ? AppColors.error : AppColors.textMid)
                          .copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// معاينة صورة الباقة تحت حقلها — لا شيء للحقل الفارغ، والصورة حين تُحمَّل،
/// و«الرابط ليس صورة» حين لا تكون.
class _PackageImagePreview extends StatelessWidget {
  const _PackageImagePreview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return LinkImagePreview(
      url: url,
      size: 44,
      fit: BoxFit.cover,
      builder: (context, image, state) {
        if (state == LinkImageState.none) return const SizedBox.shrink();
        final broken = state == LinkImageState.broken;
        return Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: broken ? AppColors.dangerSoftBg : AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: image ??
                    Icon(broken ? LucideIcons.imageOff : LucideIcons.image,
                        size: 18,
                        color: broken ? AppColors.error : AppColors.textLow),
              ),
              if (broken) ...[
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    'portal.not_image'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.subtitle(color: AppColors.error)
                        .copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ],
          ),
        );
      },
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

  /// «لا توجد باقات» لقائمةٍ وصلت فارغةً فقط — لا لشبكةٍ انقطعت.
  PortalLoad _state = PortalLoad.ok;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await PortalSettingsApi.loadPackages();
    if (!mounted) return;
    setState(() {
      _state = r.state;
      _packages = r.packages;
      _loading = false;
    });
  }

  Future<void> _editPackage(PortalPackage p) async {
    final result = await showAppSheet<PortalPackage?>(
      barrierColor: AppColors.scrim,
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
    final r =
        await PortalSettingsApi.updatePackage(p.profileId, isHidden: next);
    if (!mounted) return;
    if (!r.ok) {
      // rollback
      setState(() {
        _packages = _packages
            .map((x) => x.profileId == p.profileId
                ? x.copyWith(isHidden: p.isHidden)
                : x)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message ?? 'portal.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
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
    if (_state != PortalLoad.ok) {
      return _TabNotice(
        state: _state,
        onRetry: _load,
        what: 'portal.unsupported_packages'.tr(),
      );
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

  /// قائمةٌ وصلت فارغة — وقد تكون تعذّراً عند المزوّد: الخادم يردّ `[]` لا
  /// خطأً (قائمة ايرث لنك من الوسيط عند أيّ إخفاق، و`_fetchAdminPackages`
  /// لساس). فيُسحب للتحديث أو «إعادة المحاولة» بمكانه، لا مغادرة الشاشة.
  Widget _empty() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.brand,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(Sp.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.package,
                        size: 48,
                        color: AppColors.textMid.withValues(alpha: 0.5)),
                    const SizedBox(height: Sp.md),
                    Text(
                      'portal.packages_empty'
                          .tr(namedArgs: {'source': _source()}),
                      textAlign: TextAlign.center,
                      style: AppType.subtitle(color: AppColors.textMid),
                    ),
                    const SizedBox(height: Sp.sm),
                    TextButton(
                      onPressed: _load,
                      child: Text('common.retry'.tr()),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
            border:
                Border.all(color: AppColors.textMid.withValues(alpha: 0.15)),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              // thumbnail
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: pkg.imageUrl != null && pkg.imageUrl!.isNotEmpty
                    ? Image.network(
                        pkg.imageUrl!,
                        fit: BoxFit.cover,
                        // صورةٌ لا تُحمَّل (صفحة مشاركة · رابطٌ ميّت) تُرى
                        // من القائمة نفسها لا بعد فتح الباقة.
                        errorBuilder: (_, __, ___) =>
                            Icon(LucideIcons.imageOff, color: AppColors.error),
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
                              color: AppColors.dangerSoftBg,
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                            child: Text(
                              'portal.hidden'.tr(),
                              style: AppType.button(color: AppColors.error)
                                  .copyWith(fontSize: 10.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (hasOverride) ...[
                          // ⚠️ `Flexible` — بدونه `ellipsis` أدناه **حبرٌ
                          // على ورق**: ابن `Row` غير المرن يُقاس بعرضٍ
                          // غير محدود، فلا يبلغ حدَّه أبداً ولا يُقصّ،
                          // بل يفيض الصفّ. الإعلان كان موجوداً والأثر
                          // معدوماً.
                          Flexible(
                            child: Text(
                              pkg.sasName,
                              style: AppType.subtitle(color: AppColors.textMid)
                                  .copyWith(fontSize: 10.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: Sp.sm),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.textMid,
                              borderRadius: BorderRadius.circular(R.pill),
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
              Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textMid),
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
    final r = await PortalSettingsApi.updatePackage(
      widget.pkg.profileId,
      displayName: _nullIfEmpty(_displayName.text),
      description: _nullIfEmpty(_description.text),
      imageUrl: _nullIfEmpty(_imageUrl.text),
      displayOrder: _order,
      isHidden: _hidden,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
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
          // رفض الخادم بسببه («رابط صفحة لا صورة») — أدقّ من «فشل الحفظ».
          content: Text(r.message ?? 'portal.save_failed'.tr()),
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: r.message == null ? 4 : 6),
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
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        content: Text('portal.reset_body'.tr(namedArgs: {'source': _source()}),
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
          backgroundColor: AppColors.errorFill,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.package,
        title: widget.pkg.sasName,
        subtitle: "${'portal.original_price'.tr()}: ${widget.pkg.price} د.ع",
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'common.save'.tr(),
        icon: LucideIcons.save,
        busy: _saving,
        onPressed: _save,
        leading: SheetFooterIconButton(
          icon: LucideIcons.rotateCcw,
          color: AppColors.error,
          onTap: _saving ? null : _reset,
        ),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    helperText: 'portal.pkg_display_name_hint'
                        .tr(namedArgs: {'source': _source()}),
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
                    helperText: 'portal.image_link_hint'.tr(),
                  ),
                  // معاينةٌ حيّة مع الكتابة — لم يكن للصورة معاينةٌ أصلاً.
                  ListenableBuilder(
                    listenable: _imageUrl,
                    builder: (_, __) =>
                        _PackageImagePreview(url: _imageUrl.text.trim()),
                  ),
                  const SizedBox(height: Sp.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'portal.pkg_display_order'.tr(),
                          style: AppType.subtitle(color: AppColors.textMid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.minus, size: 16),
                        onPressed: () => setState(
                            () => _order = (_order - 10).clamp(0, 999)),
                      ),
                      Container(
                        width: 48,
                        alignment: Alignment.center,
                        child: Text('$_order',
                            style: AppType.title(color: AppColors.textHi)),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.plus, size: 16),
                        onPressed: () => setState(
                            () => _order = (_order + 10).clamp(0, 999)),
                      ),
                    ],
                  ),
                  // Material شفّاف ليجد ListTile سطحه — وإلّا «ListTile
                  // background color or ink splashes may be invisible» داخل
                  // سطح DesignSheet الملوّن (كمحرّر الموظّف). لا تغيير في المظهر.
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      value: _hidden,
                      onChanged: (v) => setState(() => _hidden = v),
                      title: Text('portal.pkg_hidden'.tr(),
                          style: AppType.subtitle(color: AppColors.textHi)),
                      subtitle: Text('portal.pkg_hidden_hint'.tr(),
                          style: AppType.subtitle(color: AppColors.textMid)
                              .copyWith(fontSize: 10.5)),
                      activeThumbColor: AppColors.brand,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          style:
              AppType.title(color: AppColors.textHi).copyWith(fontSize: 12.5)),
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
          hintStyle:
              AppType.subtitle(color: AppColors.textMid.withValues(alpha: 0.5)),
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide:
                BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.sm),
            borderSide:
                BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
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
                .copyWith(fontSize: 10.5, height: 1.4)),
      ],
    ],
  );
}

String? _nullIfEmpty(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// مصدر الباقات وأسمائها الأصليّة كما يقوله المالك — «ايرث لنك» لحسابها
/// (قائمتها من الوسيط)، و«SAS» لغيرها. كان النصّ «SAS» للجميع.
String _source() => (ProviderService.isEarthlink
        ? 'portal.source_earthlink'
        : 'portal.source_sas')
    .tr();

bool _same(Branding a, Branding b) =>
    a.displayName == b.displayName &&
    a.logoUrl == b.logoUrl &&
    a.aboutText == b.aboutText &&
    a.supportPhone == b.supportPhone &&
    a.whatsappNumber == b.whatsappNumber &&
    a.facebookUrl == b.facebookUrl &&
    a.instagramUrl == b.instagramUrl &&
    a.telegramUrl == b.telegramUrl;
