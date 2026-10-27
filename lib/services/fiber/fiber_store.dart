import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/fiber_api.dart';
import '../../models/fiber_network.dart';
import '../auth_storage.dart';
import 'fiber_light.dart';
import 'fiber_linker.dart';
import 'fiber_onu.dart';

/// ذاكرة شبكة الألياف للحساب الحاليّ: التخطيط (صناديق، ربط، إعدادات، أعطال) ودفاتر الضوء — من الخادم، ونسخةٌ على
/// الجهاز تُفتح بها الشاشة فوراً وتبقى إن لم يصل الخادم.
///
/// الكتابة: تُطبَّق فوراً على الشاشة ثمّ تُرسل. خادمٌ بلا المسارات بعد (404) ⇒ [serverReady] = false والتعديل يبقى على
/// هذا الجهاز وحده («الحفظ على هذا الجهاز فقط» — كعرض البرج قبل نشره). تُمسح مع الخروج ([clear]).
class FiberStore {
  FiberStore._();

  static final ValueNotifier<FiberLayout> layout = ValueNotifier(FiberLayout.empty);

  /// ما يدعمه كلّ أولت (من أيّ جهازٍ فحصه) — للعرض «هذا الأولت لا يعطي…».
  static final ValueNotifier<Map<int, Map<String, dynamic>>> caps = ValueNotifier(const {});

  static bool serverReady = true;
  static bool loaded = false;
  static String? lastError;
  static String? _admin;
  static Future<void>? _loading;
  static int _localId = -1;

  /// تعديلاتٌ حُفظت على الجهاز وحده (الخادم بلا المسارات بعد) — تُرفع أوّل ما يجيب ([_pushLocal]).
  static bool _pending = false;

  static final Map<int, RxDailyBook> _books = {};
  static final Map<int, DateTime> _rxLoadedAt = {};

  static String _key(String admin) => 'fiber.layout.v1.$admin';
  // v2 (٢٧ أكتوبر): قراءات VSOL V1600D قبل إصلاح «0.0070 mW(-21.55dBm)» كانت ‎0.01 — دفاترها تُترك.
  static String _rxKey(String admin, int olt) => 'fiber.rx.v2.$admin.$olt';
  static String _pendingKey(String admin) => 'fiber.pending.v1.$admin';
  static String _snapKey(String admin, int olt) => 'fiber.snap.v1.$admin.$olt';

  /// يحمّل مرّةً لكلّ جلسة (أو [force]). أوّل الطريق النسخة المحفوظة على الجهاز، ثمّ الخادم.
  static Future<void> ensureLoaded({bool force = false}) {
    if (loaded && !force) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    final admin = await AuthStorage.readAdminId() ?? '';
    if (_admin != admin) {
      _admin = admin;
      layout.value = FiberLayout.empty;
      _books.clear();
      _rxLoadedAt.clear();
    }
    if (layout.value == FiberLayout.empty) {
      final local = await _restore(admin);
      if (local != null) layout.value = local;
    }
    try {
      final p = await SharedPreferences.getInstance();
      _pending = p.getBool(_pendingKey(admin)) ?? false;
    } catch (_) {}
    final local = layout.value;
    final r = await FiberApi.load();
    if (r.ok) {
      serverReady = true;
      lastError = null;
      layout.value = r.layout;
      caps.value = Map.unmodifiable(r.caps);
      // ما حُفظ على الجهاز وحده يُرفع الآن — ولا يُمحى بردّ الخادم.
      if (_pending) await _pushLocal(local);
      await _persist();
    } else {
      serverReady = !r.notDeployed;
      lastError = r.notDeployed ? null : r.message;
    }
    loaded = true;
  }

  // ── التخطيط ─────────────────────────────────────────────────────────────────────────

  static Future<({bool ok, FiberBox? box, String? message})> saveBox(FiberBox b) async {
    final before = layout.value;
    final local = b.id == 0 ? b.copyWith(id: _localId--) : b;
    layout.value = before.withBox(local);
    if (!serverReady) {
      await _markLocal();
      return (ok: true, box: local, message: null);
    }
    final r = await FiberApi.saveBox(local);
    if (r.ok && r.box != null) {
      layout.value = layout.value.withBoxId(local.id, r.box!);
      await _persist();
      return (ok: true, box: r.box, message: null);
    }
    if (r.notDeployed) {
      serverReady = false;
      await _markLocal();
      return (ok: true, box: local, message: null);
    }
    // رفضٌ أو لا اتّصال ⇒ لا صندوق نصف محفوظ يظهر على الشاشة (ولا نسخةٌ ثانية عند الإعادة).
    layout.value = before;
    return (ok: false, box: null, message: r.message);
  }

  static Future<({bool ok, String? message})> deleteBox(int id) async {
    final before = layout.value;
    layout.value = before.withoutBox(id);
    if (!serverReady || id < 0) {
      await _markLocal();
      return (ok: true, message: null);
    }
    final r = await FiberApi.deleteBox(id);
    if (r.ok) {
      await _persist();
      return (ok: true, message: null);
    }
    if (r.notDeployed) {
      serverReady = false;
      await _markLocal();
      return (ok: true, message: null);
    }
    layout.value = before;
    return (ok: false, message: r.message);
  }

  /// يُسند الأجهزة لصندوق (أو `null` = بلا صندوق) — بهويّتها.
  static Future<({bool ok, String? message})> assign(int oltId, Iterable<FiberOnuLive> onus, int? boxId) async {
    final items = <({FiberOnuRecord record, String? oldKey})>[];
    var l = layout.value;
    for (final o in onus) {
      final cur = l.recordFor(oltId, o.key, o.ident);
      final rec = (cur ?? FiberOnuRecord(oltId: oltId, key: o.key, ident: o.ident))
          .copyWith(key: o.key, ident: o.ident, boxId: boxId, clearBox: boxId == null);
      l = l.withRecord(rec);
      items.add((record: rec, oldKey: cur?.key));
    }
    return _writeRecords(oltId, l, items);
  }

  /// يربط جهازاً بمشترك (أو `null` = فكّ الربط). اليوزر لجهازٍ واحد بالأولت: إن كان مربوطاً بغيره يُفكّ هناك بنفس الحفظ.
  static Future<({bool ok, String? message})> link(
    int oltId,
    FiberOnuLive onu,
    String? username, {
    FiberLinkSource source = FiberLinkSource.manual,
  }) async {
    var l = layout.value;
    final items = <({FiberOnuRecord record, String? oldKey})>[];
    final cur = l.recordFor(oltId, onu.key, onu.ident);
    if (username != null) {
      final u = username.toLowerCase();
      for (final r in l.onus.values.toList()) {
        if (r.oltId != oltId || r.key == onu.key || r.username?.toLowerCase() != u) continue;
        if (onu.ident != null && r.ident == onu.ident) continue;
        final freed = r.copyWith(clearLink: true);
        l = l.withRecord(freed);
        items.add((record: freed, oldKey: r.key));
      }
    }
    final base = cur ?? FiberOnuRecord(oltId: oltId, key: onu.key, ident: onu.ident);
    final rec = username == null
        ? base.copyWith(key: onu.key, ident: onu.ident, clearLink: true)
        : base.copyWith(key: onu.key, ident: onu.ident, username: username, source: source, linkedAt: DateTime.now().toUtc());
    items.add((record: rec, oldKey: cur?.key));
    return _writeRecords(oltId, l.withRecord(rec), items);
  }

  /// الجهاز المربوط الآن بهذا اليوزر على الأولت (غير [exceptKey]).
  static FiberOnuRecord? linkedTo(int oltId, String username, {String? exceptKey}) {
    final u = username.toLowerCase();
    for (final r in layout.value.onus.values) {
      if (r.oltId == oltId && r.key != exceptKey && r.username?.toLowerCase() == u) return r;
    }
    return null;
  }

  /// تثبيت عدّة اقتراحات معاً («ثبّت الأكيدة»).
  static Future<({bool ok, String? message})> linkMany(int oltId, Iterable<FiberLinkSuggestion> list) async {
    final items = <({FiberOnuRecord record, String? oldKey})>[];
    var l = layout.value;
    final at = DateTime.now().toUtc();
    for (final s in list) {
      final cur = l.recordFor(oltId, s.key, s.ident);
      final rec = (cur ?? FiberOnuRecord(oltId: oltId, key: s.key, ident: s.ident))
          .copyWith(key: s.key, ident: s.ident, username: s.username, source: s.source, linkedAt: at);
      l = l.withRecord(rec);
      items.add((record: rec, oldKey: cur?.key));
    }
    return _writeRecords(oltId, l, items);
  }

  static Future<({bool ok, String? message})> _writeRecords(
    int oltId,
    FiberLayout next,
    List<({FiberOnuRecord record, String? oldKey})> items,
  ) async {
    final before = layout.value;
    layout.value = next;
    if (!serverReady || items.isEmpty) {
      if (items.isNotEmpty) await _markLocal();
      return (ok: true, message: null);
    }
    // سجلّاتٌ تشير لصندوقٍ لم يصل الخادم بعد (رقمٌ سالب) تُرفع معه ([_pushLocal]).
    final ready = [
      for (final i in items)
        if ((i.record.boxId ?? 0) >= 0) i,
    ];
    if (ready.length < items.length) await _markLocal();
    for (var s = 0; s < ready.length; s += 300) {
      final r = await FiberApi.saveRecords(oltId, ready.skip(s).take(300).toList());
      if (r.notDeployed) {
        serverReady = false;
        await _markLocal();
        return (ok: true, message: null);
      }
      if (!r.ok) {
        // ما لم يصل الخادم لا يبقى على الشاشة كأنّه حُفظ (الدفعات السابقة وصلت؛ نعيد تحميلها مع الدخول القادم).
        if (s == 0) layout.value = before;
        return (ok: false, message: r.message);
      }
    }
    await _persist();
    return (ok: true, message: null);
  }

  static Future<({bool ok, String? message})> saveSettings(FiberOltSettings s) async {
    final before = layout.value;
    layout.value = before.withSettings(s);
    if (!serverReady) {
      await _markLocal();
      return (ok: true, message: null);
    }
    final r = await FiberApi.saveSettings(s);
    if (r.notDeployed) {
      serverReady = false;
      await _markLocal();
      return (ok: true, message: null);
    }
    if (!r.ok) {
      layout.value = before;
      return (ok: false, message: r.message);
    }
    await _persist();
    return (ok: true, message: null);
  }

  /// يحفظ على الجهاز ويعلّم «بانتظار الخادم».
  static Future<void> _markLocal() async {
    _pending = true;
    await _persist();
    final admin = _admin;
    if (admin == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_pendingKey(admin), true);
    } catch (_) {}
  }

  /// يرفع ما حُفظ على الجهاز وحده فوق تخطيط الخادم: الصناديق المحلّيّة (الأب قبل الابن) ثمّ السجلّات التي لا يعرفها الخادم
  /// والإعدادات الغائبة عنه. ما عند الخادم أصلاً لا يُكتب فوقه (جهازٌ آخر حدّثه). يبقى العلم إن تعثّر شيء.
  static Future<void> _pushLocal(FiberLayout local) async {
    var ok = true;
    final remap = <int, int>{};
    var pending = local.boxes.values.where((b) => b.id < 0).toList();
    while (pending.isNotEmpty && ok) {
      final ready = pending.where((b) => b.parentId == null || b.parentId! >= 0 || remap.containsKey(b.parentId)).toList();
      if (ready.isEmpty) break; // أبٌ محلّيّ مفقود
      for (final b in ready) {
        final parent = b.parentId == null ? null : (remap[b.parentId] ?? b.parentId);
        final r = await FiberApi.saveBox(b.copyWith(parentId: parent));
        if (!r.ok || r.box == null) {
          ok = false;
          break;
        }
        remap[b.id] = r.box!.id;
        layout.value = layout.value.withBox(r.box!);
      }
      pending = pending.where((b) => !remap.containsKey(b.id)).toList();
    }
    final server = layout.value;
    final byOlt = <int, List<({FiberOnuRecord record, String? oldKey})>>{};
    var next = server;
    for (final rec in local.onus.values) {
      if (server.onus.containsKey(FiberLayout.recordKey(rec.oltId, rec.key))) continue;
      final box = rec.boxId == null ? null : (rec.boxId! < 0 ? remap[rec.boxId] : rec.boxId);
      if (rec.boxId != null && rec.boxId! < 0 && box == null) continue; // صندوقه لم يُرفع
      final fixed = rec.copyWith(boxId: box, clearBox: box == null);
      if (fixed.isEmpty) continue;
      next = next.withRecord(fixed);
      byOlt.putIfAbsent(rec.oltId, () => []).add((record: fixed, oldKey: null));
    }
    layout.value = next;
    for (final e in byOlt.entries) {
      for (var i = 0; i < e.value.length; i += 300) {
        final r = await FiberApi.saveRecords(e.key, e.value.skip(i).take(300).toList());
        if (!r.ok) ok = false;
      }
    }
    for (final st in local.settings.values) {
      if (server.settings.containsKey(st.oltId)) continue;
      layout.value = layout.value.withSettings(st);
      final r = await FiberApi.saveSettings(st);
      if (!r.ok) ok = false;
    }
    if (!ok) return;
    _pending = false;
    final admin = _admin;
    if (admin == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_pendingKey(admin));
    } catch (_) {}
  }

  static void applyEvent(FiberEventRecord e) {
    layout.value = layout.value.withEvent(e);
    unawaited(_persist());
  }

  static void applyCaps(int oltId, Map<String, dynamic> c) {
    caps.value = Map.unmodifiable({...caps.value, oltId: c});
  }

  // ── دفاتر الضوء ─────────────────────────────────────────────────────────────────────

  static RxDailyBook bookOf(int oltId) => _books.putIfAbsent(oltId, RxDailyBook.new);

  /// يحمّل دفتر الأولت من الجهاز ثمّ يدمج تاريخ الخادم (مرّةً كلّ ٣٠ دقيقة).
  static Future<RxDailyBook> loadBook(int oltId, {DateTime? now}) async {
    final admin = _admin ?? await AuthStorage.readAdminId() ?? '';
    if (!_books.containsKey(oltId)) {
      try {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString(_rxKey(admin, oltId));
        _books[oltId] = raw == null ? RxDailyBook() : RxDailyBook.fromJson(jsonDecode(raw));
      } catch (_) {
        _books[oltId] = RxDailyBook();
      }
    }
    final book = _books[oltId]!;
    final at = _rxLoadedAt[oltId];
    final t = now ?? DateTime.now();
    if (serverReady && (at == null || t.difference(at) > const Duration(minutes: 30))) {
      _rxLoadedAt[oltId] = t;
      final r = await FiberApi.loadRx(oltId);
      if (r.ok) {
        final today = fiberDay(t);
        for (final row in r.rows) {
          book.mergeServer(row.key, row.day, today: today);
        }
      }
    }
    return book;
  }

  /// آخر لقطةٍ للأولت تُرسم فوراً في الفتحة القادمة ([FiberMonitor.snapshotJson]).
  static Future<void> saveSnapshot(int oltId, Map<String, dynamic> json) async {
    final admin = _admin ?? await AuthStorage.readAdminId() ?? '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_snapKey(admin, oltId), jsonEncode(json));
    } catch (_) {/* الفتحة القادمة تقرأ من الأولت */}
  }

  static Future<Map<String, dynamic>?> loadSnapshot(int oltId) async {
    try {
      final admin = _admin ?? await AuthStorage.readAdminId() ?? '';
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_snapKey(admin, oltId));
      if (raw == null) return null;
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> persistBook(int oltId, {DateTime? now}) async {
    final book = _books[oltId];
    if (book == null) return;
    book.prune(fiberDay(now ?? DateTime.now()));
    final admin = _admin ?? await AuthStorage.readAdminId() ?? '';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_rxKey(admin, oltId), jsonEncode(book.toJson()));
    } catch (_) {/* الدفتر في الذاكرة يبقى */}
  }

  // ── الحفظ المحلّيّ ─────────────────────────────────────────────────────────────────

  static Future<void> _persist() async {
    final admin = _admin;
    if (admin == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(admin), jsonEncode(layout.value.toJson()));
    } catch (_) {}
  }

  static Future<FiberLayout?> _restore(String admin) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key(admin));
      if (raw == null) return null;
      final l = FiberLayout.fromJson(jsonDecode(raw));
      for (final b in l.boxes.values) {
        if (b.id <= _localId) _localId = b.id - 1;
      }
      return l;
    } catch (_) {
      return null;
    }
  }

  /// يُفرغ الذاكرة (من [SessionManager]) — لا يرى المدير التالي شبكة سابقه.
  static void reset() {
    layout.value = FiberLayout.empty;
    caps.value = const {};
    loaded = false;
    serverReady = true;
    lastError = null;
    _admin = null;
    _loading = null;
    _books.clear();
    _rxLoadedAt.clear();
    _pending = false;
  }

  /// ويمسح النسخ المحفوظة على الجهاز (الخروج الحقيقيّ): أسماء المشتركين المربوطة لا تبقى بعد صاحبها — إلّا تخطيط حسابٍ
  /// عنده تعديلاتٌ لم تصل الخادم بعد ([_pending])، فيبقى لصاحبه وحده (المفتاح بحسابه) ويُرفع بدخوله القادم.
  static Future<void> clear() async {
    reset();
    try {
      final p = await SharedPreferences.getInstance();
      final keys = p.getKeys();
      final keep = {
        for (final k in keys)
          if (k.startsWith('fiber.pending.v1.')) 'fiber.layout.v1.${k.substring('fiber.pending.v1.'.length)}',
      };
      for (final k in keys.where((k) => k.startsWith('fiber.layout.v1.') || k.startsWith('fiber.rx.') || k.startsWith('fiber.snap.')).toList()) {
        if (!keep.contains(k)) await p.remove(k);
      }
    } catch (_) {}
  }

  @visibleForTesting
  static void debugSet(FiberLayout l, {bool ready = true, String admin = 'test'}) {
    layout.value = l;
    serverReady = ready;
    loaded = true;
    _admin = admin;
  }
}
