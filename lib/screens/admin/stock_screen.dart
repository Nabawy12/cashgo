// lib/screens/admin/credits_screen.dart
import 'dart:io';

import 'package:accordion_widget/accordion_widget.dart';
import 'package:cashgo_supermarket/utils/colors.dart';
import 'package:cashgo_supermarket/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/login.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';


class CreditsScreen extends StatefulWidget {
  static const routeName = "/credits";
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

/// ----------------------------------------------------------------------
/// حالة الفاتورة (مشتقة من paid_amount مقارنة بـ total الفعّال بعد الخصم)
/// ----------------------------------------------------------------------
enum _InvoiceStatus { unpaid, partial, paid }

extension on _InvoiceStatus {
  String get label {
    switch (this) {
      case _InvoiceStatus.unpaid:
        return 'لم يتم الدفع';
      case _InvoiceStatus.partial:
        return 'جزئي';
      case _InvoiceStatus.paid:
        return 'مدفوع';
    }
  }

  Color get color {
    switch (this) {
      case _InvoiceStatus.unpaid:
        return const Color(0xFFEF5350);
      case _InvoiceStatus.partial:
        return const Color(0xFFFFA726);
      case _InvoiceStatus.paid:
        return const Color(0xFF4CAF50);
    }
  }
}

class _CreditsScreenState extends State<CreditsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> credits = [];
  String query = "";

  final Map<int, List<Map<String, dynamic>>> saleItemsCache = {};
  final Set<int> loadingSaleItems = {};

  // ------------------ Filters ------------------
  DateTime? _selectedDate;
  String _selectedCashier = 'الكل';
  _InvoiceStatus? _selectedStatus; // null = الكل

  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(locale: 'ar', symbol: 'EGP ');

  @override
  void initState() {
    super.initState();
    _loadCredits();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------ Load invoices ------------------
  Future<void> _loadCredits() async {
    if (mounted) setState(() => loading = true);
    try {
      saleItemsCache.clear();

      final rows = await DBHelper.instance.getCreditSales();
      credits = rows.map((sale) {
        return {
          'id': sale['id'],
          'total': sale['total'] ?? 0.0,
          'paid_amount': sale['paid_amount'] ?? 0.0,
          'payment_method': sale['payment_method'] ?? 'credit',
          'cashier_username': sale['cashier_username'] ?? '',
          'customer_name': sale['customer_name'] ?? '',
          'date': sale['date'] ?? '',
          'is_credit': sale['is_credit'] ?? 1,
          'discount_type': sale['discount_type'] ?? 'fixed',
          'discount_value': sale['discount_value'] ?? 0.0,
        };
      }).toList();

      for (final c in credits) {
        final id = (c['id'] as num).toInt();
        saleItemsCache[id] = await _fetchInvoiceItems(id);
      }

      // الصفحة دي تعرض الفواتير التي لم يتم دفعها + المدفوعة جزئيًا،
      // وتستبعد فقط الفواتير المدفوعة بالكامل.
      credits =
          credits.where((s) => _statusOf(s) != _InvoiceStatus.paid).toList();
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

  // ------------------ Calculations ------------------
  double _itemsTotal(int saleId, Map<String, dynamic> s) {
    final items = saleItemsCache[saleId];
    if (items == null || items.isEmpty) {
      return (s['total'] as num?)?.toDouble() ?? 0.0;
    }
    return items.fold<double>(0.0, (p, it) {
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
      return p + qty * price;
    });
  }

  double _effectiveTotal(Map<String, dynamic> s) {
    final saleId = (s['id'] as num).toInt();
    final itemsTotal = _itemsTotal(saleId, s);

    final discountType =
    (s['discount_type'] ?? 'fixed').toString() == 'percent'
        ? 'percent'
        : 'fixed';
    final discountValue = (s['discount_value'] as num?)?.toDouble() ?? 0.0;

    double discountAmount = discountType == 'percent'
        ? itemsTotal * (discountValue / 100.0)
        : discountValue;
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > itemsTotal) discountAmount = itemsTotal;

    return (itemsTotal - discountAmount).clamp(0.0, double.infinity);
  }

  double _paidAmount(Map<String, dynamic> s) =>
      (s['paid_amount'] as num?)?.toDouble() ?? 0.0;

  double _remaining(Map<String, dynamic> s) {
    final r = _effectiveTotal(s) - _paidAmount(s);
    return r < 0 ? 0.0 : r;
  }

  _InvoiceStatus _statusOf(Map<String, dynamic> s) {
    final total = _effectiveTotal(s);
    final paid = _paidAmount(s);
    if (paid <= 0) return _InvoiceStatus.unpaid;
    if (paid >= total) return _InvoiceStatus.paid;
    return _InvoiceStatus.partial;
  }

  String _paymentMethodLabel(Map<String, dynamic> s) {
    final m = (s['payment_method'] ?? '').toString();
    switch (m) {
      case 'cash':
        return 'نقدي';
      case 'card':
        return 'بطاقة';
      case 'wallet':
        return 'محفظة';
      default:
        return 'آجل';
    }
  }

  String _invoiceTypeLabel(Map<String, dynamic> s) {
    final isCredit = (s['is_credit'] ?? 1) == 1 || s['is_credit'] == true;
    return isCredit ? 'آجل' : 'فوري';
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('dd/MM/yyyy hh:mm a', 'ar').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  // ------------------ Filtering ------------------
  List<Map<String, dynamic>> get _filtered {
    final q = query.trim().toLowerCase();
    return credits.where((s) {
      if (q.isNotEmpty) {
        final name = (s['customer_name'] ?? '').toString().toLowerCase();
        final cashier =
        (s['cashier_username'] ?? '').toString().toLowerCase();
        final id = (s['id'] ?? '').toString();
        final matches = name.contains(q) || cashier.contains(q) || id.contains(q);
        if (!matches) return false;
      }

      if (_selectedDate != null) {
        final raw = (s['date'] ?? '').toString();
        final dt = DateTime.tryParse(raw);
        if (dt == null) return false;
        if (dt.year != _selectedDate!.year ||
            dt.month != _selectedDate!.month ||
            dt.day != _selectedDate!.day) {
          return false;
        }
      }

      if (_selectedCashier != 'الكل') {
        if ((s['cashier_username'] ?? '').toString() != _selectedCashier) {
          return false;
        }
      }

      if (_selectedStatus != null) {
        if (_statusOf(s) != _selectedStatus) return false;
      }

      return true;
    }).toList();
  }

  List<String> get _cashierOptions {
    final set = <String>{'الكل'};
    for (final s in credits) {
      final c = (s['cashier_username'] ?? '').toString();
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList();
  }

  // ------------------ Stats ------------------
  int get _totalInvoicesCount => credits.length;

  double get _totalAmount =>
      credits.fold<double>(0.0, (p, s) => p + _effectiveTotal(s));

  double get _totalRemaining =>
      credits.fold<double>(0.0, (p, s) => p + _remaining(s));

  int get _todayInvoicesCount {
    final now = DateTime.now();
    return credits.where((s) {
      final dt = DateTime.tryParse((s['date'] ?? '').toString());
      if (dt == null) return false;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).length;
  }

  // ------------------ Actions ------------------
  Future<void> _openPaymentSheet(Map<String, dynamic> s) async {
    final saleId = (s['id'] as num).toInt();
    final total = _effectiveTotal(s);
    final alreadyPaid = _paidAmount(s);
    final remaining = _remaining(s);

    String method = 'cash'; // cash | wallet
    bool fullPayment = true;
    final amountController =
    TextEditingController(text: remaining.toStringAsFixed(2));

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final rawPayNow = fullPayment
                ? remaining
                : (double.tryParse(amountController.text) ?? 0.0);
            final payNow = rawPayNow > remaining ? remaining : rawPayNow;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                decoration: BoxDecoration(
                  color: AppColorsDark.bgCardColor,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.description_outlined,
                              color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تسجيل دفع الفاتورة',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            icon: Icon(Icons.close,
                                color: Theme.of(ctx).iconTheme.color),
                          ),
                        ],
                      ),
                      Text('INV-${saleId.toString().padLeft(4, '0')}',
                          style: TextStyle(
                              color: AppColorsDark.mainColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      Text((s['customer_name'] ?? '').toString(),
                          style: TextStyle(
                              color: AppColorsDark.mainTextLight,
                              fontSize: 13)),
                      const SizedBox(height: 16),

                      // ---- summary chips ----
                      Row(
                        children: [
                          _sheetStat('إجمالي المبلغ',
                              _money.format(total), AppColorsDark.mainTextDark),
                          _sheetStat('تم الدفع',
                              _money.format(alreadyPaid), Colors.green),
                          _sheetStat('المتبقي',
                              _money.format(remaining), Colors.redAccent),
                        ],
                      ),
                      const SizedBox(height: 20),

                      Text('اختر طريقة الدفع',
                          style: TextStyle(
                              color: AppColorsDark.mainTextDark,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _paymentMethodTile(
                        icon: Icons.attach_money,
                        label: 'نقدي',
                        selected: method == 'cash',
                        onTap: () => setSheetState(() => method = 'cash'),
                      ),
                      const SizedBox(height: 8),
                      _paymentMethodTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'بالمحفظة',
                        selected: method == 'wallet',
                        onTap: () => setSheetState(() => method = 'wallet'),
                      ),
                      const SizedBox(height: 20),

                      Text('اختر مبلغ الدفع',
                          style: TextStyle(
                              color: AppColorsDark.mainTextDark,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _amountOptionTile(
                        label: 'دفع كامل المبلغ',
                        trailing: _money.format(remaining),
                        selected: fullPayment,
                        onTap: () => setSheetState(() {
                          fullPayment = true;
                          amountController.text = remaining.toStringAsFixed(2);
                        }),
                      ),
                      const SizedBox(height: 8),
                      _amountOptionTile(
                        label: 'دفع جزء من المبلغ',
                        trailing: null,
                        selected: !fullPayment,
                        onTap: () => setSheetState(() {
                          fullPayment = false;
                          amountController.clear();
                        }),
                      ),
                      if (!fullPayment) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: amountController,
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          textDirection: TextDirection.rtl,
                          onChanged: (_) => setSheetState(() {}),
                          style: TextStyle(color: AppColorsDark.mainTextDark),
                          decoration: InputDecoration(
                            hintText: 'أدخل المبلغ',
                            suffixText: 'EGP',
                            filled: true,
                            fillColor: AppColorsDark.bgColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: payNow <= 0
                              ? null
                              : () => Navigator.pop(ctx, true),
                          child: const Text('تأكيد الدفع',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final rawPayAmount = fullPayment
        ? remaining
        : (double.tryParse(amountController.text) ?? 0.0);
    final payAmount = rawPayAmount > remaining ? remaining : rawPayAmount;
    if (payAmount <= 0) return;

    await _submitPayment(
      saleId: saleId,
      sale: s,
      method: method == 'cash' ? 'cash' : 'wallet',
      payAmount: payAmount,
      totalRemaining: remaining,
    );
  }

  Widget _sheetStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(color: AppColorsDark.mainTextLight, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColorsDark.bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColorsDark.mainTextLight, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: AppColorsDark.mainTextDark)),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.blueAccent : AppColorsDark.mainTextLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountOptionTile({
    required String label,
    required String? trailing,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColorsDark.bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.blueAccent : AppColorsDark.mainTextLight,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: AppColorsDark.mainTextDark)),
            ),
            if (trailing != null)
              Text(trailing,
                  style: TextStyle(
                      color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPayment({
    required int saleId,
    required Map<String, dynamic> sale,
    required String method,
    required double payAmount,
    required double totalRemaining,
  }) async {
    try {
      final currentRole = (Session.currentRole ?? '').toLowerCase().trim();
      final currentUser = (Session.currentUsername ?? '').trim();
      final newPaidAmount = _paidAmount(sale) + payAmount;

      await DBHelper.instance.markSaleAsPaid(
        saleId,
        paymentMethod: method,
        paidAmount: newPaidAmount,
        paidBy: currentRole != 'admin' && currentUser.isNotEmpty
            ? currentUser
            : null,
        paidAt: currentRole != 'admin' && currentUser.isNotEmpty
            ? DateTime.now()
            : null,
      );

      final isFullyPaid = payAmount >= totalRemaining;

      // لو الدفع كامل: تختفي الفاتورة من القائمة لأنها بقت مدفوعة بالكامل.
      // لو الدفع جزئي: تفضل الفاتورة ظاهرة بحالة "جزئي" عشان تقدر تفلتر عليها.
      setState(() {
        if (isFullyPaid) {
          credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
          saleItemsCache.remove(saleId);
        } else {
          final idx =
          credits.indexWhere((r) => (r['id'] as num).toInt() == saleId);
          if (idx != -1) credits[idx]['paid_amount'] = newPaidAmount;
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(isFullyPaid ? 'تم تسجيل الدفع بالكامل' : 'تم تسجيل الدفعة الجزئية'),
        ),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      debugPrint('markAsPaid error: $e');
      if (!mounted) return;
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
        title: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
              child: Text('حذف الفاتورة',
                  style: TextStyle(color: AppColorsDark.mainTextDark))),
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('هل تريد حذف الفاتورة #$saleId؟',
              style: TextStyle(color: AppColorsDark.mainTextDark)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء',
                style: TextStyle(color: AppColorsDark.mainTextDark)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      credits.removeWhere((r) => (r['id'] as num).toInt() == saleId);
      saleItemsCache.remove(saleId);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text('تم الحذف'),
      ),
    ));
  }

  void _viewInvoiceDetails(Map<String, dynamic> s) {
    final saleId = (s['id'] as num).toInt();
    final items = saleItemsCache[saleId] ?? [];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('INV-${saleId.toString().padLeft(4, '0')}',
              style: TextStyle(color: AppColorsDark.mainTextDark)),
        ),
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items
                  .map((it) => ListTile(
                dense: true,
                title: Text((it['product_name'] ?? '').toString(),
                    style:
                    TextStyle(color: AppColorsDark.mainTextDark)),
                trailing: Text(
                    '${it['quantity']} × ${(it['price'] as num?)?.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: AppColorsDark.mainTextLight)),
              ))
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إغلاق',
                style: TextStyle(color: AppColorsDark.mainTextDark)),
          ),
        ],
      ),
    );
  }

  // ------------------ UI: stat card ------------------
  Widget _statCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String unit,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColorsDark.bgCardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: AppColorsDark.mainTextLight, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(unit,
                      style: TextStyle(
                          color: AppColorsDark.mainTextLight, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ UI: filter dropdown ------------------
  Widget _dropdownFilter<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
              TextStyle(color: AppColorsDark.mainTextLight, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColorsDark.bgCardColor,
                style: TextStyle(color: AppColorsDark.mainTextDark),
                items: items
                    .map((e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(itemLabel(e)),
                ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateFilter() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('التاريخ',
              style:
              TextStyle(color: AppColorsDark.mainTextLight, fontSize: 12)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: AppColorsDark.bgCardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: AppColorsDark.mainTextLight),
                  const SizedBox(width: 8),
                  Text(
                    _selectedDate == null
                        ? 'اختر تاريخ'
                        : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                    style: TextStyle(color: AppColorsDark.mainTextDark),
                  ),
                  if (_selectedDate != null) ...[
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _selectedDate = null),
                      child: Icon(Icons.close,
                          size: 14, color: AppColorsDark.mainTextLight),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------ UI: status badge ------------------
  Widget _statusBadge(_InvoiceStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: status.color.withOpacity(0.4)),
      ),
      child: Text(status.label,
          style: TextStyle(
              color: status.color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // ------------------ Build ------------------
  // ------------------ Full-width custom table ------------------
  // ترتيب الأعمدة هنا هو ترتيب "القراءة" (RTL) فالعمود الأول بيظهر في أقصى اليمين
  static const List<int> _colFlex = [
    2, // رقم الفاتورة
    2, // اسم العميل
    2, // اسم الكاشير
    3, // المنتجات
    2, // المبلغ المستحق
    2, // تاريخ الفاتورة
    2, // الحالة
    3, // الإجراءات
  ];

  Widget _buildInvoicesTable(List<Map<String, dynamic>> list) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: AppColorsDark.bgCardColor,
            child: Row(
              children: [
                _headerCell('رقم الفاتورة', _colFlex[0]),
                _headerCell('اسم العميل', _colFlex[1]),
                _headerCell('اسم الكاشير', _colFlex[2]),
                _headerCell('المنتجات', _colFlex[3]),
                _headerCell('المبلغ المستحق', _colFlex[4]),
                _headerCell('تاريخ الفاتورة', _colFlex[5]),
                _headerCell('الحالة', _colFlex[6]),
                _headerCell('الإجراءات', _colFlex[7], alignEnd: true),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Colors.white12),
            itemBuilder: (context, index) => _invoiceRow(list[index]),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(String label, int flex, {bool alignEnd = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.start : TextAlign.center,
        style: TextStyle(
            color: AppColorsDark.mainTextDark,
            fontWeight: FontWeight.w600,
            fontSize: 13),
      ),
    );
  }

  Widget _invoiceRow(Map<String, dynamic> s) {
    final saleId = (s['id'] as num).toInt();
    final items = saleItemsCache[saleId] ?? [];
    final remaining = _remaining(s);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _colFlex[0],
            child: Text(
              'INV-${saleId.toString().padLeft(4, '0')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColorsDark.mainColor, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: _colFlex[1],
            child: Text(
              (s['customer_name'] ?? '').toString(),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColorsDark.mainTextDark),
            ),
          ),
          Expanded(
            flex: _colFlex[2],
            child: Text(
              (s['cashier_username'] ?? '').toString(),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColorsDark.mainTextDark),
            ),
          ),
          Expanded(
            flex: _colFlex[3],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (items.isNotEmpty)
                  Text('${items.length} منتجات',
                      style: TextStyle(
                          color: AppColorsDark.mainTextLight, fontSize: 11)),
                ...items.take(2).map((it) => Text(
                  '${it['quantity']} × ${(it['product_name'] ?? '')}',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColorsDark.mainTextLight, fontSize: 11),
                )),
                if (items.isEmpty)
                  Text('-', style: TextStyle(color: AppColorsDark.mainTextLight)),
              ],
            ),
          ),
          Expanded(
            flex: _colFlex[4],
            child: Text(
              _money.format(remaining),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: _colFlex[5],
            child: Text(
              _formatTime((s['date'] ?? '').toString()),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColorsDark.mainTextLight, fontSize: 12),
            ),
          ),
          Expanded(
            flex: _colFlex[6],
            child: Center(child: _statusBadge(_statusOf(s))),
          ),
          Expanded(
            flex: _colFlex[7],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () => _openPaymentSheet(s),
                  icon: const Icon(Icons.credit_card,
                      size: 16, color: Colors.white),
                  label: const Text('تم الدفع',
                      style: TextStyle(color: Colors.white)),
                ),
                IconButton(
                  onPressed: () {
                    showMenu(
                      context: context,
                      position: const RelativeRect.fromLTRB(200, 300, 0, 0),
                      items: [
                        PopupMenuItem(
                          onTap: () => _viewInvoiceDetails(s),
                          child: const Text('عرض التفاصيل'),
                        ),
                        PopupMenuItem(
                          onTap: () => _deleteCredit(saleId),
                          child: const Text('حذف',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    );
                  },
                  icon: Icon(Icons.more_vert,
                      color: Theme.of(context).iconTheme.color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        title: Text(
          'الفواتير التي لم يتم دفعها',
          style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loadCredits,
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- search ----
              CustomFormField(
                hint: 'بحث برقم الفاتورة / اسم العميل / اسم الكاشير',
                onChanged: (v) => setState(() => query = v),
                centerHint: true,
              ),
              const SizedBox(height: 16),

              // ---- stat cards ----
              Row(
                children: [
                  _statCard(
                    icon: Icons.description_outlined,
                    color: Colors.redAccent,
                    label: 'فواتير غير مدفوعة',
                    value: '$_totalInvoicesCount',
                    unit: 'فاتورة',
                  ),
                  const SizedBox(width: 12),
                  _statCard(
                    icon: Icons.account_balance_wallet_outlined,
                    color: Colors.purpleAccent,
                    label: 'إجمالي المبلغ المستحق',
                    value: _money.format(_totalRemaining),
                    unit: 'جنيه',
                  ),
                  const SizedBox(width: 12),
                  _statCard(
                    icon: Icons.event_available,
                    color: Colors.orangeAccent,
                    label: 'عدد فواتير اليوم',
                    value: '$_todayInvoicesCount',
                    unit: 'فاتورة',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- filters ----
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColorsDark.bgCardColor.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dateFilter(),
                    const SizedBox(width: 10),
                    _dropdownFilter<String>(
                      label: 'اسم الكاشير',
                      value: _selectedCashier,
                      items: _cashierOptions,
                      itemLabel: (v) => v,
                      onChanged: (v) =>
                          setState(() => _selectedCashier = v ?? 'الكل'),
                    ),
                    const SizedBox(width: 10),
                    _dropdownFilter<_InvoiceStatus?>(
                      label: 'حالة الدفع',
                      value: _selectedStatus,
                      items: const [
                        null,
                        _InvoiceStatus.unpaid,
                        _InvoiceStatus.partial,
                      ],
                      itemLabel: (v) => v == null ? 'الكل' : v.label,
                      onChanged: (v) => setState(() => _selectedStatus = v),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _selectedDate = null;
                          _selectedCashier = 'الكل';
                          _selectedStatus = null;
                        }),
                        icon: const Icon(Icons.filter_alt_off, size: 16),
                        label: const Text('تصفية'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- table ----
              list.isEmpty
                  ? const EmptyStateCard(
                icon: Icons.receipt_long,
                title: 'لا توجد فواتير',
                message: 'لا توجد فواتير آجلة مطابقة لهذا البحث.',
              )
                  : _buildInvoicesTable(list),
            ],
          ),
        ),
      ),
    );
  }
}