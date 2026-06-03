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

  bool get isExpired {
    final d = remainingDays;
    return d != null && d < 0;
  }

  bool get isNearExpiry {
    final d = remainingDays;
    return d != null && d >= 0 && d <= 3;
  }

  bool get isActive => isEnabled && !isExpired;

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
    );
  }
}
