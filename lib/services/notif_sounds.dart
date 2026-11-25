import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «أصوات الإشعارات» (٢٥ نوفمبر — اقتراح وكيل عبر المالك: «نفس فكرة الواتساب… نغمة خاصة لكل تنبيه حتى نميز كل تنبيه من صوته»).
///
/// نغمةٌ لكلّ نوع إشعار، وصوت كلّ نوعٍ يشتغل ويطفأ، و«صوتٌ ينطق النوع» («طلب رصيد»…) يعرّف الوكيل بما وصله بلا نظرة.
/// الاختيار لكلّ جهاز كالواتساب (الموظّف يختار نغماته بجهازه): يُحفظ هنا، ثمّ يُرسل مع توكن الإشعارات ليختار الخادم
/// قناة أندرويد / نغمة الآيفون لكلّ دفعٍ إلى هذا الجهاز. ما لا يعرفه الجهاز (نسخةٌ قديمة) يبقى بصوته الحاليّ.

/// العائلة = لون مربّع الأيقونة وعنوان المجموعة.
enum SoundFamily { requests, devices, money, reminders }

/// فئة صوت: نوعٌ (أو أنواع) من إشعارات الخادم تشترك بنغمةٍ واحدة ومفتاح صوتٍ واحد.
@immutable
class SoundCategory {
  const SoundCategory({
    required this.id,
    required this.family,
    required this.title,
    required this.desc,
    required this.icon,
    required this.phrase,
    required this.types,
    required this.defaultTone,
  });

  /// مفتاحٌ ثابت يُحفظ ويُرسل للخادم — لا يتغيّر بعد النشر.
  final String id;
  final SoundFamily family;
  final String title;

  /// ما يشمله — يُعرض تحت العنوان حين لا نغمة بعد، وفي رأس نافذة النغمة.
  final String desc;
  final IconData icon;

  /// ما ينطقه «صوت ينطق النوع».
  final String phrase;

  /// أنواع `data.type` من الخادم (و`type:kind` حين يفرّق النوع بنوعه الفرعيّ).
  final List<String> types;
  final String defaultTone;
}

/// الفئات بترتيب العرض. الطلبات أوّلاً (شخصٌ ينتظر الوكيل)، ثمّ الأعطال، ثمّ المال والإدارة، ثمّ التذكيرات.
const kSoundCategories = <SoundCategory>[
  SoundCategory(
    id: 'renew',
    family: SoundFamily.requests,
    title: 'طلبات التجديد',
    desc: 'مشترك يطلب تجديد اشتراكه من التطبيق',
    icon: LucideIcons.refreshCw,
    phrase: 'طلب تجديد',
    types: ['renew_request'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'debt_pay',
    family: SoundFamily.requests,
    title: 'طلبات تسديد الدين',
    desc: 'مشترك يطلب يسدّد دينه',
    icon: LucideIcons.handCoins,
    phrase: 'تسديد دين',
    types: ['renew_request:debt'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'balance',
    family: SoundFamily.requests,
    title: 'طلبات الرصيد',
    desc: 'مدير فرعي يطلب رصيد، وويّاه وصل التحويل',
    icon: LucideIcons.wallet,
    phrase: 'طلب رصيد',
    types: ['balance_request'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'ticket',
    family: SoundFamily.requests,
    title: 'التذاكر',
    desc: 'تذكرة أو استفسار جديد من مشترك',
    icon: LucideIcons.ticket,
    phrase: 'تذكرة جديدة',
    types: ['portal_ticket', 'watani_ticket'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'store',
    family: SoundFamily.requests,
    title: 'طلبات المتجر',
    desc: 'مشترك يطلب مادّة من متجرك',
    icon: LucideIcons.shoppingBag,
    phrase: 'طلب من المتجر',
    types: ['store_order'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'field',
    family: SoundFamily.requests,
    title: 'مهامّ الفريق',
    desc: 'الفنّي أنجز مهمّة أو تعذّرت عليه',
    icon: LucideIcons.wrench,
    phrase: 'تحديث من الفريق',
    types: ['field_task'],
    defaultTone: 'voice',
  ),
  SoundCategory(
    id: 'devices',
    family: SoundFamily.devices,
    title: 'انطفاء أجهزتي ورجوعها',
    desc: 'الأبراج والسكترات واللينكات والأولتات، والحرارة والفولتيّة',
    icon: LucideIcons.router,
    phrase: 'تنبيه من أجهزتك',
    types: ['agent_alert', 'fiber_outage'],
    defaultTone: 'alert',
  ),
  SoundCategory(
    id: 'sub_devices',
    family: SoundFamily.devices,
    title: 'أجهزة المشتركين',
    desc: 'الكيبل والإشارة والـCCQ',
    icon: LucideIcons.signal,
    phrase: 'تنبيه أجهزة المشتركين',
    types: ['conn_alert_pending', 'conn_alert_sent'],
    defaultTone: 'soft',
  ),
  SoundCategory(
    id: 'money',
    family: SoundFamily.money,
    title: 'تنبيهات المال',
    desc: 'الرصيد، سقف الديون، المديونين، ديون المدراء',
    icon: LucideIcons.banknote,
    phrase: 'تنبيه مالي',
    types: ['agent_money', 'manager_debt'],
    defaultTone: 'rise',
  ),
  SoundCategory(
    id: 'employees',
    family: SoundFamily.money,
    title: 'عمليّات الموظّفين',
    desc: 'كلّ عمليّة يسوّيها موظّفينك',
    icon: LucideIcons.userCog,
    phrase: 'عمليّة موظّف',
    types: ['employee_ops'],
    defaultTone: 'tap',
  ),
  SoundCategory(
    id: 'expiry',
    family: SoundFamily.reminders,
    title: 'الانتهاءات',
    desc: 'قرب الانتهاء، وانتهى اليوم',
    icon: LucideIcons.calendarClock,
    phrase: 'تذكير الانتهاءات',
    types: ['near_expiry_digest', 'expired_today_digest'],
    defaultTone: 'phone',
  ),
  SoundCategory(
    id: 'system',
    family: SoundFamily.reminders,
    title: 'النظام',
    desc: 'انفصال الواتساب، جلسة الساس، والإعلانات',
    icon: LucideIcons.info,
    phrase: 'تنبيه النظام',
    types: ['whatsapp_session_failed', 'sas_session_dead', 'system_alert', 'owner_broadcast'],
    defaultTone: 'phone',
  ),
];

/// عنوان كلّ عائلة بالشاشة.
const kSoundFamilyTitles = <SoundFamily, String>{
  SoundFamily.requests: 'الطلبات',
  SoundFamily.devices: 'الأجهزة',
  SoundFamily.money: 'المال والإدارة',
  SoundFamily.reminders: 'التذكيرات والنظام',
};

enum ToneKind { voice, builtin, phone, device }

/// نغمة: «صوتٌ ينطق النوع» أو نغمةٌ من صنعنا أو صوت الهاتف أو نغمةٌ من الجهاز (أندرويد).
@immutable
class NotifTone {
  const NotifTone(this.id, this.name, this.kind, this.hint);
  final String id;
  final String name;
  final ToneKind kind;
  final String hint;
}

/// النغمات من صنعنا (لا منسوخة) — ملفّاتها `assets/sounds/<id>.*` وفي حزمة الآيفون `<id>.caf` وفي `res/raw` لأندرويد.
const kTones = <NotifTone>[
  NotifTone('voice', 'صوت ينطق النوع', ToneKind.voice, ''),
  NotifTone('bell', 'جرس', ToneKind.builtin, 'رنّة جرس واضحة'),
  NotifTone('chime', 'رنّة مزدوجة', ToneKind.builtin, 'نغمتين ورا بعض'),
  NotifTone('alert', 'إنذار', ToneKind.builtin, 'ثلاث نبضات سريعة، للأعطال'),
  NotifTone('urgent', 'عاجل', ToneKind.builtin, 'صافرة بنغمتين، أقوى من الإنذار'),
  NotifTone('rise', 'صاعدة', ToneKind.builtin, 'ثلاث نغمات صاعدة'),
  NotifTone('harp', 'قيثارة', ToneKind.builtin, 'أربع نغمات متتابعة'),
  NotifTone('marimba', 'ماريمبا', ToneKind.builtin, 'لحن خشبي قصير'),
  NotifTone('crystal', 'كريستال', ToneKind.builtin, 'نغمتين زجاجيّة عالية'),
  NotifTone('bubble', 'فقّاعة', ToneKind.builtin, 'صعود سريع مرّتين'),
  NotifTone('pulse', 'نبض', ToneKind.builtin, 'نبضتين ناعمة مثل دقّة القلب'),
  NotifTone('tap', 'نقرة', ToneKind.builtin, 'خفيفة وقصيرة'),
  NotifTone('soft', 'هادئة', ToneKind.builtin, 'نغمة ناعمة وحدة'),
  NotifTone('phone', 'صوت الهاتف', ToneKind.phone, 'نغمة الإشعارات العاديّة بهاتفك'),
];

/// نوع إشعار الخادم ⇒ الفئة (مرآة server/notifSounds.js TYPE_CAT). «طلب تسديد دين» = renew_request بـkind=debt،
/// والإشعار التجريبيّ sound_test بفئته في cat.
const kTypeCategory = <String, String>{
  'renew_request': 'renew',
  'balance_request': 'balance',
  'balance_request_update': 'balance',
  'portal_ticket': 'ticket',
  'watani_ticket': 'ticket',
  'store_order': 'store',
  'field_task': 'field',
  'agent_alert': 'devices',
  'fiber_outage': 'devices',
  'conn_alert_pending': 'sub_devices',
  'conn_alert_sent': 'sub_devices',
  'agent_money': 'money',
  'manager_debt': 'money',
  'employee_ops': 'employees',
  'near_expiry_digest': 'expiry',
  'expired_today_digest': 'expiry',
  'whatsapp_session_failed': 'system',
  'sas_session_dead': 'system',
  'system_alert': 'system',
  'owner_broadcast': 'system',
  'admin_announcement': 'system',
};

/// نوع الإشعار التجريبيّ («إشعار تجريبي على هاتفي») — لا يدخل الجرس ولا يفتح شيئاً.
const kSoundTestType = 'sound_test';

/// فئة إشعارٍ من بياناته (FCM data) — null لما لا فئة له.
SoundCategory? categoryOfData(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString();
  String? id;
  if (type == kSoundTestType) {
    id = (data['cat'] ?? '').toString();
  } else if (type == 'renew_request' && (data['kind'] ?? '').toString() == 'debt') {
    id = 'debt_pay';
  } else {
    id = kTypeCategory[type];
  }
  if (id == null || id.isEmpty) return null;
  for (final c in kSoundCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// اسم ملفّ النغمة بلا امتداد: `v_<فئة>` لـ«صوت ينطق النوع» و`t_<نغمة>` لنغمات البرنامج — res/raw بأندرويد، و`.caf` بالآيفون.
/// null ⇒ صوت الهاتف (أو نغمة الجهاز).
String? soundFileOf(SoundCategory c, String tone) {
  if (tone == 'voice') return 'v_${c.id}';
  for (final t in kTones) {
    if (t.id == tone && t.kind == ToneKind.builtin) return 't_$tone';
  }
  return null;
}

/// كلّ ملفّات الأصوات (لنسخها إلى Library/Sounds بالآيفون، وللفحص).
List<String> allSoundFiles() => [
      for (final c in kSoundCategories) 'v_${c.id}',
      for (final t in kTones)
        if (t.kind == ToneKind.builtin) 't_${t.id}',
    ];

NotifTone toneById(String id) =>
    kTones.firstWhere((t) => t.id == id, orElse: () => kTones.last);

/// نغمةٌ اختارها من هاتفه (أندرويد) — العنوان كما يعطيه النظام والاسم كما يعرضه.
@immutable
class DeviceTone {
  const DeviceTone({required this.uri, required this.name});
  final String uri;
  final String name;

  Map<String, Object?> toJson() => {'uri': uri, 'name': name};
  static DeviceTone? fromJson(Object? j) {
    if (j is! Map) return null;
    final uri = j['uri'];
    final name = j['name'];
    if (uri is! String || uri.isEmpty) return null;
    return DeviceTone(uri: uri, name: name is String && name.isNotEmpty ? name : 'نغمة من جهازك');
  }
}

/// منفذ الاختبار والمنصّة: الآيفون بلا «من جهازك» ولا «يرنّ والموبايل صامت».
class SoundPlatform {
  SoundPlatform._();
  static bool Function() isIos = () => !kIsWeb && Platform.isIOS;
}

/// تفضيلات هذا الجهاز.
@immutable
class NotifSoundPrefs {
  const NotifSoundPrefs({
    this.tones = const {},
    this.muted = const {},
    this.deviceTones = const {},
    this.loudRequests = false,
  });

  /// فئة ⇒ نغمة (`voice`، `bell`…، `phone`، `device`). ما ليس هنا = الافتراضيّ.
  final Map<String, String> tones;

  /// فئاتٌ صوتها مطفأ (الإشعار يصل بصمت).
  final Set<String> muted;
  final Map<String, DeviceTone> deviceTones;

  /// أندرويد: الطلبات ترنّ ولو الهاتف على الصامت (صوت المنبّه) — يشغّله الوكيل بنفسه.
  final bool loudRequests;

  static const defaults = NotifSoundPrefs();

  String toneOf(SoundCategory c) {
    final t = tones[c.id] ?? c.defaultTone;
    if (t == 'device' && deviceTones[c.id] == null) return c.defaultTone;
    return t;
  }

  bool isOn(SoundCategory c) => !muted.contains(c.id);

  NotifSoundPrefs withTone(String catId, String tone, {DeviceTone? device}) {
    final t = Map<String, String>.from(tones)..[catId] = tone;
    final d = Map<String, DeviceTone>.from(deviceTones);
    if (device != null) d[catId] = device;
    return NotifSoundPrefs(tones: t, muted: muted, deviceTones: d, loudRequests: loudRequests);
  }

  NotifSoundPrefs withOn(String catId, bool on) {
    final m = Set<String>.from(muted);
    on ? m.remove(catId) : m.add(catId);
    return NotifSoundPrefs(tones: tones, muted: m, deviceTones: deviceTones, loudRequests: loudRequests);
  }

  NotifSoundPrefs withLoud(bool v) =>
      NotifSoundPrefs(tones: tones, muted: muted, deviceTones: deviceTones, loudRequests: v);

  Map<String, Object?> toJson() => {
        'v': 1,
        'tones': tones,
        'muted': muted.toList()..sort(),
        'device': {for (final e in deviceTones.entries) e.key: e.value.toJson()},
        'loud': loudRequests,
      };

  static NotifSoundPrefs fromJson(Object? j) {
    if (j is! Map) return defaults;
    final ids = {for (final c in kSoundCategories) c.id};
    final toneIds = {for (final t in kTones) t.id, 'device'};
    final tones = <String, String>{};
    final rawT = j['tones'];
    if (rawT is Map) {
      for (final e in rawT.entries) {
        if (ids.contains(e.key) && e.value is String && toneIds.contains(e.value)) {
          tones[e.key as String] = e.value as String;
        }
      }
    }
    final muted = <String>{};
    final rawM = j['muted'];
    if (rawM is List) {
      for (final v in rawM) {
        if (v is String && ids.contains(v)) muted.add(v);
      }
    }
    final device = <String, DeviceTone>{};
    final rawD = j['device'];
    if (rawD is Map) {
      for (final e in rawD.entries) {
        final d = DeviceTone.fromJson(e.value);
        if (d != null && ids.contains(e.key)) device[e.key as String] = d;
      }
    }
    return NotifSoundPrefs(tones: tones, muted: muted, deviceTones: device, loudRequests: j['loud'] == true);
  }
}

/// حفظ التفضيلات على الجهاز.
class NotifSoundStore {
  NotifSoundStore._();
  static const _key = 'notif_sounds.v1';

  static Future<NotifSoundPrefs> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return NotifSoundPrefs.defaults;
      return NotifSoundPrefs.fromJson(jsonDecode(raw));
    } catch (_) {
      return NotifSoundPrefs.defaults;
    }
  }

  static Future<void> save(NotifSoundPrefs p) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(p.toJson()));
    } catch (_) {
      /* الحفظ المحلّيّ لا يُفشل الشاشة */
    }
  }
}

/// الجملة المنطوقة لا تنقسم على سطرين بالعرض الضيّق — مسافاتها غير قابلة للكسر، فينزل السطر كلّه قبلها.
String keepTogether(String s) => s.replaceAll(' ', String.fromCharCode(0xA0));

/// وصف النغمة الحاليّة بسطر الصفّ.
String toneLine(SoundCategory c, NotifSoundPrefs p) {
  if (!p.isOn(c)) return 'بلا صوت — يوصل الإشعار بصمت';
  final t = p.toneOf(c);
  if (t == 'voice') return 'ينطق: «${keepTogether(c.phrase)}»';
  if (t == 'device') return p.deviceTones[c.id]?.name ?? 'نغمة من جهازك';
  return toneById(t).name;
}
