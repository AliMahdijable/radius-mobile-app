import 'package:firebase_auth/firebase_auth.dart' show User;

/// صاحب حساب Pro المسجَّل على هذا الجهاز — ما تحتاجه الشاشات منه فقط.
///
/// على الهاتف يُقرأ من Firebase Auth، وعلى ويندوز من [DesktopAccountAuth] (واجهة Firebase على
/// الإنترنت) — فلا تعرف الشاشات من أين جاء.
class AccountUser {
  const AccountUser({
    required this.uid,
    this.email,
    this.displayName,
    this.emailVerified = false,
    this.providerIds = const <String>[],
  });

  factory AccountUser.fromFirebase(User u) => AccountUser(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        emailVerified: u.emailVerified,
        providerIds: [for (final p in u.providerData) p.providerId],
      );

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        uid: '${j['uid']}',
        email: j['email'] as String?,
        displayName: j['displayName'] as String?,
        emailVerified: j['emailVerified'] == true,
        providerIds: [
          for (final p in (j['providerIds'] as List? ?? const [])) '$p',
        ],
      );

  final String uid;
  final String? email;
  final String? displayName;
  final bool emailVerified;

  /// `google.com` · `apple.com` · `password` …
  final List<String> providerIds;

  /// Google/Apple يؤكّدان البريد بأنفسهما.
  bool get isFederated =>
      providerIds.contains('google.com') || providerIds.contains('apple.com');

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'emailVerified': emailVerified,
        'providerIds': providerIds,
      };
}
