import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/account_api.dart';
import '../../core/platform/store_policy.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'account_widgets.dart';

/// «أجهزتي» (Pro — حدّ الأجهزة): الأجهزة النشطة للحساب، وإزالة واحدٍ منها
/// لتحرير مكانه. الحدّ = شركات الباقة + ١، و«نشط» = ظهر خلال ٣٠ يوماً.
///
/// 🐛 بلاغ ٢٠٢٦-١٠-١٣: «بلغت الحدّ الأعلى من الأجهزة في التطبيق، ما يكدر يمسح
/// جهاز». الخادم يرفض الجهاز الجديد برسالة «شيل جهازاً من «أجهزتي»» —
/// والتطبيق بلا «أجهزتي»، والرفض نفسه كان يُعامَل رمزَ بوّابةٍ فيرتدّ المستخدم
/// إلى «شركاتي» بلا كلمة. عالقٌ لا مخرج له إلّا الويب.
///
/// القائمة بتوكن الحساب وحده (الحدّ يُفحص عند دخول الساس لا هنا)، فتعمل
/// والجهاز نفسه مرفوض. مداخلها: ورقة «بلغت حدّ الأجهزة» عند الرفض
/// ([showDeviceLimitSheet])، وقائمة «شركاتي»، وبطاقة الحساب في الإعدادات.
class MyDevicesScreen extends StatefulWidget {
  const MyDevicesScreen({super.key, this.me, this.fromLimit = false, this.onRemoved});

  /// قراءة الحساب إن وُجدت — عدّاد الحدّ يظهر منها قبل وصول القائمة.
  final AccountMe? me;

  /// فُتحت من ورقة «بلغت حدّ الأجهزة»: متى صار في الحدّ مكانٌ ظهر زرّ «إعادة
  /// محاولة الدخول» يرجع بـ`true` فيُعاد الدخول نفسه فوراً.
  final bool fromLimit;

  /// بعد كلّ إزالةٍ ناجحة — أيّاً كان طريق الرجوع بعدها (الزرّ، السهم، سحب
  /// الرجوع، زرّ النظام)؛ نتيجة `pop` وحدها تضيع مع الأخيرين.
  final VoidCallback? onRemoved;

  @override
  State<MyDevicesScreen> createState() => _MyDevicesScreenState();
}

class _MyDevicesScreenState extends State<MyDevicesScreen> {
  AccountDevices? _data;
  String? _error; // مفتاح/رسالة — حين لا قائمة في اليد
  String? _removing; // معرّف الجهاز الذي يُزال الآن
  bool _removedAny = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// أوّل جلبٍ وإعادة المحاولة والسحب للتحديث. فشلٌ وفي اليد قائمة ← إشعار
  /// وتبقى القائمة؛ بلا قائمة ← حالة الخطأ وزرّ إعادة المحاولة.
  Future<void> _load() async {
    if (_data == null && _error != null) setState(() => _error = null);
    String err;
    try {
      final d = await AccountApi.listDevices();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
      return;
    } on AccountApiException catch (e) {
      err = e.message;
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 my devices: $e');
      err = 'account.err_network';
    }
    if (!mounted) return;
    if (_data == null) {
      setState(() => _error = err);
    } else {
      showAccountSnack(context, accountText(err), error: true);
    }
  }

  /// اسم الخادم معزولاً اتّجاهيّاً (قد يخلط لاتينيّاً بعربيّ: «Galaxy S24 (البيت)»
  /// يتفكّك ترتيبه داخل سطرٍ عربيّ)، وإلّا «جهاز» + المعرّف القصير.
  String _name(AccountDevice d) {
    final label = d.label;
    return label != null ? iso(_storeNeutral(label)) : 'account.devices_unnamed'.tr(args: [iso(d.shortId)]);
  }

  /// على آيفون لا يظهر اسم منصّةٍ أخرى (App Store 2.3.10): وصف الخادم «تطبيق أندرويد» /
  /// «متصفّح · أندرويد» يصير «تطبيق الهاتف» / «متصفّح · هاتف». أندرويد والويب كما هما.
  String _storeNeutral(String label) => StorePolicy.hidePurchaseFlows
      ? label.replaceAll('تطبيق أندرويد', 'تطبيق الهاتف').replaceAll('أندرويد', 'هاتف')
      : label;

  /// نوع الجهاز من وصف الخادم («تطبيق أندرويد/آيفون» أو «متصفّح · نظام»)؛ بلا وصف ← عامّ.
  IconData _icon(AccountDevice d) {
    final label = d.label ?? '';
    if (RegExp('تطبيق|أندرويد|آيفون').hasMatch(label)) return Icons.smartphone_rounded;
    if (label.isNotEmpty) return Icons.computer_rounded;
    return Icons.devices_other_rounded;
  }

  Future<void> _remove(AccountDevice d) async {
    if (_removing != null) return;
    HapticFeedback.mediumImpact();
    final ok = await showConfirmSheet(
      context,
      title: 'account.devices_remove_title'.tr(),
      message: 'account.devices_remove_body'.tr(args: [iso(_name(d))]),
      confirmLabel: 'account.devices_remove'.tr(),
      icon: Icons.phonelink_erase_rounded,
      tone: AppTone.danger,
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = d.deviceId);
    try {
      final list = await AccountApi.removeDevice(d.deviceId);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        final data = _data;
        if (data != null) {
          _data = data.withDevices(list ?? data.devices.where((x) => x.deviceId != d.deviceId).toList());
        }
        _removing = null;
        _removedAny = true;
      });
      widget.onRemoved?.call();
      showAccountSnack(context, 'account.devices_removed'.tr());
      if (list == null) await _load(); // الخادم لم يُرسل القائمة ← نتأكّد منه
    } on AccountApiException catch (e) {
      if (!mounted) return;
      setState(() => _removing = null);
      HapticFeedback.heavyImpact();
      showAccountSnack(context, accountText(e.message), error: true);
    } catch (e) {
      if (kDebugMode) debugPrint('🔴 remove device: $e');
      if (!mounted) return;
      setState(() => _removing = null);
      showAccountSnack(context, accountText('account.devices_err_remove'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final data = _data;
    final sub = widget.me?.subscription;
    final used = data?.devices.length ?? sub?.devicesUsed;
    final max = data?.maxDevices ?? sub?.maxDevices;
    return AccountScaffold(
      title: 'account.devices_title'.tr(),
      subtitle: 'account.devices_subtitle'.tr(),
      onBack: () => Navigator.of(context).maybePop(),
      showLogo: false,
      onRefresh: _load,
      children: [
        if (used != null) ...[
          _UsageCard(used: used, max: max),
          const SizedBox(height: Sp.lg),
        ],
        if (data != null) ..._status(data, max),
        ..._body(data, max),
      ],
    );
  }

  /// لافتة الحال فوق القائمة: الحدّ ممتلئ، أو — من ورقة الحدّ — صار فيه مكان.
  List<Widget> _status(AccountDevices data, int? max) {
    if (max != null && data.devices.length >= max) {
      return [
        _Banner(
          icon: Icons.warning_amber_rounded,
          tone: AppTone.warning,
          // هذا الجهاز خارج القائمة = هو المرفوض؛ وداخلها = لا جديد يدخل.
          text: (data.hasCurrent ? 'account.devices_full_current' : 'account.devices_full').tr(),
        ),
        const SizedBox(height: Sp.lg),
      ];
    }
    // حدٌّ مجهول (خادمٌ أقدم) ← المكان مؤكَّد بعد إزالةٍ فقط.
    if (widget.fromLimit && (max != null || _removedAny)) {
      return [
        _Banner(icon: Icons.check_circle_rounded, tone: AppTone.success, text: 'account.devices_room'.tr()),
        const SizedBox(height: Sp.md),
        AccountPrimaryButton(
          label: 'account.devices_retry_login'.tr(),
          icon: Icons.login_rounded,
          onTap: _removing == null ? () => Navigator.of(context).pop(true) : null,
        ),
        const SizedBox(height: Sp.lg),
      ];
    }
    return const [];
  }

  List<Widget> _body(AccountDevices? data, int? max) {
    if (data == null) {
      final error = _error;
      if (error != null) {
        return [
          AccountCard(
            child: Column(children: [
              // سحابةٌ لا «واي فاي»: الخطأ قد يكون من الخادم والإنترنت سليم.
              Icon(Icons.cloud_off_rounded, color: AppColors.textLow, size: 32),
              const SizedBox(height: Sp.sm),
              Text(accountText(error), textAlign: TextAlign.center, style: AppType.body(color: AppColors.textBody)),
              const SizedBox(height: Sp.md),
              AccountOutlineButton(label: 'common.retry'.tr(), onTap: _load),
            ]),
          ),
        ];
      }
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Center(child: CircularProgressIndicator(color: AppColors.brand, strokeWidth: 2.4)),
        ),
      ];
    }
    if (data.devices.isEmpty) {
      return [
        AccountCard(
          child: Column(children: [
            Icon(Icons.devices_other_rounded, color: AppColors.brand, size: 36),
            const SizedBox(height: Sp.md),
            Text('account.devices_empty'.tr(),
                textAlign: TextAlign.center, style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.xs),
            Text('account.devices_empty_body'.tr(),
                textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid).copyWith(height: 1.55)),
          ]),
        ),
      ];
    }
    // هذا الجهاز أوّلاً، والباقي بترتيب الخادم (الأحدث نشاطاً).
    final list = [
      ...data.devices.where(data.isCurrent),
      ...data.devices.where((d) => !data.isCurrent(d)),
    ];
    final full = max != null && data.devices.length >= max;
    return [
      for (final d in list) ...[
        _DeviceTile(
          name: _name(d),
          icon: data.isCurrent(d) ? Icons.smartphone_rounded : _icon(d),
          current: data.isCurrent(d),
          lastSeen: 'account.devices_last_seen'.tr(args: [_ago(d.lastSeenAt)]),
          firstSeen: 'account.devices_first_seen'.tr(args: [_ago(d.createdAt)]),
          busy: _removing == d.deviceId,
          onRemove: _removing == null ? () => _remove(d) : null,
        ),
        const SizedBox(height: Sp.md),
      ],
      // لافتة الامتلاء تقول ذلك أصلاً حين يكون هذا الجهاز هو المرفوض.
      if (!data.hasCurrent && !full)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
          child: Text('account.devices_current_missing'.tr(),
              textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.5)),
        ),
    ];
  }
}

/// «منذ كذا» بلغة الواجهة — بعتبات `timeAgoAr` نفسها (`server_time.dart`).
/// لا سالب أبداً: فارق ساعةٍ بين الخادم والجهاز يُقرأ «الآن».
String _ago(DateTime? at) {
  if (at == null) return '—';
  final d = DateTime.now().difference(at);
  if (d.isNegative || d.inMinutes < 1) return 'account.ago_now'.tr();
  if (d.inMinutes < 60) return 'account.ago_minutes'.tr(args: ['${d.inMinutes}']);
  if (d.inHours < 24) return 'account.ago_hours'.tr(args: ['${d.inHours}']);
  if (d.inDays < 30) return 'account.ago_days'.tr(args: ['${d.inDays}']);
  if (d.inDays < 365) return 'account.ago_months'.tr(args: ['${d.inDays ~/ 30}']);
  return 'account.ago_years'.tr(args: ['${d.inDays ~/ 365}']);
}

/// العدّاد «٢ من ٣» وخانات الحدّ وسطر شرحه.
class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.used, required this.max});
  final int used;
  final int? max;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final max = this.max;
    final full = max != null && used >= max;
    final tone = full ? AppColors.warning : AppColors.brand;
    return AccountCard(
      padding: const EdgeInsets.all(Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: full ? AppColors.warningSoftBg : AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(Icons.devices_rounded, color: tone, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('account.devices_used'.tr(),
                        style: AppType.label(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Sp.xxs),
                    Text(
                      max == null ? iso('$used') : 'account.devices_count'.tr(args: [iso('$used'), iso('$max')]),
                      style: AppType.statValue(color: AppColors.textHi),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (max != null) ...[
            const SizedBox(height: Sp.md),
            ExcludeSemantics(child: _Slots(used: used, max: max, color: tone)),
            const SizedBox(height: Sp.md),
            // آيفون: «حدّ حسابك» لا «حدّ باقتك» — لا ذكر لباقةٍ تُشترى.
            Text(
                (StorePolicy.hidePurchaseFlows ? 'account.devices_note_neutral' : 'account.devices_note')
                    .tr(args: [iso('$max')]),
                style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.5)),
          ],
        ],
      ),
    );
  }
}

/// خانةٌ لكلّ جهازٍ في الحدّ، المشغول منها ملوّن — من بداية الاتجاه.
class _Slots extends StatelessWidget {
  const _Slots({required this.used, required this.max, required this.color});
  final int used;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // حدٌّ كبير (باقة شركاتٍ كثيرة) ← شريطٌ واحد بدل خاناتٍ لا تُقرأ.
    if (max > 12) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(R.pill),
        child: LinearProgressIndicator(
          value: (used / max).clamp(0.0, 1.0),
          minHeight: 6,
          color: color,
          backgroundColor: AppColors.border,
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < max; i++) ...[
          if (i > 0) const SizedBox(width: Sp.xs),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < used ? color : AppColors.border,
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.tone, required this.text});
  final IconData icon;
  final AppTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone == AppTone.warning ? AppColors.warning : AppColors.success, size: 20),
          const SizedBox(width: Sp.md),
          Expanded(child: Text(text, style: AppType.bodyStrong(color: tone.onSoft).copyWith(height: 1.5))),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.name,
    required this.icon,
    required this.current,
    required this.lastSeen,
    required this.firstSeen,
    required this.busy,
    required this.onRemove,
  });

  final String name;

  /// أيقونة النوع (موبايل/كمبيوتر/عامّ) — من وصف الخادم.
  final IconData icon;

  /// هذا الجهاز — يُميَّز ولا زرّ إزالةٍ له: لا يُزال من نفسه (يعود فيُسجَّل
  /// مع أوّل دخولٍ أو تجديد توكن، فالإزالة لا تحرّر شيئاً).
  final bool current;
  final String lastSeen;
  final String firstSeen;
  final bool busy;

  /// null ← معطّل أثناء إزالة جهازٍ آخر.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: current ? AppColors.brandSoftBorder : AppColors.surface),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(Sp.lg, Sp.lg, current ? Sp.lg : Sp.xs, Sp.lg),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: current ? AppColors.brandSoftBg : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(
              icon,
              color: current ? AppColors.brand : AppColors.textMid,
              size: 22,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الحبّة تنزل سطراً حين يضيق الاسم عنها (٣٢٠ نقطة وتكبير الخطّ).
                Wrap(
                  spacing: Sp.sm,
                  runSpacing: Sp.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name,
                        style: AppType.listName(color: AppColors.textHi), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (current)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xxs),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoftBg,
                          borderRadius: BorderRadius.circular(R.pill),
                        ),
                        // `brandOnSoft` لا `brand`: الأخضر الداكن على خلفيّته
                        // الخفيفة ليلاً يهبط تحت ٤٫٥:١.
                        child: Text('account.devices_this'.tr(), style: AppType.pillBold(color: AppColors.brandOnSoft)),
                      ),
                  ],
                ),
                const SizedBox(height: Sp.xxs),
                // سطران لا سطر: «آخر نشاط» هو ما يميّز الأجهزة بعضها عن بعض (الأسماء
                // «جهاز» + معرّف)، وكان يُقصّ «آخر نشاط: منذ 23 …» على ٣٢٠ نقطة وتكبير ١٫٣.
                Text(lastSeen,
                    style: AppType.body(color: AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(firstSeen,
                    style: AppType.muted(color: AppColors.textLow), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (!current) ...[
            const SizedBox(width: Sp.xs),
            SizedBox(
              width: 48,
              height: 48,
              child: busy
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.brand),
                      ),
                    )
                  : IconButton(
                      onPressed: onRemove,
                      tooltip: 'account.devices_remove_hint'.tr(),
                      icon: Icon(Icons.delete_outline_rounded,
                          color: onRemove == null ? AppColors.textLow : AppColors.error),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────── «بلغت حدّ الأجهزة» ─────────────

/// يُعرض حين يرفض الخادم دخول شركةٍ من جهازٍ جديد فوق حدّ الباقة
/// (`LoginFailure.isDeviceLimit`). «إدارة أجهزتي» تفتح [MyDevicesScreen]؛ ومتى
/// تحرّر مكانٌ يُرجع `true` فيُعيد المستدعي **الدخول نفسه** فوراً — والخادم
/// يقبله الآن (الإزالة فوريّة).
///
/// [message] رسالة الخادم — منها حدّ الباقة إن ذكرته («… (3) — …»).
Future<bool> showDeviceLimitSheet(BuildContext context, {String? message}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _DeviceLimitSheet(limit: _limitFrom(message)),
  );
  return r == true;
}

/// الحدّ من رسالة الخادم «بلغت حدّ الأجهزة (3) — …»، أو null.
int? _limitFrom(String? message) {
  final m = RegExp(r'\((\d{1,3})\)').firstMatch(message ?? '');
  return m == null ? null : int.tryParse(m.group(1)!);
}

class _DeviceLimitSheet extends StatefulWidget {
  const _DeviceLimitSheet({this.limit});
  final int? limit;

  @override
  State<_DeviceLimitSheet> createState() => _DeviceLimitSheetState();
}

class _DeviceLimitSheetState extends State<_DeviceLimitSheet> {
  /// أُزيل جهازٌ ثمّ رجع المستخدم بلا «إعادة محاولة الدخول» (السهم/السحب) —
  /// الورقة تقول إنّ المكان تحرّر وزرّها يصير «إعادة المحاولة».
  bool _freed = false;

  Future<void> _manage() async {
    HapticFeedback.selectionClick();
    var removed = false;
    final retry = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => MyDevicesScreen(fromLimit: true, onRemoved: () => removed = true),
    ));
    if (!mounted) return;
    if (retry == true) {
      Navigator.of(context).pop(true);
    } else if (removed) {
      setState(() => _freed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final limit = widget.limit;
    // آيفون: بلا «رقِّ باقتك» ولا «حدّ باقتك» — إزالة جهازٍ هي المخرج الوحيد المعروض.
    final neutral = StorePolicy.hidePurchaseFlows;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: _freed ? Icons.check_circle_outline_rounded : Icons.devices_other_rounded,
        title: (_freed ? 'account.limit_freed_title' : 'account.limit_title').tr(),
        subtitle: _freed || limit == null
            ? ''
            : (neutral ? 'account.limit_subtitle_neutral' : 'account.limit_subtitle').tr(args: [iso('$limit')]),
        tint: _freed ? AppColors.success : AppColors.warning,
        tintBg: _freed ? AppColors.successSoftBg : AppColors.warningSoftBg,
        onClose: () => Navigator.of(context).pop(false),
      ),
      body: Text(
        (_freed
                ? 'account.limit_freed_body'
                : neutral
                    ? 'account.limit_body_neutral'
                    : 'account.limit_body')
            .tr(),
        style: AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
      ),
      footer: SheetFooterBar(
        label: (_freed ? 'common.retry' : 'account.limit_manage').tr(),
        icon: _freed ? Icons.refresh_rounded : Icons.devices_rounded,
        onPressed: _freed ? () => Navigator.of(context).pop(true) : _manage,
      ),
    );
  }
}
