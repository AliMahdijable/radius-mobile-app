import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// شاشة اختيار موقع GPS للمشترك على خريطة تفاعليّة.
/// نسخة مطابقة لآليّة drdounat/app/lib/widgets/location_picker.dart —
/// خريطة OpenStreetMap مع دبّوس ثابت في المركز يتحرّك بتحريك الخريطة
/// (يطابق UX تطبيقات التوصيل — الإصبع لا يغطّي الدبّوس عند اختياره).
///
/// [initial] موقع سابق (لو موجود) — نبدأ عليه بزوم قريب.
/// يرجع LatLng عند التأكيد، أو null عند الإلغاء.
///
/// السلوك:
/// - "موقعي الحالي" (FAB) يجلب موقع الجهاز عبر geolocator ويحرّك الخريطة.
/// - رفض إذن الموقع لا يغلق الشاشة — المدير يقدر يحرّك الخريطة بيده.
/// - OpenStreetMap tiles = مجانيّة بلا مفتاح API، لكن نلتزم بشرط
///   الإسناد المرئي © OpenStreetMap.
Future<LatLng?> showLocationPickerScreen(
  BuildContext context, {
  LatLng? initial,
}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(
      builder: (_) => _MapPickerScreen(initial: initial),
    ),
  );
}

/// نقطة البدء الافتراضيّة — بغداد (~الكرادة). المدير قد يكون في
/// أيّ محافظة، وعادة "موقعي الحالي" يُحرّك الخريطة فوراً. الـfallback
/// مهم فقط لو موقع الجهاز فشل ولا يوجد initial.
const _fallbackCenter = LatLng(33.3152, 44.3661);

class _MapPickerScreen extends StatefulWidget {
  const _MapPickerScreen({this.initial});
  final LatLng? initial;

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.initial ?? _fallbackCenter;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // لو ما فيه موقع سابق، جرّب موقع الجهاز تلقائياً — الحالة الأشيع
    // للمدير عند بيت المشترك.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('خدمة الموقع مغلقة في الجهاز — شغّلها من الإعدادات.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        _fail('لم يُسمح بالوصول للموقع — تقدر تحدّده يدوياً بتحريك الخريطة.');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        _fail('الإذن مرفوض دائماً — فعّله من إعدادات الجهاز أو حدّد يدوياً.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = here;
        _locating = false;
      });
      _map.move(here, 17);
    } catch (_) {
      _fail('تعذّر تحديد موقعك — حرّك الخريطة يدوياً للمكان الصحيح.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _locating = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('اختر موقع المشترك',
            style: AppType.buttonBold()),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.check, color: AppColors.success),
            tooltip: 'تأكيد',
            onPressed: () => Navigator.of(context).pop(_center),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: widget.initial != null ? 17 : 13,
                    // الدبّوس ثابت في مركز الشاشة — نقرأ المركز عند
                    // كل تحريك بحيث "الموقع المختار" = ما تحت الدبّوس.
                    onPositionChanged: (camera, _) => _center = camera.center,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.drag |
                          InteractiveFlag.doubleTapZoom |
                          InteractiveFlag.flingAnimation,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      // شرط استعمال OSM: التعريف بالتطبيق. نفس القيمة
                      // التي نستعملها في applicationId الأندرويد.
                      userAgentPackageName: 'com.mysvcs.radMysvcs',
                      maxZoom: 19,
                    ),
                    const _Attribution(),
                  ],
                ),
                // دبّوس ثابت في المركز — خارج شجرة الخريطة حتى لا
                // يتحرّك مع الـpan.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: _Pin(),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    heroTag: 'my_location',
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.success,
                    onPressed: _locating ? null : _locate,
                    child: _locating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: AppColors.success))
                        : const Icon(LucideIcons.locateFixed),
                  ),
                ),
                if (_error != null)
                  PositionedDirectional(
                    top: 12,
                    start: 12,
                    end: 12,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(R.sm),
                        border: Border.all(color: AppColors.error, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.triangleAlert,
                              size: 15, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                  fontFamily: AppType.family,
                                  fontSize: 12.5,
                                  color: AppColors.error,
                                  height: 1.6,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border:
                  Border(top: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'حرّك الخريطة حتى يقع الدبّوس على بيت المشترك',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppType.family,
                    color: AppColors.textMid,
                    fontSize: 11.5,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_center),
                    icon: const Icon(LucideIcons.check, size: 16),
                    label: const Text(
                      'تأكيد الموقع',
                      style: TextStyle(
                        fontFamily: AppType.family,
                        fontSize: 13.5, height: 1.35,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.mapPin, size: 44, color: AppColors.success),
        const SizedBox(
          width: 10,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x33000000),
              borderRadius: BorderRadius.all(Radius.circular(R.pill)),
            ),
          ),
        ),
      ],
    );
  }
}

/// إسناد OpenStreetMap — شرط الرخصة.
class _Attribution extends StatelessWidget {
  const _Attribution();
  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(color: Color(0xB3FFFFFF)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '© OpenStreetMap',
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 9.5, height: 1.2, color: Color(0xFF444444)),
            ),
          ),
        ),
      ),
    );
  }
}
