// lib/screens/admin/credits_screen.dart
import 'dart:io';

import 'package:accordion_widget/accordion_widget.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../services/db/db_helper.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';

class CreditsScreen extends StatefulWidget {
  static const routeName = "/credits";
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  final _money = NumberFormat.currency(locale: 'ar', symbol: 'EGP ');
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  double get _inventoryValue => _rows.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['inventory_value'] as num?)?.toDouble() ?? 0.0));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await DBHelper.instance.getStockReport();
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isLowStock(Map<String, dynamic> row) {
    return ((row['total_units'] as num?)?.toInt() ?? 0) <= 5;
  }

  bool _isNearExpiry(Map<String, dynamic> row) {
    final raw = (row['expiry_date'] ?? '').toString();
    final expiry = DateTime.tryParse(raw);
    if (expiry == null) return false;
    final days = expiry.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 30;
  }

  Future<void> _exportPdf() async {
    final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Text('تقرير المخزون',
              style:
                  pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(
              'قيمة المخزون التقديرية: ${_inventoryValue.toStringAsFixed(2)}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: const [
              'المنتج',
              'الباركود',
              'المخزون',
              'سعر الشراء/وحدة',
              'قيمة المخزون',
              'الصلاحية',
            ],
            data: _rows.map((r) {
              return [
                (r['name'] ?? '').toString(),
                (r['barcode'] ?? '').toString(),
                '${(r['total_units'] as num?)?.toInt() ?? 0}',
                ((r['unit_purchase_price'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
                ((r['inventory_value'] as num?)?.toDouble() ?? 0)
                    .toStringAsFixed(2),
                (r['expiry_date'] ?? '').toString(),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final downloads = Directory('${Platform.environment['HOME']}/Downloads');
    if (!downloads.existsSync()) downloads.createSync(recursive: true);
    final file = File(
        '${downloads.path}/cashgo_stock_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    _showSnack('تم حفظ التقرير في Downloads');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text(message),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text('تقرير المخزون',
            style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 24)),
        actions: [
          IconButton(
            tooltip: 'تصدير PDF',
            onPressed: _rows.isEmpty ? null : _exportPdf,
            icon: Icon(Icons.picture_as_pdf,
                color: Theme.of(context).iconTheme.color),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                color: AppColorsDark.bgCardColor,
                child: ListTile(
                  title: Text('قيمة المخزون التقديرية',
                      style: TextStyle(color: AppColorsDark.mainTextLight)),
                  trailing: Text(_money.format(_inventoryValue),
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                        ? const EmptyStateCard(
                            icon: Icons.inventory_2_outlined,
                            title: 'لا توجد منتجات',
                            message: 'أضف منتجات أولاً حتى يظهر تقرير المخزون.',
                          )
                        : ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final row = _rows[i];
                              final low = _isLowStock(row);
                              final exp = _isNearExpiry(row);
                              final color = low
                                  ? Colors.red.withValues(alpha: 0.22)
                                  : exp
                                      ? Colors.orange.withValues(alpha: 0.22)
                                      : AppColorsDark.bgCardColor;
                              return Card(
                                color: color,
                                child: ListTile(
                                  title: Text((row['name'] ?? '').toString(),
                                      style: TextStyle(
                                          color: AppColorsDark.mainTextDark)),
                                  subtitle: Text(
                                    'المخزون: ${(row['total_units'] as num?)?.toInt() ?? 0} | الصلاحية: ${(row['expiry_date'] ?? '').toString().isEmpty ? '-' : row['expiry_date']}',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextLight),
                                  ),
                                  trailing: Text(
                                    _money.format(
                                        (row['inventory_value'] as num?)
                                                ?.toDouble() ??
                                            0),
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditsScreenState extends State<CreditsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> credits = [];
  String query = "";
  final Map<int, List<Map<String, dynamic>>> saleItemsCache = {};
  final Set<int> loadingSaleItems = {};
  final Set<int> loadingSaleReturnItems = {};
  final Map<int, List<Map<String, dynamic>>> saleReturnItemsCache = {};
  final Map<int, List<Map<String, dynamic>>> saleReturnsCache = {};

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  // ------------------ Load invoices from API and keep only credit-paid invoices ------------------
  Future<void> _loadCredits() async {
    if (mounted) setState(() => loading = true);

    try {
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();
      saleItemsCache.clear();

      final rows = await DBHelper.instance.getCreditSales();
      credits = rows.map((sale) {
        return {
          'id': sale['id'],
          'invoice_id': sale['id'].toString(),
          'total': sale['total'] ?? 0.0,
          'paid_amount': sale['paid_amount'] ?? 0.0,
          'change_amount': sale['change_amount'] ?? 0.0,
          'payment_type': sale['payment_method'] ?? 'credit',
          'cashier_username': sale['cashier_username'] ?? '',
          'customer_name': sale['customer_name'] ?? '',
          'date': sale['date'] ?? '',
          'created_at': sale['date'] ?? '',
          'is_credit': sale['is_credit'] ?? 1,
          'meta': {},
        };
      }).toList();

      for (final c in credits) {
        final id = (c['id'] as num).toInt();
        saleItemsCache[id] = await _fetchInvoiceItems(id);
        saleReturnItemsCache[id] =
            await DBHelper.instance.getSaleReturnItemsForSale(id);
        saleReturnsCache[id] =
            await DBHelper.instance.getSaleReturnsBySaleId(id);
      }
    } catch (e, st) {
      debugPrint('Error loading credits: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('فشل تحميل الفواتير: $e'),
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInvoiceItems(int saleId) async {
    final rows = await DBHelper.instance.getSaleItemsBySaleId(saleId);
    return rows
        .map((r) => {
              'product_id': r['product_id'],
              'product_name': r['product_name'] ?? '',
              'barcode': r['product_barcode'] ?? '',
              'price': r['price'] ?? 0.0,
              'quantity': r['quantity'] ?? 0,
            })
        .toList();
  }

  // ------------------ Helpers & UI logic (mostly same as original) ------------------
  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      return '$hh:$mm:$ss';
    } catch (_) {
      return isoString;
    }
  }

  void _applySearch(String q) {
    setState(() => query = q.trim().toLowerCase());
  }

  List<Map<String, dynamic>> get _filtered {
    if (query.isEmpty) return credits;
    return credits.where((s) {
      final name = (s['customer_name'] ?? '').toString().toLowerCase();
      final cashier = (s['cashier_username'] ?? '').toString().toLowerCase();
      final id = (s['id'] ?? '').toString();
      return name.contains(query) ||
          cashier.contains(query) ||
          id.contains(query);
    }).toList();
  }

  double _effectiveTotalForSaleHeader(Map<String, dynamic> s) {
    final saleId = (s['id'] as num?)?.toInt();
    double currentItemsTotal = 0.0;
    if (saleId != null && saleItemsCache.containsKey(saleId)) {
      final items = saleItemsCache[saleId]!;
      currentItemsTotal = items.fold<double>(0.0, (p, it) {
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        return p + qty * price;
      });
    } else {
      currentItemsTotal = (s['total'] as num?)?.toDouble() ?? 0.0;
    }

    final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
    final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
    final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
    double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;

    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = currentItemsTotal * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > currentItemsTotal) discountAmount = currentItemsTotal;

    return (currentItemsTotal - discountAmount).clamp(0.0, double.infinity);
  }

  String _discountLabelForSale(Map<String, dynamic> s) {
    final saleId = (s['id'] as num?)?.toInt();
    double currentItemsTotal = 0.0;
    if (saleId != null && saleItemsCache.containsKey(saleId)) {
      final items = saleItemsCache[saleId]!;
      currentItemsTotal = items.fold<double>(0.0, (p, it) {
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        return p + qty * price;
      });
    } else {
      currentItemsTotal = (s['total'] as num?)?.toDouble() ?? 0.0;
    }

    final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
    final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
    final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
    double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;

    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = currentItemsTotal * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount <= 0) return '';

    if (discountType == 'percent') {
      return 'خصم ${discountValue.toStringAsFixed(0)}% (${discountAmount.toStringAsFixed(2)})';
    } else {
      return 'خصم ثابت ${discountAmount.toStringAsFixed(2)}';
    }
  }

  double _sumPaidDeltaForSale(int saleId) {
    final rows = saleReturnsCache[saleId] ?? [];
    double sum = 0.0;
    for (final r in rows) {
      sum += (r['paid_delta'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  Map<int, List<Map<String, dynamic>>> _groupReturnItemsByReturnId(int saleId) {
    final rows = saleReturnItemsCache[saleId] ?? [];
    final Map<int, List<Map<String, dynamic>>> m = {};
    for (final r in rows) {
      final rid = (r['return_id'] as num).toInt();
      m.putIfAbsent(rid, () => []).add(r);
    }
    return m;
  }

  // ------------------ Actions: mark as paid & delete (local-only) ------------------
  Future<void> _markAsPaid(
      int saleId, Map<String, dynamic> saleRow, String method) async {
    final double amountToPay = _effectiveTotalForSaleHeader(saleRow);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(
            child: Text('تأكيد الدفع',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black87
                        : Colors.white))),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'سيتم تسجيل الفاتورة كمُسدّدة بواسطة "$method" بمبلغ ${amountToPay.toStringAsFixed(2)}. هل تريد المتابعة؟',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black87
                      : Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, true),
              child: Text('تأكيد',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await DBHelper.instance.markSaleAsPaid(saleId,
          paymentMethod: method, paidAmount: amountToPay);
      setState(() {
        credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
        saleItemsCache.remove(saleId);
        saleReturnItemsCache.remove(saleId);
        saleReturnsCache.remove(saleId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('تم تسجيل الدفع '),
        ),
      ));
    } catch (e) {
      debugPrint('markAsPaid error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('فشل تسجيل الدفع: $e'),
        ),
      ));
    }
  }

  Future<void> _deleteCredit(int saleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(
            child: Text('حذف الفاتورة',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black87
                        : Colors.white))),
        content: Text(
          'هل تريد حذف الفاتورة #$saleId؟',
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.black87
                  : Colors.white),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, true),
              child: Text('حذف محلي',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
      saleItemsCache.remove(saleId);
      saleReturnItemsCache.remove(saleId);
      saleReturnsCache.remove(saleId);
    });

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text('تم الحذف'),
      ),
      duration: Duration(seconds: 3),
    ));
  }

  Widget buildLabelValue(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: AppColorsDark.mainTextLight,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 6),
        Text(
          ' : $label',
          style: TextStyle(
            color: AppColorsDark.mainTextDark,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    // Group credits by cashier username
    final Map<String, List<Map<String, dynamic>>> byCashier = {};
    for (final s in list) {
      final cashier =
          (s['cashier_username'] ?? s['cashierName'] ?? '-').toString();
      byCashier.putIfAbsent(cashier, () => []).add(s);
    }
    final cashiers = byCashier.keys.toList();

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text(
          'فواتير مدفوعة (بطاقة / كريدت)',
          style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadCredits,
            icon: Icon(Icons.refresh,
                color: Theme.of(context).iconTheme.color, size: 22),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CustomFormField(
              hint: 'بحث باسم العميل / رقم الفاتورة',
              onChanged: _applySearch,
              centerHint: true,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: loading
                  ? ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount:
                          6, // عدد عناصر shimmer المراد عرضها أثناء التحميل
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return LoadingShimmer(
                          height: 80,
                          borderRadius: BorderRadius.circular(10),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        );
                      },
                    )
                  : list.isEmpty
                      ? const EmptyStateCard(
                          icon: Icons.receipt_long,
                          title: 'لا توجد فواتير',
                          message: 'لا توجد فواتير آجلة مطابقة لهذا البحث.',
                        )
                      : ListView.separated(
                          itemCount: cashiers.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, idx) {
                            final cashier = cashiers[idx];
                            final salesForCashier = byCashier[cashier] ?? [];

                            return Card(
                                color: AppColorsDark.bgCardColor,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                        color: AppColorsDark.mainColor
                                            .withOpacity(0.12))),
                                child: Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AccordionWidget(
                                    decoration: BoxDecoration(
                                        color: AppColorsDark.bgColor),
                                    showIcon: true,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    header: AbsorbPointer(
                                      absorbing: true,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8.0, horizontal: 6),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 22,
                                              backgroundColor: AppColorsDark
                                                  .mainColor
                                                  .withOpacity(0.12),
                                              child: Text(
                                                  '${salesForCashier.length}',
                                                  style: TextStyle(
                                                      color: AppColorsDark
                                                          .mainColor,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(cashier,
                                                      style: TextStyle(
                                                          color: AppColorsDark
                                                              .mainTextDark,
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w700),
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                      'الفواتير الخاصة بهذا الكاشير',
                                                      style: TextStyle(
                                                          color: AppColorsDark
                                                              .mainTextLight,
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    content: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0, vertical: 6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // For each sale of this cashier, render the existing sale Card+Accordion as before
                                          ...salesForCashier.map((s) {
                                            final saleId =
                                                (s['id'] as num).toInt();
                                            final customer =
                                                (s['customer_name'] ?? '-')
                                                    .toString();
                                            final effectiveTotal =
                                                _effectiveTotalForSaleHeader(s);
                                            final paid =
                                                (s['paid_amount'] as num?)
                                                        ?.toDouble() ??
                                                    0.0;
                                            final dateRaw = (s['date'] ??
                                                    s['created_at'] ??
                                                    '')
                                                .toString();
                                            final time = _formatTime(dateRaw);
                                            final cashierName =
                                                (s['cashier_username'] ??
                                                        s['cashierName'] ??
                                                        '-')
                                                    .toString();
                                            final discountLabel =
                                                _discountLabelForSale(s);

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6.0),
                                              child: Card(
                                                color:
                                                    AppColorsDark.bgCardColor,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    side: BorderSide(
                                                        color: AppColorsDark
                                                            .mainColor
                                                            .withOpacity(
                                                                0.12))),
                                                child: Directionality(
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  child: AccordionWidget(
                                                    decoration: BoxDecoration(
                                                        color: AppColorsDark
                                                            .bgCardColor),
                                                    showIcon: false,
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 12,
                                                        vertical: 6),
                                                    header: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 8.0,
                                                          horizontal: 6),
                                                      child: AbsorbPointer(
                                                        absorbing: true,
                                                        child: Row(
                                                          children: [
                                                            CircleAvatar(
                                                              radius: 22,
                                                              backgroundColor:
                                                                  AppColorsDark
                                                                      .mainColor
                                                                      .withOpacity(
                                                                          0.12),
                                                              child: Text(
                                                                  '#$saleId',
                                                                  style: TextStyle(
                                                                      color: AppColorsDark
                                                                          .mainColor,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold)),
                                                            ),
                                                            const SizedBox(
                                                                width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(customer,
                                                                      style: TextStyle(
                                                                          color: Theme.of(context).brightness == Brightness.light
                                                                              ? Colors
                                                                                  .black87
                                                                              : Colors
                                                                                  .white,
                                                                          fontSize:
                                                                              16,
                                                                          fontWeight: FontWeight
                                                                              .w700),
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis),
                                                                  const SizedBox(
                                                                      height:
                                                                          6),
                                                                  Row(
                                                                    children: [
                                                                      Icon(
                                                                          Icons
                                                                              .person,
                                                                          size:
                                                                              14,
                                                                          color: Theme.of(context)
                                                                              .iconTheme
                                                                              .color),
                                                                      const SizedBox(
                                                                          width:
                                                                              6),
                                                                      Text(
                                                                          cashierName,
                                                                          style: TextStyle(
                                                                              color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight,
                                                                              fontSize: 12)),
                                                                      const SizedBox(
                                                                          width:
                                                                              12),
                                                                      Icon(
                                                                          Icons
                                                                              .access_time,
                                                                          size:
                                                                              14,
                                                                          color: Theme.of(context)
                                                                              .iconTheme
                                                                              .color),
                                                                      const SizedBox(
                                                                          width:
                                                                              6),
                                                                      Text(time,
                                                                          style: TextStyle(
                                                                              color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight,
                                                                              fontSize: 12)),
                                                                    ],
                                                                  )
                                                                ],
                                                              ),
                                                            ),
                                                            Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .end,
                                                              children: [
                                                                Text(
                                                                    effectiveTotal
                                                                        .toStringAsFixed(
                                                                            2),
                                                                    style: TextStyle(
                                                                        color: Theme.of(context).brightness == Brightness.light
                                                                            ? Colors
                                                                                .black87
                                                                            : Colors
                                                                                .white,
                                                                        fontSize:
                                                                            16,
                                                                        fontWeight:
                                                                            FontWeight.bold)),
                                                                const SizedBox(
                                                                    height: 6),
                                                                if (discountLabel
                                                                    .isNotEmpty)
                                                                  Container(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            4),
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      color: AppColorsDark
                                                                          .mainColor
                                                                          .withOpacity(
                                                                              0.08),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              20),
                                                                      border: Border.all(
                                                                          color: AppColorsDark
                                                                              .mainColor
                                                                              .withOpacity(0.2)),
                                                                    ),
                                                                    child: Text(
                                                                        discountLabel,
                                                                        style: TextStyle(
                                                                            color:
                                                                                AppColorsDark.mainColor,
                                                                            fontSize: 12)),
                                                                  )
                                                              ],
                                                            )
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    content: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8.0,
                                                          vertical: 6),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Builder(builder: (_) {
                                                            final items =
                                                                saleItemsCache[
                                                                        saleId] ??
                                                                    [];
                                                            if (loadingSaleItems
                                                                .contains(
                                                                    saleId)) {
                                                              return const Padding(
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            8.0),
                                                                child: Center(
                                                                    child:
                                                                        CircularProgressIndicator()),
                                                              );
                                                            }
                                                            if (items.isEmpty) {
                                                              return const Padding(
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            8.0),
                                                                child:
                                                                    EmptyStateCard(
                                                                  icon: Icons
                                                                      .inventory_2_outlined,
                                                                  title:
                                                                      'لا توجد عناصر',
                                                                  message:
                                                                      'لا توجد عناصر مسجلة لهذه الفاتورة.',
                                                                  margin:
                                                                      EdgeInsets
                                                                          .zero,
                                                                ),
                                                              );
                                                            }

                                                            final itemsTotal =
                                                                items.fold<
                                                                        double>(
                                                                    0.0,
                                                                    (p, it) {
                                                              final qty = (it['quantity']
                                                                          as num?)
                                                                      ?.toDouble() ??
                                                                  0.0;
                                                              final price = (it[
                                                                              'price']
                                                                          as num?)
                                                                      ?.toDouble() ??
                                                                  0.0;
                                                              return p +
                                                                  qty * price;
                                                            });

                                                            final discountTypeRaw =
                                                                (s['discount_type'] ??
                                                                        'fixed')
                                                                    .toString();
                                                            final discountValueRaw =
                                                                (s['discount_value']
                                                                            as num?)
                                                                        ?.toDouble() ??
                                                                    0.0;
                                                            final discountType =
                                                                (discountTypeRaw ==
                                                                        'percent')
                                                                    ? 'percent'
                                                                    : 'fixed';
                                                            double
                                                                discountValue =
                                                                discountValueRaw
                                                                        .isFinite
                                                                    ? discountValueRaw
                                                                    : 0.0;
                                                            double
                                                                discountAmount =
                                                                0.0;
                                                            if (discountType ==
                                                                'percent') {
                                                              discountAmount =
                                                                  itemsTotal *
                                                                      (discountValue /
                                                                          100.0);
                                                            } else {
                                                              discountAmount =
                                                                  discountValue;
                                                            }
                                                            if (discountAmount <
                                                                0)
                                                              discountAmount =
                                                                  0.0;
                                                            if (discountAmount >
                                                                itemsTotal)
                                                              discountAmount =
                                                                  itemsTotal;

                                                            final effectiveTotalLocal =
                                                                (itemsTotal -
                                                                        discountAmount)
                                                                    .clamp(
                                                                        0.0,
                                                                        double
                                                                            .infinity);

                                                            return Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                // items list: compact rows
                                                                ...items
                                                                    .map((it) {
                                                                  final name = (it[
                                                                              'product_name'] ??
                                                                          'منتج')
                                                                      as String;
                                                                  final qty =
                                                                      (it['quantity'] as num?)
                                                                              ?.toInt() ??
                                                                          0;
                                                                  final price =
                                                                      (it['price'] as num?)
                                                                              ?.toDouble() ??
                                                                          0.0;
                                                                  return Padding(
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        vertical:
                                                                            6.0),
                                                                    child: Row(
                                                                      children: [
                                                                        Expanded(
                                                                          child: Text(
                                                                              name,
                                                                              style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight, fontSize: 14),
                                                                              overflow: TextOverflow.ellipsis),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                8),
                                                                        Text(
                                                                            '$qty x',
                                                                            style:
                                                                                TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight, fontSize: 13)),
                                                                        const SizedBox(
                                                                            width:
                                                                                8),
                                                                        Text(
                                                                            price.toStringAsFixed(
                                                                                2),
                                                                            style:
                                                                                TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white, fontWeight: FontWeight.w700)),
                                                                      ],
                                                                    ),
                                                                  );
                                                                }).toList(),

                                                                const Divider(
                                                                    color: Colors
                                                                        .white12),

                                                                // summary row
                                                                Padding(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      vertical:
                                                                          8.0),
                                                                  child: Row(
                                                                    children: [
                                                                      Expanded(
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.start,
                                                                          children: [
                                                                            Text('مجموع العناصر',
                                                                                style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight, fontSize: 12)),
                                                                            const SizedBox(height: 6),
                                                                            Text(itemsTotal.toStringAsFixed(2),
                                                                                style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white, fontWeight: FontWeight.bold)),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.end,
                                                                          children: [
                                                                            Text('بعد الخصم',
                                                                                style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : AppColorsDark.mainTextLight, fontSize: 12)),
                                                                            const SizedBox(height: 6),
                                                                            Text(effectiveTotalLocal.toStringAsFixed(2),
                                                                                style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white, fontWeight: FontWeight.bold)),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),

                                                                const SizedBox(
                                                                    height: 10),

                                                                // actions row
                                                                Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .end,
                                                                  children: [
                                                                    TextButton
                                                                        .icon(
                                                                      style: TextButton
                                                                          .styleFrom(
                                                                        backgroundColor:
                                                                            AppColorsDark.bgCardColor,
                                                                      ),
                                                                      onPressed:
                                                                          () async {
                                                                        final choice =
                                                                            await showDialog<String>(
                                                                          context:
                                                                              context,
                                                                          builder: (ctx) =>
                                                                              AlertDialog(
                                                                            backgroundColor:
                                                                                AppColorsDark.bgCardColor,
                                                                            title:
                                                                                Center(child: Text('بماذا تم الدفع؟', style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black87 : Colors.white, fontSize: 22))),
                                                                            actions: [
                                                                              TextButton(style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor), onPressed: () => Navigator.pop(ctx, null), child: Text('إلغاء', style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white))),
                                                                              TextButton(style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor), onPressed: () => Navigator.pop(ctx, 'card'), child: Text('كارت', style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white))),
                                                                              TextButton(style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor), onPressed: () => Navigator.pop(ctx, 'cash'), child: Text('نقدي', style: TextStyle(color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white))),
                                                                            ],
                                                                          ),
                                                                        );
                                                                        if (choice ==
                                                                            null)
                                                                          return;
                                                                        await _markAsPaid(
                                                                            saleId,
                                                                            s,
                                                                            choice);
                                                                      },
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .check_circle,
                                                                          color:
                                                                              Colors.green),
                                                                      label: const Text(
                                                                          'تم الدفع',
                                                                          style:
                                                                              TextStyle(color: Colors.green)),
                                                                    ),
                                                                    const SizedBox(
                                                                        width:
                                                                            8),
                                                                    TextButton
                                                                        .icon(
                                                                      style: TextButton
                                                                          .styleFrom(
                                                                        backgroundColor:
                                                                            AppColorsDark.bgCardColor,
                                                                      ),
                                                                      onPressed:
                                                                          () =>
                                                                              _deleteCredit(saleId),
                                                                      icon: Icon(
                                                                          Icons
                                                                              .delete,
                                                                          color: Colors
                                                                              .red
                                                                              .withOpacity(0.7)),
                                                                      label: Text(
                                                                          'حذف',
                                                                          style:
                                                                              TextStyle(color: Colors.red.withOpacity(0.7))),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            );
                                                          }),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ));
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
