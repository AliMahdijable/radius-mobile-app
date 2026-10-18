import 'dart:async';

import 'package:flutter/widgets.dart';

/// ما آلت إليه معاينة رابط صورة.
enum LinkImageState {
  /// الحقل فارغ — لا معاينة.
  none,

  /// الرابط يُحمَّل.
  loading,

  /// صورةٌ فعلاً.
  ok,

  /// ليس صورة: صفحة ويب (ibb.co · postimg.cc…)، رابطٌ ميّت، أو نصٌّ ليس رابطاً.
  broken,
}

/// معاينة رابط صورة تقول الحقيقة: الصورة إن كان الرابط صورةً، وإلّا
/// [LinkImageState.broken] فتعرض الشاشة «الرابط ليس صورة».
///
/// 🐛 تدقيق البوّابة ٢٠٢٦-١٠-١٧ (§2.6): 17 من 27 شعاراً و10 من 39 صورة باقة
/// لا تعمل — 13 منها صفحات ويب لا صور. والمعاينة كانت تُبدّل الفشل بأيقونة
/// الصورة نفسها التي يراها الحقل الفارغ، فيحفظ المدير رابطاً لا يراه مشتركٌ
/// ولا يعرف. والمعاينة بمحرّك الصور نفسه الذي يرسم به تطبيق المشترك.
///
/// والرابط يُطلب بعد توقّف الكتابة ([settle]) لا مع كلّ حرف: «h» ثمّ «ht»…
/// طلبٌ لكلّ حرفٍ ووميض «ليس صورة» تحت إصبع المدير. أوّل بناءٍ فوريّ (الرابط
/// المحفوظ يظهر حال فتح الشاشة)، والمسح فوريّ.
class LinkImagePreview extends StatefulWidget {
  const LinkImagePreview({
    super.key,
    required this.url,
    required this.size,
    required this.builder,
    this.fit = BoxFit.contain,
  });

  /// الرابط كما في الحقل (يُقصّ هنا).
  final String url;

  /// مقاس الصورة المربّع.
  final double size;
  final BoxFit fit;

  /// يرسم المعاينة كلّها: [image] الصورة بمقاسها حين تُحمَّل، وإلّا null.
  final Widget Function(
    BuildContext context,
    Widget? image,
    LinkImageState state,
  ) builder;

  /// مهلة التوقّف عن الكتابة قبل طلب الرابط.
  static const settle = Duration(milliseconds: 450);

  /// مصدر الصورة — منفذٌ للاختبار وحده (لا شبكة في `flutter test`).
  @visibleForTesting
  static ImageProvider Function(String url) imageFor = _network;
  static ImageProvider _network(String url) => NetworkImage(url);

  @override
  State<LinkImagePreview> createState() => _LinkImagePreviewState();
}

class _LinkImagePreviewState extends State<LinkImagePreview> {
  /// الرابط المعروض فعلاً — يلحق بـ`widget.url` بعد [LinkImagePreview.settle].
  late String _url = widget.url.trim();

  /// ما ينتظره المؤقّت — فإعادة بناءٍ لا تغيّر الرابط (كتابةٌ في حقل الاسم
  /// بجانبه) لا تؤجّله من جديد.
  String? _pending;
  Timer? _settle;

  @override
  void didUpdateWidget(covariant LinkImagePreview old) {
    super.didUpdateWidget(old);
    final next = widget.url.trim();
    if (next == _pending) return;
    _settle?.cancel();
    _pending = null;
    if (next == _url) return;
    if (next.isEmpty) {
      _url = next; // المسح فوريّ — لا طلب ينتظره
      return;
    }
    _pending = next;
    _settle = Timer(LinkImagePreview.settle, () {
      _pending = null;
      if (mounted) setState(() => _url = next);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url.isEmpty) return widget.builder(context, null, LinkImageState.none);
    // ليس رابط ويب أصلاً («logo.png» · «@name» · نصٌّ حرّ): لا طلب.
    if (!_isWebLink(url)) {
      return widget.builder(context, null, LinkImageState.broken);
    }
    return Image(
      key: ValueKey<String>(url), // حالةٌ جديدة لكلّ رابط — لا يرث خطأ سابقه
      image: LinkImagePreview.imageFor(url),
      width: widget.size,
      height: widget.size,
      fit: widget.fit,
      frameBuilder: (context, child, frame, _) => widget.builder(
        context,
        frame == null ? null : child,
        frame == null ? LinkImageState.loading : LinkImageState.ok,
      ),
      errorBuilder: (context, _, __) =>
          widget.builder(context, null, LinkImageState.broken),
    );
  }
}

bool _isWebLink(String s) {
  final u = Uri.tryParse(s);
  return u != null &&
      (u.scheme == 'https' || u.scheme == 'http') &&
      u.host.isNotEmpty;
}
