/// Tiny formatting helpers. No locale dance — IQD only, en_US digits for
/// readability (per user feedback: ٥٤٠٬٠٠٠ harder than 540,000).

final _grouper = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

/// 540000 → "540,000". Negative-safe (strips the sign — callers add it).
String formatIQD(num value) {
  final s = value.abs().round().toString();
  return s.replaceAllMapped(_grouper, (m) => '${m[1]},');
}

/// 0.12 → "+12%", -0.05 → "-5%", 0 → "0%".
String formatDeltaPct(double ratio) {
  final pct = (ratio * 100).round();
  if (pct == 0) return '0%';
  return '${pct > 0 ? '+' : ''}$pct%';
}

/// 3 → "قبل 3د", 67 → "قبل 1س", 1500 → "قبل يوم".
String humanMinutesAgo(int minutes) {
  if (minutes < 1) return 'الآن';
  if (minutes < 60) return 'قبل $minutes د';
  final hours = minutes ~/ 60;
  if (hours < 24) return 'قبل $hours س';
  final days = hours ~/ 24;
  if (days == 1) return 'قبل يوم';
  return 'قبل $days أيام';
}
