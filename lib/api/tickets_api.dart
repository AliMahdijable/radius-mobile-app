import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import '../services/inbox_service.dart';
import '../services/permissions_service.dart';
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
///   GET  /api/v2/portal/tickets/:id/messages/:mid/image ⇒ بايتات صورة الرسالة (موثَّقٌ بملكيّة المحادثة؛ ٤١٠ بعد حذفها)
/// الصور (٩ نوفمبر): الردّ يحمل `image` (JPEG مضغوطاً بـdata URL) والنصّ اختياريٌّ معها.
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
    this.imageCount = 0,
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

  /// صورٌ أُرفقت بالتذكرة (الحدّ ٢٠ — الخادم يردّ ما فوقه TICKET_IMAGES_FULL).
  final int imageCount;

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
      imageCount: _int(j['image_count']),
    );
  }
}

/// صورة رسالة (٩ نوفمبر): تُجلب بمسارها الموثَّق ([TicketsApi.imageBytes]) — لا رابط عامّ. available=false بعد حذفها (٣ أشهر من فتح التذكرة
/// بعد انتهاء التذكرة).
class TicketImage {
  const TicketImage({required this.available, this.mime, this.width, this.height, this.bytes});
  final bool available;
  final String? mime;
  final int? width;
  final int? height;
  final int? bytes;

  /// نسبة العرض للارتفاع — مكان الصورة قبل وصول بايتاتها.
  double get aspect => (width ?? 0) > 0 && (height ?? 0) > 0 ? (width! / height!).clamp(0.4, 2.5) : 4 / 3;

  static TicketImage? fromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? v) => v is num && v > 0 ? v.round() : null;
    return TicketImage(
        available: j['available'] == true, mime: _str(j['mime']), width: n(j['width']), height: n(j['height']), bytes: n(j['bytes']));
  }
}

class TicketMessage {
  const TicketMessage(
      {required this.id, required this.side, this.author, this.kind = 'text', this.event, this.body, this.image, this.createdAt});
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

  /// صورة الرسالة إن كانت (نصّها قد يكون فارغاً معها).
  final TicketImage? image;
  final DateTime? createdAt;

  bool get isEvent => kind == 'event';
  bool get hasText => (body ?? '').trim().isNotEmpty;
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
      image: TicketImage.fromJson(j['image']),
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

/// ما يعدّه رقم الجرس من التذاكر (٩ نوفمبر). **[kTicketsBadgeRule] هو السطر الوحيد الذي يقلبه** (رقم الجرس ورقم رأس القسم معاً)،
/// والاختبار يفحص الوجهين (test/tickets_bell_test.dart).
enum TicketsBadgeRule {
  /// كلّ ما ينتظرك (قرار المالك ٩ نوفمبر — كطلبات التجديد تبقى معدودةً حتى تُعالَج): التذاكر **المختلفة** غير المقروءة أو «بانتظارك»
  /// (جديدة أو قيد المعالجة) — الجديدة غير المقروءة تُعدّ مرّةً واحدة. هي نفسها ما يعرضه قسم الجرس. كجرس الويب.
  waiting,

  /// غير المقروءة وحدها (أوّل جرس الويب 2e6f9a4، قبل قرار المالك): لا يبقى الجرس مضاءً لتذكرةٍ قرأتها وهي قيد المعالجة.
  unread,
}

/// قاعدة رقم الجرس — اقلبها هنا وحدها.
const TicketsBadgeRule kTicketsBadgeRule = TicketsBadgeRule.waiting;

/// رقم التذاكر على الجرس بالقاعدة [rule]: [c] أعداد الخادم، و[outside] غير المقروءة خارج «بانتظارك» (ألغاها المشترك — من قائمة الجرس،
/// [TicketsBell.outside]). «بانتظارك» + ما خارجها = كلّ تذكرةٍ غير مقروءة أو بانتظارك مرّةً واحدة (غير المقروءة داخلها لا تُعاد).
int ticketsBadgeCount(TicketCounts c, {int outside = 0, TicketsBadgeRule rule = kTicketsBadgeRule}) => switch (rule) {
      TicketsBadgeRule.waiting => c.open + outside,
      TicketsBadgeRule.unread => c.unread,
    };

/// قسم «تذاكر المشتركين» في الجرس: ما ينتظر عملاً — غير المقروءة أوّلاً ثمّ «بانتظارك» — بأحدث [TicketsState.bellMax] منها، و[outside]
/// غير المقروءة خارج «بانتظارك» (لعدّ كلّ ما ينتظر مرّةً واحدة مع «بانتظارك» من الملخّص).
@immutable
class TicketsBell {
  const TicketsBell({this.items = const [], this.outside = 0, this.known = const {}});
  final List<Ticket> items;
  final int outside;

  /// كلّ تذكرةٍ قرأها الجرس ⇒ غير مقروءة؟ — «بانتظارك» كلّها (حتى حدّ الصفحة) وغير المقروءة خارجها: ما يعدّه رقمه بمعرّفاته، فلا
  /// يُعدّ إشعارها في الصندوق مرّةً ثانية ([TicketsState.inboxDuplicates]).
  final Map<int, bool> known;

  static const empty = TicketsBell();

  /// تذكرة [id] معدودةٌ في رقم الجرس بالقاعدة [rule]: «بانتظارك» أو غير مقروءةٍ خارجها — أو غير المقروءة وحدها بالوجه الآخر.
  bool isCounted(int id, TicketsBadgeRule rule) => switch (rule) {
        TicketsBadgeRule.waiting => known.containsKey(id),
        TicketsBadgeRule.unread => known[id] == true,
      };

  /// كلّ ما ينتظرك — التذاكر المختلفة غير المقروءة أو «بانتظارك» ([c] الملخّص الأحدث).
  int waitingOf(TicketCounts c) => math.max(c.open + outside, items.length);

  /// ما لم يُعرض منها (سطر «و N غيرها…»).
  int moreOf(TicketCounts c) => math.max(0, waitingOf(c) - items.length);
}

/// ترتيب الجرس كترتيب الخادم: غير المقروءة أوّلاً، ثمّ الأحدث نشاطاً.
List<Ticket> sortBellFirst(Iterable<Ticket> list) {
  final out = list.toList();
  out.sort((a, b) {
    if (a.unread != b.unread) return a.unread ? -1 : 1;
    final ta = a.lastActivityAt, tb = b.lastActivityAt;
    if (ta != null && tb != null && ta != tb) return tb.compareTo(ta);
    if ((ta == null) != (tb == null)) return ta == null ? 1 : -1;
    return b.id.compareTo(a.id);
  });
  return out;
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

/// بايتات صورة رسالة، أو expired = حُذفت (٤١٠)؛ كلاهما null/false = تعذّر (شبكة/خادم).
typedef TicketImageResult = ({Uint8List? bytes, bool expired});

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
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>(base, queryParameters: {'filter': filter.name, 'offset': '$offset', 'limit': '$limit'});
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
          thread:
              TicketThread(ticket: t, messages: ms is List ? ms.map(TicketMessage.fromJson).whereType<TicketMessage>().toList() : const []),
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

  /// [image] JPEG مضغوطٌ بلا EXIF (lib/screens/tickets/ticket_image.dart) — النصّ اختياريٌّ معه.
  static Future<TicketWrite> reply(int id, String body, {Uint8List? image}) => _write('$base/$id/reply', {
        'body': body,
        if (image != null) 'image': 'data:image/jpeg;base64,${base64Encode(image)}',
      });

  // آخر ٤٠ صورة في الذاكرة (المحادثة تُعاد قراءتها كلّ ٣٠ث) — تُمسح بتبديل الحساب ([TicketsState.reset]).
  static final Map<String, Uint8List> _images = {};

  /// صورة رسالة بمسارها الموثَّق (والموجَّه في «كل الشركات» ببادئة القسم).
  static Future<TicketImageResult> imageBytes(int ticketId, int messageId) async {
    final key = '$ticketId/$messageId';
    final hit = _images.remove(key);
    if (hit != null) {
      _images[key] = hit;
      return (bytes: hit, expired: false);
    }
    try {
      final r = await ApiClient.dio
          .get<List<int>>('$base/$ticketId/messages/$messageId/image', options: Options(responseType: ResponseType.bytes));
      final data = r.data;
      if (r.statusCode == 200 && data != null && data.isNotEmpty) {
        final b = data is Uint8List ? data : Uint8List.fromList(data);
        _images[key] = b;
        while (_images.length > 40) {
          _images.remove(_images.keys.first);
        }
        return (bytes: b, expired: false);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 410) return (bytes: null, expired: true);
      if (kDebugMode) debugPrint('⚠️ ticket image: $e');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ ticket image: $e');
    }
    return (bytes: null, expired: false);
  }

  @visibleForTesting
  static void debugClearImages() => _images.clear();

  /// in_progress · resolved · closed
  static Future<TicketWrite> setStatus(int id, String status) => _write('$base/$id/status', {'status': status});

  static Future<TicketWrite> reopen(int id) => _write('$base/$id/reopen', const {});
}

/// حال «التذاكر» للجلسة — شارة «قوائم أخرى» وقائمة الحاسبة الجانبيّة والجرس (رقمه وقسم «تذاكر المشتركين») يستمعون له. يُقرأ عند
/// أوّل مستمع، وعند العودة للتطبيق، وحين يصل إشعار تذكرة (FCM أو تغذية الحاسبة — كلاهما يمرّ بصندوق الإشعارات)، وبعد كلّ إجراء.
/// للشركة المفتوحة دائماً ([CompanyRoute.runOpen]) — بـ«كل الشركات» لا يُكتب فوقه رقم شركةٍ أخرى ولا تذاكرها.
class TicketsState {
  TicketsState._();

  /// null = لم يُعرف بعد.
  static final ValueNotifier<TicketsAccess?> gate = _TicketsGate();

  /// «تذاكر المشتركين» في الجرس (٩ نوفمبر) — تُقرأ مع الملخّص حين يوجد ما ينتظر وحده، ولمن يرى القسم وحده ([inBell]).
  static final ValueNotifier<TicketsBell> bell = ValueNotifier<TicketsBell>(TicketsBell.empty);

  /// أقصى ما يُعرض في الجرس (كطلبات التجديد وجرس الويب).
  static const bellMax = 5;

  /// «بانتظارك» تُقرأ كلّها حتى حدّ الخادم (pageMax) — فيُعرف كم منها غير مقروء وكم غير مقروءٍ خارجها، فيُعدّ كلّ ما ينتظر مرّةً واحدة.
  /// الردّ بقدر ما يوجد (عادةً بضع تذاكر)، لا بالحدّ.
  static const _waitingReadLimit = 50;

  /// قاعدة رقم الجرس — [kTicketsBadgeRule] دائماً؛ الاختبار وحده يبدّلها ([debugSetBadgeRule]) ليفحص الوجهين.
  static TicketsBadgeRule get badgeRule => _badgeRule;
  static TicketsBadgeRule _badgeRule = kTicketsBadgeRule;

  @visibleForTesting
  static void debugSetBadgeRule(TicketsBadgeRule rule) => _badgeRule = rule;

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;

  /// قائمة الجرس تعذّرت والملخّص وصل: تُعاد بعد التبريد مع أوّل سؤالٍ تالٍ ولو لم تنتهِ المهلة — ولا تحبس الملخّص نفسه.
  static DateTime? _bellFailedAt;
  static Future<void>? _inflight;

  /// ملخّص القراءة الجارية وصل (أو انتهت) — ما ينتظره نقر الإشعار حين لا يُعرف الحال ([ensureForPush])، لا قوائم الجرس بعده.
  static Future<void>? _inflightSummary;

  /// قراءةٌ مُجبَرة طُلبت والجارية بدأت قبلها — تجري بعدها مرّةً واحدة لكلّ من طلبها أثناءها ([ensureFresh]).
  static Future<void>? _queued;

  /// متى سُئل الملخّص المنشور — ما وصل الصندوقَ قبله من إشعارات التذاكر حالُه في الأرقام ([inboxDuplicates]).
  static DateTime? _countsAsOf;

  /// الشركة التي يعرض الحال تذاكرها (المفتوحة، كما في بيانات دفعها `company_admin_id`).
  static String? _adminId;
  static String? _lastInboxId;

  static const ttl = Duration(minutes: 2);
  static const _cooldown = Duration(seconds: 20);

  static bool get on => gate.value?.on ?? false;

  /// غير المقروءة لطرف الوكيل (الشارة).
  static int get unread => on ? gate.value!.counts?.unread ?? 0 : 0;

  /// الجرس: القسم متاحٌ ويملكه المستخدم (الخادم)، غير مقيَّدٍ بمديرٍ فرعيّ، وصلاحيّته عندنا — الموظّف بلا «التذاكر — العرض» لا يرى
  /// شيئاً هناك ولا يُطلب له شيء (والقسم مقفلٌ بمكانه في «قوائم أخرى»).
  static bool get inBell => _bellFor(gate.value);

  static bool _bellFor(TicketsAccess? a) => a != null && a.on && !a.scoped && Perms.has('tickets.view');

  /// رقم التذاكر على الجرس ورأس قسمها ([ticketsBadgeCount] بالقاعدة [badgeRule]): الآن كلّ ما ينتظرك مرّةً واحدة.
  static int get bellBadge => inBell
      ? ticketsBadgeCount(gate.value!.counts ?? const TicketCounts(), outside: bell.value.outside, rule: badgeRule)
      : 0;

  /// كلّ ما ينتظرك (ما يعرضه القسم كلّه) — لسطر «و N غيرها…» أيّاً كانت القاعدة.
  static int get bellWaiting => inBell ? bell.value.waitingOf(gate.value!.counts ?? const TicketCounts()) : 0;

  /// إشعارات تذاكر غير مقروءة في الصندوق يعدّها [bellBadge] أصلاً — تُطرح من رقم الجرس (`TopActions`) فتُعدّ كلّ تذكرةٍ مرّةً واحدة
  /// (مراجعة 3.0.18: تذكرةٌ جديدة والتطبيق مفتوح كانت ٢ — إشعارها غير المقروء والتذكرة — وثلاث رسائل منها ٤؛ والحاسبة تضيف كلّ
  /// إشعارٍ غير مقروء). المعدود: إشعارٌ لتذكرةٍ معدودةٍ الآن، أو وصل قبل آخر سؤالٍ للأرقام فحالها فيها (تنتظرك ⇒ معدودة، عولجت ⇒ لا
  /// تنتظرك). وما سواه يُعدّ كأيّ إشعار: تذكرةٌ جديدة لم تُقرأ أرقامها بعد (حتى تُقرأ — فلا يتأخّر الرقم ولا يتضاعف)، أو لشركةٍ
  /// أخرى («إشعارات كلّ شركاتي» — الجرس لتذاكر المفتوحة وحدها)، أو والقسم ليس في جرسه.
  static int get inboxDuplicates {
    if (!inBell) return 0;
    final b = bell.value;
    final asOf = _countsAsOf;
    var n = 0;
    for (final x in InboxService.all) {
      if (x.isRead || x.data['type'] != 'portal_ticket') continue;
      final company = (x.data['company_admin_id'] ?? '').trim();
      if (company.isNotEmpty && company != _adminId) continue;
      final id = int.tryParse(x.data['ticket_id'] ?? '');
      if ((id != null && b.isCounted(id, badgeRule)) || (asOf != null && !x.receivedAt.isAfter(asOf))) n++;
    }
    return n;
  }

  /// نقر إشعار تذكرة (FCM أو اللافتة أو الصندوق — `openTicketPush`): المحادثة تُفتح فوراً والجرس يُقرأ في الخلفيّة (مراجعة 3.0.18 — كان
  /// النقر ينتظر الملخّص ثمّ قائمتي الجرس واحدةً بعد أخرى قبل أن يُفتح شيء). الحال معروفٌ والقسم مفتوحٌ له (والعرض عندنا) ⇒ لا
  /// انتظار: المحادثة نفسها تقرأ الجرس بعد قراءتها (قراءةٌ مُجبَرة تأتي بعد الجارية — [ensureFresh])، وصلاحيّةٌ سُحبت للتوّ يردّها
  /// خادمها (٤٠٣ ⇒ «غير متاحة»). وإلّا (لم يُعرف بعد، أو مقفل/غير متاح) ⇒ الملخّص وحده يقرّر — يُنشر حين يصل، وقائمتا الجرس تكملان
  /// بعده في الخلفيّة.
  static Future<void> ensureForPush() {
    if (on && Perms.has('tickets.view')) return Future<void>.value();
    if (_inflight == null) unawaited(ensureFresh(force: true));
    return _inflightSummary ?? Future<void>.value();
  }

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) {
      if (!force) return running;
      // مُجبَرة (إشعارٌ وصل، محادثةٌ قُرئت، رجوعٌ من تذكرة…) والجارية بدأت قبلها: لقطتها قد تسبق ما تغيّر — كانت تُعاد هي فيبقى الجرس
      // يعدّ تذكرةً قُرئت للتوّ أو يفوته جديدٌ وصل أثناءها. قراءةٌ واحدةٌ بعدها لكلّ من طلب أثناءها.
      final queued = _queued;
      if (queued != null) return queued;
      final epoch = _epoch;
      late final Future<void> next;
      next = running.then<void>((_) {}, onError: (Object _) {}).then((_) {
        if (identical(_queued, next)) _queued = null;
        return epoch == _epoch ? ensureFresh(force: true) : Future<void>.value();
      });
      _queued = next;
      return next;
    }
    final now = DateTime.now();
    if (!force) {
      final at = _fetchedAt;
      final bellFailed = _bellFailedAt;
      final bellRetry = bellFailed != null && now.difference(bellFailed) >= _cooldown;
      if (at != null && now.difference(at) < ttl && !bellRetry) return Future<void>.value();
    }
    final failed = _failedAt;
    if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    final epoch = _epoch;
    final summary = Completer<void>();
    late final Future<void> run;
    run = CompanyRoute.runOpen(() => _fetch(epoch, summary)).whenComplete(() {
      if (!summary.isCompleted) summary.complete();
      if (identical(_inflight, run)) {
        _inflight = null;
        _inflightSummary = null;
      }
    });
    _inflight = run;
    _inflightSummary = summary.future;
    return run;
  }

  static Future<void> _fetch(int epoch, Completer<void> summary) async {
    final asked = DateTime.now();
    String? adminId;
    try {
      adminId = (await AuthStorage.readAdminId())?.trim();
    } catch (_) {
      adminId = null;
    }
    final a = await TicketsApi.summary();
    if (epoch != _epoch) return;
    if (a == null) {
      _failedAt = DateTime.now();
      return;
    }
    // الجرس: لمن يرى القسم وحده، وبلا نداءٍ ثانٍ حين لا شيء ينتظر
    final wanted = _bellFor(a);
    // لم يكن من التذاكر شيءٌ في الجرس (الحال مجهول، أو مقفل، أو مطفأ): الملخّص يُنشر حين يصل — نقر الإشعار ينتظره وحده لا قائمتي
    // الجرس ([ensureForPush]). وإلّا يُنشر مع الجرس معاً، فلا يُرى رقمٌ نصفه جديدٌ ونصفه قديم.
    if (wanted && !_bellFor(gate.value)) {
      _fetchedAt = DateTime.now();
      _failedAt = null;
      _countsAsOf = asked;
      _adminId = adminId;
      gate.value = a;
    }
    if (!summary.isCompleted) summary.complete();
    TicketsBell? b = TicketsBell.empty;
    if (wanted) {
      b = await _readBell(a.counts ?? const TicketCounts());
      if (epoch != _epoch) return;
    }
    _fetchedAt = DateTime.now();
    _failedAt = null;
    if (b == null) {
      // الملخّص وصل وقائمة الجرس تعذّرت: الأرقام تتحدّث، وما عُرض يبقى حتى المحاولة التالية (بعد التبريد)
      _bellFailedAt = DateTime.now();
    } else {
      _bellFailedAt = null;
      bell.value = b;
    }
    _countsAsOf = asked;
    _adminId = adminId;
    gate.value = a;
  }

  /// ما ينتظر عملاً للجرس: «بانتظارك» كلّها (غير المقروءة أوّلاً — ترتيب الخادم)، وغير المقروءة خارجها (ألغاها المشترك — يعدّها الخادم
  /// في unread) بنداءٍ ثانٍ حين توجد وحده. والعدد: «بانتظارك» + ما خارجها = كلّ تذكرةٍ مرّةً واحدة. null = تعذّر.
  static Future<TicketsBell?> _readBell(TicketCounts c) async {
    if (c.open <= 0 && c.unread <= 0) return TicketsBell.empty;
    var open = const <Ticket>[];
    var openAll = true;
    if (c.open > 0) {
      final p = await TicketsApi.list(filter: TicketFilter.open, limit: _waitingReadLimit);
      if (p == null) return null;
      open = p.items;
      openAll = !p.hasMore;
    }
    final unreadOpen = open.where((t) => t.unread).length;
    // غير المقروءة أوّل «بانتظارك»: الصفحة تحويها كلّها ما لم تمتلئ بها — فالباقي من العدد خارجها. وإلّا (أكثر من الحدّ وكلّها جديدة)
    // يُعرف من «المنتهية» نفسها
    final known = openAll || unreadOpen < open.length;
    var outside = known ? math.max(0, c.unread - unreadOpen) : -1;
    var extra = const <Ticket>[];
    if (outside != 0) {
      final p = await TicketsApi.list(filter: TicketFilter.closed, limit: bellMax);
      if (p == null) return null;
      extra = p.items.where((t) => t.unread).toList();
      if (outside < 0) outside = extra.length;
    }
    final all = sortBellFirst([...extra, ...open]);
    return TicketsBell(
      items: List<Ticket>.unmodifiable(all.take(bellMax)),
      outside: outside,
      known: Map<int, bool>.unmodifiable({for (final t in open) t.id: t.unread, for (final t in extra) t.id: true}),
    );
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
    _bellFailedAt = null;
    _inflight = null;
    _inflightSummary = null;
    _queued = null;
    _countsAsOf = null;
    _adminId = null;
    bell.value = TicketsBell.empty;
    gate.value = null;
    TicketsApi._images.clear();
  }

  @visibleForTesting
  static void debugSet(TicketsAccess? a, {TicketsBell bell = TicketsBell.empty, String? adminId}) {
    _epoch++;
    _inflight = null;
    _inflightSummary = null;
    _queued = null;
    _failedAt = null;
    _bellFailedAt = null;
    _fetchedAt = a == null ? null : DateTime.now();
    _countsAsOf = _fetchedAt;
    _adminId = adminId;
    TicketsState.bell.value = bell;
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
