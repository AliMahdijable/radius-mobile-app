/// يوزر ساسٍ بشكل الإيميل (`admin@najaf202`) مكتوبٌ في خانة إيميل الحساب.
///
/// 🐛 بلاغ ٢٠٢٦-١٠-١٥ (فيديو «errro-creat»): يوزرات سوبرنت تحمل «@» فيظنّها مدير الكلاسيك إيميله،
/// فيكتبها في دخول الحساب ويأتيه «البريد أو كلمة السرّ غير صحيحة» بلا سببٍ يفهمه — ولا يُنشأ حسابٌ بها
/// (لا حساب واحد في القاعدة بإيميلٍ نطاقه بلا نقطة). الإيميل الحقيقيّ نطاقه فيه نقطة (gmail.com)؛
/// يوزر الساس غالباً لا.
bool looksLikeSasUsername(String input) {
  final s = input.trim();
  final at = s.indexOf('@');
  if (at <= 0 || at != s.lastIndexOf('@')) return false;
  final domain = s.substring(at + 1);
  return domain.isNotEmpty && !domain.contains('.') && !domain.contains(' ');
}
