import 'package:easy_localization/easy_localization.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../models/subscriber.dart';
import '../../../services/merged_mode.dart';
import '../../../services/manual_wa_prefs.dart';
import '../../../services/manual_wa_sender.dart';
import '../../../services/receipt_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/package_picker_field.dart';
import '_print_receipt_checkbox.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/print_feedback.dart';

/// Extend-subscription sheet — direct port of v1's _extendSubscription.
///   1. Fetch /api/v2/subscribers/:idx/extension-options. Spinner while
///      the round-trip is in flight.
///   2. Show current profile + manager balance + reward-points balance.
///   3. Dropdown of packages the subscriber can extend into; selecting
///      one fills in price + required points.
///   4. Method picker: balance (charges manager wallet) or points
///      (deducts reward points).
///   5. Submit → /api/v2/subscribers/:idx/extend with {profile_id,
///      method}.
Future<bool?> showExtendSheet(BuildContext context, Subscriber sub) {
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExtendSheet(sub: sub),
  );
}

class _ExtendSheet extends StatefulWidget {
  const _ExtendSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_ExtendSheet> createState() => _ExtendSheetState();
}

enum _Method { balance, points }

class _ExtendSheetState extends State<_ExtendSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  Map<String, dynamic>? _selectedPkg;
  _Method _method = _Method.balance;
  bool _printReceiptChecked = false;
  // RECENT_DUPLICATE (409) من خادم البرو: يُؤكَّد ويُعاد مع confirmRepeat=true.
  bool _confirmRepeat = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAutoPrint();
  }

  /// «الطباعة التلقائيّة» في مصمّم وصل الموقع ⇒ الخانة معلَّمة من البداية (الموقع يطبع بلا سؤال).
  Future<void> _loadAutoPrint() async {
    final on = await ReceiptService.autoPrintFor(widget.sub.companyKey);
    if (on && mounted && !_printTouched) setState(() => _printReceiptChecked = true);
  }

  /// المستخدم غيّر الخانة بنفسه قبل وصول الإعداد — قراره يبقى.
  bool _printTouched = false;

  Future<void> _load() async {
    final idx = widget.sub.idx;
    if (idx == null) {
      setState(() {
        _loading = false;
        _loadError = 'sheets.extend_no_idx'.tr();
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final data = await MergedOps.run(widget.sub, () => SubscribersApi.fetchExtensionOptions(idx));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
      if (data == null) {
        _loadError = 'sheets.extend_load_failed'.tr();
      } else {
        final list = (data['packages'] as List?) ?? const [];
        if (list.isNotEmpty) {
          _selectedPkg = (list.first as Map).cast<String, dynamic>();
        }
        // ايرث لنك: التمديد بالنقاط فقط (لا رصيد) — افرض الطريقة مسبقاً.
        if (data['provider']?.toString() == 'earthlink') {
          _method = _Method.points;
          // الفعّال لا تتغيّر باقته (الخادم يرفض) — الاختيار يُثبَّت على الحاليّة.
          if (_elPackageLocked) {
            final cur = data['current_profile_id']?.toString();
            for (final p in list) {
              if (p is Map && p['id']?.toString() == cur) {
                _selectedPkg = p.cast<String, dynamic>();
                break;
              }
            }
          }
        }
      }
    });
  }

  num _read(Map<String, dynamic>? m, String key) {
    final v = m?[key];
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }

  num get _managerBalance => _read(_data, 'manager_balance');
  num get _pointsBalance => _read(_data, 'reward_points_balance');
  String get _currentProfileName =>
      _data?['current_profile_name']?.toString() ?? '';

  /// ايرث لنك: التمديد بالنقاط حصراً (user/extend ٢٤ ساعة لنفس الباقة) — لا رصيد
  /// مدير ولا اختيار طريقة دفع. يُكتشَف من provider في ردّ extension-options.
  bool get _isEarthlink => _data?['provider']?.toString() == 'earthlink';

  num get _selectedPrice => _read(_selectedPkg, 'price');
  num get _selectedPoints => _read(_selectedPkg, 'reward_points_required');
  String? get _selectedDuration => _selectedPkg?['duration']?.toString();

  bool get _canSubmit {
    if (_loading || _submitting || _data == null || _selectedPkg == null) {
      return false;
    }
    if (_method == _Method.points) {
      return _pointsBalance >= _selectedPoints && _selectedPoints > 0;
    }
    return _selectedPrice > 0 && _managerBalance >= _selectedPrice;
  }

  String? get _disabledReason {
    if (_selectedPkg == null) return null;
    if (_method == _Method.points) {
      if (_selectedPoints <= 0) return 'sheets.no_points_support'.tr();
      if (_pointsBalance < _selectedPoints) {
        return 'sheets.insufficient_points'.tr();
      }
    } else {
      if (_selectedPrice <= 0) return 'sheets.no_price'.tr();
      if (_managerBalance < _selectedPrice) {
        return 'sheets.insufficient_balance'.tr();
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final idx = widget.sub.idx;
    final pkg = _selectedPkg;
    if (idx == null || pkg == null) return;
    final profileId = pkg['id']?.toString() ?? '';
    if (profileId.isEmpty) return;
    setState(() => _submitting = true);
    // 2026-08-26 (manual WA phase 2): وضع يدوي → backend يعيد wa_preview
    // بلا إرسال، ونفتح modal بعد النجاح.
    final manualMode = ManualWaPrefs.enabled.value;
    final result = await MergedOps.run(widget.sub, () => SubscribersApi.extend(
      idx: idx,
      profileId: profileId,
      method: _method == _Method.points ? 'points' : 'balance',
      skipAutoWa: manualMode,
      confirmRepeat: _confirmRepeat,
    ));
    if (!mounted) return;
    setState(() => _submitting = false);
    // حارس التكرار (كالتجديد): 409 RECENT_DUPLICATE من خادم البرو — أكّد
    // الإعادة ثمّ أعِد الإرسال بـconfirmRepeat بدل انتظار المهلة (٩٠ث). خادم
    // SAS4 لا يرسل هذا الرمز، فمسار التمديد العاديّ لا يُمَسّ.
    if (!result.ok && result.code == 'RECENT_DUPLICATE' && !_confirmRepeat) {
      final again = await showConfirmSheet(
        context,
        title: 'تمديد مكرّر',
        message: result.message ??
            'مدّدت هذا المشترك قبل لحظات — أكّد الإعادة إن أردت تمديداً آخر',
        confirmLabel: 'أكّد التمديد',
      );
      if (again == true) {
        _confirmRepeat = true;
        return _submit(); // إعادة مع confirmRepeat=true
      }
      return;
    }
    _confirmRepeat = false;
    if (!result.ok) {
      showSheetSnack(context, result.message ?? 'common.error'.tr(),
          isError: true);
      return;
    }
    SubscriberEvents.notifyChange();
    showSheetSnack(context, 'sheets.extend_ok'.tr(), isError: false);
    // 2026-07-13: طباعة تلقائية بعد النجاح لو الـcheckbox مُفعَّل.
    if (_printReceiptChecked) {
      final printed = await ReceiptService.printExtension(
        sub: widget.sub,
        price: _method == _Method.points ? 0 : _selectedPrice,
        packageName: pkg['name']?.toString(),
      );
      if (mounted) showPrintResult(context, printed);
    }
    if (!mounted) return;
    // 2026-08-26: preview WA بعد نجاح التمديد.
    if (manualMode) {
      if (result.waPreview != null) {
        await handleWaPreviewAfterOp(
          context: context,
          preview: result.waPreview!,
          opTitle: 'تأكيد التمديد',
          sas4Idx: widget.sub.idx,
        );
        if (!mounted) return;
      } else {
        final reason = result.wa?.reason;
        if (reason == 'no_phone') {
          showSheetSnack(context, 'لم يُبنَ preview: لا رقم هاتف للمشترك',
              isError: true);
        }
        // تمديد يستعمل literalMessage — بلا قالب فما نحصل no_template.
      }
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.calendarPlus,
        title: 'sheets.extend_subscriber'.tr(),
        subtitle: widget.sub.fullName,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label:
            _submitting ? 'جاري التمديد...' : (_disabledReason ?? 'تمديد الآن'),
        icon: LucideIcons.calendarPlus,
        enabled: _canSubmit,
        busy: _submitting,
        onPressed: _submit,
        above: PrintReceiptCheckbox(
          value: _printReceiptChecked,
          onChanged: (v) => setState(() {
            _printTouched = true;
            _printReceiptChecked = v;
          }),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildBody(),
      ),
    );
  }

  /// جسم شيت التمديد بلغة المخطّط (2026-08-29): صفوف الحالة → قائمة
  /// الباقات كصفوف اختيار في حاوية واحدة → بطاقة الباقة المختارة
  /// الداكنة → طريقة الدفع كبلاطتين.
  List<Widget> _buildBody() {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.mega),
          child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brandAccent, strokeWidth: 2.5),
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        _stateBlock(LucideIcons.triangleAlert, _loadError!,
            color: AppColors.error, onRetry: _load)
      ];
    }
    final pkgs = (_data?['packages'] as List?) ?? const [];
    if (pkgs.isEmpty) {
      return [
        _stateBlock(LucideIcons.inbox, 'لا توجد باقات متاحة للتمديد'),
      ];
    }
    final cur = 'common.currency'.tr();
    final list =
        pkgs.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return [
      SheetRowsGroup(
        rows: [
          SheetRowData(
            label: 'الباقة الحالية',
            value: _currentProfileName.isEmpty ? '—' : _currentProfileName,
          ),
          if (!_isEarthlink)
            SheetRowData(
              label: 'dashboard.manager_balance'.tr(),
              value: '${formatIQD(_managerBalance.round())} $cur',
            ),
          if (_pointsBalance > 0)
            SheetRowData(
              label: 'sheets.points'.tr(),
              value: formatIQD(_pointsBalance.round()),
              valueColor: AppColors.warningFill,
            ),
        ],
      ),
      const SizedBox(height: 14),
      // ايرث لنك: حقلٌ يفتح قائمة الباقات بدل الصفوف (بلاغ ٢٠٢٦-١٠-١٣) —
      // الترتيب والاختيار الافتراضيّ (الأولى) كما هما. SAS4 بلا تغيير.
      if (_isEarthlink)
        SheetSection(
          label: 'الباقة',
          child: _elPackageField(list),
        )
      else
        SheetSection(
          label: 'اختر باقة التمديد',
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.divider),
                  _PackageRow(
                    pkg: list[i],
                    selected: _selectedPkg == list[i],
                    onTap: () => setState(() => _selectedPkg = list[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (_selectedPkg != null) ...[
        const SizedBox(height: 14),
        SheetPlanCard(
          planLabel: 'الباقة المختارة',
          planName: (_selectedPkg!['name'] ?? '—').toString(),
          durationLabel:
              (_selectedDuration ?? '').isEmpty ? null : _selectedDuration,
          amountLabel: 'sheets.amount_due'.tr(),
          amount: _method == _Method.points
              ? '${formatIQD(_selectedPoints.round())} نقطة'
              : '${formatIQD(_selectedPrice.round())} $cur',
        ),
        // ايرث لنك: لا اختيار طريقة — التمديد بالنقاط حصراً (user/extend ٢٤ ساعة).
        if (!_isEarthlink) ...[
          const SizedBox(height: 14),
          SheetSection(
            label: 'sheets.payment_method'.tr(),
            gap: Sp.sm,
            child: SheetChoiceTiles(
              labels: [
                'الرصيد',
                _selectedPoints > 0
                    ? 'النقاط (${formatIQD(_selectedPoints.round())})'
                    : 'النقاط',
              ],
              icons: const [LucideIcons.wallet, LucideIcons.star],
              selectedIndex: _method == _Method.balance ? 0 : 1,
              enabled: !_submitting,
              onSelect: (i) {
                // الدفع بالنقاط متاح فقط حين تتطلّب الباقة نقاطاً.
                if (i == 1 && _selectedPoints <= 0) return;
                setState(
                    () => _method = i == 0 ? _Method.balance : _Method.points);
              },
            ),
          ),
        ],
      ],
    ];
  }

  /// حقل باقة ايرث لنك. الاختيار بالمعرّف (ما يُرسَل للخادم) لا بهويّة
  /// الخريطة: `cast` تبني غلافاً جديداً في كلّ بناء فلا تطابق المحفوظة.
  /// التمديد هنا بالنقاط وحدها، فالسعر الصفريّ لا يُعرض («0 د.ع» تضلّل).
  /// ايرث لنك: تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ، و«More» لا (حكم الخادم بصفّ المشترك، وإلّا ٢٤ ساعة).
  bool get _elPackageLocked {
    final rowFlag = widget.sub.canChangePackage;
    if (rowFlag != null) return !rowFlag;
    final exp = widget.sub.parsedExpiration;
    return exp != null && exp.difference(DateTime.now()) > const Duration(hours: 24);
  }

  Widget _elPackageField(List<Map<String, dynamic>> list) {
    final locked = _elPackageLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _elPackagePicker(list, locked),
        if (locked) ...[
          const SizedBox(height: Sp.xs),
          Text(
            widget.sub.packageChangeNote ?? 'تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ — هذا المشترك ما زال فعّالاً',
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _elPackagePicker(List<Map<String, dynamic>> list, bool locked) {
    return PackagePickerField(
      options: [
        for (final p in list)
          PackageOption(
            id: p['id']?.toString() ?? '',
            name: (p['name'] ?? '').toString(),
            price: _read(p, 'price') > 0 ? _read(p, 'price') : null,
            points: _read(p, 'reward_points_required'),
          ),
      ],
      selectedId: _selectedPkg?['id']?.toString(),
      currentId: _data?['current_profile_id']?.toString(),
      enabled: !_submitting && !locked,
      onSelected: (id) {
        for (final p in list) {
          if ((p['id']?.toString() ?? '') == id) {
            setState(() => _selectedPkg = p);
            return;
          }
        }
      },
    );
  }

  Widget _stateBlock(IconData icon, String text,
      {Color? color, VoidCallback? onRetry}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.huge),
      child: Column(
        children: [
          Icon(icon, color: color ?? AppColors.textHint, size: 32),
          const SizedBox(height: Sp.md),
          Text(text,
              style: AppType.rowValue(color: color ?? AppColors.textMid),
              textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: Sp.sm),
            TextButton(onPressed: onRetry, child: Text('common.retry'.tr())),
          ],
        ],
      ),
    );
  }
}

/// صفّ باقة داخل حاوية الاختيار — دائرة اختيار + الاسم + حبّة النقاط
/// + السعر. الأزرق `#3B82F6` القديم استُبدل بالبراند.
class _PackageRow extends StatelessWidget {
  const _PackageRow({
    required this.pkg,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> pkg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final name = pkg['name']?.toString() ?? '';
    final price = pkg['price'] is num
        ? (pkg['price'] as num).toInt()
        : int.tryParse(pkg['price']?.toString() ?? '') ?? 0;
    final points = pkg['reward_points_required'] is num
        ? (pkg['reward_points_required'] as num).toInt()
        : int.tryParse(pkg['reward_points_required']?.toString() ?? '') ?? 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              color: selected ? AppColors.brand : AppColors.textHint,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: AppType.input(
                  color: selected ? AppColors.textHi : AppColors.textBody,
                ).copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (points > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: Sp.xs),
                decoration: BoxDecoration(
                  color: AppColors.warningSoftBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Text(
                  '${formatIQD(points)} نقطة',
                  style: AppType.pillLabel(color: AppColors.warningOnSoft)
                      .copyWith(letterSpacing: 0),
                ),
              ),
              const SizedBox(width: Sp.x6),
            ],
            Text(
              '${formatIQD(price)} ${'common.currency'.tr()}',
              textDirection: ui.TextDirection.ltr,
              style: AppType.bodyStrong(color: AppColors.brandAccent)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
