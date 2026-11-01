import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/national_more_api.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_more_widgets.dart';
import 'national_widgets.dart';

/// «الإشعارات والإعلانات» — المشروع الوطنيّ (١ نوفمبر، جرس البوّابة نفسه): الإشعارات (غير المقروءة بعلامة) والإعلانات (المثبّتة
/// أوّلاً) بنصٍّ عاديّ و«المزيد» للطويل، ورابط الإعلان يُفتح خارج التطبيق. **للقراءة وحدها: فتحها هنا لا يعلّمها مقروءةً في البوّابة**
/// (لا نداء «read» أبداً). بلا صلاحيّة البوّابة ⇒ قفلٌ هادئ بسببه لا «تعذّر». الخادم `/api/v2/ftth/notifications?tab=` (العقد §8).
class NationalNotesScreen extends StatefulWidget {
  const NationalNotesScreen({super.key, this.announcements = false});

  /// يفتح على «الإعلانات».
  final bool announcements;

  @override
  State<NationalNotesScreen> createState() => _NationalNotesScreenState();
}

class _NationalNotesScreenState extends State<NationalNotesScreen> {
  late bool _ann = widget.announcements;
  final Map<bool, NationalMoreResult<Object?>?> _locked = {false: null, true: null};
  final _p = NationalPaged<NationalNote>();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _reload() {
    _p.reset();
    _locked[_ann] = null;
    setState(() {});
    _next();
  }

  void _next() {
    final ann = _ann;
    _p.next(
      (page) async {
        final r = await NationalMoreApi.notes(announcements: ann, page: page);
        if (r.locked && mounted) _locked[ann] = r;
        return r.toResult();
      },
      onChange: () {
        if (mounted) setState(() {});
      },
      alive: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('الإشعارات والإعلانات', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('الإشعارات'), icon: Icon(LucideIcons.bell, size: 16)),
                  ButtonSegment(value: true, label: Text('الإعلانات'), icon: Icon(LucideIcons.megaphone, size: 16)),
                ],
                selected: {_ann},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _ann = s.first);
                  _reload();
                },
              ),
              const SizedBox(height: Sp.sm),
              Text('من جرس بوّابة المشروع الوطني — قراءتها هنا لا تعلّمها مقروءةً هناك',
                  style: AppType.micro(color: AppColors.textMid)),
              const SizedBox(height: Sp.md),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    final locked = _locked[_ann];
    if (_p.rows.isEmpty) {
      if (locked != null) return [NationalLockedBox(title: locked.lockTitle, text: locked.error ?? '')];
      if (_p.error != null) return [NationalStateBox.error(text: _p.error!, onRetry: _reload)];
      if (_p.pending) return [NationalStateBox.pending(text: _ann ? 'جارٍ جلب الإعلانات من البوّابة…' : 'جارٍ جلب الإشعارات من البوّابة…')];
      if (_p.loading || _p.page == 0) return const [NationalStateBox.loading()];
      return [
        NationalStateBox.empty(
          text: _ann ? 'لا توجد إعلانات' : 'لا توجد إشعارات',
          icon: _ann ? LucideIcons.megaphone : LucideIcons.bell,
        ),
      ];
    }
    return [
      for (final n in _p.rows) ...[
        _NoteCard(n: n, announcement: _ann),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: _ann ? 'إعلان' : 'إشعار'),
    ];
  }
}

class _NoteCard extends StatefulWidget {
  const _NoteCard({required this.n, required this.announcement});
  final NationalNote n;
  final bool announcement;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool _more = false;
  static const _clamp = 5;

  Future<void> _open(String link) async {
    final u = Uri.tryParse(link);
    final ok = u != null && await launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) showSheetSnack(context, 'تعذّر فتح الرابط', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final n = widget.n;
    final unread = !widget.announcement && n.unread;
    final bodyStyle = AppType.body(color: AppColors.textBody).copyWith(height: 1.55);
    return NationalCard(
      highlight: unread,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unread) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: Sp.sm),
              ],
              Expanded(
                child: Text(
                  n.title.isEmpty ? (widget.announcement ? 'إعلان' : 'إشعار') : n.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.cardTitle(color: AppColors.textHi),
                ),
              ),
              if (!widget.announcement && nationalNoteType(n.type) != null) ...[
                const SizedBox(width: Sp.sm),
                ToneChip(label: nationalNoteType(n.type)!, tone: AppTone.info, dense: true),
              ],
              if (widget.announcement && n.pinned) ...[
                const SizedBox(width: Sp.sm),
                const ToneChip(label: 'مثبّت', tone: AppTone.warning, icon: LucideIcons.pin, dense: true),
              ],
              if (unread) ...[
                const SizedBox(width: Sp.sm),
                const ToneChip(label: 'غير مقروء', tone: AppTone.brand, dense: true),
              ],
            ],
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            LayoutBuilder(builder: (context, c) {
              final tp = TextPainter(
                text: TextSpan(text: n.body, style: bodyStyle),
                maxLines: _clamp,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: c.maxWidth);
              final long = tp.didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    n.body,
                    maxLines: _more ? null : _clamp,
                    overflow: _more ? null : TextOverflow.ellipsis,
                    style: bodyStyle,
                  ),
                  if (long || _more)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(44, 36),
                        ),
                        onPressed: () => setState(() => _more = !_more),
                        child: Text(_more ? 'أقلّ' : 'المزيد'),
                      ),
                    ),
                ],
              );
            }),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: nationalMeta(LucideIcons.clock, nationalTime(n.at), ltr: true)),
              if (n.link != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(44, 36),
                  ),
                  onPressed: () => _open(n.link!),
                  icon: const Icon(LucideIcons.externalLink, size: 15),
                  label: Text(widget.announcement ? 'اقرأ المقال كاملاً' : 'فتح الرابط', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
