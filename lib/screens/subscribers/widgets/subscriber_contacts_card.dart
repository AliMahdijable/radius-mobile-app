import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscriber_contacts_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// حال «أرقام تواصل إضافيّة» لمشتركٍ واحد (المالك ١٤ نوفمبر): تُجلب مرّة، وتُضاف/تُعدَّل بورقتها. تملكه شاشة المشترك (كالملاحظة)
/// وتعرضها بطاقة الهويّة تحت الهاتف (المالك ١٤ نوفمبر: «يظهرهن هنا وي كارت»)، ويقرؤه «المزيد» للإضافة والتعديل. «كل الشركات» (مشتركٌ من شركةٍ أخرى) لا يُجلب — يُعدَّل من صفحة الشركة.
class SubscriberContactsController extends ChangeNotifier {
  SubscriberContactsController(this.sub);
  final Subscriber sub;
  SubscriberContacts? contact;

  /// الميزة مفتوحة للحساب (المفتاح بالخادم) — قبل الجلب أو مطفأة ⇒ لا كرت ولا زرّ.
  bool enabled = false;
  bool loaded = false;
  bool failed = false;
  bool _loading = false;
  bool _disposed = false;

  /// جُلبت بنجاح — قبلها لا حفظ (حفظٌ على أرقامٍ لم تُقرأ قد يمحوها).
  bool get ready => loaded && !failed;

  Future<void> load() async {
    if (_loading || sub.username.isEmpty || sub.companyKey != null) return;
    _loading = true;
    final r = await SubscriberContactsApi.get(sub.username);
    _loading = false;
    if (_disposed) return;
    loaded = true;
    failed = !r.ok;
    enabled = r.ok && r.enabled;
    contact = r.contact;
    notifyListeners();
  }

  /// ورقة الأرقام — ما حُفظ يظهر في الكرت مباشرةً.
  Future<void> edit(BuildContext context) async {
    if (!ready || !enabled) return;
    final saved = await showAppSheet<({SubscriberContacts? contact})>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ContactsSheet(sub: sub, initial: contact),
    );
    if (saved == null || _disposed) return;
    contact = saved.contact;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class _ContactsSheet extends StatefulWidget {
  const _ContactsSheet({required this.sub, this.initial});
  final Subscriber sub;
  final SubscriberContacts? initial;

  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends State<_ContactsSheet> {
  late final TextEditingController _wa = TextEditingController(text: widget.initial?.waPhone2 ?? '');
  late final TextEditingController _tg = TextEditingController(text: widget.initial?.tgContact ?? '');
  bool _busy = false;
  String? _errField;
  String? _errText;

  @override
  void dispose() {
    _wa.dispose();
    _tg.dispose();
    super.dispose();
  }

  bool get _changed =>
      _wa.text.trim() != (widget.initial?.waPhone2 ?? '') || _tg.text.trim() != (widget.initial?.tgContact ?? '');

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errField = null;
      _errText = null;
    });
    final r = await SubscriberContactsApi.save(widget.sub.username, wa: _wa.text, tg: _tg.text, phone: widget.sub.phone);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      if (r.field == 'wa_phone2' || r.field == 'tg_contact') {
        setState(() {
          _errField = r.field;
          _errText = r.message;
        });
      } else {
        showSheetSnack(context, r.message ?? 'تعذّر الحفظ', isError: true);
      }
      return;
    }
    showSheetSnack(context, r.contact == null ? 'حُذفت الأرقام' : 'حُفظت الأرقام');
    Navigator.of(context).pop((contact: r.contact));
  }

  InputDecoration _deco(String hint, {required bool error}) => InputDecoration(
        hintText: hint,
        hintTextDirection: TextDirection.ltr,
        hintStyle: AppType.input(color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.surfaceInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: error ? AppColors.error : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.md),
          borderSide: BorderSide(color: error ? AppColors.error : AppColors.brand, width: 1.5),
        ),
      );

  Widget _field(String label, TextEditingController c, String hint, String field, {TextInputType? type}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppType.label(color: AppColors.textHi)),
          const SizedBox(height: 6),
          TextField(
            key: ValueKey('sub-contacts-$field'),
            controller: c,
            keyboardType: type,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: AppType.input(color: AppColors.textHi),
            decoration: _deco(hint, error: _errField == field),
          ),
          if (_errField == field && _errText != null) ...[
            const SizedBox(height: 4),
            Text(_errText!, style: AppType.micro(color: AppColors.error)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final name = widget.sub.fullName.trim().isNotEmpty ? widget.sub.fullName : widget.sub.username;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.userPlus,
        title: 'أرقام تواصل إضافيّة',
        subtitle: name,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('على خادمنا لا الساس. حين لا يصل رقم المشترك: هذا الرقم، ثمّ تلغرامه (بحسابك لمن ربط «حسابي» في تلغرام).',
              style: AppType.muted()),
          const SizedBox(height: Sp.md),
          _field('رقم واتساب ثانٍ', _wa, '07801234567', 'wa_phone2', type: TextInputType.phone),
          const SizedBox(height: Sp.md),
          _field('تلغرام — المعرّف أو الرقم', _tg, '@name أو 07…', 'tg_contact', type: TextInputType.text),
        ],
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        busy: _busy,
        enabled: _changed,
        onPressed: _save,
      ),
    );
  }
}
