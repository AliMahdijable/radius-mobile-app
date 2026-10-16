import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/earthlink_api.dart';
import '../../../core/util/amount_input.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/contact_picker.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../services/subscriber_events.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/el_deposit_password_field.dart';
import '../../../widgets/package_picker_field.dart';

/// «مشترك جديد» لجلسات ايرث لنك — يفتحه `showAddSubscriberSheet` بدل شيت
/// SAS4 حين يكون معرّف المدير المحفوظ `earthlink:<idx>`، بلا سحبٍ للإغلاق.
/// مسار SAS4 لم يتغيّر.
///
/// ثلاث طرق (من `/api/v2/el/create-options`، والمحجوبة تُخفى):
///   • رصيد أونلاين — باقةٌ من القائمة بسعرنا + باسورد الإيداع.
///   • كارت — رقم + Pin؛ الكارت يحدّد الباقة (تُقرأ بـcard-info وتُعرض للقراءة).
///   • تجريبي ٢٤ ساعة — حين تبقى حصّة، باقةٌ من القائمة بلا دفع.
/// ولطريقتي الرصيد والكارت: نقدي/دين/جزئي ما بين المشترك والوكيل بسعر
/// الباقة — بلغة شيت التفعيل نفسها (عناصره ونصوصه) فيبدو الشيتان واحداً.
///
/// ⚠️ لا إعادة إرسال تلقائيّة أبداً: ردٌّ غير مؤكّد (مهلة، بوّابة بلا ردّ،
/// `CREATE_UNCONFIRMED` أو `CREATE_LATE_SUSPECTED`) أو «أُرسلت قبل لحظات»
/// يُقفل الزرّ حتى يُعاد فتح الشيت بعد مراجعة القائمة، ورسالته (وقد تحمل مبلغ
/// الدين الذي يُسجَّل يدويّاً) باقيةٌ فوق الزرّ المقفل.
class ElAddSubscriberSheet extends StatefulWidget {
  const ElAddSubscriberSheet({super.key});

  @override
  State<ElAddSubscriberSheet> createState() => _ElAddSubscriberSheetState();
}

enum _Method { deposit, card, test }

enum _PayType { cash, partial, debt }

/// حال فحصٍ حيّ (اسم الدخول / قراءة الكارت).
enum _Check { idle, checking, ok, bad, failed }

class _ElAddSubscriberSheetState extends State<ElAddSubscriberSheet> {
  ElCreateOptions? _opts;
  bool _loading = true;
  String? _loadError;

  _Method _method = _Method.deposit;
  String _packageId = '';

  final _firstname = TextEditingController();
  final _lastname = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  // باسورد الإيداع: المحفوظ على الخادم («محفوظ · تغيير») أو يُكتب (+ «احفظه» للمالك).
  final _deposit = ElDepositPasswordController();
  final _identifierCtrl = TextEditingController(); // رقم الكارت
  final _pinCtrl = TextEditingController(); // Pin الكارت
  final _partialCtrl = TextEditingController();
  bool _showPassword = false;

  // الدين افتراضيّ — كشيت التفعيل (أغلب العمليّات آجلة، مطلب 2026-07-11).
  _PayType _pay = _PayType.debt;
  int _partialAmount = 0;

  // ── فحص اسم الدخول (مؤجَّل ٥٠٠ms) ──
  Timer? _userTimer;
  _Check _userState = _Check.idle;
  String? _userLateMsg;
  String? _userId; // name@suffix كما يعيده الخادم

  // ── قراءة الكارت (مؤجَّلة حتى يتوقّف الإدخال) ──
  Timer? _cardTimer;
  _Check _cardState = _Check.idle;
  ElCardInfo? _card;
  String? _cardError;
  String? _cardReadingKey; // القيم التي تُقرأ الآن — لا قراءتان متوازيتان لها

  bool _submitting = false;

  /// ردٌّ غير مؤكّد أو «أُرسلت قبل لحظات»: ربّما أُضيف — الزرّ مقفل.
  bool _outcomeUnclear = false;

  /// ما يُقال حين قُفل الزرّ — رسالة الخادم كما هي (CREATE_UNCONFIRMED /
  /// CREATE_LATE_SUSPECTED قد تحمل مبلغ الدين الذي يُسجَّل يدويّاً) أو نصّنا؛
  /// تبقى فوق الزرّ ما بقي الشيت، لا إشعاراً يزول بعد ثوانٍ.
  String? _outcomeNote;

  @override
  void initState() {
    super.initState();
    _load();
    _deposit.addListener(_onDepositChanged);
  }

  void _onDepositChanged() {
    if (mounted) setState(() {}); // كي يتحدّث تفعيل الزرّ
  }

  @override
  void dispose() {
    _userTimer?.cancel();
    _cardTimer?.cancel();
    _deposit.removeListener(_onDepositChanged);
    _deposit.dispose();
    for (final c in [
      _firstname,
      _lastname,
      _phone,
      _username,
      _password,
      _identifierCtrl,
      _pinCtrl,
      _partialCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final r = await EarthlinkApi.createOptions();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _opts = r.data;
      if (r.data == null) {
        _loadError = r.message ?? 'sheets.el_add.load_failed'.tr();
        return;
      }
      final methods = _methods;
      if (methods.isNotEmpty && !methods.contains(_method)) {
        _method = methods.first;
      }
      if (r.data!.packageById(_packageId) == null) _packageId = '';
    });
  }

  // ───────────────────────── المشتقّات ─────────────────────────

  /// الطرق المسموحة بالترتيب: رصيد · كارت · تجريبي (حين تبقى حصّة).
  List<_Method> get _methods {
    final o = _opts;
    if (o == null) return const [];
    return [
      if (o.canDeposit) _Method.deposit,
      if (o.canCard) _Method.card,
      if (o.testAvailable) _Method.test,
    ];
  }

  String get _suffix => _opts?.userSuffix ?? '';

  /// اسم الدخول بلا لاحقة — لو لُصق «ahmed@xxx» يُؤخذ ما قبل @.
  String get _normalizedUsername {
    final t = _username.text.trim();
    final at = t.indexOf('@');
    return at < 0 ? t : t.substring(0, at);
  }

  ElCreatePackage? get _cardPkg {
    final pid = _card?.profileId;
    return pid == null ? null : _opts?.packageById('$pid');
  }

  /// باقة العمليّة: المختارة (رصيد/تجريبي) أو باقة الكارت المقروءة.
  ElCreatePackage? get _pkg =>
      _method == _Method.card ? _cardPkg : _opts?.packageById(_packageId);

  bool get _pkgKnown => _method == _Method.card
      ? _cardState == _Check.ok
      : _packageId.isNotEmpty && _pkg != null;

  String get _pkgName {
    if (_method == _Method.card) {
      return _card?.profileName ?? _cardPkg?.name ?? '—';
    }
    return _pkg?.name ?? '—';
  }

  /// سعرنا للمشترك — به تُسعَّر نقدي/دين/جزئي. `null` = غير معروف.
  /// الكارت: باقته من القائمة أوّلاً، وإلّا السعر الذي أرجعته قراءة الكارت
  /// نفسها (باقةٌ خارج create-options) فيظهر السعر وبانر الدين.
  num? get _price => _method == _Method.card
      ? (_cardPkg?.price ?? _card?.price)
      : _pkg?.price;

  bool get _paid => _method != _Method.test;

  /// المشترك جديد (رصيده صفر): نقدي ⇒ ٠ · دين ⇒ −السعر · جزئي ⇒ −السعر+المدفوع.
  num get _balanceAfter {
    final price = _price ?? 0;
    return switch (_pay) {
      _PayType.cash => 0,
      _PayType.debt => -price,
      _PayType.partial => -price + _partialAmount,
    };
  }

  bool get _canSubmit {
    if (_loading || _submitting || _opts == null || _outcomeUnclear) {
      return false;
    }
    if (!_methods.contains(_method)) return false;
    if (_firstname.text.trim().isEmpty ||
        _phone.text.trim().isEmpty ||
        _password.text.isEmpty ||
        _normalizedUsername.isEmpty) {
      return false;
    }
    if (_userState == _Check.checking || _userState == _Check.bad) return false;
    switch (_method) {
      case _Method.deposit:
        if (_packageId.isEmpty || !_deposit.ready) return false;
      case _Method.test:
        if (_packageId.isEmpty) return false;
      case _Method.card:
        if (_cardState != _Check.ok) return false;
    }
    if (_paid && _pay == _PayType.partial && _partialAmount <= 0) return false;
    return true;
  }

  // ───────────────────────── الفحوص الحيّة ─────────────────────────

  void _onUsernameChanged(String _) {
    _userTimer?.cancel();
    final u = _normalizedUsername;
    if (u.isEmpty) {
      setState(() {
        _userState = _Check.idle;
        _userId = null;
        _userLateMsg = null;
      });
      return;
    }
    setState(() {
      _userState = _Check.checking;
      _userId = null;
      _userLateMsg = null;
    });
    _userTimer =
        Timer(const Duration(milliseconds: 500), () => _checkUsername(u));
  }

  Future<void> _checkUsername(String u) async {
    final r = await EarthlinkApi.checkUsername(u);
    // ردٌّ متأخّر لاسمٍ تغيّر بعده — يُهمل.
    if (!mounted || u != _normalizedUsername) return;
    setState(() {
      final avail = r.available;
      if (avail == null) {
        _userState = _Check.failed;
      } else {
        _userState = avail ? _Check.ok : _Check.bad;
        _userId = r.userId;
        _userLateMsg = avail ? null : r.message;
      }
    });
  }

  /// قراءة الكارت حين يتوقّف الإدخال (أو «تمّ» على اللوحة) — لا مع كلّ
  /// ضغطة: Pin ناقص يُحسب محاولةً خاطئة عند المزوّد.
  void _onCardChanged(String _) {
    _cardTimer?.cancel();
    final id = _identifierCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (id.isEmpty || pin.isEmpty) {
      setState(() {
        _cardState = _Check.idle;
        _card = null;
        _cardError = null;
      });
      return;
    }
    setState(() {
      _cardState = _Check.checking;
      _card = null;
      _cardError = null;
    });
    _cardTimer = Timer(const Duration(milliseconds: 900), _readCard);
  }

  Future<void> _readCard() async {
    _cardTimer?.cancel();
    final id = _identifierCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (id.isEmpty || pin.isEmpty) return;
    // أيّ تعديلٍ يُرجع الحال إلى «جارٍ»، فـok/bad تعني أنّ هذه القيم قُرئت.
    if (_cardState == _Check.ok || _cardState == _Check.bad) return;
    final key = '$id\n$pin';
    if (_cardReadingKey == key) return; // قراءةٌ جارية للقيم نفسها
    _cardReadingKey = key;
    if (_cardState != _Check.checking) {
      setState(() {
        _cardState = _Check.checking;
        _cardError = null;
      });
    }
    final r = await EarthlinkApi.cardInfo(identifier: id, pin: pin);
    if (_cardReadingKey == key) _cardReadingKey = null;
    if (!mounted ||
        id != _identifierCtrl.text.trim() ||
        pin != _pinCtrl.text.trim()) {
      return;
    }
    setState(() {
      final d = r.data;
      if (d == null) {
        _cardState = _Check.failed;
        _cardError = r.message;
      } else if (d.valid) {
        _cardState = _Check.ok;
        _card = d;
      } else {
        _cardState = _Check.bad;
        _cardError = d.message;
      }
    });
  }

  // ───────────────────────── الإرسال ─────────────────────────

  Future<void> _submit() async {
    if (_submitting || !_canSubmit) return;
    final method = _method;
    final price = _price;
    final paymentType = switch (_pay) {
      _PayType.cash => 'cash',
      _PayType.debt => 'debt',
      _PayType.partial => 'partial',
    };
    final num? paidAmount = switch (_pay) {
      _PayType.debt => 0,
      _PayType.partial => _partialAmount,
      // سعرٌ مجهول (باقة كارتٍ خارج قائمتنا) ⇒ لا نرسل ٠ يُقرأ «لم يدفع».
      _PayType.cash => price,
    };
    Object? profileId;
    if (method != _Method.card) {
      profileId = int.tryParse(_packageId) ?? _packageId;
    }

    // الطبقة العليا تُلتقط **قبل** الانتظار: لو أُزيل الشيت أثناءه (خروجٌ
    // قسريّ، توجيه إشعار…) تُعرض النتيجة — «ربّما أُضيف» ومبلغ الدين وتنبيه
    // الدفتر وإشعار النجاح — عليها، لا تضيع مع `!mounted`.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _submitting = true);
    final r = await EarthlinkApi.createSubscriber(
      method: method.name,
      username: _normalizedUsername,
      password: _password.text,
      firstname: _firstname.text.trim(),
      lastname: _lastname.text.trim(),
      phone: _phone.text.trim(),
      profileId: profileId,
      // null مع المحفوظ — الخادم يضيفه بنفسه.
      depositPassword:
          method == _Method.deposit ? _deposit.passwordToSend : null,
      rememberDepositPassword:
          method == _Method.deposit && _deposit.rememberToSend,
      cardIdentifier:
          method == _Method.card ? _identifierCtrl.text.trim() : null,
      cardPin: method == _Method.card ? _pinCtrl.text.trim() : null,
      paymentType: method == _Method.test ? null : paymentType,
      paidAmount: method == _Method.test ? null : paidAmount,
    );
    final duplicate = r.code == EarthlinkApi.codeRecentDuplicate;
    // ربّما أُضيف (`unclear`: مهلة/بوّابة/CREATE_UNCONFIRMED/
    // CREATE_LATE_SUSPECTED) أو «أُرسلت قبل لحظات»: الزرّ يُقفل حتى يُعاد
    // فتح الشيت بعد مراجعة القائمة. `USERNAME_TAKEN` العاديّ ليس منها.
    final locked = r.unclear || duplicate;
    // القوائم تُحدَّث ولو أُغلق الشيت أثناء الانتظار.
    if (r.ok || locked) SubscriberEvents.notifyChange();
    // سبب القفل: رسالة الخادم أولى (قد تحمل مبلغ الدين الذي يُسجَّل يدويّاً)،
    // وبلاها نصّنا.
    final String? lockNote = !locked
        ? null
        : r.message ??
            (r.unclear
                ? 'sheets.el_add.unclear'.tr()
                : 'sheets.el_add.duplicate'.tr());
    final alive = mounted;
    if (alive) {
      setState(() {
        _submitting = false;
        if (lockNote != null) {
          _outcomeUnclear = true;
          _outcomeNote = lockNote;
        }
      });
    }
    if (lockNote != null) {
      // تبقى أيضاً سطراً فوق الزرّ المقفل؛ وإن أُزيل الشيت فهذا الإشعار
      // وحده يحملها — فيطول.
      _showOverlaySnack(
        overlay,
        lockNote,
        tone: _SnackTone.error,
        duration: Duration(seconds: alive ? 8 : 20),
      );
      return;
    }
    if (!r.ok) {
      _showOverlaySnack(
        overlay,
        r.message ?? 'sheets.el_add.failed'.tr(),
        tone: _SnackTone.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    // أُضيف لكنّ دينه لم يُسجَّل في دفترنا: تنبيهٌ لا يمنع يلي إشعار النجاح،
    // على الطبقة العليا فيبقى بعد إغلاق الشيت.
    final debtWarning = r.debtWriteFailed
        ? (r.debtWriteMessage ?? 'sheets.el_add.debt_not_recorded'.tr())
        : null;
    final okShown = _showOverlaySnack(
        overlay, 'sheets.el_add.ok'.tr(), tone: _SnackTone.success);
    if (debtWarning != null) {
      unawaited(okShown.then((_) => _showOverlaySnack(
            overlay,
            debtWarning,
            tone: _SnackTone.warning,
            duration: const Duration(seconds: 8),
          )));
    }
    // يُغلق مسار هذه الورقة نفسه لا «أعلى مسار»: إشعارٌ/شاشةٌ فُتحت فوقها أثناء
    // الإنشاء كانت تُغلَق بدلها وتبقى الورقة مفتوحةً بزرٍّ حيّ (إنشاءٌ ثانٍ = خصمٌ ثانٍ).
    if (mounted) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        if (route.isCurrent) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).removeRoute(route, true);
        }
      }
    }
  }

  String get _footerLabel {
    if (_submitting) return 'sheets.el_add.submitting'.tr();
    if (_outcomeUnclear) return 'sheets.el_add.check_first'.tr();
    return 'sheets.el_add.submit'.tr();
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // حشوة لوحة المفاتيح داخل DesignSheet (يرتفع الشيت كلّه مع الزرّ).
    return PopScope(
      canPop: !_submitting,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.userPlus,
          title: 'sheets.el_add.title'.tr(),
          subtitle: 'sheets.el_add.subtitle'.tr(),
          onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
        ),
        footer: SheetFooterBar(
          label: _footerLabel,
          icon: LucideIcons.userPlus,
          enabled: _canSubmit,
          busy: _submitting,
          onPressed: _submit,
          above: _outcomeUnclear ? _outcomeNoteView() : null,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildBody(),
        ),
      ),
    );
  }

  /// سبب القفل فوق الزرّ المقفل — ظاهرٌ بلا تمرير أينما كان الجسم، وكاملاً
  /// (لا قصّ يُسقط مبلغ الدين). ارتفاعه محدودٌ بجزءٍ من المرئيّ ويُمرَّر داخله،
  /// فلا يدفع الشريط خارج الشيت مهما طالت الرسالة أو ظهرت لوحة المفاتيح.
  Widget _outcomeNoteView() {
    final visible = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: visible * 0.22),
      child: SingleChildScrollView(
        child: _Note(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          text: _outcomeNote ?? 'sheets.el_add.unclear'.tr(),
          maxLines: null,
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_loading) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.mega),
          child: Center(
            child: CircularProgressIndicator(
                color: AppColors.brandAccent, strokeWidth: 2.5),
          ),
        ),
      ];
    }
    if (_loadError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.huge),
          child: Column(
            children: [
              Icon(LucideIcons.triangleAlert, color: AppColors.error, size: 32),
              const SizedBox(height: Sp.sm),
              Text(_loadError!,
                  style: AppType.rowValue(color: AppColors.error),
                  textAlign: TextAlign.center),
              const SizedBox(height: Sp.sm),
              TextButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      ];
    }
    if (_methods.isEmpty) {
      return [
        _Note(
          tone: AppTone.danger,
          icon: LucideIcons.ban,
          text: 'sheets.el_add.no_methods'.tr(),
        ),
      ];
    }
    final cur = 'common.currency'.tr();
    final price = _price;
    final enabled = !_submitting;
    return [
      _methodSection(),
      const SizedBox(height: 14),
      // الاسم * | اللقب — عمودان كشيت SAS4.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SheetSection(
              label: 'sheets.el_add.firstname'.tr(),
              child: _textBox(
                ctrl: _firstname,
                hint: 'sheets.el_add.firstname_hint'.tr(),
                icon: LucideIcons.user,
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: SheetSection(
              label: 'sheets.el_add.lastname'.tr(),
              child: _textBox(
                ctrl: _lastname,
                hint: 'sheets.el_add.lastname_hint'.tr(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      SheetSection(
        label: 'sheets.el_add.phone'.tr(),
        child: _textBox(
          ctrl: _phone,
          hint: 'sheets.el_add.phone_hint'.tr(),
          icon: LucideIcons.phone,
          keyboard: TextInputType.phone,
          trailing: _contactButton(),
        ),
      ),
      const SizedBox(height: 14),
      SheetSection(
        label: 'sheets.el_add.username'.tr(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _usernameBox(),
            if (_userState != _Check.idle) ...[
              const SizedBox(height: Sp.x6),
              _usernameStatus(),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      SheetSection(
        label: 'sheets.el_add.password'.tr(),
        child: _textBox(
          ctrl: _password,
          hint: '••••••••',
          icon: LucideIcons.lock,
          ltr: true,
          obscure: !_showPassword,
          plain: true,
          trailing: _iconBtn(
            icon: _showPassword ? LucideIcons.eyeOff : LucideIcons.eye,
            tooltip: _showPassword
                ? 'sheets.el_add.hide_password'.tr()
                : 'sheets.el_add.show_password'.tr(),
            onTap: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (_method == _Method.card)
        _cardSection()
      else
        SheetSection(
          label: 'sheets.el_add.package'.tr(),
          child: PackagePickerField(
            options: [
              for (final p in _opts!.packages)
                PackageOption(id: p.id, name: p.name, price: p.price),
            ],
            selectedId: _packageId,
            enabled: enabled,
            emptyText: 'sheets.el_add.no_packages'.tr(),
            onSelected: (id) => setState(() => _packageId = id),
          ),
        ),
      if (_method == _Method.deposit) ...[
        const SizedBox(height: 14),
        SheetSection(
          label: 'sheets.el_add.deposit_password'.tr(),
          child: ElDepositPasswordField(
            controller: _deposit,
            enabled: enabled,
            hint: 'sheets.el_add.deposit_password_hint'.tr(),
          ),
        ),
      ],
      if (_paid && _pkgKnown) ...[
        const SizedBox(height: 14),
        SheetPlanCard(
          planLabel: 'subscribers.label_package'.tr(),
          planName: _pkgName,
          durationLabel: null,
          amountLabel: 'sheets.amount_due'.tr(),
          amount: price == null ? '—' : '${formatIQD(price.round())} $cur',
        ),
        ..._infoRows(cur),
      ],
      if (_paid) ...[
        const SizedBox(height: 14),
        _paymentSection(price),
        if (_pkgKnown && price != null) ...[
          const SizedBox(height: 14),
          SheetResultBanner(
            icon: LucideIcons.arrowLeft,
            label: _balanceAfter < 0
                ? 'sheets.el_add.debt_after'.tr()
                : 'sheets.el_add.credit_after'.tr(),
            value: '${formatIQD(_balanceAfter.abs().round())} $cur',
            tone: _balanceAfter < 0 ? AppTone.danger : AppTone.brand,
          ),
        ],
      ],
    ];
  }

  /// «طريقة الإضافة»: رصيد أونلاين | كارت | تجريبي — المحجوبة لا تظهر،
  /// وحصّة التجريبيّ الباقية في طرف سطر التسمية.
  Widget _methodSection() {
    final methods = _methods;
    final o = _opts!;
    return SheetSection(
      label: 'sheets.el_add.method'.tr(),
      hint: o.testAvailable
          ? 'sheets.el_add.test_left'.tr(namedArgs: {'n': '${o.testCount}'})
          : null,
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetChoiceTiles(
            labels: [
              for (final m in methods)
                switch (m) {
                  _Method.deposit => 'sheets.el_add.method_deposit'.tr(),
                  _Method.card => 'sheets.el_add.method_card'.tr(),
                  _Method.test => 'sheets.el_add.method_test'.tr(),
                },
            ],
            icons: [
              for (final m in methods)
                switch (m) {
                  _Method.deposit => LucideIcons.wallet,
                  _Method.card => LucideIcons.creditCard,
                  _Method.test => LucideIcons.hourglass,
                },
            ],
            selectedIndex: methods.indexOf(_method),
            enabled: !_submitting,
            onSelect: (i) => setState(() => _method = methods[i]),
          ),
          if (_method == _Method.test) ...[
            const SizedBox(height: Sp.sm),
            _Note(
              tone: AppTone.info,
              icon: LucideIcons.hourglass,
              text: 'sheets.el_add.test_note'
                  .tr(namedArgs: {'n': '${o.testCount}'}),
            ),
          ],
        ],
      ),
    );
  }

  /// الكارت: رقم + Pin (كشيت التفعيل)، وتحتهما باقته المقروءة أو سبب رفضه.
  Widget _cardSection() {
    return SheetSection(
      label: 'sheets.el_add.card'.tr(),
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _textBox(
                  ctrl: _identifierCtrl,
                  hint: 'sheets.el_add.card_number'.tr(),
                  ltr: true,
                  plain: true,
                  keyboard: TextInputType.number,
                  onChanged: _onCardChanged,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _textBox(
                  ctrl: _pinCtrl,
                  hint: 'sheets.el_add.card_pin'.tr(),
                  ltr: true,
                  plain: true,
                  keyboard: TextInputType.number,
                  action: TextInputAction.done,
                  onChanged: _onCardChanged,
                  onSubmitted: _readCard,
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          _cardNote(),
        ],
      ),
    );
  }

  Widget _cardNote() {
    switch (_cardState) {
      case _Check.idle:
        return _Note(
          tone: AppTone.neutral,
          icon: LucideIcons.ticket,
          text: 'sheets.el_add.card_enter'.tr(),
        );
      case _Check.checking:
        return _Note(
          tone: AppTone.neutral,
          icon: LucideIcons.ticket,
          text: 'sheets.el_add.card_checking'.tr(),
          busy: true,
        );
      case _Check.ok:
        return _Note(
          tone: AppTone.brand,
          icon: LucideIcons.circleCheck,
          text: 'sheets.el_add.card_package'
              .tr(namedArgs: {'name': _pkgName}),
        );
      case _Check.bad:
        return _Note(
          tone: AppTone.danger,
          icon: LucideIcons.circleX,
          text: _cardError ?? 'sheets.el_add.card_invalid'.tr(),
        );
      case _Check.failed:
        // نصّ الخادم أولى (كـRATE_LIMITED «انتظر دقيقة»)؛ وبلاه نصّنا.
        return _Note(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          text: _cardError ?? 'sheets.el_add.card_read_failed'.tr(),
          onRetry: _submitting ? null : _readCard,
        );
    }
  }

  /// كلفة الباقة على الوكيل + رصيد الإيداع (للرصيد) — كصفوف شيت التفعيل،
  /// وتنبيهٌ (لا منع) حين يقلّ الرصيد عن الكلفة: الخادم صاحب الحكم.
  List<Widget> _infoRows(String cur) {
    final cost = _method == _Method.card
        ? (_cardPkg?.costPrice ?? _card?.costPrice)
        : _pkg?.costPrice;
    final balance = _method == _Method.deposit ? _opts?.depositBalance : null;
    final low = balance != null && cost != null && cost > balance;
    final rows = [
      if (cost != null && cost > 0)
        SheetRowData(
          label: 'sheets.el_add.package_cost'.tr(),
          value: '${formatIQD(cost.round())} $cur',
          valueColor: AppColors.textMid,
        ),
      if (balance != null)
        SheetRowData(
          label: 'sheets.el_add.deposit_balance'.tr(),
          value: '${formatIQD(balance.round())} $cur',
          valueColor: low ? AppColors.error : null,
          strong: true,
        ),
    ];
    return [
      if (rows.isNotEmpty) ...[
        const SizedBox(height: 14),
        SheetRowsGroup(rows: rows),
      ],
      if (low) ...[
        const SizedBox(height: Sp.sm),
        _Note(
          tone: AppTone.warning,
          icon: LucideIcons.triangleAlert,
          text: 'sheets.el_add.low_balance'.tr(),
        ),
      ],
    ];
  }

  /// طريقة الدفع (نقدي/دين/جزئي + المبلغ الجزئيّ) — نسخة شيت التفعيل.
  Widget _paymentSection(num? price) {
    return SheetSection(
      label: 'sheets.payment_method'.tr(),
      gap: Sp.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetChoiceTiles(
            labels: [
              'sheets.pay_cash'.tr(),
              'sheets.pay_debt'.tr(),
              'sheets.pay_partial'.tr(),
            ],
            icons: const [
              LucideIcons.banknote,
              LucideIcons.creditCard,
              LucideIcons.chartPie,
            ],
            selectedIndex: switch (_pay) {
              _PayType.cash => 0,
              _PayType.debt => 1,
              _PayType.partial => 2,
            },
            enabled: !_submitting,
            onSelect: (i) => setState(() => _pay = switch (i) {
                  0 => _PayType.cash,
                  1 => _PayType.debt,
                  _ => _PayType.partial,
                }),
          ),
          if (_pay == _PayType.partial) ...[
            const SizedBox(height: Sp.md),
            SheetSection(
              label: 'sheets.cash_paid_amount'.tr(),
              gap: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetBox(
                    focused: _partialAmount > 0,
                    radius: 18,
                    padding: const EdgeInsets.symmetric(
                        horizontal: Sp.lg, vertical: 14),
                    child: AmountTextField(
                      controller: _partialCtrl,
                      enabled: !_submitting,
                      currency: 'common.currency'.tr(),
                      onValue: (v) => setState(() => _partialAmount = v),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final c in _partialChips(price?.round() ?? 0))
                        SheetQuickChip(
                          label: AmountShorthand.format(c),
                          selected: _partialAmount == c,
                          enabled: !_submitting,
                          onTap: () => _addToPartial(c),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// الشرائح تُضيف (سلوك شيت التفعيل).
  void _addToPartial(int chip) {
    final next = _partialAmount + chip;
    // المتحكّم يُعاد تنسيقه داخل AmountTextField، و`onValue` يضبط المبلغ.
    _partialCtrl.value = TextEditingValue(
      text: AmountShorthand.format(next),
      selection:
          TextSelection.collapsed(offset: AmountShorthand.format(next).length),
    );
    setState(() => _partialAmount = next);
  }

  /// سلّم المبالغ الجزئيّة — يُقصّ عند سعر الباقة (والسعر المجهول ⇒ السلّم كلّه).
  static List<int> _partialChips(int price) {
    const scale = [5000, 10000, 15000, 20000, 25000, 30000, 40000, 50000];
    if (price <= 0) return scale;
    final out = scale.where((c) => c < price).toList();
    return out.isEmpty ? [price] : out;
  }

  // ───────────────────────── الحقول ─────────────────────────

  /// حقلٌ بلغة شيت التفعيل: SheetBox أبيض بحدّ البراند حين يمتلئ.
  Widget _textBox({
    required TextEditingController ctrl,
    required String hint,
    IconData? icon,
    bool ltr = false,
    bool obscure = false,
    bool plain = false,
    TextInputType? keyboard,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    Widget? trailing,
  }) {
    return SheetBox(
      icon: icon,
      focused: ctrl.text.isNotEmpty,
      // مع زرٍّ في الطرف: حشوةٌ أصغر من جهته وعموديّاً، فيبقى الارتفاع ٤٥
      // كبقيّة الحقول (SheetBox يأخذ EdgeInsets لا Directional).
      padding: trailing == null
          ? const EdgeInsets.symmetric(horizontal: 15, vertical: 13)
          : (Directionality.of(context) == ui.TextDirection.rtl
              ? const EdgeInsets.fromLTRB(4, 2.5, 15, 2.5)
              : const EdgeInsets.fromLTRB(15, 2.5, 4, 2.5)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              enabled: !_submitting,
              obscureText: obscure,
              autocorrect: !plain,
              enableSuggestions: !plain,
              keyboardType: keyboard,
              textInputAction: action,
              textDirection: ltr ? ui.TextDirection.ltr : null,
              onChanged: (v) {
                if (onChanged != null) {
                  onChanged(v);
                } else {
                  setState(() {}); // كي يتحدّث تفعيل الزرّ وحدّ الحقل
                }
              },
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
              style: AppType.input(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: AppColors.textMid,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      onPressed: _submitting ? null : onTap,
    );
  }

  Widget _contactButton() {
    return IconButton(
      icon: const Icon(LucideIcons.contact, size: 18),
      color: AppColors.brand,
      tooltip: 'sheets.el_add.pick_contact'.tr(),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      onPressed: _submitting
          ? null
          : () async {
              final r = await ContactPicker.pickPhone();
              if (!mounted) return;
              if (r.phone != null) {
                setState(() => _phone.text = r.phone!);
              } else if (r.error != null) {
                showSheetSnack(context, r.error!, isError: true);
              }
            },
    );
  }

  /// اسم الدخول + اللاحقة الثابتة (`@xxx`) — لاتينيّ من اليسار كما يُكتب،
  /// وأيقونة الفحص في طرفه.
  Widget _usernameBox() {
    final suffix = _suffix;
    return SheetBox(
      focused: _userState == _Check.ok,
      borderColor: _userState == _Check.bad ? AppColors.error : null,
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: LayoutBuilder(
          builder: (context, c) => Row(
            children: [
              Icon(LucideIcons.atSign, size: 18, color: AppColors.textHint),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: TextField(
                  controller: _username,
                  enabled: !_submitting,
                  autocorrect: false,
                  enableSuggestions: false,
                  // لوحة لاتينيّة بلا اقتراحات على أندرويد وiOS.
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.next,
                  textDirection: ui.TextDirection.ltr,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@-]')),
                  ],
                  onChanged: _onUsernameChanged,
                  style: AppType.input(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'sheets.el_add.username_hint'.tr(),
                    hintStyle: AppType.input(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
              if (suffix.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: c.maxWidth * 0.5),
                  child: Text(
                    suffix,
                    textDirection: ui.TextDirection.ltr,
                    style: AppType.input(color: AppColors.textMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (_userState != _Check.idle) ...[
                const SizedBox(width: Sp.sm),
                _userStateIcon(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _userStateIcon() {
    return switch (_userState) {
      _Check.checking => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.textHint),
        ),
      _Check.ok =>
        Icon(LucideIcons.circleCheck, size: 16, color: AppColors.success),
      _Check.bad => Icon(LucideIcons.circleX, size: 16, color: AppColors.error),
      _ => Icon(LucideIcons.circleAlert, size: 16, color: AppColors.textHint),
    };
  }

  /// ✓ متاح (مع المعرّف الكامل) · ✗ مستخدم · جارٍ الفحص · تعذّر الفحص.
  Widget _usernameStatus() {
    // «مستخدم» لأنّ إضافةً سابقة غير مؤكّدة نجحت متأخّرة: نصّ الخادم كاملاً (ينهى
    // عن الإضافة باسمٍ آخر — خصمٌ ثانٍ)، والإرسال يبقى مقفولاً كأيّ اسمٍ مستخدم.
    final late = _userLateMsg;
    if (_userState == _Check.bad && late != null && late.isNotEmpty) {
      return Text(
        '⚠ $late',
        style: AppType.muted(color: AppColors.warning).copyWith(fontSize: 11.5),
      );
    }
    final (String text, Color color) = switch (_userState) {
      _Check.checking => ('sheets.el_add.user_checking'.tr(), AppColors.textHint),
      _Check.ok => (
          (_userId ?? '').isEmpty
              ? '✓ ${'sheets.el_add.user_available'.tr()}'
              : '✓ ${'sheets.el_add.user_available'.tr()} — ${iso(_userId!)}',
          AppColors.success,
        ),
      _Check.bad => ('✗ ${'sheets.el_add.user_taken'.tr()}', AppColors.error),
      _ => ('sheets.el_add.user_check_failed'.tr(), AppColors.textHint),
    };
    return Text(
      text,
      style: AppType.muted(color: color).copyWith(fontSize: 11.5),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// سطر حالٍ بنغمةٍ من `AppTone` — نسخة `_CardNote` في شيت التفعيل. ومع
/// [onRetry] يصير السطر كلّه زرّاً بأيقونة تحديث.
class _Note extends StatelessWidget {
  const _Note({
    required this.tone,
    required this.icon,
    required this.text,
    this.onRetry,
    this.busy = false,
    this.maxLines = 3,
  });

  final AppTone tone;
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final bool busy;

  /// `null` = النصّ كاملاً بلا قصّ (سبب القفل: قد يحمل مبلغ الدين).
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final retry = onRetry;
    return Material(
      color: tone.softBg,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: busy ? null : retry,
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: tone.softBorder),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tone.fill),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppType.body(color: tone.onSoft),
                  maxLines: maxLines,
                  // القصّ مع سطورٍ بلا حدّ يُرجع النصّ سطراً واحداً — فلا قصّ.
                  overflow: maxLines == null ? null : TextOverflow.ellipsis,
                ),
              ),
              if (retry != null || busy) ...[
                const SizedBox(width: Sp.sm),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: busy
                      ? CircularProgressIndicator(
                          strokeWidth: 2, color: tone.fill)
                      : Icon(LucideIcons.refreshCw, size: 16, color: tone.fill),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _SnackTone { success, error, warning }

/// إشعارٌ عائم بشكل `showSheetSnack` نفسه وبثلاث نغمات (ذاك يعرف النجاح
/// والخطأ وحدهما)، يُغلق بلمسةٍ أو بعد [duration]، ويكتمل مستقبله حين يُغلق
/// (فيتلوه تنبيهٌ آخر بلا تراكب).
///
/// يأخذ [OverlayState] لا سياقاً: تُلتقط الطبقة العليا قبل انتظار الإضافة،
/// فيُعرض ولو أُغلق الشيت أو أُزيل أثناءها. طبقةٌ غائبة ⇒ لا شيء.
Future<void> _showOverlaySnack(
  OverlayState? overlay,
  String message, {
  required _SnackTone tone,
  Duration duration = const Duration(seconds: 3),
}) {
  if (overlay == null || !overlay.mounted) return Future<void>.value();
  final done = Completer<void>();
  Timer? timer;
  late final OverlayEntry entry;
  void dismiss() {
    if (done.isCompleted) return;
    timer?.cancel();
    entry.remove();
    entry.dispose();
    done.complete();
  }

  entry = OverlayEntry(
    builder: (context) {
      final (Color fill, IconData icon) = switch (tone) {
        _SnackTone.success => (AppColors.successFill, Icons.check_circle_outline),
        _SnackTone.error => (AppColors.errorFill, Icons.error_outline),
        _SnackTone.warning => (AppColors.warningFill, LucideIcons.triangleAlert),
      };
      return Positioned(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
        child: SafeArea(
          top: false,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(R.sm),
            color: fill,
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: dismiss,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.onBrand, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: AppColors.onBrand,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  overlay.insert(entry);
  timer = Timer(duration, dismiss);
  return done.future;
}
