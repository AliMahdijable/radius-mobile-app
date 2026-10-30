/// تغيير باقة مشترك SAS4: «حالاً» أو «عند انتهاء الاشتراك» — قرار المالك ١٨ أكتوبر.
///
/// ما يرسله الخادم في `GET /api/v2/subscribers/:idx/activation-data` (يقرؤه شيت
/// التعديل أصلاً، فلا نداء إضافيّ):
///   `subscription_active` · `profile_change` · `can_change_profile` ·
///   `can_change_profile_active` · `immediate_keeps_date` (+ `profile_id` الباقة الآن)
/// وخادمٌ أقدم لا يرسلها ⇒ [PackageChangeInfo.supported] = false.
/// و`immediate_keeps_date` = true حين يعرف الخادم أنّ التاريخ سيبقى وحده؛ null = صلاحيّات
/// المدير لم تُقرأ بعد ⇒ «غير مضمون» (تنبيهٌ وتأكيد)، لا وعد.
library;

/// تغيير باقةٍ **مجدول** «عند انتهاء الاشتراك».
///
/// الساس يحفظه في `user.profileChange` بالشكل `{profile_id, due_date,
/// profile_name}` (لوحة SAS4 نفسها تعرضه «User profile is already scheduled
/// for change on <due_date> to: <profile_name>» وتلغيه بـ`cancelProfileChange`)،
/// والخادم يمرّره مطبَّعاً باسم `profile_change`. وغيابه = لا جدولة.
class ScheduledPackageChange {
  const ScheduledPackageChange({
    required this.profileName,
    required this.dueDate,
    this.profileId,
  });

  /// الباقة التي ستحلّ — قد تأتي بلا اسم فيُكمَّل من قائمة الباقات بـ[profileId].
  final int? profileId;
  final String profileName;

  /// موعد التغيير كما أرسله الساس (`YYYY-MM-DD HH:mm:ss` عادةً) — قد يكون فارغاً.
  final String dueDate;

  /// الموعد محلَّلاً — null إن لم يُفهم.
  DateTime? get dueAt {
    final t = dueDate.trim();
    if (t.isEmpty) return null;
    return DateTime.tryParse(t.replaceFirst(' ', 'T')) ??
        DateTime.tryParse(t.split(' ').first);
  }

  /// اليوم وحده للعرض («2026-11-16») — الساعة لا تضيف للوكيل شيئاً، وتطيل
  /// السطر على شاشة ٣٢٠. وإن لم يُفهم التاريخ يُعرض كما جاء.
  String get dueDay {
    final d = dueAt;
    if (d == null) return dueDate.trim();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// من ردّ الخادم. والساس الخام يرسل `false` (أو `[]` من PHP) حين لا جدولة،
  /// وقد يأتي `null` — وكلّها «لا شيء». ويلزم الحدّ الأدنى: باقةٌ معروفة (اسم أو رقم).
  static ScheduledPackageChange? tryParse(Object? raw) {
    if (raw is! Map) return null;
    String str(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.toLowerCase() == 'null' ? '' : s;
    }

    final rawId = raw['profile_id'] ?? raw['profileId'];
    final id = rawId is int ? rawId : int.tryParse(str(rawId));
    final name = str(raw['profile_name'] ?? raw['profileName'] ?? raw['name']);
    if ((id == null || id <= 0) && name.isEmpty) return null;
    return ScheduledPackageChange(
      profileId: (id != null && id > 0) ? id : null,
      profileName: name,
      dueDate: str(raw['due_date'] ?? raw['dueDate']),
    );
  }
}

/// حقول «تغيير الباقة» في activation-data.
class PackageChangeInfo {
  const PackageChangeInfo({
    this.supported = false,
    this.profileId,
    this.active,
    this.canChangeProfile,
    this.canChangeActive,
    this.immediateKeepsDate,
    this.scheduled,
    this.scheduleSupported,
  });

  /// الخادم يعرف `change_type`: يجدول، ويلغي المجدول قبل تغييرٍ جديد، ويُبقي تاريخ
  /// سوبرنت مع «حالاً». خادمٌ أقدم يتجاهله (فتصير الجدولة تغييراً فوريّاً).
  final bool supported;

  /// الباقة الآن كما في الساس (`profile_id`) — أحدث من صفّ القائمة (قد تكون غُيّرت من
  /// الويب أو سرى مجدول). null = لم تُرسَل.
  final int? profileId;

  /// فعّالٌ بمعيار الساس (`status.expiration`) — null = لا نعرف (يُقدَّر من التاريخ).
  final bool? active;

  /// صلاحيّة الساس `prm_users_change_profile` (تغيير باقة أيّ مشترك) — null = لا نعرف أو
  /// لا يرسلها الخادم في activation-data (مسار `/profile-change` يرسلها)، فيحكم الساس عند الحفظ.
  final bool? canChangeProfile;

  /// صلاحيّة الساس `prm_users_change_profile_active` (للموظّف: صلاحيّة مديره، فتوكنه
  /// توكن مديره عند الخادم) — null = لا نعرف، فيحكم الساس عند الحفظ.
  final bool? canChangeActive;

  /// «حالاً» يُبقي تاريخ الانتهاء: سوبرنت لمن يملك تعديله (الخادم يعيده بنفسه).
  final bool? immediateKeepsDate;

  /// تغييرٌ مجدول ينتظر — null = لا شيء.
  final ScheduledPackageChange? scheduled;

  /// «عند انتهاء الاشتراك» متاحٌ عند مزوّد الشركة؟ `false` صريحةً من الشركات المُضافة بلا جدولة (نبض، ٣٠ أكتوبر —
  /// `schedule_supported`): الباقة تتغيّر «حالاً» وحدها فلا يُسأل «متى؟». null = لا يقولها الخادم (SAS4 — يجدول كما كان).
  final bool? scheduleSupported;

  static bool? _flag(Object? v) {
    if (v is bool) return v;
    if (v == 1 || v == '1' || v == 'true') return true;
    if (v == 0 || v == '0' || v == 'false') return false;
    return null;
  }

  /// من `data` في ردّ activation-data. null (تعذّر الجلب) ⇒ لا شيء معروف.
  static PackageChangeInfo fromActivationData(Map<String, dynamic>? data) {
    if (data == null) return const PackageChangeInfo();
    final rawPid = data['profile_id'];
    final pid = rawPid is int ? rawPid : int.tryParse(rawPid?.toString() ?? '');
    return PackageChangeInfo(
      supported: data.containsKey('immediate_keeps_date') ||
          data.containsKey('subscription_active'),
      profileId: (pid != null && pid > 0) ? pid : null,
      active: _flag(data['subscription_active']),
      canChangeProfile: _flag(data['can_change_profile']),
      canChangeActive: _flag(data['can_change_profile_active']),
      immediateKeepsDate: _flag(data['immediate_keeps_date']),
      scheduled: ScheduledPackageChange.tryParse(
          data['profile_change'] ?? data['profileChange']),
      scheduleSupported: _flag(data['schedule_supported']),
    );
  }

  PackageChangeInfo withoutScheduled() => PackageChangeInfo(
        supported: supported,
        profileId: profileId,
        active: active,
        canChangeProfile: canChangeProfile,
        canChangeActive: canChangeActive,
        immediateKeepsDate: immediateKeepsDate,
        scheduleSupported: scheduleSupported,
      );
}
