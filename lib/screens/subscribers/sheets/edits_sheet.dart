import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscriber_edits_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/merged_company.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/provider_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../services/employee_visibility.dart';

/// «سجلّ التعديلات» للمشترك (المالك ٢٠ نوفمبر، صورةٌ من نظامٍ آخر: «من يوزر يعدلون عليه معلومات… سويها»): كلّ تعديلٍ بما تغيّر
/// «من … إلى …»، ومن عدّله (الموظّف باسمه، والمدير باسمه في السجلات إن وضعه) ومتى — كقسم الموقع في نافذة المشترك
/// (`SubscriberEditsSection.tsx`) والخادم `server/subscriberEdits.js`. يُقرأ حين يُفتح. كلمات المرور «تغيّرت» بلا قيمة، والملاحظة
/// الخاصّة «أُضيفت/عُدّلت/حُذفت» بلا نصّها، وإعداد الجهاز لمن يملك صلاحيّة الأجهزة. التعديلات قبل ٢٠ نوفمبر بأسماء حقولها وحدها.
Future<void> showSubscriberEditsSheet(BuildContext context, Subscriber sub) {
  return showAppSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SubscriberEditsSheet(sub: sub),
  );
}

/// هل يُعرض الزرّ لـ[s]: مشتركٌ برقم، وليس من FTTH القديم، ولا فايبر اكس في «كل الشركات» (جدول التوجيه بالخادم لا يمرّره لها) —
/// كشرط الموقع.
bool subscriberEditsAvailable(Subscriber s) {
  if ((s.idx ?? '').isEmpty) return false;
  final c = MergedMode.companyOf(s.companyKey);
  if (c != null) return c.provider != MergedProvider.ftth && c.provider != MergedProvider.fiberx;
  return !ProviderService.isFtth;
}

/// مسافةٌ لا تنكسر بين التاريخ ووقته (يبقيان سطراً واحداً).
final String _nbsp = String.fromCharCode(0xA0);

final RegExp _dateValue = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2})?)?$');

/// «2026-12-01 00:00:00» ⇒ «2026/12/01 00:00» (التواريخ أرقامٌ بالشرطة المائلة — ذوق المالك)؛ غيرها كما هو.
String editValue(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return '';
  final m = _dateValue.firstMatch(s);
  if (m == null) return s;
  final day = '${m[1]}/${m[2]}/${m[3]}';
  return m[4] == null ? day : '$day$_nbsp${m[4]}:${m[5]}';
}

/// وقت التعديل بتوقيت بغداد (UTC+3 بلا توقيتٍ صيفيّ): «2026/11/20 16:35».
String editTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 3));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}$_nbsp${two(d.hour)}:${two(d.minute)}';
}

class SubscriberEditsSheet extends StatefulWidget {
  const SubscriberEditsSheet({super.key, required this.sub});
  final Subscriber sub;

  @override
  State<SubscriberEditsSheet> createState() => _SubscriberEditsSheetState();
}

class _SubscriberEditsSheetState extends State<SubscriberEditsSheet> {
  bool _loading = true;
  String? _error;
  List<SubscriberEdit> _rows = const [];

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
    final s = widget.sub;
    // «كل الشركات»: من شركة الصفّ (الخادم يوجّه القراءة)؛ الوضع العاديّ كما هو.
    final r = await MergedOps.run(s, () => SubscriberEditsApi.list(s.idx ?? '', username: s.username));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _rows = r.rows;
      } else {
        _error = (r.message ?? '').trim().isEmpty ? 'تعذّرت قراءة سجلّ التعديلات' : r.message!.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.sub;
    final who = Sees.usernames
        ? (s.fullName.trim().isNotEmpty ? s.fullName.trim() : iso(s.username))
        : Sees.nameOf(s.fullName, s.username);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.fileDiff,
        title: 'سجلّ التعديلات',
        subtitle: MergedOps.withCompany(who, s.companyKey),
        // الاسم الطويل واسم الشركة في «كل الشركات» يلتفّان سطراً ثانياً لا يُقصّان
        subtitleMaxLines: 2,
        onClose: () => Navigator.of(context).pop(),
      ),
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
      );
    }
    if (_error != null) {
      return Padding(
        key: const ValueKey('sub-edits-error'),
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 32, color: AppColors.error),
            const SizedBox(height: Sp.sm),
            Text(_error!, style: AppType.subtitle(color: AppColors.error), textAlign: TextAlign.center),
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Padding(
        key: const ValueKey('sub-edits-empty'),
        padding: const EdgeInsets.symmetric(vertical: Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.inbox, size: 36, color: AppColors.textLow),
            const SizedBox(height: Sp.sm),
            Text(
              'لا تعديلات مسجّلة لهذا المشترك',
              style: AppType.subtitle(color: AppColors.textMid),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          _EditCard(key: ValueKey('sub-edit-${_rows[i].id}'), r: _rows[i]),
        ],
      ],
    );
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({super.key, required this.r});
  final SubscriberEdit r;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final muted = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.45);
    final strong = AppType.bodyStrong(color: AppColors.textHi).copyWith(fontSize: 13, height: 1.45);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm + 2, Sp.md, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوان ووقته: يلتفّ الوقت لسطرٍ تحته حين يضيق العرض (لا قصّ ولا سحق — ٣٢٠ بخطّ ١٫٢).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Sp.sm,
            runSpacing: Sp.xxs,
            children: [
              Text(r.title, style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
              if (r.atMs != null)
                Text(
                  iso(editTime(r.atMs!)),
                  style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 11.5),
                ),
            ],
          ),
          const SizedBox(height: Sp.xs),
          // من عدّله — الاسم الطويل يلتفّ لا يُقصّ.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  r.byEmployee ? LucideIcons.userRound : LucideIcons.userCog,
                  size: 14,
                  color: AppColors.textLow,
                ),
              ),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: r.byEmployee ? 'الموظّف: ' : 'المدير: ', style: muted),
                    TextSpan(text: iso(r.byName), style: strong.copyWith(fontSize: 12.5)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.x6),
          ..._details(muted, strong),
        ],
      ),
    );
  }

  List<Widget> _details(TextStyle muted, TextStyle strong) {
    if (r.diff.isNotEmpty) {
      return [
        for (var i = 0; i < r.diff.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : Sp.xxs),
            child: Text.rich(TextSpan(children: entrySpans(r.diff[i], muted, strong))),
          ),
      ];
    }
    if (r.fields.isNotEmpty) {
      return [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'عُدّل: ', style: muted),
          TextSpan(text: r.fields.join('، '), style: strong),
          TextSpan(text: ' — سجلٌّ قديم بلا القيم', style: muted.copyWith(fontSize: 11.5)),
        ])),
      ];
    }
    if (r.note != null) return [Text(r.note!, style: strong)];
    return const [];
  }
}

/// سطر الحقل: «الهاتف: من X إلى Y» — القيم معزولة الاتّجاه (يوزرٌ وعنوانٌ وتاريخٌ لاتينيّ وسط العربيّ لا ينقلب).
List<InlineSpan> entrySpans(EditEntry e, TextStyle muted, TextStyle strong) {
  final out = <InlineSpan>[TextSpan(text: '${e.label}: ', style: muted)];
  if (e.secret) return out..add(TextSpan(text: 'تغيّرت', style: strong));
  if (e.hidden) return out..add(TextSpan(text: 'تغيّر — يظهر لمن عنده صلاحيّة الأجهزة', style: muted));
  if (e.text != null) return out..add(TextSpan(text: e.text, style: strong));
  final from = editValue(e.from);
  final to = editValue(e.to);
  if (from.isNotEmpty) {
    out
      ..add(TextSpan(text: 'من ', style: muted))
      ..add(TextSpan(text: iso(from), style: strong))
      ..add(TextSpan(text: ' إلى ', style: muted));
  } else {
    out.add(TextSpan(text: 'صار ', style: muted));
  }
  out.add(TextSpan(text: to.isNotEmpty ? iso(to) : 'فارغ', style: strong));
  if (e.atExpiry) out.add(TextSpan(text: ' (عند انتهاء الاشتراك)', style: muted));
  return out;
}
