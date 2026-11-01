import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'national_portal_api.dart';

/// أقسام البوّابة الباقية في التطبيق — الجزء الأوّل (المشروع الوطنيّ، ١ نوفمبر؛ المالك: «اقسام البوابة البقية افضل تمضي بيها
/// وتكملها»): ما يخصّ المشترك الواحد في صفحته (محفظته، سجلّ أخطاء اشتراكه، تذاكره، مهامّه، جلساته السابقة) وتفاصيل المهمّة
/// وتعليقاتها وتعليقات الطلب، والتعليق عليهما. عقد الخادم: `release_work/national_rest/contract.md` §1–§3 و§6
/// (`server/watani/wataniPortalBeta.js`)، خلف مفتاح الحساب لأقسام البوّابة (`watani_sections` — `lookups.beta`؛ «تبديل الباقة» بقيت
/// على `watani_beta`) — مطفأٌ ⇒ لا شيء من هذا يظهر.
///
/// القراءة بكاش الخادم (الجلب الأوّل قد يردّ `pending` ⇒ اسأل بعد ٤ث). «لا صلاحيّة في البوّابة» ردٌّ ناجح بعلم `locked` (عنوانٌ
/// وسبب) يُعرض قفلاً بمكانه — لا خطأ ولا قائمة فارغة. الكتابة (التعليق) خلف مفتاح الكتابة (`watani_portal`) أيضاً: نداءٌ واحد،
/// لا إعادة تلقائيّة أبداً، و«غير مؤكَّد» يُعرض كما هو. لا هواتف ولا وثائق: ما لا يُعرف يبقى null («—»)، لا صفرٌ كاذب.

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? ''));
num? _num(dynamic v) => v is num ? v : (v == null ? null : num.tryParse(v.toString()));
String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

/// قفلٌ من البوّابة: مستخدم الوطني الذي دخل به الحساب لا يملك صلاحيّة القسم (أو المفتاح التجريبيّ أُطفئ). يُعرض بمكانه.
class NationalLock {
  const NationalLock({this.title = 'لا صلاحيّة في البوّابة', required this.message});
  final String title;
  final String message;

  static const _fallback = 'المستخدم الذي دخلت به في المشروع الوطني لا يملك صلاحيّة هذا القسم في البوّابة';

  /// من ردّ الخادم (`locked:true` + title/message)، أو null.
  static NationalLock? of(dynamic b) {
    if (b is! Map) return null;
    if (b['locked'] == true) return NationalLock(title: _sn(b['title']) ?? 'لا صلاحيّة في البوّابة', message: _sn(b['message']) ?? _fallback);
    if (b['code'] == 'BETA_OFF') {
      return NationalLock(title: 'قسمٌ تجريبيّ', message: _sn(b['message']) ?? 'هذا القسم تجريبيّ ولم يُفتح لحسابك بعد — سيُفتح قريباً');
    }
    return null;
  }
}

/// نتيجة قراءة قسمٍ من البوّابة: البيانات، أو قفلٌ ([lock] — بمكانه بسببه)، أو سبب الفشل (إعادة المحاولة).
class NationalSheetResult<T> {
  const NationalSheetResult.ok(this.data)
      : error = null,
        code = null,
        lock = null,
        relogin = false;
  const NationalSheetResult.locked(NationalLock this.lock)
      : data = null,
        error = null,
        code = null,
        relogin = false;
  const NationalSheetResult.fail(this.error, {this.code, this.relogin = false})
      : data = null,
        lock = null;
  final T? data;
  final String? error;
  final String? code;
  final NationalLock? lock;
  final bool relogin;
  bool get ok => error == null && lock == null;
  bool get locked => lock != null;
}

/// «سجلّ الأخطاء» — رفضُ دخولٍ أو خطأ جلسةٍ سجّلته البوّابة لهذا الاشتراك (§3.2).
class NationalErrorRow {
  const NationalErrorRow({this.at, required this.message, this.username});
  final String? at;
  final String message;

  /// اسم الجهاز الذي سُجّل عليه الخطأ.
  final String? username;

  static NationalErrorRow fromJson(Map<String, dynamic> j) =>
      NationalErrorRow(at: _sn(j['at']), message: _s(j['message']), username: _sn(j['username']));
}

/// جلسةٌ من سجلّ جلسات الاشتراك (§3.3، الأحدث أوّلاً).
class NationalSessionRow {
  const NationalSessionRow({this.startedAt, this.seconds, this.ip, this.mac, this.status = '', this.down, this.up});
  final String? startedAt;
  final int? seconds;
  final String? ip;
  final String? mac;
  final String status;
  final int? down;
  final int? up;

  /// الجلسة الجارية الآن (حالها «متصل»: Online، أو رقمها في البوّابة 0).
  bool get live {
    final s = status.toLowerCase();
    return s == 'online' || s == 'active' || s == '0' || s == 'متصل';
  }

  static NationalSessionRow fromJson(Map<String, dynamic> j) {
    final st = j['status'];
    return NationalSessionRow(
      startedAt: _sn(j['started_at']),
      seconds: _int(j['duration_s']),
      ip: _sn(j['ip']),
      mac: _sn(j['mac']),
      status: _s(st is Map ? (st['name'] ?? st['id'] ?? st['displayValue']) : st),
      down: _int(j['down']),
      up: _int(j['up']),
    );
  }
}

/// مهمّةٌ من مهامّ المشترك (§3.5 — مرجعٌ: رقمها وعنوانها؛ التفاصيل بـ[NationalSheetApi.task]).
class NationalTaskRef {
  const NationalTaskRef(this.id, this.title);
  final String? id;
  final String title;

  static NationalTaskRef fromJson(Map<String, dynamic> j) => NationalTaskRef(_sn(j['id']), _s(j['title']));
}

/// محفظة المشترك (§3.1): رصيدها والائتمان — null = تعذّرت قراءته (لا صفر)، و[locked] = البوّابة لا تُري الرصيد لهذا المستخدم.
class NationalCustomerBalance {
  const NationalCustomerBalance({this.balance, this.credit, this.currency = 'IQD', this.locked = false});
  final num? balance;
  final num? credit;
  final String currency;
  final bool locked;

  static NationalCustomerBalance fromRaw(Map<String, dynamic> raw) {
    final b = raw['balance'];
    final locked = raw['balance_locked'] == true;
    if (b is Map) {
      return NationalCustomerBalance(balance: _num(b['balance']), credit: _num(b['credit']), currency: _sn(b['currency']) ?? 'IQD', locked: locked);
    }
    return NationalCustomerBalance(locked: locked);
  }
}

/// تفاصيل مهمّة (§6.1) مع تعليقاتها وما يُسمح به من هنا.
class NationalTaskDetail {
  const NationalTaskDetail({
    this.id,
    required this.title,
    this.type = '',
    required this.status,
    this.description,
    this.createdAt,
    this.modifiedAt,
    this.closedAt,
    this.customer,
    this.zone,
    this.address,
    this.lineOfBusiness,
    this.requestId,
    this.ticket,
    this.comments,
    this.commentsTotal,
    this.commentsLocked = false,
    this.canComment = false,
  });
  final String? id;
  final String title;

  /// `connect customer` · `sign contract` · `maintenance` · غيره.
  final String type;

  /// `not started` · `in progress` · `completed` · `canceled`.
  final String status;
  final String? description;
  final String? createdAt;
  final String? modifiedAt;
  final String? closedAt;
  final NationalRef? customer;
  final NationalRef? zone;
  final String? address;
  final String? lineOfBusiness;
  final String? requestId;

  /// التذكرة المرتبطة — null بلا تذكرة.
  final NationalRef? ticket;

  /// null = لم تُجلب: مقفلةٌ ([commentsLocked]) أو تعذّر جلبها الآن (لا «لا تعليقات» كاذبة).
  final List<NationalComment>? comments;
  final int? commentsTotal;
  final bool commentsLocked;
  final bool canComment;

  /// اسم المهمّة بالعربيّ: من نوعها، وإلّا عنوانها.
  String get label => type.isNotEmpty ? type : title;

  static NationalTaskDetail fromJson(Map<String, dynamic> j) {
    final cs = j['comments'];
    final can = j['can'] is Map ? j['can'] as Map : const {};
    return NationalTaskDetail(
      id: _sn(j['id']),
      title: _s(j['title']),
      type: _s(j['type']),
      status: _s(j['status']),
      description: _sn(j['description']),
      createdAt: _sn(j['created_at']),
      modifiedAt: _sn(j['modified_at']),
      closedAt: _sn(j['closed_at']),
      customer: NationalRef.from(j['customer']),
      zone: NationalRef.from(j['zone']),
      address: _sn(j['address']),
      lineOfBusiness: _sn(j['line_of_business']),
      requestId: _sn(j['request_id']),
      ticket: NationalRef.from(j['ticket']),
      comments: cs is List ? cs.whereType<Map>().map(nationalCommentOf).toList() : null,
      commentsTotal: _int(j['comments_total']),
      commentsLocked: j['comments_locked'] == true,
      canComment: can['comment'] == true,
    );
  }
}

/// تعليقٌ من ردّ الخادم (CommentRow: {id, text, by, by_type, at}).
NationalComment nationalCommentOf(Map c) => NationalComment(_s(c['text']), _s(c['by']), _sn(c['at']));

/// ما يقوله الخادم عن الأقسام التجريبيّة لهذا الحساب (§2): مفتوحةٌ أم لا، وأقفال البوّابة الجاهزة بأسبابها.
class NationalBeta {
  const NationalBeta({required this.on, this.caps, this.locks = const {}, this.canWrite = false, this.refused = false});
  final bool on;

  /// موظّفٌ رفض الخادم سؤاله (403 PERMISSION_DENIED — لا يملك أيّ مفتاحٍ يقرأ به `lookups`، القرار ٤ في ١ نوفمبر): لا نعرف أهي مفتوحة،
  /// والأقسام تبقى بمكانها **مقفلةً بمفاتيحه** لا مخفيّة (الموظّف يرى ما لا يملكه مقفلاً).
  final bool refused;

  /// تُعرض الأقسام (مفتوحةً أو مقفلةً بمكانها).
  bool get shown => on || refused;

  /// null = لم تُعرف بعد (لا قفل على المجهول).
  final Map<String, bool>? caps;

  /// القسم ⇒ سبب القفل بالعربيّ (null أو غائب = متاحٌ أو لا يُعرف).
  final Map<String, String> locks;
  final bool canWrite;

  /// سبب قفل القسم من البوّابة، أو null.
  String? lockOf(String section) => locks[section];

  static NationalBeta fromJson(Map<String, dynamic> j) {
    final caps = j['caps'];
    final locks = j['portal_locks'];
    return NationalBeta(
      on: j['beta'] == true,
      caps: caps is Map ? {for (final e in caps.entries) e.key.toString(): e.value == true} : null,
      locks: locks is Map
          ? {
              for (final e in locks.entries)
                if (_sn(e.value) != null) e.key.toString(): _s(e.value),
            }
          : const {},
      canWrite: j['can_write'] == true,
    );
  }
}

class NationalSheetApi {
  NationalSheetApi._();

  /* ───────────── أدوات ───────────── */

  static Map<String, dynamic> _q(Map<String, Object?> m) =>
      {for (final e in m.entries) if (e.value != null && e.value.toString().isNotEmpty) e.key: e.value};

  static Future<NationalSheetResult<Map<String, dynamic>>> _get(String path, [Map<String, Object?> query = const {}]) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path, queryParameters: _q(query));
      final b = r.data ?? const {};
      final lock = NationalLock.of(b);
      if (lock != null) return NationalSheetResult.locked(lock);
      if (b['success'] != true) return NationalSheetResult.fail(_msg(b), code: _sn(b['code']));
      return NationalSheetResult.ok(b);
    } on DioException catch (e) {
      final b = e.response?.data;
      if (!kReleaseMode) debugPrint('🔴 $path: ${e.response?.statusCode}');
      final lock = NationalLock.of(b);
      if (lock != null) return NationalSheetResult.locked(lock);
      final code = b is Map ? _sn(b['code']) : null;
      return NationalSheetResult.fail(_msg(b), code: code, relogin: code == 'FTTH_RELOGIN' || code == 'PROVIDER_RELOGIN');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: $e');
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  static String _msg(dynamic b) {
    final m = b is Map ? b['message']?.toString().trim() : null;
    return (m != null && m.isNotEmpty && m.length < 200) ? m : 'تعذّر جلب البيانات من بوّابة المشروع الوطني';
  }

  static NationalPage<T> _page<T>(Map<String, dynamic> b, T Function(Map<String, dynamic>) map) => NationalPage<T>(
        items: (b['data'] is List ? b['data'] as List : const [])
            .whereType<Map>()
            .map((m) => map(Map<String, dynamic>.from(m)))
            .toList(),
        total: _int(b['total']),
        page: _int(b['page']) ?? 1,
        pageCount: _int(b['page_count']),
        pending: b['pending'] == true,
        stale: b['stale'] == true,
        fetchedAt: _sn(b['fetched_at']),
        raw: b,
      );

  static Future<NationalSheetResult<NationalPage<T>>> _list<T>(
    String path,
    Map<String, Object?> query,
    T Function(Map<String, dynamic>) map,
  ) async {
    final r = await _get(path, query);
    if (r.locked) return NationalSheetResult.locked(r.lock!);
    if (!r.ok) return NationalSheetResult.fail(r.error, code: r.code, relogin: r.relogin);
    return NationalSheetResult.ok(_page(r.data!, map));
  }

  static String _sub(String sid) => '/api/v2/ftth/subscriptions/${Uri.encodeComponent(sid)}';

  /* ───────────── الأقسام التجريبيّة لهذا الحساب ───────────── */

  static const _betaTtl = Duration(minutes: 5);
  static NationalBeta? _beta;
  static String? _betaOwner;
  static DateTime? _betaAt;
  static Future<NationalBeta?>? _betaInflight;

  /// مفتوحةٌ لهذا الحساب؟ (+ أقفال البوّابة) — من `lookups` (§2)، ذاكرةٌ لخمس دقائق لكلّ حساب فصفحة المشترك لا تسأل كلّ مرّة.
  /// null = تعذّر السؤال الآن (لا يُعرض شيء).
  static Future<NationalBeta?> beta({bool force = false}) async {
    final owner = await AuthStorage.readAdminId();
    final at = _betaAt;
    if (!force && _beta != null && owner == _betaOwner && at != null && DateTime.now().difference(at) < _betaTtl) return _beta;
    final running = _betaInflight;
    if (running != null && owner == _betaOwner) return running;
    _betaOwner = owner;
    final run = () async {
      final r = await _get('/api/v2/ftth/lookups');
      // موظّفٌ بلا مفتاحٍ يقرأ به (403 PERMISSION_DENIED): الأقسام بمكانها مقفلةً لا مخفيّة — جوابٌ يُحفظ كغيره (لا يُسأل كلّ مرّة)
      final NationalBeta? b = r.code == 'PERMISSION_DENIED'
          ? const NationalBeta(on: false, refused: true)
          : (!r.ok || r.data!['data'] is! Map)
              ? null
              : NationalBeta.fromJson(Map<String, dynamic>.from(r.data!['data'] as Map));
      if (b == null) return null;
      if (owner == _betaOwner) {
        _beta = b;
        _betaAt = DateTime.now();
      }
      return b;
    }();
    _betaInflight = run;
    try {
      return await run;
    } finally {
      if (identical(_betaInflight, run)) _betaInflight = null;
    }
  }

  /// للاختبار: ينسى ما عرف.
  @visibleForTesting
  static void debugReset() {
    _beta = null;
    _betaAt = null;
    _betaOwner = null;
    _betaInflight = null;
  }

  /* ───────────── صفحة المشترك (S1، §3) ───────────── */

  /// صفحة المشترك تعرض قليلاً في المرّة (الخادم يقبل ١٠ أو ٢٥).
  static const sheetPageSize = 10;

  /// محفظة المشترك: رصيدها ([NationalCustomerBalance.fromRaw] من `raw`) وآخر حركاتها (صفّ «محفظتي» نفسه).
  static Future<NationalSheetResult<NationalPage<NationalMoneyRow>>> wallet(String sid, {int page = 1}) =>
      _list('${_sub(sid)}/wallet', {'page': page, 'size': sheetPageSize}, NationalMoneyRow.fromJson);

  static Future<NationalSheetResult<NationalPage<NationalErrorRow>>> errors(String sid, {int page = 1}) =>
      _list('${_sub(sid)}/errors', {'page': page, 'size': sheetPageSize}, NationalErrorRow.fromJson);

  static Future<NationalSheetResult<NationalPage<NationalTicket>>> tickets(String sid, {int page = 1}) =>
      _list('${_sub(sid)}/tickets', {'page': page, 'size': sheetPageSize}, NationalTicket.fromJson);

  static Future<NationalSheetResult<NationalPage<NationalTaskRef>>> tasks(String sid, {int page = 1}) =>
      _list('${_sub(sid)}/tasks', {'page': page, 'size': sheetPageSize}, NationalTaskRef.fromJson);

  static Future<NationalSheetResult<NationalPage<NationalSessionRow>>> sessions(String sid, {int page = 1}) =>
      _list('${_sub(sid)}/sessions', {'page': page, 'size': sheetPageSize}, NationalSessionRow.fromJson);

  /* ───────────── المهمّة والطلب (S4، §6) ───────────── */

  /// مهمّةٌ واحدة — null داخل ok = pending (اسأل ثانيةً).
  static Future<NationalSheetResult<NationalTaskDetail?>> task(String id) async {
    final r = await _get('/api/v2/ftth/tasks/${Uri.encodeComponent(id)}');
    if (r.locked) return NationalSheetResult.locked(r.lock!);
    if (!r.ok) return NationalSheetResult.fail(r.error, code: r.code, relogin: r.relogin);
    if (r.data!['pending'] == true || r.data!['data'] is! Map) return const NationalSheetResult.ok(null);
    return NationalSheetResult.ok(NationalTaskDetail.fromJson(Map<String, dynamic>.from(r.data!['data'] as Map)));
  }

  /// تعليقات طلب — بطيئةٌ عند البوّابة (~٩ث) فالأولى غالباً pending؛ `raw['can']['comment']` = التعليق مسموحٌ من هنا.
  static Future<NationalSheetResult<NationalPage<NationalComment>>> requestComments(String id, {int page = 1}) =>
      _list('/api/v2/ftth/requests/${Uri.encodeComponent(id)}/comments', {'page': page, 'size': sheetPageSize}, nationalCommentOf);

  static Future<NationalWrite> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(path, data: body);
      return writeOf(r.data);
    } on DioException catch (e) {
      final b = e.response?.data;
      if (!kReleaseMode) debugPrint('🔴 POST $path: ${e.response?.statusCode}');
      if (b is Map) return writeOf(b);
      // أُرسل ولم يصل الردّ (مهلة القراءة): ربّما كُتب — لا «فشل» ولا إعادة. أمّا تعذّر الاتّصال أصلاً فلم يُرسل شيء.
      if (e.type == DioExceptionType.receiveTimeout) {
        return const NationalWrite(NationalWriteState.unconfirmed,
            message: 'انقطع الاتّصال قبل الردّ — ربّما أُرسل التعليق، حدّث التعليقات قبل الإعادة', code: 'UNCONFIRMED');
      }
      return const NationalWrite(NationalWriteState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 POST $path: $e');
      return const NationalWrite(NationalWriteState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    }
  }

  /// ردّ الكتابة (§6.5) ⇒ نتيجتها: النجاح وحده `success:true` بلا `locked` (القفل ردٌّ ناجحٌ لم يُرسل شيئاً).
  @visibleForTesting
  static NationalWrite writeOf(dynamic b) {
    if (b is! Map) return const NationalWrite(NationalWriteState.failed, message: 'تعذّر التنفيذ — لم يتغيّر شيء');
    final lock = NationalLock.of(b);
    if (lock != null) return NationalWrite(NationalWriteState.failed, message: lock.message, code: b['code'] == 'BETA_OFF' ? 'BETA_OFF' : 'LOCKED');
    if (b['success'] == true) {
      return NationalWrite(NationalWriteState.ok, data: b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const {});
    }
    if (b['code'] == 'UNCONFIRMED') {
      return NationalWrite(NationalWriteState.unconfirmed,
          message: _sn(b['message']) ?? 'لم يتأكّد إرسال التعليق — حدّث التعليقات وتحقّق قبل إعادته', code: 'UNCONFIRMED');
    }
    final m = _s(b['message']);
    return NationalWrite(
      NationalWriteState.failed,
      message: m.isNotEmpty && m.length < 220 ? m : 'تعذّر التنفيذ — لم يتغيّر شيء',
      portalMessage: _sn(b['portal_message']),
      code: _sn(b['code']),
    );
  }

  /// تعليقٌ على مهمّة — نداءٌ واحد بلا إعادة (§6.2).
  static Future<NationalWrite> commentTask(String id, String text) =>
      _post('/api/v2/ftth/tasks/${Uri.encodeComponent(id)}/comments', {'text': text.trim()});

  /// تعليقٌ على طلب — نداءٌ واحد بلا إعادة (§6.4)؛ [type] نوع الطلب كما في صفّه (البوّابة تحتاجه).
  static Future<NationalWrite> commentRequest(String id, String type, String text) =>
      _post('/api/v2/ftth/requests/${Uri.encodeComponent(id)}/comments', {'text': text.trim(), 'type': type});
}
