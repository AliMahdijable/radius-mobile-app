import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/fcm_service.dart';
import 'package:rad_mysvcs/services/notif_sound_engine.dart';
import 'package:rad_mysvcs/services/notif_sounds.dart';

/// «أصوات الإشعارات» (٢٥ نوفمبر): الكتالوج، الملفّات بأماكنها (res/raw + keep.xml لأندرويد، assets/sounds للآيفون ومُعلَن في pubspec)،
/// مطابقة فئات الخادم (server/notifSounds.js TYPE_CAT)، قنوات أندرويد، خريطة الخادم، التفضيلات، ومن يرنّ والتطبيق مفتوح.
void main() {
  SoundCategory cat(String id) => kSoundCategories.firstWhere((c) => c.id == id);

  test('الكتالوج: ١٢ فئة بمعرّفاتٍ ثابتة، و١٢ نغمة من البرنامج + الصوت + صوت الهاتف', () {
    expect(kSoundCategories.map((c) => c.id).toList(), [
      'renew', 'debt_pay', 'balance', 'ticket', 'store', 'field',
      'devices', 'sub_devices', 'money', 'employees', 'expiry', 'system',
    ]);
    expect(kTones.where((t) => t.kind == ToneKind.builtin).length, 12);
    expect(kTones.where((t) => t.kind == ToneKind.voice).length, 1);
    expect(kTones.where((t) => t.kind == ToneKind.phone).length, 1);
    expect(kTones.map((t) => t.id).toSet().length, kTones.length, reason: 'معرّفات النغمات فريدة');
    for (final c in kSoundCategories) {
      expect(kTones.any((t) => t.id == c.defaultTone), isTrue, reason: '${c.id} الافتراضيّ معروف');
      expect(c.phrase, isNotEmpty);
    }
    // الطلبات تنطق نوعها افتراضاً (قرار التصميم)
    for (final c in kSoundCategories.where((c) => c.family == SoundFamily.requests)) {
      expect(c.defaultTone, 'voice', reason: c.id);
    }
  });

  test('الملفّات: كلّ صوتٍ في res/raw (WAV) وفي assets/sounds (CAF)، وkeep.xml يحفظ raw، وassets/sounds/ مُعلَن', () {
    final files = allSoundFiles();
    expect(files.length, 24);
    for (final f in files) {
      expect(RegExp(r'^[a-z0-9_]+$').hasMatch(f), isTrue, reason: 'اسم مورد أندرويد صالح: $f');
      final raw = File('android/app/src/main/res/raw/$f.wav');
      final caf = File('assets/sounds/$f.caf');
      expect(raw.existsSync(), isTrue, reason: raw.path);
      expect(caf.existsSync(), isTrue, reason: caf.path);
      expect(raw.lengthSync(), greaterThan(4000), reason: raw.path);
      expect(caf.lengthSync(), greaterThan(1000), reason: caf.path);
      // الآيفون: أقصر من ٣٠ ث (وإلّا يرنّ صوت النظام) — WAV 22.05k/16bit ⇒ البايتات/44100 ثوانٍ
      expect((raw.lengthSync() - 44) / 44100, lessThan(30), reason: f);
    }
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    expect(keep, contains('tools:keep="@raw/*"'));
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s+- assets/sounds/\s*$', multiLine: true).hasMatch(pub), isTrue);
    // لا مجلّدات فرعيّة تحت assets/sounds (الإعلان لا يشملها)
    expect(Directory('assets/sounds').listSync().whereType<Directory>(), isEmpty);
  });

  test('الفئة من بيانات الإشعار = جدول الخادم (TYPE_CAT)، وتسديد الدين من kind، والتجريبيّ من cat', () {
    const server = {
      'renew_request': 'renew', 'balance_request': 'balance', 'balance_request_update': 'balance',
      'portal_ticket': 'ticket', 'watani_ticket': 'ticket', 'store_order': 'store', 'field_task': 'field',
      'agent_alert': 'devices', 'fiber_outage': 'devices', 'conn_alert_pending': 'sub_devices', 'conn_alert_sent': 'sub_devices',
      'agent_money': 'money', 'manager_debt': 'money', 'employee_ops': 'employees',
      'near_expiry_digest': 'expiry', 'expired_today_digest': 'expiry',
      'whatsapp_session_failed': 'system', 'sas_session_dead': 'system', 'system_alert': 'system',
      'owner_broadcast': 'system', 'admin_announcement': 'system',
    };
    expect(kTypeCategory, server);
    for (final e in server.entries) {
      expect(categoryOfData({'type': e.key})?.id, e.value, reason: e.key);
    }
    expect(categoryOfData({'type': 'renew_request', 'kind': 'debt'})?.id, 'debt_pay');
    expect(categoryOfData({'type': kSoundTestType, 'cat': 'store'})?.id, 'store');
    expect(categoryOfData({'type': kSoundTestType, 'cat': 'nope'}), isNull);
    expect(categoryOfData({'type': 'manager_balance_update'}), isNull);
  });

  test('قنوات أندرويد: نغمةٌ لكلّ معرّف، الصامت off، نغمة الجهاز ببصمتها، والطلبات بصوت المنبّه _loud', () {
    var p = NotifSoundPrefs.defaults;
    expect(NotifSoundEngine.channelIdOf(cat('renew'), p), 'ns_renew_voice');
    expect(NotifSoundEngine.channelIdOf(cat('devices'), p), 'ns_devices_alert');
    expect(NotifSoundEngine.channelIdOf(cat('expiry'), p), 'ns_expiry_phone');
    p = p.withOn('expiry', false);
    expect(NotifSoundEngine.channelIdOf(cat('expiry'), p), 'ns_expiry_off');
    p = p.withTone('balance', 'device', device: const DeviceTone(uri: 'content://media/internal/audio/media/7', name: 'Pixie'));
    final dev = NotifSoundEngine.channelIdOf(cat('balance'), p);
    expect(dev, matches(RegExp(r'^ns_balance_dev_[0-9a-f]{8}$')));
    expect(NotifSoundEngine.channelIdOf(cat('balance'), p), dev, reason: 'البصمة ثابتة');
    p = p.withLoud(true);
    expect(NotifSoundEngine.channelIdOf(cat('renew'), p), 'ns_renew_voice_loud');
    expect(NotifSoundEngine.channelIdOf(cat('devices'), p), 'ns_devices_alert', reason: 'المنبّه للطلبات وحدها');

    final ch = NotifSoundEngine.channelOf(cat('renew'), NotifSoundPrefs.defaults);
    expect(ch.name, 'طلبات التجديد');
    expect(ch.importance, Importance.high);
    expect((ch.sound as RawResourceAndroidNotificationSound).sound, 'v_renew');
    final off = NotifSoundEngine.channelOf(cat('expiry'), NotifSoundPrefs.defaults.withOn('expiry', false));
    expect(off.playSound, isFalse);
    expect(off.sound, isNull);
    final loud = NotifSoundEngine.channelOf(cat('ticket'), NotifSoundPrefs.defaults.withLoud(true));
    expect(loud.audioAttributesUsage, AudioAttributesUsage.alarm);
    final phone = NotifSoundEngine.channelOf(cat('system'), NotifSoundPrefs.defaults);
    expect(phone.sound, isNull, reason: 'صوت الهاتف = صوت القناة الافتراضيّ');
    expect(phone.playSound, isTrue);
  });

  test('خريطة الخادم: أندرويد {ch, snd} والآيفون {snd: ملفّ.caf | default}، والصامت mute', () {
    final p = NotifSoundPrefs.defaults.withOn('expiry', false).withTone('money', 'bell');
    final a = NotifSoundEngine.serverMap(p, ios: false);
    expect(a.keys.length, 12);
    expect(a['renew'], {'ch': 'ns_renew_voice', 'snd': 'v_renew'});
    expect(a['money'], {'ch': 'ns_money_bell', 'snd': 't_bell'});
    expect(a['system'], {'ch': 'ns_system_phone', 'snd': 'default'});
    expect(a['expiry'], {'mute': true, 'ch': 'ns_expiry_off'});
    final i = NotifSoundEngine.serverMap(p, ios: true);
    expect(i['renew'], {'snd': 'v_renew.caf'});
    expect(i['money'], {'snd': 't_bell.caf'});
    expect(i['system'], {'snd': 'default'});
    expect(i['expiry'], {'mute': true});
    // الشكل يطابق فحص الخادم (CH_RE / IOS_SND_RE / RAW_RE)
    for (final e in a.values) {
      if (e['ch'] != null) expect(RegExp(r'^[a-z0-9_]{1,60}$').hasMatch(e['ch'] as String), isTrue);
    }
    for (final e in i.values) {
      final s = e['snd'];
      if (s != null && s != 'default') expect(RegExp(r'^[a-z0-9_]{1,40}\.(caf|wav|aiff)$').hasMatch(s as String), isTrue);
    }
  });

  test('التفضيلات: JSON ذهاباً وإياباً، والقيم المجهولة تسقط، ونغمة جهازٍ بلا رابط ترجع للافتراضيّ', () {
    final p = NotifSoundPrefs.defaults
        .withTone('ticket', 'crystal')
        .withOn('employees', false)
        .withTone('store', 'device', device: const DeviceTone(uri: 'content://x/1', name: 'Ping'))
        .withLoud(true);
    final back = NotifSoundPrefs.fromJson(p.toJson());
    expect(back.toneOf(cat('ticket')), 'crystal');
    expect(back.isOn(cat('employees')), isFalse);
    expect(back.toneOf(cat('store')), 'device');
    expect(back.deviceTones['store']?.name, 'Ping');
    expect(back.loudRequests, isTrue);
    final junk = NotifSoundPrefs.fromJson({
      'tones': {'ticket': 'nope', 'hack': 'bell', 'money': 'harp', 'renew': 'device'},
      'muted': ['x', 'expiry', 5],
      'device': {'money': {'uri': ''}},
    });
    expect(junk.toneOf(cat('ticket')), 'voice');
    expect(junk.toneOf(cat('money')), 'harp');
    expect(junk.toneOf(cat('renew')), 'voice', reason: 'device بلا نغمة جهاز ⇒ الافتراضيّ');
    expect(junk.isOn(cat('expiry')), isFalse);
    expect(junk.deviceTones, isEmpty);
    expect(NotifSoundPrefs.fromJson('garbage').tones, isEmpty);
  });

  test('التطبيق مفتوح: التجريبيّ يرنّ دائماً، والطلبات والأجهزة والمال، لا الانتهاءات ولا المطفأ (إلّا العاجل القديم)', () {
    const d = NotifSoundPrefs.defaults;
    expect(FcmService.ringsInForeground({'type': kSoundTestType, 'cat': 'expiry'}, d), isTrue);
    expect(FcmService.ringsInForeground({'type': 'balance_request'}, d), isTrue, reason: 'كان صامتاً بالجرس');
    expect(FcmService.ringsInForeground({'type': 'agent_alert'}, d), isTrue);
    expect(FcmService.ringsInForeground({'type': 'agent_money'}, d), isTrue);
    expect(FcmService.ringsInForeground({'type': 'near_expiry_digest'}, d), isFalse);
    expect(FcmService.ringsInForeground({'type': 'unknown_type'}, d), isFalse);
    expect(FcmService.ringsInForeground({'type': 'renew_request'}, d), isTrue);
    final muted = d.withOn('balance', false).withOn('renew', false);
    expect(FcmService.ringsInForeground({'type': 'balance_request'}, muted), isFalse);
    expect(FcmService.ringsInForeground({'type': 'renew_request'}, muted), isTrue, reason: 'العاجل القديم يُعرض (بقناته الصامتة)');
  });

  test('سطر النغمة: الجملة المنطوقة لا تنقسم (مسافاتٌ غير قابلة للكسر)', () {
    final line = toneLine(cat('sub_devices'), NotifSoundPrefs.defaults.withTone('sub_devices', 'voice'));
    expect(line.contains(' '), isTrue, reason: 'بعد «ينطق:»');
    expect(line.substring(line.indexOf('«')).contains(' '), isFalse);
    expect(toneLine(cat('expiry'), NotifSoundPrefs.defaults.withOn('expiry', false)), contains('بلا صوت'));
  });
}
