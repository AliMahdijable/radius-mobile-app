import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import 'auth_storage.dart';
import 'notif_sounds.dart';

/// حالة الهاتف التي تمنع الصوت أو تسمح به — تُعرض أعلى «أصوات الإشعارات» لأنّ «الإشعار صامت» كثيراً ما يكون من إعدادات الهاتف.
@immutable
class PhoneSoundStatus {
  const PhoneSoundStatus({required this.notificationsOn, required this.soundOn, this.breaksThrough, this.fixChannel});

  /// إذن الإشعارات للتطبيق.
  final bool notificationsOn;

  /// صوت إشعارات الطلبات بإعدادات الهاتف (قناة أندرويد / إعداد الآيفون).
  final bool soundOn;

  /// أندرويد: «عدم الإزعاج» شغّال الآن والطلبات لا تعبره ⇒ false. null ⇒ لا يُعرض (مطفأ أو الآيفون).
  final bool? breaksThrough;

  /// القناة التي يفتحها «صلّح» (أندرويد) — null ⇒ إعدادات التطبيق.
  final String? fixChannel;
}

/// «أصوات الإشعارات» على الجهاز (٢٥ نوفمبر): قنوات أندرويد بنغماتها، ونسخ نغمات الآيفون إلى Library/Sounds، وإرسال خريطة الجهاز
/// للخادم (POST /api/fcm/register/sounds) فيختار لكلّ دفعٍ قناته/صوته، والمعاينة، ونغمة الجهاز، وحالة الهاتف، والإشعار التجريبيّ.
///
/// قنوات أندرويد: `ns_<فئة>_<نغمة>` (و`_loud` للطلبات بصوت المنبّه، و`ns_<فئة>_dev_<بصمة>` لنغمة الجهاز، و`ns_<فئة>_off` للصامت).
/// القناة لا تُغيَّر نغمتها بعد إنشائها (والمحذوفة تعود بإعداداتها إن أُعيدت بالمعرّف نفسه) ⇒ تغيير النغمة = قناةٌ بمعرّفٍ جديد،
/// وتُحذف قنوات الفئة الأخرى. قناةٌ لم تُنشأ بعد ⇒ FCM يرجع لقناة المانيفست mysvcs_fcm (لا شيء ينكسر).
class NotifSoundEngine {
  NotifSoundEngine._();
  static final NotifSoundEngine instance = NotifSoundEngine._();

  static const _native = MethodChannel('com.mysvcs.rad_mysvcs/notif_sounds');

  // منافذ الاختبار
  @visibleForTesting
  static bool Function() isAndroid = () => !kIsWeb && Platform.isAndroid;
  @visibleForTesting
  static bool Function() isIos = () => !kIsWeb && Platform.isIOS;
  @visibleForTesting
  static Future<String?> Function() fcmToken = () => FirebaseMessaging.instance.getToken();

  NotifSoundPrefs? _prefs;
  String? _lastPostKey;
  bool _iosInstalled = false;
  bool _synced = false;

  /// أندرويد: قنوات الفئات مزامَنة مرّةً بهذا التشغيل قبل أوّل إشعارٍ يُعرض والتطبيق مفتوح.
  Future<void> ensureSynced() async {
    if (_synced || !isAndroid()) return;
    await syncAndroidChannels(await prefs());
  }

  /// تفضيلات هذا الجهاز (تُقرأ مرّة).
  Future<NotifSoundPrefs> prefs() async => _prefs ??= await NotifSoundStore.load();

  /// للـFCM بالتطبيق المفتوح: الإعدادات الحاليّة إن قُرئت (وإلّا الافتراضيّ) — بلا انتظار.
  NotifSoundPrefs get current => _prefs ?? NotifSoundPrefs.defaults;

  @visibleForTesting
  void debugReset() {
    _prefs = null;
    _lastPostKey = null;
    _iosInstalled = false;
    _synced = false;
  }

  // ───────────────────────── القنوات والخريطة (نقيّة) ─────────────────────────

  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static bool _loud(SoundCategory c, NotifSoundPrefs p) => p.loudRequests && c.family == SoundFamily.requests;

  /// معرّف قناة أندرويد لفئةٍ بإعداداتها الحاليّة.
  static String channelIdOf(SoundCategory c, NotifSoundPrefs p) {
    if (!p.isOn(c)) return 'ns_${c.id}_off';
    final tone = p.toneOf(c);
    final loud = _loud(c, p) ? '_loud' : '';
    if (tone == 'device') {
      final d = p.deviceTones[c.id];
      return 'ns_${c.id}_dev_${_fnv(d?.uri ?? '')}$loud';
    }
    return 'ns_${c.id}_$tone$loud';
  }

  /// قناة أندرويد الكاملة لفئة (الاسم كما يظهر بإعدادات الهاتف = عنوان الفئة).
  static AndroidNotificationChannel channelOf(SoundCategory c, NotifSoundPrefs p) {
    final id = channelIdOf(c, p);
    final on = p.isOn(c);
    final tone = p.toneOf(c);
    AndroidNotificationSound? sound;
    if (on) {
      if (tone == 'device') {
        final d = p.deviceTones[c.id];
        if (d != null) sound = UriAndroidNotificationSound(d.uri);
      } else {
        final f = soundFileOf(c, tone);
        if (f != null) sound = RawResourceAndroidNotificationSound(f);
      }
    }
    return AndroidNotificationChannel(
      id,
      c.title,
      description: c.desc,
      importance: on ? Importance.high : Importance.low,
      playSound: on,
      sound: sound,
      enableVibration: on,
      audioAttributesUsage: _loud(c, p) ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
    );
  }

  /// خريطة الجهاز للخادم: أندرويد {ch, snd} والآيفون {snd: ملفّ.caf | default}، والصامت {mute} (وقناته لأندرويد).
  static Map<String, Map<String, Object>> serverMap(NotifSoundPrefs p, {required bool ios}) {
    final out = <String, Map<String, Object>>{};
    for (final c in kSoundCategories) {
      final tone = p.toneOf(c);
      final file = soundFileOf(c, tone);
      if (!p.isOn(c)) {
        out[c.id] = {'mute': true, if (!ios) 'ch': channelIdOf(c, p)};
      } else if (ios) {
        out[c.id] = {'snd': file == null ? 'default' : '$file.caf'};
      } else {
        out[c.id] = {'ch': channelIdOf(c, p), 'snd': file ?? 'default'};
      }
    }
    return out;
  }

  // ───────────────────────── المزامنة ─────────────────────────

  AndroidFlutterLocalNotificationsPlugin? get _android => FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// أندرويد: قناةٌ لكلّ فئة بنغمتها، وحذف قنوات الفئة القديمة. لا يرمي.
  Future<void> syncAndroidChannels(NotifSoundPrefs p) async {
    if (!isAndroid()) return;
    try {
      final plugin = _android;
      if (plugin == null) return;
      final existing = (await plugin.getNotificationChannels() ?? const <AndroidNotificationChannel>[]).map((c) => c.id).toSet();
      for (final c in kSoundCategories) {
        final want = channelIdOf(c, p);
        if (!existing.contains(want)) await plugin.createNotificationChannel(channelOf(c, p));
        for (final old in existing) {
          if (old != want && old.startsWith('ns_${c.id}_') && _belongs(old, c.id)) {
            await plugin.deleteNotificationChannel(old);
          }
        }
      }
      _synced = true;
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds channels: $e');
    }
  }

  /// `ns_sub_devices_*` يبدأ بـ`ns_sub_` لا `ns_devices_` — لكنّ `ns_devices_` لا يطابق `ns_sub_devices_`؛ والعكس: فئة `devices`
  /// لا تحذف قنوات `sub_devices`. يكفي التحقّق أنّ الباقي بعد البادئة نغمةٌ معروفة أو off/dev.
  static bool _belongs(String channelId, String catId) {
    final rest = channelId.substring('ns_${catId}_'.length);
    final head = rest.split('_').first;
    if (head == 'off' || head == 'dev') return true;
    return kTones.any((t) => t.id == head);
  }

  /// الآيفون: نغمات البرنامج إلى Library/Sounds (يبحث الآيفون هناك عن صوت الإشعار قبل الحزمة). مرّةً لكلّ تشغيل. لا يرمي.
  Future<void> installIosSounds() async {
    if (!isIos() || _iosInstalled) return;
    try {
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      for (final name in allSoundFiles()) {
        final data = await rootBundle.load('assets/sounds/$name.caf');
        final f = File('${dir.path}/$name.caf');
        if (f.existsSync() && f.lengthSync() == data.lengthInBytes) continue;
        await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      _iosInstalled = true;
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds ios install: $e');
    }
  }

  /// يرسل خريطة الجهاز للخادم إن تغيّرت (أو تغيّر التوكن/الصفحة). لا يرمي.
  Future<bool> postToServer({String? token, String? adminId, bool force = false}) async {
    if (!isAndroid() && !isIos()) return false;
    try {
      final tok = token ?? await fcmToken();
      final admin = adminId ?? await AuthStorage.readAdminId();
      if (tok == null || tok.isEmpty || admin == null || admin.isEmpty) return false;
      final p = await prefs();
      final map = serverMap(p, ios: isIos());
      final key = '$admin|$tok|${jsonEncode(map)}';
      if (!force && key == _lastPostKey) return true;
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/fcm/register/sounds',
        data: {'token': tok, 'adminId': admin, 'platform': isIos() ? 'ios' : 'android', 'sounds': map},
      );
      final ok = r.data?['success'] == true;
      if (ok) _lastPostKey = key;
      return ok;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('notif-sounds post: ${e.response?.statusCode} ${e.message}');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds post: $e');
      return false;
    }
  }

  /// بعد تسجيل توكن الإشعارات للصفحة (FcmService): القنوات/الملفّات ثمّ الخريطة للخادم.
  Future<void> onTokenRegistered(String token, String adminId) async {
    final p = await prefs();
    await syncAndroidChannels(p);
    await installIosSounds();
    await postToServer(token: token, adminId: adminId);
  }

  /// حين يغيّر المستخدم نغمةً أو مفتاحاً.
  Future<void> apply(NotifSoundPrefs p) async {
    _prefs = p;
    await NotifSoundStore.save(p);
    await syncAndroidChannels(p);
    await installIosSounds();
    await postToServer();
  }

  // ───────────────────────── واجهة الشاشة ─────────────────────────

  /// معاينة النغمة: أندرويد من res/raw (أو رابط نغمة الجهاز، أو صوت الهاتف)، والآيفون من Library/Sounds.
  Future<void> preview(String toneId, SoundCategory c) async {
    try {
      await installIosSounds();
      final p = await prefs();
      final file = soundFileOf(c, toneId);
      final device = toneId == 'device' ? p.deviceTones[c.id]?.uri : null;
      await _native.invokeMethod<Object?>('play', {
        'raw': file,
        'ios': file == null ? null : '$file.caf',
        'uri': device,
      });
      // المعاينة تشتغل ثانيتين تقريباً — الزرّ يبقى «يشتغل» خلالها
      await Future<void>.delayed(Duration(milliseconds: toneId == 'voice' ? 2600 : 1300));
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds preview: $e');
    }
  }

  /// أندرويد: منتقي نغمات الهاتف ⇒ (الرابط، الاسم) أو null.
  Future<DeviceTone?> pickFromDevice({String? current}) async {
    if (!isAndroid()) return null;
    try {
      final r = await _native.invokeMethod<Map<Object?, Object?>>('pickRingtone', {'current': current, 'title': 'نغمة من جهازك'});
      if (r == null) return null;
      final uri = r['uri']?.toString() ?? '';
      if (uri.isEmpty) return null;
      final title = r['title']?.toString() ?? '';
      return DeviceTone(uri: uri, name: title.isEmpty ? 'نغمة من جهازك' : title);
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds pick: $e');
      return null;
    }
  }

  /// حالة الهاتف: الإذن، وصوت قناة «طلبات الرصيد» (ممثّلةً للطلبات)، و«عدم الإزعاج» الشغّال الآن.
  Future<PhoneSoundStatus?> status() async {
    try {
      if (isAndroid()) {
        final p = await prefs();
        final balance = kSoundCategories.firstWhere((c) => c.id == 'balance');
        final ch = channelIdOf(balance, p);
        final r = await _native.invokeMethod<Map<Object?, Object?>>('status', {'channels': [ch]});
        if (r == null) return null;
        final enabled = r['enabled'] != false;
        final chans = (r['channels'] as Map?) ?? const {};
        final info = chans[ch] as Map?;
        final soundOn = !p.isOn(balance) || info == null || (info['sound'] == true && ((info['importance'] as int?) ?? 3) >= 3);
        final dndActive = r['dnd'] == true;
        final bypass = info != null && info['bypassDnd'] == true;
        return PhoneSoundStatus(
          notificationsOn: enabled,
          soundOn: soundOn,
          breaksThrough: dndActive ? bypass : null,
          fixChannel: ch,
        );
      }
      if (isIos()) {
        final r = await _native.invokeMethod<Map<Object?, Object?>>('status');
        if (r == null) return null;
        return PhoneSoundStatus(notificationsOn: r['enabled'] != false, soundOn: r['sound'] != false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('notif-sounds status: $e');
    }
    return null;
  }

  /// «صلّح»: إعدادات قناة الطلبات (أندرويد) أو إعدادات التطبيق.
  Future<void> openPhoneSettings({String? channel}) async {
    try {
      await _native.invokeMethod<Object?>('openSettings', {'channel': channel});
    } catch (_) {}
  }

  /// «إشعار تجريبي على هاتفي»: دفعٌ حقيقيّ من الخادم بعد [delaySeconds] — رسالةٌ للمستخدم أو null عند النجاح.
  Future<String?> sendTest(SoundCategory c, {int delaySeconds = 5}) async {
    try {
      final tok = await fcmToken();
      final admin = await AuthStorage.readAdminId();
      if (tok == null || tok.isEmpty || admin == null || admin.isEmpty) return 'الإشعارات غير مفعّلة على هذا الجهاز';
      await postToServer(token: tok, adminId: admin, force: true);
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/fcm/register/test-sound',
        data: {'token': tok, 'adminId': admin, 'category': c.id, 'delay_s': delaySeconds},
      );
      if (r.data?['success'] == true) return null;
      return (r.data?['message'] as String?) ?? 'تعذّر الإرسال — حاول مرّة ثانية';
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg = (e.response?.data is Map) ? (e.response!.data as Map)['message']?.toString() : null;
      if (code == 429) return msg ?? 'انتظر ثواني وجرّب مرّة ثانية';
      if (code == 409) return 'سجّل الجهاز للإشعارات أوّلاً — افتح التطبيق من جديد';
      return msg ?? 'تعذّر الإرسال — تأكّد من الإنترنت';
    } catch (_) {
      return 'تعذّر الإرسال — حاول مرّة ثانية';
    }
  }
}
