import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../api/receipt_settings_api.dart';
import '../../../services/receipt_layout.dart';

/// نتيجة «حفظ» كما تعرضها الشاشة.
@immutable
class DesignerSaveOutcome {
  const DesignerSaveOutcome({required this.ok, required this.message, this.conflict = false, this.notSaved = const []});

  final bool ok;
  final String message;

  /// 409: حفظٌ أحدث من جهازٍ آخر — الشاشة تعرض «تحديث (تضيع تعديلاتك)».
  final bool conflict;

  /// ما أرسلناه ولم يحفظه الخادم (خادمٌ أقدم يُسقط مفاتيح v3) — مسارات.
  final List<String> notSaved;
}

/// «تصميم الوصل» في التطبيق (spec §4.4): يجلب الصفّ كما هو، ويرقّع **التصميم الخامّ** (لا يعيد تسلسل نموذجٍ يُسقط ما لا
/// يفهمه)، ويحفظ الأعمدة السبعة كلّها + مفاتيح v1 الستّة والثلاثين + `layout` مضغوطاً (أو null حين يكون افتراضيّاً) +
/// `if_updated_at` — بلا الشعار (يبقى المحفوظ). لا يُنزل `v` أبداً، ويُبقي مفاتيح `layout` التي لا يعرفها.
///
/// كلّ تعديلٍ يحفظ لقطةً للتراجع (حتى ٣٠)، و[draft] إعدادات الوصل كما ستُطبع — المعاينة تبنيها بالبايتات نفسها.
class ReceiptDesignController extends ChangeNotifier {
  ReceiptDesignController({
    Future<ReceiptDesignLoad> Function()? fetch,
    Future<ReceiptSaveResult> Function(Map<String, dynamic> body)? save,
  })  : _fetch = fetch ?? ReceiptSettingsApi.fetchRaw,
        _saveCall = save ?? ReceiptSettingsApi.save;

  final Future<ReceiptDesignLoad> Function() _fetch;
  final Future<ReceiptSaveResult> Function(Map<String, dynamic> body) _saveCall;

  /// أعمدة الصفّ التي يرسلها كلّ حفظ — عمودٌ غائب يمحوه الخادم (`shop_*`) أو يعيده (`show_qr` 1، `paper_size` pos،
  /// `auto_print` 0).
  static const columnKeys = ['shop_name', 'shop_address', 'shop_phone', 'footer_text', 'show_qr', 'paper_size', 'auto_print'];

  static const int maxUndo = 30;

  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _disposed = false;

  Uint8List? _logo;
  Map<String, dynamic> _row = const {};
  Map<String, dynamic> _cols = {};
  Map<String, dynamic> _design = {};
  Object? _token;

  /// الخادم يعرف بروتوكول التعارض (`updated_at` في الجلب): `if_updated_at` يُرسل دائماً — null = «لم أرَ صفّاً».
  bool _hasToken = false;
  String _savedSig = '';
  final List<String> _history = [];
  int _revision = 0;

  bool get loading => _loading;
  String? get loadError => _loadError;
  bool get saving => _saving;

  /// يرتفع مع كلّ تعديل/تحميل — المعاينة تعيد البناء عليه.
  int get revision => _revision;

  /// ختم آخر حفظٍ كما أعاده الخادم (يُرسل كما هو).
  Object? get updatedAt => _token;

  /// الشعار المحفوظ (لا يُعدَّل من التطبيق في المرحلة ١).
  Uint8List? get logo => _logo;

  /// التصميم الخامّ الحاليّ (للقراءة) — مفاتيح v1 و`layout`.
  Map<String, dynamic> get design => _design;

  /// `layout` الخامّ (null = وصل v1).
  Map<String, dynamic>? get layout => _design['layout'] is Map ? _design['layout'] as Map<String, dynamic> : null;

  Object? column(String key) => _cols[key];
  String get paperSize => _cols['paper_size'] == 'a4' ? 'a4' : 'pos';
  bool get showQr => _cols['show_qr'] != false;
  bool get autoPrint => _cols['auto_print'] == true;

  bool get canUndo => _history.isNotEmpty;
  bool get dirty => !_loading && _loadError == null && _signature() != _savedSig;

  /// إعدادات الوصل كما ستُطبع بعد الحفظ — المعاينة و«اطبع تجربة» تبنيان منها.
  ReceiptSettings get draft => ReceiptSettings.fromJson(
        {..._row, ..._cols, 'design': _designToSend()},
        logo: _logo,
      );

  // ───────────────────────── تحميل ─────────────────────────

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    _notify();
    final r = await _fetch();
    if (_disposed) return;
    final s = r.settings;
    if (s == null) {
      _loading = false;
      _loadError = r.error ?? 'تعذّر جلب تصميم الوصل';
      _notify();
      return;
    }
    _adopt(s.raw ?? const {}, s.logo);
    _history.clear();
    _loading = false;
    _notify();
  }

  /// يتبنّى صفّ الخادم: الأعمدة بأنواعها، والتصميم نسخةً عميقة، و`v` لا يقلّ عن ٣ (spec §3.4 Load).
  void _adopt(Map<String, dynamic> row, Uint8List? logo) {
    _row = Map<String, dynamic>.from(row)..remove('logo_data');
    _logo = logo;
    _token = row['updated_at'];
    _hasToken = row.containsKey('updated_at');
    bool on(Object? v, {required bool fallback}) =>
        v == null ? fallback : (v == true || v == 1 || '$v' == '1' || '$v' == 'true');
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    _cols = {
      'shop_name': text(row['shop_name']),
      'shop_address': text(row['shop_address']),
      'shop_phone': text(row['shop_phone']),
      'footer_text': text(row['footer_text']),
      'show_qr': on(row['show_qr'], fallback: true),
      'paper_size': row['paper_size'] == 'a4' ? 'a4' : 'pos',
      'auto_print': on(row['auto_print'], fallback: false),
    };
    final d = row['design'];
    _design = d is Map ? _deep(d) as Map<String, dynamic> : <String, dynamic>{};
    final l = _design['layout'];
    if (l is Map) {
      final v = l['v'];
      l['v'] = v is int && v > 3 ? v : 3;
    } else {
      _design.remove('layout');
    }
    _savedSig = _signature();
    _revision++;
  }

  // ───────────────────────── الحفظ ─────────────────────────

  /// `layout` الذي يُرسل: مضغوطاً، أو null حين لا يبقى فيه شيء (الوصل بطريق v1).
  Map<String, dynamic>? get compactLayout => receiptCompactLayout(_design['layout']);

  /// التصميم كما يُرسل: مفاتيح v1 الستّة والثلاثون كلّها (الافتراضيّ ثمّ المحفوظ ثمّ التعديلات) + `layout`.
  Map<String, dynamic> _designToSend() => {
        ...receiptV1AllDefaults,
        for (final k in receiptV1AllDefaults.keys)
          if (_design.containsKey(k) && _design[k] != null) k: _design[k],
        'layout': compactLayout,
      };

  /// جسم الحفظ (spec §4.4): الأعمدة السبعة + التصميم + `if_updated_at` — بلا `logo_data`.
  Map<String, dynamic> buildSaveBody() => {
        for (final k in columnKeys) k: _cols[k],
        'design': _designToSend(),
        if (_hasToken) 'if_updated_at': _token,
      };

  Future<DesignerSaveOutcome> save() async {
    if (_saving) return const DesignerSaveOutcome(ok: false, message: 'جارٍ الحفظ…');
    _saving = true;
    _notify();
    final body = buildSaveBody();
    final sent = (body['design'] as Map)['layout'];
    final r = await _saveCall(body);
    if (_disposed) return DesignerSaveOutcome(ok: r.ok, message: r.message);
    _saving = false;
    if (!r.ok) {
      _notify();
      return DesignerSaveOutcome(ok: false, message: r.message, conflict: r.conflict);
    }
    // ما حُفظ فعلاً: ردّ الخادم إن حمل التصميم (خادمٌ أقدم يُسقط مفاتيح v3 — يُقال بالمسار).
    final stored = r.hasDesign ? r.design : body['design'] as Map<String, dynamic>;
    final storedLayout = stored is Map ? receiptCompactLayout(stored!['layout']) : null;
    final lost = r.hasDesign ? receiptLayoutDiff(sent, storedLayout) : const <String>[];
    final row = <String, dynamic>{
      ..._row,
      ..._cols,
      'design': stored,
      if (r.hasUpdatedAt) 'updated_at': r.updatedAt,
    };
    _adopt(row, _logo);
    _history.clear();
    _notify();
    return DesignerSaveOutcome(
      ok: true,
      message: lost.isEmpty ? 'حُفظ تصميم الوصل' : 'حُفظ — لكنّ الخادم لم يحفظ: ${lost.take(4).join('، ')}',
      notSaved: lost,
    );
  }

  // ───────────────────────── التعديلات ─────────────────────────

  /// عمودٌ من الأعمدة السبعة (اسم المحلّ وعنوانه وهاتفه، والذيل، وQR، ونوع الورق، والطباعة التلقائيّة).
  /// [typing] نقرات الكتابة في الحقل نفسه لقطة تراجعٍ واحدة.
  void setColumn(String key, Object? value, {bool typing = false}) {
    assert(columnKeys.contains(key), key);
    _edit(coalesce: typing ? 'col:$key' : null, () {
      if (value is String && value.trim().isEmpty) {
        _cols[key] = null;
      } else {
        _cols[key] = value;
      }
    });
  }

  /// مفتاحٌ من مفاتيح v1 (null = يعود افتراضيّاً).
  void setV1(String key, Object? value) {
    assert(receiptV1AllDefaults.containsKey(key), key);
    _edit(() {
      if (value == null) {
        _design.remove(key);
      } else {
        _design[key] = value;
      }
    });
  }

  /// مفاتيح v1 دفعةً واحدة (لقطة تراجعٍ واحدة).
  void setV1All(Map<String, Object?> values) => _edit(() {
        for (final e in values.entries) {
          if (e.value == null) {
            _design.remove(e.key);
          } else {
            _design[e.key] = e.value;
          }
        }
      });

  /// الورق: `pos` بعرضه، أو `a4` — لقطة تراجعٍ واحدة للعمود ومفتاح v1.
  void setPaper(String size, {num? widthMm}) => _edit(() {
        _cols['paper_size'] = size == 'a4' ? 'a4' : 'pos';
        if (widthMm != null) _design['paper_width_mm'] = widthMm;
      });

  /// الهوامش الأربع معاً (ملّيمتر).
  void setMargins(num mm) => _edit(() {
        for (final k in const ['margin_top_mm', 'margin_right_mm', 'margin_bottom_mm', 'margin_left_mm']) {
          _design[k] = mm;
        }
      });

  /// مفتاحٌ في أعلى `layout` (`density` · `emoji` · `mono` · `currency` …) — null يحذفه.
  void setLayoutKey(String key, Object? value, {bool typing = false}) => _edit(coalesce: typing ? 'l:$key' : null, () {
        final l = _layout();
        if (value == null) {
          l.remove(key);
        } else {
          l[key] = value;
        }
      });

  /// ترقيع `layout.fields[id]` — قيمةٌ null تحذف مفتاحها.
  void setField(String id, Map<String, Object?> patch, {bool typing = false}) =>
      _edit(coalesce: typing ? 'f:$id:${patch.keys.join(',')}' : null, () => _patch(_layoutMap('fields'), id, patch));

  /// ترقيع `layout.sections[id]`.
  void setSection(String id, Map<String, Object?> patch, {bool typing = false}) =>
      _edit(coalesce: typing ? 's:$id:${patch.keys.join(',')}' : null, () => _patch(_layoutMap('sections'), id, patch));

  /// ترقيع `layout.blocks[id]` (الحاويات: الشعار، العنوان والهاتف، الرقم والتاريخ، QR، الذيل).
  void setBlock(String id, Map<String, Object?> patch) => _edit(() => _patch(_layoutMap('blocks'), id, patch));

  /// عنوان نوع الوصل (فارغ ⇒ الافتراضيّ).
  void setTitle(String kind, String? text, {bool typing = false}) => _edit(coalesce: typing ? 't:$kind' : null, () {
        final t = _layoutMap('titles');
        if (text == null || text.trim().isEmpty) {
          t.remove(kind);
        } else {
          t[kind] = text;
        }
      });

  List<Map<String, dynamic>> get texts {
    final xs = layout?['texts'];
    return xs is List ? [for (final x in xs) if (x is Map) Map<String, dynamic>.from(x)] : const [];
  }

  /// نصٌّ إضافيّ جديد (أسفل الوصل) — حتى ستّة.
  void addText() {
    if (texts.length >= receiptLimits3['texts']!) return;
    _edit(() {
      final l = _layout();
      final xs = l['texts'] is List ? List<dynamic>.from(l['texts'] as List) : <dynamic>[];
      xs.add({'id': 't${xs.length + 1}', 'at': 'bottom', 'text': ''});
      l['texts'] = xs;
    });
  }

  void setText(int i, Map<String, Object?> patch, {bool typing = false}) =>
      _edit(coalesce: typing ? 'x:$i:${patch.keys.join(',')}' : null, () {
        final l = _layout();
        final xs = l['texts'] is List ? List<dynamic>.from(l['texts'] as List) : <dynamic>[];
        if (i < 0 || i >= xs.length || xs[i] is! Map) return;
        final t = Map<String, dynamic>.from(xs[i] as Map);
        for (final e in patch.entries) {
          if (e.value == null) {
            t.remove(e.key);
          } else {
            t[e.key] = e.value;
          }
        }
        xs[i] = t;
        l['texts'] = xs;
      });

  void removeText(int i) => _edit(() {
        final l = _layout();
        final xs = l['texts'] is List ? List<dynamic>.from(l['texts'] as List) : <dynamic>[];
        if (i < 0 || i >= xs.length) return;
        xs.removeAt(i);
        l['texts'] = xs;
      });

  /// ترتيب الكتل المحلول.
  List<String> get blockOrder => receiptResolveBlockOrder(_obj(layout?['order'])?['blocks']);

  /// ترتيب الأقسام المحلول.
  List<String> get bodyOrder => receiptResolveBodyOrder(_obj(layout?['order'])?['body']);

  /// صفوف كلّ قسمٍ محلولة.
  Map<String, List<String>> get rowOrder => receiptResolveSectionFields(layout?['order']);

  /// يحرّك عنصراً خطوةً (±1): صفٌّ داخل قسمه (ومن طرفه إلى القسم المجاور)، أو قسمٌ بين الأقسام، أو كتلة بين الكتل.
  void move(String id, int delta) {
    if (delta == 0) return;
    if (receiptRowFieldIds.contains(id)) return _moveRow(id, delta);
    if (receiptBodySections.contains(id)) {
      final order = bodyOrder;
      final i = order.indexOf(id);
      final j = i + delta;
      if (j < 0 || j >= order.length) return;
      order
        ..removeAt(i)
        ..insert(j, id);
      _edit(() => _orderMap()['body'] = order);
      return;
    }
    final order = blockOrder;
    final i = order.indexOf(id);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= order.length) return;
    order
      ..removeAt(i)
      ..insert(j, id);
    _edit(() => _orderMap()['blocks'] = order);
  }

  void _moveRow(String id, int delta) {
    final rows = rowOrder;
    final body = bodyOrder;
    final sec = rows.entries.firstWhere((e) => e.value.contains(id)).key;
    final list = rows[sec]!;
    // الصفوف المحجوزة لا تُرسم في المرحلة ١ — الحركة بين الظاهرة وحدها.
    final shown = [for (final x in list) if (!receiptReservedFieldIds.contains(x)) x];
    final i = shown.indexOf(id);
    final j = i + delta;
    if (j >= 0 && j < shown.length) {
      final other = shown[j];
      final a = list.indexOf(id);
      final b = list.indexOf(other);
      list[a] = other;
      list[b] = id;
    } else {
      // من طرف القسم إلى القسم المجاور بترتيب الطباعة.
      final k = body.indexOf(sec) + (delta > 0 ? 1 : -1);
      if (k < 0 || k >= body.length) return;
      final target = rows[body[k]]!;
      list.remove(id);
      if (delta > 0) {
        target.insert(0, id);
      } else {
        target.add(id);
      }
    }
    _edit(() {
      final o = _orderMap();
      for (final s in receiptBodySections) {
        o[s] = rows[s];
      }
    });
  }

  /// «قوالب جاهزة»: الورق ومفاتيح v1 والضغط و«أسود فقط» — الحقول والنصوص والعناوين كما هي.
  void applyTemplate(String id) {
    if (!receiptTemplates.containsKey(id)) return;
    _edit(() {
      final r = receiptApplyTemplate(
        (paperSize: paperSize, design: {..._design}..remove('layout'), layout: layout),
        id,
      );
      _design = {...r.design, 'layout': r.layout};
      _cols['paper_size'] = r.paperSize;
    });
  }

  /// «حجم الوصل»: مفاتيح v1 الاثنا عشر والضغط والرموز (كالموقع).
  void applyPreset(String id) {
    final p = receiptPresets[id];
    if (p == null) return;
    _edit(() {
      _design.addAll(p.v1);
      final l = _layout();
      if (p.density == 'normal') {
        l.remove('density');
      } else {
        l['density'] = p.density;
      }
      if (p.emoji) {
        l.remove('emoji');
      } else {
        l['emoji'] = false;
      }
    });
  }

  /// «حجم الخطّ العامّ» (٨٠–١٣٠٪): الأساس والعنوان = round(١٣ أو ١٦ × النسبة).
  void setFontPct(int pct) {
    final p = pct.clamp(80, 130);
    _edit(() {
      _design['font_size_base'] = (13 * p / 100).round();
      _design['font_size_title'] = (16 * p / 100).round();
    });
  }

  /// النسبة الحاليّة لـ«حجم الخطّ العامّ».
  int get fontPct {
    final b = _design['font_size_base'];
    return b is num ? (b / 13 * 100).round() : 100;
  }

  /// «إعادة للافتراضي»: مفاتيح v1 افتراضيّة وبلا `layout` — المحتوى (اسم المحلّ وعنوانه…) كما هو (كالموقع).
  void resetToDefault() => _edit(() {
        _design = {...receiptV1AllDefaults};
      });

  /// تراجعٌ خطوة.
  void undo() {
    if (_history.isEmpty) return;
    _lastCoalesce = null;
    final snap = jsonDecode(_history.removeLast()) as Map<String, dynamic>;
    _cols = Map<String, dynamic>.from(snap['cols'] as Map);
    _design = Map<String, dynamic>.from(snap['design'] as Map);
    _revision++;
    _notify();
  }

  /// كم عنصراً بحجمٍ مثبّت (`pt`) — «إرجاعها للتلقائي».
  int get pinnedCount => receiptPinnedCount(layout);

  /// يعيد كلّ حجمٍ مثبّت للتلقائي.
  void unpinAll() {
    final l = layout;
    if (l == null) return;
    _edit(() => _design['layout'] = receiptUnpinAll(l));
  }

  // ───────────────────────── داخليّ ─────────────────────────

  String? _lastCoalesce;

  void _edit(void Function() change, {String? coalesce}) {
    // كتابةٌ متّصلة في الحقل نفسه = لقطةٌ واحدة (التراجع يعيد الحقل كما كان قبل الكتابة).
    if (coalesce == null || coalesce != _lastCoalesce || _history.isEmpty) {
      _history.add(_snapshot());
      if (_history.length > maxUndo) _history.removeAt(0);
    }
    _lastCoalesce = coalesce;
    change();
    _revision++;
    _notify();
  }

  String _snapshot() => jsonEncode({'cols': _cols, 'design': _design});

  /// بصمة ما سيُرسل — «غير محفوظ» حين تختلف عن آخر تحميل/حفظ.
  String _signature() => jsonEncode({
        for (final k in columnKeys) k: _cols[k],
        'design': _designToSend(),
      });

  Map<String, dynamic> _layout() {
    final l = _design['layout'];
    if (l is Map<String, dynamic>) return l;
    final created = <String, dynamic>{'v': 3};
    _design['layout'] = created;
    return created;
  }

  Map<String, dynamic> _layoutMap(String key) {
    final l = _layout();
    final m = l[key];
    if (m is Map<String, dynamic>) return m;
    final created = m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
    l[key] = created;
    return created;
  }

  Map<String, dynamic> _orderMap() => _layoutMap('order');

  static void _patch(Map<String, dynamic> parent, String id, Map<String, Object?> patch) {
    final cur = parent[id] is Map ? Map<String, dynamic>.from(parent[id] as Map) : <String, dynamic>{};
    for (final e in patch.entries) {
      if (e.value == null) {
        cur.remove(e.key);
      } else {
        cur[e.key] = e.value;
      }
    }
    if (cur.isEmpty) {
      parent.remove(id);
    } else {
      parent[id] = cur;
    }
  }

  static Map<String, dynamic>? _obj(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

  static Object? _deep(Object? v) {
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _deep(e.value)};
    if (v is List) return [for (final x in v) _deep(x)];
    return v;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
