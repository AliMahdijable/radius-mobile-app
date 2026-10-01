import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// طبقة قراءةٍ لـ**OLT من VSOL** (سلسلة V1600D) عبر SNMP v2c.
///
/// **لماذا SNMP وحده هنا؟**
/// لأنّ الجهاز يكشف **كلّ ONU كواجهةٍ مستقلّة** في `IF-MIB`:
///
/// ```
///   GE0/1 … GE0/8        منافذ الصعود
///   EPON0/1 … EPON0/4    منافذ PON بعدّاداتها الإجماليّة
///   EPON0/3:2            ← ONU رقم ٢ على منفذ PON الثالث
/// ```
///
/// فمسحةٌ واحدة تعطي حالة كلّ المشتركين وسرعتهم وعناوينهم وترفكهم —
/// وهذا أسرع بكثيرٍ من جلسة Telnet لكلّ جهاز.
///
/// **وما لا يعطيه SNMP على هذا الجهاز** — فحصتُه على جهازٍ فعليّ
/// ٢٠٢٦-٠٩-٢٨، ولم أستنتجه من توثيق:
///   • القدرة الضوئيّة والحرارة والجهد (`show onu N ctc opm_diag`)
///   • المصنّع والطراز وإصدار البرنامج (`show onu baisc-info all`)
///   • المسافة (`show onu N rtt`)
///
/// وMIB المؤسّسة (‏`.1.3.6.1.4.1.2162`) شبه فارغ: جدول الـcommunity
/// وحده. وفحصتُ `ENTITY-SENSOR` و`ENTITY-MIB` و`OPTIF` فكلّها غائبة.
/// فمن أراد القدرة الضوئيّة فطريقه Telnet لا غير — وتلك مرحلةٌ ثانية
/// تُستدعى عند فتح ONU بعينه لا في النبضة الدوريّة.
class VsolOltApi {
  VsolOltApi._();

  static const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
  static const String _oidSysName = '1.3.6.1.2.1.1.5.0';
  static const String _oidSysUpTime = '1.3.6.1.2.1.1.3.0';

  static const String _oidIfDescr = '1.3.6.1.2.1.2.2.1.2';

  /// البديل حين تكون `ifDescr` فارغة — انظر `_readIfTable`.
  static const String _oidIfName = '1.3.6.1.2.1.31.1.1.1.1';
  static const String _oidIfOper = '1.3.6.1.2.1.2.2.1.8';
  static const String _oidIfPhys = '1.3.6.1.2.1.2.2.1.6';
  static const String _oidIfHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
  static const String _oidIfHCIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const String _oidIfHCOut = '1.3.6.1.2.1.31.1.1.1.10';

  /// كم قيمةً نطلب في حزمة GETBULK الواحدة.
  ///
  /// ⚡ قياسٌ على `Popq3-olt` ‏(٣٢٧ واجهة · ping ٢٧ مللي):
  ///
  ///   chunk= 25 →  6353 مللي
  ///   chunk= 50 →  3150 مللي   ← الأسرع
  ///   chunk= 80 →  3730 مللي
  ///   chunk=120 →  5557 مللي
  ///
  /// خمسون تُنصّف الزمن. وما فوقها يسوء لأنّ الردّ يتجاوز MTU فيتجزّأ،
  /// وضياع جزءٍ واحد يُسقط الحزمة كلّها فتُعاد.
  static const _bulkSize = 50;

  /// أجهزةٌ ثبت أنّها بلا عدّادات ٦٤ بت.
  ///
  /// ⚡ العمود الغائب لا يُرفَض بل **يُهمَل الطلب**، فندفع مهلة خمس
  /// ثوانٍ في كلّ مسحة. والدرس يُشترى مرّةً واحدة.
  static final Set<String> _narrowHosts = <String>{};

  /// بديلا العدّادين حين تغيب نسخة ٦٤ بت — انظر `_readIfTable`.
  static const String _oidIfIn32 = '1.3.6.1.2.1.2.2.1.10';
  static const String _oidIfOut32 = '1.3.6.1.2.1.2.2.1.16';

  /// لقطةٌ كاملة. يرمي [VsolException] حين يتعذّر الاتّصال.
  /// [structureOnly] — أسماءٌ وحالةٌ فقط، بلا عدّادات ولا عناوين.
  /// ستّ ثوانٍ بدل أربعٍ وثلاثين على أولتٍ فيه ٣٢٧ واجهة.
  static Future<VsolOltStats> fetchStats({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 5),
    bool structureOnly = false,
    bool withCounters = true,
    void Function(VsolOltStats partial)? onPartialReady,
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    String? descr, name;
    Duration? uptime;
    try {
      for (final vb
          in await snmp.get([_oidSysDescr, _oidSysName, _oidSysUpTime])) {
        if (vb.oid == _oidSysDescr) descr = vb.asString;
        if (vb.oid == _oidSysName) name = vb.asString;
        if (vb.oid == _oidSysUpTime) {
          final t = vb.asInt;
          if (t > 0) uptime = Duration(milliseconds: t * 10);
        }
      }
      // ⚡ الهويّة أوّلاً: اللوحة تعرض الطراز ومدّة التشغيل بلا انتظار
      // مسح الواجهات، وهو الجزء الثقيل (‏٣٨ واجهة × ستّة أعمدة).
      onPartialReady?.call(VsolOltStats(
        sysDescr: descr,
        sysName: name,
        uptime: uptime,
      ));
    } on SnmpException catch (e) {
      throw VsolException('تعذّر الاتّصال بالـOLT عبر SNMP: $e\n'
          'تحقّق:\n'
          '• الـcommunity "$community" صحيحة\n'
          '• المنفذ $port مفتوح (UDP)\n'
          '• SNMP مفعّل على الجهاز');
    }

    // ⚡ **مرحلتان لا واحدة.** الأسماء والحالة تصل في ~١٠ ثوانٍ،
    // والعدّادات تأخذ ١٥ أخرى. وعدد المشتركين ومنافذ PON لا يحتاج
    // العدّادات أصلاً — فننشرها فور وصولها بدل حبس اللوحة ثلاثين
    // ثانيةً على «٠/٠».
    //
    // (بلاغ المستخدم ٢٠٢٦-١٠-٠١: «يصير تأخير بعرض البيانات… يعني
    // ١٥ ثانية تقريباً»)
    final scan =
        await _readIfTable(snmp, structureOnly: structureOnly, onNames: (rows) {
      final early = VsolParse.build(rows);
      onPartialReady?.call(VsolOltStats(
        sysDescr: descr,
        sysName: name,
        uptime: uptime,
        uplinks: early.uplinks,
        ponPorts: early.ponPorts,
        onus: early.onus,
      ));
    });
    final parsed = VsolParse.build(scan.rows);

    // ⚠️ **مشتركون بلا منافذَ تحملهم = قراءةٌ ناقصة، لا جهازٌ غريب.**
    //
    // 🐛 ٢٠٢٦-١٠-٠١ — ظهرت متقطّعةً في لقطات المستخدم وفي المحاكاة:
    // «PON 0 · ONU 301 · صعود 0». و`walk` يتوقّف صامتاً إن ضاعت حزمة،
    // فيُرجع ذيل الجدول بلا رأسه — والمنافذ والصعود في أوّل أربعٍ
    // وعشرين فهرساً.
    //
    // وكنتُ أقبل الناقص كأنّه كامل: فتُعرَض «٠/٠»، وتُحفَظ في المخزن،
    // وتُبنى عليها الطبقة السريعة التي تسأل عن فهارس لا تعرفها —
    // فيتجمّد كلّ شيء على أصفار.
    //
    // كلّ ONU على هذه الأجهزة يجلس على منفذ PON، فغيابُ المنافذ مع
    // وجود المشتركين تناقضٌ لا يحتمل تأويلاً.
    if (parsed.onus.isNotEmpty && parsed.ponPorts.isEmpty) {
      throw VsolException(
          'قراءةٌ ناقصة: ${parsed.onus.length} مشتركاً بلا منافذ PON — '
          'لم يُجب الجهاز بالجدول كاملاً');
    }

    if (kDebugMode) {
      debugPrint('══════ VSOL OLT ══════');
      debugPrint('  ${descr ?? "?"} / ${name ?? "?"} · ${uptime?.inDays}d');
      debugPrint('  uplinks ${parsed.uplinks.length} · '
          'pon ${parsed.ponPorts.length} · onu ${parsed.onus.length} '
          '(${parsed.onusOnline} متّصل)');
      debugPrint('══════════════════════');
    }

    return VsolOltStats(
      sysDescr: descr,
      sysName: name,
      uptime: uptime,
      uplinks: parsed.uplinks,
      ponPorts: parsed.ponPorts,
      onus: parsed.onus,
      narrowCounters: scan.narrowCounters,
      rxAt: scan.rxAt,
      txAt: scan.txAt,
    );
  }

  /// تحديثٌ خفيف: عمودا العدّاد وحدهما على بنيةٍ معروفة سلفاً.
  ///
  /// ⚡ **عشر ثوانٍ بدل إحدى وثلاثين.** المسح الكامل ستّة أعمدة، خمسةٌ
  /// منها تصف بنيةً لا تتغيّر كلّ دقيقة (أسماء · حالة · عناوين ·
  /// سرعات). والمعدّل لا يحتاج إلّا العدّادين.
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «ظهر هسه بس تأخّر هواي». أوّل معدّلٍ
  /// كان ينتظر مسحتين كاملتين — ‏٤٧ ثانية فاصلاً و٣١ مسحاً — فنحو
  /// ثمانين ثانيةً قبل أوّل رقم. والخفيفة تُنزلها إلى نحو العشرين.
  ///
  /// ⚠️ ولا تُغني عن الكاملة: حالة المشترك (متّصل/مفصول) وظهور مشتركٍ
  /// جديد لا يأتيان من العدّادين. فاللوحة تُناوب بينهما.
  static Future<VsolOltStats> refreshCounters({
    required String host,
    int port = 161,
    required String community,
    required VsolOltStats previous,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    Future<List<Varbind>> safeWalk(String base) async {
      try {
        return await snmp.walk(base, chunkSize: _bulkSize);
      } catch (_) {
        return const [];
      }
    }

    Future<Map<int, int>> col(String wide, String narrow) async {
      // نبدأ من حيث انتهت المسحة الكاملة: إن كانت ضيّقةً فلا نُعيد
      // شراء مهلة الخمس ثوانٍ على عمودٍ نعرف أنّه غائب.
      final known = previous.narrowCounters || _narrowHosts.contains(host);
      var vbs = known ? const <Varbind>[] : await safeWalk(wide);
      var base = wide;
      // والقاعدة نفسها هنا: أصفارٌ كلّها = عمودٌ غائب.
      if (vbs.isEmpty || !vbs.any((v) => v.asInt > 0)) {
        if (!known) _narrowHosts.add(host);
        vbs = await safeWalk(narrow);
        base = narrow;
      }
      final m = <int, int>{};
      for (final vb in vbs) {
        final i = _lastIndex(vb.oid, base);
        if (i != null) m[i] = vb.asInt;
      }
      return m;
    }

    final rx = await col(_oidIfHCIn, _oidIfIn32);
    final rxAt = DateTime.now();
    final tx = await col(_oidIfHCOut, _oidIfOut32);
    final txAt = DateTime.now();
    if (rx.isEmpty && tx.isEmpty) return previous;

    return VsolOltStats(
      sysDescr: previous.sysDescr,
      sysName: previous.sysName,
      uptime: previous.uptime,
      narrowCounters: previous.narrowCounters,
      rxAt: rxAt,
      txAt: txAt,
      uplinks: [
        for (final u in previous.uplinks)
          u.withBytes(rx[u.index] ?? u.rxBytes, tx[u.index] ?? u.txBytes)
      ],
      ponPorts: [
        for (final p in previous.ponPorts)
          p.withBytes(rx[p.index] ?? p.rxBytes, tx[p.index] ?? p.txBytes)
      ],
      onus: [
        for (final o in previous.onus)
          o.withBytes(rx[o.ifIndex] ?? o.rxBytes, tx[o.ifIndex] ?? o.txBytes)
      ],
    );
  }

  /// أسرع تحديث: عدّادات **منافذ PON ومنافذ الصعود وحدها**.
  ///
  /// ⚡ قياسٌ على `Popq3-olt`: ‏٢٤ واجهةً في **١٫١ ثانية**، مقابل ٦ ثوانٍ
  /// لكلّ الـ٣٢٥. والوكيل يعالج ~١٠٠ قيمةً في الثانية مهما سألناه —
  /// جرّبتُ التوازي فلم يُعطِ إلّا ١٩٪ لأنّه يُسلسل داخليّاً. فالرافعة
  /// ليست أن نسأل أسرع بل **أن نسأل أقلّ**.
  ///
  /// والبطاقة العلويّة وصفّ كلّ منفذ PON هي ما يُنظَر إليه أوّلاً، أمّا
  /// الثلاثمئة مشتركٍ فقائمةٌ تُمرَّر. فنُحيي ما يُنظَر إليه ونُبقي
  /// البقيّة على إيقاعٍ أبطأ.
  ///
  /// ⚠️ عدّادات الـONU تُنقَل كما هي — فلا تُحسَب منها معدّلات. اللوحة
  /// تُقارن كلّ طبقةٍ بلقطتها هي.
  static Future<VsolOltStats> refreshHotCounters({
    required String host,
    int port = 161,
    required String community,
    required VsolOltStats previous,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final hot = <int>[
      for (final p in previous.ponPorts) p.index,
      for (final u in previous.uplinks) u.index,
    ];
    if (hot.isEmpty) return previous;

    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );
    Future<Map<int, int>> col(String base) async {
      final out = <int, int>{};
      try {
        // طلبٌ واحد لأربعٍ وعشرين قيمة: أقلّ الرحلات، وحجمٌ دون MTU.
        for (final vb in await snmp.get([for (final i in hot) '$base.$i'])) {
          final i = _lastIndex(vb.oid, base);
          if (i != null && !vb.isAbsent) out[i] = vb.asInt;
        }
      } catch (_) {/* نُبقي القديم بدل أن نُصفّر */}
      return out;
    }

    /// ⚠️ **المعرفة مشتركة، والسقوط هنا لا في المستدعي.**
    ///
    /// 🐛 ٢٠٢٦-١٠-٠١: مسحة البنية لا تقرأ عدّاداتٍ، فلا تتعلّم أنّ
    /// الجهاز بلا ٦٤ بت. وكانت هذه الدالّة تثق بعَلَم اللقطة وحده،
    /// فتسأل عموداً غائباً ويُهمَل طلبُها، فتنتظر المهلة كاملةً ثمّ
    /// ترجع فارغة — عشر ثوانٍ وصفرُ ترفك.
    Future<Map<int, int>> counter(String wideOid, String narrowOid) async {
      if (previous.narrowCounters || _narrowHosts.contains(host)) {
        return col(narrowOid);
      }
      final w = await col(wideOid);
      // ⚠️ **عمودٌ كلّه أصفار ليس قراءةً ناجحة.**
      //
      // 🐛 ٢٠٢٦-١٠-٠١: الجهاز لا يرفض عدّاد ٦٤ بت في طلب GET بل يُرجع
      // أربعاً وعشرين قيمةً صفريّة. فكنتُ أحسبها نجاحاً وأبني عليها،
      // فظهرت اللوحة كلّها «0 bps» — وهي كذبةٌ أهدأ من القفزة لكنّها
      // كذبة. (لقطة المستخدم: «؟؟؟؟؟»)
      //
      // ثماني واجهات نشطةٍ لا تكون أصفاراً كلّها، فهذا دليل الغياب.
      if (w.values.any((v) => v > 0)) return w;
      _narrowHosts.add(host);
      return col(narrowOid);
    }

    final rx = await counter(_oidIfHCIn, _oidIfIn32);
    final rxAt = DateTime.now();
    final tx = await counter(_oidIfHCOut, _oidIfOut32);
    final txAt = DateTime.now();
    if (rx.isEmpty && tx.isEmpty) return previous;

    return VsolOltStats(
      sysDescr: previous.sysDescr,
      sysName: previous.sysName,
      uptime: previous.uptime,
      narrowCounters: previous.narrowCounters || _narrowHosts.contains(host),
      rxAt: rxAt,
      txAt: txAt,
      onus: previous.onus,
      uplinks: [
        for (final u in previous.uplinks)
          u.withBytes(rx[u.index] ?? u.rxBytes, tx[u.index] ?? u.txBytes)
      ],
      ponPorts: [
        for (final p in previous.ponPorts)
          p.withBytes(rx[p.index] ?? p.rxBytes, tx[p.index] ?? p.txBytes)
      ],
    );
  }

  /// يقرأ جدول الواجهات مع تحمّل الأخطاء الجزئيّة.
  ///
  /// ⚠️ المسح يتوقّف عند أوّل `genErr` فيُسقط ما بعده — وهي المصيدة
  /// نفسها التي أفقدتنا ترفك روجي كلّه. فحين يرجع عمودٌ فارغاً نسأل
  /// كلّ فهرسٍ وحده ونتجاوز من يفشل.
  static Future<
      ({
        List<VsolIfRow> rows,
        bool narrowCounters,
        DateTime? rxAt,
        DateTime? txAt
      })> _readIfTable(
    SnmpV2c snmp, {
    void Function(List<VsolIfRow> rows)? onNames,
    bool structureOnly = false,
    bool withCounters = true,
  }) async {
    Future<List<Varbind>> safeWalk(String base) async {
      try {
        return await snmp.walk(base, chunkSize: _bulkSize);
      } catch (_) {
        return const [];
      }
    }

    // ── الأسماء: `ifName` أوّلاً ─────────────────────────────────
    //
    // 🐛 ٢٠٢٦-١٠-٠١ — فيرموير V1600D الثاني يُرجع `ifDescr` **فارغةً
    // لكلّ الواجهات الـ٣٢٧**، ويضع الأسماء في `ifName` من `ifXTable`.
    //
    // ⚡ وكان الترتيب معكوساً: نمسح `ifDescr` كاملاً (‏٣٢٧ سطراً من
    // الفراغ · ~٥ ثوانٍ) ثمّ نمسح `ifName`. فالعمود الفارغ يُدفَع ثمنه
    // في **كلّ** مسحة قبل أن تبدأ.
    //
    // `ifName` هو القياسيّ في `ifXTable` والمأهول على الجهازين، فهو
    // الأصل. و`ifDescr` احتياطٌ لا يُقرأ إلّا إن خاب الأوّل.
    //
    // (بلاغ المستخدم ٢٠٢٦-١٠-٠١: «شوف بنفسك التأخير شكد فضيع»)
    final byIdx = <int, String>{};
    for (final vb in await safeWalk(_oidIfName)) {
      final i = _lastIndex(vb.oid, _oidIfName);
      final n = vb.asString.trim();
      if (i != null && n.isNotEmpty) byIdx[i] = n;
    }
    if (byIdx.isEmpty) {
      for (final vb in await safeWalk(_oidIfDescr)) {
        final i = _lastIndex(vb.oid, _oidIfDescr);
        final n = vb.asString.trim();
        if (i != null && n.isNotEmpty) byIdx[i] = n;
      }
    }
    // ⚠️ **بنيةٌ فارغة ليست نتيجة — بل فشل.**
    //
    // 🐛 ٢٠٢٦-١٠-٠١: حين يسقط مسح الأسماء بمهلةٍ (والجهاز يسقط كثيراً
    // تحت الضغط) كنتُ أُرجع قائمةً فارغةً بصمت. فتُمحى اللوحة إلى
    // «٠/٠»، وتُحفَظ الفراغة في المخزن، وتُبنى عليها الطبقة السريعة.
    // (لقطة المستخدم: ثمانية منافذ كلّها `0 bps`)
    //
    // والرمي هنا يُبقي آخر قراءةٍ صحيحةٍ معروضةً — وهو الصواب: بيانٌ
    // قديمٌ معلومُ القِدَم خيرٌ من فراغٍ يُقرأ حقيقة.
    if (byIdx.isEmpty) {
      throw VsolException('تعذّرت قراءة جدول الواجهات — لم يُجب الجهاز');
    }

    Map<int, Varbind> index(List<Varbind> vbs, String base) {
      final m = <int, Varbind>{};
      for (final vb in vbs) {
        final i = _lastIndex(vb.oid, base);
        if (i != null) m[i] = vb;
      }
      return m;
    }

    /// ⚠️ **السقوط إلى السؤال الفرديّ محدودٌ بعدد الواجهات.**
    ///
    /// 🐛 ٢٠٢٦-١٠-٠١ — على OLT فيه ٣٢٧ واجهة كان عمودٌ واحدٌ فاشل
    /// يُنتج ٣٢٧ رحلةً متتابعة، والرحلة ١٣٠ مللي ثانية: ٤٢ ثانيةً
    /// للعمود الواحد. وعمودان يتجاوزان مهلة الأربع دقائق فلا تظهر
    /// بيانات **إطلاقاً** — والحلّ المكلف أسوأ من لا شيء.
    ///
    /// فوق هذا الحدّ نكتفي بما نجح: لوحةٌ بلا عدّاداتٍ خيرٌ من لوحةٍ
    /// لا تصل.
    const perIndexLimit = 64;

    /// هل أثبت الجهاز أنّه لا يُجيب عدّادات ٦٤ بت؟
    ///
    /// الجهاز لا يرفض العمود الغائب بل **يُهمِل الطلب**، فنُنتظره خمس
    /// ثوانٍ حتّى تنقضي المهلة. والعدّادان في الجدول نفسه (`ifXTable`)،
    /// فإذا غاب أحدهما غاب الآخر — فلا نشتري الدرس مرّتين.
    var wideCountersGone = _narrowHosts.contains(snmp.host);
    Future<Map<int, Varbind>> column(String base,
        {String? fallbackOid, bool wide = false}) async {
      var vbs =
          wide && wideCountersGone ? const <Varbind>[] : await safeWalk(base);
      if (wide && vbs.isEmpty) wideCountersGone = true;
      // بديلٌ رخيص: مسحةٌ واحدة لعمودٍ آخر يحمل المعنى نفسه.
      if (vbs.isEmpty && fallbackOid != null) {
        final alt = await safeWalk(fallbackOid);
        if (alt.isNotEmpty) return index(alt, fallbackOid);
      }
      if (vbs.isEmpty && byIdx.length <= perIndexLimit) {
        final got = <Varbind>[];
        for (final i in byIdx.keys) {
          try {
            final r = await snmp.get(['$base.$i']);
            if (r.isNotEmpty) got.add(r.first);
          } catch (_) {/* هذه الواجهة لا تجيب — نتجاوزها */}
        }
        vbs = got;
      }
      return index(vbs, base);
    }

    final oper = await column(_oidIfOper);

    // ⚡ **لقطةٌ مبكّرة: أسماءٌ وحالةٌ فقط.**
    //
    // عدد المشتركين المتّصلين وقائمة منافذ PON لا يحتاجان عنواناً ولا
    // سرعةً ولا عدّاداً. فننشرهما بعد عمودين (~٤٫٥ث) بدل انتظار
    // المسحة كلّها (~٢١ث).
    //
    // (بلاغ المستخدم ٢٠٢٦-١٠-٠١: «أوّل ما يعرض البطاقات يتأخّر يلا
    // يظهر المعلومات»)
    if (onNames != null) {
      onNames([
        for (final i in byIdx.keys.toList()..sort())
          VsolIfRow(
            index: i,
            name: byIdx[i]!,
            up: oper[i]?.asInt == 1,
            mac: null,
            speedMbps: 0,
            rxBytes: 0,
            txBytes: 0,
          ),
      ]);
    }

    // ⚡ **مسحةٌ خفيفة: بنيةٌ فقط.**
    //
    // قياسٌ على `Popq3-olt` ‏(٣٢٧ واجهة): الأسماء والحالة ٦ ثوانٍ،
    // والعدّادات ١٧ أخرى، والعناوين والسرعات ١١. فالمسحة الكاملة ٣٤
    // ثانيةً قبل أن يظهر رقمٌ واحد.
    //
    // والعدّادات تأتي من الطبقات السريعة (‏٢٤ واجهةً في ثانية)، فلا
    // داعيَ لحملها في مسحة البنية. والعناوين والسرعات زينةٌ تتبع.
    //
    // (بلاغ المستخدم ٢٠٢٦-١٠-٠١: «شوف بنفسك التأخير شكد فضيع»)
    if (structureOnly) {
      return (
        rows: [
          for (final i in byIdx.keys.toList()..sort())
            VsolIfRow(
              index: i,
              name: byIdx[i]!,
              up: oper[i]?.asInt == 1,
              mac: null,
              speedMbps: 0,
              rxBytes: 0,
              txBytes: 0,
            ),
        ],
        narrowCounters: _narrowHosts.contains(snmp.host),
        rxAt: null,
        txAt: null,
      );
    }

    // ⚡ **العدّادات قبل العناوين والسرعات.**
    //
    // الترفك يحتاج عيّنتين، وكلّ تأخيرٍ في العيّنة الأولى يؤخّر أوّل
    // رقمٍ مرّتين. والعناوين والسرعات زينةٌ لا يتوقّف عليها شيء.
    //
    // ٦٤ بت أوّلاً، و٣٢ بت بديلاً: فيرموير V1600D الثاني لا ينفّذ
    // `ifXTable` للعدّادات ويضعها في الجدول الأساسيّ وحده.
    // ⚡ مسحة التفاصيل (عناوين وسرعات) لا تحتاج عدّادات: الطبقتان
    // الخفيفتان تجلبانهما أرخص. وتخطّيهما يوفّر ثلاث عشرة ثانيةً من
    // تجميد اللوحة.
    final inOct = withCounters
        ? await column(_oidIfHCIn, fallbackOid: _oidIfIn32, wide: true)
        : const <int, Varbind>{};
    final rxAt = withCounters ? DateTime.now() : null;
    final outOct = withCounters
        ? await column(_oidIfHCOut, fallbackOid: _oidIfOut32, wide: true)
        : const <int, Varbind>{};
    final txAt = withCounters ? DateTime.now() : null;

    if (wideCountersGone) _narrowHosts.add(snmp.host);

    // لقطةٌ ثانية: بنيةٌ **وعدّادات**.
    if (onNames != null && withCounters) {
      onNames([
        for (final i in byIdx.keys.toList()..sort())
          VsolIfRow(
            index: i,
            name: byIdx[i]!,
            up: oper[i]?.asInt == 1,
            mac: null,
            speedMbps: 0,
            rxBytes: inOct[i]?.asInt ?? 0,
            txBytes: outOct[i]?.asInt ?? 0,
          ),
      ]);
    }

    final phys = await column(_oidIfPhys);
    final speed = await column(_oidIfHighSpeed);

    final out = <VsolIfRow>[];
    for (final i in byIdx.keys.toList()..sort()) {
      out.add(VsolIfRow(
        index: i,
        name: byIdx[i]!,
        up: oper[i]?.asInt == 1,
        mac: _macOf(phys[i]),
        speedMbps: speed[i]?.asInt ?? 0,
        rxBytes: inOct[i]?.asInt ?? 0,
        txBytes: outOct[i]?.asInt ?? 0,
      ));
    }
    return (
      rows: out,
      narrowCounters: wideCountersGone,
      rxAt: rxAt,
      txAt: txAt,
    );
  }

  static int? _lastIndex(String oid, String base) {
    if (!oid.startsWith('$base.')) return null;
    final rest = oid.substring(base.length + 1);
    final dot = rest.indexOf('.');
    return int.tryParse(dot >= 0 ? rest.substring(0, dot) : rest);
  }

  /// عنوان MAC من **البايتات الخام** لا من النصّ.
  ///
  /// 🐛 ٢٠٢٦-٠٩-٢٨ — قرأتُه أوّلاً عبر `asString`، وهي تُحوّل
  /// `OCTET STRING` بـ`String.fromCharCodes`. فبايتاتٌ مثل
  /// `7C 6A 60 0E 08 07` تصير محارف تحكّمٍ ورموزاً (`|j\u0060`)
  /// لا عنواناً. والمشغّل يُطابق هذا العنوان بما في نظام الفوترة،
  /// فالتشويه يجعله بلا قيمة.
  ///
  /// ونُصفّر البادئة: `7c:6a:60:0e:08:07` لا `7c:6a:60:e:8:7` —
  /// الصيغة الأولى هي ما يُكتب في كلّ نظامٍ آخر.
  static String? _macOf(Varbind? vb) {
    if (vb == null || vb.isAbsent) return null;
    final b = vb.rawBytes;
    if (b.length != 6) return null;
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
  }
}

// ═══════════════════════════════════════════════════════════
// التحليل — خالصٌ وقابلٌ للاختبار بلا شبكة
// ═══════════════════════════════════════════════════════════

/// صفٌّ خامٌّ من `IF-MIB` قبل التصنيف.
///
/// عامٌّ عمداً: التصنيف هو قلب هذه الطبقة وأكثر ما يُخطئ فيه، فيجب
/// أن يُختبَر بلقطاتٍ مركّبةٍ بلا شبكةٍ ولا جهاز.
@immutable
class VsolIfRow {
  const VsolIfRow({
    required this.index,
    required this.name,
    required this.up,
    required this.mac,
    required this.speedMbps,
    required this.rxBytes,
    required this.txBytes,
  });
  final int index;
  final String name;
  final bool up;
  final String? mac;
  final int speedMbps, rxBytes, txBytes;
}

class VsolParse {
  VsolParse._();

  /// `EPON0/3:2` → منفذ PON ‏3 و ONU ‏2. و`EPON0/3` → منفذ PON وحده.
  /// و`GE0/5` → منفذ صعود. وما لا يُطابق يُهمَل.
  ///
  /// نلتقط الشرطة المائلة والنقطتين بتعبيرٍ واحد كيلا نُصنّف
  /// `EPON0/3` ONU رقم صفر — وهو ما يُفسد عدّ المشتركين.
  static final RegExp _rePon =
      RegExp(r'^EPON(\d+)/(\d+)(?::(\d+))?$', caseSensitive: false);

  /// صيغةٌ ثانية للمشتركين: `EPON01ONU34` = خانة 0، منفذ 1، ONU 34.
  ///
  /// 🐛 ٢٠٢٦-١٠-٠١ — ظهرت على V1600D ثانٍ بفيرموير مختلف. وبدونها
  /// كانت اللوحة تعرض «٠ مشتركين» على جهازٍ فيه ٣٢٧ واجهةً ومئات
  /// المشتركين: منافذ PON تُقرأ (صيغتها واحدة في الفيرمويرين) بينما
  /// يسقط المشتركون كلّهم بصمت.
  static final RegExp _reOnuAlt =
      RegExp(r'^EPON(\d)(\d+)ONU(\d+)$', caseSensitive: false);
  static final RegExp _reUplink =
      RegExp(r'^(?:GE|XGE|TE)(\d+)/(\d+)$', caseSensitive: false);

  static ({
    List<VsolUplink> uplinks,
    List<VsolPonPort> ponPorts,
    List<VsolOnu> onus,
    int onusOnline,
  }) build(List<VsolIfRow> rows) {
    final uplinks = <VsolUplink>[];
    final pons = <String, VsolPonPort>{};
    final onus = <VsolOnu>[];

    for (final r in rows) {
      final alt = _reOnuAlt.firstMatch(r.name);
      if (alt != null) {
        onus.add(VsolOnu(
          ifIndex: r.index,
          slot: int.parse(alt.group(1)!),
          ponPort: int.parse(alt.group(2)!),
          onuId: int.parse(alt.group(3)!),
          online: r.up,
          mac: r.up ? r.mac : null,
          speedMbps: r.speedMbps,
          rxBytes: r.rxBytes,
          txBytes: r.txBytes,
        ));
        continue;
      }
      final pon = _rePon.firstMatch(r.name);
      if (pon != null) {
        final slot = int.parse(pon.group(1)!);
        final port = int.parse(pon.group(2)!);
        final onuId = pon.group(3);
        final portKey = '$slot/$port';
        if (onuId == null) {
          pons[portKey] = VsolPonPort(
            index: r.index,
            slot: slot,
            port: port,
            up: r.up,
            rxBytes: r.rxBytes,
            txBytes: r.txBytes,
          );
        } else {
          onus.add(VsolOnu(
            ifIndex: r.index,
            slot: slot,
            ponPort: port,
            onuId: int.parse(onuId),
            online: r.up,
            // ⚠️ العنوان يُقرأ **للمتّصل وحده**.
            //
            // فحصتُ الثلاثة عشر المتّصلة على جهازٍ فعليّ وقارنتُها بما
            // يعرضه `show onu baisc-info all`: تطابقٌ تامّ. أمّا
            // المفصولة فيُرجع لها الجهاز عنواناً **قديماً مكرّراً** —
            // رأيتُ `EPON0/1:1` المفصول يحمل عنوان `EPON0/2:9`
            // المتّصل. وعرضُ عنوان مشتركٍ أمام اسم مشتركٍ آخر أسوأ من
            // ألّا نعرض شيئاً: المشغّل يُطابقه بنظام الفوترة ويبني
            // عليه قراراً.
            mac: r.up ? r.mac : null,
            speedMbps: r.speedMbps,
            rxBytes: r.rxBytes,
            txBytes: r.txBytes,
          ));
        }
        continue;
      }
      if (_reUplink.hasMatch(r.name)) {
        uplinks.add(VsolUplink(
          index: r.index,
          name: r.name,
          up: r.up,
          speedMbps: r.speedMbps,
          rxBytes: r.rxBytes,
          txBytes: r.txBytes,
        ));
      }
    }

    onus.sort((a, b) {
      final c = a.ponPort.compareTo(b.ponPort);
      return c != 0 ? c : a.onuId.compareTo(b.onuId);
    });
    final ports = pons.values.toList()
      ..sort((a, b) => a.port.compareTo(b.port));

    // عدد الـONU على كلّ منفذ — يُحسب هنا لا في الواجهة، فالواجهة
    // تُعيد الرسم كثيراً والعدّ ثابتٌ ما دامت اللقطة واحدة.
    final counted = ports.map((p) {
      final mine = onus.where((o) => o.slot == p.slot && o.ponPort == p.port);
      return p.withCounts(
        onuTotal: mine.length,
        onuOnline: mine.where((o) => o.online).length,
      );
    }).toList();

    return (
      uplinks: uplinks,
      ponPorts: counted,
      onus: onus,
      onusOnline: onus.where((o) => o.online).length,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// النماذج
// ═══════════════════════════════════════════════════════════

@immutable
class VsolUplink {
  const VsolUplink({
    required this.index,
    required this.name,
    required this.up,
    required this.speedMbps,
    required this.rxBytes,
    required this.txBytes,
  });
  final int index;
  final String name;
  final bool up;
  final int speedMbps, rxBytes, txBytes;

  VsolUplink withBytes(int rx, int tx) => VsolUplink(
        index: index,
        name: name,
        up: up,
        speedMbps: speedMbps,
        rxBytes: rx,
        txBytes: tx,
      );
}

@immutable
class VsolPonPort {
  const VsolPonPort({
    required this.index,
    required this.slot,
    required this.port,
    required this.up,
    required this.rxBytes,
    required this.txBytes,
    this.onuTotal = 0,
    this.onuOnline = 0,
  });
  final int index;
  final int slot, port;
  final bool up;
  final int rxBytes, txBytes, onuTotal, onuOnline;

  String get label => 'EPON$slot/$port';

  VsolPonPort withBytes(int rx, int tx) => VsolPonPort(
        index: index,
        slot: slot,
        port: port,
        up: up,
        rxBytes: rx,
        txBytes: tx,
        onuTotal: onuTotal,
        onuOnline: onuOnline,
      );

  VsolPonPort withCounts({required int onuTotal, required int onuOnline}) =>
      VsolPonPort(
        index: index,
        slot: slot,
        port: port,
        up: up,
        rxBytes: rxBytes,
        txBytes: txBytes,
        onuTotal: onuTotal,
        onuOnline: onuOnline,
      );
}

@immutable
class VsolOnu {
  const VsolOnu({
    required this.ifIndex,
    required this.slot,
    required this.ponPort,
    required this.onuId,
    required this.online,
    this.mac,
    this.speedMbps = 0,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  final int ifIndex, slot, ponPort, onuId;
  final bool online;
  final String? mac;
  final int speedMbps, rxBytes, txBytes;

  /// كما يكتبه المشغّل ويقرؤه في الـCLI: `EPON0/3:2`.
  String get label => 'EPON$slot/$ponPort:$onuId';

  VsolOnu withBytes(int rx, int tx) => VsolOnu(
        ifIndex: ifIndex,
        slot: slot,
        ponPort: ponPort,
        onuId: onuId,
        online: online,
        mac: mac,
        speedMbps: speedMbps,
        rxBytes: rx,
        txBytes: tx,
      );
}

@immutable
class VsolOltStats {
  const VsolOltStats({
    this.sysDescr,
    this.sysName,
    this.uptime,
    this.uplinks = const [],
    this.ponPorts = const [],
    this.onus = const [],
    this.narrowCounters = false,
    this.rxAt,
    this.txAt,
  });

  final String? sysDescr, sysName;
  final Duration? uptime;

  /// هل العدّادات ٣٢ بت (تلتفّ عند ٤٫٢٩ جيجابايت)؟
  ///
  /// ⚠️ **حين تكون كذلك، المجموع التراكميّ كذبةٌ لا نقص.** قياسٌ فعليّ
  /// على `Popq3-olt` ‏(٢٠٢٦-١٠-٠١): مرفوعٌ ٦٨ ساعة، ١٨٩ مشتركاً،
  /// ومجموع منافذه ٣٧٫٥ جيجابايت — أي ١٫٥ كيلوبت/ث للمشترك. والعدّادات
  /// الستّة عشر كلّها دون ٢³²، وأربعةٌ على بُعد ١٪ من السقف.
  /// العدّاد لم «يَقِلّ»، بل التفّ مراراً فضاع ما قبل اللفّة الأخيرة.
  ///
  /// (بلاغ المستخدم: «قيم الترفك مبالغ بيها ٣٧ كيكا»)
  final bool narrowCounters;

  /// ⚠️ **لحظة قراءة العدّادات — لا لحظة انتهاء المسحة.**
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «أكو شي مو منطقي… ٧٥٩ ميكا» ثمّ
  /// قفزاتٌ إلى ٣٠٦١ ميجابت في المحاكاة.
  ///
  /// المسحة الكاملة ثلاثٌ وثلاثون ثانية وتقرأ عدّاداتها في منتصفها.
  /// فختمُها بلحظة الانتهاء يُؤخّر العيّنة ثمانيَ عشرة ثانية، ثمّ
  /// يُقسَم الفرق التالي على ثانيتين بدل عشرين — تضخيمٌ أحد عشر ضعفاً.
  ///
  /// فالعدّاد يحمل ختمه معه، والمعدّل يُحسب من الختمين لا من ساعة
  /// المستدعي.
  ///
  /// ⚠️ **وختمان لا واحد.** الوارد والصادر عمودان يُمسحان بالتتابع،
  /// وبينهما خمس ثوانٍ على جدولٍ فيه ٣٢٧ واجهة. فختمٌ مشترَكٌ يُخطئ
  /// أحدهما بخمسٍ — وهي عشرة أضعافٍ حين يكون الفاصل نصف ثانية.
  final DateTime? rxAt, txAt;

  DateTime? get countersAt => rxAt;
  final List<VsolUplink> uplinks;
  final List<VsolPonPort> ponPorts;
  final List<VsolOnu> onus;

  int get onusOnline => onus.where((o) => o.online).length;
  int get onusTotal => onus.length;
  int get ponUp => ponPorts.where((p) => p.up).length;

  /// إجماليّ ترفك **منافذ PON** لا مجموع الـONU.
  ///
  /// ⚠️ جمع الـONU يعدّ البايت مرّتين: ما يمرّ على ONU يمرّ على منفذ
  /// PON الذي يحمله. وهي العلّة نفسها التي أبلغ عنها المستخدم في لوحة
  /// روجي ٢٠٢٦-٠٩-٢٨.
  int get ponRxBytes => ponPorts.fold(0, (s, p) => s + p.rxBytes);
  int get ponTxBytes => ponPorts.fold(0, (s, p) => s + p.txBytes);

  bool get isEmpty => onus.isEmpty && ponPorts.isEmpty && uplinks.isEmpty;

  /// كم واجهةً تحملها هذه اللقطة — مقياسُ «الأغنى».
  int get interfaceCount => ponPorts.length + onus.length + uplinks.length;

  /// هل فيها عدّاداتٌ أصلاً؟ لقطةُ البنية تأتي بأصفار.
  bool get hasCounters =>
      ponPorts.any((p) => p.rxBytes > 0 || p.txBytes > 0) ||
      uplinks.any((u) => u.rxBytes > 0 || u.txBytes > 0);

  /// هل [next] أغنى من [cur]؟
  ///
  /// 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «هيج صافن». المسحة تبعث لقطتين:
  /// الهويّة (اسمٌ ورفع، صفر واجهات) بعد ثانية، ثمّ الأسماء والحالة
  /// (‏٨ منافذ و٣٠١ مشترك) بعد عشر. وكانت اللوحة تقبل الأولى وترفض
  /// الثانية بشرط `_stats == null`، فتبقى على «٠/٠» إحدى وعشرين
  /// ثانيةً بلا سبب.
  ///
  /// والقاعدة: **لا نُفقر المعروض**. وهي تحمي الاتّجاه الآخر أيضاً —
  /// لقطة هويّةٍ في مسحةٍ دوريّةٍ لاحقة لا تمحو لوحةً مكتملة.
  static bool richer(VsolOltStats? cur, VsolOltStats next) {
    if (cur == null) return true;
    if (next.interfaceCount != cur.interfaceCount) {
      return next.interfaceCount > cur.interfaceCount;
    }
    // عند تساوي الواجهات: من يحمل عدّاداتٍ أغنى ممّن لا يحملها.
    return next.hasCounters && !cur.hasCounters;
  }
}

/// معدّل المرور بين لقطتين، بالبت في الثانية.
///
/// العدّاد التراكميّ لا يصلح عرضاً — لا لأنّه كبير بل لأنّه يلتفّ.
/// والفرق بين لقطتين يَسلم من الالتفاف ما دامت اللقطتان في لفّةٍ
/// واحدة، وهو أيضاً ما يحتاجه المشغّل فعلاً.
class VsolTraffic {
  const VsolTraffic(this.rxBps, this.txBps);

  /// `null` تعني «لا نعرف» — ولا تُعرَض رقماً.
  final double? rxBps, txBps;

  bool get known => rxBps != null && txBps != null;

  static const _wrap32 = 4294967296; // ٢³²

  /// يحسب المعدّل، أو `null` حيث لا يصحّ ادّعاء رقم.
  ///
  /// ⚠️ **الحارس هو سرعة المنفذ.** العدّاد الضيّق يلتفّ كلّ ٢٧ ثانيةً
  /// على منفذ EPON مشبَع. فإن جاء الفرق بمعدّلٍ يتجاوز سرعة المنفذ
  /// فقد فاتتنا لفّةٌ كاملة على الأقلّ، والرقم عندها تخمينٌ لا قياس —
  /// فنقول «لا نعرف» بدل أن نكتب عدداً يُبنى عليه قرار.
  static double? _rate({
    required int before,
    required int now,
    required Duration elapsed,
    required int speedMbps,
    required bool narrow,
  }) {
    final secs = elapsed.inMilliseconds / 1000.0;
    if (secs <= 0) return null;

    // ⚠️ **صفرٌ في العيّنة الأولى معناه «لم نقرأ» لا «لم يمرّ شيء».**
    //
    // 🐛 بلاغ المستخدم ٢٠٢٦-١٠-٠١: «أكو شي مو منطقي بسحوبات
    // المشتركين، لاحظت بلحظة ٧٥٩ ميكا!».
    //
    // مسحة البنية تُرجع العدّادات أصفاراً لأنّها لا تقرأها. فالطرح
    // منها يُنتج **العدّاد كلّه منذ الإقلاع** مقسوماً على ثوانٍ
    // قليلة: ‏٤ جيجابايت ÷ ٤٢ث ≈ ٧٦٢ ميجابت — وهو ما رآه.
    //
    // وعدّادٌ صفرٌ بقي صفراً فهو خاملٌ حقّاً، فنُبقي له صفره.
    if (before == 0 && now > 0) return null;

    var delta = now - before;
    if (delta < 0) {
      if (!narrow) return null; // ٦٤ بت لا يلتفّ عمليّاً — فهذه إعادة تصفير
      delta += _wrap32;
    }
    final bps = delta * 8 / secs;
    if (speedMbps > 0 && bps > speedMbps * 1000000 * 1.05) return null;
    return bps;
  }

  /// سرعة منفذ EPON الاسميّة — ‏١٫٢٥ جيجابت.
  ///
  /// `VsolPonPort` لا تحمل سرعةً من الجهاز (العمود `ifSpeed` يرجع
  /// صفراً على منافذ PON)، والسرعة هنا سقفُ تصديقٍ لا قياس: ما تجاوزها
  /// فقد التفّ.
  static const eponPortMbps = 1250;

  /// مقارنةُ لقطتين وإخراج معدّلٍ لكلّ عنصر، مفتاحُه اسمه الظاهر.
  ///
  /// الاسم هو الهويّة لا فهرس SNMP: الفهرس يتغيّر بإعادة تسجيل الـONU
  /// بينما `EPON0/3:2` يبقى هو هو.
  static Map<String, VsolTraffic> between(
    VsolOltStats before,
    VsolOltStats now,
    Duration fallbackElapsed,
  ) {
    // ⏱️ الختمان أصدق من ساعة المستدعي: المسحة قد تقرأ عدّاداتها في
    // منتصفها ثمّ تستمرّ عشرين ثانيةً أخرى.
    Duration span(DateTime? a, DateTime? b) =>
        (a != null && b != null) ? b.difference(a) : fallbackElapsed;
    final rxSpan = span(before.rxAt, now.rxAt);
    final txSpan = span(before.txAt, now.txAt);
    final prev = <String, (int, int)>{};
    for (final p in before.ponPorts) {
      prev[p.label] = (p.rxBytes, p.txBytes);
    }
    for (final o in before.onus) {
      prev[o.label] = (o.rxBytes, o.txBytes);
    }
    for (final u in before.uplinks) {
      prev[u.name] = (u.rxBytes, u.txBytes);
    }

    final out = <String, VsolTraffic>{};
    void put(String key, int rx, int tx, int speedMbps) {
      final b = prev[key];
      if (b == null) return;
      out[key] = VsolTraffic(
        _rate(
            before: b.$1,
            now: rx,
            elapsed: rxSpan,
            speedMbps: speedMbps,
            narrow: now.narrowCounters),
        _rate(
            before: b.$2,
            now: tx,
            elapsed: txSpan,
            speedMbps: speedMbps,
            narrow: now.narrowCounters),
      );
    }

    for (final p in now.ponPorts) {
      put(p.label, p.rxBytes, p.txBytes, eponPortMbps);
    }
    for (final o in now.onus) {
      put(o.label, o.rxBytes, o.txBytes, o.speedMbps);
    }
    for (final u in now.uplinks) {
      put(u.name, u.rxBytes, u.txBytes, u.speedMbps);
    }
    return out;
  }
}

class VsolException implements Exception {
  VsolException(this.message);
  final String message;
  @override
  String toString() => message;
}
