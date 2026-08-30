import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import 'brand_badge.dart';

/// صورة الجهاز الفعليّة بدل شارة العلامة التجاريّة.
///
/// الأسماء في `assets/devices-images/` غير منتظمة: مسافات و`+`
/// وشرطات وحالات أحرف مختلطة («CCR2116-12G-4S+.webp» · «rocket m5.png»
/// · «LHG 60G.webp»). والموديل الذي يكتبه المدير في النموذج حرّ تماماً.
/// لذلك المطابقة تجري على مفتاح **مُطبَّع**: حروف وأرقام فقط، بلا
/// حالة ولا فواصل.
///
/// ⚠️ الترتيب من الأطول إلى الأقصر مقصود: «CCR2004-16G-2S+PC» يحوي
/// «CCR2004-16G-2S+» كسابقة، فالبحث من الأقصر كان سيلتقط الخطأ ويُظهر
/// صورة جهاز آخر — وهي أسوأ من لا صورة، لأنّها تبدو صحيحة.
class DeviceImage extends StatelessWidget {
  const DeviceImage({
    super.key,
    required this.brand,
    required this.model,
    this.size = 44,
  });

  final String brand;
  final String? model;
  final double size;


  /// الاسم التجاري ← اسم اللوحة.
  ///
  /// ⚠️ ميكروتك تُسمّي الجهاز الواحد باسمين: **اسم لوحة** (RB912UAG-5HPnD-OUT)
  /// و**اسم تجاري** (BaseBox 5). و`board-name` في RouterOS يُرجع أحدهما
  /// بحسب الطراز والإصدار — فالجهاز نفسه قد يُبلّغ باسم لا يُطابق ملفّ
  /// الصورة رغم أنّه هو هو. (أكّده المستخدم: BaseBox 5 = RB912)
  ///
  /// الأسماء هنا مقتصرة على ما يقابل صورةً موجودة فعلاً — لا نُضيف
  /// مرادفاً لطراز لا صورة له، فذلك يُوهم بالتغطية.
  static const Map<String, String> _aliases = {
    // ميكروتك — لاسلكيّات
    'basebox5': 'rb912uag5hpndout',
    'basebox': 'rb912uag5hpndout',
    'sxtsq5ac': 'rbsxtsqg5acd',
    'sxtsqlite5': 'rbsxtsq5nd',
    'sxtsqlite2': 'rbsxtsq2nd',
    'sxtsq5nd': 'rbsxtsq5nd',
    'sxtsq2nd': 'rbsxtsq2nd',
    'sxt5achpsa': 'rbsxtg5hpacdsa',
    // أكّده المستخدم: SXT SA5 = RBSXTG-5HPacD-SA
    'sxtsa5': 'rbsxtg5hpacdsa',
    'sxtsa5ac': 'rbsxtg5hpacdsa',
    'sxtg5hpacdsa': 'rbsxtg5hpacdsa',
    'lhg5': 'rblhg5nd',
    'lhgxl5': 'rblhg5hpndxl',
    'ldf5': 'rbldf5nd',
    'groove52ac': 'rbgroovega52hpacn',
    'groovea52hpn': 'rbgroovea52hpn',
    'groove52hpn': 'rbgroove52hpn',
    'omnitik5poeac': 'rbomnitikpg5hacd',
    'mantbox212s': 'rb911g2hpnd12s',
    'hexpoe': 'rb960pgspb',
    // يوبيكويتي — `platform` في mca-status يُرجع الاسم التجاري.
    //
    // ⚠️ عائلات M2 وM5 تشترك في الهيكل نفسه (أكّده المستخدم: «nano m2,
    // m5 نفس الشكل»)، فتُشير إلى الصورة ذاتها. الفرق نطاق التردّد لا
    // الشكل، والصورة تُعرّف الجهاز بصريّاً لا تُوثّق مواصفاته.
    'nanostationm5': 'nanom52',
    'nanostationm2': 'nanom52',
    'nanostationloco m5': 'nanom52',
    'nanostationlocom5': 'nanom52',
    'nanostationlocom2': 'nanom52',
    'locom5': 'nanom52',
    'locom2': 'nanom52',
    'nano5': 'nanom52',
    'nanom5': 'nanom52',
    'nanom2': 'nanom52',
    'nanobridgem5': 'nanobridgem5',
    'nanobridgem2': 'nanobridgem5',
    'nanobridge': 'nanobridgem5',
    'rocketm2': 'rocketm5',
    'rocket5': 'rocketm5',
    'rocketm5': 'rocketm5',
    'powerbeam': 'powerbeamm5',
    'powerbeam5ac': 'powerbeamm5',
    'powerbeamm2': 'powerbeamm5',
    'pb5ac': 'powerbeamm5',
  };

  /// مفتاح مُطبَّع: حروف وأرقام لاتينيّة فقط.
  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// اسم ملفّ الصورة الموافق للموديل، أو null.
  ///
  /// مكشوفة للاختبار: المطابقة بالسابقة سهلة الانزلاق إلى جهاز مجاور.
  /// بادئات أسماء ملفّات ميكروتك — تُستعمل لبوّابة العلامة.
  static const _mikrotikPrefixes = ['ccr', 'crs', 'css', 'rb', 'l0', 'l1', 'l2'];

  static String? assetFor(String? model, {String? brand}) {
    if (model == null) return null;
    final k = _key(model);
    if (k.isEmpty) return null;
    // المرادف أوّلاً: يُترجم الاسم التجاري إلى اسم اللوحة ثمّ يُطابَق
    // كما لو كُتب اسم اللوحة مباشرةً.
    final k2 = _aliases[k] ?? k;

    // مطابقة تامّة — أدقّ ما يمكن.
    final exact = _byKey[k2];
    if (exact != null) return _gate(exact, brand);
    // ثمّ احتواء: المدير قد يكتب «Mikrotik CCR2116-12G-4S+ router».
    // المفاتيح مرتّبة تنازليّاً بالطول فيفوز الأطول = الأدقّ.
    for (final e in _byKey.entries) {
      if (e.key.length >= 6 && k2.contains(e.key)) return _gate(e.value, brand);
    }
    // وأخيراً: المكتوب سابقةٌ لاسم ملفّ — «912» لـRB912UAG-5HPnD-OUT.
    final partial = <MapEntry<String, String>>[];
    for (final e in _byKey.entries) {
      if (e.key.contains(k2)) partial.add(e);
    }
    if (partial.length == 1 && k2.length >= 3) {
      return _gate(partial.first.value, brand);
    }
    if (partial.length > 1) {
      // ⚠️ التعدّد: عتبتان لا قاعدة واحدة.
      //
      // مفتاح قصير («208» من اسم عربيّ بعد حذف حروفه) لا يميّز جهازاً،
      // وعرض أحد مطابقاته اعتباطاً أسوأ من الشارة — يبدو صحيحاً فيُبنى
      // عليه قرار في الميدان. يبقى مرفوضاً.
      //
      // أمّا المفتاح الطويل فتعدّده لاحقةٌ لا جهاز آخر: «CRS326-24G-2S+»
      // يُطابق نسختَي IN وRM — وهما الجهاز نفسه بتثبيت مختلف. رفضُهما
      // يترك المستخدم بشارة عامّة بينما صورة إحداهما تُعرّفه فوراً.
      // (طلب المستخدم 2026-08-30: «مو لازم 100% الاسم».)
      if (k2.length < 8) return null;
      // اختيار حتميّ لا اعتباطيّ: الأقرب طولاً للمكتوب (أقلّ لاحقة)،
      // ثمّ أبجديّاً — فلا تتبدّل الصورة بين تشغيل وآخر.
      partial.sort((a, b) {
        final c = a.key.length.compareTo(b.key.length);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
      return _gate(partial.first.value, brand);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final file = assetFor(model, brand: brand);
    if (file == null) return BrandBadge(brand: brand, size: size);
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        // سطح فاتح ثابت خلف الصورة: صور المصنّعين على خلفيّة بيضاء
        // شفّافة، وعلى سطح داكن تختفي حوافّها.
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.icon),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Image.asset(
        'assets/devices-images/$file',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // ملفّ مفقود أو تالف لا يُسقط الشاشة — نعود للشارة.
        errorBuilder: (_, __, ___) => BrandBadge(brand: brand, size: size),
      ),
    );
  }

  /// بوّابة العلامة: تمنع صورة طراز من علامة أخرى.
  ///
  /// ⚠️ ليست تجميلاً. فحص قاعدة الإنتاج أظهر أنّ المطابقة بلا هذه
  /// البوّابة تعرض **سويتشات مراكز بيانات على هوائيّات قطاعيّة**:
  /// «سكتر 208» المسجَّل ubnt يُطابق CRS320-8P-8B لأنّ مفتاحه بعد حذف
  /// العربيّة يصير «208». عمود `brand` مملوء 100% في الأسطول بينما
  /// `model` فارغ في 55% — فهو المصدر الأوثق، ونُحكّمه.
  static String? _gate(String file, String? brand) {
    if (brand == null || brand.isEmpty) return file;
    final b = brand.toLowerCase();
    final f = file.toLowerCase();
    final looksMikrotik = _mikrotikPrefixes.any(f.startsWith);
    if (looksMikrotik && b != 'mikrotik') return null;
    if (!looksMikrotik && b == 'mikrotik') return null;
    return file;
  }

  /// كلّ الصور المتاحة، مرتّبة أبجديّاً — للمنتقي اليدوي.
  static List<String> get allAssets {
    final v = _byKey.values.toList()..sort();
    return v;
  }

  /// اسم اللوحة (بلا امتداد) الذي يُطابق ملفّاً — يُكتب في `model` عند
  /// الاختيار اليدوي، فيصير الجهاز مُطابَقاً للأبد بالمسار العادي.
  static String boardNameOf(String file) {
    final i = file.lastIndexOf('.');
    return i > 0 ? file.substring(0, i) : file;
  }

  /// مفتاح مُطبَّع ← اسم الملفّ. مرتّب تنازليّاً بطول المفتاح.
  static const Map<String, String> _byKey = {
  'ubiquitiairfiberaf24hd': 'ubiquiti-airfiber-af24hd.png',
  'rb1100ahx4dudeedition': 'RB1100AHx4 Dude Edition.webp',
  'l23ugsr5haxd2haxdnm': 'L23UGSR-5HaxD2HaxD-NM.webp',
  'ubiquitiairfiber4x': 'ubiquiti-airfiber-4x.png',
  'rbgroovega52hpacn': 'RBGrooveGA-52HPacn.webp',
  'ccr22161g12xs2xq': 'CCR2216-1G-12XS-2XQ.webp',
  'rb912uag5hpndout': 'RB912UAG-5HPnD-OUT.webp',
  'rbomnitikpg5hacd': 'RBOmniTikPG-5HacD.webp',
  'ccr10097g1c1spc': 'CCR1009-7G-1C-1S+PC.webp',
  'ccr20041g12s2xs': 'CCR2004-1G-12S+2XS.webp',
  'crs3101g5s4sout': 'CRS310-1G-5S-4S+OUT.webp',
  'crs3264c20g2qrm': 'CRS326-4C+20G+2Q+RM.webp',
  'crs3284c20s4srm': 'CRS328-4C-20S-4S+RM.webp',
  'crs35448g4s2qrm': 'CRS354-48G-4S+2Q+RM.webp',
  'crs35448p4s2qrm': 'CRS354-48P-4S+2Q+RM.webp',
  'crs51816xs2xqrm': 'CRS518-16XS-2XQ-RM.webp',
  'crs5204xs16xqrm': 'CRS520-4XS-16XQ-RM.webp',
  'ccr103612g4sem': 'CCR1036-12G-4S-EM.webp',
  'ccr200416g2spc': 'CCR2004-16G-2S+PC.webp',
  'crs3101g5s4sin': 'CRS310-1G-5S-4S+IN.webp',
  'crs31816p2sout': 'CRS318-16P-2S+OUT.webp',
  'crs3208p8b4srm': 'CRS320-8P-8B-4S+RM.webp',
  'rb911g2hpnd12s': 'RB911G-2HPnD-12S.webp',
  'rbgroovea52hpn': 'RBGrooveA-52HPn.webp',
  'rbsxtg5hpacdsa': 'RBSXTG-5HPacD-SA.webp',
  'ccr10097g1c1s': 'CCR1009-7G-1C-1S+.webp',
  'ccr10368g2sem': 'CCR1036-8G-2S+EM.webp',
  'crs3124c8xgrm': 'CRS312-4C+8XG-RM.webp',
  'crs3171g16srm': 'CRS317-1G-16S+RM.webp',
  'crs32624g2sin': 'CRS326-24G-2S+IN.webp',
  'crs32624g2srm': 'CRS326-24G-2S+RM.webp',
  'crs32624s2qrm': 'CRS326-24S+2Q+RM.webp',
  'crs32824p4srm': 'CRS328-24P-4S+RM.webp',
  'css31816g2sin': 'CSS318-16G-2S+IN.webp',
  'css32624g2srm': 'CSS326-24G-2S+RM.webp',
  'rbgroove52hpn': 'RBGroove52HPn.webp',
  'airfiber5af5': 'AirFIBER 5 af-5.png',
  'ccr101612s1s': 'CCR1016-12S-1S+.webp',
  'ccr103612g4s': 'CCR1036-12G-4S.webp',
  'ccr200416g2s': 'CCR2004-16G-2S+.webp',
  'ccr211612g4s': 'CCR2116-12G-4S+.webp',
  'crs3091g8sin': 'CRS309-1G-8S+IN.webp',
  'crs3108g2sin': 'CRS310-8G+2S+IN.webp',
  'l11ug5haxdnb': 'L11UG-5HaxD-NB.webp',
  'nanobridgem5': 'nanobridge m5.png',
  'rb5009uprsin': 'RB5009UPr+S+IN.webp',
  'rblhg5hpndxl': 'RBLHG-5HPnD-XL.webp',
  'rbsxtsqg5acd': 'RBSXTsqG-5acD.png',
  'c5cptmphero': 'c5c-ptmp-hero.png',
  'ccr10368g2s': 'CCR1036-8G-2S+.webp',
  'powerbeamm5': 'powerbeam M5.webp',
  'rb4011igsrm': 'RB4011iGS+RM.webp',
  'rb5009ugsin': 'RB5009UG+S+IN.webp',
  '5xairfiber': '5x airfiber.png',
  'ccr101612g': 'CCR1016-12G.webp',
  'l009uigsrm': 'L009UiGS-RM.webp',
  'rb1100ahx4': 'RB1100AHx4.webp',
  'rb960pgspb': 'RB960PGS-PB.webp',
  'rbsxtsq2nd': 'RBSXTsq2nD.webp',
  'rbsxtsq5nd': 'RBSXTsq5nD.webp',
  'lhg5axdxl': 'LHG-5axD-XL.webp',
  'rbldf5nd': 'RBLDF-5nD.webp',
  'rblhg5nd': 'RBLHG-5nD.webp',
  'rocketm5': 'rocket m5.png',
  'lhg5axd': 'LHG-5axD.webp',
  'nanom52': 'nano m5-2.png',
  'lhg60g': 'LHG 60G.webp',
  };
}
