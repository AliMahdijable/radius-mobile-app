part of 'sales_screen.dart';

// ═══════════════════════════ «المتجر» (٢٣ نوفمبر) ═══════════════════════════
//
// تبويبٌ في «المبيعات» (المالك: «الوكيل يختار منتجات من مخزونه الي بالمبيعات يعرضهن ويحطلهن صور ووصف ويظهرن بتطبيق المتشرك
// ويكدر المشترك يطلب شراء ايضا»). فوق: طلبات المشتركين (الجديدة والمقبولة، و«الكلّ» لما مضى) — «بيع» يفتح نافذة البيع المعتادة
// معبّأةً ([_SalesScreenState._sellStoreOrder]) و«قبول» و«رفض» بسببٍ يصل المشترك و«تمّ التسليم». تحت: موادّ المخزون — مفتاح «اعرضها
// بالمتجر» و«تعديل» (الوصف والصور حتى ٣ وسعر العرض) بمعاينةٍ كما يراها المشترك. ما لا يملكه الموظّف بمكانه مقفلاً. لا مال هنا.
// «المتجر: الدفع» (٢٥ نوفمبر): الطلب يقول طريقة دفع المشترك (كاش عند الاستلام / حوالة زين كاش / حوالة ماستر) و«صورة الحوالة» تفتحها.

/// للاختبار: بدل معرض الهاتف في «إضافة صورة».
@visibleForTesting
PackageImagePicker? storeImagePickerForTest;

const _kStoreOrderStatus = <String, ({String label, AppTone tone, RpTone icon})>{
  'pending': (label: 'جديد', tone: AppTone.warning, icon: RpTone.debt),
  'accepted': (label: 'مقبول', tone: AppTone.info, icon: RpTone.info),
  'done': (label: 'تمّ', tone: AppTone.success, icon: RpTone.money),
  'rejected': (label: 'مرفوض', tone: AppTone.danger, icon: RpTone.loss),
  'cancelled': (label: 'ألغاه المشترك', tone: AppTone.brand, icon: RpTone.neutral),
  'expired': (label: 'انتهى', tone: AppTone.brand, icon: RpTone.neutral),
};

({String label, AppTone tone}) _listingLabel(StoreItem it) => switch (storeListingState(it)) {
      StoreListingState.notListed => (label: 'غير معروضة', tone: AppTone.brand),
      StoreListingState.hidden => (label: 'مخفيّة', tone: AppTone.brand),
      StoreListingState.inactive => (label: 'موقوفة بالمخزون', tone: AppTone.warning),
      StoreListingState.soldOut => (label: 'معروضة — نفدت', tone: AppTone.warning),
      StoreListingState.listed => (label: 'معروضة', tone: AppTone.success),
    };

/// إطار بطاقةٍ كبطاقات القسم: سطح، حدّ، زوايا.
BoxDecoration _storeCardBox() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      border: Border.all(color: AppColors.border),
    );

class _StoreTab extends StatefulWidget {
  const _StoreTab({
    required this.view,
    required this.canItems,
    required this.canSell,
    required this.refreshTick,
    required this.onSell,
    required this.onChanged,
    this.lockMessage,
  });
  final StoreView view;

  /// `sales.items` والقسم مفعّل.
  final bool canItems;

  /// `sales.sell` والقسم مفعّل.
  final bool canSell;

  /// سبب القفل إن لم يكن الصلاحيّة («المبيعات موقوفة»).
  final String? lockMessage;

  /// يتغيّر بسحب التحديث وبعد كلّ بيع ⇒ الطلبات تُقرأ من جديد.
  final int refreshTick;
  final void Function(StoreOrder o) onSell;

  /// تغيّر شيءٌ هنا ⇒ الصفحة تقرأ المتجر (الموادّ والأعداد).
  final VoidCallback onChanged;

  @override
  State<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<_StoreTab> {
  bool _all = false;
  List<StoreOrder>? _orders;
  StoreCounts? _counts;
  String? _error;
  bool _loading = true;

  /// فعلٌ جارٍ: `accept:12` · `done:12` · `vis:5` — لا فعلان معاً.
  String? _busy;
  int _seq = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // طلبٌ جديد والتبويب مفتوح ⇒ يظهر خلال دقيقة (والإشعار يصل فوراً)
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_load(quiet: true)));
  }

  @override
  void didUpdateWidget(covariant _StoreTab old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) unawaited(_load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final seq = ++_seq;
    if (!quiet && _orders == null) setState(() => _loading = true);
    final r = await PortalStoreApi.orders(all: _all);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (r.orders != null) {
        _orders = r.orders;
        _counts = r.counts;
        _error = null;
      } else if (_orders == null) {
        _error = r.error;
      }
    });
  }

  void _setAll(bool all) {
    if (all == _all) return;
    setState(() {
      _all = all;
      _orders = null;
      _loading = true;
    });
    unawaited(_load());
  }

  void _changed() {
    widget.onChanged();
    unawaited(_load(quiet: true));
  }

  Future<void> _act(StoreOrder o, String kind) async {
    if (_busy != null) return;
    setState(() => _busy = '$kind:${o.id}');
    final r = kind == 'accept' ? await PortalStoreApi.accept(o.id) : await PortalStoreApi.done(o.id);
    if (!mounted) return;
    setState(() => _busy = null);
    showSheetSnack(
      context,
      r.ok ? (kind == 'accept' ? 'قُبل الطلب — أُبلغ المشترك' : 'تمّ — أُبلغ المشترك') : (r.message ?? 'sales.not_saved'.tr()),
      isError: !r.ok,
    );
    _changed();
  }

  Future<void> _toggle(StoreItem it, bool v) async {
    if (_busy != null || !widget.canItems) return;
    setState(() => _busy = 'vis:${it.itemId}');
    final r = await PortalStoreApi.saveItem(it.itemId, visible: v);
    if (!mounted) return;
    setState(() => _busy = null);
    showSheetSnack(
      context,
      r.ok ? (v ? '«${it.name}» معروضةٌ لمشتركيك' : '«${it.name}» مخفيّة') : (r.message ?? 'sales.not_saved'.tr()),
      isError: !r.ok,
    );
    _changed();
  }

  Future<void> _reject(StoreOrder o) async {
    if (_busy != null) return;
    final done = await _showSheet(context, _StoreRejectSheet(order: o));
    if (done == true && mounted) _changed();
  }

  Future<void> _edit(StoreItem it) async {
    final changed = await _showSheet(
      context,
      _StoreItemSheet(item: it, imagesMax: widget.view.imagesMax, descMax: widget.view.descMax),
    );
    if (changed == true && mounted) _changed();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final view = widget.view;
    return Column(
      key: const ValueKey('store-tab'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!view.available) ...[
          const _Banner(icon: LucideIcons.store, text: '«متجر الوكيل» موقوفٌ لحسابك الآن — ما تراه للعرض فقط'),
          const SizedBox(height: Sp.md),
        ],
        _ordersCard(),
        const SizedBox(height: Sp.md),
        _itemsCard(view),
      ],
    );
  }

  Widget _cardHeader({required String title, required String sub, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.sm),
      child: Wrap(
        spacing: Sp.sm,
        runSpacing: Sp.sm,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.45)),
            ],
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _ordersCard() {
    final counts = _counts ?? widget.view.counts;
    final orders = _orders;
    final Widget body;
    if (_loading && orders == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.xl),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    } else if (orders == null) {
      body = _StoreEmpty(text: _error ?? 'تعذّر جلب الطلبات', retry: () => unawaited(_load()));
    } else if (orders.isEmpty) {
      body = _StoreEmpty(text: _all ? 'لا طلبات خلال الشهرين الماضيين' : 'لا طلبات مفتوحة الآن');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < orders.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.border),
            _StoreOrderTile(
              order: orders[i],
              busy: _busy,
              canSell: widget.canSell,
              lockMessage: widget.lockMessage,
              onSell: () => widget.onSell(orders[i]),
              onAccept: () => unawaited(_act(orders[i], 'accept')),
              onDone: () => unawaited(_act(orders[i], 'done')),
              onReject: () => unawaited(_reject(orders[i])),
            ),
          ],
        ],
      );
    }
    return Container(
      key: const ValueKey('store-orders'),
      decoration: _storeCardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(
            title: 'طلبات المشتركين',
            sub: counts.open > 0
                ? '${counts.pending} جديد · ${counts.accepted} مقبول بانتظار البيع'
                : 'لا طلبات مفتوحة — كلّ طلبٍ يصلك إشعاراً',
            trailing: Wrap(
              spacing: Sp.x6,
              children: [
                SheetQuickChip(key: const ValueKey('store-orders-open'), label: 'المفتوحة', selected: !_all, onTap: () => _setAll(false)),
                SheetQuickChip(key: const ValueKey('store-orders-all'), label: 'الكلّ', selected: _all, onTap: () => _setAll(true)),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          Padding(padding: const EdgeInsets.symmetric(horizontal: Sp.md), child: body),
        ],
      ),
    );
  }

  Widget _itemsCard(StoreView view) {
    final listed = view.listedCount;
    return Container(
      key: const ValueKey('store-items'),
      decoration: _storeCardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(
            title: 'موادّ المتجر',
            sub: listed > 0 ? '$listed معروضة لمشتركيك' : 'اختر ما يظهر لمشتركيك في تطبيقهم وبوّابتهم — بصوره ووصفه وسعره',
          ),
          Divider(height: 1, color: AppColors.border),
          if (view.items.isEmpty)
            const _StoreEmpty(text: 'أضف موادّك أوّلاً من «الموادّ والمخزون»')
          else
            for (int i = 0; i < view.items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.border, indent: Sp.md, endIndent: Sp.md),
              _StoreItemRow(
                item: view.items[i],
                canItems: widget.canItems,
                lockMessage: widget.lockMessage,
                busy: _busy == 'vis:${view.items[i].itemId}',
                anyBusy: _busy != null,
                onEdit: () => unawaited(_edit(view.items[i])),
                onToggle: (v) => unawaited(_toggle(view.items[i], v)),
              ),
            ],
        ],
      ),
    );
  }
}

class _StoreEmpty extends StatelessWidget {
  const _StoreEmpty({required this.text, this.retry});
  final String text;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.lg, horizontal: Sp.md),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13, height: 1.5)),
          if (retry != null)
            TextButton.icon(
              onPressed: retry,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
              label: Text('common.retry'.tr()),
            ),
        ],
      ),
    );
  }
}

class _StoreOrderTile extends StatelessWidget {
  const _StoreOrderTile({
    required this.order,
    required this.busy,
    required this.canSell,
    required this.onSell,
    required this.onAccept,
    required this.onDone,
    required this.onReject,
    this.lockMessage,
  });
  final StoreOrder order;
  final String? busy;
  final bool canSell;
  final String? lockMessage;
  final VoidCallback onSell;
  final VoidCallback onAccept;
  final VoidCallback onDone;
  final VoidCallback onReject;

  Future<void> _openReceipt(BuildContext context, StoreOrder o) async {
    final r = await PortalStoreApi.receipt(o.id);
    if (!context.mounted) return;
    final b = r.bytes;
    if (b == null) {
      showSheetSnack(context, r.gone ? 'لا صورة حوالة لهذا الطلب (تُحفظ ٦٠ يوماً)' : 'تعذّر جلب صورة الحوالة — حاول مرّة ثانية',
          isError: !r.gone);
      return;
    }
    openTransferImageViewer(context, b, 'صورة الحوالة — ${o.who}');
  }

  Future<void> _call(BuildContext context, String phone) async {
    try {
      final ok = await launchUrl(Uri(scheme: 'tel', path: phone.trim()));
      if (!ok && context.mounted) showSheetSnack(context, 'تعذّر فتح الاتّصال', isError: true);
    } catch (_) {
      if (context.mounted) showSheetSnack(context, 'تعذّر فتح الاتّصال', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final o = order;
    final st = _kStoreOrderStatus[o.status] ?? _kStoreOrderStatus['expired']!;
    final mine = busy != null && busy!.endsWith(':${o.id}');
    final meta = AppType.micro(color: AppColors.textMid);
    final user = (o.subUsername ?? '').trim();
    final phone = (o.subPhone ?? '').trim();
    return Padding(
      key: ValueKey('store-order-${o.id}'),
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RpIconBox(icon: LucideIcons.shoppingBag, tone: st.icon, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الاسم كاملاً (يلتفّ) — والعدد في سطره: لا يلتصق رقمٌ باسمٍ لاتينيّ
                    Text(iso(o.name), style: AppType.bodyBold(color: AppColors.textHi)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: Sp.x6,
                      runSpacing: 2,
                      children: [
                        Text('العدد ${_qty(o.qty)}', style: meta),
                        Text('·', style: meta),
                        Text(_money(o.total), style: meta.copyWith(color: AppColors.textHi, fontWeight: FontWeight.w700)),
                        if (o.createdAt != null) ...[
                          Text('·', style: meta),
                          Text(_time(o.createdAt), style: meta),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              _Chip(st.label, st.tone),
            ],
          ),
          const SizedBox(height: Sp.x6),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 36 + Sp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Sp.md,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.user, size: 13, color: AppColors.textMid),
                        const SizedBox(width: 4),
                        Flexible(child: Text(iso(o.who), style: AppType.body(color: AppColors.textBody).copyWith(fontSize: 13))),
                      ],
                    ),
                    if (user.isNotEmpty && user != o.who) Text(iso(user), style: meta),
                    if (phone.isNotEmpty)
                      InkWell(
                        key: ValueKey('store-order-call-${o.id}'),
                        borderRadius: BorderRadius.circular(R.sm),
                        onTap: () => unawaited(_call(context, phone)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.phone, size: 13, color: AppColors.brand),
                              const SizedBox(width: 4),
                              Text(iso(phone), style: meta.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if ((o.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: Sp.x6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: Sp.x6),
                    decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
                    child: Text('«${o.note}»', style: AppType.body(color: AppColors.textBody).copyWith(fontSize: 12.5, height: 1.5)),
                  ),
                ],
                if (o.payLabel != null) ...[
                  const SizedBox(height: Sp.x6),
                  Wrap(
                    spacing: Sp.md,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(o.isTransfer ? LucideIcons.creditCard : LucideIcons.banknote, size: 13, color: AppColors.textMid),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('الدفع: ${o.payLabel}',
                                key: ValueKey('store-order-pay-${o.id}'),
                                style: meta.copyWith(color: AppColors.textBody, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      if (o.hasReceipt)
                        InkWell(
                          key: ValueKey('store-receipt-${o.id}'),
                          borderRadius: BorderRadius.circular(R.sm),
                          onTap: () => unawaited(_openReceipt(context, o)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.image, size: 13, color: AppColors.brand),
                                const SizedBox(width: 4),
                                Text('صورة الحوالة', style: meta.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (o.status == 'rejected' && (o.reason ?? '').isNotEmpty) ...[
                  const SizedBox(height: Sp.x6),
                  Text('السبب: ${o.reason}', style: meta.copyWith(color: AppColors.error)),
                ],
                if (o.status == 'done') ...[
                  const SizedBox(height: Sp.x6),
                  Text(
                    [o.saleId != null ? 'بيع #${o.saleId}' : 'تمّ التسليم', if ((o.decidedBy ?? '').isNotEmpty) o.decidedBy!].join(' · '),
                    style: meta,
                  ),
                ],
                if (o.isOpen) ...[
                  const SizedBox(height: Sp.sm),
                  IgnorePointer(
                    ignoring: busy != null,
                    child: Opacity(
                      opacity: busy != null && !mine ? 0.55 : 1,
                      child: Wrap(
                        spacing: Sp.sm,
                        runSpacing: Sp.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _ActionButton(
                            key: ValueKey('store-sell-${o.id}'),
                            label: 'بيع',
                            icon: LucideIcons.shoppingCart,
                            tone: AppTone.brand,
                            locked: !canSell,
                            lockMessage: lockMessage,
                            onTap: onSell,
                            dense: true,
                          ),
                          if (o.isPending)
                            _ActionButton(
                              key: ValueKey('store-accept-${o.id}'),
                              label: 'قبول',
                              icon: LucideIcons.check,
                              tone: AppTone.success,
                              locked: !canSell,
                              lockMessage: lockMessage,
                              onTap: onAccept,
                              dense: true,
                            ),
                          if (o.isAccepted)
                            _ActionButton(
                              key: ValueKey('store-done-${o.id}'),
                              label: 'تمّ التسليم',
                              icon: LucideIcons.packageCheck,
                              tone: AppTone.info,
                              locked: !canSell,
                              lockMessage: lockMessage,
                              onTap: onDone,
                              dense: true,
                            ),
                          _ActionButton(
                            key: ValueKey('store-reject-${o.id}'),
                            label: 'رفض',
                            icon: LucideIcons.x,
                            tone: AppTone.danger,
                            locked: !canSell,
                            lockMessage: lockMessage,
                            onTap: onReject,
                            dense: true,
                          ),
                          if (mine) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// صورة مادّةٍ من خادمنا — والمكان بأيقونةٍ إن لم تكن أو تعذّرت.
class _StoreThumb extends StatelessWidget {
  const _StoreThumb({required this.url, required this.size, this.radius = R.md, this.iconSize = 20});
  final String? url;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ph = Container(
      color: AppColors.surfaceSunken,
      alignment: Alignment.center,
      child: Icon(LucideIcons.package, size: iconSize, color: AppColors.textLow),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? ph
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => ph,
                loadingBuilder: (context, child, p) => p == null ? child : ph,
              ),
      ),
    );
  }
}

class _StoreItemRow extends StatelessWidget {
  const _StoreItemRow({
    required this.item,
    required this.canItems,
    required this.busy,
    required this.anyBusy,
    required this.onEdit,
    required this.onToggle,
    this.lockMessage,
  });
  final StoreItem item;
  final bool canItems;
  final bool busy;
  final bool anyBusy;
  final String? lockMessage;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = item;
    final st = _listingLabel(it);
    final meta = AppType.micro(color: AppColors.textMid);
    final img = it.listing?.images.isNotEmpty == true ? it.listing!.images.first.absoluteUrl : null;
    // إظهار مادّةٍ موقوفة بالمخزون لا يُسمح (الخادم يرفضه) — إخفاؤها مسموح
    final canFlip = canItems && !anyBusy && (it.active || it.visible);
    return Padding(
      key: ValueKey('store-item-${it.itemId}'),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
      child: Row(
        children: [
          _StoreThumb(url: img, size: 48),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(iso(it.name), style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: Sp.x6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(_money(it.shownPrice), style: meta.copyWith(color: AppColors.textHi, fontWeight: FontWeight.w700)),
                    Text('·', style: meta),
                    Text(it.qtyOnHand > 0 ? 'بالمخزون ${_qty(it.qtyOnHand)}' : 'نفد', style: meta),
                    _Chip(st.label, st.tone),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.x6),
          Tooltip(
            message: 'تعديل بالمتجر',
            child: InkWell(
              key: ValueKey('store-edit-${it.itemId}'),
              borderRadius: BorderRadius.circular(R.md),
              onTap: canItems ? onEdit : () => showNoPermission(context, action: true, message: lockMessage),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  canItems ? LucideIcons.pencil : LucideIcons.lock,
                  size: 17,
                  color: canItems ? AppColors.textBody : LockedStyle.glyph,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: busy
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : GestureDetector(
                    // مقفلٌ بمكانه: لمسه يقول السبب (لا مفتاحٌ ميّتٌ صامت)
                    onTap: canItems ? null : () => showNoPermission(context, action: true, message: lockMessage),
                    child: AbsorbPointer(
                      absorbing: !canItems,
                      child: Switch(
                        key: ValueKey('store-visible-${it.itemId}'),
                        value: it.visible,
                        activeThumbColor: AppColors.brand,
                        onChanged: canFlip ? onToggle : null,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── تعديل المادّة بالمتجر ───

class _StoreItemSheet extends StatefulWidget {
  const _StoreItemSheet({required this.item, required this.imagesMax, required this.descMax});
  final StoreItem item;
  final int imagesMax;
  final int descMax;

  @override
  State<_StoreItemSheet> createState() => _StoreItemSheetState();
}

class _StoreItemSheetState extends State<_StoreItemSheet> {
  late StoreItem _cur = widget.item;
  late final _desc = TextEditingController(text: widget.item.listing?.description ?? '');
  late final _price = TextEditingController(
    text: widget.item.listing?.price == null ? '' : AmountShorthand.format(widget.item.listing!.price!),
  );
  late int _priceValue = widget.item.listing?.price ?? 0;
  late bool _visible = widget.item.listing?.visible ?? true;

  /// `save` · `img` · رقم صورةٍ تُحذف.
  Object? _busy;

  /// رُفعت صورةٌ أو حُذفت (تُحفظ فوراً) ⇒ الصفحة تتحدّث ولو أُغلقت النافذة بلا «حفظ».
  bool _dirty = false;

  bool get _meter => _cur.unit == 'متر';
  int get _descLen => _desc.text.characters.length;
  bool get _descOk => _descLen <= widget.descMax;
  bool get _priceEmpty => _price.text.trim().isEmpty;
  bool get _priceOk => _priceEmpty || _priceValue > 0;
  int get _shown => !_priceEmpty && _priceValue > 0 ? _priceValue : _cur.salePrice;
  List<StoreImage> get _images => _cur.listing?.images ?? const [];

  @override
  void dispose() {
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  void _close() {
    if (_busy != null) return;
    Navigator.of(context).pop(_dirty);
  }

  Future<void> _save() async {
    if (_busy != null || !_descOk || !_priceOk) return;
    setState(() => _busy = 'save');
    final r = await PortalStoreApi.saveItem(
      _cur.itemId,
      visible: _visible,
      description: _desc.text.trim(),
      setPrice: true,
      price: _priceEmpty ? null : _priceValue,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
      return;
    }
    showSheetSnack(context, _visible ? 'حُفظ — يراها مشتركوك هكذا' : 'حُفظ — مخفيّة عن مشتركيك');
    Navigator.of(context).pop(true);
  }

  Future<void> _addImage() async {
    if (_busy != null) return;
    setState(() => _busy = 'img');
    try {
      final picked = await (storeImagePickerForTest ?? pickPackageImage)();
      if (picked == null) return;
      final r = await PortalStoreApi.addImage(_cur.itemId, picked.image.dataUrl);
      if (!mounted) return;
      if (r.ok && r.item != null) {
        setState(() {
          _cur = r.item!;
          _dirty = true;
        });
      } else {
        showSheetSnack(context, r.message ?? 'تعذّر رفع الصورة', isError: true);
      }
    } on PackageImageError catch (e) {
      if (mounted) {
        showSheetSnack(context, e.reason == 'too-big' ? 'الصورة كبيرة حتى بعد الضغط — اختر غيرها' : 'تعذّر قراءة الصورة — اختر غيرها',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _removeImage(StoreImage im) async {
    if (_busy != null) return;
    setState(() => _busy = im.id);
    final r = await PortalStoreApi.removeImage(im.id);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (r.ok && r.item != null) {
        _cur = r.item!;
        _dirty = true;
      }
    });
    if (!r.ok) showSheetSnack(context, r.message ?? 'تعذّر حذف الصورة', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final it = _cur;
    final avail = it.availableToSubscriber;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.store,
          title: 'المادّة بالمتجر',
          subtitle: it.name,
          subtitleMaxLines: 3,
          onClose: _close,
        ),
        footer: SheetFooterBar(
          label: 'sales.save'.tr(),
          icon: LucideIcons.check,
          enabled: _busy == null && _descOk && _priceOk,
          busy: _busy == 'save',
          onPressed: _save,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اعرضها بالمتجر', style: AppType.label(color: AppColors.textHi)),
                      Text(
                        it.active ? 'يراها مشتركوك في «متجر وكيلي» بتطبيقهم وبوّابتهم' : 'موقوفة بالمخزون — فعّلها من «الموادّ والمخزون» لتُعرض',
                        style: AppType.muted(color: it.active ? AppColors.textMid : AppTone.warning.onSoft).copyWith(fontSize: 11.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Switch(
                  key: const ValueKey('store-sheet-visible'),
                  value: _visible,
                  activeThumbColor: AppColors.brand,
                  onChanged: _busy != null || (!it.active && !_visible) ? null : (v) => setState(() => _visible = v),
                ),
              ],
            ),
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'الصور',
              footnote: '${_images.length} من ${widget.imagesMax} — تُضغط على هاتفك قبل الرفع',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final im in _images)
                    Stack(
                      key: ValueKey('store-sheet-img-${im.id}'),
                      children: [
                        _StoreThumb(url: im.absoluteUrl, size: 88, radius: R.lg, iconSize: 24),
                        PositionedDirectional(
                          top: 4,
                          end: 4,
                          child: Material(
                            color: AppColors.scrim,
                            shape: const CircleBorder(),
                            child: InkWell(
                              key: ValueKey('store-sheet-img-del-${im.id}'),
                              customBorder: const CircleBorder(),
                              onTap: _busy == null ? () => unawaited(_removeImage(im)) : null,
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child: _busy == im.id
                                    ? const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                                      )
                                    : const Icon(LucideIcons.trash2, size: 15, color: AppColors.onBrand),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (_images.length < widget.imagesMax)
                    InkWell(
                      key: const ValueKey('store-sheet-add-img'),
                      borderRadius: BorderRadius.circular(R.lg),
                      onTap: _busy == null ? () => unawaited(_addImage()) : null,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(R.lg),
                          border: Border.all(color: AppColors.borderStrong),
                          color: AppColors.surfaceSunken,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _busy == 'img'
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(LucideIcons.imagePlus, size: 20, color: AppColors.textMid),
                            const SizedBox(height: 4),
                            Text('إضافة صورة', textAlign: TextAlign.center, style: AppType.micro(color: AppColors.textMid)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'الوصف',
              footnote: '$_descLen / ${widget.descMax}',
              child: SheetBox(
                icon: LucideIcons.fileText,
                alignTop: true,
                borderColor: _descOk ? null : AppColors.error,
                child: TextField(
                  key: const ValueKey('store-sheet-desc'),
                  controller: _desc,
                  minLines: 3,
                  maxLines: 8,
                  style: AppType.input(),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'مثلاً: راوتر ثنائي النطاق، ضمان سنة، يغطّي بيتاً من طابقين',
                    hintMaxLines: 3,
                    hintStyle: AppType.input(color: AppColors.textPlaceholder),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'سعر العرض',
              footnote: 'فارغ = سعر البيع بالمخزون (${_money(it.salePrice)}). البيع نفسه بالسعر الذي تختاره عند «بيع».',
              child: KeyedSubtree(
                key: const ValueKey('store-sheet-price'),
                child: _MoneyField(
                  controller: _price,
                  shorthand: !_meter,
                  onValue: (v) => setState(() => _priceValue = v),
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),
            SheetSection(
              label: 'كما يراها المشترك',
              child: Container(
                key: const ValueKey('store-sheet-preview'),
                decoration: _storeCardBox(),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (_, c) => _StoreThumb(
                          url: _images.isEmpty ? null : _images.first.absoluteUrl,
                          size: c.maxWidth,
                          radius: 0,
                          iconSize: 30,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Sp.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: Sp.sm,
                            runSpacing: 4,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(iso(it.name), style: AppType.bodyBold(color: AppColors.textHi)),
                              Text(_money(_shown), style: AppType.bodyStrong(color: AppColors.brand)),
                            ],
                          ),
                          const SizedBox(height: Sp.x6),
                          _Chip(avail ? 'متوفّر' : 'نفد', avail ? AppTone.success : AppTone.brand),
                          if (_desc.text.trim().isNotEmpty) ...[
                            const SizedBox(height: Sp.x6),
                            Text(_desc.text.trim(), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.55)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── رفض الطلب ───

class _StoreRejectSheet extends StatefulWidget {
  const _StoreRejectSheet({required this.order});
  final StoreOrder order;

  @override
  State<_StoreRejectSheet> createState() => _StoreRejectSheetState();
}

class _StoreRejectSheetState extends State<_StoreRejectSheet> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await PortalStoreApi.reject(widget.order.id, _reason.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'sales.not_saved'.tr(), isError: true);
      return;
    }
    showSheetSnack(context, 'رُفض الطلب — أُبلغ المشترك بالسبب');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final o = widget.order;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.x,
        tint: AppTone.danger.fill,
        tintBg: AppTone.danger.softBg,
        title: 'رفض الطلب',
        subtitle: '${o.name} — العدد ${_qty(o.qty)} — ${o.who}',
        subtitleMaxLines: 3,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'رفض وإبلاغ المشترك',
        icon: LucideIcons.x,
        color: AppTone.danger.fill,
        busy: _busy,
        onPressed: _submit,
      ),
      body: SheetSection(
        label: 'السبب (يصل المشترك)',
        footnote: 'اختياريّ — حتى ١٦٠ حرفاً',
        child: SheetBox(
          icon: LucideIcons.messageSquare,
          alignTop: true,
          child: TextField(
            key: const ValueKey('store-reject-reason'),
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            maxLength: 160,
            style: AppType.input(),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: 'مثلاً: نفدت الكمّيّة هذا الأسبوع',
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
            ),
          ),
        ),
      ),
    );
  }
}

/// «طلب شراء من المتجر» (إشعار `store_order`) ⇒ «المبيعات» على «المتجر» للصفحة المفتوحة.
Future<bool> openStoreOrderPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'store_order') return false;
  await nav.push(MaterialPageRoute(builder: (_) => const SalesScreen(openStore: true)));
  return true;
}
