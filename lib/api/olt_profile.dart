import 'package:flutter/foundation.dart';

import '../models/network_device.dart';

/// مَن صنع هذا الـOLT — وهو ما يقرّر أيّ جداول المصنّع يجوز أن نسألها.
///
/// اللوحة مشتركة (‏IF-MIB · العدّادات · الواجهة) لكنّ جداول المصنّع ليست
/// كذلك. سؤال BDCOM عن جدول VSOL ‏(`37950`) يُهدر مهلةً في أحسن الأحوال،
/// وفي أسوئها يجمع أعمدة مصنّعٍ آخر فيُعرض أمام مشتركٍ ماكُ غيره.
///
/// `hsgq` (٢٨ أكتوبر): أولت HSGQ EPON وما يحمل برمجيّته بأسماءٍ أخرى — يُعرف بالمؤسّسة `50224` لا بالاسم ([HsgqOlt]).
/// `cdata` (٢٩ أكتوبر): أولت C-Data EPON ‏(«GEPON OLT») — يُعرف بالمؤسّسة `34592` ([CdataOlt]).
enum OltVendor { vsol, bdcom, hsgq, cdata, unknown }

/// ملفّ المصنّع لجهازٍ واحد: من السجلّ أوّلاً، ثمّ من هويّته الحيّة.
///
/// 🐛 ٢٠٢٦-١٠-٢٠ — جهاز المالك مسجّلٌ `brand=vsol` وطرازه
/// «BDCOM P3600-04». فكان يدخل لوحة VSOL ويُعامَل معاملتها، ومنها
/// قراءة `ifPhysAddress` على أنّه ماك المشترك — وهي ثلاثة عناوين فقط
/// تتكرّر على ٨٦ ONU.
///
/// القاعدة: **الهويّة الحيّة تحكم** (‏`sysObjectID` و`sysDescr`)،
/// والسجلّ تلميحٌ لما قبلها. والمصنّع وحده لا يكفي لعدّه OLT — سويتش
/// BDCOM العاديّ يحمل المؤسّسة `3320` نفسها؛ فقدرة PON تُثبتها منافذ
/// `EPON0/x` في IF-MIB لا رقم المؤسّسة.
@immutable
class OltProfile {
  const OltProfile({
    this.vendor = OltVendor.unknown,
    this.model,
    this.identified = false,
    this.oltLikely = false,
  });

  static const unknown = OltProfile();

  final OltVendor vendor;

  /// رمز الطراز كما يُبلّغه الجهاز أو السجلّ: `P3600-04` · `V1600G0B`.
  final String? model;

  /// هل جاء [vendor] من هويّة الجهاز الحيّة لا من السجلّ؟
  final bool identified;

  /// السجلّ أو الطراز يقول إنّه OLT — العلامة نفسها، أو رمز طرازٍ لأولت.
  final bool oltLikely;

  /// جداول VSOL ‏(`1.3.6.1.4.1.37950`) — لـVSOL وحدها.
  bool get readsVsolTables => vendor == OltVendor.vsol;

  /// جداول BDCOM ‏`NMS-EPON-*` — مثبتة على EPON وحده. BDCOM GPON لم
  /// يُختبر حيّاً، فلا تُعمَّم عليه أعمدة `101.10`.
  bool get readsBdcomEponTables => vendor == OltVendor.bdcom;

  /// جداول HSGQ ‏(`1.3.6.1.4.1.50224`) — بالـGET وحده على فهارس محسوبة ([HsgqOlt]): المسح يُعلّق وكيلها.
  bool get readsHsgqTables => vendor == OltVendor.hsgq;

  /// جداول C-Data ‏(`1.3.6.1.4.1.34592`) — بالـGET وحده على فهارس محسوبة ([CdataOlt]).
  bool get readsCdataTables => vendor == OltVendor.cdata;

  /// أولتٌ تُقرأ الـONU فيه من جدول المصنّع **بالـGET وحده** على فهارس نحسبها (HSGQ · C-Data — [OltGetTables]): لا صفوف
  /// ONU في IF-MIB يُعتمد عليها، فلا ifLastChange ولا ifOperStatus لها ولا ifAlias.
  bool get readsGetTables => vendor == OltVendor.hsgq || vendor == OltVendor.cdata;

  /// `ifPhysAddress` على BDCOM عنوانُ واجهةٍ مشترك (٣ عناوين لـ٨٦ ONU)،
  /// فقراءته هناك عمودٌ مدفوعٌ بلا فائدة. وعلى HSGQ صفوف الـONU في IF-MIB
  /// كلّها لا يُعتمد عليها (أسماءٌ قديمة، وصفوفٌ لمفصولة) — هويّتها من جدول المصنّع.
  bool get readsInterfaceMac => vendor != OltVendor.bdcom && !readsGetTables;

  /// هل لكلّ ONU عدّادات ترفك في IF-MIB؟ HSGQ يُرجعها أصفاراً (‏١٦ من ١٦ حيّاً، ٢٨ أكتوبر) — وصفرٌ بقي صفراً
  /// يُحسب «0 bps» فيُرى مشتركٌ يتصفّح خاملاً. فلا ترفك لكلّ مشترك هناك، وترفك منافذ PON يبقى. وC-Data بلا صفوف ONU في
  /// IF-MIB أصلاً (ثمانية منافذ فقط، ٢٩ أكتوبر).
  bool get hasOnuCounters => !readsGetTables;

  /// أجهزة المشترك خلف الـONU (جدول الجسر/جدول VSOL). HSGQ بلا BRIDGE-MIB ولا Q-BRIDGE (يقفز السؤال إلى ifXTable)،
  /// فلا يُسأل أصلاً.
  bool get readsBridgeFdb => vendor == OltVendor.vsol || vendor == OltVendor.bdcom;

  /// كم يُحدّث الجهاز عدّادات منافذه — `null` = لحظيّاً. HSGQ كلّ ~٣١ ثانية (خمسون قراءةً بفاصل ثانية، ٢٨ أكتوبر):
  /// بينهما تُرجع القيمة نفسها، فالفرق صفرٌ هناك «لم يُحدَّث» لا «لم يمرّ شيء»، ونبضة ثلاث ثوانٍ تقسم نصف دقيقةٍ من
  /// الترفك على ثلاث ثوانٍ (عشرة أضعاف). فالمعدّل بين قيمتين مختلفتين وحدهما ([VsolTraffic.portsMoved]).
  /// وC-Data كلّ ~٤ ثوانٍ (قراءةٌ كلّ ثانيةٍ ١٢ مرّة، ٢٩ أكتوبر) — أطول من نبضة اللوحة، فالقاعدة نفسها.
  Duration? get countersRefresh => switch (vendor) {
        OltVendor.hsgq => const Duration(seconds: 31),
        OltVendor.cdata => const Duration(seconds: 4),
        _ => null,
      };

  String get label => switch (vendor) {
        OltVendor.bdcom => 'BDCOM OLT',
        OltVendor.vsol => 'VSOL OLT',
        OltVendor.hsgq => 'HSGQ OLT',
        OltVendor.cdata => 'C-Data OLT',
        OltVendor.unknown => 'OLT',
      };

  @override
  bool operator ==(Object other) =>
      other is OltProfile &&
      other.vendor == vendor &&
      other.model == model &&
      other.identified == identified &&
      other.oltLikely == oltLikely;

  @override
  int get hashCode => Object.hash(vendor, model, identified, oltLikely);

  @override
  String toString() =>
      'OltProfile(${vendor.name}, $model${identified ? ', live' : ''})';

  // ═══════════════════════════════════════════════════════════
  // التصنيف
  // ═══════════════════════════════════════════════════════════

  static const bdcomEnterprise = '1.3.6.1.4.1.3320.';
  static const vsolEnterprise = '1.3.6.1.4.1.37950.';

  /// Shenzhen HS Fiber Communication (HSGQ) في سجلّ IANA — وأولت المالك يُبلّغ `…50224.3.1.1`. وصفُه «EPON OLT»
  /// وحده عامٌّ لا يُعرف به، فالمؤسّسة هي البصمة: تبقى مع البرمجيّة مهما تبدّل الاسم على الجهاز.
  static const hsgqEnterprise = '1.3.6.1.4.1.50224.';

  /// «HSGQ» كلمةً لا جزءاً من كلمة — في طرازٍ كتبه المشغّل أو كشفه [ModelDetector] («HSGQ OLT»).
  static final _hsgqWord = RegExp(r'(^|[^a-z0-9])hsgq([^a-z]|$)', caseSensitive: false);

  /// Shenzhen C-Data Technology في سجلّ IANA — وأولت المالك يُبلّغ `sysObjectID` = ‏`…34592` نفسه بلا ذيل، ووصفه
  /// «GEPON OLT» عامّ. فالمطابقة بالمؤسّسة: الرقم كما هو أو ما تحته ([isCdataObjectId]).
  static const cdataEnterprise = '1.3.6.1.4.1.34592';

  static bool isCdataObjectId(String? oid) {
    final o = oid?.trim() ?? '';
    return o == cdataEnterprise || o.startsWith('$cdataEnterprise.');
  }

  /// «C-Data» / «CDATA» كلمةً، أو رمز سلسلتها EPON ‏(`FD1104S` · `FD1108SN` · `FD1216S`) — في طرازٍ كتبه المشغّل أو
  /// كشفه [ModelDetector] («C-Data OLT»).
  static final _cdataText =
      RegExp(r'(^|[^a-z0-9])(c-?data|fd1[0-9]{3}[a-z0-9-]*)([^a-z0-9]|$)', caseSensitive: false);

  /// «BDCOM» كلمةً لا جزءاً من كلمة: `BDCOM(tm)` · `bdcom p3600` ·
  /// `BDCOM-P3600-04`.
  static final _bdcomWord =
      RegExp(r'(^|[^a-z0-9])bdcom([^a-z]|$)', caseSensitive: false);

  /// مطابقةٌ ضيّقةٌ عمداً كما كانت `_isVsolOlt`: «olt» وحدها تلتقط أسماءً
  /// كثيرةً لا تخصّنا، فنشترط اسم المصنّع أو رمز السلسلة.
  static final _vsolText = RegExp(r'v-?sol|v16\d\d', caseSensitive: false);
  static final _vsolLiveModel = RegExp(
      r'\b(V(?:16\d\d|3600|5600)[A-Z0-9-]*)',
      caseSensitive: false);

  /// الطراز بعد كلمة BDCOM: «BDCOM(tm) P3600-04 Software…» ← `P3600-04`.
  static final _bdcomModel = RegExp(
      r'bdcom(?:\s*\(tm\))?[\s:_-]*([a-z0-9]+(?:-[a-z0-9]+)*)',
      caseSensitive: false);

  /// أولتيات BDCOM: ‏EPON ‏`P3310C · P3600-04 · P3608-2TE`، وGPON
  /// ‏`GP3600-08`.
  static final _bdcomOltModel = RegExp(r'^G?P\d{4}', caseSensitive: false);

  /// سويتشات BDCOM ‏(`S2528-B` · `S3740`…): العلامة نفسها والمؤسّسة
  /// `3320` نفسها، ولا PON فيها.
  static final _bdcomSwitchModel = RegExp(r'^S\d{4}', caseSensitive: false);

  /// علاماتٌ لها لوحاتها — اسمٌ يحوي «vsol» على ميكروتك لا يجعله أولت.
  static const _ownBrands = {
    'mikrotik',
    'ubnt',
    'mimosa',
    'cisco',
    'ruijie',
    'bdcom',
    'hsgq',
    'cdata',
  };

  static bool hasBdcomIdentity(String? text) =>
      text != null && _bdcomWord.hasMatch(text);

  static bool hasHsgqIdentity(String? text) =>
      text != null && _hsgqWord.hasMatch(text);

  static bool hasCdataIdentity(String? text) =>
      text != null && _cdataText.hasMatch(text);

  static bool hasVsolIdentity(String? text) =>
      text != null && _vsolText.hasMatch(text);

  /// رمز طراز BDCOM من نصٍّ حرّ، أو `null`.
  static String? bdcomModelFrom(String? text) {
    if (text == null) return null;
    final m = _bdcomModel.firstMatch(text);
    final token = m?.group(1);
    if (token == null || !RegExp(r'\d').hasMatch(token)) return null;
    return token.toUpperCase();
  }

  static bool isBdcomOltModel(String? token) =>
      token != null && _bdcomOltModel.hasMatch(token.trim());

  static bool isBdcomSwitchModel(String? token) =>
      token != null && _bdcomSwitchModel.hasMatch(token.trim());

  /// أوّل كلمةٍ تجمع حرفاً ورقماً — طرازٌ كتبه المشغّل بلا اسم المصنّع.
  static String? _firstModelToken(String? s) {
    if (s == null) return null;
    for (final w in s.split(RegExp(r'[\s,;()]+'))) {
      final t = w.trim();
      if (t.length < 2 || t.length > 24) continue;
      if (RegExp(r'\d').hasMatch(t) && RegExp(r'[A-Za-z]').hasMatch(t)) {
        return t.toUpperCase();
      }
    }
    return null;
  }

  /// من السجلّ المخزَّن وحده — قبل أيّ قراءةٍ من الجهاز.
  ///
  /// ⚠️ **توافق السجلّات القديمة**: الخادم لم يكن يقبل علامة `bdcom`،
  /// فسُجّلت أولتيات BDCOM ‏`vsol` أو `other` وطرازها يقول BDCOM. اسم
  /// المصنّع الصريح في الطراز يغلب العلامة المخزَّنة خطأً.
  static OltProfile fromRecord({
    required String brand,
    String? model,
    String? name,
  }) {
    final b = brand.toLowerCase().trim();
    final text = '${model ?? ''} ${name ?? ''}';
    if (b == 'bdcom' ||
        ((b == 'vsol' || b == 'other') && hasBdcomIdentity(text))) {
      final token =
          bdcomModelFrom(model) ?? bdcomModelFrom(name) ?? _firstModelToken(model);
      return OltProfile(
        vendor: OltVendor.bdcom,
        model: token,
        // ⚠️ النفي لا الإثبات: حقل الطراز حرٌّ («برج 3 OLT» · «Main-2»)،
        // فاشتراط رمز أولتٍ صريح كان سيُخفي اللوحة عن أولتٍ حقيقيّ كُتب
        // طرازه بكلماتٍ أخرى. نستبعد سويتش BDCOM المعروف وحده، ونترك
        // ما سواه لقدرة PON الحيّة تحكم فيه (منافذ `EPON0/x` في IF-MIB).
        oltLikely: !isBdcomSwitchModel(token),
      );
    }
    // HSGQ: العلامة، أو «HSGQ» في طراز سجلٍّ علامته `vsol`/`other` — الخادم لم يكن يقبل `hsgq`، والوكيل يختار أقرب
    // علامة. والهويّة الحيّة (المؤسّسة 50224) تحكم بعدها أيّاً كان المكتوب.
    if (b == 'hsgq' || ((b == 'vsol' || b == 'other') && hasHsgqIdentity(text))) {
      return OltProfile(
        vendor: OltVendor.hsgq,
        model: _firstModelToken(model),
        oltLikely: true,
      );
    }
    // C-Data: العلامة، أو «C-Data»/رمز FD في طراز سجلٍّ علامته `vsol`/`other` — والمؤسّسة 34592 تحكم بعدها.
    if (b == 'cdata' || ((b == 'vsol' || b == 'other') && hasCdataIdentity(text))) {
      return OltProfile(
        vendor: OltVendor.cdata,
        model: _firstModelToken(model),
        oltLikely: true,
      );
    }
    // كما كانت `_isVsolOlt`: العلامة، أو الاسم/الطراز لما لا علامة له
    // تخصّه (أجهزةٌ سُجّلت `other` قبل أن يقبل الخادم `vsol`).
    if (b == 'vsol' || (!_ownBrands.contains(b) && hasVsolIdentity(text))) {
      return OltProfile(
        vendor: OltVendor.vsol,
        model: _firstModelToken(model),
        oltLikely: true,
      );
    }
    return OltProfile.unknown;
  }

  /// يُكمل [hint] بهويّة الجهاز الحيّة. الهويّة الحاسمة تغلب السجلّ؛
  /// والغامضة تُبقيه كما هو.
  static OltProfile resolve(
    OltProfile hint, {
    String? sysObjectId,
    String? sysDescr,
  }) {
    final oid = sysObjectId?.trim() ?? '';
    final descr = sysDescr ?? '';
    OltVendor? live;
    if (oid.startsWith(bdcomEnterprise) || hasBdcomIdentity(descr)) {
      live = OltVendor.bdcom;
    } else if (oid.startsWith(hsgqEnterprise) || hasHsgqIdentity(descr)) {
      live = OltVendor.hsgq;
    } else if (isCdataObjectId(oid) || hasCdataIdentity(descr)) {
      live = OltVendor.cdata;
    } else if (oid.startsWith(vsolEnterprise) ||
        hasVsolIdentity(descr) ||
        _vsolLiveModel.hasMatch(descr)) {
      live = OltVendor.vsol;
    }
    if (live == null) return hint;
    final model = switch (live) {
      OltVendor.bdcom => bdcomModelFrom(descr) ??
          (hint.vendor == OltVendor.bdcom ? hint.model : null),
      // وصف HSGQ بلا طراز («EPON OLT») — طراز السجلّ إن كان سجلّ HSGQ أصلاً، لا طراز VSOL كُتب خطأً.
      OltVendor.hsgq => hint.vendor == OltVendor.hsgq ? hint.model : null,
      // C-Data كذلك: «GEPON OLT» بلا طراز.
      OltVendor.cdata => hint.vendor == OltVendor.cdata ? hint.model : null,
      _ => _vsolLiveModel.firstMatch(descr)?.group(1)?.toUpperCase() ??
          (hint.vendor == OltVendor.vsol ? hint.model : null),
    };
    return OltProfile(
      vendor: live,
      model: model,
      identified: true,
      // HSGQ: القارئ يُثبت أنّه أولت بعدد منافذ PON في جدوله ([HsgqOlt.fetchStats]) — وإلّا يقولها صراحةً.
      oltLikely: live == OltVendor.vsol ||
          live == OltVendor.hsgq ||
          live == OltVendor.cdata ||
          isBdcomOltModel(model) ||
          (hint.oltLikely && !isBdcomSwitchModel(model)),
    );
  }

  /// من سجلّ الجهاز — اختصارٌ لـ[fromRecord].
  static OltProfile fromDevice(NetworkDevice d) =>
      fromRecord(brand: d.brand, model: d.model, name: d.name);

  /// هل تُفتح لوحة الـOLT لهذا السجلّ؟ مصنّعٌ نعرف جداوله، وطرازٌ لا
  /// ينفي أنّه أولت. والحكم الأخير لمنافذ PON في المسحة الحيّة.
  bool get opensOltPanel => vendor != OltVendor.unknown && oltLikely;

  /// ملفّ VSOL افتراضيّ — لقراءاتٍ لا هويّة معها (اختبارات المحلّل).
  static const vsolDefault =
      OltProfile(vendor: OltVendor.vsol, oltLikely: true);

  // ═══════════════════════════════════════════════════════════
  // مواصفات الكتالوج — منفصلةٌ عن قراءات الجهاز
  // ═══════════════════════════════════════════════════════════

  /// مواصفات الطراز الأساسيّ من صفحة المصنّع — **ليست قراءةً حيّة**.
  ///
  /// مطابقةٌ تامّة للرمز: `P3600-04-2AC` و`P3600-08E` طُرزٌ أخرى لم تُوثَّق
  /// مواصفاتها هنا، فلا تُستعار لها. ولا رقم RAM تسويقيّ: قراءة الذاكرة
  /// الحيّة شيءٌ آخر ولا يُخلط بها.
  static const Map<String, List<String>> _bdcomSpecs = {
    // ⚠️ علامة LRM ‏(U+200E) بعد كلّ مقطعٍ لاتينيٍّ ينتهي بقوسٍ أو «+»: بلاها
    // يُقلب الرمز المحايد في سطرٍ عربيّ فيُرسم «‎+SFP» و«(RJ45) GE».
    'P3600-04': [
      'EPON · IEEE 802.3ah\u200E',
      '4 منافذ PON',
      '4 منافذ GE (RJ45)\u200E',
      '4 منافذ 10GE/GE (SFP+)\u200E',
      'تركيب rack بارتفاع 1U',
    ],
  };

  List<String>? get catalogSpecs => vendor == OltVendor.bdcom
      ? _bdcomSpecs[model?.trim().toUpperCase()]
      : null;
}
