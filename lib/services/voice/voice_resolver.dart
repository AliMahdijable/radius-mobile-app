import '../../api/big_subscribers_api.dart';
import '../../api/company_route.dart';
import '../../api/merged_devices_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/subscribers_api.dart';
import '../../core/util/arabic_text.dart';
import '../../models/merged_company.dart';
import '../../models/network_device.dart';
import '../../models/subscriber.dart';
import '../merged_mode.dart';

/// مرشّحٌ بدرجة تطابقه (٠–١٠٠).
class VoiceMatch<T> {
  const VoiceMatch(this.item, this.score);
  final T item;
  final int score;
}

/// نتيجة البحث عن اسم الأمر: الأفضل أوّلاً، و[sure] حين يكون واحدٌ واضحاً بلا منافس.
class VoiceMatches<T> {
  const VoiceMatches(this.items, {this.error});
  final List<VoiceMatch<T>> items;

  /// تعذّر جلب القائمة (شبكة) — رسالةٌ للوكيل لا «ما لكيت».
  final String? error;

  bool get isEmpty => items.isEmpty;

  /// واحدٌ واضح: درجته ≥ ٨٠ ولا ثاني قريبٌ منه (فارق ≥ ١٥).
  bool get sure =>
      items.isNotEmpty && items.first.score >= 80 && (items.length == 1 || items.first.score - items[1].score >= 15);
}

/// جهازٌ بشركته («كل الشركات») — [company] null خارج الوضع، و[open] للشركة المفتوحة (تُفحص بطريقها المعتاد).
typedef VoiceDeviceCompany = ({MergedCompany company, bool open});

/// مطابقة اسم الأمر الصوتيّ بمشتركي الوكيل وأجهزته — على الجهاز، من القوائم نفسها التي يعرضها التطبيق (والحساب الكبير
/// ≥٥٠٠٠ من بحث الشركة لا القائمة الكاملة — pro-big-lists).
///
/// «كل الشركات» (٨ نوفمبر — المالك: «البحث الصوتي ان يتعمم على جميع الشركات… جلب اسماء الاجهزه للوكيل شركه كانت ام عده شركات
/// والبحث باسم الجهاز»): المشتركون من قوائم كلّ الشركات (كلُّ صفٍّ بمفتاح شركته فتذهب عمليّته لها)، والكبيرة ببحثها الموجَّه؛
/// والأجهزة من أجهزة كلّ شركة ([companyOfDevice]).
class VoiceResolver {
  VoiceResolver._();

  /// بدائل الاختبار.
  static Future<List<Subscriber>?> Function() loadSubscribers = SubscribersApi.loadAllWithOnline;
  static Future<int> Function() bigProbe = BigSubscribersApi.probe;
  static Future<List<Subscriber>> Function(String q) bigSearch = _bigSearch;
  static Future<List<NetworkDevice>> Function() loadDevices = () => NetworkDevicesApi.list();

  /// «كل الشركات» فعّال الآن.
  static bool Function() mergedOn = () => MergedMode.active.value;

  /// «كل الشركات»: مشتركو كلّ الشركات لهذا الاسم (الصغيرة من قوائمها، والكبيرة ببحثها) — كلٌّ بمفتاح شركته.
  static Future<List<Subscriber>> Function(String q) mergedSubscribers = _mergedSubscribers;

  /// «كل الشركات»: أجهزة كلّ شركة بشركتها.
  static Future<List<({NetworkDevice device, VoiceDeviceCompany company})>> Function() mergedDevices = _mergedDevices;

  static final Map<int, VoiceDeviceCompany> _deviceCompany = {};

  /// شركة جهازٍ من آخر جلب («كل الشركات») — null خارج الوضع.
  static VoiceDeviceCompany? companyOfDevice(int id) => _deviceCompany[id];

  static Future<List<Subscriber>> _bigSearch(String q) async =>
      (await BigSubscribersApi.page(page: 1, size: 30, tab: 'all', query: q)).rows;

  /// بحث الحساب الكبير بالنصّ كما هو ثمّ بأطول كلمة (الاسم الكامل قد لا يُطابَق حرفيّاً هناك).
  static Future<List<Subscriber>> _bigWithFallback(String q, Future<List<Subscriber>> Function(String q) search) async {
    var pool = await search(q);
    if (pool.isEmpty) {
      final words = q.split(' ')..sort((a, b) => b.length.compareTo(a.length));
      if (words.first != q && words.first.length >= 2) pool = await search(words.first);
    }
    return pool;
  }

  static Future<List<Subscriber>> _mergedSubscribers(String q) async {
    final r = await MergedSubscribers.withSessions(await MergedSubscribers.load());
    final pool = <Subscriber>[...r.rows];
    // الكبيرة: لا قائمة كاملة لها هنا — بحثها الموجَّه بمفتاحها
    for (final p in r.big) {
      try {
        final rows = await CompanyRoute.run(p.company.key, () => _bigWithFallback(q, _bigSearch));
        pool.addAll(rows.map((s) => s.withCompany(p.company.key)));
      } catch (_) {}
    }
    return pool;
  }

  static Future<List<({NetworkDevice device, VoiceDeviceCompany company})>> _mergedDevices() async {
    final data = await MergedMode.load();
    // المفتوحة: المالك بمعرّف جلسته كما كان، والموظّف بصفحته الحاليّة («كل الصفحات» — جلسته تحفظ معرّف مدير الصفحة بصيغةٍ
    // أخرى، فلا تُعرف صفحته فيُرفض فحص جهازه أو يُفحص عبر VPN) — كشاشة الأجهزة.
    final openAdmin = await MergedMode.openAdminId();
    final parts = await MergedDevicesApi.load(data.usable, openAdminId: openAdmin);
    final seen = <int>{};
    return [
      for (final p in parts)
        for (final d in p.devices ?? const <NetworkDevice>[])
          // معرّف الجهاز فريدٌ في قاعدتنا — تكرارٌ بين شركتين لا يُنسب لاثنتين
          if (seen.add(d.id)) (device: d, company: (company: p.company, open: p.open)),
    ];
  }

  static Future<VoiceMatches<Subscriber>> subscribers(String query, {int limit = 6}) async {
    final q = query.trim();
    if (q.isEmpty) return const VoiceMatches([]);
    try {
      List<Subscriber> pool;
      if (mergedOn()) {
        pool = await mergedSubscribers(q);
      } else if (await bigProbe() > 0) {
        pool = await _bigWithFallback(q, bigSearch);
      } else {
        pool = await loadSubscribers() ?? const [];
      }
      return VoiceMatches(rank(pool, q, limit: limit));
    } catch (_) {
      return const VoiceMatches([], error: 'تعذّر جلب المشتركين الآن — حاول بعد قليل');
    }
  }

  static Future<VoiceMatches<NetworkDevice>> devices(String query, {String? kind, int limit = 6}) async {
    try {
      List<NetworkDevice> all;
      if (mergedOn()) {
        final rows = await mergedDevices();
        _deviceCompany
          ..clear()
          ..addEntries(rows.map((r) => MapEntry(r.device.id, r.company)));
        all = [for (final r in rows) r.device];
      } else {
        _deviceCompany.clear();
        all = await loadDevices();
      }
      return VoiceMatches(rankDevices(all, query, kind: kind, limit: limit));
    } catch (_) {
      return const VoiceMatches([], error: 'تعذّر جلب الأجهزة الآن — حاول بعد قليل');
    }
  }

  // ───────────────────────── المطابقة (نقيّة — مختبَرة) ─────────────────────────

  static List<VoiceMatch<Subscriber>> rank(List<Subscriber> all, String query, {int limit = 6}) {
    final q = _prep(query);
    if (q.text.isEmpty) return const [];
    final out = <VoiceMatch<Subscriber>>[];
    for (final s in all) {
      final sc = scoreSubscriber(s, q);
      if (sc >= 40) out.add(VoiceMatch(s, sc));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  static int scoreSubscriber(Subscriber s, VoiceQuery q) {
    final user = _norm(s.username);
    final first = _norm(s.firstname);
    final last = _norm(s.lastname);
    final full = '$first $last'.trim();
    final nameWords = full.isEmpty ? const <String>[] : full.split(' ').map(_bare).toList();
    var best = 0;
    void at(int v) {
      if (v > best) best = v;
    }

    // اليوزر
    final compact = q.text.replaceAll(' ', '');
    if (user == compact || user == q.text) at(100);
    if (compact.length >= 3 && user.startsWith(compact)) at(72);
    if (compact.length >= 3 && user.contains(compact)) at(55);
    // اليوزر بكلماته («ali hussein» ⇔ ali.hussein — الفهم يحوّل نقطته مسافة)
    final userWords = user.split(_userSplit).where((w) => w.isNotEmpty).toList();
    if (userWords.length > 1 && compact.length >= 3) {
      final flat = userWords.join();
      if (flat == compact) at(98);
      if (flat.startsWith(compact)) at(72);
    }
    if (q.digits.isEmpty && q.letters.isNotEmpty && userWords.isNotEmpty) {
      final parts = [for (final w in userWords) w.replaceAll(RegExp(r'\d+'), '')].where((w) => w.isNotEmpty).toList();
      var hit = 0;
      var ordered = true;
      var lastAt = -1;
      for (final w in q.letters) {
        final i = _wordIndex(parts, w, from: 0);
        if (i < 0) continue;
        hit++;
        if (i < lastAt) ordered = false;
        lastAt = i;
      }
      if (hit == q.letters.length) at(ordered ? 86 : 80);
    }
    // الاسم: كامله، ثمّ كلّ كلمة بداية كلمةٍ منه (بالترتيب أعلى)
    if (full.isNotEmpty && _bare(full) == _bare(q.text)) at(95);
    // كلمات الحروف وحدها تُطابَق بالاسم (الأرقام لليوزر)
    var letterHit = 0;
    if (nameWords.isNotEmpty && q.letters.isNotEmpty) {
      var ordered = true;
      var last0 = -1;
      for (final w in q.letters) {
        final i = _wordIndex(nameWords, w, from: 0);
        if (i < 0) continue;
        letterHit++;
        if (i < last0) ordered = false;
        last0 = i;
      }
      if (q.digits.isEmpty) {
        if (letterHit == q.letters.length) {
          at(ordered ? 88 : 80);
        } else if (letterHit > 0) {
          at(40 + 15 * letterHit ~/ q.letters.length);
        }
      }
    }
    // الاسم بلغةٍ والمنطوق بأخرى: «ali hussein» ⇔ «علي حسين» كلمةً كلمة بالهيكل الصوتيّ (١٠ نوفمبر — الأمر بالإنكليزيّة)
    var crossHit = 0;
    if (nameWords.isNotEmpty && q.letters.isNotEmpty && letterHit < q.letters.length) {
      var fuzzy = 0;
      var bonus = 0;
      var ordered = true;
      var lastAt = -1;
      for (final w in q.letters) {
        var at0 = _wordIndex(nameWords, w, from: 0);
        var grade = at0 >= 0 ? 2 : 0;
        if (grade == 0) {
          for (var i = 0; i < nameWords.length; i++) {
            final g = phoneticMatch(w, nameWords[i]);
            if (g > grade) {
              grade = g;
              at0 = i;
              if (g == 2) break;
            }
          }
          if (grade == 2 && _longVowelAgree(w, nameWords[at0])) bonus = 3;
        }
        if (grade == 0) continue;
        crossHit++;
        if (grade == 1) fuzzy++;
        if (at0 < lastAt) ordered = false;
        lastAt = at0;
      }
      if (q.digits.isEmpty) {
        if (crossHit == q.letters.length) {
          // التقريبيّ (حرفٌ مختلف) لا يُجزم به وحده
          at((ordered ? 84 : 78) - 6 * fuzzy + bonus);
        } else if (crossHit > 0) {
          at(40 + 15 * crossHit ~/ q.letters.length);
        }
      }
    }
    if (crossHit > letterHit) letterHit = crossHit;
    // الأرقام في الجملة («علي 77») يجب أن تكون في اليوزر — وتحسم بين «علي»ات
    if (q.digits.isNotEmpty) {
      final hasAll = q.digits.every(user.contains);
      if (!hasAll) {
        best = best >= 80 ? best - 30 : best ~/ 2;
      } else if (q.letters.isEmpty) {
        at(70);
      } else if (letterHit == q.letters.length) {
        at(86);
      } else if (letterHit > 0) {
        at(66);
      } else if (q.letters.every((w) => user.contains(w))) {
        at(84);
      }
    }
    // يوزرٌ لاتينيّ وجملةٌ عربيّة: بالهيكل الصوتيّ («علي حسين» ⇒ LHSN ≈ ali.hussein)
    if (best < 80 && q.skeleton.length >= 2 && RegExp('[a-z]').hasMatch(user)) {
      final us = latinSkeleton(user);
      if (us.isNotEmpty) {
        if (us == q.skeleton) {
          at(78);
        } else if (us.startsWith(q.skeleton) || q.skeleton.startsWith(us) && us.length >= 3) {
          at(62);
        } else if (q.skeleton.length >= 3 && us.contains(q.skeleton)) {
          at(50);
        }
      }
    }
    // الهاتف: رقمٌ طويل وحده
    if (q.letters.isEmpty && q.digits.length == 1 && q.digits.first.length >= 6) {
      String core(String? p) {
        var d = (p ?? '').replaceAll(RegExp(r'\D'), '');
        if (d.startsWith('00')) d = d.substring(2);
        if (d.startsWith('964')) d = d.substring(3);
        if (d.startsWith('0')) d = d.substring(1);
        return d;
      }
      var want = q.digits.first;
      if (want.startsWith('0')) want = want.substring(1);
      if (core(s.phone).endsWith(want) || core(s.mobile).endsWith(want)) at(90);
    }
    return best;
  }

  static List<VoiceMatch<NetworkDevice>> rankDevices(List<NetworkDevice> all, String query, {String? kind, int limit = 6}) {
    final q = _prep(query);
    final out = <VoiceMatch<NetworkDevice>>[];
    for (final d in all) {
      var sc = 0;
      final name = _bare(_norm(d.name));
      final words = name.isEmpty ? const <String>[] : name.split(' ');
      if (q.text.isEmpty) {
        sc = kind != null && d.type == kind ? 70 : 0;
      } else {
        if (name == _bare(q.text)) sc = 100;
        if (sc < 90 && d.ip == query.trim()) sc = 100;
        if (q.words.isNotEmpty) {
          var hit = 0;
          var cross = 0;
          for (final w in q.words) {
            if (_wordIndex(words, w, from: 0) >= 0 || name.contains(w)) {
              hit++;
            } else if (_crossDeviceWord(words, w)) {
              // "check sector north" ⇔ «سكتر الشمال»، "karrada" ⇔ «الكرادة»
              cross++;
            }
          }
          if (hit + cross == q.words.length) {
            final full = cross > 0 ? 80 : 85;
            sc = sc < full ? full : sc;
          } else if (hit + cross > 0 && sc < 50) {
            sc = 40 + 20 * (hit + cross) ~/ q.words.length;
          }
        }
        if (q.digits.isNotEmpty && !q.digits.every((x) => name.contains(x) || d.ip.endsWith(x))) sc = sc ~/ 2;
        if (kind != null && sc > 0) sc = d.type == kind ? (sc + 8).clamp(0, 100) : sc - 10;
      }
      if (sc >= 40) out.add(VoiceMatch(d, sc));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out.take(limit).toList();
  }

  // ── أدوات ──
  static String _norm(String? s) => normalizeArabic(latinDigits((s ?? '').toLowerCase()));

  /// بلا «ال» التعريف أوّل كلّ كلمة — «السكتر الشمالي» = «سكتر شمالي».
  static String _bare(String s) => s.split(' ').map((w) => w.length > 3 && w.startsWith('ال') ? w.substring(2) : w).join(' ');

  static int _wordIndex(List<String> words, String w, {int from = 0}) {
    final b = _bare(w);
    for (var i = from; i < words.length; i++) {
      final x = words[i];
      if (x == b || (b.length >= 2 && x.startsWith(b))) return i;
      // «لعلي» = لـ + علي، و«بعلي» = بـ + علي («اتصل بعلي» — ٧ نوفمبر)
      if (b.length > 3 && (b.startsWith('ل') || b.startsWith('ب')) && (x == b.substring(1) || x.startsWith(b.substring(1)))) return i;
    }
    return -1;
  }

  static final _userSplit = RegExp('[^a-z0-9\u0621-\u064A]+');
  static final _arabicLetter = RegExp('[\u0621-\u064A\u067E\u0686\u06A4\u06AF]');
  static final _latinLetter = RegExp('[a-z]');

  /// اتّجاهاتٌ وصفاتٌ تُسمّى بها الأجهزة — المنطوق الإنكليزيّ يطابق الاسم العربيّ.
  static const _deviceTerms = {
    'north': 'شمال', 'northern': 'شمال', 'south': 'جنوب', 'southern': 'جنوب', 'east': 'شرق', 'eastern': 'شرق',
    'west': 'غرب', 'western': 'غرب', 'center': 'مركز', 'centre': 'مركز', 'central': 'مركز', 'middle': 'وسط',
    'main': 'رييسي', 'old': 'قديم', 'new': 'جديد', 'tower': 'برج', 'first': 'اول', 'second': 'ثاني', 'third': 'ثالث',
  };

  static bool _crossDeviceWord(List<String> nameWords, String w) {
    final b = _bare(w);
    final ar = _deviceTerms[b];
    for (final x in nameWords) {
      if (ar != null && x.startsWith(ar)) return true;
      final back = _deviceTerms[x];
      if (back != null && b.startsWith(back)) return true;
      if (phoneticMatch(b, x) == 2) return true;
    }
    return false;
  }

  /// كلمتان بلغتين (عربيّة ولاتينيّة) تُنطقان واحدة؟ ٢ = مطابقة، ١ = تقريبيّة (حرفٌ ساكن مختلف — «kazem» ⇔ «كاظم»)، ٠ = لا.
  /// الهيكل القصير (ساكنٌ أو اثنان: «علي» = L) يُشترط له اتّفاق أوّل الكلمة وآخرها — وإلّا طابق «ali» «ليلى» و«علا».
  static int phoneticMatch(String a, String b) {
    final aAr = _arabicLetter.hasMatch(a);
    final bAr = _arabicLetter.hasMatch(b);
    if (aAr == bAr) return 0;
    final ar = _bare(aAr ? a : b);
    final la = (aAr ? b : a).toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    if (ar.isEmpty || la.isEmpty) return 0;
    final ska = wordSkeleton(ar);
    if (ska.isEmpty) return 0;
    var best = 0;
    // «alhilli» ⇔ «الحلي»: أداة التعريف ملصوقةً باللاتينيّة
    final forms = [la, if (la.length > 4 && (la.startsWith('al') || la.startsWith('el'))) la.substring(2)];
    for (final f in forms) {
      final skl = wordSkeleton(f);
      if (skl.isEmpty) continue;
      if (ska == skl) {
        if (ska.length >= 3 || _edgesAgree(ar, f)) return 2;
      } else if (ska.length >= 3 && skl.length >= 3 && _oneEdit(ska, skl)) {
        best = 1;
      }
    }
    return best;
  }

  /// هيكل كلمةٍ واحدة — كـ[arabicSkeleton]/[latinSkeleton] مع إسقاط التاء المربوطة/الهاء الأخيرة (تُكتب a/ah باللاتينيّة).
  static String wordSkeleton(String w) {
    if (_arabicLetter.hasMatch(w)) {
      final x = w.length > 2 && w.endsWith('ه') ? w.substring(0, w.length - 1) : w;
      return arabicSkeleton(x);
    }
    var x = w.toLowerCase().replaceAll(RegExp('[^a-z]'), '').replaceAll('ph', 'f');
    if (x.length > 3 && (x.endsWith('ah') || x.endsWith('eh'))) x = x.substring(0, x.length - 1);
    return latinSkeleton(x);
  }

  /// أوّل الكلمة (صائتٌ/ساكن) وآخرها (ي ⇔ i/y/a، ا ⇔ a، ه ⇔ a/ah، ساكنٌ ⇔ ساكن) متّفقان بين الكتابتين.
  static bool _edgesAgree(String ar, String la) {
    const vowels = 'aeiou';
    final a0 = ar[0];
    final l0 = la[0];
    final arOpen = a0 == 'ا' || a0 == 'ع' || a0 == 'ء';
    if (arOpen != vowels.contains(l0)) {
      final glide = (a0 == 'و' && 'wou'.contains(l0)) || (a0 == 'ي' && 'yiej'.contains(l0));
      if (!glide) return false;
    }
    final aN = ar[ar.length - 1];
    final lN = la[la.length - 1];
    return switch (aN) {
      'ي' => 'iyea'.contains(lN) || la.endsWith('ah'),
      'ا' => lN == 'a' || la.endsWith('ah'),
      'ه' => 'ae'.contains(lN) || la.endsWith('ah') || la.endsWith('eh') || lN == 't',
      'و' => 'ouw'.contains(lN),
      _ => !vowels.contains(lN),
    };
  }

  /// «hussein» ⇔ «حسين» (ياءٌ ممدودة بالكتابتين) — يقدّمه على «حسن».
  static bool _longVowelAgree(String a, String b) {
    final ar = _arabicLetter.hasMatch(a) ? a : b;
    final la = (_arabicLetter.hasMatch(a) ? b : a).toLowerCase();
    if (!_latinLetter.hasMatch(la)) return false;
    final arLong = ar.length > 1 && ar.substring(1).contains('ي');
    final laLong = RegExp('ee|ei|ie|ey|ai|ay').hasMatch(la) || la.endsWith('i') || la.endsWith('y');
    return arLong && laLong;
  }

  /// هيكلان بينهما حرفٌ واحد (تبديلٌ أو زيادة أو نقص).
  static bool _oneEdit(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }

  static VoiceQuery _prep(String query) {
    final text = _bare(_norm(query)).replaceAll(RegExp(r'\s+'), ' ').trim();
    // «ali al hussein» — أداة التعريف اللاتينيّة قائمةً بنفسها ليست كلمة اسم
    final words = text.isEmpty ? const <String>[] : text.split(' ').where((w) => w != 'al' && w != 'el').toList();
    final digits = <String>[];
    final letters = <String>[];
    for (final w in words) {
      digits.addAll(RegExp(r'\d+').allMatches(w).map((x) => x.group(0)!));
      final l = w.replaceAll(RegExp(r'\d+'), '');
      if (l.isNotEmpty) letters.add(l);
    }
    return VoiceQuery(text, words, digits, letters, arabicSkeleton(letters.join(' ')));
  }

  /// هيكلٌ صوتيّ بلا حروف علّة (للمطابقة بين المنطوق العربيّ واليوزر اللاتينيّ).
  static String arabicSkeleton(String s) {
    const map = {
      'ب': 'B', 'پ': 'B', 'ت': 'T', 'ط': 'T', 'ث': 'T', 'ج': 'J', 'چ': 'J', 'ح': 'H', 'ه': 'H', 'خ': 'K', 'د': 'D',
      'ذ': 'D', 'ض': 'D', 'ظ': 'D', 'ر': 'R', 'ز': 'Z', 'س': 'S', 'ص': 'S', 'ش': 'S', 'غ': 'G', 'ف': 'F', 'ڤ': 'F',
      'ق': 'K', 'ك': 'K', 'گ': 'K', 'ل': 'L', 'م': 'M', 'ن': 'N',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final m = map[ch];
      if (m != null) b.write(m);
    }
    return _collapse(b.toString());
  }

  static String latinSkeleton(String s) {
    var t = s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    t = t
        .replaceAll('kh', 'K')
        .replaceAll('gh', 'G')
        .replaceAll('sh', 'S')
        .replaceAll('ch', 'J')
        .replaceAll('th', 'T')
        .replaceAll('dh', 'D');
    const map = {
      'b': 'B', 'p': 'B', 't': 'T', 'j': 'J', 'h': 'H', 'd': 'D', 'z': 'Z', 'r': 'R', 's': 'S', 'f': 'F', 'v': 'F',
      'q': 'K', 'k': 'K', 'g': 'K', 'c': 'K', 'l': 'L', 'm': 'M', 'n': 'N', 'x': 'KS',
    };
    final b = StringBuffer();
    for (final ch in t.split('')) {
      if (ch == ch.toUpperCase() && RegExp('[A-Z]').hasMatch(ch)) {
        b.write(ch);
        continue;
      }
      final m = map[ch];
      if (m != null) b.write(m);
    }
    return _collapse(b.toString());
  }

  static String _collapse(String s) {
    final b = StringBuffer();
    String? prev;
    for (final ch in s.split('')) {
      if (ch != prev) b.write(ch);
      prev = ch;
    }
    return b.toString();
  }
}

/// جملة الاسم بعد التطبيع: النصّ وكلماته وأرقامه وهيكله الصوتيّ.
class VoiceQuery {
  const VoiceQuery(this.text, this.words, this.digits, this.letters, this.skeleton);
  final String text;
  final List<String> words;
  final List<String> digits;
  final List<String> letters;
  final String skeleton;
}
