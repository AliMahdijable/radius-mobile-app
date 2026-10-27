import '../../api/big_subscribers_api.dart';
import '../../api/subscribers_api.dart';
import '../../models/subscriber.dart';
import 'fiber_diagnosis.dart';

/// حسابات المشتركين لأجهزة الألياف: حالة الاشتراك والدين والهاتف. الحساب العاديّ من القائمة (مخبوءة ٤٥ث)، والكبير
/// (≥٥٠٠٠) بحثٌ لكلّ يوزر — لا قائمة كاملة أبداً.
class FiberSubs {
  FiberSubs._();

  /// يوزر (بحروفٍ صغيرة) ← مشترك. ما لم يُوجد لا يُعاد.
  static Future<Map<String, Subscriber>> byUsernames(Iterable<String> usernames, {int cap = 64}) async {
    final want = {for (final u in usernames) u.trim().toLowerCase()}..remove('');
    if (want.isEmpty) return const {};
    final out = <String, Subscriber>{};
    if (await BigSubscribersApi.probe() > 0) {
      final list = want.take(cap).toList();
      for (var i = 0; i < list.length; i += 4) {
        final got = await Future.wait([
          for (final u in list.skip(i).take(4)) BigSubscribersApi.findOne(username: u),
        ]);
        for (final s in got) {
          if (s != null) out[s.username.toLowerCase()] = s;
        }
      }
      return out;
    }
    final all = await SubscribersApi.loadAllWithOnline() ?? await SubscribersApi.loadAll() ?? const <Subscriber>[];
    for (final s in all) {
      final u = s.username.toLowerCase();
      if (want.contains(u)) out[u] = s;
    }
    return out;
  }

  /// دليل الحساب (يوزر بحروفٍ صغيرة ← مشترك) للربط بالاسم والبحث — العاديّ وحده؛ الكبير فارغ (لا قائمة كاملة).
  static Future<Map<String, Subscriber>> directory() async {
    if (await BigSubscribersApi.probe() > 0) return const {};
    final all = await SubscribersApi.loadAll() ?? const <Subscriber>[];
    return {for (final s in all) s.username.toLowerCase(): s};
  }

  /// جلسات الساس الحيّة: يوزر ← ماك (للربط بالماك). الكبير بلا قائمة متّصلين ⇒ فارغ.
  static Future<Map<String, String>> sessionMacs() async {
    final online = await SubscribersApi.loadOnline();
    if (online == null) return const {};
    return {
      for (final e in online.entries)
        if (e.value.mac != null && e.value.mac!.trim().isNotEmpty) e.key: e.value.mac!,
    };
  }

  static FiberSubscriberFacts facts(Subscriber s) => FiberSubscriberFacts(
        expired: s.isExpired,
        disabled: s.isDisabled,
        sessionOnline: s.isOnline,
        expiresAt: s.parsedExpiration,
        remainingDays: s.remainingDays,
        debt: s.hasDebt ? s.debtAbs : 0,
      );
}
