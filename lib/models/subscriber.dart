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
  final int? remainingDays;
  final String? notes;
  final bool hasDebtFlag;
  final double? debt;
  final String? profileName;
  final int? profileId;
  final String? parentUsername;
  final bool isEnabled;
  final bool isOnlineFlag;
  final String? ipAddress;
  final int? sessionTime;
  final int? downloadBytes;
  final int? uploadBytes;
  final double? discount;
  /// Sale price (user_price) for this subscriber's package. Filled by
  /// `enrichWithPackages` from the catalogue map — the with-phones
  /// endpoint doesn't carry it. null = unknown / no price loaded.
  final num? price;

  const Subscriber({
    this.idx,
    required this.username,
    required this.firstname,
    required this.lastname,
    this.phone,
    this.mobile,
    this.expiration,
    this.remainingDays,
    this.notes,
    this.hasDebtFlag = false,
    this.debt,
    this.profileName,
    this.profileId,
    this.parentUsername,
    this.isEnabled = true,
    this.isOnlineFlag = false,
    this.ipAddress,
    this.sessionTime,
    this.downloadBytes,
    this.uploadBytes,
    this.discount,
    this.price,
  });

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

    return Subscriber(
      idx: j['id']?.toString() ?? j['idx']?.toString(),
      username: (j['username'] ?? '').toString(),
      firstname: (j['firstname'] ?? '').toString(),
      lastname: (j['lastname'] ?? '').toString(),
      phone: j['phone']?.toString(),
      mobile: j['mobile']?.toString(),
      expiration: j['expiration']?.toString(),
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
      isEnabled: toBool(j['enabled'] ?? j['isEnabled'], dflt: true),
      isOnlineFlag: toBool(j['isOnline'] ?? j['is_online']),
      ipAddress: j['ip']?.toString() ?? j['ipAddress']?.toString(),
      sessionTime: toInt(j['session_time'] ?? j['sessionTime']),
      downloadBytes: toInt(j['download'] ?? j['downloadBytes']),
      uploadBytes: toInt(j['upload'] ?? j['uploadBytes']),
      discount: toDouble(j['discount']),
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
      remainingDays: remainingDays,
      notes: notes,
      hasDebtFlag: hasDebtFlag,
      debt: debt,
      profileName: newName,
      profileId: profileId,
      parentUsername: parentUsername,
      isEnabled: isEnabled,
      isOnlineFlag: isOnlineFlag,
      ipAddress: ipAddress,
      sessionTime: sessionTime,
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      discount: discount,
      price: newPrice,
    );
  }

  Subscriber copyWithOnline({
    required bool online,
    String? ip,
    int? session,
    int? dl,
    int? ul,
  }) {
    return Subscriber(
      idx: idx,
      username: username,
      firstname: firstname,
      lastname: lastname,
      phone: phone,
      mobile: mobile,
      expiration: expiration,
      remainingDays: remainingDays,
      notes: notes,
      hasDebtFlag: hasDebtFlag,
      debt: debt,
      profileName: profileName,
      profileId: profileId,
      parentUsername: parentUsername,
      isEnabled: isEnabled,
      isOnlineFlag: online,
      ipAddress: ip ?? ipAddress,
      sessionTime: session ?? sessionTime,
      downloadBytes: dl ?? downloadBytes,
      uploadBytes: ul ?? uploadBytes,
      discount: discount,
      price: price,
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
