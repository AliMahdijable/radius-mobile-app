/// Admin-wide device credentials. Second-tier fallback between a
/// per-subscriber override and the hard-coded library defaults.
class AdminDeviceDefaults {
  final String? ontUsername;
  final String? ontPassword;
  final String? ubntUsername;
  final String? ubntPassword;

  const AdminDeviceDefaults({
    this.ontUsername,
    this.ontPassword,
    this.ubntUsername,
    this.ubntPassword,
  });

  factory AdminDeviceDefaults.empty() => const AdminDeviceDefaults();

  factory AdminDeviceDefaults.fromJson(Map<String, dynamic> j) => AdminDeviceDefaults(
        ontUsername: _nullIfBlank(j['ontUsername']),
        ontPassword: _nullIfBlank(j['ontPassword']),
        ubntUsername: _nullIfBlank(j['ubntUsername']),
        ubntPassword: _nullIfBlank(j['ubntPassword']),
      );

  Map<String, dynamic> toJson() => {
        'ontUsername': ontUsername,
        'ontPassword': ontPassword,
        'ubntUsername': ubntUsername,
        'ubntPassword': ubntPassword,
      };
}

String? _nullIfBlank(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}
