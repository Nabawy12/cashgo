// lib/screens/admin/credits_screen.dart
import 'dart:convert';
import 'package:accordion_widget/accordion_widget.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../widgets/Loading/Admin/invoice_cash.dart';

class CreditsScreen extends StatefulWidget {
  static const routeName = "/credits";
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
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

  static const String apiBase = 'https://nabawisolution.com/invoice_reciept.php';

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  // ------------------ Load invoices from API and keep only credit-paid invoices ------------------
  Future<void> _loadCredits() async {
    if (mounted) setState(() => loading = true);

    try {
      final uri = Uri.parse('$apiBase?action=get_all_invoices');
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}: ${resp.body}');
      }

      final Map<String, dynamic> body = jsonDecode(resp.body);
      if (body['success'] != true || body['data'] == null) {
        throw Exception('Unexpected server response: ${resp.body}');
      }

      final List<dynamic> remote = List<dynamic>.from(body['data'] as List);

      // split top-level invoices and child invoices
      final List<Map<String, dynamic>> topLevel = [];
      final List<Map<String, dynamic>> childInvoices = [];

      for (final e in remote) {
        if (e == null) continue;
        final Map<String, dynamic> raw = (e is Map<String, dynamic>) ? Map<String, dynamic>.from(e) : {};
        if (raw.isEmpty) continue;

        final parent = raw['parent_invoice_id'];
        final parentInt = (parent is num) ? parent.toInt() : (parent == null ? null : int.tryParse(parent.toString()));

        if (parentInt == null) topLevel.add(raw);
        else childInvoices.add(raw);
      }

      // Build return caches from childInvoices
      saleReturnItemsCache.clear();
      saleReturnsCache.clear();
      for (final child in childInvoices) {
        final parent = child['parent_invoice_id'];
        final parentId = (parent is num) ? parent.toInt() : (parent == null ? 0 : int.tryParse(parent.toString()) ?? 0);
        if (parentId == 0) continue;

        // product_list may be array or {meta:..., items: [...]}
        final dynamic pl = child['product_list'];
        final List<Map<String, dynamic>> items = [];
        if (pl is List) {
          for (final it in pl) {
            if (it == null) continue;
            final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? Map<String, dynamic>.from(it) : {};
            items.add({
              'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
              'product_name': (rIt['product_name'] ?? rIt['name'] ?? '').toString(),
              'barcode': rIt['barcode']?.toString() ?? '',
              'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
              'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() : (int.tryParse(rIt['qty']?.toString() ?? '') ?? 0),
            });
          }
        } else if (pl is Map && pl.containsKey('items')) {
          final itemsRaw = pl['items'];
          if (itemsRaw is List) {
            for (final it in itemsRaw) {
              if (it == null) continue;
              final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? Map<String, dynamic>.from(it) : {};
              items.add({
                'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
                'product_name': (rIt['product_name'] ?? rIt['name'] ?? '').toString(),
                'barcode': rIt['barcode']?.toString() ?? '',
                'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
                'qty': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() : (int.tryParse(rIt['qty']?.toString() ?? '') ?? 0),
              });
            }
          }
        }

        // interpret items: negative qty => returned (is_replacement=0), positive => replacement (is_replacement=1)
        for (final it in items) {
          final int pid = (it['product_id'] is num) ? (it['product_id'] as num).toInt() : 0;
          int qty = (it['qty'] is num) ? (it['qty'] as num).toInt() : (int.tryParse(it['qty']?.toString() ?? '') ?? 0);
          final price = (it['price'] is num) ? (it['price'] as num).toDouble() : 0.0;
          final name = (it['product_name'] ?? '').toString();
          final isReplacement = qty > 0 ? 1 : 0;
          final qtyAbs = qty.abs();

          saleReturnItemsCache.putIfAbsent(parentId, () => []);
          saleReturnItemsCache[parentId]!.add({
            'return_id': (child['id'] is num) ? (child['id'] as num).toInt() : int.tryParse(child['id']?.toString() ?? '') ?? 0,
            'product_id': pid,
            'product_name': name,
            'price': price,
            'qty': qtyAbs,
            'is_replacement': isReplacement,
          });
        }

        // meta / paid_delta
        final double paidAmount = (child['paid_amount'] is num) ? (child['paid_amount'] as num).toDouble() : (double.tryParse(child['paid_amount']?.toString() ?? '') ?? 0.0);
        double refundAmountInMeta = 0.0;
        try {
          final meta = child['meta'] ?? child['meta_json'];
          if (meta is Map && meta.containsKey('refund_amount')) {
            final raf = meta['refund_amount'];
            refundAmountInMeta = (raf is num) ? raf.toDouble() : (double.tryParse(raf?.toString() ?? '') ?? 0.0);
          }
        } catch (_) {}
        final double paid_delta = paidAmount - refundAmountInMeta;

        saleReturnsCache.putIfAbsent((child['parent_invoice_id'] as int?) ?? 0, () => []);
        saleReturnsCache[(child['parent_invoice_id'] is num) ? (child['parent_invoice_id'] as num).toInt() : int.tryParse(child['parent_invoice_id']?.toString() ?? '') ?? 0]!.add({
          'id': (child['id'] is num) ? (child['id'] as num).toInt() : int.tryParse(child['id']?.toString() ?? '') ?? 0,
          'date': child['created_at'] ?? child['date'] ?? DateTime.now().toIso8601String(),
          'paid_delta': paid_delta,
          'meta': child['meta'] ?? child['meta_json'] ?? {},
          'type': child['type'] ?? 'return',
          'cashier': child['cashier_name'] ?? child['cashier_username'] ?? '',
        });
      }

      // now filter topLevel for invoices where payment_type == 'credit'
      final List<Map<String, dynamic>> onlyCredits = [];
      for (final inv in topLevel) {
        // strict check on payment_type field (case-insensitive)
        final pt = (inv['payment_type'] ?? '').toString().trim().toLowerCase();
        bool isCredit = pt == 'credit';

        // allow fallback if meta explicitly marks is_credit
        if (!isCredit) {
          final meta = inv['meta'] ?? inv['meta_json'];
          if (meta is Map && meta.containsKey('is_credit')) {
            final v = meta['is_credit'];
            if (v is num) isCredit = v.toInt() == 1;
            else if (v is bool) isCredit = v;
            else if (v is String) {
              final s = v.trim().toLowerCase();
              isCredit = s == '1' || s == 'true' || s == 'yes';
            }
          }
        }

        if (isCredit) {
          onlyCredits.add(inv);
        }
      }

      // set credits and prefetch items for them
      credits = onlyCredits;

      // prefetch items for each credit invoice (chunked)
      saleItemsCache.clear();
      const int chunkSize = 12;
      final creditIds = credits.map((c) => (c['id'] is num) ? (c['id'] as num).toInt() : int.tryParse(c['id']?.toString() ?? '') ?? 0).toList();
      for (int i = 0; i < creditIds.length; i += chunkSize) {
        final end = (i + chunkSize < creditIds.length) ? i + chunkSize : creditIds.length;
        final chunk = creditIds.sublist(i, end);
        await Future.wait(chunk.map((saleId) async {
          try {
            final items = await _fetchInvoiceItems(saleId);
            saleItemsCache[saleId] = items;
          } catch (e) {
            saleItemsCache[saleId] = [];
          }
        }));
        if (mounted) setState(() {});
      }
    } catch (e, st) {
      debugPrint('Error loading credits: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل الفواتير: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInvoiceItems(int saleId) async {
    final uri = Uri.parse('$apiBase?action=get_invoice_items&id=$saleId');
    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) throw Exception('get_invoice_items error ${resp.statusCode}');
    final decoded = jsonDecode(resp.body);
    if (decoded is Map && decoded['success'] == true && decoded['data'] is List) {
      final itemsRaw = List<dynamic>.from(decoded['data']);
      final List<Map<String, dynamic>> items = [];
      for (final it in itemsRaw) {
        if (it == null) continue;
        final Map<String, dynamic> rIt = (it is Map<String, dynamic>) ? Map<String, dynamic>.from(it) : {};
        items.add({
          'product_id': (rIt['product_id'] is num) ? (rIt['product_id'] as num).toInt() : (int.tryParse(rIt['product_id']?.toString() ?? '') ?? 0),
          'product_name': (rIt['product_name'] ?? rIt['name'] ?? '').toString(),
          'barcode': rIt['barcode']?.toString() ?? '',
          'price': (rIt['price'] is num) ? (rIt['price'] as num).toDouble() : (double.tryParse(rIt['price']?.toString() ?? '') ?? 0.0),
          'quantity': (rIt['qty'] is num) ? (rIt['qty'] as num).toInt() : (rIt['quantity'] is num) ? (rIt['quantity'] as num).toInt() : (int.tryParse(rIt['qty']?.toString() ?? '') ?? (int.tryParse(rIt['quantity']?.toString() ?? '') ?? 0)),
        });
      }
      return items;
    }
    return [];
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
      return name.contains(query) || cashier.contains(query) || id.contains(query);
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
  Future<void> _markAsPaid(int saleId, Map<String, dynamic> saleRow, String method) async {
    // compute amount to pay: نستخدم الدالة الحالية التي تحسب المجموع الفعلي
    final double amountToPay = _effectiveTotalForSaleHeader(saleRow);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(child: Text('تأكيد الدفع', style: TextStyle(color: Colors.white))),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'سيتم تسجيل الفاتورة كمُسدّدة بواسطة "$method" بمبلغ ${amountToPay.toStringAsFixed(2)}. هل تريد المتابعة؟',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;

    // show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );

    try {
      final uri = Uri.parse(apiBase);
      final payload = {
        'action': 'mark_paid',
        'invoice_id': saleId,
        'paymentMethod': method,
        'paid': amountToPay,
        // optional: pass cashier
        'cashierUsername': (saleRow['cashier_username'] ?? saleRow['cashierName'] ?? '').toString(),
        // optional debug flag
        'debug': true,
      };

      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      Navigator.of(context).pop(); // close loading

      if (resp.statusCode != 200) {
        throw Exception('Server returned ${resp.statusCode}: ${resp.body}');
      }

      final Map<String, dynamic> body = jsonDecode(resp.body);
      if (body['success'] == true) {
        // update local state: remove from credits & caches
        setState(() {
          credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
          saleItemsCache.remove(saleId);
          saleReturnItemsCache.remove(saleId);
          saleReturnsCache.remove(saleId);
        });

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم تسجيل الدفع على السيرفر بنجاح (${body['payment_type'] ?? method}).'),
          duration: const Duration(seconds: 3),
        ));
      } else {
        final msg = body['message'] ?? 'خطأ غير معروف من السيرفر';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تسجيل الدفع: $msg'),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      try { Navigator.of(context).pop(); } catch (_) {}
      debugPrint('markAsPaid error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إرسال طلب الدفع: $e')));
    }
  }

  Future<void> _deleteCredit(int saleId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(child: Text('حذف الفاتورة', style: TextStyle(color: Colors.white))),
        content: Text(
          'هل تريد حذف الفاتورة #$saleId؟ هذا الحذف محلي فقط ولن يؤثر على السيرفر. لحذف فعلي احتاج endpoint في السيرفر.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
          TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف محلي', style: TextStyle(color: Colors.white))),
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
      content: Text('حُذفت الفاتورة محليًا. لإجراء حذف دائم على السيرفر أرسل لي endpoint لأربطه.'),
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
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 6),
        Text(
          ' : $label',
          style: const TextStyle(
            color: Colors.white,
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
      final cashier = (s['cashier_username'] ?? s['cashierName'] ?? '-').toString();
      byCashier.putIfAbsent(cashier, () => []).add(s);
    }
    final cashiers = byCashier.keys.toList();

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: const Text(
          'فواتير مدفوعة (بطاقة / كريدت)',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadCredits,
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
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
                itemCount: 6, // عدد عناصر shimmer المراد عرضها أثناء التحميل
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
                  ? const Center(child: Text('لا توجد فواتير حتي الان', style: TextStyle(fontSize: 18, color: Colors.white)))
                  : ListView.separated(
                itemCount: cashiers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final cashier = cashiers[idx];
                  final salesForCashier = byCashier[cashier] ?? [];

                  return Card(
                      color: AppColorsDark.bgCardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColorsDark.mainColor.withOpacity(0.12))),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: AccordionWidget(
                          decoration: BoxDecoration(color: AppColorsDark.bgColor),
                          showIcon: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          header: AbsorbPointer(
                            absorbing: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColorsDark.mainColor.withOpacity(0.12),
                                    child: Text('${salesForCashier.length}', style: TextStyle(color: AppColorsDark.mainColor, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(cashier, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 6),
                                        Text('الفواتير الخاصة بهذا الكاشير', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          content: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // For each sale of this cashier, render the existing sale Card+Accordion as before
                                ...salesForCashier.map((s) {
                                  final saleId = (s['id'] as num).toInt();
                                  final customer = (s['customer_name'] ?? '-').toString();
                                  final effectiveTotal = _effectiveTotalForSaleHeader(s);
                                  final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                  final dateRaw = (s['date'] ?? s['created_at'] ?? '').toString();
                                  final time = _formatTime(dateRaw);
                                  final cashierName = (s['cashier_username'] ?? s['cashierName'] ?? '-').toString();
                                  final discountLabel = _discountLabelForSale(s);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Card(
                                      color: AppColorsDark.bgCardColor,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColorsDark.mainColor.withOpacity(0.12))),
                                      child: Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: AccordionWidget(
                                          decoration: BoxDecoration(color: AppColorsDark.bgCardColor),
                                          showIcon: false,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          header: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 6),
                                            child: AbsorbPointer(
                                              absorbing: true,
                                              child: Row(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 22,
                                                    backgroundColor: AppColorsDark.mainColor.withOpacity(0.12),
                                                    child: Text('#$saleId', style: TextStyle(color: AppColorsDark.mainColor, fontWeight: FontWeight.bold)),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(customer, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                                                        const SizedBox(height: 6),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.person, size: 14, color: Colors.white24),
                                                            const SizedBox(width: 6),
                                                            Text(cashierName, style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                            const SizedBox(width: 12),
                                                            Icon(Icons.access_time, size: 14, color: Colors.white24),
                                                            const SizedBox(width: 6),
                                                            Text(time, style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                          ],
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      Text(effectiveTotal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                                      const SizedBox(height: 6),
                                                      if (discountLabel.isNotEmpty)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: AppColorsDark.mainColor.withOpacity(0.08),
                                                            borderRadius: BorderRadius.circular(20),
                                                            border: Border.all(color: AppColorsDark.mainColor.withOpacity(0.2)),
                                                          ),
                                                          child: Text(discountLabel, style: TextStyle(color: AppColorsDark.mainColor, fontSize: 12)),
                                                        )
                                                    ],
                                                  )
                                                ],
                                              ),
                                            ),
                                          ),
                                          content: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Builder(builder: (_) {
                                                  final items = saleItemsCache[saleId] ?? [];
                                                  if (loadingSaleItems.contains(saleId)) {
                                                    return const Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Center(child: CircularProgressIndicator()),
                                                    );
                                                  }
                                                  if (items.isEmpty) {
                                                    return const Padding(
                                                      padding: EdgeInsets.all(8.0),
                                                      child: Text('لا توجد عناصر مسجلة لهذه الفاتورة', style: TextStyle(color: Colors.white)),
                                                    );
                                                  }

                                                  final itemsTotal = items.fold<double>(0.0, (p, it) {
                                                    final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
                                                    final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                    return p + qty * price;
                                                  });

                                                  final discountTypeRaw = (s['discount_type'] ?? 'fixed').toString();
                                                  final discountValueRaw = (s['discount_value'] as num?)?.toDouble() ?? 0.0;
                                                  final discountType = (discountTypeRaw == 'percent') ? 'percent' : 'fixed';
                                                  double discountValue = discountValueRaw.isFinite ? discountValueRaw : 0.0;
                                                  double discountAmount = 0.0;
                                                  if (discountType == 'percent') {
                                                    discountAmount = itemsTotal * (discountValue / 100.0);
                                                  } else {
                                                    discountAmount = discountValue;
                                                  }
                                                  if (discountAmount < 0) discountAmount = 0.0;
                                                  if (discountAmount > itemsTotal) discountAmount = itemsTotal;

                                                  final effectiveTotalLocal = (itemsTotal - discountAmount).clamp(0.0, double.infinity);

                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // items list: compact rows
                                                      ...items.map((it) {
                                                        final name = (it['product_name'] ?? 'منتج') as String;
                                                        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                                                        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                                                        return Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              Text('$qty x', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                                              const SizedBox(width: 8),
                                                              Text(price.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                                            ],
                                                          ),
                                                        );
                                                      }).toList(),

                                                      const Divider(color: Colors.white12),

                                                      // summary row
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                        child: Row(
                                                          children: [
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text('مجموع العناصر', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                                  const SizedBox(height: 6),
                                                                  Text(itemsTotal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                ],
                                                              ),
                                                            ),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                                children: [
                                                                  Text('بعد الخصم', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                                                  const SizedBox(height: 6),
                                                                  Text(effectiveTotalLocal.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),

                                                      const SizedBox(height: 10),

                                                      // actions row
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.end,
                                                        children: [
                                                          TextButton.icon(
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: AppColorsDark.bgCardColor,
                                                            ),
                                                            onPressed: () async {
                                                              final choice = await showDialog<String>(
                                                                context: context,
                                                                builder: (ctx) => AlertDialog(
                                                                  backgroundColor: AppColorsDark.bgCardColor,
                                                                  title: Center(child: Text('بماذا تم الدفع؟', style: TextStyle(color: Colors.white, fontSize: 22))),
                                                                  actions: [
                                                                    TextButton(
                                                                        style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
                                                                        onPressed: () => Navigator.pop(ctx, null),
                                                                        child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
                                                                    TextButton(
                                                                        style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
                                                                        onPressed: () => Navigator.pop(ctx, 'card'),
                                                                        child: const Text('كارت', style: TextStyle(color: Colors.white))),
                                                                    TextButton(
                                                                        style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
                                                                        onPressed: () => Navigator.pop(ctx, 'cash'),
                                                                        child: const Text('نقدي', style: TextStyle(color: Colors.white))),
                                                                  ],
                                                                ),
                                                              );
                                                              if (choice == null) return;
                                                              await _markAsPaid(saleId, s, choice);
                                                            },
                                                            icon: const Icon(Icons.check_circle, color: Colors.green),
                                                            label: const Text('تم الدفع', style: TextStyle(color: Colors.green)),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          TextButton.icon(
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: AppColorsDark.bgCardColor,
                                                            ),
                                                            onPressed: () => _deleteCredit(saleId),
                                                            icon: Icon(Icons.delete, color: Colors.red.withOpacity(0.7)),
                                                            label: Text('حذف', style: TextStyle(color: Colors.red.withOpacity(0.7))),
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
