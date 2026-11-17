import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/portal_services_api.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/merged_section.dart';

/// «خدماتنا» (١٦ نوفمبر ٢٠٢٦): تطبيقات الوكيل وصفحاته لمشتركيه — اسمٌ ورابطٌ وصورةٌ يضغطها التطبيق، يراها المشترك في «وكيلي»
/// بتطبيق MyServices ويفتح الرابط بنقرة. الصفّ كلّه يفتح التعديل (والحذف داخله بتأكيد)، وسهما الترتيب بجانبه، وبطاقة «كما يراها
/// مشتركوك» تحت القائمة. التبويب بـ`settings.edit` (مقفلٌ بمكانه بدونه — portal_settings_screen).

// ─────────────── ضغط الصورة ───────────────

const serviceIconSide = 256;
const serviceIconMaxBytes = 300 * 1024;

class ServiceImageError implements Exception {
  const ServiceImageError(this.reason);

  /// decode · too-big
  final String reason;
  String get message => reason == 'too-big' ? 'الصورة كبيرة جداً — اختر صورةً أخرى' : 'تعذّر قراءة الصورة — اختر صورةً أخرى';
}

/// الصورة كما اختيرت ⇒ مربّعٌ من وسطها بضلع ≤ 256 بلا EXIF ولا ملفّ ألوان: PNG إن كانت فيها شفافيّة (زوايا الأيقونات)، وإلّا JPEG
/// بجودة 85 (ثمّ 70 ثمّ 55) — تحت 300 ك.ب دائماً. نقيّة (تُشغَّل في معزل).
ServiceImage prepareServiceIcon(Uint8List raw, {int side = serviceIconSide}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const ServiceImageError('decode');
  final base = img.bakeOrientation(decoded);
  final s = math.min(base.width, base.height);
  var sq = img.copyCrop(base, x: (base.width - s) ~/ 2, y: (base.height - s) ~/ 2, width: s, height: s);
  if (s > side) sq = img.copyResize(sq, width: side, height: side, interpolation: img.Interpolation.average);
  sq.exif = img.ExifData();
  sq.iccProfile = null;
  if (sq.hasAlpha) {
    final png = img.encodePng(sq, level: 9);
    if (png.length <= serviceIconMaxBytes) return ServiceImage(png, 'image/png');
  }
  final flat = img.Image(width: sq.width, height: sq.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, sq);
  for (final q in const [85, 70, 55]) {
    final jpg = img.encodeJpg(flat, quality: q);
    if (jpg.length <= serviceIconMaxBytes) return ServiceImage(jpg, 'image/jpeg');
  }
  throw const ServiceImageError('too-big');
}

(ServiceImage?, String?) _prepareInIsolate(Uint8List raw) {
  try {
    return (prepareServiceIcon(raw), null);
  } on ServiceImageError catch (e) {
    return (null, e.reason);
  } catch (_) {
    return (null, 'decode');
  }
}

/// يختار صورةً من المعرض ويجهّزها. null = ألغى. [ServiceImageError] = تعذّرت.
typedef ServiceImagePicker = Future<ServiceImage?> Function();

Future<ServiceImage?> pickServiceImage() async {
  final XFile? f;
  try {
    f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 95,
      requestFullMetadata: false,
    );
  } catch (_) {
    throw const ServiceImageError('decode');
  }
  if (f == null) return null;
  final raw = await f.readAsBytes();
  if (raw.isEmpty) throw const ServiceImageError('decode');
  final (ServiceImage?, String?) r;
  try {
    r = await compute(_prepareInIsolate, raw);
  } catch (_) {
    throw const ServiceImageError('decode');
  }
  if (r.$1 == null) throw ServiceImageError(r.$2 ?? 'decode');
  return r.$1;
}

/// فحص الحقول كالخادم (رسالةٌ عربيّة أو null) — الخادم يبقى الحَكَم.
String? validateService(String name, String url) {
  final n = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (n.isEmpty) return 'اكتب اسم الخدمة';
  if (n.runes.length > PortalServicesApi.nameMax) return 'الاسم طويل — حتى ${PortalServicesApi.nameMax} حرفاً';
  final raw = url.trim();
  if (raw.isEmpty) return 'الصق رابط الخدمة أو التطبيق';
  if (raw.contains(RegExp(r'\s'))) return 'الرابط فيه مسافات — الصقه كما هو';
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(raw) ? raw : 'https://$raw';
  final u = Uri.tryParse(withScheme);
  if (u == null || (u.scheme != 'https' && u.scheme != 'http') || !u.host.contains('.')) {
    return 'الرابط غير صالح — الصق رابط التطبيق أو الصفحة (يبدأ بـ https://)';
  }
  return null;
}

// ─────────────── التبويب ───────────────

class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key, this.picker = pickServiceImage});

  /// اختيار الصورة وضغطها — يُستبدل في الاختبارات.
  final ServiceImagePicker picker;

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  List<PortalService> _items = const [];
  int _limit = PortalServicesApi.defaultLimit;
  ServicesLoad _state = ServicesLoad.ok;
  bool _loading = true;
  bool _ordering = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await PortalServicesApi.list();
    if (!mounted) return;
    setState(() {
      _state = r.state;
      _items = r.services;
      _limit = r.limit;
      _loading = false;
    });
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.errorFill : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _edit(PortalService? s) async {
    final changed = await showAppSheet<bool>(
      barrierColor: AppColors.scrim,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServiceEditorSheet(service: s, picker: widget.picker),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _move(int i, int dir) async {
    final j = i + dir;
    if (_ordering || j < 0 || j >= _items.length) return;
    final was = _items;
    final next = List<PortalService>.of(_items);
    final t = next[i];
    next[i] = next[j];
    next[j] = t;
    setState(() {
      _items = next;
      _ordering = true;
    });
    final r = await PortalServicesApi.order([for (final s in next) s.id]);
    if (!mounted) return;
    setState(() {
      _ordering = false;
      if (r.services != null) {
        _items = r.services!;
      } else {
        _items = was;
      }
    });
    if (r.services == null) _snack(r.message ?? 'تعذّر حفظ الترتيب — حاول مرّة ثانية', error: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (_loading) return const Center(child: CircularProgressIndicator());
    final viewOnly = MergedSection.viewOnlyOf(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          _Header(
            count: _items.length,
            limit: _limit,
            canAdd: !viewOnly && _state == ServicesLoad.ok && _items.length < _limit,
            showAdd: !viewOnly && _state == ServicesLoad.ok,
            onAdd: () => _edit(null),
          ),
          const SizedBox(height: Sp.md),
          if (_state == ServicesLoad.failed || _state == ServicesLoad.denied)
            _Notice(
              icon: LucideIcons.wifiOff,
              text: _state == ServicesLoad.denied ? 'ليس لديك صلاحيّة لعرض الخدمات' : 'تعذّر جلب الخدمات الآن',
              onRetry: _state == ServicesLoad.failed ? _load : null,
            )
          else if (_state == ServicesLoad.unavailable)
            const _Notice(icon: LucideIcons.clock, text: 'الخدمات غير متاحة بعد — حاول لاحقاً')
          else if (_items.isEmpty)
            const _Notice(
              icon: LucideIcons.layoutGrid,
              title: 'ما أضفت خدمات بعد',
              text: 'أضف تطبيقك أو صفحتك: اسمٌ ورابط وصورة — تنضغط الصورة تلقائيّاً',
            )
          else ...[
            for (final (i, s) in _items.indexed) ...[
              _ServiceRow(
                service: s,
                onEdit: viewOnly ? null : () => _edit(s),
                onUp: viewOnly || i == 0 || _ordering ? null : () => _move(i, -1),
                onDown: viewOnly || i == _items.length - 1 || _ordering ? null : () => _move(i, 1),
              ),
              const SizedBox(height: Sp.sm),
            ],
            const SizedBox(height: Sp.sm),
            _Preview(items: _items),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.limit, required this.canAdd, required this.showAdd, required this.onAdd});
  final int count;
  final int limit;
  final bool canAdd;
  final bool showAdd;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.textMid.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.sm)),
            child: Icon(LucideIcons.layoutGrid, color: AppColors.brand, size: 20),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('خدماتنا', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                'تطبيقاتك وصفحاتك — يراها مشتركوك في «وكيلي» بتطبيق MyServices ويفتحونها بنقرة',
                style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11.5),
              ),
            ]),
          ),
        ]),
        if (showAdd) ...[
          const SizedBox(height: Sp.md),
          FilledButton.icon(
            onPressed: canAdd ? onAdd : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
            ),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(
              count >= limit ? 'وصلت الحدّ ($limit خدمة)' : 'إضافة خدمة  $count/$limit',
              style: AppType.button(color: AppColors.onBrand),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.title, this.onRetry});
  final IconData icon;
  final String? title;
  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.xxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.textMid.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 40, color: AppColors.textMid.withValues(alpha: 0.5)),
        const SizedBox(height: Sp.md),
        if (title != null) ...[
          Text(title!, textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 15)),
          const SizedBox(height: 4),
        ],
        Text(text, textAlign: TextAlign.center, style: AppType.subtitle(color: AppColors.textMid)),
        if (onRetry != null) ...[
          const SizedBox(height: Sp.sm),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ]),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.name, required this.initial, this.url, this.bytes, this.size = 44});
  final String name;
  final String initial;
  final String? url;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(size >= 56 ? 16 : R.sm);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: r),
      child: Text(initial, style: AppType.title(color: AppColors.brand).copyWith(fontSize: size * 0.4)),
    );
    if (bytes == null && url == null) return fallback;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: r, border: Border.all(color: AppColors.textMid.withValues(alpha: 0.15))),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes!, fit: BoxFit.cover, width: size, height: size, excludeFromSemantics: true)
          : Image.network(url!, fit: BoxFit.cover, width: size, height: size, excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => fallback),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.onEdit, required this.onUp, required this.onDown});
  final PortalService service;
  final VoidCallback? onEdit;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textMid.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(children: [
          // الصفّ كلّه يفتح التعديل — الاسم والمضيف كاملان (ينزلان لسطرٍ ثانٍ ولا يُقصّان)
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.md, Sp.sm, Sp.md),
                child: Row(children: [
                  _ServiceIcon(name: s.name, initial: s.initial, url: s.image),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(s.host,
                          textDirection: TextDirection.ltr,
                          style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11.5)),
                    ]),
                  ),
                  if (onEdit != null) Icon(LucideIcons.pencil, size: 16, color: AppColors.textMid),
                ]),
              ),
            ),
          ),
          if (onUp != null || onDown != null)
            Column(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'تحريك للأعلى',
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.arrowUp, size: 18),
                onPressed: onUp,
              ),
              IconButton(
                tooltip: 'تحريك للأسفل',
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.arrowDown, size: 18),
                onPressed: onDown,
              ),
            ]),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.items});
  final List<PortalService> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.md, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.textMid.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
          child: Text('كما يراها مشتركوك', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 14)),
        ),
        const SizedBox(height: Sp.md),
        LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 84).floor().clamp(3, 6);
          final w = c.maxWidth / cols;
          return Wrap(runSpacing: Sp.md, children: [
            for (final s in items)
              SizedBox(
                width: w,
                child: Column(children: [
                  _ServiceIcon(name: s.name, initial: s.initial, url: s.image, size: 56),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      s.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppType.subtitle(color: AppColors.textHi).copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
          ]);
        }),
      ]),
    );
  }
}

// ─────────────── الإضافة والتعديل ───────────────

class ServiceEditorSheet extends StatefulWidget {
  const ServiceEditorSheet({super.key, this.service, this.picker = pickServiceImage});

  /// null = خدمة جديدة.
  final PortalService? service;
  final ServiceImagePicker picker;

  @override
  State<ServiceEditorSheet> createState() => _ServiceEditorSheetState();
}

class _ServiceEditorSheetState extends State<ServiceEditorSheet> {
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _url = TextEditingController(text: widget.service?.url ?? '');
  ServiceImage? _image;
  bool _removeImage = false;
  bool _busy = false;
  bool _picking = false;
  String? _err;

  bool get _isNew => widget.service == null;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _err = null;
    });
    try {
      final im = await widget.picker();
      if (!mounted) return;
      if (im != null) {
        setState(() {
          _image = im;
          _removeImage = false;
        });
      }
    } on ServiceImageError catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final bad = validateService(_name.text, _url.text);
    if (bad != null) return setState(() => _err = bad);
    setState(() {
      _busy = true;
      _err = null;
    });
    final s = widget.service;
    final ServiceWrite r;
    if (s == null) {
      r = await PortalServicesApi.create(name: _name.text, url: _url.text, image: _image);
    } else {
      final name = _name.text.trim() != s.name ? _name.text : null;
      final url = _url.text.trim() != s.url ? _url.text : null;
      if (name == null && url == null && _image == null && !_removeImage) {
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      r = await PortalServicesApi.update(s.id, name: name, url: url, image: _image, removeImage: _removeImage);
    }
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _err = r.denied
          ? 'ليس لديك صلاحيّة لتغيير هذا الإعداد — اطلب صلاحيّة «تعديل إعدادات النظام» من مديرك'
          : (r.message ?? 'تعذّر الحفظ — حاول مرّة ثانية');
    });
  }

  Future<void> _delete() async {
    final s = widget.service;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخدمة؟'),
        content: Text('«${s.name}» تنحذف عند كلّ مشتركيك.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('حذف نهائياً', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final r = await PortalServicesApi.remove(s.id);
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _err = r.message ?? 'تعذّر الحذف — حاول مرّة ثانية';
    });
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppType.subtitle(color: AppColors.textMid.withValues(alpha: 0.5)),
        filled: true,
        fillColor: AppColors.surfaceInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(R.sm),
          borderSide: BorderSide(color: AppColors.brand),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final showUrl = !_removeImage && _image == null ? s?.image : null;
    final hasImage = _image != null || showUrl != null;
    final label = Text('اسم الخدمة', style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11));
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.layoutGrid,
        title: _isNew ? 'خدمة جديدة' : 'تعديل الخدمة',
        subtitle: 'تظهر لمشتركيك بصورتها واسمها، وتفتح الرابط بنقرة',
        onClose: _busy ? () {} : () => Navigator.of(context).pop(false),
      ),
      footer: SheetFooterBar(
        label: _isNew ? 'إضافة' : 'حفظ',
        icon: _isNew ? LucideIcons.plus : LucideIcons.save,
        busy: _busy,
        onPressed: _picking ? null : _save,
        leading: _isNew
            ? null
            : SheetFooterIconButton(icon: LucideIcons.trash2, color: AppColors.error, onTap: _busy ? null : _delete),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Sp.lg),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  hasImage
                      ? _ServiceIcon(
                          name: _name.text,
                          initial: '',
                          url: showUrl,
                          bytes: _image?.bytes,
                          size: 64,
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(R.lg),
                            border: Border.all(color: AppColors.textMid.withValues(alpha: 0.35)),
                          ),
                          child: Icon(LucideIcons.imagePlus, color: AppColors.textMid),
                        ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: Sp.sm, runSpacing: Sp.xs, children: [
                        OutlinedButton.icon(
                          onPressed: _busy || _picking ? null : _pick,
                          icon: _picking
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(LucideIcons.imagePlus, size: 16),
                          label: Text(hasImage ? 'تغيير الصورة' : 'اختيار صورة'),
                        ),
                        if (hasImage)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _image = null;
                                      _removeImage = true;
                                    }),
                            icon: const Icon(LucideIcons.x, size: 16),
                            label: const Text('إزالة'),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        _image != null
                            ? 'بعد الضغط: ${(_image!.bytes.length / 1024).ceil()} ك.ب — مربّع $serviceIconSide بكسل'
                            : 'تنضغط تلقائيّاً لمربّعٍ صغير (اختياريّة)',
                        style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11.5),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: Sp.lg),
                label,
                const SizedBox(height: 4),
                TextField(
                  controller: _name,
                  maxLength: PortalServicesApi.nameMax + 10,
                  style: AppType.subtitle(color: AppColors.textHi),
                  decoration: _dec('مثلاً: تطبيق الأفلام').copyWith(counterText: ''),
                ),
                const SizedBox(height: Sp.md),
                Text('الرابط', style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11)),
                const SizedBox(height: 4),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppType.subtitle(color: AppColors.textHi),
                  decoration: _dec('https://play.google.com/store/apps/details?id=…'),
                ),
                const SizedBox(height: 4),
                Text(
                  'رابط التطبيق في المتجر، أو صفحة، أو قناة — يفتح عند المشترك بنقرة',
                  style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 11.5),
                ),
                if (_err != null) ...[
                  const SizedBox(height: Sp.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Sp.sm),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoftBg,
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Text(_err!, style: AppType.subtitle(color: AppColors.error)),
                  ),
                ],
                const SizedBox(height: Sp.md),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
