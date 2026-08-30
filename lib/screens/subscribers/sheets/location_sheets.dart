import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/subscribers_api.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../services/permissions_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import 'location_picker_screen.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// 2026-08-26: chooser الصغير — نقرة على أيقونة الموقع تفتح قائمة
/// خيارات فتح (Google Maps / Waze / نسخ). يتعامل مع فتح روابط
/// الملاحة الخارجية بلا حاجة SDK.
///
/// روابط الملاحة:
/// - Google Maps: https://www.google.com/maps?q=LAT,LNG
/// - Waze:        https://waze.com/ul?ll=LAT,LNG&navigate=yes
Future<void> showLocationChooserSheet(
  BuildContext context, {
  required Subscriber sub,
}) {
  if (!sub.hasLocation) return Future.value();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _ChooserSheet(sub: sub),
  );
}

/// Smart entry — يقرّر ما يعرض حسب حالة الموقع + الصلاحيّة:
///  - موقع مُعيَّن: chooser (Google Maps + Waze + نسخ + تعديل لو صلاحيّة).
///  - لا موقع + صلاحيّة تعديل: edit sheet مباشرة.
///  - لا موقع + لا صلاحيّة: لا شيء.
Future<void> showLocationSheet(
  BuildContext context, {
  required Subscriber sub,
}) async {
  if (sub.hasLocation) {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _ChooserSheet(sub: sub, allowEdit: canEditLocation()),
    );
    return;
  }
  if (!canEditLocation()) return;
  await showLocationEditSheet(context, sub: sub);
}

/// شاشة تعديل موقع GPS — لصق رابط Google Maps، إدخال إحداثيّات
/// يدوياً، أو حذف. يستدعي PATCH /api/v2/subscribers/:idx/location.
/// Returns true لو تمّ حفظ/حذف بنجاح.
Future<bool?> showLocationEditSheet(
  BuildContext context, {
  required Subscriber sub,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _EditSheet(sub: sub),
  );
}

class _ChooserSheet extends StatelessWidget {
  const _ChooserSheet({required this.sub, this.allowEdit = false});
  final Subscriber sub;
  final bool allowEdit;

  Future<void> _open(String url, BuildContext ctx) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && ctx.mounted) {
      showSheetSnack(ctx, 'تعذّر فتح الرابط', isError: true);
    }
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  Future<void> _copy(BuildContext ctx) async {
    final coord =
        '${sub.latitude!.toStringAsFixed(6)},${sub.longitude!.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: coord));
    if (!ctx.mounted) return;
    showSheetSnack(ctx, 'نُسخت الإحداثيّات');
    Navigator.of(ctx).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lat = sub.latitude!;
    final lng = sub.longitude!;
    final coord = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.mapPin,
        title: 'موقع المشترك',
        subtitle: coord,
        subtitleLtr: true,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _actionRow(
            icon: LucideIcons.map,
            label: 'فتح في Google Maps',
            color: const Color(0xFF4285F4),
            onTap: () =>
                _open('https://www.google.com/maps?q=$lat,$lng', context),
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: LucideIcons.navigation,
            label: 'فتح في Waze',
            color: const Color(0xFF33CCFF),
            onTap: () =>
                _open('https://waze.com/ul?ll=$lat,$lng&navigate=yes', context),
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: LucideIcons.copy,
            label: 'نسخ الإحداثيّات',
            color: AppColors.textMid,
            onTap: () => _copy(context),
          ),
          if (allowEdit) ...[
            const SizedBox(height: 8),
            _actionRow(
              icon: LucideIcons.pencil,
              label: 'تعديل الموقع',
              color: AppColors.warning,
              onTap: () async {
                Navigator.of(context).pop();
                await showLocationEditSheet(context, sub: sub);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13.5, height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHi,
                    )),
              ),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.sub});
  final Subscriber sub;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  final _inputCtrl = TextEditingController();
  double? _lat;
  double? _lng;
  bool _saving = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    // pre-fill بالإحداثيّات الحاليّة (لو موجودة)
    if (widget.sub.hasLocation) {
      _lat = widget.sub.latitude;
      _lng = widget.sub.longitude;
      _inputCtrl.text =
          '${_lat!.toStringAsFixed(6)},${_lng!.toStringAsFixed(6)}';
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  /// يستخرج lat,lng من:
  /// - "33.31,44.36" (خام)
  /// - "https://www.google.com/maps?q=33.31,44.36"
  /// - "https://maps.google.com/maps/@33.31,44.36,15z"
  /// - "https://maps.google.com/?q=loc:33.31,44.36"
  /// - "https://waze.com/ul?ll=33.31,44.36"
  /// يرفض روابط goo.gl القصيرة (تحتاج HTTP resolve).
  (double?, double?, String?) _parseInput(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return (null, null, null);
    if (s.contains('goo.gl') || s.contains('maps.app.goo.gl')) {
      return (
        null,
        null,
        'روابط goo.gl القصيرة غير مدعومة — افتحها ثم انسخ الإحداثيّات'
      );
    }
    // نمط عام: يبحث عن أوّل زوجَي أرقام lat,lng في النصّ.
    final re = RegExp(
      r'(-?\d{1,2}\.\d{2,10})[,\s@=/]+(-?\d{1,3}\.\d{2,10})',
    );
    final m = re.firstMatch(s);
    if (m == null) {
      return (
        null,
        null,
        'ما قدرت أستخرج إحداثيّات — الصق رابط Google Maps أو "lat,lng"'
      );
    }
    final lat = double.tryParse(m.group(1)!);
    final lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null) {
      return (null, null, 'قيم غير صالحة');
    }
    if (lat < -90 || lat > 90) return (null, null, 'خط العرض خارج المدى (±90)');
    if (lng < -180 || lng > 180)
      return (null, null, 'خط الطول خارج المدى (±180)');
    return (lat, lng, null);
  }

  void _onInputChanged(String v) {
    final (lat, lng, err) = _parseInput(v);
    setState(() {
      _lat = lat;
      _lng = lng;
      _parseError = err;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _inputCtrl.text = text;
    _onInputChanged(text);
  }

  /// يفتح شاشة الخريطة — لو المدير عند بيت المشترك يقدر يضغط
  /// "موقعي الحالي" داخل الشاشة، ويحرّك بيده لضبط بدقّة.
  Future<void> _pickOnMap() async {
    final initial =
        (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    final picked = await showLocationPickerScreen(context, initial: initial);
    if (picked == null || !mounted) return;
    final txt = '${picked.latitude.toStringAsFixed(6)},'
        '${picked.longitude.toStringAsFixed(6)}';
    _inputCtrl.text = txt;
    _onInputChanged(txt);
  }

  Future<void> _save() async {
    final idx = widget.sub.idx;
    if (idx == null || _lat == null || _lng == null) return;
    setState(() => _saving = true);
    final r = await SubscribersApi.setLocation(idx, lat: _lat, lng: _lng);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      SubscriberEvents.notifyChange();
      showSheetSnack(context, 'تم حفظ الموقع');
      Navigator.of(context).pop(true);
    } else {
      // 409 مع existingText = تصادم مع نصّ يدوي
      if (r.code == 'address_has_manual_text' &&
          (r.existingText ?? '').isNotEmpty) {
        _showConflictDialog(r.existingText!);
      } else {
        showSheetSnack(context, r.message ?? 'فشل الحفظ', isError: true);
      }
    }
  }

  Future<void> _clear() async {
    final idx = widget.sub.idx;
    if (idx == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('حذف الموقع',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: const Text('سيُحذف موقع GPS المخزَّن. متأكّد؟',
            style: TextStyle(fontFamily: 'Cairo', height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final r = await SubscribersApi.setLocation(idx, clear: true);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.ok) {
      SubscriberEvents.notifyChange();
      showSheetSnack(context, 'حُذف الموقع');
      Navigator.of(context).pop(true);
    } else {
      showSheetSnack(context, r.message ?? 'فشل الحذف', isError: true);
    }
  }

  void _showConflictDialog(String existing) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('الحقل مستخدَم',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'حقل العنوان في SAS4 يحتوي نصّاً يدوياً:',
              style: TextStyle(
                  fontFamily: 'Cairo', height: 1.6, color: AppColors.textMid),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceInput,
                borderRadius: BorderRadius.circular(R.sm),
              ),
              child: SelectableText(
                existing,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5, height: 1.4,
                  color: AppColors.textHi,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'احذفه من SAS4 (لوحة الإدارة → المشترك → العنوان) أوّلاً، ثم أعد المحاولة.',
              style: TextStyle(
                  fontFamily: 'Cairo', height: 1.6, color: AppColors.textMid),
            ),
          ],
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('فهمت',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasParsed = _lat != null && _lng != null;
    final canSave = hasParsed && !_saving;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.mapPin,
        title: widget.sub.hasLocation ? 'تعديل الموقع' : 'إضافة موقع',
        subtitle: widget.sub.fullName,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جارٍ الحفظ...' : 'حفظ',
        icon: LucideIcons.save,
        enabled: canSave,
        busy: _saving,
        onPressed: _save,
        leading: widget.sub.hasLocation
            ? SheetFooterIconButton(
                icon: LucideIcons.trash2,
                color: AppColors.error,
                onTap: _saving ? null : _clear,
              )
            : null,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.sub.hasManualAddressText) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: AppColors.dangerSoftBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.triangleAlert,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حقل العنوان في SAS4 يحتوي نصّاً يدوياً — احذفه من لوحة SAS4 أوّلاً.',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: AppColors.textHi,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // زر الخريطة — الطريقة الأسهل: المدير عند البيت يضغط
          // "موقعي الحالي" داخل الشاشة، ويقدر يحرّك الدبّوس لضبط.
          if (!widget.sub.hasManualAddressText) ...[
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _saving ? null : _pickOnMap,
                icon: const Icon(LucideIcons.map, size: 16),
                label: const Text(
                  'اختر من الخريطة (موقعك الحالي)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13, height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(R.md)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.border, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('أو',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11, height: 1.35,
                        color: AppColors.textMid,
                      )),
                ),
                Expanded(child: Divider(color: AppColors.border, height: 1)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Text('الصق رابط Google Maps أو "lat,lng"',
              style: AppType.bodyBold(color: AppColors.textMid)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  onChanged: _onInputChanged,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5, height: 1.4,
                    color: AppColors.textHi,
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://maps.google.com/… أو 33.315,44.366',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5, height: 1.35,
                      color: AppColors.textLow,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide:
                          BorderSide(color: AppColors.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide:
                          BorderSide(color: AppColors.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(R.sm),
                      borderSide:
                          BorderSide(color: AppColors.success, width: 1),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(LucideIcons.clipboardPaste,
                    size: 18, color: AppColors.brand),
                onPressed: _pasteFromClipboard,
                tooltip: 'لصق',
              ),
            ],
          ),
          if (_parseError != null) ...[
            const SizedBox(height: 6),
            Text(
              _parseError!,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                color: AppColors.error,
                height: 1.5,
              ),
            ),
          ],
          if (hasParsed && _parseError == null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.successSoftBg,
                borderRadius: BorderRadius.circular(R.sm),
                border: Border.all(
                  color: AppColors.successSoftBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.circleCheck,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تمّ استخراج: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                      style: AppType.bodyBold(),
                      textDirection: TextDirection.ltr,
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

/// Utility: check لو المدير/الموظّف يقدر يعدّل الموقع.
bool canEditLocation() => Perms.has('subscribers.edit_location');
