import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';

import '../api/account_api.dart';
import '../core/platform/store_policy.dart';
import '../core/util/bidi.dart';
import '../core/widgets/explain_action.dart';
import '../services/ai_assistant_state.dart';
import '../widgets/sas_captcha_sheet.dart';
import '../api/auth_api.dart';
import '../services/account_service.dart';
import '../services/app_version.dart';
import '../services/auth_storage.dart';
import '../services/company_creds_store.dart';
import '../services/saved_profiles_store.dart';
import '../services/sas_login_flow.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'account/account_gate_screen.dart';
import 'account/my_devices_screen.dart';
import 'main_shell.dart';
import '../core/platform/app_platform.dart';

/// Login — Soft Pastel + Premium. Wired to https://rad.mysvcs.net/api/auth/login.
/// Persists token on success via AuthStorage. On failure shows a snackbar.
///
/// Layout note: previous version used ConstrainedBox + Spacer + animations,
/// which tripped Flutter's semantics assertions during animation frames
/// (`!semantics.parentDataDirty`). Replaced with a flat Column inside
/// SingleChildScrollView — no Spacer, no min-height tricks.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialSasUrl,
    this.initialUsername,
    this.initialCompanyLabel,
    this.initialSasCode,
    this.fromCompanies = false,
  });

  /// Pro البند ٤ ③: تُفتح من «شركاتي» — لإضافة شركة، أو لدخول شركةٍ
  /// مربوطة كلمةُ سرّها غير محفوظة (الرابط واليوزر معبّآن).
  final String? initialSasUrl;
  final String? initialUsername;

  /// اسم الشركة المربوطة وكودها (من «شركاتي») — يُعرض في بطاقة الشركة بدل
  /// رابطها، ويُنسب للجلسة (شريط الشركة بعد الدخول).
  final String? initialCompanyLabel;
  final String? initialSasCode;
  final bool fromCompanies;

  /// منفذا الاختبار وحده: مصدرا اسم الشركة (دليل الشركات، والشركات المربوطة
  /// بالحساب). `AccountApi` يمرّ بحساب Firebase وبالشبكة، ولا يعمل أيٌّ منهما
  /// في `flutter test`.
  @visibleForTesting
  static Future<List<DirectoryCompany>> Function() directorySource =
      AccountApi.sasDirectory;
  @visibleForTesting
  static Future<List<LinkedCompany>> Function() linkedSource =
      AccountApi.companies;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _sasCtrl = TextEditingController(); // Pro: رابط صفحة شركة SAS (اختياريّ)
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  // Default ON — matches v1 behavior. Users who don't want auto-login
  // on a shared device can untick before submitting.
  bool _remember = true;

  // Pro البند ٤ ③: «إضافة شركة» ← اختيار من دليل الشركات (يضبطه المالك)، وفي
  // الآخر «شركة أخرى» برابطٍ يدويّ. دخول شركةٍ معروفة (مربوطة) ← بطاقةٌ باسمها.
  bool get _pickerMode => widget.fromCompanies && (widget.initialSasUrl ?? '').isEmpty;
  List<DirectoryCompany>? _directory;
  DirectoryCompany? _picked;
  bool _manualLink = false;
  String? _pendingUrl; // حسابٌ محفوظ اختير قبل وصول الدليل

  // الشركة المعروفة خارج «إضافة شركة» (مربوطةٌ من «شركاتي»، أو شركة حسابٍ
  // محفوظ) تُعرض **باسمها** في بطاقةٍ للقراءة فقط بدل حقل الرابط؛ والرابط يبقى
  // مخفيّاً في [_sasCtrl] فيجري الدخول كما كان. مضيفٌ فارغ ← لا شركة معروفة ← الحقل.
  String _fixedHost = '';
  String? _fixedName; // null ← لا اسم (بعدُ): المضيف وحده بخطٍّ خافت
  String? _fixedCode;
  int _nameSeq = 0; // حسمٌ يصل بعد تبديل الشركة لا يُكتب على غيرها

  /// يثبّت الشركة المعروفة ويحسم اسمها بلا حجبٍ للنموذج: أفضل اسمٍ معروف
  /// يُعرض فوراً، والأدقّ يحلّ محلّه حين يصل. الترتيب: اسمها من «شركاتي» ←
  /// دليل الشركات (بالمضيف) ← الشركات المربوطة بالحساب ← وإلّا المضيف وحده.
  void _fixCompany(String url) {
    _sasCtrl.text = url;
    final host = CompanyCredsStore.hostOf(url);
    if (host.isEmpty) {
      // رابطٌ بلا مضيف — لا شركة تُسمّى ← الحقل نفسه قابلاً للتعديل، فلا تبقى
      // بطاقةٌ باسم شركةٍ غير التي يُرسَل رابطها.
      _fixedName = _fixedCode = null;
      _fixedHost = '';
      _nameSeq++;
      return;
    }
    if (host == _fixedHost) return; // الشركة نفسها: اسمها (أو حسمه الجاري) باقٍ
    _fixedHost = host;
    final seq = ++_nameSeq;
    final initUrl = widget.initialSasUrl ?? '';
    final linked = initUrl.isNotEmpty && CompanyCredsStore.hostOf(initUrl) == host;
    final label = widget.initialCompanyLabel?.trim() ?? '';
    _fixedName = linked ? _realName(label) : null;
    _fixedCode = linked ? widget.initialSasCode : null;
    if (_fixedName != null) return;
    // اسمٌ من «شركاتي» لكنّه مضيف ← هي لا تعرف غيره، فلا تُسأل ثانيةً.
    _resolveName(seq, host, askLinked: !(linked && label.isNotEmpty));
  }

  /// اسمٌ يصلح للعرض — لا فارغ، ولا مضيفٌ أو رابطٌ متنكّرٌ في اسم: «شركاتي»
  /// تُرجع المضيف اسماً لشركةٍ ليست في الدليل.
  static String? _realName(String? s) {
    final t = s?.trim() ?? '';
    if (t.isEmpty || t.contains('://') || _hostLike.hasMatch(t)) return null;
    return t;
  }

  static final _hostLike = RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?$');

  Future<void> _resolveName(int seq, String host, {required bool askLinked}) async {
    bool stale() => !mounted || seq != _nameSeq;
    // الاسم وحده يُحسم هنا؛ الكود المعروف (كود «شركاتي» الذي رُبط به الحساب)
    // لا يُستبدل بكود صفٍّ آخر يشاركه المضيف — يُكمَّل فقط إن جُهل.
    void apply(String name, String code) => setState(() {
          _fixedName = name;
          if (code.isNotEmpty && (_fixedCode ?? '').isEmpty) _fixedCode = code;
        });
    try {
      final dir = await LoginScreen.directorySource();
      if (stale()) return;
      for (final c in dir) {
        final name = c.name.trim();
        if (name.isNotEmpty && CompanyCredsStore.hostOf(c.url) == host) {
          apply(name, c.code);
          return;
        }
      }
    } catch (_) {
      // لا دليل (شبكة/حساب) ← الخطوة التالية.
    }
    if (!askLinked || stale()) return;
    try {
      final linked = await LoginScreen.linkedSource();
      if (stale()) return;
      for (final c in linked) {
        final name = _realName(c.label);
        if (name != null && CompanyCredsStore.hostOf(c.sasUrl ?? '') == host) {
          apply(name, c.sasCode);
          return;
        }
      }
    } catch (_) {
      // يبقى المضيف — الاحتياط الأخير.
    }
  }

  /// يختار الشركة من رابطها: من الدليل إن وُجدت، وإلّا «شركة أخرى» بالرابط.
  /// وخارج «إضافة شركة» تُثبَّت باسمها في بطاقة الشركة ([_fixCompany]).
  void _selectCompanyUrl(String url) {
    if (!_pickerMode) {
      _fixCompany(url);
      return;
    }
    _sasCtrl.text = url;
    final dir = _directory;
    if (dir == null) {
      _pendingUrl = url;
      return;
    }
    final host = CompanyCredsStore.hostOf(url);
    final hit = dir.where((c) => CompanyCredsStore.hostOf(c.url) == host).firstOrNull;
    _picked = hit;
    _manualLink = hit == null;
    if (hit != null) _sasCtrl.text = hit.url;
  }

  Future<void> _loadDirectory() async {
    try {
      final list = await LoginScreen.directorySource();
      if (!mounted) return;
      setState(() {
        _directory = list;
        if (list.isEmpty) _manualLink = true; // لا دليل ← الحقل اليدويّ مباشرةً
        final pending = _pendingUrl;
        _pendingUrl = null;
        if (pending != null) _selectCompanyUrl(pending);
      });
    } catch (_) {
      if (mounted) setState(() { _directory = const []; _manualLink = true; });
    }
  }

  Future<void> _openPicker() async {
    HapticFeedback.selectionClick();
    final items = _directory ?? const <DirectoryCompany>[];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceSheet,
      barrierColor: AppColors.scrim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheet))),
      builder: (ctx) => _CompanyPickerSheet(items: items, selected: _picked),
    );
    if (!mounted || choice == null) return;
    setState(() {
      if (choice is DirectoryCompany) {
        _picked = choice;
        _manualLink = false;
        _sasCtrl.text = choice.url;
      } else {
        _picked = null;
        _manualLink = true;
        _sasCtrl.clear();
      }
    });
    if (_userCtrl.text.isEmpty) _userFocus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _sasCtrl.text = widget.initialSasUrl ?? '';
    _userCtrl.text = widget.initialUsername ?? '';
    if (_pickerMode) {
      _loadDirectory();
    } else if ((widget.initialSasUrl ?? '').isNotEmpty) {
      _fixCompany(widget.initialSasUrl!); // شركةٌ معروفة ← باسمها لا برابطها
    }
    // توكن الحساب يُجدَّد الآن بينما يكتب المستخدم — لا عند الضغط على «دخول».
    AccountService.idToken();
    if (_userCtrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _sasCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool error = false, Duration? duration}) {
    if (!mounted) return;
    // آيفون: رسالة الخادم بلا «فعّل كوداً»/«رقِّ باقتك» (حدّ الشركات، انتهاء الاشتراك).
    msg = StorePolicy.storeSafe(msg);
    // «اشرحلي» على رفض الخادم (حدّ الشركات/الأجهزة، الاشتراك، رمز الصورة…) —
    // يظهر حين يقول الخادم إنّ المساعد مفتوح، بتوكن الحساب (لا جلسة شركة بعد).
    final ask = error ? AiAssistantState.explainFor(msg) : null;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: ExplainSnackContent(
          message: msg,
          style: AppType.button(color: AppColors.onBrand),
          request: ask,
          onExplain: () {
            messenger.hideCurrentSnackBar();
            if (ask != null && mounted) openExplain(context, ask);
          },
        ),
        backgroundColor: error ? AppColors.error : AppColors.brand,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
        ),
        margin: const EdgeInsets.all(Sp.lg),
        duration: explainSnackDuration(duration ?? const Duration(seconds: 3), ask),
      ),
    );
  }

  /// الشركة المعروفة لهذا الدخول (من الدليل أو «شركاتي») — لشريط الشركة أعلى
  /// الواجهة. لا تُنسب إلّا إن طابق الرابطُ المرسَل رابطَها: الحقل قابلٌ
  /// للتعديل، واسمٌ خاطئ أسوأ من لا اسم (يُحسم حينها من «شركاتي»).
  ({String? label, String? code}) _knownCompany(String sasUrl) {
    final host = CompanyCredsStore.hostOf(sasUrl);
    final p = _picked;
    if (p != null && CompanyCredsStore.hostOf(p.url) == host) {
      return (label: p.name, code: p.code);
    }
    // اسم بطاقة الشركة كما حُسم (من «شركاتي» أو الدليل أو الشركات المربوطة).
    final name = _fixedName;
    if (name != null && host.isNotEmpty && host == _fixedHost) {
      return (label: name, code: _fixedCode);
    }
    final initUrl = widget.initialSasUrl ?? '';
    if ((widget.initialCompanyLabel ?? '').isNotEmpty &&
        initUrl.isNotEmpty &&
        CompanyCredsStore.hostOf(initUrl) == host) {
      return (label: widget.initialCompanyLabel, code: widget.initialSasCode);
    }
    return (label: null, code: null);
  }

  Future<void> _onLogin() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (_pickerMode && _picked == null && _sasCtrl.text.trim().isEmpty) {
      _showSnack('login.pick_company_first'.tr(), error: true);
      return;
    }
    if (user.isEmpty || pass.isEmpty) {
      _showSnack('login.enter_credentials'.tr(), error: true);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    // الدوّارة باقيةٌ حتى يكتمل **الحفظ** لا الطلب وحده — كانت تتوقّف بعد ردّ الخادم فيبدو الزرّ بلا جوابٍ
    // أثناء الحفظ (أو بعد فشله الصامت)، فيضغطه المدير مراراً (بلاغ ٢٠٢٦-١٠-١٥).
    try {
      // ساسٌ يطلب رمز صورة (الحياة عمارة…) ← نافذة الرمز ثمّ الدخول بها. ومالكٌ فعّل التحقّق
      // بخطوتين ← نافذة الكود؛ فما يصل هنا جلسةٌ كاملة أو فشل.
      final result = await SasCaptchaLogin.login(context, username: user, password: pass, sasUrl: _sasCtrl.text);
      if (!mounted) return;

      switch (result) {
        case LoginSuccess():
          // Pro البند ٤ ③: ما بعد الدخول في مكانٍ واحد (مع «شركاتي»): مسح بقايا
          // الجلسة السابقة ← حفظ الجلسة ورابط ساسها ← كلمة السرّ على الجهاز لهذه
          // الشركة ← الصلاحيّات ← FCM.
          final sasUrl = _sasCtrl.text.trim();
          final company = _knownCompany(sasUrl);
          final out = await SasLoginFlow.completeSafely(
            result,
            username: user,
            password: pass,
            sasUrl: sasUrl,
            remember: _remember,
            companyLabel: company.label,
            sasCode: company.code,
          );
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          if (out == SasLoginOutcome.permsFailed) {
            _showSnack('login.perms_fetch_failed'.tr(), error: true);
            return;
          }
          if (out == SasLoginOutcome.storageFailed) {
            _showSnack(
              (Platform.isAndroid ? 'login.save_failed_android' : 'login.save_failed').tr(),
              error: true,
              duration: const Duration(seconds: 9),
            );
            return;
          }
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()),
            (_) => false,
          );
        case final LoginFailure f:
          if (f.isCancelled) return; // أغلق نافذة رمز الصورة أو كود التحقّق — لا رسالة
          HapticFeedback.heavyImpact();
          // حدّ الأجهزة — قبل البوّابة: كان رسالةً تحيل إلى «أجهزتي» غير موجودة
          // ثمّ ارتداداً للبوّابة. الآن «أجهزتي» تحرّر مكاناً ويُعاد الدخول فوراً.
          if (f.isDeviceLimit) {
            if (await showDeviceLimitSheet(context, message: f.message) && mounted) await _onLogin();
            return;
          }
          // رفضٌ من الساس: نذكّر بالشركة المختارة — أكثر سببٍ له يوزر شركةٍ على ساس أخرى.
          final company = _picked?.name;
          _showSnack(
            f.rejected && company != null ? '${f.message}\n${'login.check_company'.tr(args: [company])}' : f.message,
            error: true,
          );
          // بوّابة الحساب (اشتراكٌ منتهٍ/حسابٌ معطّل/بلا حساب): البوّابة تقرّر.
          if (f.isAccountGate) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AccountGateScreen()),
              (_) => false,
            );
          }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onBiometric() async {
    HapticFeedback.selectionClick();
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) {
      _showSnack('login.password_login_first'.tr(), error: true);
      return;
    }
    final auth = LocalAuthentication();
    try {
      final ok = await auth.authenticate(
        localizedReason: 'login.biometric_reason'.tr(),
        options: AuthenticationOptions(
          biometricOnly: !AppPlatform.isDesktop,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (ok) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('login.biometric_unavailable'.tr(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      // resizeToAvoidBottomInset lets the layout shift up when the keyboard
      // appears — without ConstrainedBox/Spacer fighting the new constraints.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.xxl,
            vertical: Sp.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.fromCompanies)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, color: AppColors.textHi),
                  ),
                ),
              SizedBox(height: widget.fromCompanies ? Sp.md : Sp.huge),
              const _Logo()
                  .animate()
                  .scale(
                    begin: const Offset(0.7, 0.7),
                    end: const Offset(1, 1),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: const Duration(milliseconds: 350)),
              const SizedBox(height: Sp.xl),
              const _BrandTitle()
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 200),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: Sp.lg),
              // 2026-08-26: chips للحسابات المحفوظة — تُملأ الفورم بضغطة،
              // long-press لحذف حساب. تُخفى لو لا يوجد محفوظات.
              _ProfileChips(
                onPick: (p) async {
                  try {
                    final plain =
                        await SavedProfilesStore.decrypt(p.encryptedPassword);
                    // Pro: وشركته معه — كان يملأ اليوزر وتبقى الشركة المختارة سابقاً.
                    final url = await CompanyCredsStore.sasUrlFor(p.username);
                    if (!mounted) return;
                    setState(() {
                      _userCtrl.text = p.username;
                      _passCtrl.text = plain;
                      if (url != null) _selectCompanyUrl(url);
                    });
                    _passFocus.requestFocus();
                  } catch (_) {
                    _showSnack('تعذّر قراءة الحساب المحفوظ', error: true);
                  }
                },
                onRemoved: () {
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: Sp.md),
              _FormCard(
                companyField: _pickerMode
                    ? _CompanyField(
                        loading: _directory == null,
                        picked: _picked,
                        manual: _manualLink,
                        sasCtrl: _sasCtrl,
                        onTap: _directory == null ? null : _openPicker,
                      )
                    : _fixedHost.isNotEmpty
                        ? _KnownCompanyTile(name: _fixedName, host: _fixedHost)
                        : null,
                sasCtrl: _sasCtrl,
                userCtrl: _userCtrl,
                passCtrl: _passCtrl,
                userFocus: _userFocus,
                passFocus: _passFocus,
                obscure: _obscure,
                loading: _loading,
                remember: _remember,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onToggleRemember: () => setState(() => _remember = !_remember),
                onLogin: _loading ? null : _onLogin,
              )
                  .animate()
                  .fadeIn(
                    delay: const Duration(milliseconds: 320),
                    duration: const Duration(milliseconds: 350),
                  )
                  .slideY(begin: 0.06, end: 0),
              const SizedBox(height: Sp.lg),
              _BiometricButton(onTap: _onBiometric).animate().fadeIn(
                    delay: const Duration(milliseconds: 450),
                    duration: const Duration(milliseconds: 350),
                  ),
              const SizedBox(height: Sp.huge),
              const _Footer(),
              const SizedBox(height: Sp.lg),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2026-08-26: صفّ chips للحسابات المحفوظة على شاشة الدخول.
/// - يُخفى تلقائياً لو لا محفوظات (SizedBox.shrink).
/// - Tap: يعبّئ الفورم بيوزر+باسورد الحساب.
/// - Long-press: يحذف الحساب من الذاكرة الدائمة.
class _ProfileChips extends StatefulWidget {
  const _ProfileChips({required this.onPick, required this.onRemoved});
  final void Function(SavedProfile p) onPick;
  final VoidCallback onRemoved;

  @override
  State<_ProfileChips> createState() => _ProfileChipsState();
}

class _ProfileChipsState extends State<_ProfileChips> {
  late Future<List<SavedProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = SavedProfilesStore.list();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = SavedProfilesStore.list();
    });
  }

  Future<void> _confirmRemove(SavedProfile p) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب المحفوظ'),
        content: Text(
            'حذف "${p.displayName.isEmpty ? p.username : p.displayName}" من قائمة الحسابات المحفوظة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await SavedProfilesStore.remove(p.username);
      if (!mounted) return;
      await _refresh();
      widget.onRemoved();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return FutureBuilder<List<SavedProfile>>(
      future: _future,
      builder: (_, snap) {
        final items = snap.data ?? const <SavedProfile>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.xs),
              child: Text(
                'الحسابات المحفوظة',
                style: AppType.muted().copyWith(fontSize: 11),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: Sp.sm),
                itemBuilder: (_, i) {
                  final p = items[i];
                  final label =
                      p.displayName.isEmpty ? p.username : p.displayName;
                  return GestureDetector(
                    onLongPress: () => _confirmRemove(p),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.xl),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onPick(p);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoftBg,
                          borderRadius: BorderRadius.circular(R.xl),
                          border: Border.all(
                            color: AppColors.brandSoftBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_outline,
                                size: 15, color: AppColors.brand),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(
                                label,
                                style: AppType.button(color: AppColors.brand)
                                    .copyWith(fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // Tint the logo brand-green using BlendMode.modulate via ColorFilter.
    // The logo is violet shapes on a transparent/white background.
    // We render it inside a ShaderMask that:
    //   1. Takes the alpha mask from the image (the violet shapes only).
    //   2. Fills the masked area with brand green.
    // White/transparent areas of the source stay transparent (white card
    // shows through), violet shapes get re-colored to brand.
    return Center(
      child: Container(
        width: 130,
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandSoftBg,
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        padding: const EdgeInsets.all(Sp.md),
        // The PNG itself is now pre-tinted brand-green with the white
        // background converted to transparent (recolor_logo.js, 2026-06-02).
        // No runtime tinting needed — what you see is what's in the asset.
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          // 2026-08-28: cache thumbnail (~200KB بدل ~4MB في imageCache).
          cacheWidth: 320,
        ),
      ),
    );
  }
}

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      children: [
        Text(
          'MyServices Pro',
          textAlign: TextAlign.center,
          style: AppType.title(color: AppColors.textHi),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'login.subtitle'.tr(),
          textAlign: TextAlign.center,
          style: AppType.subtitle(color: AppColors.textMid),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({
    this.companyField,
    required this.sasCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.userFocus,
    required this.passFocus,
    required this.obscure,
    required this.loading,
    required this.remember,
    required this.onToggleObscure,
    required this.onToggleRemember,
    required this.onLogin,
  });

  /// Pro: حقل الشركة البديل (اختيارٌ من الدليل، أو بطاقة الشركة المعروفة
  /// باسمها) — null = حقل الرابط الاختياريّ (لا شركة معروفة).
  final Widget? companyField;
  final TextEditingController sasCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final FocusNode userFocus;
  final FocusNode passFocus;
  final bool obscure;
  final bool loading;
  final bool remember;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleRemember;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.xl),
      ),
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pro: رابط صفحة شركة SAS. اختياريّ — فارغٌ = الحساب المعتاد.
          if (companyField != null) companyField! else _LabeledInput(
            label: 'login.company'.tr(),
            child: TextField(
              controller: sasCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: AppType.input(color: AppColors.textHi),
              decoration: _decoration(hint: 'login.company_hint'.tr()),
            ),
          ),
          const SizedBox(height: Sp.lg),
          _LabeledInput(
            label: 'login.username'.tr(),
            child: TextField(
              controller: userCtrl,
              focusNode: userFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passFocus.requestFocus(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _decoration(hint: 'login.username_hint'.tr()),
            ),
          ),
          const SizedBox(height: Sp.lg),
          _LabeledInput(
            label: 'login.password'.tr(),
            child: TextField(
              controller: passCtrl,
              focusNode: passFocus,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onLogin?.call(),
              style: AppType.input(color: AppColors.textHi),
              decoration: _decoration(
                hint: '••••••',
                suffix: IconButton(
                  splashRadius: 18,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textMid,
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          // Forgot-password link removed per user request — admins
          // who lose their password are reset by their parent admin, no
          // public reset flow exists. Toggle stays aligned to RTL start.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _RememberToggle(
              value: remember,
              onChanged: onToggleRemember,
            ),
          ),
          const SizedBox(height: Sp.lg),
          _PrimaryButton(
            label: 'login.sign_in'.tr(),
            loading: loading,
            onTap: onLogin,
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration({required String hint, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppType.input(color: AppColors.textLow),
      filled: true,
      fillColor: AppColors.surfaceInput,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Sp.lg,
        vertical: Sp.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: AppColors.brand, width: 1.5),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: Sp.xs, bottom: Sp.sm),
          child: Text(label, style: AppType.label(color: AppColors.textMid)),
        ),
        child,
      ],
    );
  }
}

class _RememberToggle extends StatelessWidget {
  const _RememberToggle({required this.value, required this.onChanged});

  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onChanged,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.sm,
            vertical: Sp.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom check box — Material's Checkbox is too noisy here.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? AppColors.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(
                    color: value ? AppColors.brand : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.onBrand, size: 14)
                    : null,
              ),
              const SizedBox(width: Sp.sm),
              Text('login.remember_me'.tr(),
                  style: AppType.link(color: AppColors.textHi)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      height: 54,
      child: Material(
        color: onTap == null ? AppColors.borderStrong : AppColors.brand,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.onBrand,
                    ),
                  )
                : Text(label, style: AppType.button(color: AppColors.onBrand)),
          ),
        ),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  const _BiometricButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fingerprint_rounded, color: AppColors.brand, size: 22),
              const SizedBox(width: Sp.sm),
              Text(
                'login.biometric_prompt'.tr(),
                style: AppType.button(color: AppColors.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: Text(
        '${AppVersion.shortVersion}  •  ${'login.footer_copyright'.tr()}',
        style: AppType.muted(color: AppColors.textLow),
      ),
    );
  }
}

/// Pro البند ٤ ③: حقل «الشركة» — يفتح الدليل؛ و«شركة أخرى» يُظهر حقل الرابط.
class _CompanyField extends StatelessWidget {
  const _CompanyField({
    required this.loading,
    required this.picked,
    required this.manual,
    required this.sasCtrl,
    required this.onTap,
  });
  final bool loading;
  final DirectoryCompany? picked;
  final bool manual;
  final TextEditingController sasCtrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final label = picked?.name ?? (manual ? 'login.company_other'.tr() : 'login.company_choose'.tr());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LabeledInput(
          label: 'login.company_pick'.tr(),
          child: Material(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(R.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.md),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md + 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 20, color: picked != null ? AppColors.brand : AppColors.textLow),
                    const SizedBox(width: Sp.sm),
                    Expanded(
                      child: Text(label,
                          style: AppType.input(color: picked != null || manual ? AppColors.textHi : AppColors.textLow),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (loading)
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                    else
                      Icon(Icons.expand_more_rounded, color: AppColors.textMid),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (manual) ...[
          const SizedBox(height: Sp.lg),
          _LabeledInput(
            label: 'login.company_link'.tr(),
            child: TextField(
              controller: sasCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              textDirection: ui.TextDirection.ltr,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'login.company_hint'.tr(),
                hintStyle: AppType.input(color: AppColors.textLow),
                filled: true,
                fillColor: AppColors.surfaceInput,
                contentPadding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pro: الشركة المعروفة لهذا الدخول — **باسمها** لا برابطها، وللقراءة فقط
/// (الرابط مخفيٌّ في النموذج يُرسَل مع الدخول). مصدر الاسم وترتيبه في
/// `_fixCompany`.
///
/// [name] null ← لا اسم معروف: يُعرض **المضيف وحده** («rapi.earthlink.iq» بلا
/// بروتوكولٍ ولا مسار) بخطٍّ خافت. هو الاحتياط الأخير لشركةٍ ليست في الدليل ولا
/// تعرف «شركاتي» اسمها، وهو ما يظهر لحظةَ الحسم قبل وصول الاسم — فلا يُحجب
/// النموذج، ويحلّ الاسم محلّه بتلاشٍ حين يصل.
class _KnownCompanyTile extends StatelessWidget {
  const _KnownCompanyTile({required this.name, required this.host});
  final String? name;
  final String host;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final caption = 'login.company_pick'.tr();
    final named = name;
    final shown = named ?? host;
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$caption: $shown',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + Sp.xxs),
        decoration: BoxDecoration(
          color: AppColors.brandSoftBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.brandSoftBorder),
        ),
        child: Row(
          children: [
            Container(
              width: H.iconBox,
              height: H.iconBox,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.icon),
              ),
              child: Icon(Icons.apartment_rounded, size: 22, color: AppColors.brand),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(caption,
                      style: AppType.label(color: AppColors.textMid),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Sp.xxs),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, if (current != null) current],
                    ),
                    // الاسم معزولٌ اتّجاهيّاً: لاتينيٌّ أو مختلط («EarthLink») داخل
                    // سطرٍ عربيّ لا يتفكّك ترتيبه. والمضيف لاتينيٌّ دائماً: سطرٌ
                    // يساريّ محاذىً لبداية الواجهة، فيقع القصّ (إن طال) في آخره.
                    child: named != null
                        ? Text(
                            iso(named),
                            key: ValueKey(shown),
                            // اتّجاه الفقرة من أوّل حرفٍ قويّ (ما يستنتجه العزل نفسه)
                            // فتقع «…» في آخر الاسم المقصوص: اسمٌ لاتينيّ طويل في
                            // واجهةٍ عربيّة كان يُقصّ «...Telecom & Int» كأنّ أوّله قُطع.
                            textDirection:
                                Bidi.startsWithRtl(named) ? ui.TextDirection.rtl : ui.TextDirection.ltr,
                            textAlign: rtl ? TextAlign.right : TextAlign.left,
                            style: AppType.listName(color: AppColors.textHi),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text(
                            host,
                            key: ValueKey(shown),
                            textDirection: ui.TextDirection.ltr,
                            textAlign: rtl ? TextAlign.right : TextAlign.left,
                            // بارتفاع سطر الاسم: وصولُ الاسم بعده لا يزيح الحقول تحته.
                            strutStyle: StrutStyle.fromTextStyle(AppType.listName(), forceStrutHeight: true),
                            style: AppType.body(color: AppColors.textMid),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// قائمة الشركات (مع بحثٍ حين تكثر) + «شركة أخرى — اكتب رابطها» في الآخر.
class _CompanyPickerSheet extends StatefulWidget {
  const _CompanyPickerSheet({required this.items, required this.selected});
  final List<DirectoryCompany> items;
  final DirectoryCompany? selected;

  @override
  State<_CompanyPickerSheet> createState() => _CompanyPickerSheetState();
}

class _CompanyPickerSheetState extends State<_CompanyPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.items
        : widget.items.where((c) => c.name.toLowerCase().contains(q) || c.host.toLowerCase().contains(q)).toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(R.pill)),
                ),
              ),
              const SizedBox(height: Sp.md),
              Text('login.company_choose'.tr(), textAlign: TextAlign.center, style: AppType.sheetTitle(color: AppColors.textHi)),
              if (widget.items.length > 6) ...[
                const SizedBox(height: Sp.md),
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  style: AppType.input(color: AppColors.textHi),
                  decoration: InputDecoration(
                    hintText: 'login.company_search'.tr(),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textLow),
                    filled: true,
                    fillColor: AppColors.surfaceInput,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                  ),
                ),
              ],
              const SizedBox(height: Sp.md),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in items)
                      _PickerRow(
                        icon: Icons.apartment_rounded,
                        title: c.name,
                        subtitle: c.host,
                        selected: widget.selected?.code == c.code,
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                    const SizedBox(height: Sp.xs),
                    _PickerRow(
                      icon: Icons.link_rounded,
                      title: 'login.company_other'.tr(),
                      subtitle: 'login.company_other_sub'.tr(),
                      selected: false,
                      onTap: () => Navigator.of(context).pop('manual'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: selected ? AppColors.brandSoftBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.brand, size: 22),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.rowLabelBold(color: AppColors.textHi)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppType.muted(color: AppColors.textMid),
                          maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: ui.TextDirection.ltr),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: AppColors.brand, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
