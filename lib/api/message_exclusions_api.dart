import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'company_route.dart';

/// «المستثنون من الرسائل» (المالك ١٤ نوفمبر: «نسوي مثل القسم الريجكتد مسج، يعني ذولا ما تروح لهم رسائل… التفعيل، التنبيهات،
/// التذكير، التبليغات» ثمّ «تقسيم… نعم مستثنى»): على خادمنا وحده (`server/messageExclusions.js` — المسارات
/// `/api/v2/message-exclusions`). لكلّ مشترك «كلّ الرسائل» أو أنواعٌ منها، والخادم يحجبها عند كلّ باب إرسال — فالتطبيق يعرض ويحفظ
/// فقط. المفتاح مطفأ للحساب ⇒ enabled:false ⇒ لا شيء يُعرض.
///
/// «كل الشركات» (١٥ نوفمبر — المالك: «نعم هم سويها»): قائمة كلّ شركةٍ تُقرأ بطلبها الموجَّه ([MessageExclusionsState.ensureFreshFor])،
/// وإيقاف رسائل مشترك صفٍّ والسماح بها بالمسار ذي الرقم ([MessageExclusionsApi.saveAt]/[MessageExclusionsApi.removeAt]) بغلاف شركة
/// الصفّ (MergedOps.writeAt — مرجع نافذته، كبقيّة كتابات المشترك). الجماعيّ والمساران بلا رقم للصفحة المفتوحة وحدها.

/// نوعٌ من الرسائل يُوقف عن المشترك — `all` «كلّ الرسائل» أو مجموعة (ops · reminders · broadcast · conn). الاسم والشرح من الخادم.
class MxGroup {
  const MxGroup({required this.key, required this.label, required this.hint});
  final String key;
  final String label;
  final String hint;

  bool get isAll => key == allKey;

  static const String allKey = 'all';

  static MxGroup? fromJson(dynamic v) {
    if (v is! Map) return null;
    final k = v['key']?.toString().trim() ?? '';
    final l = v['label']?.toString().trim() ?? '';
    if (k.isEmpty || l.isEmpty) return null;
    return MxGroup(key: k, label: l, hint: v['hint']?.toString().trim() ?? '');
  }
}

/// مشتركٌ مستثنى: ما أُوقف عنه، وملاحظة الوكيل، ومن أوقفها ومتى.
class MxEntry {
  const MxEntry({
    required this.username,
    required this.groups,
    required this.label,
    this.idx,
    this.name,
    this.phone,
    this.note,
    this.by,
    this.at,
  });

  final String username;

  /// `['all']` أو جزءٌ من المجموعات بترتيب الخادم.
  final List<String> groups;

  /// نصّ الخادم الجاهز للعرض: «كلّ الرسائل» أو «التذكيرات، التبليغات».
  final String label;
  final String? idx;
  final String? name;
  final String? phone;
  final String? note;
  final String? by;
  final DateTime? at;

  bool get all => groups.contains(MxGroup.allKey);

  /// اسم العرض: الاسم المحفوظ وقت الاستثناء، وإلّا اليوزر.
  String get display => (name ?? '').trim().isNotEmpty ? name!.trim() : username;

  static MxEntry? fromJson(String username, dynamic v) {
    if (v is! Map || username.trim().isEmpty) return null;
    String? s(dynamic x) {
      final t = x?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final groups = [
      if (v['groups'] is List)
        for (final g in v['groups'] as List)
          if ((g?.toString().trim() ?? '').isNotEmpty) g.toString().trim(),
    ];
    if (groups.isEmpty) return null;
    return MxEntry(
      username: username,
      groups: groups,
      label: s(v['label']) ?? groups.join('، '),
      idx: s(v['idx']),
      name: s(v['name']),
      phone: s(v['phone']),
      note: s(v['note']),
      by: s(v['by']),
      at: DateTime.tryParse(v['at']?.toString() ?? '')?.toLocal(),
    );
  }
}

/// المشترك كما يُرسَل للحفظ (اليوزر مفتاحه؛ رقمه عند المزوّد واسمه وهاتفه تُحفظ معه ليُعرف في كلّ مسار إرسال).
class MxSubject {
  const MxSubject({required this.username, this.idx, this.name, this.phone});
  final String username;
  final String? idx;
  final String? name;
  final String? phone;

  Map<String, dynamic> toJson() => {
        'username': username,
        if ((idx ?? '').isNotEmpty) 'idx': idx,
        if ((name ?? '').trim().isNotEmpty) 'name': name!.trim(),
        if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
      };
}

/// قائمة مستثني الصفحة كما قرأناها: هل الميزة مفتوحة، هل يُدير هذا المستخدم، الأنواع، والمستثنون (بيوزرٍ صغير الأحرف).
class MxSnapshot {
  const MxSnapshot({
    required this.enabled,
    required this.canManage,
    required this.groups,
    required this.entries,
    this.max = 5000,
  });

  final bool enabled;
  final bool canManage;
  final List<MxGroup> groups;
  final Map<String, MxEntry> entries;
  final int max;

  static const MxSnapshot off = MxSnapshot(enabled: false, canManage: false, groups: [], entries: {});

  int get count => entries.length;

  MxEntry? of(String? username) {
    final u = username?.trim().toLowerCase() ?? '';
    return u.isEmpty ? null : entries[u];
  }

  /// نسخةٌ بعد حفظ/إزالة مشتركٍ واحد (entry null = أُزيل).
  MxSnapshot withEntry(String username, MxEntry? entry) {
    final next = Map<String, MxEntry>.of(entries);
    final k = username.trim().toLowerCase();
    if (entry == null) {
      next.remove(k);
    } else {
      next[k] = entry;
    }
    return MxSnapshot(enabled: enabled, canManage: canManage, groups: groups, entries: next, max: max);
  }

  static MxSnapshot fromJson(Map<String, dynamic> b) {
    if (b['enabled'] != true) return off;
    final groups = [
      if (b['groups'] is List)
        for (final g in b['groups'] as List)
          if (MxGroup.fromJson(g) case final MxGroup x) x,
    ];
    final entries = <String, MxEntry>{};
    final raw = b['exclusions'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final u = e.key.toString();
        final x = MxEntry.fromJson(u, e.value);
        if (x != null) entries[u.trim().toLowerCase()] = x;
      }
    }
    final max = b['max'];
    return MxSnapshot(
      enabled: true,
      canManage: b['can_manage'] == true,
      groups: groups,
      entries: entries,
      max: max is num && max > 0 ? max.toInt() : 5000,
    );
  }
}

class MessageExclusionsApi {
  MessageExclusionsApi._();

  static const String path = '/api/v2/message-exclusions';
  static const String allPath = '$path/all';
  static const String bulkPath = '$path/bulk';

  /// حدّ الخادم لدفعةٍ واحدة — المحدَّد الأكبر يُقسَّم.
  static const int bulkMax = 500;

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final b = e.response?.data;
      final m = b is Map ? b['message']?.toString() : null;
      if (m != null && m.trim().isNotEmpty) return m;
    }
    return fallback;
  }

  /// قائمة الصفحة المفتوحة كلّها (صغيرة) — للشارة على الكرت، ولوحة المشترك، وصفحة القائمة.
  static Future<({bool ok, MxSnapshot? snapshot, String? message})> all() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(allPath);
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, snapshot: null, message: b['message']?.toString());
      return (ok: true, snapshot: MxSnapshot.fromJson(b), message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusions GET: $e');
      return (ok: false, snapshot: null, message: _msg(e, 'تعذّر جلب قائمة المستثنين'));
    }
  }

  /// حفظ ما يُوقف عن مشترك — [groups] فارغة = إزالة الاستثناء. ⇒ entry: الصفّ بعد الحفظ (null إن أُزيل).
  static Future<({bool ok, MxEntry? entry, String? message})> save(
    MxSubject subject, {
    required List<String> groups,
    String note = '',
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(path, data: {
        ...subject.toJson(),
        'groups': groups,
        'note': note.trim(),
      });
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, entry: null, message: b['message']?.toString() ?? 'تعذّر الحفظ');
      return (ok: true, entry: MxEntry.fromJson(subject.username, b['exclusion']), message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusions PUT: $e');
      return (ok: false, entry: null, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  /// إزالة الاستثناء — تعود الرسائل تصله.
  static Future<({bool ok, String? message})> remove(String username) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(path, queryParameters: {'username': username});
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, message: b['message']?.toString() ?? 'تعذّر الحفظ');
      return (ok: true, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusions DELETE: $e');
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  // ── المسار ذو الرقم («كل الشركات»، ١٥ نوفمبر) ──────────────────────────────────────────────────────────────
  // الخادم: PUT/DELETE /api/v2/subscribers/:idx/message-exclusion — المعالج نفسه، والرقم من المسار. في «كل الشركات» يوجّهه جدول
  // التوجيه لشركة الصفّ بمرجع نافذة المشترك ([CompanyRefs] — 'message-exclusion')؛ فمن يناديه يغلّفه بشركة الصفّ (MergedOps.writeAt).

  /// رقم المشترك الصالح للمسار الموجَّه (أرقامٌ ١–١٢ كجدول الخادم) — وإلّا null (لا يُوجَّه: يُدار من صفحة الشركة).
  static String? routedIdx(String? idx) {
    final s = idx?.trim() ?? '';
    return RegExp(r'^\d{1,12}$').hasMatch(s) ? s : null;
  }

  /// حين لا رقم صالحاً لمشترك صفٍّ في «كل الشركات».
  static const String noRoutedIdx = 'تعذّر تحديد المشترك في شركته — افتح الشركة وحدها';

  static String _subPath(String idx) => '/api/v2/subscribers/${Uri.encodeComponent(idx)}/message-exclusion';

  /// [save] لمشتركٍ برقمه [idx] في شركة الصفّ — [groups] فارغة = إزالة الاستثناء.
  static Future<({bool ok, MxEntry? entry, String? message})> saveAt(
    String idx,
    MxSubject subject, {
    required List<String> groups,
    String note = '',
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(_subPath(idx), data: {
        ...subject.toJson(),
        'groups': groups,
        'note': note.trim(),
      });
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, entry: null, message: b['message']?.toString() ?? 'تعذّر الحفظ');
      return (ok: true, entry: MxEntry.fromJson(subject.username, b['exclusion']), message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusion PUT: $e');
      return (ok: false, entry: null, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  /// [remove] لمشتركٍ برقمه [idx] في شركة الصفّ — تعود الرسائل تصله.
  static Future<({bool ok, String? message})> removeAt(String idx, String username) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(_subPath(idx), queryParameters: {'username': username});
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, message: b['message']?.toString() ?? 'تعذّر الحفظ');
      return (ok: true, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusion DELETE: $e');
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  /// الجماعيّ: إيقافٌ ([add] true، بـ[groups]) أو سماحٌ ([add] false) لعدّة مشتركين — [bulkMax] في الطلب. ⇒ done: كم نُفّذ.
  static Future<({bool ok, int done, String? message})> bulk({
    required bool add,
    required List<MxSubject> items,
    List<String> groups = const [],
    String note = '',
  }) async {
    var done = 0;
    try {
      for (var i = 0; i < items.length; i += bulkMax) {
        final part = items.sublist(i, i + bulkMax > items.length ? items.length : i + bulkMax);
        final r = await ApiClient.dio.post<Map<String, dynamic>>(bulkPath, data: {
          'action': add ? 'add' : 'remove',
          'items': [for (final s in part) s.toJson()],
          if (add) 'groups': groups,
          if (add) 'note': note.trim(),
        });
        final b = r.data ?? const {};
        if (b['success'] != true) return (ok: false, done: done, message: b['message']?.toString() ?? 'تعذّر الحفظ');
        final d = b['done'];
        done += d is num ? d.toInt() : 0;
      }
      return (ok: true, done: done, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-exclusions bulk: $e');
      return (ok: false, done: done, message: _msg(e, 'تعذّر الحفظ'));
    }
  }
}

/// حال قائمة المستثنين: تُقرأ مرّةً وتتشاركها القائمة (الشارة) ولوحة المشترك وصفحة «المستثنون من الرسائل».
///
/// * الصفحة المفتوحة: [snapshot] (null = لم تُقرأ بعد) — كلّ قراءةٍ وكتابة لها صراحةً ([CompanyRoute.runOpen]) فلا تأخذ وجهة قسمٍ
///   في «كل الشركات».
/// * «كل الشركات» (١٥ نوفمبر): [companies] — قائمة كلّ شركةٍ بمفتاحها، تُقرأ بطلبها الموجَّه ([CompanyRoute.run])؛ صفوف الوضع كلّها
///   تحمل مفتاح شركتها (والمفتوحة منها). الكتابة لمشترك صفٍّ ليست هنا: شاشته تنادي [MessageExclusionsApi.saveAt]/[removeAt] بغلاف
///   شركة الصفّ ثمّ [applySavedFor] — كبقيّة كتابات المشترك (والحارس الثابت يفحص غلافها عند الموضع نفسه).
class MessageExclusionsState {
  MessageExclusionsState._();

  static final ValueNotifier<MxSnapshot?> snapshot = ValueNotifier<MxSnapshot?>(null);

  /// «كل الشركات»: ما قُرئ من قوائم الشركات — مفتاح الشركة ⇒ قائمتها. شركةٌ غائبة = لم تُقرأ بعد (أو تعذّرت): لا علامة ولا زرّ.
  static final ValueNotifier<Map<String, MxSnapshot>> companies = ValueNotifier<Map<String, MxSnapshot>>(const {});

  /// يتغيّر مع أيٍّ منهما — لما يرسم من الاثنين (القائمة المدموجة، صفحة المشترك، صفحة «المستثنون»).
  static final Listenable changes = Listenable.merge([snapshot, companies]);

  static const Duration ttl = Duration(seconds: 60);
  static const Duration _cooldown = Duration(seconds: 20);

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static final Map<String, DateTime> _coFetchedAt = {};
  static final Map<String, DateTime> _coFailedAt = {};
  static final Map<String, Future<void>> _coInflight = {};

  static bool get enabled => snapshot.value?.enabled ?? false;
  static bool get canManage => enabled && (snapshot.value?.canManage ?? false);
  static MxEntry? of(String? username) => snapshot.value?.of(username);

  /// قائمة شركة الصفّ: [key] مفتاح شركته في «كل الشركات»، وnull ⇒ الصفحة المفتوحة.
  static MxSnapshot? snapshotFor(String? key) => key == null ? snapshot.value : companies.value[key];
  static bool enabledFor(String? key) => snapshotFor(key)?.enabled ?? false;
  static bool canManageFor(String? key) {
    final s = snapshotFor(key);
    return s != null && s.enabled && s.canManage;
  }

  /// مستثنى الصفّ في شركته ([key] null ⇒ المفتوحة) — null: ليس مستثنى، أو قائمة شركته لم تُقرأ.
  static MxEntry? ofRow(String? key, String? username) => snapshotFor(key)?.of(username);

  /// ما يُعرض في «الإعدادات» وصفحة «المستثنون»: [keys] null (الوضع العاديّ) ⇒ الصفحة المفتوحة وحدها (مفتاحها null)؛ وإلّا
  /// («كل الشركات») ما قُرئ من قوائم تلك الشركات بترتيبها — كلٌّ بمفتاحه. الشاشة تمرّر شركاتها (الطبقة هنا لا تقرأ الوضع).
  static List<({String? key, MxSnapshot snap})> viewFor(Iterable<String>? keys) => keys == null
      ? [if (snapshot.value case final MxSnapshot s) (key: null, snap: s)]
      : [
          for (final k in keys)
            if (companies.value[k] case final MxSnapshot s) (key: k, snap: s),
        ];

  /// يقرأ القائمة إن قدُمت (أو [force]). تعذّرٌ لا يمحو آخر قراءة، ويُعاد بعد مهلةٍ قصيرة.
  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    final now = DateTime.now();
    if (!force) {
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = CompanyRoute.runOpen(() => _fetch(epoch)).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  static Future<void> _fetch(int epoch) async {
    final r = await MessageExclusionsApi.all();
    if (epoch != _epoch) return; // خرج المدير أو تبدّلت الشركة أثناء الطلب
    if (!r.ok || r.snapshot == null) {
      _failedAt = DateTime.now();
      return;
    }
    _failedAt = null;
    _fetchedAt = DateTime.now();
    snapshot.value = r.snapshot;
  }

  /// [ensureFresh] لشركة صفّ: [key] null ⇒ الصفحة المفتوحة؛ وإلّا قائمة تلك الشركة بطلبها الموجَّه (مفتاحٌ غير صالح ⇒ لا طلب).
  static Future<void> ensureFreshFor(String? key, {bool force = false}) {
    if (key == null) return ensureFresh(force: force);
    if (!CompanyRoute.keyRe.hasMatch(key)) return Future<void>.value();
    final running = _coInflight[key];
    if (running != null) return running;
    final now = DateTime.now();
    if (!force) {
      final at = _coFetchedAt[key];
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _coFailedAt[key];
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = CompanyRoute.run(key, () => _fetchFor(key, epoch)).whenComplete(() {
      if (identical(_coInflight[key], run)) {
        // إزالةٌ بجسمٍ لا بسهم: remove تُرجع المستقبل نفسه، وإرجاعه من whenComplete يجعله ينتظر نفسه
        _coInflight.remove(key);
      }
    });
    _coInflight[key] = run;
    return run;
  }

  static Future<void> _fetchFor(String key, int epoch) async {
    final r = await MessageExclusionsApi.all();
    if (epoch != _epoch) return;
    if (!r.ok || r.snapshot == null) {
      _coFailedAt[key] = DateTime.now();
      return;
    }
    _coFailedAt.remove(key);
    _coFetchedAt[key] = DateTime.now();
    companies.value = {...companies.value, key: r.snapshot!};
  }

  /// «كل الشركات»: قوائم عدّة شركاتٍ معاً (كلٌّ بمدّته) — للقائمة المدموجة وصفحة «المستثنون».
  static Future<void> ensureCompanies(Iterable<String> keys, {bool force = false}) =>
      Future.wait([for (final k in keys.toSet()) ensureFreshFor(k, force: force)]);

  /// بعد حفظٍ أو إزالةٍ ناجحة لمشتركٍ واحد — الشاشات المستمعة ترسم فوراً.
  static void applySaved(String username, MxEntry? entry) {
    final cur = snapshot.value;
    if (cur == null || !cur.enabled) return;
    snapshot.value = cur.withEntry(username, entry);
  }

  /// [applySaved] لشركة الصفّ ([key] null ⇒ المفتوحة). الشركة المفتوحة قد تُعرض بمفتاحها أيضاً («كل الشركات»): قائمتها بلا مفتاح
  /// تُقرأ من جديد عند أوّل طلب، فلا تبقى بما قبل الحفظ.
  static void applySavedFor(String? key, String username, MxEntry? entry) {
    if (key == null) {
      applySaved(username, entry);
      return;
    }
    final cur = companies.value[key];
    if (cur != null && cur.enabled) companies.value = {...companies.value, key: cur.withEntry(username, entry)};
    _fetchedAt = null;
  }

  /// حفظٌ للشركة المفتوحة ثمّ تحديث الحال. ⇒ نتيجة [MessageExclusionsApi.save].
  static Future<({bool ok, MxEntry? entry, String? message})> save(
    MxSubject subject, {
    required List<String> groups,
    String note = '',
  }) async {
    final r = await CompanyRoute.runOpen(() => MessageExclusionsApi.save(subject, groups: groups, note: note));
    if (r.ok) applySaved(subject.username, r.entry);
    return r;
  }

  static Future<({bool ok, String? message})> remove(String username) async {
    final r = await CompanyRoute.runOpen(() => MessageExclusionsApi.remove(username));
    if (r.ok) applySaved(username, null);
    return r;
  }

  static Future<({bool ok, int done, String? message})> bulk({
    required bool add,
    required List<MxSubject> items,
    List<String> groups = const [],
    String note = '',
  }) async {
    final r = await CompanyRoute.runOpen(() => MessageExclusionsApi.bulk(add: add, items: items, groups: groups, note: note));
    // ما نُفّذ (ولو جزئيّاً) يُقرأ من الخادم — القائمة مصدرها هو
    await ensureFresh(force: true);
    return r;
  }

  /// خروجٌ أو تبديل شركة: لا يرى المدير التالي مستثني سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    _coFetchedAt.clear();
    _coFailedAt.clear();
    _coInflight.clear();
    snapshot.value = null;
    companies.value = const {};
  }
}
