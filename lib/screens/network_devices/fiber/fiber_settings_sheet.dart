import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/bidi.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/fiber_network.dart';
import '../../../services/fiber/fiber_store.dart';
import '../../../services/fiber/fiber_text.dart';
import '../../../services/fiber/fiber_watch.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'fiber_home_screen.dart';

/// إعدادات شبكة الألياف لأولتٍ واحد: فنّي المنطقة (يصله الموقع والاتّصال من شاشة العطل)، والتنبيهات، ونصّا رسالتي
/// العطل و«رجع النت». يُرجع `true` إن حُفظت.
Future<bool?> showFiberSettingsSheet(BuildContext context, {required int oltId, required String oltName}) => showAppSheet<bool>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.card))),
      builder: (_) => _SettingsSheet(oltId: oltId, oltName: oltName),
    );

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.oltId, required this.oltName});
  final int oltId;
  final String oltName;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final FiberOltSettings _initial = FiberStore.layout.value.settingsOf(widget.oltId);
  late final _techName = TextEditingController(text: _initial.techName ?? '');
  late final _techPhone = TextEditingController(text: _initial.techPhone ?? '');
  late final _msgOutage = TextEditingController(text: _initial.outageMessage);
  late final _msgBack = TextEditingController(text: _initial.backMessage);
  late bool _notifyOutages = _initial.notifyOutages;
  late bool _notifyPower = _initial.notifyPower;
  late int _minOnus = _initial.minOnus;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _techName.dispose();
    _techPhone.dispose();
    _msgOutage.dispose();
    _msgBack.dispose();
    super.dispose();
  }

  /// رقمٌ عراقيّ يُقبل بصيغه الشائعة (07…، 7…، 9647…، +9647…) — يُحفظ كما كُتب بلا فراغات.
  static bool phoneOk(String p) {
    final d = p.replaceAll(RegExp(r'[\s\-]'), '');
    if (d.isEmpty) return true;
    return RegExp(r'^(\+?964|0)?7\d{9}$').hasMatch(d);
  }

  Future<void> _save() async {
    final phone = _techPhone.text.trim();
    if (!phoneOk(phone)) {
      setState(() => _error = 'رقم الفنّي غير صحيح — مثال: 07701234567');
      return;
    }
    String? text(TextEditingController c, String def) {
      final t = c.text.trim();
      return t.isEmpty || t == def ? null : t;
    }

    final s = FiberOltSettings(
      oltId: widget.oltId,
      techName: _techName.text.trim().isEmpty ? null : _techName.text.trim(),
      techPhone: phone.isEmpty ? null : phone.replaceAll(RegExp(r'[\s\-]'), ''),
      notifyOutages: _notifyOutages,
      notifyPower: _notifyPower,
      minOnus: _minOnus.clamp(FiberOltSettings.minOnusFloor, FiberOltSettings.minOnusCeil),
      msgOutage: text(_msgOutage, FiberOltSettings.defaultOutageMessage),
      msgBack: text(_msgBack, FiberOltSettings.defaultBackMessage),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await FiberStore.saveSettings(s);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = r.message ?? 'تعذّر الحفظ');
      return;
    }
    // التنبيهات تغيّرت ⇒ مراقبة الحاسبة بالخلفيّة تتبعها الآن لا بعد عشر دقائق.
    unawaited(FiberWatch.sync());
    Navigator.of(context).pop(true);
  }

  InputDecoration _field(String label, {String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        filled: true,
        fillColor: AppColors.surfaceInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: Sp.lg, bottom: Sp.sm),
        child: Text(t, style: AppType.cardTitleBold(color: AppColors.textHi)),
      );

  Widget _switch({required String title, required String sub, required bool value, required ValueChanged<bool>? onChanged}) =>
      Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          title: Text(title, style: AppType.bodyStrong(color: AppColors.textHi)),
          subtitle: Text(sub, style: AppType.muted(color: AppColors.textMid)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final canEdit = fiberCanEdit();
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.settings2,
        title: 'إعدادات شبكة الألياف',
        subtitle: iso(widget.oltName),
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: canEdit ? 'حفظ' : 'لا صلاحيّة',
        icon: canEdit ? LucideIcons.check : LucideIcons.lock,
        busy: _busy,
        enabled: canEdit,
        onPressed: canEdit ? _save : null,
      ),
      body: AbsorbPointer(
        absorbing: !canEdit,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Text('تعديلها لمن عنده صلاحيّة إدارة الأجهزة.', style: AppType.body(color: AppColors.textMid)),
            ),
          Text('فنّي المنطقة', style: AppType.cardTitleBold(color: AppColors.textHi)),
          const SizedBox(height: Sp.xs),
          Text('يصله موقع العطل بالواتساب ويتّصل بيه من شاشة العطل.', style: AppType.muted(color: AppColors.textMid)),
          const SizedBox(height: Sp.sm),
          TextField(controller: _techName, decoration: _field('اسم الفنّي', hint: 'مثال: أبو علي', prefix: const Icon(LucideIcons.user, size: 18))),
          const SizedBox(height: Sp.sm),
          TextField(
            controller: _techPhone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]'))],
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            decoration: _field('رقم الفنّي', hint: '07701234567', prefix: const Icon(LucideIcons.phone, size: 18)),
          ),
          _title('التنبيهات'),
          _switch(
            title: 'نبّهني بالعطل',
            sub: 'قطع ليف أو صندوق طافي كلّه — يوصل لكلّ أجهزة الحساب.',
            value: _notifyOutages,
            onChanged: (v) => setState(() => _notifyOutages = v),
          ),
          _switch(
            title: 'نبّهني بانطفاء الكهرباء الجماعيّ',
            sub: 'أجهزة بعثت إشارة انطفاء معاً — ما يحتاج فنّياً، فمطفأ أساساً.',
            value: _notifyPower,
            onChanged: (v) => setState(() => _notifyPower = v),
          ),
          const SizedBox(height: Sp.sm),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('أقلّ عدد أجهزة يُعدّ عطلاً', style: AppType.bodyStrong(color: AppColors.textHi)),
                Text('${FiberText.devices(_minOnus)} انقطعت معاً بدقيقتين', style: AppType.muted(color: AppColors.textMid)),
              ]),
            ),
            IconButton.outlined(
              tooltip: 'أقلّ',
              onPressed: _minOnus > FiberOltSettings.minOnusFloor ? () => setState(() => _minOnus--) : null,
              icon: const Icon(LucideIcons.minus, size: 16),
            ),
            SizedBox(
              width: 40,
              child: Text(iso('$_minOnus'), textAlign: TextAlign.center, style: AppType.statValue(color: AppColors.textHi)),
            ),
            IconButton.outlined(
              tooltip: 'أكثر',
              onPressed: _minOnus < FiberOltSettings.minOnusCeil ? () => setState(() => _minOnus++) : null,
              icon: const Icon(LucideIcons.plus, size: 16),
            ),
          ]),
          _title('رسائل المشتركين'),
          TextField(controller: _msgOutage, minLines: 2, maxLines: 5, decoration: _field('رسالة العطل')),
          const SizedBox(height: Sp.sm),
          TextField(controller: _msgBack, minLines: 1, maxLines: 4, decoration: _field('رسالة «رجع النت»')),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _msgOutage.text = FiberOltSettings.defaultOutageMessage;
                _msgBack.text = FiberOltSettings.defaultBackMessage;
              }),
              icon: const Icon(LucideIcons.rotateCcw, size: 15),
              label: const Text('رجّع النصّ الأصليّ'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Sp.sm),
            Text(_error!, style: AppType.body(color: AppColors.error)),
          ],
        ]),
      ),
    );
  }
}
