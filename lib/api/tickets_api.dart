import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/inbox_service.dart';
import '../services/provider_service.dart';
import 'api_client.dart';
import 'company_route.dart';

/// «التذاكر» (المالك ٩ نوفمبر — الخادم server/tickets.js): المشترك يفتح تذكرةً من تطبيقه (نوع المشكلة + نصّه) ووكيله وموظّفوه
/// بالصلاحيّة يردّون ويغيّرون حالها؛ إشعارٌ لكلّ طرفٍ بما فعله الآخر. لكلّ الشركات ما عدا الوطنيّ.
///   GET  /api/v2/portal/tickets/summary          ⇒ available · can_view · can_reply · scoped · counts {open, answered, closed, unread, total}
///   GET  /api/v2/portal/tickets?filter=&offset=&limit= ⇒ items · counts · has_more · next_offset
///   GET  /api/v2/portal/tickets/:id              ⇒ ticket · messages (تُعلَّم مقروءةً لطرف الوكيل)
///   POST /api/v2/portal/tickets/:id/reply        { body } ⇒ ticket · message
///   POST /api/v2/portal/tickets/:id/status       { status: in_progress|resolved|closed } ⇒ ticket · message
///   POST /api/v2/portal/tickets/:id/reopen       ⇒ ticket · message
/// الموظّف: tickets.view (القسم والإشعار) وtickets.reply (الردّ والحالة). المقيَّد بمديرٍ فرعيّ لا يأخذ القسم.

DateTime? _time(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
int _int(Object? v, [int def = 0]) => v is num ? v.round() : def;
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// فلاتر القائمة كما يفهمها الخادم.
enum TicketFilter { open, answered, closed, all }

/// نوع المشكلة كما يختاره المشترك — نصّ التطبيق نفسه (الخادم يرسل المفتاح).
String ticketCategoryLabel(String? key) => switch (key) {
      'internet' => 'انقطاع أو بطء',
      'account' => 'الاشتراك والدفع',
      'device' => 'الراوتر والجهاز',
      _ => 'أخرى',
    };

class TicketSubscriber {
  const TicketSubscriber({required this.idx, this.username, this.name});
  final String idx;
  final String? username;
  final String? name;

  /// اسمه وإلّا يوزره.
  String get title => (name ?? '').trim().isNotEmpty ? name!.trim() : (username ?? '#$idx');
}

class Ticket {
  const Ticket({
    required this.id,
    required this.status,
    required this.category,
    required this.subscriber,
    this.subject,
    this.unread = false,
    this.seenBySubscriber = true,
    this.messageCount = 0,
    this.lastAuthor,
    this.lastPreview,
    this.lastActivityAt,
    this.createdAt,
    this.closedAt,
    this.statusBy,
    this.canReply = false,
    this.canReopen = false,
    this.actions = const [],
    this.moved = false,
  });

  final int id;

  /// open · answered · in_progress · resolved · closed · cancelled
  final String status;

  /// internet · account · device · other
  final String category;
  final TicketSubscriber subscriber;
  final String? subject;

  /// كتب المشترك ولم يقرأ طرف الوكيل.
  final bool unread;

  /// قرأ المشترك آخر ما كتبه الوكيل.
  final bool seenBySubscriber;
  final int messageCount;

  /// subscriber · manager · employee
  final String? lastAuthor;
  final String? lastPreview;
  final DateTime? lastActivityAt;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final String? statusBy;
  final bool canReply;
  final bool canReopen;

  /// ما يضبطه الوكيل الآن: in_progress · resolved · closed
  final List<String> actions;

  /// انتقل المشترك لوكيلٍ آخر (أو تبدّل مديره المباشر) بعد فتحها — للقراءة وحدها (الخادم يردّ الكتابة TICKET_MOVED).
  final bool moved;

  bool get isFinal => status == 'closed' || status == 'cancelled';
  bool get waitingForAgent => status == 'open' || status == 'in_progress';

  static Ticket? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final status = _str(j['status']);
    final sub = j['subscriber'];
    final idx = sub is Map ? _str(sub['idx']) : null;
    if (id is! num || status == null || idx == null) return null;
    final acts = j['actions'];
    return Ticket(
      id: id.toInt(),
      status: status,
      category: _str(j['category']) ?? 'other',
      subscriber: TicketSubscriber(idx: idx, username: _str((sub as Map)['username']), name: _str(sub['name'])),
      subject: _str(j['subject']),
      unread: j['unread'] == true,
      seenBySubscriber: j['seen_by_subscriber'] != false,
      messageCount: _int(j['message_count']),
      lastAuthor: _str(j['last_author']),
      lastPreview: _str(j['last_preview']),
      lastActivityAt: _time(j['last_activity_at']),
      createdAt: _time(j['created_at']),
      closedAt: _time(j['closed_at']),
      statusBy: _str(j['status_by']),
      canReply: j['can_reply'] == true,
      canReopen: j['can_reopen'] == true,
      actions: acts is List ? acts.map((x) => x.toString()).toList() : const [],
      moved: j['moved'] == true,
    );
  }
}

class TicketMessage {
  const TicketMessage({required this.id, required this.side, this.author, this.kind = 'text', this.event, this.body, this.createdAt});
  final int id;

  /// subscriber · manager · employee · system
  final String side;

  /// من كتب من طرف الوكيل (المدير أو الموظّف باسمه).
  final String? author;

  /// text · event
  final String kind;

  /// in_progress · resolved · closed · reopened · cancelled
  final String? event;
  final String? body;
  final DateTime? createdAt;

  bool get isEvent => kind == 'event';
  bool get fromSubscriber => side == 'subscriber';

  static TicketMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! num) return null;
    return TicketMessage(
      id: id.toInt(),
      side: _str(j['side']) ?? 'system',
      author: _str(j['author']),
      kind: _str(j['kind']) ?? 'text',
      event: _str(j['event']),
      body: j['body']?.toString(),
      createdAt: _time(j['created_at']),
    );
  }
}

class TicketCounts {
  const TicketCounts({this.open = 0, this.answered = 0, this.closed = 0, this.unread = 0, this.total = 0});
  final int open;
  final int answered;
  final int closed;
  final int unread;
  final int total;

  static TicketCounts fromJson(Object? j) => j is Map
      ? TicketCounts(
          open: _int(j['open']),
          answered: _int(j['answered']),
          closed: _int(j['closed']),
          unread: _int(j['unread']),
          total: _int(j['total']),
        )
      : const TicketCounts();

  int of(TicketFilter f) => switch (f) {
        TicketFilter.open => open,
        TicketFilter.answered => answered,
        TicketFilter.closed => closed,
        TicketFilter.all => total,
      };
}

/// ما يملكه المستخدم من القسم — يُقرأ لكلّ مستخدمٍ للحساب (الموظّف بلا صلاحيّة يرى القسم مقفلاً لا مخفيّاً).
class TicketsAccess {
  const TicketsAccess({required this.available, this.canView = false, this.canReply = false, this.scoped = false, this.counts});

  /// المفتاح العامّ مفتوحٌ للحساب، وليس وطنيّاً.
  final bool available;
  final bool canView;
  final bool canReply;

  /// موظّفٌ مقيَّدٌ بمديرٍ فرعيّ — التذاكر من كلّ الحساب فلا يُفتح له القسم.
  final bool scoped;

  /// لمن يرى القسم وحده.
  final TicketCounts? counts;

  static const off = TicketsAccess(available: false);

  bool get on => available && canView;

  static TicketsAccess fromJson(Map j) => TicketsAccess(
        available: j['available'] == true,
        canView: j['can_view'] == true,
        canReply: j['can_reply'] == true,
        scoped: j['scoped'] == true,
        counts: j['counts'] is Map ? TicketCounts.fromJson(j['counts']) : null,
      );
}

class TicketsPage {
  const TicketsPage({required this.items, required this.counts, this.hasMore = false, this.nextOffset});
  final List<Ticket> items;
  final TicketCounts counts;
  final bool hasMore;
  final int? nextOffset;
}

class TicketThread {
  const TicketThread({required this.ticket, required this.messages});
  final Ticket ticket;
  final List<TicketMessage> messages;
}

typedef TicketWrite = ({bool ok, String? message, Ticket? ticket, TicketMessage? posted});

class TicketsApi {
  TicketsApi._();

  static const base = '/api/v2/portal/tickets';

  /// الوطنيّ (FTTH القديم والمشروع الوطنيّ على providerKit) بلا تذاكر — المالك ٩ نوفمبر: «للشركات كلها ما عدا الوطني».
  static bool get servedByProvider => !(ProviderService.isFtth || ProviderService.parentIsZone);

  static String? _msg(Object? data) => data is Map ? _str(data['message']) : null;

  /// null = تعذّر (شبكة/خادم)؛ [TicketsAccess.off] = غير متاحٍ لحسابه (أو خادمٌ أقدم بلا القسم).
  static Future<TicketsAccess?> summary() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    if (!servedByProvider) return TicketsAccess.off;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$base/summary');
      final d = r.data;
      if (r.statusCode == 200 && d != null && d['success'] == true) return TicketsAccess.fromJson(d);
      if (r.statusCode == 404) return TicketsAccess.off;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ tickets summary: $e');
    }
    return null;
  }

  /// null = تعذّر.
  static Future<TicketsPage?> list({TicketFilter filter = TicketFilter.open, int offset = 0, int limit = 30}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(base,
          queryParameters: {'filter': filter.name, 'offset': '$offset', 'limit': '$limit'});
      final d = r.data;
      if (r.statusCode == 200 && d != null && d['success'] == true) {
        final items = d['items'];
        final next = d['next_offset'];
        return TicketsPage(
          items: items is List ? items.map(Ticket.fromJson).whereType<Ticket>().toList() : const [],
          counts: TicketCounts.fromJson(d['counts']),
          hasMore: d['has_more'] == true,
          nextOffset: next is num ? next.toInt() : null,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ tickets list: $e');
    }
    return null;
  }

  /// thread = المحادثة؛ gone = لم تعد لهذا الحساب (٤٠٤/٤٠٣)؛ كلاهما null/false = تعذّر.
  static Future<({TicketThread? thread, bool gone, String? message})> thread(int id) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('$base/$id');
      final d = r.data;
      final t = Ticket.fromJson(d?['ticket']);
      if (r.statusCode == 200 && d?['success'] == true && t != null) {
        final ms = d?['messages'];
        return (
          thread: TicketThread(
              ticket: t, messages: ms is List ? ms.map(TicketMessage.fromJson).whereType<TicketMessage>().toList() : const []),
          gone: false,
          message: null,
        );
      }
      if (r.statusCode == 404 || r.statusCode == 403) return (thread: null, gone: true, message: _msg(d));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ tickets thread: $e');
    }
    return (thread: null, gone: false, message: null);
  }

  static Future<TicketWrite> _write(String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(path, data: body);
      final d = r.data;
      final t = Ticket.fromJson(d?['ticket']);
      final m = TicketMessage.fromJson(d?['message']);
      if (r.statusCode == 200 && d?['success'] == true) return (ok: true, message: null, ticket: t, posted: m);
      return (ok: false, message: _msg(d) ?? 'تعذّر الآن — حاول مرّة ثانية', ticket: t, posted: null);
    } catch (e) {
      return (
        ok: false,
        message: e is DioException ? _msg(e.response?.data) ?? 'تعذّر الاتصال' : 'تعذّر الآن',
        ticket: null,
        posted: null,
      );
    }
  }

  static Future<TicketWrite> reply(int id, String body) => _write('$base/$id/reply', {'body': body});

  /// in_progress · resolved · closed
  static Future<TicketWrite> setStatus(int id, String status) => _write('$base/$id/status', {'status': status});

  static Future<TicketWrite> reopen(int id) => _write('$base/$id/reopen', const {});
}

/// حال «التذاكر» للجلسة — شارة «قوائم أخرى» وقائمة الحاسبة الجانبيّة يستمعان له. يُقرأ عند أوّل مستمع، وعند العودة للتطبيق،
/// وحين يصل إشعار تذكرة (FCM أو تغذية الحاسبة — كلاهما يمرّ بصندوق الإشعارات)، وبعد كلّ إجراء. للشركة المفتوحة دائماً.
class TicketsState {
  TicketsState._();

  /// null = لم يُعرف بعد.
  static final ValueNotifier<TicketsAccess?> gate = _TicketsGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;
  static String? _lastInboxId;

  static const ttl = Duration(minutes: 2);
  static const _cooldown = Duration(seconds: 20);

  static bool get on => gate.value?.on ?? false;

  /// غير المقروءة لطرف الوكيل (الشارة).
  static int get unread => on ? gate.value!.counts?.unread ?? 0 : 0;

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    final now = DateTime.now();
    if (!force) {
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
    }
    final failed = _failedAt;
    if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    final epoch = _epoch;
    late final Future<void> run;
    run = CompanyRoute.runOpen(() => _fetch(epoch)).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  static Future<void> _fetch(int epoch) async {
    final a = await TicketsApi.summary();
    if (epoch != _epoch) return;
    if (a == null) {
      _failedAt = DateTime.now();
      return;
    }
    _fetchedAt = DateTime.now();
    _failedAt = null;
    gate.value = a;
  }

  /// العودة للتطبيق: إشعارٌ وصل والتطبيق بالخلفيّة لم يمرّ هنا — يُقرأ ثانيةً (بمهلةٍ قصيرة لا كلّ رجوع).
  static Future<void> onResume() {
    final at = _fetchedAt;
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 20)) return Future<void>.value();
    return ensureFresh(force: true);
  }

  /// صندوق الإشعارات تغيّر: إشعار تذكرةٍ لم نره ⇒ الشارة من جديد.
  static void onInboxChanged() {
    String? id;
    for (final x in InboxService.all) {
      if (x.data['type'] == 'portal_ticket') {
        id = x.id;
        break;
      }
    }
    if (id == null || id == _lastInboxId) return;
    final first = _lastInboxId == null;
    _lastInboxId = id;
    // أوّل قراءةٍ للصندوق تعرّفنا بآخر إشعارٍ قائم ولا تعني تذكرةً جديدة — إلّا والحال معروفٌ أصلاً.
    if (first && gate.value == null) return;
    unawaited(ensureFresh(force: true));
  }

  /// تبديل الجلسة: لا يرى المدير التالي تذاكر سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(TicketsAccess? a) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = a == null ? null : DateTime.now();
    gate.value = a;
  }

  @visibleForTesting
  static void debugResetInbox() => _lastInboxId = null;
}

class _TicketsGate extends ValueNotifier<TicketsAccess?> {
  _TicketsGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(TicketsState.ensureFresh);
  }
}
