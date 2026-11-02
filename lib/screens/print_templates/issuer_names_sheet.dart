import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/receipt_issuer_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «أصدره» على الوصل (٢ نوفمبر — طلب المالك): اسمٌ عربيّ يختاره المدير لنفسه («المدراء كلها تجي admin@») ولكلّ موظّف، يُطبع
/// بدل اليوزر. الفارغ يعيد ما كان (يوزر المدير، أو اسم الموظّف). يُحفظ في الخادم فيظهر في التطبيق والموقع معاً.
Future<void> showIssuerNamesSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const IssuerNamesSheet(),
    );

class IssuerNamesSheet extends StatefulWidget {
  const IssuerNamesSheet({super.key});

  @override
  State<IssuerNamesSheet> createState() => _IssuerNamesSheetState();
}

class _IssuerNamesSheetState extends State<IssuerNamesSheet> {
  IssuerNames? _data;
  String? _error;
  bool _saving = false;
  final _owner = TextEditingController();
  final _emp = <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _owner.dispose();
    for (final c in _emp.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final r = await ReceiptIssuerApi.load();
    if (!mounted) return;
    setState(() {
      _error = r.error;
      _data = r.data;
      if (r.data != null) {
        _owner.text = r.data!.owner ?? '';
        for (final e in r.data!.employees) {
          (_emp[e.id] ??= TextEditingController()).text = e.name ?? '';
        }
      }
    });
  }

  Future<void> _save() async {
    final d = _data;
    if (d == null || _saving) return;
    setState(() => _saving = true);
    final r = await ReceiptIssuerApi.save(
      owner: _owner.text.trim(),
      employees: {for (final e in d.employees) e.id: _emp[e.id]?.text.trim() ?? ''},
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.data != null) {
      showSheetSnack(context, 'حُفظت الأسماء — تظهر في الوصولات القادمة');
      Navigator.of(context).pop();
    } else {
      showSheetSnack(context, r.error ?? 'تعذّر الحفظ', isError: true);
    }
  }

  Widget _field(TextEditingController c, String label, String hint, int max) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textLabel)),
          const SizedBox(height: 6),
          SheetBox(
            child: Semantics(
              label: label,
              child: TextField(
                controller: c,
                enabled: !_saving,
                maxLength: max,
                style: AppType.input(),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: hint,
                  hintStyle: AppType.input(color: AppColors.textPlaceholder),
                ),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = _data;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.signature,
        title: 'اسم «أصدره» على الوصل',
        subtitle: 'يُطبع بالعربيّ بدل اليوزر — لك ولموظّفيك',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: d == null
          ? null
          : SheetFooterBar(label: 'حفظ', icon: LucideIcons.check, busy: _saving, onPressed: _save),
      body: d == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.xl),
              child: _error == null
                  ? const Center(child: CircularProgressIndicator())
                  : Text(_error!, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.error)),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _field(_owner, 'اسمك على الوصل', d.ownerDefault == null ? 'مثل: علي الموسوي' : 'بدل ${d.ownerDefault}', d.max),
              if (d.employees.isNotEmpty) ...[
                const SizedBox(height: Sp.xs),
                Text('موظّفوك', style: AppType.cardTitle(color: AppColors.textHi)),
                const SizedBox(height: Sp.xs),
                Text('الفارغ يُطبع باسمه في «الموظّفين»', style: AppType.micro(color: AppColors.textMid)),
                const SizedBox(height: Sp.sm),
                for (final e in d.employees)
                  _field(_emp[e.id]!, e.active ? e.label : '${e.label} (موقوف)', 'بدل ${e.label}', d.max),
              ],
              Text('الاسم للعرض على الوصل وحده — لا يغيّر الدخول ولا الصلاحيّات.', style: AppType.micro(color: AppColors.textMid)),
            ]),
    );
  }
}
