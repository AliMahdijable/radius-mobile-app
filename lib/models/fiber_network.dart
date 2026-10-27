import 'package:flutter/foundation.dart';

/// شبكة الألياف — ما يحفظه الوكيل على خادمنا عن شبكة الأولت (المالك ٢٧ أكتوبر: «لاهل ال olt والوضوئي… كلشي
/// عجبني بي… ابنيها ع تطبيق الهاتف والحاسوب بدقة»).
///
/// الأولت لا يعرف الموزّعات ولا الصناديق ولا من هو المشترك خلف كلّ ONU؛ هذا كلّه وصفٌ يضعه الوكيل (أو يقترحه التطبيق
/// ويثبّته الوكيل) ويُحفظ على `/api/v2/admin/devices/fiber`. القراءات الحيّة (الحالة والضوء وسبب السقوط) يقرؤها التطبيق
/// من الأولت مباشرةً كبقيّة قسم الأجهزة.
///
/// مفتاح الـONU = اسمه على الأولت (`EPON0/3:2`)، ومعه هويّته الثابتة [FiberOnuRecord.ident] (ماك EPON أو SN لـGPON):
/// جهازٌ أُعيد تسجيله برقمٍ آخر يُعرف من هويّته فلا يضيع صندوقه ولا مشتركه.

enum FiberNodeKind { splitter, box }

/// من أين جاء ربط الـONU بالمشترك.
enum FiberLinkSource { name, mac, onuMac, manual }

/// سبب العطل الجماعيّ: قطع ليف · انطفاء كهرباء · خليط · غير معروف (الأولت لا يعطي السبب).
enum FiberEventKind { cut, power, mixed, unknown }

/// أين العطل: صندوق · موزّع · المنفذ كلّه · مجموعة أجهزة بلا صناديق معروفة.
enum FiberEventScope { box, splitter, pon, group }

extension FiberLinkSourceWire on FiberLinkSource {
  String get wire => switch (this) {
        FiberLinkSource.name => 'name',
        FiberLinkSource.mac => 'mac',
        FiberLinkSource.onuMac => 'onu_mac',
        FiberLinkSource.manual => 'manual',
      };

  static FiberLinkSource? parse(Object? v) => switch (v) {
        'name' => FiberLinkSource.name,
        'mac' => FiberLinkSource.mac,
        'onu_mac' => FiberLinkSource.onuMac,
        'manual' => FiberLinkSource.manual,
        _ => null,
      };
}

T? _enumByName<T extends Enum>(List<T> values, Object? v) {
  if (v is! String) return null;
  for (final e in values) {
    if (e.name == v) return e;
  }
  return null;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num && v == v.roundToDouble()) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

String? _str(Object? v, {int max = 200}) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return s.length > max ? s.substring(0, max) : s;
}

bool _bool(Object? v, {required bool dflt}) {
  if (v == true || v == 1 || v == '1' || v == 'true') return true;
  if (v == false || v == 0 || v == '0' || v == 'false') return false;
  return dflt;
}

/// تاريخ الخادم بالـUTC: ISO (`…Z`) أو «YYYY-MM-DD HH:MM:SS» بلا منطقة (MySQL) — كلاهما UTC.
DateTime? fiberParseUtc(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  var s = v.trim();
  if (!s.contains('T')) s = s.replaceFirst(' ', 'T');
  if (!s.endsWith('Z') && !RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s)) s = '${s}Z';
  return DateTime.tryParse(s)?.toUtc();
}

/// هويّة ONU مطبَّعة للمقارنة: ماك بلا فواصل بحروفٍ صغيرة، أو SN بحروفٍ كبيرة. `null` للفارغ.
String? fiberIdent(String? macOrSerial) {
  if (macOrSerial == null) return null;
  final s = macOrSerial.trim();
  if (s.isEmpty) return null;
  final hex = s.replaceAll(RegExp(r'[:\-.\s]'), '');
  if (RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(hex)) {
    final v = hex.toLowerCase();
    return v == '000000000000' || v == 'ffffffffffff' ? null : v;
  }
  return s.toUpperCase();
}

/// موزّعٌ أو صندوقٌ على منفذ PON بعينه. [parentId] = الموزّع فوقه، و`null` = على المنفذ مباشرةً.
@immutable
class FiberBox {
  const FiberBox({
    required this.id,
    required this.oltId,
    required this.pon,
    required this.name,
    this.parentId,
    this.kind = FiberNodeKind.box,
    this.ratio = 8,
    this.location,
    this.lat,
    this.lng,
    this.note,
  });

  /// نسب التقسيم المعروفة. ٨ و١٦ أكثرها في الصناديق، و٤ و٨ في الموزّع الرئيسي.
  static const ratios = [2, 4, 8, 16, 32, 64];

  /// رقم الخادم (> 0)، أو سالبٌ لصندوقٍ أُنشئ ولم يصل الخادم بعد.
  final int id;
  final int oltId;

  /// منفذ PON كما يسمّيه الأولت: `EPON0/3`.
  final String pon;
  final int? parentId;
  final FiberNodeKind kind;
  final String name;

  /// عدد مخارج الموزّع/الصندوق (١:٨ ⇒ ٨).
  final int ratio;
  final String? location;
  final double? lat, lng;
  final String? note;

  bool get hasGps => lat != null && lng != null;

  FiberBox copyWith({
    int? id,
    String? name,
    FiberNodeKind? kind,
    int? ratio,
    int? parentId,
    bool clearParent = false,
    String? location,
    double? lat,
    double? lng,
    bool clearGps = false,
    String? note,
  }) =>
      FiberBox(
        id: id ?? this.id,
        oltId: oltId,
        pon: pon,
        name: name ?? this.name,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        kind: kind ?? this.kind,
        ratio: ratio ?? this.ratio,
        location: location ?? this.location,
        lat: clearGps ? null : (lat ?? this.lat),
        lng: clearGps ? null : (lng ?? this.lng),
        note: note ?? this.note,
      );

  static FiberBox? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    final olt = _int(j['olt_id']);
    final pon = _str(j['pon'], max: 24);
    final name = _str(j['name'], max: 80);
    if (id == null || id == 0 || olt == null || olt <= 0 || pon == null || name == null) return null;
    final ratio = _int(j['ratio']);
    final lat = _double(j['lat']);
    final lng = _double(j['lng']);
    final gpsOk = lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);
    final parent = _int(j['parent_id']);
    return FiberBox(
      id: id,
      oltId: olt,
      pon: pon,
      name: name,
      parentId: parent == null || parent == 0 || parent == id ? null : parent,
      kind: _enumByName(FiberNodeKind.values, j['kind']) ?? FiberNodeKind.box,
      ratio: ratio != null && ratio >= 2 && ratio <= 128 ? ratio : 8,
      location: _str(j['location'], max: 120),
      lat: gpsOk ? lat : null,
      lng: gpsOk ? lng : null,
      note: _str(j['note'], max: 200),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'olt_id': oltId,
        'pon': pon,
        'name': name,
        'parent_id': parentId,
        'kind': kind.name,
        'ratio': ratio,
        'location': location,
        'lat': lat,
        'lng': lng,
        'note': note,
      };

  @override
  bool operator ==(Object other) =>
      other is FiberBox &&
      other.id == id &&
      other.oltId == oltId &&
      other.pon == pon &&
      other.name == name &&
      other.parentId == parentId &&
      other.kind == kind &&
      other.ratio == ratio &&
      other.location == location &&
      other.lat == lat &&
      other.lng == lng &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, oltId, pon, name, parentId, kind, ratio, location, lat, lng, note);
}

/// ما يُحفظ لكلّ ONU: صندوقه ومشتركه.
@immutable
class FiberOnuRecord {
  const FiberOnuRecord({
    required this.oltId,
    required this.key,
    this.ident,
    this.boxId,
    this.username,
    this.source,
    this.linkedAt,
  });

  final int oltId;

  /// اسمه على الأولت: `EPON0/3:2`.
  final String key;

  /// ماكه (EPON) أو SN (GPON) — [fiberIdent].
  final String? ident;
  final int? boxId;

  /// يوزر المشترك بالساس.
  final String? username;
  final FiberLinkSource? source;
  final DateTime? linkedAt;

  bool get linked => username != null;
  bool get isEmpty => boxId == null && username == null;

  FiberOnuRecord copyWith({
    String? key,
    String? ident,
    int? boxId,
    bool clearBox = false,
    String? username,
    FiberLinkSource? source,
    DateTime? linkedAt,
    bool clearLink = false,
  }) =>
      FiberOnuRecord(
        oltId: oltId,
        key: key ?? this.key,
        ident: ident ?? this.ident,
        boxId: clearBox ? null : (boxId ?? this.boxId),
        username: clearLink ? null : (username ?? this.username),
        source: clearLink ? null : (source ?? this.source),
        linkedAt: clearLink ? null : (linkedAt ?? this.linkedAt),
      );

  static FiberOnuRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final olt = _int(j['olt_id']);
    final key = _str(j['onu_key'], max: 40);
    if (olt == null || olt <= 0 || key == null) return null;
    final box = _int(j['box_id']);
    final user = _str(j['username'], max: 128);
    return FiberOnuRecord(
      oltId: olt,
      key: key,
      ident: fiberIdent(_str(j['ident'], max: 40)),
      boxId: box == null || box == 0 ? null : box,
      username: user,
      source: user == null ? null : FiberLinkSourceWire.parse(j['link_source']),
      linkedAt: user == null ? null : fiberParseUtc(j['linked_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'olt_id': oltId,
        'onu_key': key,
        'ident': ident,
        'box_id': boxId,
        'username': username,
        'link_source': source?.wire,
        'linked_at': linkedAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is FiberOnuRecord &&
      other.oltId == oltId &&
      other.key == key &&
      other.ident == ident &&
      other.boxId == boxId &&
      other.username == username &&
      other.source == source;

  @override
  int get hashCode => Object.hash(oltId, key, ident, boxId, username, source);
}

/// إعدادات كلّ أولت: فنّي المنطقة والتنبيهات ونصّا الرسالتين.
@immutable
class FiberOltSettings {
  const FiberOltSettings({
    required this.oltId,
    this.techName,
    this.techPhone,
    this.notifyOutages = true,
    this.notifyPower = false,
    this.minOnus = 3,
    this.msgOutage,
    this.msgBack,
  });

  static const minOnusFloor = 2;
  static const minOnusCeil = 32;

  static const defaultOutageMessage =
      'مشتركنا العزيز، صار عطل بخطّ الألياف بمنطقتكم والفنّي يشتغل عليه. نبلّغكم أوّل ما يرجع النت، ونعتذر عن الإزعاج.';
  static const defaultBackMessage = 'مشتركنا العزيز، رجع النت عندكم. شكراً لصبركم.';

  final int oltId;
  final String? techName, techPhone;

  /// إشعارٌ لأجهزة الحساب عند قطع الليف/العطل الجماعيّ.
  final bool notifyOutages;

  /// وعند انطفاء الكهرباء الجماعيّ (لا يحتاج فنّياً — مطفأٌ افتراضيّاً).
  final bool notifyPower;

  /// أقلّ عددٍ من الأجهزة الساقطة معاً يُعدّ عطلاً.
  final int minOnus;
  final String? msgOutage, msgBack;

  String get outageMessage => msgOutage ?? defaultOutageMessage;
  String get backMessage => msgBack ?? defaultBackMessage;

  FiberOltSettings copyWith({
    String? techName,
    String? techPhone,
    bool? notifyOutages,
    bool? notifyPower,
    int? minOnus,
    String? msgOutage,
    String? msgBack,
  }) =>
      FiberOltSettings(
        oltId: oltId,
        techName: techName ?? this.techName,
        techPhone: techPhone ?? this.techPhone,
        notifyOutages: notifyOutages ?? this.notifyOutages,
        notifyPower: notifyPower ?? this.notifyPower,
        minOnus: (minOnus ?? this.minOnus).clamp(minOnusFloor, minOnusCeil),
        msgOutage: msgOutage ?? this.msgOutage,
        msgBack: msgBack ?? this.msgBack,
      );

  static FiberOltSettings? fromJson(Object? j) {
    if (j is! Map) return null;
    final olt = _int(j['olt_id']);
    if (olt == null || olt <= 0) return null;
    return FiberOltSettings(
      oltId: olt,
      techName: _str(j['tech_name'], max: 80),
      techPhone: _str(j['tech_phone'], max: 32),
      notifyOutages: _bool(j['notify_outages'], dflt: true),
      notifyPower: _bool(j['notify_power'], dflt: false),
      minOnus: (_int(j['min_onus']) ?? 3).clamp(minOnusFloor, minOnusCeil),
      msgOutage: _str(j['msg_outage'], max: 500),
      msgBack: _str(j['msg_back'], max: 500),
    );
  }

  Map<String, dynamic> toJson() => {
        'olt_id': oltId,
        'tech_name': techName,
        'tech_phone': techPhone,
        'notify_outages': notifyOutages,
        'notify_power': notifyPower,
        'min_onus': minOnus,
        'msg_outage': msgOutage,
        'msg_back': msgBack,
      };

  @override
  bool operator ==(Object other) =>
      other is FiberOltSettings &&
      other.oltId == oltId &&
      other.techName == techName &&
      other.techPhone == techPhone &&
      other.notifyOutages == notifyOutages &&
      other.notifyPower == notifyPower &&
      other.minOnus == minOnus &&
      other.msgOutage == msgOutage &&
      other.msgBack == msgBack;

  @override
  int get hashCode => Object.hash(oltId, techName, techPhone, notifyOutages, notifyPower, minOnus, msgOutage, msgBack);
}

/// عطلٌ جماعيّ كما سجّله الخادم (من أوّل جهازٍ رآه) — فيراه كلّ هاتفٍ وحاسبةٍ للحساب.
@immutable
class FiberEventRecord {
  const FiberEventRecord({
    required this.id,
    required this.oltId,
    required this.kind,
    required this.scope,
    required this.scopeKey,
    required this.pon,
    required this.onuKeys,
    required this.startedAt,
    this.boxId,
    this.endedAt,
    this.autoBack = false,
    this.notifiedAt,
    this.backSentAt,
  });

  final int id;
  final int oltId;
  final FiberEventKind kind;
  final FiberEventScope scope;

  /// `box:12` · `pon:EPON0/3` · `group:EPON0/3`.
  final String scopeKey;
  final String pon;
  final int? boxId;
  final List<String> onuKeys;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// «لمّا يرجع النت أرسل لهم» — اختيار الوكيل لهذا العطل.
  final bool autoBack;
  final DateTime? notifiedAt, backSentAt;

  bool get open => endedAt == null;
  Duration durationAt(DateTime now) => (endedAt ?? now).difference(startedAt);

  FiberEventRecord copyWith({DateTime? endedAt, bool? autoBack, DateTime? notifiedAt, DateTime? backSentAt}) =>
      FiberEventRecord(
        id: id,
        oltId: oltId,
        kind: kind,
        scope: scope,
        scopeKey: scopeKey,
        pon: pon,
        boxId: boxId,
        onuKeys: onuKeys,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        autoBack: autoBack ?? this.autoBack,
        notifiedAt: notifiedAt ?? this.notifiedAt,
        backSentAt: backSentAt ?? this.backSentAt,
      );

  static FiberEventRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = _int(j['id']);
    final olt = _int(j['olt_id']);
    final started = fiberParseUtc(j['started_at']);
    final pon = _str(j['pon'], max: 24);
    if (id == null || id <= 0 || olt == null || started == null || pon == null) return null;
    final keys = j['onus'] is List
        ? [for (final k in j['onus'] as List) if (_str(k, max: 40) != null) _str(k, max: 40)!]
        : const <String>[];
    final box = _int(j['box_id']);
    return FiberEventRecord(
      id: id,
      oltId: olt,
      kind: _enumByName(FiberEventKind.values, j['kind']) ?? FiberEventKind.unknown,
      scope: _enumByName(FiberEventScope.values, j['scope']) ?? FiberEventScope.group,
      scopeKey: _str(j['scope_key'], max: 48) ?? 'group:$pon',
      pon: pon,
      boxId: box == null || box == 0 ? null : box,
      onuKeys: List.unmodifiable(keys),
      startedAt: started,
      endedAt: fiberParseUtc(j['ended_at']),
      autoBack: _bool(j['auto_back'], dflt: false),
      notifiedAt: fiberParseUtc(j['notified_at']),
      backSentAt: fiberParseUtc(j['back_sent_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'olt_id': oltId,
        'kind': kind.name,
        'scope': scope.name,
        'scope_key': scopeKey,
        'pon': pon,
        'box_id': boxId,
        'onus': onuKeys,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'auto_back': autoBack,
        'notified_at': notifiedAt?.toUtc().toIso8601String(),
        'back_sent_at': backSentAt?.toUtc().toIso8601String(),
      };
}

/// كلّ ما حُفظ لشبكة الألياف في الحساب.
@immutable
class FiberLayout {
  const FiberLayout({
    this.boxes = const {},
    this.onus = const {},
    this.settings = const {},
    this.events = const [],
  });

  static const empty = FiberLayout();

  final Map<int, FiberBox> boxes;

  /// بالمفتاح `oltId|key` — [recordKey].
  final Map<String, FiberOnuRecord> onus;
  final Map<int, FiberOltSettings> settings;
  final List<FiberEventRecord> events;

  static String recordKey(int oltId, String key) => '$oltId|$key';

  FiberOltSettings settingsOf(int oltId) => settings[oltId] ?? FiberOltSettings(oltId: oltId);

  List<FiberBox> boxesOf(int oltId, {String? pon}) => [
        for (final b in boxes.values)
          if (b.oltId == oltId && (pon == null || b.pon == pon)) b,
      ]..sort((a, b) => a.name.compareTo(b.name));

  /// سجلّ هذه الـONU: بهويّتها أوّلاً (جهازٌ أُعيد تسجيله برقمٍ آخر)، ثمّ باسمها ما لم تتعارض الهويّتان.
  FiberOnuRecord? recordFor(int oltId, String key, String? ident) {
    if (ident != null) {
      for (final r in onus.values) {
        if (r.oltId == oltId && r.ident == ident) return r;
      }
    }
    final byKey = onus[recordKey(oltId, key)];
    if (byKey == null) return null;
    if (ident != null && byKey.ident != null && byKey.ident != ident) return null;
    return byKey;
  }

  FiberLayout withBox(FiberBox b) => FiberLayout(
        boxes: Map.unmodifiable({...boxes, b.id: b}),
        onus: onus,
        settings: settings,
        events: events,
      );

  /// حذف صندوق: ما تحته من صناديق يرتفع لأبيه، وأجهزته تصير بلا صندوق.
  FiberLayout withoutBox(int id) {
    final gone = boxes[id];
    if (gone == null) return this;
    final next = <int, FiberBox>{};
    for (final b in boxes.values) {
      if (b.id == id) continue;
      next[b.id] = b.parentId == id
          ? (gone.parentId == null ? b.copyWith(clearParent: true) : b.copyWith(parentId: gone.parentId))
          : b;
    }
    return FiberLayout(
      boxes: Map.unmodifiable(next),
      onus: Map.unmodifiable({
        for (final e in onus.entries)
          if (e.value.boxId == id) e.key: e.value.copyWith(clearBox: true) else e.key: e.value,
      }),
      settings: settings,
      events: events,
    );
  }

  /// صندوقٌ رجع من الخادم برقمٍ حقيقيّ بدل رقمه المحلّيّ السالب: يُستبدل وكلّ ما يشير إليه.
  FiberLayout withBoxId(int localId, FiberBox saved) {
    if (localId == saved.id) return withBox(saved);
    return FiberLayout(
      boxes: Map.unmodifiable({
        for (final b in boxes.values)
          if (b.id != localId) b.id: (b.parentId == localId ? b.copyWith(parentId: saved.id) : b),
        saved.id: saved,
      }),
      onus: Map.unmodifiable({
        for (final e in onus.entries) e.key: (e.value.boxId == localId ? e.value.copyWith(boxId: saved.id) : e.value),
      }),
      settings: settings,
      events: events,
    );
  }

  /// يضع السجلّ تحت مفتاحه الحاليّ، ويحذف سجلّه القديم إن انتقلت الـONU لرقمٍ آخر (الهويّة نفسها).
  FiberLayout withRecord(FiberOnuRecord r) {
    final next = <String, FiberOnuRecord>{};
    for (final e in onus.entries) {
      final v = e.value;
      if (v.oltId == r.oltId && (v.key == r.key || (r.ident != null && v.ident == r.ident))) continue;
      next[e.key] = v;
    }
    if (!r.isEmpty) next[recordKey(r.oltId, r.key)] = r;
    return FiberLayout(boxes: boxes, onus: Map.unmodifiable(next), settings: settings, events: events);
  }

  FiberLayout withSettings(FiberOltSettings s) => FiberLayout(
        boxes: boxes,
        onus: onus,
        settings: Map.unmodifiable({...settings, s.oltId: s}),
        events: events,
      );

  FiberLayout withEvent(FiberEventRecord e) => FiberLayout(
        boxes: boxes,
        onus: onus,
        settings: settings,
        events: List.unmodifiable([
          for (final x in events)
            if (x.id != e.id) x,
          e,
        ]..sort((a, b) => b.startedAt.compareTo(a.startedAt))),
      );

  static FiberLayout fromJson(Object? body) {
    if (body is! Map) return empty;
    final boxes = <int, FiberBox>{};
    for (final b in (body['boxes'] is List ? body['boxes'] as List : const [])) {
      final v = FiberBox.fromJson(b);
      if (v != null) boxes[v.id] = v;
    }
    final onus = <String, FiberOnuRecord>{};
    for (final o in (body['onus'] is List ? body['onus'] as List : const [])) {
      final v = FiberOnuRecord.fromJson(o);
      if (v != null && !v.isEmpty) onus[recordKey(v.oltId, v.key)] = v;
    }
    final settings = <int, FiberOltSettings>{};
    for (final s in (body['settings'] is List ? body['settings'] as List : const [])) {
      final v = FiberOltSettings.fromJson(s);
      if (v != null) settings[v.oltId] = v;
    }
    final events = <FiberEventRecord>[
      for (final e in (body['events'] is List ? body['events'] as List : const []))
        if (FiberEventRecord.fromJson(e) case final v?) v,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return FiberLayout(
      boxes: Map.unmodifiable(boxes),
      onus: Map.unmodifiable(onus),
      settings: Map.unmodifiable(settings),
      events: List.unmodifiable(events),
    );
  }

  Map<String, dynamic> toJson() => {
        'boxes': [for (final b in boxes.values) b.toJson()],
        'onus': [for (final o in onus.values) o.toJson()],
        'settings': [for (final s in settings.values) s.toJson()],
        'events': [for (final e in events) e.toJson()],
      };
}
