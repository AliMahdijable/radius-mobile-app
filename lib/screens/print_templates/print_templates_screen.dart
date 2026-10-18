import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/api_client.dart';
import '../../api/print_templates_api.dart';
import '../../api/receipt_settings_api.dart';
import '../../core/util/bidi.dart';
import '../../services/auth_storage.dart';
import '../../services/print_prefs.dart';
import '../../services/print_service.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// شاشة "قوالب الطباعة" — **read-only** على الموبايل.
/// التحرير من الويب (rad.mysvcs.net/v2/print-templates). الموبايل يعرض
/// القوالب المحفوظة + زر طباعة تجريبية للتحقّق من الاتصال بالطابعة.
///
/// ايرث لنك: لا قوالب `print_templates` لها (لا يكتبها أيّ عميل منشور، وحسابها
/// جديدٌ في Pro) — فكانت «لم يُنشَأ بعد» دائماً، والبانر يحيل إلى مصمّمٍ لا يصل
/// التطبيقَ ما يُحفظ فيه. تعرض بدلها **إعدادات وصل الويب** (`receipt_settings`)
/// التي يطبع بها التطبيق وصلها ([ReceiptService.usesWebReceiptSettings]).
class PrintTemplatesScreen extends StatefulWidget {
  const PrintTemplatesScreen({super.key});

  @override
  State<PrintTemplatesScreen> createState() => _PrintTemplatesScreenState();
}

class _PrintTemplatesScreenState extends State<PrintTemplatesScreen> {
  List<PrintTemplate> _list = const [];
  bool _loading = true;

  /// ايرث لنك: إعدادات وصل الويب، و`null` إن تعذّر جلبها.
  ReceiptSettings? _receipt;

  bool get _web => ReceiptService.usesWebReceiptSettings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_web) {
      // جديدٌ دائماً (والطباعة تجده مخبّأً بعدها).
      final r = await ReceiptSettingsApi.fetch(force: true);
      if (!mounted) return;
      setState(() {
        _receipt = r;
        _loading = false;
      });
      return;
    }
    final list = await PrintTemplatesApi.list();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  /// معاينة وصل ايرث لنك: بياناتٌ تجريبيّة بترويسة الويب وتذييله، وبالشكل
  /// المختار في «الطابعة الافتراضية» — كما يخرج بعد التفعيل.
  Future<void> _testPrintWeb() async {
    final type = PrintPrefs.currentTemplateType;
    final b = ReceiptService.brandingFor(_receipt,
        displayName: await AuthStorage.readDisplayName());
    final ok = await PrintService.printReceipt(
      data: PrintService.sampleData,
      format: PrintService.formatForType(type),
      title: type == 'a4'
          ? 'print_templates.a4_default_name'.tr()
          : 'print_templates.pos_default_name'.tr(),
      documentName: 'Receipt-preview',
      companyName: b.companyName,
      branding: b.branding,
    );
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('print_templates.print_cancelled'.tr()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  PrintTemplate? _byType(String type) {
    for (final t in _list) {
      if (t.templateType == type) return t;
    }
    return null;
  }

  Future<void> _testPrint(PrintTemplate t) async {
    // 2026-07-13: نجرّب HTML template أوّلاً (تصميم الأدمن من الويب)،
    // وإذا فشل WebView (chromium crash على الإيموليتر) نلجأ لـprintReceipt
    // (PDF مبني بـpw widgets — يعمل بلا WebView).
    final format = PrintService.formatForType(t.templateType);
    final data = PrintService.sampleData;
    bool ok = false;
    if (t.content.trim().isNotEmpty) {
      final filled = PrintService.fillTemplate(t.content, data);
      ok = await PrintService.printHtml(
        html: filled,
        format: format,
        documentName: t.templateName,
      );
    }
    if (!ok) {
      // fallback: PDF مباشر
      ok = await PrintService.printReceipt(
        data: data,
        format: format,
        title: t.templateType == 'a4' ? 'فاتورة A4' : 'إيصال POS',
        documentName: t.templateName,
      );
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('print_templates.print_cancelled'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a4 = _byType('a4');
    final pos = _byType('pos');

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'print_templates.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr(),
            icon:
                Icon(LucideIcons.refreshCw, size: 18, color: AppColors.textHi),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
                children: _web
                    ? [
                        _WebOnlyBanner(
                          title: 'print_templates.el_banner_title'.tr(),
                          body: 'print_templates.el_banner_body'.tr(),
                          copyPath: '/v2/print-templates',
                        ),
                        const SizedBox(height: Sp.lg),
                        _sectionLabel(
                          'print_templates.el_section'.tr(),
                          LucideIcons.receipt,
                        ),
                        const SizedBox(height: Sp.sm),
                        _WebReceiptCard(
                          settings: _receipt,
                          onPreview: _testPrintWeb,
                        ),
                      ]
                    : [
                        // Banner: التحرير من الويب فقط
                        const _WebOnlyBanner(),
                        const SizedBox(height: Sp.lg),
                        _sectionLabel(
                          'print_templates.a4_section'.tr(),
                          LucideIcons.fileText,
                        ),
                        const SizedBox(height: Sp.sm),
                        _TemplateViewCard(
                          type: 'a4',
                          template: a4,
                          // زر المعاينة يظهر فقط للقالب الفعّال (طلب المستخدم)
                          onPreview: (a4 != null && a4.isActive)
                              ? () => _testPrint(a4)
                              : null,
                        ),
                        const SizedBox(height: Sp.lg),
                        _sectionLabel(
                          'print_templates.pos_section'.tr(),
                          LucideIcons.receipt,
                        ),
                        const SizedBox(height: Sp.sm),
                        _TemplateViewCard(
                          type: 'pos',
                          template: pos,
                          onPreview: (pos != null && pos.isActive)
                              ? () => _testPrint(pos)
                              : null,
                        ),
                      ],
              ),
            ),
    );
  }
}

Widget _sectionLabel(String text, IconData icon) => Row(
      children: [
        Icon(icon, size: 14, color: AppColors.brand),
        const SizedBox(width: Sp.xs),
        Text(text,
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 12.5)),
      ],
    );

class _WebOnlyBanner extends StatelessWidget {
  // الافتراضيّات نصّ الساس ورابطه كما كانا.
  const _WebOnlyBanner({
    this.title,
    this.body,
    this.copyPath = '/v2/portal-settings',
  });
  final String? title;
  final String? body;
  final String copyPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        border: Border.all(color: AppColors.brandSoftBorder),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppColors.brand),
              const SizedBox(width: Sp.sm),
              Text(
                title ?? 'print_templates.web_only_title'.tr(),
                style: AppType.title(color: AppColors.brand)
                    .copyWith(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text(
            body ?? 'print_templates.web_only_body'.tr(),
            style: AppType.subtitle(color: AppColors.textMid)
                .copyWith(fontSize: 11.5, height: 1.6),
          ),
          const SizedBox(height: Sp.sm),
          GestureDetector(
            onTap: () async {
              // رابط ويب الخادم نفسه (Pro ⇒ pro.mysvcs.net) لا الكلاسيك المثبَّت سابقاً.
              await Clipboard.setData(
                  ClipboardData(text: '${ApiClient.baseUrl}$copyPath'));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('common.copied'.tr()),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.brandSoftBorder),
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.link, size: 12, color: AppColors.brand),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      '${Uri.parse(ApiClient.baseUrl).host}/v2',
                      style: AppType.bodyBold(color: AppColors.brand),
                    ),
                  ),
                  Icon(LucideIcons.copy,
                      size: 12, color: AppColors.brandSoftBorder),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateViewCard extends StatelessWidget {
  const _TemplateViewCard({
    required this.type,
    required this.template,
    required this.onPreview,
  });
  final String type;
  final PrintTemplate? template;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final exists = template != null;
    final IconData typeIcon =
        type == 'a4' ? LucideIcons.fileText : LucideIcons.receipt;

    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(typeIcon, color: AppColors.brand, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  exists
                      ? template!.templateName
                      : (type == 'a4'
                          ? 'print_templates.a4_default_name'.tr()
                          : 'print_templates.pos_default_name'.tr()),
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: (exists && template!.isActive)
                        ? AppColors.brandSoftBg
                        : AppColors.textMid.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    exists
                        ? (template!.isActive
                            ? 'print_templates.active'.tr()
                            : 'print_templates.inactive'.tr())
                        : 'print_templates.not_created'.tr(),
                    style: AppType.button(
                      color: (exists && template!.isActive)
                          ? AppColors.brand
                          : AppColors.textMid,
                    ).copyWith(fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ),
          if (exists && onPreview != null)
            Material(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onPreview!();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.eye, size: 14, color: AppColors.brand),
                      const SizedBox(width: 4),
                      Text(
                        'print_templates.preview'.tr(),
                        style: AppType.button(color: AppColors.brand)
                            .copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ايرث لنك: إعدادات وصل الويب كما يطبع بها التطبيق — للقراءة، والتعديل من
/// المصمّم على الويب. [settings] `null` ← تعذّر الجلب (يُطبع باسم الحساب).
class _WebReceiptCard extends StatelessWidget {
  const _WebReceiptCard({required this.settings, required this.onPreview});
  final ReceiptSettings? settings;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = settings;
    final custom = s != null && s.isCustomized;
    final chip = s == null
        ? 'print_templates.el_failed'.tr()
        : custom
            ? 'print_templates.el_customized'.tr()
            : 'print_templates.el_not_customized'.tr();
    final hidden = 'print_templates.el_hidden'.tr();
    final logo = s?.logo;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                clipBehavior: Clip.antiAlias,
                child: logo != null && s!.showLogo
                    ? Image.memory(logo, fit: BoxFit.contain)
                    : Icon(LucideIcons.receipt,
                        color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s?.shopName ?? 'print_templates.el_card_title'.tr(),
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Sp.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: custom
                              ? AppColors.brandSoftBg
                              : AppColors.textMid.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                        child: Text(
                          chip,
                          style: AppType.button(
                            color: custom ? AppColors.brand : AppColors.textMid,
                          ).copyWith(fontSize: 10.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: AppColors.brandSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onPreview();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.md, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.eye, size: 14, color: AppColors.brand),
                        const SizedBox(width: 4),
                        Text(
                          'print_templates.preview'.tr(),
                          style: AppType.button(color: AppColors.brand)
                              .copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (custom) ...[
            const SizedBox(height: Sp.md),
            _WebReceiptRow(
              label: 'print_templates.el_address'.tr(),
              value: s.showShopInfo ? s.shopAddress : hidden,
            ),
            _WebReceiptRow(
              label: 'print_templates.el_phone'.tr(),
              value: s.showShopInfo ? s.shopPhone : hidden,
              ltr: s.showShopInfo,
            ),
            _WebReceiptRow(
              label: 'print_templates.el_footer'.tr(),
              value: !s.showFooter
                  ? hidden
                  : (s.footerText ?? 'print_templates.el_default_footer'.tr()),
            ),
          ] else ...[
            const SizedBox(height: Sp.sm),
            Text(
              (s == null
                      ? 'print_templates.el_failed_hint'
                      : 'print_templates.el_not_customized_hint')
                  .tr(),
              style: AppType.subtitle(color: AppColors.textMid)
                  .copyWith(fontSize: 11.5, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebReceiptRow extends StatelessWidget {
  const _WebReceiptRow({
    required this.label,
    required this.value,
    this.ltr = false,
  });
  final String label;
  final String? value;

  /// قيمةٌ لاتينيّة الاتّجاه (رقم الهاتف).
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final v = value?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: AppType.muted(color: AppColors.textMid)
                    .copyWith(fontSize: 11.5)),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : (ltr ? iso(v) : v),
              style: AppType.body(color: AppColors.textHi)
                  .copyWith(fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
