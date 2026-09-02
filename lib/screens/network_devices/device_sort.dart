import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/design_sheet.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// ترتيب الأجهزة — مشترك بين «نظرة عامّة» وقائمة الأجهزة.
///
/// ⚠️ وحدةٌ واحدة عمداً: كانت القائمة تحمل `_compareIps` خاصّتها
/// و«نظرة عامّة» تحمل `ipSortKey` خاصّتها — دالّتان تحلّان المسألة
/// نفسها. ونسختان من منطق ترتيب تنحرفان حتماً، فيرى المستخدم ترتيبين
/// مختلفين لنفس الأجهزة في شاشتين متجاورتين.
enum DeviceSortField {
  /// غير المتّصل أوّلاً ثمّ الأبطأ.
  health('الحالة', LucideIcons.activity),

  name('الاسم', LucideIcons.arrowDownAZ),

  /// يجمع أجهزة الشبكة الفرعيّة الواحدة متجاورةً.
  ip('العنوان', LucideIcons.network);

  const DeviceSortField(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum SortDir { asc, desc }

/// مفتاح ترتيب العنوان — **رقميّ لا نصّيّ**.
///
/// ⚠️ المقارنة النصّيّة تضع `10.70.241.10` قبل `10.70.241.9` لأنّ '1'
/// يسبق '9' حرفيّاً. والنتيجة قائمةٌ تبدو مرتّبةً وليست كذلك، وهي أسوأ
/// من قائمةٍ غير مرتّبة لأنّ العين تثق بها فتظنّ الجهاز غائباً وهو
/// أمامها.
///
/// نُعبّئ الخانات الأربع في عددٍ واحد فتصير المقارنة عدديّةً بحتة.
/// وما ليس IPv4 صالحاً يُدفع إلى الذيل بدل أن يرمي.
int ipSortKey(String ip) {
  final parts = ip.trim().split('.');
  if (parts.length != 4) return 1 << 33; // ليس IPv4 — إلى الذيل
  var key = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return 1 << 33;
    key = (key << 8) | n;
  }
  return key;
}

/// رتبة الصحّة: غير المتّصل أوّلاً، والمجهول قبل السليم — لم يُفحص
/// بعدُ فقد يكون ساقطاً.
int healthRank(NetworkDevice d) => switch (d.lastStatus) {
      'offline' => 0,
      'unknown' => 1,
      _ => 2,
    };

/// المقارنة الأساسيّة قبل تطبيق الاتّجاه.
///
/// ⚠️ كلّ فرعٍ ينتهي بفاصلٍ حاسم (الاسم): بلا ذلك يصير ترتيب
/// المتساويات غير مستقرّ، فتقفز البطاقات بين موضعين مع كلّ جولة مسح.
int _base(NetworkDevice a, NetworkDevice b, DeviceSortField f) {
  switch (f) {
    case DeviceSortField.name:
      return a.name.compareTo(b.name);
    case DeviceSortField.ip:
      final k = ipSortKey(a.ip).compareTo(ipSortKey(b.ip));
      return k != 0 ? k : a.name.compareTo(b.name);
    case DeviceSortField.health:
      final r = healthRank(a).compareTo(healthRank(b));
      if (r != 0) return r;
      // ثمّ الأبطأ أوّلاً — البطء يسبق السقوط.
      final ms = (b.lastResponseMs ?? 0).compareTo(a.lastResponseMs ?? 0);
      return ms != 0 ? ms : a.name.compareTo(b.name);
  }
}

/// يقارن جهازين وفق [f] و[dir].
///
/// «تصاعديّ» في [DeviceSortField.health] يعني **غير المتّصل أوّلاً**:
/// الرتبة تصعد من صفر (ساقط) إلى اثنين (سليم). وهو الافتراضيّ لأنّك
/// تفتح هذه الشاشات لتجد العطل لا لتتصفّح.
int compareDevices(
  NetworkDevice a,
  NetworkDevice b,
  DeviceSortField f,
  SortDir dir,
) {
  final c = _base(a, b, f);
  return dir == SortDir.asc ? c : -c;
}

/// ورقة اختيار المعيار والاتّجاه. تُعيد `null` إن أُغلقت بلا اختيار.
Future<({DeviceSortField field, SortDir dir})?> showDeviceSortSheet(
  BuildContext context, {
  required DeviceSortField field,
  required SortDir dir,
  String subtitle = 'المعيار والاتّجاه',
}) {
  return showModalBottomSheet<({DeviceSortField field, SortDir dir})>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    builder: (_) => _DeviceSortSheet(
      field: field,
      dir: dir,
      subtitle: subtitle,
    ),
  );
}

class _DeviceSortSheet extends StatefulWidget {
  const _DeviceSortSheet({
    required this.field,
    required this.dir,
    required this.subtitle,
  });

  final DeviceSortField field;
  final SortDir dir;
  final String subtitle;

  @override
  State<_DeviceSortSheet> createState() => _DeviceSortSheetState();
}

class _DeviceSortSheetState extends State<_DeviceSortSheet> {
  late DeviceSortField _field = widget.field;
  late SortDir _dir = widget.dir;

  /// ماذا يعني «تصاعديّ» لهذا المعيار بالضبط.
  ///
  /// «تصاعديّ» مجرّدةً لا تقول شيئاً عن حقلٍ اسمه «الحالة». السطر
  /// يُترجمها إلى ما سيراه المستخدم فعلاً.
  String get _hint => switch ((_field, _dir)) {
        (DeviceSortField.health, SortDir.asc) => 'غير المتّصل أوّلاً',
        (DeviceSortField.health, SortDir.desc) => 'السليم أوّلاً',
        (DeviceSortField.name, SortDir.asc) => 'من أ إلى ي',
        (DeviceSortField.name, SortDir.desc) => 'من ي إلى أ',
        (DeviceSortField.ip, SortDir.asc) => 'من الأصغر إلى الأكبر',
        (DeviceSortField.ip, SortDir.desc) => 'من الأكبر إلى الأصغر',
      };

  @override
  Widget build(BuildContext context) {
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.arrowDownUp,
        title: 'ترتيب الأجهزة',
        subtitle: widget.subtitle,
        onClose: () => Navigator.pop(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('حسب', style: AppType.muted()),
          const SizedBox(height: Sp.sm),
          SheetChoiceTiles(
            labels: [for (final f in DeviceSortField.values) f.label],
            icons: [for (final f in DeviceSortField.values) f.icon],
            selectedIndex: DeviceSortField.values.indexOf(_field),
            onSelect: (i) =>
                setState(() => _field = DeviceSortField.values[i]),
          ),
          const SizedBox(height: Sp.lg),
          Text('الاتّجاه', style: AppType.muted()),
          const SizedBox(height: Sp.sm),
          SheetChoiceTiles(
            labels: ['sort.asc'.tr(), 'sort.desc'.tr()],
            icons: const [LucideIcons.arrowUp, LucideIcons.arrowDown],
            selectedIndex: _dir == SortDir.asc ? 0 : 1,
            onSelect: (i) =>
                setState(() => _dir = i == 0 ? SortDir.asc : SortDir.desc),
          ),
          const SizedBox(height: Sp.md),
          Text(_hint, style: AppType.muted(color: AppColors.brandAccent)),
        ],
      ),
      footer: SheetFooterBar(
        label: 'تطبيق',
        icon: LucideIcons.check,
        onPressed: () => Navigator.pop(context, (field: _field, dir: _dir)),
      ),
    );
  }
}
