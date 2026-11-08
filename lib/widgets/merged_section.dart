import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/company_route.dart';
import '../models/merged_company.dart';
import '../services/active_company.dart';
import '../services/auth_storage.dart';
import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'merged_company_strip.dart';

/// ما يعرضه قسمٌ من «قوائم أخرى» الآن في «كل الشركات».
class MergedSectionInfo {
  const MergedSectionInfo({required this.company, required this.open, this.readOnly = false});

  /// القسم قراءةٌ وحدها لغير المفتوحة (كتاباته غير موجَّهة بعد) ⇒ الشريط يقول «للعرض هنا».
  final bool readOnly;

  /// الشركة المختارة في الشريط — null = «الكل» (تُعرض المفتوحة كما كانت).
  final MergedCompany? company;

  /// المعروضة هي الشركة المفتوحة (طلباتٌ عاديّة بلا توجيه).
  final bool open;

  /// شركةٌ غير المفتوحة: طلبات القسم موجَّهةٌ لها.
  bool get routed => company != null && !open;
}

/// «قوائم أخرى» بـ«كل الشركات» (٨ نوفمبر — المالك: «كل الاقسام مال قائمة المزيد لازم تخضع لهذا النظام شركتين بدقة»): يلفّ
/// شاشة القسم. الشركة المختارة في الشريط ([MergedMode.focus]) تُعرض بمكانها — طلبات بادئات القسم ([prefixes]) من أيّ زرٍّ أو
/// شيتٍ فيه موجَّهةٌ لها ما دام مفتوحاً ([CompanyRoute.enterSection]) — و«الكل» ⇒ الشركة المفتوحة كما كانت. الشاشة تُبنى من
/// جديد لكلّ شركة (لا تبقى أرقام شركةٍ تحت اسم أخرى). خارج «كل الشركات» لا أثر له.
class MergedSection extends StatefulWidget {
  const MergedSection({super.key, required this.prefixes, required this.child, this.readOnly = false});

  /// بادئات مسارات القسم كلّها (قراءاتٍ وكتابات) — ما لم يُذكر يذهب للشركة المفتوحة، فيُذكر كلّ ما يطلبه القسم وشيتاته.
  final List<String> prefixes;
  final Widget child;

  /// كتابات القسم غير موجَّهة بعد ⇒ غير المفتوحة للعرض وحده (والخادم يرفض كتابتها الموجَّهة أصلاً).
  final bool readOnly;

  /// ما يعرضه أقرب قسم — null خارج قسمٍ أو خارج «كل الشركات».
  static MergedSectionInfo? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MergedSectionScope>()?.info;

  @override
  State<MergedSection> createState() => _MergedSectionState();
}

class _MergedSectionState extends State<MergedSection> {
  String? _openAdmin;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    MergedMode.active.addListener(_changed);
    MergedMode.focus.addListener(_changed);
    _ready = !MergedMode.active.value;
    if (!_ready) _readOpen();
  }

  Future<void> _readOpen() async {
    try {
      _openAdmin = (await AuthStorage.readAdminId())?.trim();
    } catch (_) {
      _openAdmin = null; // لا تُعرف المفتوحة ⇒ كلّ شركةٍ مختارة موجَّهة (الكتابة يحكمها الخادم)
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  void _changed() {
    if (!mounted) return;
    if (MergedMode.active.value && !_ready) return;
    if (MergedMode.active.value && _openAdmin == null) {
      setState(() => _ready = false);
      _readOpen();
      return;
    }
    setState(() {});
  }

  MergedSectionInfo? get _info {
    if (!MergedMode.active.value) return null;
    final f = MergedMode.focused;
    if (f == null) return const MergedSectionInfo(company: null, open: true);
    final open = (_openAdmin ?? '').isNotEmpty && f.adminId == _openAdmin;
    return MergedSectionInfo(company: f, open: open, readOnly: widget.readOnly);
  }

  /// وجهة طلبات القسم — تُضبط قبل بناء الشاشة فيبدأ جلبها الأوّل موجَّهاً.
  void _apply(MergedSectionInfo? i) {
    if (i != null && i.routed) {
      CompanyRoute.enterSection(this, i.company!.key, widget.prefixes, adminId: i.company!.adminId);
    } else {
      CompanyRoute.leaveSection(this);
    }
  }

  @override
  void dispose() {
    MergedMode.active.removeListener(_changed);
    MergedMode.focus.removeListener(_changed);
    CompanyRoute.leaveSection(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final i = _info;
    _apply(i);
    return _MergedSectionScope(
      info: i,
      child: KeyedSubtree(
        key: ValueKey('merged-section-${i?.company?.key ?? 'open'}'),
        child: widget.child,
      ),
    );
  }
}

class _MergedSectionScope extends InheritedWidget {
  const _MergedSectionScope({required this.info, required super.child});
  final MergedSectionInfo? info;

  @override
  bool updateShouldNotify(_MergedSectionScope old) =>
      old.info?.company?.key != info?.company?.key || old.info?.open != info?.open;
}

/// شريط القسم في «كل الشركات» أعلى الشاشة: الشركات (والمختارة تُعرض بمكانها) ثمّ سطرٌ يقول ما يُعرض — المفتوحة («الكل»)،
/// أو شركةٌ للعرض بسببها ([lockedText] من الشاشة: الخادم لم يفتح كتابتها هنا)، أو شركةٌ تُدار من هنا. خارج الوضع لا شيء.
class MergedSectionBar extends StatelessWidget {
  const MergedSectionBar({
    super.key,
    this.lockedText,
    this.padding = const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
  });

  final String? lockedText;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!MergedMode.active.value) return const SizedBox.shrink();
    Theme.of(context); // theme-dep (dark-mode)
    final info = MergedSection.of(context);
    final String? text;
    final bool warn;
    if (info == null || info.company == null) {
      final open = ActiveCompany.current;
      text = 'merged.section_open'.tr(args: [open?.label ?? '—']);
      warn = false;
    } else if (lockedText != null) {
      text = lockedText;
      warn = true;
    } else if (info.routed && info.readOnly) {
      text = 'merged.section_locked'.tr(args: [info.company!.name]);
      warn = true;
    } else if (info.routed) {
      text = 'merged.section_routed'.tr(args: [info.company!.name]);
      warn = false;
    } else {
      text = null;
      warn = false;
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MergedCompanyStrip(),
          if (text != null) ...[
            const SizedBox(height: Sp.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
              decoration: BoxDecoration(
                color: warn ? AppColors.warningSoftBg : AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: warn ? AppTone.warning.fill.withValues(alpha: 0.35) : AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(warn ? LucideIcons.eye : LucideIcons.layers,
                        size: 15, color: warn ? AppTone.warning.onSoft : AppColors.textMid),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(color: warn ? AppTone.warning.onSoft : AppColors.textMid)
                          .copyWith(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// جسم شاشة قسمٍ في «كل الشركات»: [MergedSectionBar] فوقه — خارج الوضع أو خارج [MergedSection] الجسمُ نفسه حرفاً.
class MergedSectionBody extends StatelessWidget {
  const MergedSectionBody({super.key, required this.child, this.lockedText});
  final Widget child;
  final String? lockedText;

  @override
  Widget build(BuildContext context) {
    if (!MergedMode.active.value || MergedSection.of(context) == null) return child;
    return Column(
      children: [
        MergedSectionBar(lockedText: lockedText),
        Expanded(child: child),
      ],
    );
  }
}
