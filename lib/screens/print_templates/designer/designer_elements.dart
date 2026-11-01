import 'package:flutter/foundation.dart';

import '../../../services/receipt_layout.dart';
import 'controls.dart';
import 'designer_controller.dart';

enum DesignerElType { container, field, section, sale }

/// عنصرٌ في «العناصر»: معرّفه ونوعه واسمه وعمقه (صفٌّ تحت حاويته أو قسمه).
@immutable
class DesignerElement {
  const DesignerElement(this.id, this.type, {this.depth = 0});

  final String id;
  final DesignerElType type;
  final int depth;

  String get name => designerElementNames[id] ?? id;
}

/// أسماء العناصر كما يقرؤها الوكيل.
const Map<String, String> designerElementNames = {
  'logo': 'الشعار',
  'shop_name': 'اسم المحلّ',
  'shop_lines': 'العنوان والهاتف',
  'shop_address': 'العنوان',
  'shop_phone': 'هاتف المحلّ',
  'title': 'عنوان الوصل',
  'meta': 'الرقم والتاريخ',
  'receipt_no': 'رقم الوصل',
  'issued_at': 'التاريخ والوقت',
  'subscriber': 'قسم المشترك',
  'package': 'قسم الباقة',
  'transaction': 'قسم المعاملة',
  'subscriber_name': 'اسم المشترك',
  'username': 'اسم المستخدم',
  'phone': 'هاتف المشترك',
  'package_name': 'اسم الباقة',
  'package_price': 'سعر الباقة',
  'expiry_date': 'تاريخ الانتهاء',
  'days_remaining': 'الأيام المتبقّية',
  'payment_type': 'طريقة الدفع',
  'amount': 'المبلغ',
  'cash_paid': 'المدفوع نقداً',
  'balance_debt': 'الدين المتبقّي',
  'balance_credit': 'الرصيد المتبقّي',
  'qr': 'رمز QR',
  'qr_caption': 'التعليق تحت الرمز',
  'footer': 'الذيل',
  'issuer': 'أصدره',
  'footer_text': 'نصّ الذيل',
  'sale_customer': 'الزبون',
  'sale_items': 'المواد',
  'sale_totals': 'المجموع وطريقة الدفع',
};

/// مفتاح v1 الذي يُظهر العنصر (حين لا يكون `fields[id].show`).
const Map<String, String> _v1Show = {
  'logo': 'show_logo',
  'shop_lines': 'show_shop_info',
  'receipt_no': 'show_receipt_id',
  'issued_at': 'show_datetime',
  'subscriber': 'show_subscriber_info',
  'package': 'show_package_info',
  'transaction': 'show_transaction_info',
  'package_price': 'show_package_price',
  'footer': 'show_footer',
  'issuer': 'show_manager_signature',
};

/// أنواع الوصل التي تظهر فيها الحاويات والأقسام.
const Map<String, List<String>> _blockKinds = {
  'logo': receiptKinds,
  'shop_lines': receiptKinds,
  'meta': receiptKinds,
  'qr': ['activation', 'extension', 'payment', 'info'],
  'footer': receiptKinds,
  'subscriber': ['activation', 'extension', 'payment', 'info'],
  'package': ['activation', 'extension', 'payment', 'info'],
  'transaction': ['activation', 'extension', 'payment', 'info'],
  'sale_customer': ['sale'],
  'sale_items': ['sale'],
  'sale_totals': ['sale'],
};

extension DesignerElements on ReceiptDesignController {
  /// العناصر بترتيب الطباعة (الحاويات وصفوفها، والأقسام وصفوفها)، ثمّ أقسام فاتورة البيع.
  /// [qrAvailable] false (ايرث لنك، فايبر اكس، الشركات المُضافة) ⇒ لا QR ولا تعليقه.
  List<DesignerElement> elements({required bool qrAvailable}) {
    final out = <DesignerElement>[];
    const c = DesignerElType.container;
    const f = DesignerElType.field;
    for (final b in blockOrder) {
      switch (b) {
        case 'logo':
          out.add(const DesignerElement('logo', c));
        case 'shop_name':
          out.add(const DesignerElement('shop_name', f));
        case 'shop_lines':
          out
            ..add(const DesignerElement('shop_lines', c))
            ..add(const DesignerElement('shop_address', f, depth: 1))
            ..add(const DesignerElement('shop_phone', f, depth: 1));
        case 'title':
          out.add(const DesignerElement('title', f));
        case 'meta':
          out
            ..add(const DesignerElement('meta', c))
            ..add(const DesignerElement('receipt_no', f, depth: 1))
            ..add(const DesignerElement('issued_at', f, depth: 1));
        case 'body':
          final rows = rowOrder;
          for (final s in bodyOrder) {
            out.add(DesignerElement(s, DesignerElType.section));
            for (final r in rows[s]!) {
              if (receiptReservedFieldIds.contains(r)) continue;
              out.add(DesignerElement(r, f, depth: 1));
            }
          }
        case 'qr':
          // ايرث لنك وفايبر اكس والشركات المُضافة: لا QR على وصلها — ملاحظةٌ مكانه.
          if (!qrAvailable) {
            out.add(const DesignerElement('qr_note', c));
            continue;
          }
          out
            ..add(const DesignerElement('qr', c))
            ..add(const DesignerElement('qr_caption', f, depth: 1));
        case 'footer':
          out
            ..add(const DesignerElement('footer', c))
            ..add(const DesignerElement('issuer', f, depth: 1))
            ..add(const DesignerElement('footer_text', f, depth: 1));
      }
    }
    for (final s in const ['sale_customer', 'sale_items', 'sale_totals']) {
      out.add(DesignerElement(s, DesignerElType.sale));
    }
    return out;
  }

  /// خصائص العنصر في `layout` (حقل/قسم/حاوية) — نسخة.
  Map<String, dynamic> styleOf(String id) {
    final l = layout;
    final bucket = receiptFieldCaps.containsKey(id)
        ? 'fields'
        : receiptSectionCaps.containsKey(id)
            ? 'sections'
            : 'blocks';
    final m = l?[bucket];
    final s = m is Map ? m[id] : null;
    return s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{};
  }

  /// يرقّع خصائص العنصر في مكانها الصحيح.
  void setStyle(String id, Map<String, Object?> patch) {
    if (receiptFieldCaps.containsKey(id)) return setField(id, patch);
    if (receiptSectionCaps.containsKey(id)) return setSection(id, patch);
    setBlock(id, patch);
  }

  /// هل العنصر ظاهر؟ null = لا مفتاح له («الرقم والتاريخ» يظهر بجزأيه، وأقسام الفاتورة دائماً).
  bool? shown(String id) {
    if (id == 'meta' || id.startsWith('sale_')) return null;
    if (id == 'qr') return showQr;
    final v1 = _v1Show[id];
    if (v1 != null) return design[v1] != false;
    return styleOf(id)['show'] != false;
  }

  void setShown(String id, bool on) {
    if (id == 'qr') return setColumn('show_qr', on);
    final v1 = _v1Show[id];
    if (v1 != null) return setV1(v1, on ? null : false);
    setField(id, {'show': on ? null : false});
  }

  /// سبب التخفيت في النوع المعروض («لا يظهر في وصل التسديد») أو null.
  String? dimReason(String id, String kind) {
    final kinds = receiptFieldDefs[id]?.kinds ?? _blockKinds[id] ?? receiptKinds;
    final only = receiptOnly(styleOf(id)['only']);
    if (!kinds.contains(kind) || (only != null && !only.contains(kind))) {
      return 'لا يظهر في ${designerKindPhrase[kind]}';
    }
    return null;
  }

  /// ملخّص العنصر في سطره: «12 · عريض · وسط · تحت بعض» — ما غيّره الوكيل وحده.
  String summary(String id) {
    final s = styleOf(id);
    final parts = <String>[];
    final pt = s['pt'];
    if (pt is num) parts.add(pt == pt.truncateToDouble() ? '${pt.toInt()}' : '$pt');
    final def = receiptFieldDefs[id];
    final bold = s['bold'];
    if (bold is bool && def != null && bold != def.bold) parts.add(bold ? 'عريض' : 'عاديّ');
    final align = s['align'];
    if (align is String && designerAlignLabels.containsKey(align)) parts.add(designerAlignLabels[align]!);
    final mode = s['row_mode'];
    if (mode is String && mode != 'line' && designerRowModeLabels.containsKey(mode)) {
      parts.add(designerRowModeLabels[mode]!);
    }
    final gb = s['gap_before'];
    final ga = s['gap_after'];
    if ((gb is num && gb > 0) || (ga is num && ga > 0)) parts.add('مسافة');
    final sep = s['sep'];
    if (sep is String && designerSepLabels.containsKey(sep)) parts.add(sep == 'none' ? 'بلا خطّ' : 'خطّ تحته');
    final only = receiptOnly(s['only']);
    if (only != null) parts.add('في: ${only.map((k) => designerKindChips[k]).join('، ')}');
    final label = s['label'];
    if (label is String && def != null && def.mode != 'none') {
      parts.add(label.trim().isEmpty ? 'بلا تسمية' : '«${label.trim()}»');
    }
    if (receiptSectionCaps.containsKey(id)) {
      if (s['show_title'] == false) parts.add('بلا عنوان');
      final t = s['title'];
      if (t is String && t.trim().isNotEmpty) parts.add('«${t.trim()}»');
    }
    return parts.join(' · ');
  }
}
