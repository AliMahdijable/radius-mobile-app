import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/api_client.dart';
import '../../api/receipt_settings_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/print_feedback.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';

/// شاشة "قوالب الطباعة" — **read-only** في التطبيق، والتصميم من الويب
/// (`/v2/print-templates` ← `receipt_settings`).
///
/// تعرض إعدادات وصل الموقع التي يطبع بها التطبيق كلّ وصولاته لكلّ المزوّدين منذ ٢٤ أكتوبر
/// ([ReceiptService]) — كانت للساس قوالب `print_templates` الكلاسيكيّة التي لا يقرؤها الموقع،
/// فيخرج وصل التطبيق غير وصل الموقع. وزرّ المعاينة يطبع وصلاً تجريبيّاً بها.
class PrintTemplatesScreen extends StatefulWidget {
  const PrintTemplatesScreen({super.key});

  @override
  State<PrintTemplatesScreen> createState() => _PrintTemplatesScreenState();
}

class _PrintTemplatesScreenState extends State<PrintTemplatesScreen> {
  bool _loading = true;

  /// إعدادات وصل الويب، و`null` إن تعذّر جلبها.
  ReceiptSettings? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // جديدٌ دائماً (والطباعة تجده مخبّأً بعدها).
    final r = await ReceiptSettingsApi.fetch(force: true);
    if (!mounted) return;
    setState(() {
      _receipt = r;
      _loading = false;
    });
  }

  /// وصلٌ تجريبيّ بتصميم الحساب وبالشكل المختار في «الطابعة الافتراضية» — كما يخرج بعد التفعيل.
  Future<void> _preview() async {
    final r = await ReceiptService.printSample(_receipt);
    if (mounted) showPrintResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
                children: [
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
                    onPreview: _preview,
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



/// إعدادات وصل الويب كما يطبع بها التطبيق — للقراءة، والتعديل من المصمّم على الويب.
/// [settings] `null` ← تعذّر الجلب (يُطبع باسم الحساب).
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
          // ما يحكم الطباعة نفسها (لا الشكل): رمز QR والطباعة بعد العمليّة بلا سؤال.
          if (s != null) ...[
            if (!custom) const SizedBox(height: Sp.sm),
            _WebReceiptRow(
              label: 'print_templates.qr'.tr(),
              value: (s.showQr ? 'print_templates.on' : 'print_templates.off').tr(),
            ),
            _WebReceiptRow(
              label: 'print_templates.auto_print'.tr(),
              value: (s.autoPrint ? 'print_templates.on' : 'print_templates.off').tr(),
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
