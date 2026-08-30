import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../widgets/device_image.dart';

/// اختيار صورة الجهاز يدويّاً حين لا يُطابق الطراز المُبلَّغ أيّ صورة.
///
/// ⚠️ سبب وجوده: أسماء ميكروتك ثنائيّة (اسم لوحة واسم تجاري) وغير
/// منتظمة، فكلّ طراز جديد لا يُطابق كان يتطلّب إضافة مرادف في الكود —
/// أي إصداراً جديداً لكلّ جهاز. هذا يُنهي التبعيّة: المستخدم يعرف
/// جهازه فيختار صورته بنفسه.
///
/// الاختيار **يكتب اسم اللوحة في `model`** لا في حقل جديد: فيصير
/// الجهاز مُطابَقاً بالمسار العادي، وتظهر صورته في القائمة والتفاصيل
/// بلا منطق إضافي — ويستفيد منه أيّ جهاز آخر بالطراز نفسه.
Future<String?> showDeviceImagePicker(
  BuildContext context, {
  required String brand,
  String? currentModel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _PickerSheet(brand: brand, currentModel: currentModel),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.brand, this.currentModel});
  final String brand;
  final String? currentModel;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final q = _search.text.trim().toLowerCase();
    // بوّابة العلامة تُطبَّق هنا أيضاً: لا معنى لعرض سويتش ميكروتك على
    // جهاز ubnt ولو يدويّاً — نفس الخطأ الذي تمنعه المطابقة التلقائيّة.
    final all = DeviceImage.allAssets.where((f) {
      final board = DeviceImage.boardNameOf(f);
      if (DeviceImage.assetFor(board, brand: widget.brand) == null) return false;
      return q.isEmpty || f.toLowerCase().contains(q);
    }).toList();

    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.image,
        title: 'اختيار صورة الجهاز',
        subtitle: (widget.currentModel?.trim().isNotEmpty ?? false)
            ? 'الطراز الحالي: ${widget.currentModel}'
            : 'لم يُطابق أيّ صورة',
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.md),
            child: SheetSearchField(
              controller: _search,
              hint: 'ابحث بالطراز…',
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (all.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  q.isEmpty
                      ? 'لا صور لهذه العلامة'
                      : 'لا نتائج — جرّب جزءاً من الاسم',
                  style: AppType.body(color: AppColors.textLow),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.xxl),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: all.length,
                itemBuilder: (_, i) => _Tile(
                  file: all[i],
                  onTap: () => Navigator.of(context)
                      .pop(DeviceImage.boardNameOf(all[i])),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.file, required this.onTap});
  final String file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            children: [
              Expanded(
                child: Image.asset('assets/devices-images/$file',
                    fit: BoxFit.contain),
              ),
              const SizedBox(height: 4),
              Text(
                DeviceImage.boardNameOf(file),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppType.micro(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
