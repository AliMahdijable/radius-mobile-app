/// Subscriber model — mirrors the fields v1 reads from
/// /api/subscribers/with-phones (backend) merged with SAS4 online data.
/// Only fields needed for the list+card view are required; the rest are
/// optional and filled in opportunistically.
class Subscriber {
  final String? idx;
  final String username;
  final String firstname;
  final String lastname;
  final String? phone;
  final String? mobile;
  final String? expiration;
  /// 2026-07-16: آخر اتصال — من SAS4 `last_online` field. backend يمرّرها
  /// في /api/v2/subscribers (server.js:9006). فارغة = SAS4 ما زوّدها.
  /// تُعرَض في subscriber_detail_screen للمشتركين غير المتّصلين.
  final String? lastOnline;
  final int? remainingDays;
  final String? notes;
  final bool hasDebtFlag;
  final double? debt;
  final String? profileName;
  final int? profileId;
  final String? parentUsername;
  /// SAS4-stored password — used to pre-fill the edit sheet so the
  /// admin can reveal/copy the current password before deciding to
  /// change it. null when the backend response didn't include it.
  final String? password;
  final bool isEnabled;
  final bool isOnlineFlag;
  final String? ipAddress;
  final int? sessionTime;
  final int? downloadBytes;
  final int? uploadBytes;
  /// Device vendor / OUI string from SAS4 (e.g., 'Huawei', 'Mikrotik')
  /// — comes through /api/v2/online-users as `device`. Shown on the
  /// online row of the subscriber card so admins can see what hardware
  /// is connected at a glance.
  final String? deviceVendor;
  final double? discount;
  /// Sale price (user_price) for this subscriber's package. Filled by
  /// `enrichWithPackages` from the catalogue map — the with-phones
  /// endpoint doesn't carry it. null = unknown / no price loaded.
  final num? price;

  /// SAS4 daily_traffic_details — استهلاك يومي إجمالي (traffic + upload +
  /// download) بالبايت. الـbackend يمرّرها كما هي في حقل `daily_traffic`.
  /// شكلها عادة: { traffic: N, upload: N, download: N } لكن قد تكون null
  /// لو المشترك بلا جلسات في اليوم الحالي. مطلب المستخدم 2026-07-13.
  final int? dailyTrafficTotal;
  final int? dailyUpload;
  final int? dailyDownload;

  /// 2026-08-26: موقع GPS للمشترك — يُخزَّن في SAS4 field `address`
  /// بصيغة "gps:LAT,LNG". backend parses ويعيدها هنا. null = لم يُعيَّن.
  final double? latitude;
  final double? longitude;

  /// النصّ الخام لحقل `address` من SAS4 (لأغراض التصادم — نمنع الكتابة
  /// فوق نصّ يدوي كتبه المدير قبل تفعيل الميزة). إذا يبدأ بـ"gps:" فهو
  /// موقع نظيف؛ خلاف ذلك = نصّ قديم يجب تنظيفه من SAS4 أوّلاً.
  final String? addressRaw;

  const Subscriber({
    this.idx,
    required this.username,
    required this.firstname,
    required this.lastname,
    this.phone,
    this.mobile,
    this.expiration,
    this.lastOnline,
    this.remainingDays,
    this.notes,
    this.hasDebtFlag = false,
    this.debt,
    this.profileName,
    this.profileId,
    this.parentUsername,
    this.password,
    this.isEnabled = true,
    this.isOnlineFlag = false,
    this.ipAddress,
    this.sessionTime,
    this.downloadBytes,
    this.uploadBytes,
    this.deviceVendor,
    this.discount,
    this.price,
    this.dailyTrafficTotal,
    this.dailyUpload,
    this.dailyDownload,
    this.latitude,
    this.longitude,
    this.addressRaw,
  });

  /// true فقط لو الـbackend أرجع إحداثيّات صالحة (parse من prefix gps:).
  bool get hasLocation => latitude != null && longitude != null;

  /// true = حقل address في SAS4 محتلّ بنصّ يدوي (بلا gps:) — يمنع
  /// تعيين موقع GPS جديد صامتاً. الـUI يعرض تحذيراً + رابط "احذف من SAS4".
  bool get hasManualAddressText {
    final raw = addressRaw?.trim() ?? '';
    if (raw.isEmpty) return false;
    return !raw.toLowerCase().startsWith('gps:');
  }

  String get fullName {
    final n = '$firstname $lastname'.trim();
    return n.isEmpty ? username : n;
  }

  String get displayPhone => (phone?.isNotEmpty ?? false) ? phone! : (mobile ?? '');

  /// Signed amount from notes (negative = debt, positive = credit).
  double get balanceAmount {
    final raw = notes?.trim() ?? '';
    if (raw.isEmpty) {
      // Fallback: backend's hasDebt + debt fields.
      if (hasDebtFlag && debt != null && debt! != 0) return -debt!.abs();
      return 0;
    }
    final cleaned = raw.replaceAll(',', '');
    final v = double.tryParse(cleaned) ?? 0;
    if (v.abs() < 1) return 0;
    return v;
  }

  bool get hasDebt => balanceAmount < 0;
  bool get hasCredit => balanceAmount > 0;
  double get debtAbs => balanceAmount.abs();

  /// Parsed expiration date — null when SAS4 sent an unparseable value.
  /// Mirrors v1's SubscriberModel._parsedExpiration so the date-based
  /// predicates below behave identically to v1.
  DateTime? get parsedExpiration {
    final raw = expiration;
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim()) ??
        DateTime.tryParse(raw.trim().split(' ').first);
  }

  /// Matches v1: prefer the parsed date (so we catch expirations that
  /// happen mid-day); fall back to remainingDays for rows missing a
  /// date string.
  bool get isExpired {
    final exp = parsedExpiration;
    if (exp != null) return exp.isBefore(DateTime.now());
    final d = remainingDays;
    return d != null && d < 0;
  }

  /// v1 rule: 'قارب الانتهاء' is 1..3 days remaining (NOT 0 — 0 means
  /// it expires today, which v1 treats as expired-or-about-to-expire).
  /// When we have a parsed date we measure actual hours instead, so a
  /// sub that expires in 2 days at 3pm is included.
  bool get isNearExpiry {
    final exp = parsedExpiration;
    if (exp != null) {
      if (exp.isBefore(DateTime.now())) return false;
      return exp.difference(DateTime.now()).inDays <= 3;
    }
    final d = remainingDays;
    return d != null && d >= 1 && d <= 3;
  }

  /// v1 says: active = not-expired. Disabled subscribers are NOT
  /// excluded from this count — they have a separate 'disabled' filter.
  bool get isActive => !isExpired;

  bool get isDisabled => !isEnabled;
  bool get isOnline => isOnlineFlag;

  /// v1: offline = (not online) AND (not expired). Disabled subscribers
  /// are counted as offline here (their own filter shows them separately).
  bool get isOffline => !isOnline && !isExpired;

  factory Subscriber.fromJson(Map<String, dynamic> j) {
    int? toInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', ''));
    }

    bool toBool(dynamic v, {bool dflt = false}) {
      if (v == null) return dflt;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }

    // SAS4 returns `profile_details: { id, name }` on each subscriber.
    // Read that first (matches v1 model), then fall back to the flat
    // fields the column-list query returns.
    final pd = j['profile_details'];
    final pdName = pd is Map ? pd['name'] : null;
    final pdId = pd is Map ? pd['id'] : null;

    // Match v1's SubscriberModel.fromJson exactly:
    // `(json['id'] ?? json['idx'])?.toString()`. The user's diagnostic
    // log of with-phones returned neither key — suggests SAS4 isn't
    // honoring our `idx` column request for some tree shapes. We log
    // the raw row at the API layer so we can see what IS there.
    final idRaw = j['id'] ?? j['idx'];
    return Subscriber(
      idx: idRaw?.toString(),
      // .trim() — دفاع أمامي: SAS4 قد يعطي username مع مسافة زائدة
      // (حادثة ame@rezz 2026-07-13). backend يُنقّي منها الآن كذلك،
      // هذا layer إضافي في حال أي مسار جديد يمرّر raw JSON.
      username: (j['username'] ?? '').toString().trim(),
      firstname: (j['firstname'] ?? '').toString(),
      lastname: (j['lastname'] ?? '').toString(),
      phone: j['phone']?.toString(),
      mobile: j['mobile']?.toString(),
      expiration: j['expiration']?.toString(),
      lastOnline: j['last_online']?.toString(),
      remainingDays: toInt(j['remaining_days'] ?? j['daysRemaining']),
      notes: j['notes']?.toString() ?? j['comments']?.toString(),
      hasDebtFlag: toBool(j['hasDebt']),
      debt: toDouble(j['debt']),
      profileName: pdName?.toString() ??
          j['profile_name']?.toString() ??
          j['profileName']?.toString() ??
          j['name']?.toString() ??
          j['package_name']?.toString(),
      profileId: toInt(pdId ?? j['profile_id'] ?? j['profileId']),
      parentUsername: j['parent_username']?.toString() ??
          j['parentUsername']?.toString(),
      password: j['password']?.toString(),
      isEnabled: toBool(j['enabled'] ?? j['isEnabled'], dflt: true),
      // Mirror v1's exact online-flag read (subscribers_provider.dart:455-458):
      //   isOnline = online_status==1 || is_online IN [true, 1, '1']
      // SAS4 surfaces both names on /index/user — accept either.
      isOnlineFlag: j['online_status'] == 1 ||
          j['online_status'] == '1' ||
          j['is_online'] == true ||
          j['is_online'] == 1 ||
          j['is_online'] == '1' ||
          j['isOnline'] == true,
      ipAddress: j['ip']?.toString() ??
          j['framedipaddress']?.toString() ??
          j['framed_ip_address']?.toString() ??
          j['ipAddress']?.toString(),
      sessionTime: toInt(j['session_time'] ?? j['sessionTime']),
      downloadBytes: toInt(j['download'] ?? j['downloadBytes']),
      uploadBytes: toInt(j['upload'] ?? j['uploadBytes']),
      discount: toDouble(j['discount']),
      // The with-phones endpoint already enriches each row with the
      // sale price (priceList.user_price). Read it directly; the
      // packages-map enrichment only kicks in if both are absent.
      price: toDouble(j['user_price']) ??
          toDouble(j['sale_price']) ??
          toDouble(j['price']),
      // 2026-07-13: daily_traffic_details يمرّه backend كـdaily_traffic.
      // شكل السجل: { traffic: N, upload: N, download: N } من SAS4.
      dailyTrafficTotal:
          toInt((j['daily_traffic'] is Map ? j['daily_traffic']['traffic'] : null)),
      dailyUpload:
          toInt((j['daily_traffic'] is Map ? j['daily_traffic']['upload'] : null)),
      dailyDownload:
          toInt((j['daily_traffic'] is Map ? j['daily_traffic']['download'] : null)),
      latitude: toDouble(j['latitude']),
      longitude: toDouble(j['longitude']),
      addressRaw: j['address_raw']?.toString(),
    );
  }

  /// Returns a copy with profileName + price filled in from the
  /// packages catalogue map. Mirrors v1's `_enrichWithPackage` —
  /// matches by profileId, leaves the row untouched when there's no
  /// match. We always re-apply the price even if profileName is set,
  /// because the price comes from priceList (sub-reseller info) which
  /// isn't part of the with-phones row.
  Subscriber enrichWithPackages(Map<String, PackageInfo> packagesById) {
    if (profileId == null) return this;
    final found = packagesById[profileId.toString()];
    if (found == null) return this;
    final newName =
        (profileName == null || profileName!.isEmpty) ? found.name : profileName;
    final newPrice = price ?? found.price;
    if (newName == profileName && newPrice == price) return this;
    return Subscriber(
      idx: idx,
      username: username,
      firstname: firstname,
      lastname: lastname,
      phone: phone,
      mobile: mobile,
      expiration: expiration,
      lastOnline: lastOnline,
      remainingDays: remainingDays,
      notes: notes,
      hasDebtFlag: hasDebtFlag,
      debt: debt,
      profileName: newName,
      profileId: profileId,
      parentUsername: parentUsername,
      password: password,
      isEnabled: isEnabled,
      isOnlineFlag: isOnlineFlag,
      ipAddress: ipAddress,
      sessionTime: sessionTime,
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      discount: discount,
      price: newPrice,
      dailyTrafficTotal: dailyTrafficTotal,
      dailyUpload: dailyUpload,
      dailyDownload: dailyDownload,
      latitude: latitude,
      longitude: longitude,
      addressRaw: addressRaw,
    );
  }

  Subscriber copyWithOnline({
    required bool online,
    String? ip,
    int? session,
    int? dl,
    int? ul,
    String? device,
  }) {
    return Subscriber(
      idx: idx,
      username: username,
      firstname: firstname,
      lastname: lastname,
      phone: phone,
      mobile: mobile,
      expiration: expiration,
      lastOnline: lastOnline,
      remainingDays: remainingDays,
      notes: notes,
      hasDebtFlag: hasDebtFlag,
      debt: debt,
      profileName: profileName,
      profileId: profileId,
      parentUsername: parentUsername,
      password: password,
      isEnabled: isEnabled,
      isOnlineFlag: online,
      ipAddress: ip ?? ipAddress,
      sessionTime: session ?? sessionTime,
      downloadBytes: dl ?? downloadBytes,
      uploadBytes: ul ?? uploadBytes,
      deviceVendor: device ?? deviceVendor,
      discount: discount,
      price: price,
      dailyTrafficTotal: dailyTrafficTotal,
      dailyUpload: dailyUpload,
      dailyDownload: dailyDownload,
      latitude: latitude,
      longitude: longitude,
      addressRaw: addressRaw,
    );
  }

  /// 2026-08-26: نُسخة مع موقع GPS مُحدَّث — بعد PATCH ناجح، نُطبّقها
  /// محلياً حتى الكارت + شاشة التفاصيل تتحدّث بدون انتظار refetch.
  Subscriber copyWithLocation({double? latitude, double? longitude, String? addressRaw}) {
    return Subscriber(
      idx: idx,
      username: username,
      firstname: firstname,
      lastname: lastname,
      phone: phone,
      mobile: mobile,
      expiration: expiration,
      lastOnline: lastOnline,
      remainingDays: remainingDays,
      notes: notes,
      hasDebtFlag: hasDebtFlag,
      debt: debt,
      profileName: profileName,
      profileId: profileId,
      parentUsername: parentUsername,
      password: password,
      isEnabled: isEnabled,
      isOnlineFlag: isOnlineFlag,
      ipAddress: ipAddress,
      sessionTime: sessionTime,
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      deviceVendor: deviceVendor,
      discount: discount,
      price: price,
      dailyTrafficTotal: dailyTrafficTotal,
      dailyUpload: dailyUpload,
      dailyDownload: dailyDownload,
      latitude: latitude,
      longitude: longitude,
      addressRaw: addressRaw ?? this.addressRaw,
    );
  }
}

/// Package catalogue entry from /api/v2/packages — name + sale price
/// for the subscriber. Used by `Subscriber.enrichWithPackages` to fill
/// in fields the with-phones row doesn't carry.
class PackageInfo {
  const PackageInfo({required this.name, this.price});
  final String name;
  final num? price;
}
