import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/whatsapp_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/connection_alerts.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// إعدادات «تنبيه المشترك» بمشكلة الاتصال — لكلّ مدير.
///
/// ثلاثة أشياء في شاشة واحدة لأنّها تُقرأ معاً:
///   • تفعيل الميزة (= تفعيل قالب الرسالة العامّة).
///   • الحدود الأربعة القابلة للضبط ضمن المسموح. والكيبل ثابت.
///   • نصّ الرسالة: العامّة وفيها {problems}، وسطرٌ لكلّ مشكلة — مع معاينة
///     حيّة فيرى المدير ما سيقرؤه المشترك قبل الحفظ.
///
/// القوالب تُحفظ في `whatsapp_templates` كبقيّة القوالب، لكنّها لا تُعرض
/// في قائمة القوالب العامّة: سبعة أسطر قصيرة متفرّقة هناك لا معنى لها
/// منفصلةً عن بعضها.
class ConnectionAlertsScreen extends StatefulWidget {
  const ConnectionAlertsScreen({super.key});

  @override
  State<ConnectionAlertsScreen> createState() => _ConnectionAlertsScreenState();
}

class _ConnectionAlertsScreenState extends State<ConnectionAlertsScreen> {
  bool _loading = true;
  bool _saving = false;

  ConnectionAlertThresholds _t = ConnectionAlertThresholds.defaults;
  ConnectionAlertThresholds _savedT = ConnectionAlertThresholds.defaults;

  /// التفعيل في حدود المدير على الخادم (`enabled`) — متوقّفٌ حتّى يفعّله.
  bool _enabled = false;
  bool _savedEnabled = false;

  /// قالبٌ عامّ حُفظ معطّلاً في نسخةٍ سابقة (كان التفعيل فيه). يُعاد
  /// تفعيله عند الحفظ كي لا يبقى مفتاحٌ قديم يُعطّل ما فعّله المدير.
  bool _envelopeInactive = false;

  /// نصّ كلّ نوع كما وصل (أو الافتراضيّ) — لمعرفة ما تغيّر عند الحفظ.
  final Map<String, String> _savedText = {};
  final Map<String, bool> _exists = {};
  final Map<String, TextEditingController> _ctrls = {
    for (final t in ConnectionAlertTemplates.allTypes)
      t: TextEditingController(),
  };

  bool get _canEdit => Perms.has('whatsapp.templates');

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls.values) {
      c.addListener(_onTextChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ConnectionAlertSettings.ensureLoaded(force: true),
      WhatsAppApi.loadTemplates(refresh: true),
    ]);
    if (!mounted) return;
    final t = results[0] as ConnectionAlertThresholds;
    final templates = results[1] as List<WhatsTemplate>?;
    WhatsTemplate? own(String type) {
      for (final x in templates ?? const <WhatsTemplate>[]) {
        if (x.templateType == type) return x;
      }
      return null;
    }

    final envelope = own(ConnectionAlertTemplates.envelopeType);
    setState(() {
      _t = t;
      _savedT = t;
      _enabled = t.enabled;
      _savedEnabled = t.enabled;
      _envelopeInactive = envelope != null && !envelope.isActive;
      for (final type in ConnectionAlertTemplates.allTypes) {
        final tpl = own(type);
        final text = (tpl?.messageContent.trim().isNotEmpty ?? false)
            ? tpl!.messageContent
            : ConnectionAlertTemplates.defaultFor(type);
        _exists[type] = tpl != null;
        _savedText[type] = text;
        _ctrls[type]!.text = text;
      }
      _loading = false;
    });
  }

  bool get _thresholdsChanged =>
      _t.signalDbm != _savedT.signalDbm ||
      _t.ccqPct != _savedT.ccqPct ||
      _t.fiberRxDbm != _savedT.fiberRxDbm ||
      _t.fiberTempC != _savedT.fiberTempC;

  List<String> get _changedTypes => [
        for (final type in ConnectionAlertTemplates.allTypes)
          if (_ctrls[type]!.text.trim() != (_savedText[type] ?? '').trim())
            type,
      ];

  /// أنواعٌ لا صفّ لها في الخادم بعد — تعمل بالافتراضيّ ولا تُرى محفوظة.
  List<String> get _missingTypes => [
        for (final type in ConnectionAlertTemplates.allTypes)
          if (_exists[type] != true) type,
      ];

  /// ⚠️ الناقص يُعدّ تغييراً: بدونه يبقى زرّ الحفظ معطّلاً لمن لم يعدّل
  /// شيئاً، فلا يُثبَّت النصّ أبداً وتبقى بطاقته في القوالب «فاضي».
  bool get _dirty =>
      _thresholdsChanged ||
      _enabled != _savedEnabled ||
      _changedTypes.isNotEmpty ||
      _missingTypes.isNotEmpty;

  Future<void> _save() async {
    if (_saving || !_canEdit) return;
    final envelopeText =
        _ctrls[ConnectionAlertTemplates.envelopeType]!.text.trim();
    if (envelopeText.isEmpty) {
      showSheetSnack(context, 'نصّ الرسالة العامّة فارغ', isError: true);
      return;
    }
    setState(() => _saving = true);
    final failed = <String>[];

    if (_thresholdsChanged || _savedT.isDefault || _enabled != _savedEnabled) {
      final r = await ConnectionAlertSettings.save(_t.copyWith(enabled: _enabled));
      if (r.ok) {
        _savedT = ConnectionAlertSettings.current.value;
        _t = _savedT;
        _savedEnabled = _savedT.enabled;
      } else {
        failed.add(r.message ?? 'تعذّر حفظ الحدود');
      }
    }

    // الناقص يُحفظ بنصّه الحاليّ (الافتراضيّ إن لم يُعدَّل) فيصير ما يُرسل
    // هو ما يُرى في القوالب، وتجده المرحلة المجدولة في الخادم.
    final types = {
      ..._changedTypes,
      ..._missingTypes,
      if (_envelopeInactive) ConnectionAlertTemplates.envelopeType,
    };
    for (final type in types) {
      final isEnvelope = type == ConnectionAlertTemplates.envelopeType;
      final text = _ctrls[type]!.text.trim();
      // سطرٌ أُفرغ = عودةٌ إلى الافتراضيّ، لا سطرٌ فارغ يُبتلع في الرسالة.
      final body = text.isEmpty ? ConnectionAlertTemplates.defaultFor(type) : text;
      final r = await WhatsAppApi.saveTemplate(
        templateType: type,
        templateName: ConnectionAlertTemplates.labels[type] ?? type,
        messageContent: body,
        // القالب نفسه فعّالٌ دائماً — التفعيل في `enabled` لا هنا.
        isActive: true,
      );
      if (r.ok) {
        _savedText[type] = body;
        _exists[type] = true;
        if (text.isEmpty) _ctrls[type]!.text = body;
        if (isEnvelope) _envelopeInactive = false;
      } else {
        failed.add(
            'تعذّر حفظ «${ConnectionAlertTemplates.labels[type] ?? type}»');
      }
    }
    // ⚠️ `saveTemplate` لا يمسّ كاش القوالب (عشر دقائق). بدون هذا يُرسل
    // «تنبيه المشترك» بالنصّ القديم بعد الحفظ مباشرةً.
    if (types.isNotEmpty) await WhatsAppApi.loadTemplates(refresh: true);

    if (!mounted) return;
    setState(() => _saving = false);
    showSheetSnack(
      context,
      // كلّ عنصرٍ جملةٌ تامّة («تعذّر حفظ …») — كان يُسبق بـ«تعذّر:»
      // فيصير «تعذّر: تعذّر حفظ الحدود».
      failed.isEmpty ? 'تم حفظ إعدادات التنبيه' : failed.join(' • '),
      isError: failed.isNotEmpty,
    );
  }

  void _restoreDefaults() {
    for (final type in ConnectionAlertTemplates.allTypes) {
      _ctrls[type]!.text = ConnectionAlertTemplates.defaultFor(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'تنبيهات الاتصال',
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      bottomNavigationBar: _loading || !_canEdit
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.sm),
                child: SizedBox(
                  height: H.button,
                  child: FilledButton.icon(
                    onPressed: _saving || !_dirty ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onBrand,
                            ),
                          )
                        : const Icon(LucideIcons.check, size: 18),
                    label: Text('حفظ', style: AppType.button()),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: AppColors.onBrand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.button),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _intro(),
                const SizedBox(height: Sp.md),
                _card(children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged:
                        _canEdit ? (v) => setState(() => _enabled = v) : null,
                    activeTrackColor: AppColors.brand,
                    title: Text('تفعيل تنبيه المشترك',
                        style: AppType.bodyStrong(color: AppColors.textHi)),
                    subtitle: Text(
                      _enabled
                          ? 'الزرّ يظهر على كارت المشترك عند وجود مشكلة'
                          : 'متوقّف — فعّله ليظهر زرّ «تنبيه المشترك»',
                      style: AppType.muted(color: AppColors.textMid),
                    ),
                  ),
                ]),
                const SizedBox(height: Sp.lg),
                _sectionTitle('حدود المشاكل'),
                const SizedBox(height: Sp.sm),
                _card(children: [
                  _slider(
                    icon: LucideIcons.signal,
                    label: 'الإشارة',
                    rule: 'أضعف من',
                    valueText: iso('${_t.signalDbm} dBm'),
                    value: _t.signalDbm.toDouble(),
                    min: ConnectionAlertLimits.signalMin.toDouble(),
                    max: ConnectionAlertLimits.signalMax.toDouble(),
                    divisions: ConnectionAlertLimits.signalMax -
                        ConnectionAlertLimits.signalMin,
                    onChanged: (v) =>
                        setState(() => _t = _t.copyWith(signalDbm: v.round())),
                  ),
                  _divider(),
                  _slider(
                    icon: LucideIcons.gauge,
                    label: 'CCQ',
                    rule: 'هذا أو أقلّ',
                    valueText: iso('${_t.ccqPct}%'),
                    value: _t.ccqPct.toDouble(),
                    min: ConnectionAlertLimits.ccqMin.toDouble(),
                    max: ConnectionAlertLimits.ccqMax.toDouble(),
                    divisions:
                        ConnectionAlertLimits.ccqMax - ConnectionAlertLimits.ccqMin,
                    onChanged: (v) =>
                        setState(() => _t = _t.copyWith(ccqPct: v.round())),
                  ),
                  _divider(),
                  _slider(
                    icon: LucideIcons.signalHigh,
                    label: 'الإشارة الضوئيّة',
                    rule: 'أضعف من',
                    valueText: iso('${_fmt(_t.fiberRxDbm)} dBm'),
                    value: _t.fiberRxDbm,
                    min: ConnectionAlertLimits.rxMin,
                    max: ConnectionAlertLimits.rxMax,
                    // خطوة نصف ديسيبل.
                    divisions: ((ConnectionAlertLimits.rxMax -
                                ConnectionAlertLimits.rxMin) *
                            2)
                        .round(),
                    onChanged: (v) => setState(() =>
                        _t = _t.copyWith(fiberRxDbm: (v * 2).round() / 2)),
                  ),
                  _divider(),
                  _slider(
                    icon: LucideIcons.thermometer,
                    label: 'حرارة جهاز الفايبر',
                    rule: 'أعلى من',
                    valueText: iso('${_t.fiberTempC}°C'),
                    value: _t.fiberTempC.toDouble(),
                    min: ConnectionAlertLimits.tempMin.toDouble(),
                    max: ConnectionAlertLimits.tempMax.toDouble(),
                    divisions: ConnectionAlertLimits.tempMax -
                        ConnectionAlertLimits.tempMin,
                    onChanged: (v) =>
                        setState(() => _t = _t.copyWith(fiberTempC: v.round())),
                  ),
                  _divider(),
                  _fixedCableRow(),
                ]),
                const SizedBox(height: Sp.lg),
                Row(
                  children: [
                    Expanded(child: _sectionTitle('نصّ الرسالة')),
                    if (_canEdit)
                      TextButton.icon(
                        onPressed: _restoreDefaults,
                        icon: const Icon(LucideIcons.rotateCcw, size: 14),
                        label: Text('النصوص الافتراضيّة',
                            style: AppType.label(color: AppColors.brand)),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.brand),
                      ),
                  ],
                ),
                const SizedBox(height: Sp.sm),
                _card(children: [
                  _field(
                    ConnectionAlertTemplates.envelopeType,
                    title: 'الرسالة العامّة',
                    hint: '{problems} مكان أسطر المشاكل · {subscriber_name} اسم المشترك',
                    minLines: 5,
                  ),
                  if (!_ctrls[ConnectionAlertTemplates.envelopeType]!
                      .text
                      .contains('{problems}'))
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.xs),
                      child: Text(
                        'لا يوجد {problems} — ستُضاف أسطر المشاكل في نهاية الرسالة',
                        style: AppType.micro(color: AppColors.warning),
                      ),
                    ),
                  for (final type in ConnectionAlertTemplates.lineTypes) ...[
                    _divider(),
                    _field(
                      type,
                      title: (ConnectionAlertTemplates.labels[type] ?? type)
                          .replaceFirst('سطر: ', ''),
                      hint: _lineHint(type),
                      minLines: 2,
                    ),
                  ],
                ]),
                const SizedBox(height: Sp.lg),
                _sectionTitle('معاينة'),
                const SizedBox(height: Sp.sm),
                _preview(),
              ],
            ),
    );
  }

  // ── أجزاء ──────────────────────────────────────────────────────

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.brandSoftBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.brandSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.bellRing, size: 18, color: AppColors.brand),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'حين يكشف فحص جهاز المشترك مشكلةً بالحدود أدناه، يظهر زرّ '
              '«تنبيه المشترك» على كارته في القائمة، وهو حاضرٌ دائماً داخل '
              'الكارت. الرسالة تُرسل تلقائيّاً: عبر بوت تلغرام إن كان '
              'المشترك مربوطاً، وإلّا عبر واتساب.',
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(height: 1.6),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: AppType.bodyStrong(color: AppColors.textHi),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xs),
        child: Divider(height: 1, color: AppColors.divider),
      );

  Widget _slider({
    required IconData icon,
    required String label,
    required String rule,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.textMid),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(
                  '$label · $rule',
                  style: AppType.body(color: AppColors.textHi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                valueText,
                style: AppType.bodyStrong(color: AppColors.brand),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.brand,
            inactiveColor: AppColors.border,
            onChanged: _canEdit ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _fixedCableRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Icon(LucideIcons.cable, size: 15, color: AppColors.textMid),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(
              'كيبل LAN · 10 ميكا أو غير مربوط',
              style: AppType.body(color: AppColors.textHi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Text('ثابت', style: AppType.label(color: AppColors.textMid)),
          ),
        ],
      ),
    );
  }

  String _lineHint(String type) {
    final v = ConnectionAlertTemplates.lineVariable[type];
    return switch (type) {
      'conn_alert_cable' => '$v = «غير مربوط» أو «يقرأ 10 ميكا» (اختياريّ)',
      _ => '$v = القيمة المقروءة',
    };
  }

  Widget _field(
    String type, {
    required String title,
    required String hint,
    required int minLines,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: AppType.body(color: AppColors.textHi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: Sp.xs),
          TextField(
            controller: _ctrls[type],
            readOnly: !_canEdit,
            minLines: minLines,
            maxLines: minLines + 6,
            style: AppType.input(color: AppColors.textHi),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
          const SizedBox(height: Sp.xs),
          Text(hint,
              style: AppType.micro(color: AppColors.textLow),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  /// معاينة بمثالٍ ثابت: نانو كيبله مفصول وإشارته ‎-68 — يكفي ليرى المدير
  /// الرسالة العامّة وسطرين معاً.
  Widget _preview() {
    final sample = <ConnectionProblem>[
      const ConnectionProblem(
        kind: ConnectionProblemKind.cable,
        label: '',
        vars: {'{lan_state}': 'غير مربوط'},
      ),
      ConnectionProblem(
        kind: ConnectionProblemKind.signal,
        label: '',
        vars: {'{signal}': iso('-68 dBm')},
      ),
    ];
    final body = ConnectionAlerts.compose(
      envelope: _ctrls[ConnectionAlertTemplates.envelopeType]!.text,
      lines: {
        for (final t in ConnectionAlertTemplates.lineTypes) t: _ctrls[t]!.text,
      },
      problems: sample,
    );
    final text = body
        .replaceAll('{subscriber_name}', 'محمد علي')
        .replaceAll('{firstname}', 'محمد')
        .replaceAll('{username}', 'sample.user');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: AppType.body(color: AppColors.textHi).copyWith(height: 1.7),
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
