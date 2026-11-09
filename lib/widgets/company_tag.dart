import 'package:flutter/material.dart';

import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

/// «كل الشركات»: نقطة الشركة بلونها واسمها — تحت المشترك في القائمة، وفي رأس تفاصيله.
class CompanyTag extends StatelessWidget {
  const CompanyTag({super.key, required this.companyKey, this.fontSize = 11.5});

  final String companyKey;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = MergedMode.companyOf(companyKey);
    if (c == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.body(color: AppColors.textMid).copyWith(fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// شركة صفّ مشتركٍ في «كل الشركات» (رأس صفحته، كشف حسابه — التحقّق الثالث من 179): بمفتاحه ⇒ شارة شركته؛ بلا مفتاح ⇒ الشركة
/// المفتوحة (تُعرف بين الصالحة بمعرّف مديرها، وإلّا لا شيء). لا شيء خارج الوضع — الشاشات كما كانت حرفاً.
class RowCompanyTag extends StatefulWidget {
  const RowCompanyTag({super.key, required this.companyKey, this.fontSize = 11.5});

  final String? companyKey;
  final double fontSize;

  @override
  State<RowCompanyTag> createState() => _RowCompanyTagState();
}

class _RowCompanyTagState extends State<RowCompanyTag> {
  String? _openKey;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(RowCompanyTag old) {
    super.didUpdateWidget(old);
    if (old.companyKey != widget.companyKey) _resolve();
  }

  Future<void> _resolve() async {
    if (widget.companyKey != null || !MergedMode.active.value) return;
    final k = await MergedMode.openKey();
    if (mounted && k != _openKey) setState(() => _openKey = k);
  }

  @override
  Widget build(BuildContext context) {
    if (!MergedMode.active.value) return const SizedBox.shrink();
    final key = widget.companyKey ?? _openKey;
    return key == null ? const SizedBox.shrink() : CompanyTag(companyKey: key, fontSize: widget.fontSize);
  }
}
