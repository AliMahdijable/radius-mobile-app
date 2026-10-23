import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../api/big_subscribers_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../api/telegram_api.dart';
import '../../../core/util/clipboard_helper.dart';
import '../../../models/subscriber.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/app_sheet.dart';

/// telegramLinkGeneratorSheet — يبحث المدير عن مشترك بالاسم، يولّد
/// deep link، وينسخه/يرسله عبر واتساب. يستدعي:
///   - GET /api/telegram/deep-link/:adminId/:idx
///   - POST /api/telegram/send-link-via-wa/:adminId/:idx
Future<void> showTelegramLinkGeneratorSheet(
  BuildContext context, {
  required String adminId,
  required VoidCallback onDone,
}) {
  return showAppSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _GeneratorSheet(adminId: adminId, onDone: onDone),
  );
}

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet({required this.adminId, required this.onDone});
  final String adminId;
  final VoidCallback onDone;

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  final _searchCtrl = TextEditingController();
  List<Subscriber> _allSubs = const [];
  Subscriber? _selected;
  String? _generatedLink;
  bool _loading = true;
  bool _generating = false;
  bool _sending = false;
  String? _err;

  /// 2026-08-26: عرض QR — للمشتركين اللي بلا واتساب، الأدمن يعرض
  /// الـQR على شاشته، المشترك يمسحه بجواله.
  bool _showQr = false;

  /// الحساب الكبير (≥ ٥٠٠٠): البحث في الساس بعد توقّف الكتابة بدل القائمة الكاملة. جيلٌ لكلّ طلب.
  bool _big = false;
  int _bigTotal = 0;
  List<Subscriber> _bigMatches = const [];
  bool _bigSearching = false;
  int _bigGen = 0;
  Timer? _bigDebounce;

  @override
  void initState() {
    super.initState();
    _loadSubs();
  }

  @override
  void dispose() {
    _bigDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubs() async {
    setState(() => _loading = true);
    final big = await BigSubscribersApi.probe();
    if (!mounted) return;
    if (big > 0) {
      setState(() {
        _big = true;
        _bigTotal = big;
        _loading = false;
      });
      return;
    }
    final subs = await SubscribersApi.loadAll();
    if (!mounted) return;
    setState(() {
      _allSubs = subs ?? const [];
      _loading = false;
    });
  }

  void _bigSearchSoon() {
    _bigDebounce?.cancel();
    _bigDebounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _searchCtrl.text.trim();
      final gen = ++_bigGen;
      if (q.isEmpty) {
        if (mounted) setState(() => _bigMatches = const []);
        return;
      }
      setState(() => _bigSearching = true);
      try {
        final p = await BigSubscribersApi.page(page: 1, size: 12, tab: 'all', query: q);
        if (!mounted || gen != _bigGen) return;
        setState(() {
          _bigMatches = p.rows;
          _bigSearching = false;
        });
      } on BigListException catch (e) {
        if (!mounted || gen != _bigGen) return;
        setState(() {
          _bigMatches = const [];
          _bigSearching = false;
          _err = e.message;
        });
      }
    });
  }

  List<Subscriber> get _matches {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    if (_big) return [for (final s in _bigMatches) if (s.idx != null) s];
    final out = <Subscriber>[];
    for (final s in _allSubs) {
      if (s.idx == null) continue;
      final hay = [s.username, s.firstname, s.lastname, s.phone]
          .where((x) => x != null && x.isNotEmpty)
          .join(' ')
          .toLowerCase();
      if (hay.contains(q)) {
        out.add(s);
        if (out.length >= 12) break;
      }
    }
    return out;
  }

  Future<void> _pick(Subscriber s) async {
    setState(() {
      _selected = s;
      _searchCtrl.text = s.fullName;
      _generating = true;
      _err = null;
    });
    final res = await TelegramApi.generateDeepLink(widget.adminId, s.idx!);
    if (!mounted) return;
    setState(() {
      _generating = false;
      _generatedLink = res.link;
      _err = res.link == null ? (res.message ?? 'فشل التوليد') : null;
    });
  }

  Future<void> _sendViaWa() async {
    if (_selected == null) return;
    setState(() => _sending = true);
    final res =
        await TelegramApi.sendLinkViaWa(widget.adminId, _selected!.idx!);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('أُرسل الرابط لـ${_selected!.fullName} عبر واتساب ✅',
            style: const TextStyle(fontFamily: AppType.family)),
        backgroundColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onDone();
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.message ?? 'فشل الإرسال',
            style: const TextStyle(fontFamily: AppType.family)),
        backgroundColor: AppColors.errorFill,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _reset() {
    setState(() {
      _selected = null;
      _generatedLink = null;
      _searchCtrl.clear();
      _err = null;
      _showQr = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.link,
        title: 'ربط مشترك',
        subtitle: 'ابحث عن المشترك ثم أرسل الرابط عبر واتساب',
        tint: AppColors.channelTelegram,
        tintBg: AppColors.channelTelegramSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          const SizedBox(height: 12),
          // ⚠️ حقل البحث سقط كاملاً عند نقل الشيت إلى القوقعة (602c357):
          // بقيت `_searchCtrl` تُقرأ في الفلترة وتُكتب عند الاختيار، بلا
          // أيّ ويدجت تربطها — فالشيت يعرض «ابدأ الكتابة» ولا مكان
          // للكتابة، ولا سبيل لاختيار مشترك أو توليد رابط إطلاقاً.
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, 0, Sp.xl, Sp.md),
            child: SheetSearchField(
              controller: _searchCtrl,
              hint: 'ابحث بالاسم أو اليوزر أو الهاتف',
              autofocus: true,
              onChanged: (_) {
                // السلوك قبل الهجرة: الكتابة بعد اختيار مشترك تُلغي
                // الاختيار وتعود للبحث.
                if (_selected != null) {
                  _reset();
                } else {
                  setState(() {});
                }
                if (_big) _bigSearchSoon();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _selected == null
                    ? _searchResults()
                    : _generatedView(),
          ),
          if (_selected != null && _generatedLink != null) _actionBar(),
        ],
      ),
    );
  }

  Widget _searchResults() {
    final matches = _matches;
    if (_searchCtrl.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('ابدأ الكتابة للبحث بين ${_big ? _bigTotal : _allSubs.length} مشترك',
              style: AppType.body(color: AppColors.textLow),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (matches.isEmpty && _big && _bigSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (matches.isEmpty) {
      return Center(
        child: Text('لا نتائج',
            style: AppType.body(color: AppColors.textLow)),
      );
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (_, i) {
        final s = matches[i];
        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: () => _pick(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.fullName,
                            style: TextStyle(
                              fontFamily: AppType.family,
                              fontSize: 13.5, height: 1.35,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [
                            '@${s.username}',
                            if (s.displayPhone.isNotEmpty) s.displayPhone,
                          ].join(' · '),
                          style: AppType.muted(color: AppColors.textMid),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronLeft,
                      size: 18, color: AppColors.textLow),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _generatedView() {
    if (_generating) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_err != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 40, color: AppColors.error),
            const SizedBox(height: 10),
            Text(_err!,
                style: AppType.body(color: AppColors.textMid),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المشترك',
                    style: TextStyle(
                      fontFamily: AppType.family,
                      fontSize: 10.5, height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLow,
                      letterSpacing: 0.5,
                    )),
                const SizedBox(height: 4),
                Text(_selected!.fullName,
                    style: AppType.buttonBold()),
                const SizedBox(height: 2),
                Text('@${_selected!.username}',
                    style: TextStyle(
                      fontFamily: AppType.family,
                      fontSize: 11, height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMid,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('رابط الربط',
                        style: TextStyle(
                          fontFamily: AppType.family,
                          fontSize: 10.5, height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textLow,
                          letterSpacing: 0.5,
                        )),
                    const Spacer(),
                    // 2026-08-26: toggle QR — للمشتركين اللي بلا واتساب.
                    InkWell(
                      onTap: () => setState(() => _showQr = !_showQr),
                      borderRadius: BorderRadius.circular(R.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _showQr
                              ? AppColors.channelTelegram.withValues(alpha: 0.14)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(R.sm),
                          border: Border.all(
                            color: _showQr
                                ? AppColors.channelTelegram
                                : AppColors.border,
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.qrCode,
                                size: 12,
                                color: _showQr
                                    ? AppColors.channelTelegram
                                    : AppColors.textMid),
                            const SizedBox(width: 4),
                            Text(_showQr ? 'إخفاء QR' : 'عرض QR',
                                style: AppType.pillBold(color: _showQr
                                      ? AppColors.channelTelegram
                                      : AppColors.textMid)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _generatedLink!,
                  textDirection: TextDirection.ltr,
                  style: AppType.bodyStrong(color: AppColors.textHi),
                ),
              ],
            ),
          ),
          if (_showQr) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                children: [
                  Center(
                    child: QrImageView(
                      data: _generatedLink!,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F1419),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F1419),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.info,
                          size: 12, color: AppColors.textMid),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'اعرض الشاشة على المشترك — يفتحه بكاميرا هاتفه',
                          style: TextStyle(
                            fontFamily: AppType.family,
                            fontSize: 10.5, height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid,
                          ),
                        ),
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

  Widget _actionBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await copyToClipboard(context, _generatedLink!,
                        label: 'رابط الربط');
                  },
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: const Text('نسخ',
                      style: TextStyle(
                        fontFamily: AppType.family,
                        fontSize: 13, height: 1.35,
                        fontWeight: FontWeight.w700,
                      )),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.channelTelegram,
                    side: BorderSide(
                        color: AppColors.channelTelegram.withValues(alpha: 0.5),
                        width: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.md)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: _sending ? null : _sendViaWa,
                  icon: _sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white))
                      : const Icon(LucideIcons.messageCircle, size: 16),
                  label: const Text('أرسل عبر واتساب',
                      style: TextStyle(
                        fontFamily: AppType.family,
                        fontSize: 13, height: 1.35,
                        fontWeight: FontWeight.w700,
                      )),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.channelWhatsApp,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.md)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
