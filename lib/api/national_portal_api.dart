import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// المشروع الوطنيّ (watani، ٣١ أكتوبر — المالك: «الطلبات التذاكر هاي مهمه مموجوده كذلك المواضع الي متعلقة بالمالية…
/// سرعه بالاستجابه والعرض… والفلاتر»): أقسام البوّابة بالتطبيق من `/api/v2/ftth/*` بالخادم
/// (`server/watani/wataniPortalRoutes.js`) — فلاتر البوّابة نفسها، وكاشٌ بالخادم: الجلب الأوّل البطيء (الطلبات ~١٦ث، المهامّ ~٨ث)
/// يردّ `pending` والشاشة تعيد السؤال كلّ ٤ث. لا هواتف ولا وثائق هويّة ولا إحداثيّات (الخادم لا يرسلها).
///
/// الكتابة (المرحلة ٢، ٣١ أكتوبر — خلف مفتاح الحساب `watani_portal`، والخادم يقول `can_write`/`can`): فتح تذكرة (لمشترك أو للزون)،
/// والتعليق، وموعد الزيارة، وإلغاء الطلب. لا إعادة إرسالٍ تلقائيّة أبداً: «غير مؤكَّد» (202 UNCONFIRMED) يُعرض كما هو، والتذكرة
/// تحمل مرجع النموذج (`client_ref` = ticketId) فإعادتها بالمرجع نفسه لا تفتح ثانية.

class NationalRef {
  const NationalRef(this.id, this.name);
  final String? id;
  final String name;

  static NationalRef? from(dynamic v) {
    if (v is! Map) return null;
    final name = (v['name'] ?? '').toString().trim();
    final id = v['id']?.toString();
    if (name.isEmpty && (id == null || id.isEmpty)) return null;
    return NationalRef(id, name);
  }
}

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? ''));
num? _num(dynamic v) => v is num ? v : (v == null ? null : num.tryParse(v.toString()));
String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

/// صفحةٌ من قسم: الصفوف والإجماليّ، أو `pending` (الخادم يجلب — اسأل ثانيةً بعد قليل).
class NationalPage<T> {
  const NationalPage({
    required this.items,
    this.total,
    this.page = 1,
    this.pageCount,
    this.pending = false,
    this.stale = false,
    this.fetchedAt,
    this.raw = const {},
  });
  final List<T> items;
  final int? total;
  final int page;
  final int? pageCount;
  final bool pending;
  final bool stale;
  final String? fetchedAt;

  /// الردّ كاملاً — ما يخصّ القسم (summary · balance · sum).
  final Map<String, dynamic> raw;

  bool get hasMore => !pending && pageCount != null && page < pageCount!;
}

/// نتيجة نداء: البيانات، أو رسالة الخادم العربيّة (`relogin` حين انتهت جلسة الشركة).
class NationalResult<T> {
  const NationalResult.ok(this.data)
      : error = null,
        relogin = false;
  const NationalResult.fail(this.error, {this.relogin = false}) : data = null;
  final T? data;
  final String? error;
  final bool relogin;
  bool get ok => data != null;
}

class NationalTicket {
  const NationalTicket({
    required this.id,
    required this.displayId,
    required this.source,
    required this.title,
    required this.summary,
    required this.status,
    this.customer,
    this.zone,
    this.infra = false,
    this.comments = 0,
    this.attachments = 0,
    this.createdAt,
  });
  final String? id;
  final String displayId;
  final String source; // partner | call_center
  final String title;
  final String summary;
  final String status;
  final NationalRef? customer;
  final NationalRef? zone;
  final bool infra;
  final int comments;
  final int attachments;
  final String? createdAt;

  static NationalTicket fromJson(Map<String, dynamic> j) => NationalTicket(
        id: _sn(j['id']),
        displayId: _s(j['display_id']),
        source: _s(j['source']),
        title: _s(j['title']),
        summary: _s(j['summary']),
        status: _s(j['status']),
        customer: NationalRef.from(j['customer']),
        zone: NationalRef.from(j['zone']),
        infra: j['infra'] == true,
        comments: _int(j['comments']) ?? 0,
        attachments: _int(j['attachments']) ?? 0,
        createdAt: _sn(j['created_at']),
      );
}

class NationalComment {
  const NationalComment(this.text, this.by, this.at);
  final String text;
  final String by;
  final String? at;
}

class NationalTicketDetails {
  const NationalTicketDetails({
    this.id,
    required this.title,
    required this.displayId,
    required this.status,
    required this.details,
    this.category,
    this.issue,
    this.customer,
    this.zone,
    this.infra = false,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
    this.scheduleDate,
    this.scheduleReason,
    this.attachments = const [],
    this.comments,
    this.canComment = false,
    this.canSchedule = false,
  });
  final String? id;
  final String title;
  final String displayId;
  final String status;
  final String details;
  final String? category;
  final String? issue;
  final NationalRef? customer;
  final NationalRef? zone;
  final bool infra;
  final String? createdAt;
  final String? updatedAt;
  final String? closedAt;
  final String? scheduleDate;
  final String? scheduleReason;
  final List<String> attachments;

  /// null = تعذّر جلبها الآن (لا «لا تعليقات» كاذبة).
  final List<NationalComment>? comments;

  /// ما يُسمح به من هنا (مفتاح الحساب + حالة التذكرة + حاجتها لموعد) — من الخادم.
  final bool canComment;
  final bool canSchedule;

  static NationalTicketDetails fromJson(Map<String, dynamic> j) {
    final sch = j['schedule'];
    final cs = j['comments'];
    final can = j['can'] is Map ? j['can'] as Map : const {};
    return NationalTicketDetails(
      id: _sn(j['id']),
      title: _s(j['title']),
      displayId: _s(j['display_id']),
      status: _s(j['status']),
      details: _s(j['details']),
      category: NationalRef.from(j['category'])?.name,
      issue: j['issue'] is Map ? _sn((j['issue'] as Map)['name']) : null,
      customer: NationalRef.from(j['customer']),
      zone: NationalRef.from(j['zone']),
      infra: j['infra'] == true,
      createdAt: _sn(j['created_at']),
      updatedAt: _sn(j['updated_at']),
      closedAt: _sn(j['closed_at']),
      scheduleDate: sch is Map ? _sn(sch['date']) : null,
      scheduleReason: sch is Map ? _sn(sch['reason']) : null,
      attachments: (j['attachments'] is List ? j['attachments'] as List : const []).map(_s).where((x) => x.isNotEmpty).toList(),
      comments: cs is List
          ? cs.whereType<Map>().map((c) => NationalComment(_s(c['text']), _s(c['by']), _sn(c['at']))).toList()
          : null,
      canComment: can['comment'] == true,
      canSchedule: can['schedule'] == true,
    );
  }
}

class NationalRequest {
  const NationalRequest({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.status,
    this.customer,
    this.username,
    this.zone,
    this.createdAt,
    this.closedAt,
    this.cancelable = false,
  });
  final String? id;
  final String type; // CustomerOnboardingRequest…
  final String typeLabel;
  final String status;
  final NationalRef? customer;
  final String? username;
  final NationalRef? zone;
  final String? createdAt;
  final String? closedAt;
  final bool cancelable;

  static NationalRequest fromJson(Map<String, dynamic> j) => NationalRequest(
        id: _sn(j['id']),
        type: _s(j['type']),
        typeLabel: _s(j['type_label']),
        status: _s(j['status']),
        customer: NationalRef.from(j['customer']),
        username: _sn(j['username']),
        zone: NationalRef.from(j['zone']),
        createdAt: _sn(j['created_at']),
        closedAt: _sn(j['closed_at']),
        cancelable: j['cancelable'] == true,
      );
}

class NationalRequestDetail {
  const NationalRequestDetail({
    required this.status,
    this.plan,
    this.address,
    this.cancelable = false,
    this.createdAt,
    this.closedAt,
    this.tasks = const [],
    this.logs,
    this.logsPending = false,
    this.canCancel = false,
  });
  final String status;
  final String? plan;
  final String? address;
  final bool cancelable;
  final String? createdAt;
  final String? closedAt;
  /// [id] (٢ نوفمبر): تُفتح المهمّة المرتبطة بورقتها — ومنها «تنصيب الجهاز».
  final List<({String? id, String title, String status, String? dueAt})> tasks;

  /// null = لم يصل بعد (`logsPending`) أو تعذّر.
  final List<({String? at, bool? ok, String text})>? logs;
  final bool logsPending;

  /// «إلغاء الطلب» من هنا (مفتاح الحساب + isCancelable) — من الخادم.
  final bool canCancel;

  static NationalRequestDetail fromJson(Map<String, dynamic> j) {
    final d = j['detail'] is Map ? Map<String, dynamic>.from(j['detail'] as Map) : const <String, dynamic>{};
    final logs = j['logs'];
    return NationalRequestDetail(
      status: _s(d['status']),
      plan: _sn(d['plan']),
      address: _sn(d['address']),
      cancelable: d['cancelable'] == true,
      createdAt: _sn(d['created_at']),
      closedAt: _sn(d['closed_at']),
      tasks: (d['tasks'] is List ? d['tasks'] as List : const [])
          .whereType<Map>()
          .map((t) => (id: _sn(t['id']), title: _s(t['title']), status: _s(t['status']), dueAt: _sn(t['due_at'])))
          .toList(),
      logs: logs is List
          ? logs.whereType<Map>().map((l) => (at: _sn(l['at']), ok: l['ok'] is bool ? l['ok'] as bool : null, text: _s(l['text']))).toList()
          : null,
      logsPending: j['logs_pending'] == true,
      canCancel: j['can'] is Map && (j['can'] as Map)['cancel'] == true,
    );
  }
}

class NationalTask {
  const NationalTask({required this.id, required this.title, required this.status, this.dueAt, this.customer, this.zone});
  final String? id;
  final String title;
  final String status;
  final String? dueAt;
  final NationalRef? customer;
  final NationalRef? zone;

  static NationalTask fromJson(Map<String, dynamic> j) => NationalTask(
        id: _sn(j['id']),
        title: _s(j['title']),
        status: _s(j['status']),
        dueAt: _sn(j['due_at']),
        customer: NationalRef.from(j['customer']),
        zone: NationalRef.from(j['zone']),
      );
}

/// حركةٌ ماليّة: إيرادٌ (transactions/revenue) أو حركة محفظة (transactions — «محفظتي» و«التحويلات»).
///
/// صفّ المحفظة v2 (الخادم ١ نوفمبر، `ftthAdapter.mapWalletRow`): نوع المحفظة (الرئيسيّة/العمولة) ومالكها (الوكيل/المشترك) ونوع التغيير
/// (مجدول/فوري) وطريقة الدفع والتسلسليّ والزون والاتّجاه، والتحويل (من/إلى)، و«المنفّذ» مشتقّاً بالخادم (`by`: me · team · null) — لا
/// اسم مستخدمٍ خامٌ أبداً (قرار الخصوصيّة ١٩ أكتوبر). ما لا يرسله خادمٌ أقدم يبقى فارغاً.
class NationalMoneyRow {
  const NationalMoneyRow({
    required this.at,
    required this.type,
    this.id,
    this.amount,
    this.balanceAfter,
    this.method = '',
    this.paidBy = '',
    this.username,
    this.customer,
    this.subscriptionId,
    this.planName,
    this.starts,
    this.ends,
    this.planKind = '',
    this.outsidePeriod = false,
    this.discount,
    this.walletType = '',
    this.owner = '',
    this.changeType = '',
    this.payMethod = '',
    this.salesType = '',
    this.serial,
    this.zone,
    this.direction = '',
    this.by,
    this.byName,
    this.transferFrom,
    this.transferTo,
  });
  final String? id;
  final String? at;
  final String type;
  final num? amount;
  final num? balanceAfter;
  final String method;
  final String paidBy;
  final String? username;
  final NationalRef? customer;
  final String? subscriptionId;
  final String? planName;
  final String? starts;
  final String? ends;
  final String planKind;
  final bool outsidePeriod;
  final num? discount;

  /// `Main` · `Commission` · ''.
  final String walletType;

  /// `Partner` · `Customer` · ''.
  final String owner;

  /// `Scheduled` · `Instant` · ''.
  final String changeType;
  final String payMethod;
  final String salesType;
  final String? serial;
  final String? zone;

  /// `in` · `out` — من الخادم، وإلّا من إشارة المبلغ.
  final String direction;

  /// `me` · `team` · null (لا يُعرف).
  final String? by;

  /// اسم عضو «فريقي» الذي نفّذها (الخادم يطابق المنفّذ بأعضاء الفريق — لا يوزر ولا هاتف خامٌ أبداً)؛ null لحركاتك أو حين لا يُعرف.
  final String? byName;
  final NationalRef? transferFrom;
  final NationalRef? transferTo;

  bool get isCommission => walletType == 'Commission';
  bool get isOut => direction == 'out';
  bool get isIn => direction == 'in';

  static String _walletTypeOf(dynamic v) {
    final s = _s(v is Map ? (v['id'] ?? v['displayValue']) : v).toLowerCase();
    if (s == 'main' || s == '0') return 'Main';
    if (s == 'commission' || s == '1') return 'Commission';
    return '';
  }

  static String _ownerOf(dynamic v) {
    final s = _s(v is Map ? (v['id'] ?? v['displayValue']) : v).toLowerCase();
    if (s == 'partner' || s == '1') return 'Partner';
    if (s == 'customer' || s == '0') return 'Customer';
    return '';
  }

  static NationalMoneyRow fromJson(Map<String, dynamic> j) {
    final sub = j['subscription'] is Map ? j['subscription'] as Map : null;
    final tr = j['transfer'] is Map ? j['transfer'] as Map : null;
    final amount = _num(j['amount']);
    final dir = _s(j['direction']).toLowerCase();
    final by = _s(j['by']).toLowerCase();
    return NationalMoneyRow(
      id: _sn(j['id']),
      at: _sn(j['at']),
      type: _s(j['type']),
      amount: amount,
      balanceAfter: _num(j['balance_after']),
      method: _s(j['method']),
      paidBy: _s(j['paid_by']),
      username: _sn(j['username']),
      customer: NationalRef.from(j['customer']),
      subscriptionId: sub == null ? null : _sn(sub['id']),
      planName: sub == null ? null : _sn(sub['name']),
      starts: sub == null ? null : _sn(sub['starts']),
      ends: sub == null ? null : _sn(sub['ends']),
      planKind: _s(j['plan_kind']),
      outsidePeriod: j['outside_period'] == true,
      discount: _num(j['discount']),
      walletType: _walletTypeOf(j['wallet_type']),
      owner: _ownerOf(j['owner']),
      changeType: const {'scheduled': 'Scheduled', 'instant': 'Instant'}[_s(j['change_type']).toLowerCase()] ?? '',
      payMethod: _s(j['pay_method']),
      salesType: _s(j['sales_type']),
      serial: _sn(j['serial']),
      zone: _sn(j['zone']),
      direction: dir == 'in' || dir == 'out'
          ? dir
          : amount == null || amount == 0
              ? ''
              : (amount < 0 ? 'out' : 'in'),
      by: by == 'me' || by == 'team' ? by : null,
      byName: by == 'me' ? null : _sn(j['by_name']),
      transferFrom: tr == null ? null : NationalRef.from(tr['from']),
      transferTo: tr == null ? null : NationalRef.from(tr['to']),
    );
  }
}

/// ما يخصّ «محفظتي» من ردّ الخادم: الرصيد (أو «حدّ المحفظة» لعضو فريقٍ بحدّ) والعمولة، وما يملكه الحساب في البوّابة (caps)، ونطاق
/// الفترة، و«أيّ مشترك؟» حين يطابق الاسم أكثر من واحد. خادمٌ أقدم (v1) بلا caps ⇒ [v2] false: لا أقسام ولا فرزٌ لا يفهمه.
class NationalWalletMeta {
  const NationalWalletMeta({
    this.balance,
    this.commission,
    this.limit,
    this.currency = 'IQD',
    this.caps = const {},
    this.v2 = false,
    this.rangeDefault = false,
    this.from,
    this.to,
    this.ambiguous,
  });

  final num? balance;
  final num? commission;

  /// «حدّ المحفظة» لعضو فريقٍ له حدّ — يُعرض بدل الرصيد كما تفعل البوّابة.
  final num? limit;
  final String currency;

  /// commission · transfers · records · team (لا يُعرف ⇒ غائب).
  final Map<String, bool> caps;
  final bool v2;
  final bool rangeDefault;
  final String? from;
  final String? to;
  final List<({String? customerId, String name, String? username})>? ambiguous;

  bool cap(String k) => caps[k] == true;

  static NationalWalletMeta fromRaw(Map<String, dynamic> raw) {
    final b = raw['balance'] is Map ? raw['balance'] as Map : null;
    final lim = b == null ? null : b['limit'];
    final caps = raw['caps'] is Map ? raw['caps'] as Map : null;
    final amb = raw['ambiguous'];
    return NationalWalletMeta(
      balance: b == null ? null : _num(b['balance']),
      commission: b == null ? null : _num(b['commission']),
      limit: lim is Map ? _num(lim['balance']) : null,
      currency: b == null ? 'IQD' : (_sn(b['currency']) ?? 'IQD'),
      caps: caps == null ? const {} : {for (final e in caps.entries) e.key.toString(): e.value == true},
      v2: caps != null || raw.containsKey('range_default') || raw['wallet'] is String,
      rangeDefault: raw['range_default'] == true,
      from: _sn(raw['from']),
      to: _sn(raw['to']),
      ambiguous: amb is List
          ? amb
              .whereType<Map>()
              .map((m) => (customerId: _sn(m['customer_id']), name: _s(m['name']), username: _sn(m['username'])))
              .where((x) => x.name.isNotEmpty || (x.username ?? '').isNotEmpty)
              .toList()
          : null,
    );
  }
}

class NationalLookupItem {
  const NationalLookupItem(this.id, this.name);
  final String id;
  final String name;
}

class NationalLookups {
  const NationalLookups({
    this.ticketStatuses,
    this.ticketCategories,
    this.requestTypes,
    this.requestStatuses,
    this.zones,
    this.transactionTypes,
    this.canWrite = false,
  });
  final List<NationalLookupItem>? ticketStatuses;
  final List<NationalLookupItem>? ticketCategories;
  final List<NationalLookupItem>? requestTypes;
  final List<NationalLookupItem>? requestStatuses;
  final List<NationalLookupItem>? zones;
  final List<NationalLookupItem>? transactionTypes;

  /// الكتابة مفتوحةٌ لهذا الحساب (تذكرة/تعليق/موعد/إلغاء طلب).
  final bool canWrite;

  static List<NationalLookupItem>? _list(dynamic v) => v is List
      ? v.whereType<Map>().map((x) => NationalLookupItem(_s(x['id']), _s(x['name']))).where((x) => x.id.isNotEmpty).toList()
      : null;

  static NationalLookups fromJson(Map<String, dynamic> j) => NationalLookups(
        ticketStatuses: _list(j['ticket_statuses']),
        ticketCategories: _list(j['ticket_categories']),
        requestTypes: _list(j['request_types']),
        requestStatuses: _list(j['request_statuses']),
        zones: _list(j['zones']),
        transactionTypes: _list(j['transaction_types']),
        canWrite: j['can_write'] == true,
      );
}

/// مشتركٌ تُفتح له تذكرة: معرّف زبونه وزون اشتراكه عند البوّابة (بحث المشتركين بالخادم).
class NationalTarget {
  const NationalTarget({required this.idx, required this.username, required this.name, this.customerId, this.zoneId, this.zone});
  final String idx;
  final String username;
  final String name;
  final String? customerId;
  final String? zoneId;
  final String? zone;

  static NationalTarget? fromJson(Map<String, dynamic> j) {
    final w = j['watani'] is Map ? j['watani'] as Map : const {};
    final idx = _s(j['idx']);
    if (idx.isEmpty) return null;
    final name = [_s(j['firstname']), _s(j['lastname'])].where((x) => x.isNotEmpty).join(' ');
    return NationalTarget(
      idx: idx,
      username: _s(j['username']),
      name: name.isEmpty ? _s(j['username']) : name,
      customerId: _sn(w['customerId']),
      zoneId: _sn(w['zoneId']),
      zone: _sn(w['zone']),
    );
  }
}

/// نتيجة كتابة: نجاحٌ (+ بيانات)، أو «غير مؤكَّد» (لا «فشل» — ربّما وصلت)، أو رفضٌ برسالة الخادم (+ رسالة البوّابة إن وُجدت).
enum NationalWriteState { ok, unconfirmed, failed }

class NationalWrite {
  const NationalWrite(this.state, {this.message, this.portalMessage, this.code, this.data = const {}});
  final NationalWriteState state;
  final String? message;
  final String? portalMessage;
  final String? code;
  final Map<String, dynamic> data;
  bool get ok => state == NationalWriteState.ok;
  bool get unconfirmed => state == NationalWriteState.unconfirmed;
}

class NationalCounts {
  const NationalCounts({this.tasksOpen, this.requestsOpen, this.actionRequired});
  final int? tasksOpen;
  final int? requestsOpen;

  /// طلباتٌ بانتظار إجراء الوكيل — null حتى يدفأ كاشها بالخادم.
  final int? actionRequired;
}

class NationalPortalApi {
  NationalPortalApi._();

  /// يُسقط الفارغ — الخادم يتجاهل ما لا يعرفه ويرفض الصالح شكلاً فقط.
  static Map<String, dynamic> _q(Map<String, Object?> m) =>
      {for (final e in m.entries) if (e.value != null && e.value.toString().isNotEmpty) e.key: e.value};

  static Future<NationalResult<Map<String, dynamic>>> _get(String path, Map<String, Object?> query) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path, queryParameters: _q(query));
      final b = r.data ?? const {};
      if (b['success'] != true) return NationalResult.fail(_msg(b));
      return NationalResult.ok(b);
    } on DioException catch (e) {
      final b = e.response?.data;
      if (!kReleaseMode) debugPrint('🔴 $path: ${e.response?.statusCode}');
      final code = b is Map ? b['code']?.toString() : null;
      return NationalResult.fail(_msg(b), relogin: code == 'FTTH_RELOGIN' || code == 'PROVIDER_RELOGIN');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: $e');
      return const NationalResult.fail('تعذّر الاتّصال — أعد المحاولة');
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

  static Future<NationalResult<NationalPage<NationalTicket>>> tickets({
    int page = 1,
    String? q,
    String? status,
    String? zone,
    String? from,
    String? to,
  }) async {
    final r = await _get('/api/v2/ftth/tickets', {'page': page, 'q': q, 'status': status, 'zone': zone, 'from': from, 'to': to});
    return r.ok ? NationalResult.ok(_page(r.data!, NationalTicket.fromJson)) : NationalResult.fail(r.error, relogin: r.relogin);
  }

  /// تذكرةٌ واحدة — null داخل ok = pending (اسأل ثانيةً).
  static Future<NationalResult<NationalTicketDetails?>> ticket(String id) async {
    final r = await _get('/api/v2/ftth/tickets/${Uri.encodeComponent(id)}', const {});
    if (!r.ok) return NationalResult.fail(r.error, relogin: r.relogin);
    if (r.data!['pending'] == true || r.data!['data'] is! Map) return const NationalResult.ok(null);
    return NationalResult.ok(NationalTicketDetails.fromJson(Map<String, dynamic>.from(r.data!['data'] as Map)));
  }

  static Future<NationalResult<NationalPage<NationalRequest>>> requests({
    int page = 1,
    String? q,
    String? type,
    String? status,
    bool actionRequired = false,
    String? zone,
    String? from,
    String? to,
  }) async {
    final r = await _get('/api/v2/ftth/requests', {
      'page': page,
      'q': q,
      'type': type,
      'status': status,
      'action': actionRequired ? '1' : null,
      'zone': zone,
      'from': from,
      'to': to,
    });
    return r.ok ? NationalResult.ok(_page(r.data!, NationalRequest.fromJson)) : NationalResult.fail(r.error, relogin: r.relogin);
  }

  /// طلبٌ واحد (تفاصيله حسب نوعه + سجلّه) — null داخل ok = pending.
  static Future<NationalResult<NationalRequestDetail?>> request(String id, String type) async {
    final r = await _get('/api/v2/ftth/requests/${Uri.encodeComponent(id)}', {'type': type});
    if (!r.ok) return NationalResult.fail(r.error, relogin: r.relogin);
    if (r.data!['pending'] == true || r.data!['data'] is! Map) return const NationalResult.ok(null);
    return NationalResult.ok(NationalRequestDetail.fromJson(Map<String, dynamic>.from(r.data!['data'] as Map)));
  }

  static Future<NationalResult<NationalPage<NationalTask>>> tasks({
    int page = 1,
    String? q,
    String? zone,
    String? from,
    String? to,
  }) async {
    final r = await _get('/api/v2/ftth/tasks', {'page': page, 'q': q, 'zone': zone, 'from': from, 'to': to});
    return r.ok ? NationalResult.ok(_page(r.data!, NationalTask.fromJson)) : NationalResult.fail(r.error, relogin: r.relogin);
  }

  /// الإيرادات (revenue=true) أو حركات محفظة الوكيل لنافذة تاريخ (YYYY-MM-DD بتوقيت بغداد).
  static Future<NationalResult<NationalPage<NationalMoneyRow>>> money({
    required bool revenue,
    required String from,
    required String to,
    int page = 1,
    String? q,
    String? type,
    String? method,
    String? min,
    String? max,
  }) async {
    final r = await _get(revenue ? '/api/v2/ftth/transactions' : '/api/v2/ftth/wallet', {
      'from': from,
      'to': to,
      'page': page,
      'q': revenue ? q : null,
      'types': revenue ? null : type,
      'method': revenue ? null : method,
      'min': min,
      'max': max,
    });
    return r.ok ? NationalResult.ok(_page(r.data!, NationalMoneyRow.fromJson)) : NationalResult.fail(r.error, relogin: r.relogin);
  }

  /// «محفظتي» (حركات محفظة الوكيل: الرئيسيّة والعمولة) أو «التحويلات» ([transfers]: كلّ المحافظ التي يراها الحساب، ومنها محافظ
  /// المشتركين — دفعهم بالبطاقة). الفترة YYYY-MM-DD بتوقيت بغداد (حتى ٩٢ يوماً)؛ [group] مجموعة أنواع (activations · topups · refunds
  /// · commissions)، [type] نوعٌ واحد، [wallet] main|commission، [owner] partner|customer (التحويلات)، [method] طريقة الدفع (التحويلات)،
  /// [change] scheduled|instant، [sales] upfront|installment، [tx] رقم المعاملة، [sub] رقم الاشتراك، [q] رمز الاشتراك أو اسم المشترك،
  /// [mine] حركاتي أنا وحدي (المنفّذ). ما كان «الكلّ» لا يُرسل — إلّا محفظة «محفظتي»: `wallet=all` صريحةً (بلاها الرئيسيّة وحدها).
  static Future<NationalResult<NationalPage<NationalMoneyRow>>> wallet({
    bool transfers = false,
    String? from,
    String? to,
    int page = 1,
    int? size,
    String? group,
    String? type,
    String? wallet,
    String? owner,
    String? method,
    String? change,
    String? sales,
    String? tx,
    String? sub,
    String? q,
    bool mine = false,
  }) async {
    final r = await _get(transfers ? '/api/v2/ftth/transfers' : '/api/v2/ftth/wallet', walletQuery(
      transfers: transfers,
      from: from,
      to: to,
      page: page,
      size: size,
      group: group,
      type: type,
      wallet: wallet,
      owner: owner,
      method: method,
      change: change,
      sales: sales,
      tx: tx,
      sub: sub,
      q: q,
      mine: mine,
    ));
    return r.ok ? NationalResult.ok(_page(r.data!, NationalMoneyRow.fromJson)) : NationalResult.fail(r.error, relogin: r.relogin);
  }

  /// معاملات «محفظتي»/«التحويلات» كما تُرسل (الفارغ يسقط في [_get]).
  @visibleForTesting
  static Map<String, Object?> walletQuery({
    bool transfers = false,
    String? from,
    String? to,
    int page = 1,
    int? size,
    String? group,
    String? type,
    String? wallet,
    String? owner,
    String? method,
    String? change,
    String? sales,
    String? tx,
    String? sub,
    String? q,
    bool mine = false,
  }) {
    String? opt(String? v) => v == null || v.isEmpty || v == 'all' ? null : v;
    return {
      'from': from,
      'to': to,
      'page': page,
      'size': size,
      'group': opt(group),
      'types': opt(type),
      // «محفظتي»: المحفظة صريحةً دائماً — الخادم بلاها يردّ الرئيسيّة وحدها (توافقاً مع النسخ الأقدم)، فـ«الكلّ» = all.
      // و«التحويلات» افتراضها الكلّ عند الخادم: «الكلّ» لا يُرسل
      'wallet': transfers ? opt(wallet) : (opt(wallet) ?? 'all'),
      'owner': transfers ? opt(owner) : null,
      'method': transfers ? opt(method) : null,
      'change': opt(change),
      'sales': opt(sales),
      'tx': opt(tx?.trim()),
      'sub': opt(sub?.trim()),
      'q': opt(q?.trim()),
      'by': mine ? 'me' : null,
    };
  }

  /* ───────────── الكتابة ───────────── */

  static const summaryMax = 150;
  static const detailsMax = 2000;
  static const commentMax = 1000;
  static const reasonMax = 300;

  static Future<NationalWrite> _write(String method, String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.request<Map<String, dynamic>>(path, data: body, options: Options(method: method));
      final b = r.data ?? const {};
      if (b['success'] == true) {
        return NationalWrite(NationalWriteState.ok, data: b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const {});
      }
      if (b['code'] == 'UNCONFIRMED') {
        return NationalWrite(NationalWriteState.unconfirmed, message: _sn(b['message']) ?? 'لم تتأكّد النتيجة — تحقّق قبل الإعادة', code: 'UNCONFIRMED');
      }
      return NationalWrite(NationalWriteState.failed, message: _writeMsg(b), portalMessage: _sn(b['portal_message']), code: _sn(b['code']));
    } on DioException catch (e) {
      final b = e.response?.data;
      if (!kReleaseMode) debugPrint('🔴 $method $path: ${e.response?.statusCode}');
      if (b is Map) {
        return NationalWrite(NationalWriteState.failed, message: _writeMsg(b), portalMessage: _sn(b['portal_message']), code: _sn(b['code']));
      }
      return const NationalWrite(NationalWriteState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $method $path: $e');
      return const NationalWrite(NationalWriteState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    }
  }

  static String _writeMsg(dynamic b) {
    final m = b is Map ? b['message']?.toString().trim() : null;
    return (m != null && m.isNotEmpty && m.length < 220) ? m : 'تعذّر التنفيذ — لم يتغيّر شيء';
  }

  /// مرجع نموذجٍ جديد (UUID v4) — ticketId عند البوّابة.
  static String newRef([Random? rnd]) {
    final r = rnd ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// مشتركون للتذكرة (الاسم/اليوزر/الهاتف ≥ حرفين) — من بحث الخادم بحقول الوطنيّ.
  static Future<List<NationalTarget>?> searchTargets(String q) async {
    final t = q.trim();
    if (t.length < 2) return const [];
    final r = await _get('/api/subscribers/search', {'search': t, 'count': 12});
    if (!r.ok) return null;
    return (r.data!['data'] is List ? r.data!['data'] as List : const [])
        .whereType<Map>()
        .map((m) => NationalTarget.fromJson(Map<String, dynamic>.from(m)))
        .whereType<NationalTarget>()
        .toList();
  }

  /// فتح تذكرة: لمشترك (customerId + زون اشتراكه) أو للزون (بلا customerId). `ref` يبقى نفسه لإعادة «تحقّق».
  static Future<NationalWrite> createTicket({
    required String ref,
    required String category,
    required String summary,
    required String details,
    required String zone,
    String? customerId,
    String? subscriber,
  }) =>
      _write('POST', '/api/v2/ftth/tickets', {
        'client_ref': ref,
        'category': category,
        'summary': summary.trim(),
        'details': details.trim(),
        'zone': zone,
        if (customerId != null && customerId.isNotEmpty) 'customer_id': customerId,
        if (subscriber != null && subscriber.isNotEmpty) 'subscriber': subscriber,
      });

  static Future<NationalWrite> comment(String ticketId, String text) =>
      _write('POST', '/api/v2/ftth/tickets/${Uri.encodeComponent(ticketId)}/comments', {'text': text.trim()});

  /// موعد الزيارة: اليوم «YYYY-MM-DD» والساعة «HH:MM» بتوقيت بغداد (٩ص–١١م).
  static Future<NationalWrite> schedule(String ticketId, {required String date, required String time, required String reason}) =>
      _write('PUT', '/api/v2/ftth/tickets/${Uri.encodeComponent(ticketId)}/schedule', {'date': date, 'time': time, 'reason': reason.trim()});

  static Future<NationalWrite> cancelRequest(String requestId, String type) =>
      _write('POST', '/api/v2/ftth/requests/${Uri.encodeComponent(requestId)}/cancel', {'confirm': true, 'type': type});

  static Future<NationalLookups?> lookups() async {
    final r = await _get('/api/v2/ftth/lookups', const {});
    if (!r.ok || r.data!['data'] is! Map) return null;
    return NationalLookups.fromJson(Map<String, dynamic>.from(r.data!['data'] as Map));
  }

  /// العدّادات — والنداء نفسه يُدفئ بالخادم القوائم البطيئة فتفتح فوراً.
  static Future<NationalCounts?> counts() async {
    final r = await _get('/api/v2/ftth/counts', const {});
    if (!r.ok || r.data!['data'] is! Map) return null;
    final d = r.data!['data'] as Map;
    return NationalCounts(
      tasksOpen: _int(d['tasks_open']),
      requestsOpen: _int(d['requests_open']),
      actionRequired: _int(d['requests_action_required']),
    );
  }
}
