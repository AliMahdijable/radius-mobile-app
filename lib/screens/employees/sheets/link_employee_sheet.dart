import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/account_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// ٨ نوفمبر — «موظّفٌ بأكثر من صفحة» (المالك: «نفس الموظف نسنده لاكثر من صفحه… تمام ابدي بيها»): موظّفو صفحاتك الأخرى في
/// «شركاتي» — اختر واحداً فيُضاف لهذه الصفحة [pageId] بصلاحيّاته الحاليّة (تغيّرها بعدها من «الموظفون»). يدخل باسمه نفسه ويتنقّل
/// بين صفحاته من «صفحاتي». ⇒ true إن أُضيف أحد.
Future<bool> showLinkEmployeeSheet(BuildContext context, {required String pageId}) async {
  HapticFeedback.selectionClick();
  final r = await showAppSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => LinkEmployeeSheet(pageId: pageId),
  );
  return r == true;
}

class LinkEmployeeSheet extends StatefulWidget {
  const LinkEmployeeSheet({super.key, required this.pageId});

  /// الصفحة المفتوحة (معرّف المدير كما يحفظه التطبيق) — الهدف.
  final String pageId;

  /// منافذ الاختبار: القراءة والربط (Firebase لا يعمل في `flutter test`).
  @visibleForTesting
  static Future<AccountEmployees> Function() load = AccountApi.employees;
  @visibleForTesting
  static Future<({bool ok, String? message, String? newPassword, String? loginUsername})> Function(
      {required int employeeId, required String toPageId}) link = AccountApi.linkEmployee;

  @override
  State<LinkEmployeeSheet> createState() => _LinkEmployeeSheetState();
}

class _LinkEmployeeSheetState extends State<LinkEmployeeSheet> {
  AccountEmployees? _data;
  bool _loading = true;
  String? _error;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await LinkEmployeeSheet.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on AccountApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message.startsWith('account.') ? 'تعذّرت قراءة موظّفي صفحاتك الآن — حاول بعد قليل' : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّرت قراءة موظّفي صفحاتك الآن — حاول بعد قليل';
      });
    }
  }

  Future<void> _add(AccountEmployee e, String pageName) async {
    if (_busy != null) return;
    final name = (e.fullName?.trim().isNotEmpty ?? false) ? e.fullName!.trim() : e.loginUsername;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('إضافة $name لهذه الصفحة؟'),
        content: Text(
          'يعمل في هذه الصفحة أيضاً، ويدخل باسم الدخول نفسه (${e.loginUsername}) ويتنقّل بين صفحاته من «صفحاتي».'
          ' صلاحيّاته هنا تبدأ مثل صلاحيّاته في «$pageName» الآن — وتقدر تغيّرها من «الموظفون».'
          '${e.pages.length < 2 ? '\n\nأوّل إضافةٍ لصفحةٍ أخرى تغيّر كلمة مروره (للأمان) — نعطيك الجديدة بعد الإضافة لتسلّمها له.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('إضافة')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = e.id;
      _error = null;
    });
    final r = await LinkEmployeeSheet.link(employeeId: e.id, toPageId: widget.pageId);
    if (!mounted) return;
    if (r.ok) {
      HapticFeedback.lightImpact();
      final pw = r.newPassword;
      if (pw != null) {
        setState(() => _busy = null); // لا مؤشّر دوّارٌ خلف النافذة
        await _showNewPassword(name: name, login: r.loginUsername ?? e.loginUsername, password: pw);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = null;
      _error = r.message ?? 'تعذّرت الإضافة — حاول بعد قليل';
    });
  }

  /// كلمة مرور الشخص الجديدة (أوّل إضافةٍ لصفحةٍ أخرى) — مرّةً واحدة، بزرّ نسخ؛ تُعرض لاحقاً من «عرض كلمة المرور» بصفحته الأصليّة.
  Future<void> _showNewPassword({required String name, required String login, required String password}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var copied = false;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            key: const ValueKey('link-employee-new-password'),
            title: Text('أُضيف $name — كلمة مروره الجديدة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'أوّل إضافةٍ لصفحةٍ أخرى تغيّر كلمة مروره للأمان (من كان يعرف القديمة لا يدخل صفحاتك). أعطه هذه — يدخل باسمه ($login)'
                  ' ثمّ يتنقّل من «صفحاتي». تجدها لاحقاً في «عرض كلمة المرور» بصفحته الأصليّة.',
                  style: AppType.body(color: AppColors.textMid),
                ),
                const SizedBox(height: Sp.md),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(R.md)),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          password,
                          key: const ValueKey('link-employee-password-text'),
                          textDirection: TextDirection.ltr,
                          style: AppType.listName(color: AppColors.textHi),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: password));
                          setD(() => copied = true);
                        },
                        icon: Icon(copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                        label: Text(copied ? 'نُسخت' : 'نسخ'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('تمّ')),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: Icons.group_add_outlined,
        title: 'موظف من صفحة أخرى',
        subtitle: 'نفس الموظف يعمل بأكثر من صفحة — لكلّ صفحةٍ صلاحيّاتها',
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _body(),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return const [
        Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator())),
      ];
    }
    final data = _data;
    final out = <Widget>[];
    if (_error != null) {
      out.addAll([
        Container(
          key: const ValueKey('link-employee-error'),
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(color: AppColors.dangerSoftBg, borderRadius: BorderRadius.circular(R.md)),
          child: Text(_error!, style: AppType.body(color: AppColors.error)),
        ),
        const SizedBox(height: Sp.md),
      ]);
      if (data == null) {
        out.add(Center(child: TextButton(onPressed: _load, child: const Text('إعادة المحاولة'))));
        return out;
      }
    }
    if (data == null) return out;
    final addable = data.addableTo(widget.pageId);
    if (addable.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.lg),
        child: Text(
          data.pages.length < 2
              ? 'هذه الصفحة وحدها في «شركاتي» — أضف صفحةً أخرى أوّلاً'
              : 'لا موظّفين في صفحاتك الأخرى يمكن إضافتهم هنا',
          textAlign: TextAlign.center,
          style: AppType.body(color: AppColors.textMid),
        ),
      ));
      return out;
    }
    // مجمَّعون بصفحاتهم، بترتيب «شركاتي»
    for (final page in data.pages) {
      final group = addable.where((e) => e.pageId == page.id).toList();
      if (group.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsetsDirectional.only(start: Sp.xs, top: Sp.sm, bottom: Sp.xs),
        child: Text(page.name, style: AppType.label(color: AppColors.textMid)),
      ));
      for (final e in group) {
        final name = (e.fullName?.trim().isNotEmpty ?? false) ? e.fullName!.trim() : e.loginUsername;
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: Material(
            key: ValueKey('link-employee-${e.id}'),
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy != null ? null : () => _add(e, page.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: AppType.listName(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: Sp.xxs),
                          Text(e.loginUsername,
                              style: AppType.body(color: AppColors.textMid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr),
                        ],
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    if (_busy == e.id)
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.add_circle_outline_rounded, color: AppColors.brand, size: 22),
                  ],
                ),
              ),
            ),
          ),
        ));
      }
    }
    return out;
  }
}
