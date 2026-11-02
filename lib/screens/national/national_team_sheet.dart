import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_device_api.dart';
import '../../api/national_more_api.dart';
import '../../api/national_sheet_api.dart';
import '../../api/national_team_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'national_edit_widgets.dart';
import 'national_task_sheet.dart' show NationalPortalLockBox;
import 'national_ticket_write.dart' show NationalUnconfirmedBox;
import 'national_widgets.dart';

/// «فريقي» — إضافة عضوٍ أو تعديله (المشروع الوطنيّ، ٢ نوفمبر — نسخة الموقع WataniTeamSheet). الإضافة: اسم المستخدم (يُفحص هل هو
/// مأخوذ)، الاسمان، الهاتف، كلمة السرّ بشروط البوّابة، الوظيفة (بوصفها وهل تصرف مالاً)، الزونات (إلّا لوظيفةٍ ترى كلّ الزونات)، وحدّ
/// المحفظة («غير محدود» أو مبلغٌ أقصى). التعديل: ما يُكتب وحده يتغيّر (الفارغ يبقى)، والزونات بمفتاحٍ صريح. طلبٌ واحد بلا إعادة.
Future<bool?> showNationalTeamSheet(BuildContext context, {NationalTeamMember? member}) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    builder: (_) => NationalTeamSheet(member: member),
  );
}

class NationalTeamSheet extends StatefulWidget {
  const NationalTeamSheet({super.key, this.member});
  final NationalTeamMember? member;

  @override
  State<NationalTeamSheet> createState() => _NationalTeamSheetState();
}

class _NationalTeamSheetState extends State<NationalTeamSheet> {
  bool get _add => widget.member == null;

  TeamMeta? _meta;
  String? _metaErr;
  NationalLock? _lock;
  Timer? _poll;
  int _polls = 0;

  final _user = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  final _amount = TextEditingController();
  String? _roleId;
  String? _initialRole;
  final Set<String> _zones = {};
  bool _editZones = false;
  bool? _limited;

  // فحص الاسم
  Timer? _userTimer;
  String _checked = '';
  bool? _taken;
  String? _userErr;
  bool _checking = false;

  bool _busy = false;
  String? _unconfirmed;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _userTimer?.cancel();
    for (final c in [_user, _first, _last, _phone, _pw, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeta() async {
    _poll?.cancel();
    final r = await NationalTeamApi.meta();
    if (!mounted) return;
    if (r.ok && r.data == null) {
      if (_polls++ < 12) _poll = Timer(const Duration(milliseconds: 2500), _loadMeta);
      return;
    }
    setState(() {
      _lock = r.lock;
      _metaErr = r.locked ? null : r.error;
      if (r.ok) {
        _meta = r.data;
        // التعديل: الوظيفة الحاليّة بمطابقة رمزها
        final code = widget.member?.roleCode;
        if (!_add && code != null && code.isNotEmpty) {
          for (final x in r.data!.roles) {
            if (x.code == code) _initialRole = x.id;
          }
          _roleId ??= _initialRole;
        }
      }
    });
  }

  TeamRole? get _role {
    for (final x in _meta?.roles ?? const <TeamRole>[]) {
      if (x.id == _roleId) return x;
    }
    return null;
  }

  void _onUser(String v) {
    _userTimer?.cancel();
    final u = v.trim();
    setState(() {
      _taken = null;
      _userErr = null;
      _checking = teamUserOk.hasMatch(u);
    });
    if (!teamUserOk.hasMatch(u)) return;
    _userTimer = Timer(const Duration(milliseconds: 700), () => _check(u, 0));
  }

  Future<void> _check(String u, int attempt) async {
    final r = await NationalTeamApi.usernameTaken(u);
    if (!mounted || _user.text.trim() != u) return;
    if (r.retry && attempt < 4) {
      _userTimer = Timer(const Duration(milliseconds: 1400), () => _check(u, attempt + 1));
      return;
    }
    setState(() {
      _checking = false;
      _checked = u;
      _taken = r.taken;
      _userErr = r.error;
    });
  }

  String get _phoneN => teamDigits(_phone.text.trim());
  int? get _amountN => int.tryParse(teamDigits(_amount.text.trim()).replaceAll(',', ''));

  Map<String, dynamic> get _editBody {
    final b = <String, dynamic>{};
    if (_first.text.trim().isNotEmpty) b['first_name'] = _first.text.trim();
    if (_last.text.trim().isNotEmpty) b['last_name'] = _last.text.trim();
    if (_phoneN.isNotEmpty) b['phone'] = _phoneN;
    if (_roleId != null && _roleId != _initialRole) b['role_id'] = _roleId;
    final role = _role;
    if (_editZones && role != null && !role.allZones) b['zone_ids'] = _zones.toList();
    return b;
  }

  bool get _ready {
    final m = _meta;
    if (m == null || _unconfirmed != null) return false;
    final phoneOk = _phoneN.isEmpty || teamPhoneOk.hasMatch(_phoneN);
    final role = _role;
    final zonesNeeded = role != null && !role.allZones && (_add || _editZones);
    final zonesOk = !zonesNeeded || _zones.isNotEmpty;
    if (!phoneOk || !zonesOk) return false;
    if (_add) {
      final u = _user.text.trim();
      final amountOk = _limited == false || (_limited == true && _amountN != null && _amountN! >= 0 && _amountN! <= teamWalletMax);
      return teamUserOk.hasMatch(u) &&
          !(_checked == u && _taken == true) &&
          !_checking &&
          m.policy.ok(_pw.text, u) &&
          role != null &&
          amountOk;
    }
    return _editBody.isNotEmpty;
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    final role = _role;
    setState(() => _busy = true);
    final NationalEditResult r;
    if (_add) {
      r = await NationalTeamApi.add(
        username: _user.text.trim(),
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        phone: _phoneN,
        password: _pw.text,
        roleId: _roleId!,
        zoneIds: role != null && role.allZones ? const [] : _zones.toList(),
        limited: _limited == true,
        amount: _limited == true ? _amountN : null,
      );
    } else {
      r = await NationalTeamApi.edit(widget.member!.id!, _editBody);
    }
    if (!mounted) return;
    _pw.clear();
    setState(() => _busy = false);
    if (r.ok) {
      final applied = r.outcome == 'applied';
      showSheetSnack(context, applied ? (_add ? 'أُضيف «${_user.text.trim()}» إلى فريقك' : 'عُدّل العضو') : (r.message ?? 'قبلت البوّابة الطلب — حدّث «فريقي» لترى أثره'),
          isError: r.outcome == 'not_applied', duration: Duration(seconds: applied ? 3 : 8));
      Navigator.of(context).pop(true);
      return;
    }
    if (r.unconfirmed) {
      setState(() => _unconfirmed = r.message ?? 'لم يتأكّد — حدّث «فريقي» وتحقّق قبل الإعادة');
      return;
    }
    if (r.code == 'META_MISSING') _loadMeta();
    showSheetSnack(context, r.text, isError: true, duration: const Duration(seconds: 10), autoExplain: false);
  }

  Future<void> _close() async {
    if (_busy) return;
    Navigator.of(context).pop(_unconfirmed != null);
  }

  Widget _label(String t, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text(t, style: AppType.label(color: AppColors.textLabel)),
          if (hint != null) ...[
            const SizedBox(width: Sp.sm),
            Expanded(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: AppType.micro(color: AppColors.textHint))),
          ],
        ]),
      );

  Widget _arabicField(TextEditingController c, String hint) => SheetBox(
        child: TextField(
          controller: c,
          enabled: !_busy && _unconfirmed == null,
          maxLength: 40,
          onChanged: (_) => setState(() {}),
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
      );

  Widget _chip(String label, bool on, VoidCallback? onTap, {IconData? icon}) => ChoiceChip(
        avatar: icon == null ? null : Icon(icon, size: 14, color: on ? AppColors.brand : AppColors.warning),
        label: Text(label),
        selected: on,
        onSelected: onTap == null ? null : (_) => onTap(),
        labelStyle: AppType.label(color: on ? AppColors.brand : AppColors.textHi),
        selectedColor: AppColors.brandSoftBg,
        backgroundColor: AppColors.surface,
        side: BorderSide(color: on ? AppColors.brandSoftBorder : AppColors.border),
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
      );

  Widget _form(TeamMeta m) {
    final frozen = _busy || _unconfirmed != null;
    final u = _user.text.trim();
    final role = _role;
    final phoneBad = _phoneN.isNotEmpty && !teamPhoneOk.hasMatch(_phoneN);
    final Widget? userStatus = !_add || u.isEmpty
        ? null
        : !teamUserOk.hasMatch(u)
            ? Text('حروفٌ إنكليزيّة وأرقام و . _ - @ (٣ إلى ٤٠)', style: AppType.micro(color: AppColors.error))
            : (_checking || _checked != u)
                ? Text('يُفحص الاسم…', style: AppType.micro(color: AppColors.textMid))
                : _taken == true
                    ? Text('هذا الاسم مستخدمٌ في البوّابة — اختر غيره', style: AppType.micro(color: AppColors.error))
                    : _taken == false
                        ? Row(children: [
                            Icon(LucideIcons.circleCheck, size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text('الاسم متاح', style: AppType.micro(color: AppColors.success)),
                          ])
                        : (_userErr == null ? null : Text(_userErr!, style: AppType.micro(color: AppColors.error)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_add) ...[
        _label('اسم المستخدم *', hint: 'يدخل به العضو إلى البوّابة'),
        NationalLatinField(controller: _user, hint: 'admin-54', maxLength: 40, enabled: !frozen, semanticLabel: 'اسم المستخدم', helper: userStatus, onChanged: _onUser),
        const SizedBox(height: Sp.lg),
      ],
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('الاسم الأوّل'), _arabicField(_first, _add ? '' : 'بلا تغيير')])),
        const SizedBox(width: Sp.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_label('اسم العائلة'), _arabicField(_last, _add ? '' : 'بلا تغيير')])),
      ]),
      const SizedBox(height: Sp.lg),
      _label('رقم الهاتف', hint: _add ? null : 'الفارغ يبقى كما هو'),
      NationalLatinField(
        controller: _phone,
        hint: '07XXXXXXXXX',
        maxLength: 16,
        enabled: !frozen,
        semanticLabel: 'رقم الهاتف',
        error: phoneBad ? 'رقمٌ عراقيّ: 07XXXXXXXXX' : null,
        onChanged: (_) => setState(() {}),
      ),
      if (_add) ...[
        const SizedBox(height: Sp.lg),
        _label('كلمة السرّ *', hint: m.policyAssumed ? 'شروطٌ تقريبيّة — البوّابة تتحقّق عند الحفظ' : null),
        NationalLatinField(controller: _pw, maxLength: 64, secret: true, enabled: !frozen, semanticLabel: 'كلمة السرّ', onChanged: (_) => setState(() {})),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (final c in m.policy.checks(_pw.text, u))
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(c.ok ? LucideIcons.circleCheck : LucideIcons.circle, size: 13, color: c.ok ? AppColors.success : AppColors.textHint),
              const SizedBox(width: 3),
              Text(c.label, style: AppType.micro(color: c.ok ? AppColors.success : AppColors.textMid)),
            ]),
        ]),
      ],
      const SizedBox(height: Sp.lg),
      _label(_add ? 'الوظيفة *' : 'الوظيفة'),
      if (m.roles.isEmpty)
        Text('الوظائف غير متاحة الآن — أعد فتح النافذة', style: AppType.muted())
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in m.roles) _chip(x.label, _roleId == x.id, frozen ? null : () => setState(() => _roleId = x.id), icon: x.monetary ? LucideIcons.banknote : null),
        ]),
      if (role?.description != null) ...[
        const SizedBox(height: 6),
        Text(role!.description!, style: AppType.micro(color: AppColors.textMid)),
      ],
      if (role != null && role.monetary) ...[
        const SizedBox(height: 4),
        Text('هذه الوظيفة تصرف مالاً من المحفظة', style: AppType.micro(color: AppColors.warningOnSoft)),
      ],
      const SizedBox(height: Sp.lg),
      if (role != null && role.allZones)
        Text('هذه الوظيفة ترى كلّ زونات حسابك', style: AppType.micro(color: AppColors.textMid))
      else ...[
        if (!_add)
          SheetSwitchRow(
            icon: LucideIcons.mapPin,
            label: 'تعديل الزونات',
            footnote: 'اختر زوناته من جديد — بلا تشغيلٍ تبقى كما هي',
            value: _editZones,
            enabled: !frozen,
            onChanged: frozen ? null : (v) => setState(() => _editZones = v),
          ),
        if (_add || _editZones) ...[
          if (!_add) const SizedBox(height: Sp.sm),
          _label(_add ? 'الزونات *' : 'الزونات', hint: m.zones.length > 1 ? '${_zones.length} من ${m.zones.length}' : null),
          if (m.zones.isEmpty)
            Text('لا زونات — أعد فتح النافذة', style: AppType.muted())
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (m.zones.length > 2)
                _chip(_zones.length == m.zones.length ? 'إلغاء الكلّ' : 'الكلّ', false, frozen ? null : () => setState(() {
                      if (_zones.length == m.zones.length) {
                        _zones.clear();
                      } else {
                        _zones
                          ..clear()
                          ..addAll(m.zones.map((z) => z.id));
                      }
                    })),
              for (final z in m.zones)
                _chip(z.name, _zones.contains(z.id), frozen ? null : () => setState(() => _zones.contains(z.id) ? _zones.remove(z.id) : _zones.add(z.id))),
            ]),
        ],
      ],
      if (_add) ...[
        const SizedBox(height: Sp.lg),
        _label('حدّ المحفظة *', hint: '«غير محدود» بلا سقف، أو مبلغٌ أقصى يصرفه العضو'),
        Wrap(spacing: 6, children: [
          _chip('غير محدود', _limited == false, frozen ? null : () => setState(() => _limited = false)),
          _chip('بحدّ', _limited == true, frozen ? null : () => setState(() => _limited = true)),
        ]),
        if (_limited == true) ...[
          const SizedBox(height: Sp.sm),
          NationalLatinField(
            controller: _amount,
            hint: '200000',
            maxLength: 12,
            enabled: !frozen,
            semanticLabel: 'حدّ المحفظة بالدينار',
            error: _amount.text.isNotEmpty && (_amountN == null || _amountN! > teamWalletMax) ? 'مبلغٌ صحيح بين ٠ و١٠٠٬٠٠٠٬٠٠٠' : null,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
      if (_unconfirmed != null) ...[
        const SizedBox(height: Sp.lg),
        NationalUnconfirmedBox(text: _unconfirmed!),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final m = _meta;
    final who = widget.member == null ? '' : (widget.member!.name.isNotEmpty ? widget.member!.name : (widget.member!.login ?? 'العضو'));
    final Widget body;
    if (_lock != null) {
      body = NationalPortalLockBox(title: _lock!.title, text: _lock!.message);
    } else if (m == null && _metaErr != null) {
      body = NationalStateBox.error(text: _metaErr!, onRetry: () {
        setState(() => _metaErr = null);
        _polls = 0;
        _loadMeta();
      });
    } else if (m == null) {
      body = const NationalStateBox.pending(text: 'جارٍ قراءة الوظائف والزونات من البوّابة…');
    } else {
      body = _form(m);
    }
    return PopScope(
      canPop: !_busy,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: _add ? LucideIcons.userPlus : LucideIcons.userPen,
          title: _add ? 'إضافة عضو للفريق' : 'تعديل $who',
          subtitle: _add ? 'يُنشأ في بوّابة المشروع الوطني باسم حسابك' : 'اكتب ما تريد تغييره فقط — الفارغ يبقى كما هو',
          onClose: _close,
        ),
        body: body,
        footer: m == null
            ? null
            : SheetFooterBar(
                label: _unconfirmed != null ? 'إغلاق والتحقّق لاحقاً' : (_add ? 'إضافة العضو' : 'حفظ التعديل'),
                icon: _unconfirmed != null ? LucideIcons.x : (_add ? LucideIcons.userPlus : LucideIcons.save),
                busy: _busy,
                enabled: _unconfirmed != null || _ready,
                onPressed: _unconfirmed != null ? _close : _submit,
              ),
      ),
    );
  }
}
