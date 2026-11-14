import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'company_route.dart';

/// «المستثنون من الرسائل» (المالك ١٤ نوفمبر: «نسوي مثل القسم الريجكتد مسج، يعني ذولا ما تروح لهم رسائل… التفعيل، التنبيهات،
/// التذكير، التبليغات» ثمّ «تقسيم… نعم مستثنى»): على خادمنا وحده (`server/messageExclusions.js` — المسارات
/// `/api/v2/message-exclusions`). لكلّ مشترك «كلّ الرسائل» أو أنواعٌ منها، والخادم يحجبها عند كلّ باب إرسال — فالتطبيق يعرض ويحفظ
/// فقط. صفحة الحساب المفتوحة وحدها («كل الشركات» تُدار من صفحة الشركة). المفتاح مطفأ للحساب ⇒ enabled:false ⇒ لا شيء يُعرض.

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

/// حال قائمة المستثنين للجلسة المفتوحة: تُقرأ مرّةً وتتشاركها القائمة (الشارة) ولوحة المشترك وصفحة «المستثنون من الرسائل».
/// null = لم تُقرأ بعد. كلّ قراءةٍ وكتابة للشركة المفتوحة صراحةً ([CompanyRoute.runOpen]) — لا تأخذ وجهة قسمٍ في «كل الشركات».
class MessageExclusionsState {
  MessageExclusionsState._();

  static final ValueNotifier<MxSnapshot?> snapshot = ValueNotifier<MxSnapshot?>(null);

  static const Duration ttl = Duration(seconds: 60);
  static const Duration _cooldown = Duration(seconds: 20);

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static bool get enabled => snapshot.value?.enabled ?? false;
  static bool get canManage => enabled && (snapshot.value?.canManage ?? false);
  static MxEntry? of(String? username) => snapshot.value?.of(username);

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

  /// بعد حفظٍ أو إزالةٍ ناجحة لمشتركٍ واحد — الشاشات المستمعة ترسم فوراً.
  static void applySaved(String username, MxEntry? entry) {
    final cur = snapshot.value;
    if (cur == null || !cur.enabled) return;
    snapshot.value = cur.withEntry(username, entry);
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
    snapshot.value = null;
  }
}
