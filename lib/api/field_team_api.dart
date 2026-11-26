import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/error_text.dart';
import '../core/util/server_time.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';
import '../services/employee_visibility.dart';

/// «الصيانة والمبيعات» — الفريق الميدانيّ لكلّ مدير (٢٣ نوفمبر — المالك: «كل مدير عنده قسم خاص به اللي هو قسم الصيانة … بموظفين
/// منفصلين … او يقدر يسند نفس الموظف … رابط تطبيق»). الخادم server/fieldTeam (`/api/v2/field/*`)، والموقع /v2/field-team (7ccfb8e)
/// هو المرجع: المهامّ، والفريق، والأنواع والإسناد. الفنّي يعمل من رابطه [kFieldTeamAppUrl] لا من هذا التطبيق.
///
/// المرحلة الأولى للمدير وحده: الموظّف يرى البند مقفلاً بمكانه («لمدير الصفحة وحده الآن»)، والمقيَّد بمديرٍ فرعيّ لا يراه (الخادم
/// يقول available=false). المفتاح `field_team` بالخادم — غائبٌ حتى يُفتح للحساب. كلّ النداءات للشركة المفتوحة صراحةً
/// ([CompanyRoute.explicit]) — «كل الشركات» لا تمرّرها، فالقسم لكلّ صفحةٍ وحدها كالموقع.
const kFieldTeamAppUrl = 'https://pro.mysvcs.net/team/';

/// حالات المهمّة كما يرسلها الخادم (core.STATUSES). paused (٢٦ نوفمبر): علّقها الفنّي (أو أجّلها لموعد — [FieldTask.holdUntil])،
/// والمدير يستأنفها لنفسه أو لغيره.
const kFieldStatuses = ['new', 'assigned', 'on_way', 'working', 'done', 'failed', 'cancelled', 'paused'];

/// أسماء الحالات (core.STATUS_LABELS) — للحالة التي لا يرسل الخادم اسمها (لا يحدث عادةً).
const kFieldStatusLabels = <String, String>{
  'new': 'بانتظار الإسناد',
  'assigned': 'مُسندة',
  'on_way': 'في الطريق',
  'working': 'قيد العمل',
  'done': 'منجزة',
  'failed': 'تعذّرت',
  'cancelled': 'ملغاة',
  'paused': 'معلّقة',
};

/// أنواع العمل (core.ROLES) بترتيب الموقع.
const kFieldRoles = <({String key, String label})>[
  (key: 'tech', label: 'فنّي صيانة'),
  (key: 'sales', label: 'مبيعات وترويج'),
  (key: 'both', label: 'صيانة ومبيعات'),
];

String fieldRoleLabel(String role) => kFieldRoles.firstWhere((r) => r.key == role, orElse: () => kFieldRoles.first).label;

/// مراحل المهمّة كما يراها الفنّي (مُسندة ← في الطريق ← قيد العمل ← منجزة)، و«بانتظار الإسناد» قبلها كلّها.
const kFieldSteps = <({String key, String label})>[
  (key: 'assigned', label: 'مُسندة'),
  (key: 'on_way', label: 'في الطريق'),
  (key: 'working', label: 'قيد العمل'),
  (key: 'done', label: 'منجزة'),
];

/// موضع الحال من المراحل: -1 بانتظار الإسناد، null لما خرج منها (تعذّرت/ملغاة).
int? fieldStepAt(String status) => switch (status) {
      'new' => -1,
      'assigned' => 0,
      'on_way' => 1,
      'working' => 2,
      'done' => 3,
      _ => null,
    };

/// شرائح القائمة (الموقع: FILTERS — ٢٦ نوفمبر «فلتر المهمام وكل»: «الكلّ» أوّلاً، والمعلّقة والمنجزة والملغاة) — والخادم يفهمها بأسمائها.
enum FieldTaskFilter {
  all('all', 'الكلّ'),
  waiting('new', 'بانتظار الإسناد'),
  active('active', 'الجارية'),
  paused('paused', 'المعلّقة'),
  failed('failed', 'تعذّرت'),
  done('done', 'المنجزة'),
  cancelled('cancelled', 'الملغاة');

  const FieldTaskFilter(this.wire, this.label);
  final String wire;
  final String label;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString().trim() ?? '');
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().trim() ?? '');
}

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

DateTime? _time(Object? v) => parseServerUtc(_str(v));

({double lat, double lng})? _loc(Object? v) {
  final m = _map(v);
  final lat = _num(m['lat']);
  final lng = _num(m['lng']);
  if (lat == null || lng == null) return null;
  return (lat: lat, lng: lng);
}

/// ملخّص القسم (`GET /api/v2/field/summary`): available=false ⇒ البند غائب؛ canManage=false ⇒ موظّف (مقفلٌ بمكانه).
class FieldSummary {
  const FieldSummary({
    required this.available,
    required this.canManage,
    this.canReopen = true,
    this.canAdmin = true,
    this.waiting = 0,
    this.active = 0,
    this.failed = 0,
    this.paused = 0,
    this.doneToday = 0,
    this.staffCount = 0,
  });

  factory FieldSummary.fromJson(Map<String, dynamic> j) {
    final c = _map(j['counts']);
    final manage = _bool(j['can_manage']);
    return FieldSummary(
      available: _bool(j['available']),
      canManage: manage,
      // خادمٌ أقدم بلا الحقلين: المدير وحده يدير القسم ⇒ كلّه له
      canReopen: j.containsKey('can_reopen') ? _bool(j['can_reopen']) : manage,
      canAdmin: j.containsKey('can_admin') ? _bool(j['can_admin']) : manage,
      waiting: _int(c['new']) ?? 0,
      active: _int(c['active']) ?? 0,
      failed: _int(c['failed']) ?? 0,
      paused: _int(c['paused']) ?? 0,
      doneToday: _int(c['done_today']) ?? 0,
      staffCount: _int(j['staff_count']) ?? 0,
    );
  }

  final bool available;

  /// القسم مفتوحٌ له: المدير، أو موظّفٌ بصلاحيّة «الصيانة والمبيعات» (field.view — ٢٦ نوفمبر).
  final bool canManage;

  /// إعادة الفتح والاستئناف وتغيير المُسندة والإلغاء (المدير، أو موظّفٌ بـfield.reopen).
  final bool canReopen;

  /// إدارة الفريق (الحسابات وكلمات المرور) والأنواع — مدير الصفحة وحده.
  final bool canAdmin;

  /// «بانتظار الإسناد».
  final int waiting;

  /// عند الفريق: مُسندة + في الطريق + قيد العمل.
  final int active;
  final int failed;
  final int paused;
  final int doneToday;
  final int staffCount;

  int countOf(FieldTaskFilter f) => switch (f) {
        FieldTaskFilter.waiting => waiting,
        FieldTaskFilter.active => active,
        FieldTaskFilter.paused => paused,
        FieldTaskFilter.failed => failed,
        _ => 0,
      };
}

class FieldStaff {
  const FieldStaff({
    required this.id,
    required this.kind,
    required this.fullName,
    required this.role,
    required this.roleLabel,
    required this.isActive,
    this.phone,
    this.address,
    this.username,
    this.employeeId,
    this.lastLoginAt,
    this.lastSeenAt,
    this.activeTasks = 0,
    this.pausedTasks = 0,
    this.doneToday = 0,
  });

  static FieldStaff? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final role = _str(j['role']) ?? 'tech';
    return FieldStaff(
      id: id,
      kind: _str(j['kind']) == 'employee' ? 'employee' : 'own',
      fullName: _str(j['full_name']) ?? '',
      phone: _str(j['phone']),
      address: _str(j['address']),
      role: role,
      roleLabel: _str(j['role_label']) ?? fieldRoleLabel(role),
      isActive: _bool(j['is_active']),
      username: _str(j['username']),
      employeeId: _int(j['employee_id']),
      lastLoginAt: _time(j['last_login_at']),
      lastSeenAt: _time(j['last_seen_at']),
      activeTasks: _int(j['active_tasks']) ?? 0,
      pausedTasks: _int(j['paused_tasks']) ?? 0,
      doneToday: _int(j['done_today']) ?? 0,
    );
  }

  final int id;

  /// `own` حسابٌ ميدانيّ مستقلّ (يُحسب من حدّ الموظّفين) · `employee` موظّفٌ موجود يدخل بحسابه.
  final String kind;
  final String fullName;
  final String? phone;
  final String? address;
  final String role;
  final String roleLabel;
  final bool isActive;
  final String? username;
  final int? employeeId;
  final DateTime? lastLoginAt;
  final DateTime? lastSeenAt;
  final int activeTasks;

  /// المعلّقة عنده (بانتظار قرار المدير) — ٢٦ نوفمبر.
  final int pausedTasks;

  /// أنجزها اليوم (بتوقيت بغداد).
  final int doneToday;

  bool get isOwn => kind == 'own';

  /// «نشِطٌ الآن»: ظهر خلال ٥ دقائق (الخادم يحدّث آخر ظهوره كلّ دقيقتين ما دام تطبيق الفريق مفتوحاً) — كالموقع isLive.
  bool liveAt(DateTime now) {
    final t = lastSeenAt;
    return isActive && t != null && now.difference(t) < const Duration(minutes: 5);
  }
}

class FieldTicketCategory {
  const FieldTicketCategory(this.key, this.label);
  final String key;
  final String label;
}

class FieldType {
  const FieldType({
    required this.id,
    required this.name,
    required this.ticketCategories,
    required this.assignMode,
    required this.isActive,
    this.defaultStaffId,
  });

  static FieldType? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final cats = j['ticket_categories'];
    return FieldType(
      id: id,
      name: _str(j['name']) ?? '',
      ticketCategories: cats is List
          ? [
              for (final c in cats)
                if (_str(c) != null) _str(c)!
            ]
          : const [],
      assignMode: _str(j['assign_mode']) == 'auto' ? 'auto' : 'manual',
      defaultStaffId: _int(j['default_staff_id']),
      isActive: j['is_active'] == null || _bool(j['is_active']),
    );
  }

  final int id;
  final String name;
  final List<String> ticketCategories;

  /// `auto` يُسند فوراً لـ[defaultStaffId] · `manual` ينتظر في «بانتظار الإسناد».
  final String assignMode;
  final int? defaultStaffId;
  final bool isActive;

  bool get isAuto => assignMode == 'auto';
}

class FieldSubscriber {
  const FieldSubscriber({this.name, this.username, this.phone, this.phone2, this.idx});
  final String? name;
  final String? username;
  final String? phone;

  /// الرقم الثاني (٢٦ نوفمبر — «أرقام تواصل إضافيّة» أو ما كُتب).
  final String? phone2;

  /// رقم المشترك عند شركته — لقراءة كلمة مروره وإرسالها للفنّي.
  final String? idx;

  /// الرقم الأوّل، وبلاه الثاني.
  String? get mainPhone => (phone ?? '').isNotEmpty ? phone : phone2;

  /// الثاني حين يوجد الأوّل.
  String? get otherPhone => (phone ?? '').isNotEmpty && (phone2 ?? '').isNotEmpty ? phone2 : null;

  /// الاسم، وإلّا اسم الدخول — و«ما يراه الموظّف»: اليوزر مخفيّ ⇒ «بلا اسم».
  String? get title => !Sees.usernames && (username ?? '').isNotEmpty ? Sees.nameOf(name, username!) : (name ?? username);
}

class FieldTask {
  const FieldTask({
    required this.id,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.source,
    required this.actions,
    this.details,
    this.typeId,
    this.typeName,
    this.ticketId,
    this.subscriber,
    this.address,
    this.location,
    this.assignedStaffId,
    this.assignedStaffName,
    this.failReason,
    this.createdBy,
    this.createdAt,
    this.assignedAt,
    this.updatedAt,
    this.holdUntil,
    this.holdReason,
    this.credentialsSent = false,
  });

  static FieldTask? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final raw = _str(j['status']) ?? 'new';
    final status = kFieldStatuses.contains(raw) ? raw : 'new';
    final sub = _map(j['subscriber']);
    final subscriber = FieldSubscriber(
      name: _str(sub['name']),
      username: _str(sub['username']),
      phone: _str(sub['phone']),
      phone2: _str(sub['phone2']),
      idx: _str(sub['idx']),
    );
    final acts = j['actions'];
    return FieldTask(
      id: id,
      title: _str(j['title']) ?? '',
      details: _str(j['details']),
      status: status,
      statusLabel: _str(j['status_label']) ?? kFieldStatusLabels[status]!,
      typeId: _int(j['type_id']),
      typeName: _str(j['type_name']),
      source: _str(j['source']) == 'ticket' ? 'ticket' : 'manual',
      ticketId: _int(j['ticket_id']),
      subscriber: subscriber.name == null && subscriber.username == null && subscriber.phone == null && subscriber.phone2 == null
          ? null
          : subscriber,
      address: _str(j['address']),
      location: _loc(j['location']),
      assignedStaffId: _int(j['assigned_staff_id']),
      assignedStaffName: _str(j['assigned_staff_name']),
      failReason: _str(j['fail_reason']),
      createdBy: _str(j['created_by']),
      createdAt: _time(j['created_at']),
      assignedAt: _time(j['assigned_at']),
      updatedAt: _time(j['updated_at']),
      holdUntil: _time(j['hold_until']),
      holdReason: _str(j['hold_reason']),
      credentialsSent: _bool(j['credentials_sent']),
      actions: acts is List
          ? {
              for (final a in acts)
                if (_str(a) != null) _str(a)!
            }
          : const <String>{},
    );
  }

  final int id;
  final String title;
  final String? details;
  final String status;
  final String statusLabel;
  final int? typeId;
  final String? typeName;

  /// `ticket` من تذكرة المشترك · `manual` أنشأها المدير.
  final String source;
  final int? ticketId;
  final FieldSubscriber? subscriber;
  final String? address;
  final ({double lat, double lng})? location;
  final int? assignedStaffId;
  final String? assignedStaffName;
  final String? failReason;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? updatedAt;

  /// موعد التأجيل (المعلّقة بموعد = «مؤجّلة») وسبب التعليق كما كتبه الفنّي.
  final DateTime? holdUntil;
  final String? holdReason;

  /// أُرسل يوزر المشترك وكلمة مروره للفنّي (المدير لا يرى كلمة المرور هنا).
  final bool credentialsSent;

  /// ما يُتاح للمدير الآن (core.managerActions): assign · cancel · reopen.
  final Set<String> actions;

  bool get fromTicket => source == 'ticket';
  bool get isPaused => status == 'paused';

  /// حالٌ تُرسل فيها بيانات الدخول (الخادم core.CRED_STATUSES).
  bool get credentialsOpen => const {'new', 'assigned', 'on_way', 'working', 'paused'}.contains(status);
}

class FieldEvent {
  const FieldEvent({
    required this.id,
    required this.side,
    required this.who,
    required this.kind,
    this.statusTo,
    this.statusLabel,
    this.note,
    this.hasImage = false,
    this.location,
    this.createdAt,
    this.holdUntil,
  });

  static FieldEvent? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    return FieldEvent(
      id: id,
      side: _str(j['side']) ?? 'system',
      who: _str(j['who']) ?? '',
      kind: _str(j['kind']) ?? 'note',
      statusTo: _str(j['status_to']),
      statusLabel: _str(j['status_label']),
      note: _str(j['note']),
      hasImage: _bool(j['has_image']),
      location: _loc(j['location']),
      createdAt: _time(j['created_at']),
      holdUntil: _time(j['hold_until']),
    );
  }

  final int id;

  /// موعد التأجيل في سطر «معلّقة/مؤجّلة».
  final DateTime? holdUntil;

  /// manager · employee · staff · system.
  final String side;
  final String who;

  /// created · assigned · status · note · unassigned.
  final String kind;
  final String? statusTo;
  final String? statusLabel;
  final String? note;
  final bool hasImage;
  final ({double lat, double lng})? location;
  final DateTime? createdAt;
}

/// مهمّة تذكرةٍ («حوّلها مهمّة» — `GET /api/v2/field/ticket-tasks`): شارة قائمة التذاكر وسطر محادثتها.
class FieldTicketTask {
  const FieldTicketTask({required this.id, required this.status, required this.statusLabel, this.assignedStaffName, this.typeName});

  static FieldTicketTask? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    if (id == null) return null;
    final raw = _str(j['status']) ?? 'new';
    final status = kFieldStatuses.contains(raw) ? raw : 'new';
    return FieldTicketTask(
      id: id,
      status: status,
      statusLabel: _str(j['status_label']) ?? kFieldStatusLabels[status]!,
      assignedStaffName: _str(j['assigned_staff_name']),
      typeName: _str(j['type_name']),
    );
  }

  final int id;
  final String status;
  final String statusLabel;
  final String? assignedStaffName;
  final String? typeName;
}

// ─────────── حركات الشخص والفريق (٢٦ نوفمبر — «عرض حركات كل موظف ونوعها وعددها») ───────────

/// فترة الحركات: اليوم (بتوقيت بغداد) · ٧ أيّام · ٣٠ يوماً · الكلّ.
enum FieldPeriod {
  today('today', 'اليوم'),
  week('7d', '٧ أيّام'),
  month('30d', '٣٠ يوماً'),
  all('all', 'الكلّ');

  const FieldPeriod(this.wire, this.label);
  final String wire;
  final String label;
}

/// أنواع الحركة بترتيب العرض (الخادم core.MOVES).
const kFieldMoves = ['done', 'failed', 'paused', 'working', 'on_way', 'assigned', 'note', 'unassigned'];
const kFieldMoveLabels = <String, String>{
  'assigned': 'استلم',
  'on_way': 'في الطريق',
  'working': 'بدأ العمل',
  'done': 'أنجز',
  'failed': 'تعذّر',
  'paused': 'علّق',
  'note': 'ملاحظة',
  'unassigned': 'سُحبت منه',
};

Map<String, int> _counts(Object? v) {
  final m = _map(v);
  return {for (final k in kFieldMoves) k: _int(m[k]) ?? 0};
}

class FieldMove {
  const FieldMove({
    required this.id,
    required this.taskId,
    required this.taskTitle,
    required this.move,
    required this.moveLabel,
    this.subscriberName,
    this.typeName,
    this.by,
    this.note,
    this.holdUntil,
    this.createdAt,
  });

  static FieldMove? fromJson(Map<String, dynamic> j) {
    final id = _int(j['id']);
    final move = _str(j['move']);
    if (id == null || move == null) return null;
    return FieldMove(
      id: id,
      taskId: _int(j['task_id']) ?? 0,
      taskTitle: _str(j['task_title']) ?? '',
      move: move,
      moveLabel: _str(j['move_label']) ?? kFieldMoveLabels[move] ?? move,
      subscriberName: _str(j['subscriber_name']),
      typeName: _str(j['type_name']),
      by: _str(j['by']),
      note: _str(j['note']),
      holdUntil: _time(j['hold_until']),
      createdAt: _time(j['created_at']),
    );
  }

  final int id;
  final int taskId;
  final String taskTitle;
  final String move;
  final String moveLabel;
  final String? subscriberName;
  final String? typeName;
  final String? by;
  final String? note;
  final DateTime? holdUntil;
  final DateTime? createdAt;
}

class FieldStaffActivity {
  const FieldStaffActivity({
    required this.counts,
    required this.total,
    required this.byType,
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });

  /// [counts]/[total]/[byType] مع الصفحة الأولى وحدها (null بعدها).
  final Map<String, int>? counts;
  final int? total;
  final List<({String name, int total, Map<String, int> counts})>? byType;
  final List<FieldMove> items;
  final bool hasMore;
  final int nextOffset;
}

class FieldTeamMoves {
  const FieldTeamMoves(
      {required this.staffId,
      required this.fullName,
      required this.isActive,
      required this.deleted,
      required this.counts,
      required this.total});
  final int staffId;
  final String fullName;
  final bool isActive;
  final bool deleted;
  final Map<String, int> counts;
  final int total;
}

class FieldTasksPage {
  const FieldTasksPage({required this.items, required this.hasMore, required this.nextOffset});
  final List<FieldTask> items;
  final bool hasMore;
  final int nextOffset;
}

/// النتيجة بلا استثناء للواجهة: `ok` أو رسالة الخادم العربيّة كما هي (`message`).
typedef FieldResult = ({bool ok, String? error});

/// مشتركٌ من البحث في مشتركيه — ومعه رقمه وموقعه المحفوظ (٢٦ نوفمبر).
typedef FieldSearchHit = ({
  String username,
  String name,
  String? phone,
  String? package,
  String? idx,
  ({double lat, double lng})? location
});

class FieldTeamApi {
  FieldTeamApi._();

  static const base = '/api/v2/field';

  /// حجم الصفحة كالموقع (PAGE_SIZE).
  static const pageSize = 30;

  static void _log(String where, Object e) {
    if (kDebugMode) debugPrint('[FieldTeamApi] $where: $e');
  }

  /// للشركة المفتوحة صراحةً — لا قسمٌ موجَّه يمرّرها لغيرها.
  static Options _opts([Options? o]) => CompanyRoute.explicit(null, o);

  /// رسالة الخادم الجاهزة من ردٍّ بلا نجاح، وإلّا [fallback].
  static String _msg(Object? body, String fallback) => _str(_map(body)['message']) ?? fallback;

  /// رسالة الخادم من استثناء Dio (5xx يرمي)، وإلّا نصّ الخطأ البشريّ.
  static String _errOf(Object e, String fallback) {
    if (e is DioException) {
      final m = _str(_map(e.response?.data)['message']);
      if (m != null) return m;
    }
    return humanError(e, fallback: fallback);
  }

  static bool _ok(Response<Object?> r) => (r.statusCode ?? 0) < 300 && _map(r.data)['success'] == true;

  /// ملخّص القسم لهذا المستخدم. null = تعذّر الوصول (يُعاد لاحقاً) أو لا جلسة — لا شيء يظهر بلا تأكيد.
  static Future<FieldSummary?> summary() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('$base/summary', options: _opts());
      final code = r.statusCode ?? 0;
      final body = _map(r.data);
      // خادمٌ أقدم بلا المسار، أو مزوّدٌ ردّه الآمن بلا available ⇒ غير متاح.
      if (code == 404 || code == 400) return const FieldSummary(available: false, canManage: false);
      if (code == 403) return const FieldSummary(available: false, canManage: false);
      if (code >= 400 || body['success'] != true) return null;
      return FieldSummary.fromJson(body);
    } catch (e) {
      _log('summary', e);
      return null;
    }
  }

  // ── الفريق ──

  static Future<({List<FieldStaff>? items, String? error})> staff() async {
    try {
      final r = await ApiClient.dio.get<Object?>('$base/staff', options: _opts());
      if (!_ok(r)) return (items: null, error: _msg(r.data, 'تعذّر جلب الفريق'));
      final raw = _map(r.data)['items'];
      return (
        items: raw is List
            ? [for (final m in raw.whereType<Map>()) FieldStaff.fromJson(_map(m))].whereType<FieldStaff>().toList()
            : <FieldStaff>[],
        error: null,
      );
    } catch (e) {
      _log('staff', e);
      return (items: null, error: _errOf(e, 'تعذّر جلب الفريق'));
    }
  }

  /// حسابٌ ميدانيّ مستقلّ (يُحسب من حدّ الموظّفين في الباقة).
  static Future<({FieldStaff? staff, String? error})> createOwn({
    required String fullName,
    required String username,
    required String password,
    required String role,
    String? phone,
    String? address,
  }) =>
      _createStaff({
        'full_name': fullName,
        'username': username,
        'password': password,
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (address != null && address.isNotEmpty) 'address': address,
      });

  /// موظّفٌ موجود يدخل تطبيق الفريق بحسابه نفسه — بلا مقعدٍ جديد.
  static Future<({FieldStaff? staff, String? error})> linkEmployee({
    required int employeeId,
    required String role,
    String? phone,
    String? address,
  }) =>
      _createStaff({
        'employee_id': employeeId,
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (address != null && address.isNotEmpty) 'address': address,
      });

  static Future<({FieldStaff? staff, String? error})> _createStaff(Map<String, Object?> body) async {
    try {
      final r = await ApiClient.dio.post<Object?>('$base/staff', data: body, options: _opts());
      if (!_ok(r)) return (staff: null, error: _msg(r.data, 'تعذّرت الإضافة'));
      final s = FieldStaff.fromJson(_map(_map(r.data)['staff']));
      return (staff: s, error: s == null ? 'تعذّرت الإضافة' : null);
    } catch (e) {
      _log('staff create', e);
      return (staff: null, error: _errOf(e, 'تعذّرت الإضافة'));
    }
  }

  /// تعديلٌ جزئيّ: {full_name, phone, address, role, is_active, password}. [released] = مهامّ رجعت «بانتظار الإسناد» (الإيقاف).
  static Future<({bool ok, int released, String? error})> updateStaff(int id, Map<String, Object?> body) async {
    try {
      final r = await ApiClient.dio.put<Object?>('$base/staff/$id', data: body, options: _opts());
      if (!_ok(r)) return (ok: false, released: 0, error: _msg(r.data, 'تعذّر الحفظ'));
      return (ok: true, released: _int(_map(r.data)['released_tasks']) ?? 0, error: null);
    } catch (e) {
      _log('staff update', e);
      return (ok: false, released: 0, error: _errOf(e, 'تعذّر الحفظ'));
    }
  }

  static Future<({bool ok, int released, String? error})> deleteStaff(int id) async {
    try {
      final r = await ApiClient.dio.delete<Object?>('$base/staff/$id', options: _opts());
      if (!_ok(r)) return (ok: false, released: 0, error: _msg(r.data, 'تعذّر الحذف'));
      return (ok: true, released: _int(_map(r.data)['released_tasks']) ?? 0, error: null);
    } catch (e) {
      _log('staff delete', e);
      return (ok: false, released: 0, error: _errOf(e, 'تعذّر الحذف'));
    }
  }

  // ── الأنواع ──

  static Future<({List<FieldType>? items, List<FieldTicketCategory> categories, String? error})> types() async {
    try {
      final r = await ApiClient.dio.get<Object?>('$base/types', options: _opts());
      if (!_ok(r)) return (items: null, categories: const <FieldTicketCategory>[], error: _msg(r.data, 'تعذّر جلب الأنواع'));
      final body = _map(r.data);
      final raw = body['items'];
      final cats = body['ticket_categories'];
      return (
        items: raw is List
            ? [for (final m in raw.whereType<Map>()) FieldType.fromJson(_map(m))].whereType<FieldType>().toList()
            : <FieldType>[],
        categories: cats is List
            ? [
                for (final c in cats.whereType<Map>())
                  if (_str(c['key']) != null) FieldTicketCategory(_str(c['key'])!, _str(c['label']) ?? _str(c['key'])!),
              ]
            : const <FieldTicketCategory>[],
        error: null,
      );
    } catch (e) {
      _log('types', e);
      return (items: null, categories: const <FieldTicketCategory>[], error: _errOf(e, 'تعذّر جلب الأنواع'));
    }
  }

  /// [id] null ⇒ نوعٌ جديد.
  static Future<FieldResult> saveType({
    int? id,
    required String name,
    required List<String> ticketCategories,
    required String assignMode,
    int? defaultStaffId,
    required bool isActive,
  }) async {
    final body = {
      'name': name,
      'ticket_categories': ticketCategories,
      'assign_mode': assignMode,
      'default_staff_id': assignMode == 'auto' ? defaultStaffId : null,
      'is_active': isActive,
    };
    try {
      final r = id == null
          ? await ApiClient.dio.post<Object?>('$base/types', data: body, options: _opts())
          : await ApiClient.dio.put<Object?>('$base/types/$id', data: body, options: _opts());
      if (!_ok(r)) return (ok: false, error: _msg(r.data, 'تعذّر حفظ النوع'));
      return (ok: true, error: null);
    } catch (e) {
      _log('type save', e);
      return (ok: false, error: _errOf(e, 'تعذّر حفظ النوع'));
    }
  }

  static Future<FieldResult> deleteType(int id) async {
    try {
      final r = await ApiClient.dio.delete<Object?>('$base/types/$id', options: _opts());
      if (!_ok(r)) return (ok: false, error: _msg(r.data, 'تعذّر الحذف'));
      return (ok: true, error: null);
    } catch (e) {
      _log('type delete', e);
      return (ok: false, error: _errOf(e, 'تعذّر الحذف'));
    }
  }

  // ── المهامّ ──

  static Future<({FieldTasksPage? page, String? error})> tasks({
    required FieldTaskFilter filter,
    String query = '',
    int offset = 0,
    int? staffId,
    int? typeId,
  }) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$base/tasks',
        queryParameters: {
          'filter': filter.wire,
          'offset': offset,
          'limit': pageSize,
          if (query.trim().isNotEmpty) 'q': query.trim(),
          if (staffId != null) 'staff_id': staffId,
          if (typeId != null) 'type_id': typeId,
        },
        options: _opts(),
      );
      if (!_ok(r)) return (page: null, error: _msg(r.data, 'تعذّر جلب المهامّ'));
      final body = _map(r.data);
      final raw = body['items'];
      final items =
          raw is List ? [for (final m in raw.whereType<Map>()) FieldTask.fromJson(_map(m))].whereType<FieldTask>().toList() : <FieldTask>[];
      return (
        page: FieldTasksPage(
          items: items,
          hasMore: _bool(body['has_more']),
          nextOffset: _int(body['next_offset']) ?? offset + items.length,
        ),
        error: null,
      );
    } catch (e) {
      _log('tasks', e);
      return (page: null, error: _errOf(e, 'تعذّر جلب المهامّ'));
    }
  }

  static Future<({FieldTask? task, List<FieldEvent> events, String? error})> task(int id) async {
    try {
      final r = await ApiClient.dio.get<Object?>('$base/tasks/$id', options: _opts());
      if (!_ok(r)) return (task: null, events: const <FieldEvent>[], error: _msg(r.data, 'تعذّر جلب المهمّة'));
      final body = _map(r.data);
      final raw = body['events'];
      return (
        task: FieldTask.fromJson(_map(body['task'])),
        events: raw is List
            ? [for (final m in raw.whereType<Map>()) FieldEvent.fromJson(_map(m))].whereType<FieldEvent>().toList()
            : <FieldEvent>[],
        error: null,
      );
    } catch (e) {
      _log('task', e);
      return (task: null, events: const <FieldEvent>[], error: _errOf(e, 'تعذّر جلب المهمّة'));
    }
  }

  /// مهمّةٌ جديدة. [subscriber] من مشتركيه أو «تفاصيل أخرى» (null = بلا مشترك). [staffId] null ⇒ بانتظار الإسناد.
  /// ٢٦ نوفمبر: [location] موقعه المحفوظ من صفّه، و[password] كلمة مروره للفنّي (اختيار المدير)، والرقم الثاني يُكمّله الخادم إن غاب.
  static Future<({FieldTask? task, String? error})> createTask({
    String? title,
    int? typeId,
    int? staffId,
    FieldSubscriber? subscriber,
    String? address,
    String? details,
    ({double lat, double lng})? location,
    String? password,
  }) async {
    final sub = subscriber == null
        ? null
        : {
            if ((subscriber.name ?? '').isNotEmpty) 'name': subscriber.name,
            if ((subscriber.username ?? '').isNotEmpty) 'username': subscriber.username,
            if ((subscriber.phone ?? '').isNotEmpty) 'phone': subscriber.phone,
            if ((subscriber.phone2 ?? '').isNotEmpty) 'phone2': subscriber.phone2,
            if ((subscriber.idx ?? '').isNotEmpty) 'idx': subscriber.idx,
            if ((password ?? '').isNotEmpty) 'password': password,
          };
    final body = <String, Object?>{
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if (typeId != null) 'type_id': typeId,
      if (staffId != null) 'staff_id': staffId,
      if (sub != null && sub.isNotEmpty) 'subscriber': sub,
      if ((address ?? '').trim().isNotEmpty) 'address': address!.trim(),
      if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
      if (location != null) 'lat': location.lat,
      if (location != null) 'lng': location.lng,
    };
    try {
      final r = await ApiClient.dio.post<Object?>('$base/tasks', data: body, options: _opts());
      if (!_ok(r)) return (task: null, error: _msg(r.data, 'تعذّر إنشاء المهمّة'));
      return (task: FieldTask.fromJson(_map(_map(r.data)['task'])), error: null);
    } catch (e) {
      _log('task create', e);
      return (task: null, error: _errOf(e, 'تعذّر إنشاء المهمّة'));
    }
  }

  static Future<FieldResult> _post(String path, Map<String, Object?> body, String fallback) async {
    try {
      final r = await ApiClient.dio.post<Object?>(path, data: body, options: _opts());
      if (!_ok(r)) return (ok: false, error: _msg(r.data, fallback));
      return (ok: true, error: null);
    } catch (e) {
      _log('post $path', e);
      return (ok: false, error: _errOf(e, fallback));
    }
  }

  static Future<FieldResult> assign(int id, int staffId) => _post('$base/tasks/$id/assign', {'staff_id': staffId}, 'تعذّر الإسناد');

  static Future<FieldResult> cancel(int id, {String? reason}) =>
      _post('$base/tasks/$id/cancel', {if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim()}, 'تعذّر الإلغاء');

  /// إعادة الفتح أو الاستئناف (٢٦ نوفمبر): [staffId] null ⇒ لنفس الفنّي إن بقي فعّالاً (وإلّا بانتظار الإسناد)، وإلّا لمن اختاره.
  static Future<FieldResult> reopen(int id, {int? staffId}) =>
      _post('$base/tasks/$id/reopen', {if (staffId != null) 'staff_id': staffId}, 'تعذّرت إعادة الفتح');

  /// يوزر المشترك وكلمة مروره للفنّي (٢٦ نوفمبر) — تُختم بالخادم وتُمحى بانتهاء المهمّة.
  static Future<FieldResult> sendCredentials(int id, String password, {String? username}) => _post(
        '$base/tasks/$id/credentials',
        {'password': password, if ((username ?? '').trim().isNotEmpty) 'username': username!.trim()},
        'تعذّر إرسال بيانات الدخول',
      );

  static Future<FieldResult> dropCredentials(int id) async {
    try {
      final r = await ApiClient.dio.delete<Object?>('$base/tasks/$id/credentials', options: _opts());
      if (!_ok(r)) return (ok: false, error: _msg(r.data, 'تعذّر السحب'));
      return (ok: true, error: null);
    } catch (e) {
      _log('creds drop', e);
      return (ok: false, error: _errOf(e, 'تعذّر السحب'));
    }
  }

  /// كلمة مرور المشترك من شركته (`GET /api/v2/subscribers/:idx/password` — مسار «عرض كلمة المرور» نفسه بصلاحيّاته). null = تعذّرت.
  static Future<String?> subscriberPassword(String idx) async {
    if (!RegExp(r'^\d{1,20}$').hasMatch(idx)) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('/api/v2/subscribers/$idx/password', options: _opts());
      if ((r.statusCode ?? 0) >= 300) return null;
      return _str(_map(_map(r.data)['data'])['password']);
    } catch (e) {
      _log('sub password', e);
      return null;
    }
  }

  /// حركات شخص ([FieldPeriod]) بصفحاتٍ من ٣٠ — العدّ مع الأولى.
  static Future<({FieldStaffActivity? data, String? error})> staffActivity(int id, FieldPeriod period, {int offset = 0}) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$base/staff/$id/activity',
        queryParameters: {'period': period.wire, 'offset': offset, 'limit': pageSize},
        options: _opts(),
      );
      if (!_ok(r)) return (data: null, error: _msg(r.data, 'تعذّر جلب الحركات'));
      final b = _map(r.data);
      final raw = b['items'];
      final types = b['by_type'];
      return (
        data: FieldStaffActivity(
          counts: b.containsKey('counts') ? _counts(b['counts']) : null,
          total: _int(b['total']),
          byType: types is List
              ? [
                  for (final t in types.whereType<Map>())
                    (name: _str(t['type_name']) ?? 'بلا نوع', total: _int(t['total']) ?? 0, counts: _counts(t['counts'])),
                ]
              : null,
          items:
              raw is List ? [for (final m in raw.whereType<Map>()) FieldMove.fromJson(_map(m))].whereType<FieldMove>().toList() : const [],
          hasMore: _bool(b['has_more']),
          nextOffset: _int(b['next_offset']) ?? offset,
        ),
        error: null,
      );
    } catch (e) {
      _log('staff activity', e);
      return (data: null, error: _errOf(e, 'تعذّر جلب الحركات'));
    }
  }

  /// حركات الفريق مجمّعةً لكلّ شخص (الأكثر أوّلاً، ومن حُذف وله حركاتٌ موسوماً).
  static Future<({List<FieldTeamMoves>? items, String? error})> teamActivity(FieldPeriod period) async {
    try {
      final r = await ApiClient.dio.get<Object?>('$base/activity', queryParameters: {'period': period.wire}, options: _opts());
      if (!_ok(r)) return (items: null, error: _msg(r.data, 'تعذّر جلب الحركات'));
      final raw = _map(r.data)['items'];
      return (
        items: raw is List
            ? [
                for (final m in raw.whereType<Map>())
                  if (_int(m['staff_id']) != null)
                    FieldTeamMoves(
                      staffId: _int(m['staff_id'])!,
                      fullName: _str(m['full_name']) ?? '',
                      isActive: _bool(m['is_active']),
                      deleted: _bool(m['deleted']),
                      counts: _counts(m['counts']),
                      total: _int(m['total']) ?? 0,
                    ),
              ]
            : <FieldTeamMoves>[],
        error: null,
      );
    } catch (e) {
      _log('team activity', e);
      return (items: null, error: _errOf(e, 'تعذّر جلب الحركات'));
    }
  }

  static Future<FieldResult> note(int id, String note) => _post('$base/tasks/$id/note', {'note': note.trim()}, 'تعذّر إرسال الملاحظة');

  /// موظّفو الصفحة الفعّالون لـ«موظّف موجود» (`GET /api/v2/employees` — قائمة قسم الموظّفين نفسها، للمفتوحة صراحةً).
  static Future<({List<({int id, String username, String name})>? items, String? error})> employees() async {
    try {
      final r = await ApiClient.dio.get<Object?>('/api/v2/employees', options: _opts());
      final body = _map(r.data);
      if ((r.statusCode ?? 0) >= 300 || body['success'] != true) return (items: null, error: _msg(r.data, 'تعذّر جلب الموظّفين'));
      final raw = body['data'];
      final out = <({int id, String username, String name})>[];
      if (raw is List) {
        for (final m in raw.whereType<Map>()) {
          final j = _map(m);
          final id = _int(j['id']);
          final user = _str(j['username']);
          if (id == null || user == null) continue;
          if (j['is_active'] != null && !_bool(j['is_active'])) continue;
          if (_str(j['deleted_at']) != null) continue;
          out.add((id: id, username: user, name: _str(j['full_name']) ?? user));
        }
      }
      return (items: out, error: null);
    } catch (e) {
      _log('employees', e);
      return (items: null, error: _errOf(e, 'تعذّر جلب الموظّفين'));
    }
  }

  /// بحث «من مشتركيك» (`GET /api/subscribers/search` — بحث «بيع جديد» نفسه، يعمل للحساب الكبير أيضاً): ٨ نتائج.
  static Future<({List<FieldSearchHit>? items, String? error})> searchSubscribers(String term) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '/api/subscribers/search',
        queryParameters: {'search': term, 'count': 8},
        options: _opts(),
      );
      final body = _map(r.data);
      final raw = body['data'];
      if ((r.statusCode ?? 0) >= 300 || raw is! List) return (items: null, error: _msg(r.data, 'تعذّر البحث في مشتركيك'));
      final out = <FieldSearchHit>[];
      for (final m in raw.whereType<Map>()) {
        final j = _map(m);
        final user = _str(j['username']);
        if (user == null) continue;
        final name = [_str(j['firstname']), _str(j['lastname'])].whereType<String>().join(' ').trim();
        final lat = _num(j['latitude']);
        final lng = _num(j['longitude']);
        out.add((
          username: user,
          name: name.isEmpty ? user : name,
          phone: _str(j['phone']),
          package: _str(j['profile_name']) ?? _str(j['package_name']),
          idx: _str(j['idx']),
          // موقعه المحفوظ (حقل العنوان «gps:» — الخادم ٢٦ نوفمبر)؛ صفرٌ = لا موقع
          location: lat != null && lng != null && (lat != 0 || lng != 0) ? (lat: lat, lng: lng) : null,
        ));
        if (out.length >= 8) break;
      }
      return (items: out, error: null);
    } catch (e) {
      _log('search', e);
      return (items: null, error: _errOf(e, 'تعذّر البحث في مشتركيك'));
    }
  }

  /// مهامّ تذاكر بعينها (حتى ١٠٠): التذكرة ⇒ مهمّتها، وما لا مهمّة له غائب. null = تعذّر (لا شارةٌ ولا «حوّلها»).
  static Future<Map<int, FieldTicketTask>?> ticketTasks(Iterable<int> ids) async {
    final clean = {
      for (final i in ids)
        if (i > 0) i
    }.take(100).toList();
    if (clean.isEmpty) return const <int, FieldTicketTask>{};
    try {
      final r = await ApiClient.dio.get<Object?>('$base/ticket-tasks', queryParameters: {'ids': clean.join(',')}, options: _opts());
      if (!_ok(r)) return null;
      final items = _map(_map(r.data)['items']);
      final out = <int, FieldTicketTask>{};
      for (final e in items.entries) {
        final id = int.tryParse(e.key);
        final t = FieldTicketTask.fromJson(_map(e.value));
        if (id != null && t != null) out[id] = t;
      }
      return out;
    } catch (e) {
      _log('ticket-tasks', e);
      return null;
    }
  }

  /// «حوّلها مهمّة»: العنوان والمشترك والتفاصيل من التذكرة نفسها. الإنشاء لا يُسند بالنوع وحده ⇒ [staffId] صريحاً (كالموقع).
  /// [linked] = للتذكرة مهمّةٌ أصلاً (TICKET_LINKED).
  static Future<({FieldTask? task, String? error, bool linked})> createFromTicket(
      {required int ticketId, int? typeId, int? staffId}) async {
    final body = <String, Object?>{
      'ticket_id': ticketId,
      if (typeId != null) 'type_id': typeId,
      if (staffId != null) 'staff_id': staffId,
    };
    try {
      final r = await ApiClient.dio.post<Object?>('$base/tasks', data: body, options: _opts());
      if (!_ok(r)) {
        return (task: null, error: _msg(r.data, 'تعذّر إنشاء المهمّة'), linked: _str(_map(r.data)['code']) == 'TICKET_LINKED');
      }
      return (task: FieldTask.fromJson(_map(_map(r.data)['task'])), error: null, linked: false);
    } catch (e) {
      _log('ticket convert', e);
      return (task: null, error: _errOf(e, 'تعذّر إنشاء المهمّة'), linked: false);
    }
  }

  /// صورة حدثٍ من السجلّ بالترويسة نفسها. [expired] = حُذفت (410) أو لم تعد موجودة (404).
  static Future<({Uint8List? bytes, bool expired})> eventImage(int taskId, int eventId) async {
    try {
      final r = await ApiClient.dio.get<List<int>>(
        '$base/tasks/$taskId/events/$eventId/image',
        options: _opts(Options(responseType: ResponseType.bytes)),
      );
      final code = r.statusCode ?? 0;
      if (code == 404 || code == 410) return (bytes: null, expired: true);
      final data = r.data;
      if (code >= 300 || data == null || data.isEmpty) return (bytes: null, expired: false);
      return (bytes: Uint8List.fromList(data), expired: false);
    } catch (e) {
      _log('image', e);
      return (bytes: null, expired: false);
    }
  }
}

/// بوّابة البند في «قوائم أخرى»: ملخّص القسم للمستخدم الحاليّ (null = لم يُعرف بعد ⇒ لا يظهر). الاستماع يطلبه إن كان قديماً.
class FieldTeamState {
  FieldTeamState._();

  static final ValueNotifier<FieldSummary?> gate = _FieldGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 2);
  static const _cooldown = Duration(seconds: 30);

  /// مفتوحٌ للحساب (المدير يديره، والموظّف يراه مقفلاً).
  static bool get visible => gate.value?.available ?? false;

  static bool get canManage => gate.value?.canManage ?? false;

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = FieldTeamApi.summary().then((s) {
      if (epoch != _epoch) return;
      if (s == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = s;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// الشاشة قرأت الملخّص بنفسها ⇒ البطاقة تتبعه بلا نداءٍ ثانٍ.
  static void remember(FieldSummary s) {
    _fetchedAt = DateTime.now();
    _failedAt = null;
    gate.value = s;
  }

  /// تبديل الجلسة: لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(FieldSummary? s) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = s == null ? null : DateTime.now();
    gate.value = s;
  }
}

class _FieldGate extends ValueNotifier<FieldSummary?> {
  _FieldGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(FieldTeamState.ensureFresh);
  }
}
