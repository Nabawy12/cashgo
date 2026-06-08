// admin_later_purchases_screen.dart
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/login.dart';
import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';
import '../../widgets/Loading/Admin/invoice_cash.dart';
import '../../widgets/empty_state_card.dart';

class AdminLaterPurchasesScreen extends StatefulWidget {
  const AdminLaterPurchasesScreen({Key? key}) : super(key: key);

  @override
  State<AdminLaterPurchasesScreen> createState() =>
      _AdminLaterPurchasesScreenState();
}

class _AdminLaterPurchasesScreenState extends State<AdminLaterPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  // فلتر التاريخ
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load(date: selectedDate);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({DateTime? date}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _fetchReceiptsFromServer(date: date);

      // فلترة محلياً لإظهار سجلات الآجل (credit) فقط، أو التي تحتوي على credit_amount>0،
      // ولليوم المحدد إن طُلب
      final filtered = rows.where((r) {
        final pt = _normalizePaymentType(r);
        final creditAmt = _getNumericField(r, [
          'credit_amount',
          'creditAmount',
          'due',
          'due_amount',
          'dueAmount'
        ]);
        // show if declared payment_type is credit OR credit_amount > 0
        if (!(pt == 'credit' || creditAmt > 0.0)) return false;

        if (date == null) return true;
        final raw = (r['created_at'] ?? r['receipt_date'] ?? r['date'] ?? '')
            .toString();
        final dt = _parseDateOnly(raw);
        if (dt == null) return false;
        return dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      }).toList();

      setState(() {
        _rows = filtered;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading credit purchase receipts: $e\n$st');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchReceiptsFromServer(
      {DateTime? date}) async {
    return DBHelper.instance.getCreditPurchaseReceipts();
  }

  // ------------ helpers for payment processing ------------

  String _fmtDate(String s) {
    if (s.isEmpty) return s;
    try {
      final d = DateTime.parse(s);
      return DateFormat('yyyy-MM-dd HH:mm').format(d);
    } catch (_) {
      return s;
    }
  }

  Color? _paymentColor(String paymentType) {
    switch (paymentType) {
      case 'cash':
        return Colors.greenAccent;
      case 'wallet':
        return Colors.blueAccent;
      case 'card':
        return Colors.orangeAccent[200];
      case 'credit':
        return Colors.redAccent;
      default:
        return Colors.grey[400];
    }
  }

  Color get _dialogTextColor => Theme.of(context).brightness == Brightness.light
      ? Colors.black
      : Colors.white;

  Color get _cardTextColor => Theme.of(context).brightness == Brightness.light
      ? Colors.black87
      : Colors.white;

  Color get _cardLabelColor => Theme.of(context).brightness == Brightness.light
      ? Colors.grey[700]!
      : Colors.grey[400]!;

  Color get _dialogBackgroundColor =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : AppColorsDark.bgCardColor;

  Color get _dialogSecondaryButtonColor =>
      Theme.of(context).brightness == Brightness.light
          ? Colors.grey.shade200
          : AppColorsDark.bgColor;

  DateTime? _parseDateOnly(String raw) {
    if (raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '') ?? 0;
        final mo = int.tryParse(m.group(2) ?? '') ?? 0;
        final d = int.tryParse(m.group(3) ?? '') ?? 0;
        if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
      }
      final parts =
          raw.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 3) {
        if (parts[0].length == 4) {
          final y = int.tryParse(parts[0]) ?? 0;
          final mo = int.tryParse(parts[1]) ?? 0;
          final d = int.tryParse(parts[2]) ?? 0;
          if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
        } else {
          final d = int.tryParse(parts[0]) ?? 0;
          final mo = int.tryParse(parts[1]) ?? 0;
          final y = int.tryParse(parts[2]) ?? 0;
          if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
        }
      }
    }
    return null;
  }

  String _normalizePaymentType(Map<String, dynamic> r) {
    final pt =
        (r['payment_type'] ?? r['paymentType'] ?? r['paymentTypeStored'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (pt.isEmpty) return 'cash';
    if (pt == 'wallet' || pt == 'card' || pt == 'cash' || pt == 'credit')
      return pt;
    if (pt.contains('card')) return 'card';
    if (pt.contains('wallet') || pt.contains('محفظ')) return 'wallet';
    if (pt.contains('credit') || pt.contains('آجل') || pt.contains('قرض'))
      return 'credit';
    return 'cash';
  }

  double _getNumericField(Map<String, dynamic> r, List<String> keys,
      [double fallback = 0.0]) {
    for (final k in keys) {
      if (!r.containsKey(k)) continue;
      final v = r[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) continue;
      final parsed = double.tryParse(s.replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  Widget _buildPaymentChip(String paymentType, {double creditAmount = 0.0}) {
    final label = paymentType == 'cash'
        ? 'نقدي'
        : paymentType == 'wallet'
            ? 'دفع بالمحفظة'
            : paymentType == 'card'
                ? 'بطاقة'
                : paymentType == 'credit'
                    ? 'آجل'
                    : paymentType;
    return Container(
      decoration: BoxDecoration(
        color: _paymentColor(paymentType)!.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: _paymentColor(paymentType) ?? Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
        child: Text(
          creditAmount > 0 && paymentType == 'credit'
              ? '$label (${creditAmount.toStringAsFixed(2)})'
              : label,
          style: TextStyle(color: _cardTextColor, fontSize: 12),
        ),
      ),
    );
  }

  /// Show dialog to choose payment method (cash/wallet) and confirm -> returns 'cash'|'wallet' or null
  Future<String?> _askForPaymentMethod({required bool isFullPayment}) async {
    final picked = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String selected = 'cash';
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            return AlertDialog(
              backgroundColor: _dialogBackgroundColor,
              title: Center(
                  child: Text(
                      isFullPayment ? 'دفع المبلغ كاملاً' : 'دفع جزء من المبلغ',
                      style: TextStyle(color: _dialogTextColor))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'cash',
                    groupValue: selected,
                    title:
                        Text('نقدي', style: TextStyle(color: _dialogTextColor)),
                    activeColor: AppColorsDark.mainColor,
                    onChanged: (v) => setState2(() => selected = v ?? 'cash'),
                  ),
                  RadioListTile<String>(
                    value: 'wallet',
                    groupValue: selected,
                    title: Text('دفع بالمحفظة',
                        style: TextStyle(color: _dialogTextColor)),
                    activeColor: AppColorsDark.mainColor,
                    onChanged: (v) => setState2(() => selected = v ?? 'wallet'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: _dialogSecondaryButtonColor,
                    foregroundColor: _dialogTextColor,
                  ),
                  onPressed: () => Navigator.of(ctx2).pop(null),
                  child: const Text('إلغاء'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: AppColorsDark.mainColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx2).pop(selected),
                  child: const Text('إتمام'),
                ),
              ],
            );
          }),
        );
      },
    );

    return picked;
  }

  /// Process payment locally in SQLite.
  Future<void> _processPaymentOnServer({
    required int receiptId,
    required double amount,
    required String method,
    Map<String, dynamic>? receiptRow,
  }) async {
    setState(() => _loading = true);
    try {
      await DBHelper.instance.addPaymentToPurchase(
        receiptId,
        amount,
        paymentMethod: method,
      );

      final currentRole = (Session.currentRole ?? '').toLowerCase().trim();
      final currentUser = (Session.currentUsername ?? '').trim();
      if (currentRole != 'admin' && currentUser.isNotEmpty) {
        debugPrint(
            '[CreditPayment] payment recorded on original purchase receipt only: amount=$amount method=$method cashier=$currentUser receiptId=$receiptId');
      }

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('تمت المعالجةً'),
          ),
        ));
      await _load(date: selectedDate);
    } catch (e) {
      debugPrint('Error processing payment: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('فشل تسجيل الدفعة: $e'),
          ),
        ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Mark fully paid (ask method then call server)
  Future<void> _markPaid(int id) async {
    final r = _rows.firstWhere(
        (e) =>
            ((e['id'] ?? e['receipt_id']) is num) &&
            (e['id'] ?? e['receipt_id']) == id,
        orElse: () => {});
    if (r.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('السند غير موجود'),
        ),
      ));
      return;
    }

    final due = _getNumericField(
        r,
        ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount'],
        0.0);
    if (due <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('لا يوجد مبلغ مستحق'),
        ),
      ));
      return;
    }

    final method = await _askForPaymentMethod(isFullPayment: true);
    if (method == null) return;
    await _processPaymentOnServer(
        receiptId: id, amount: due, method: method, receiptRow: r);
  }

  // Partial payment: ask amount then method then send
  Future<void> _partialPay(int id) async {
    final r = _rows.firstWhere(
        (e) =>
            ((e['id'] ?? e['receipt_id']) is num) &&
            (e['id'] ?? e['receipt_id']) == id,
        orElse: () => {});
    if (r.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('السند غير موجود'),
        ),
      ));
      return;
    }

    final due = _getNumericField(
        r,
        ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount'],
        0.0);
    if (due <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('لا يوجد مبلغ مستحق'),
        ),
      ));
      return;
    }

    final ctrl = TextEditingController();
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _dialogBackgroundColor,
        title: Center(
            child: Text('دفع جزء من المبلغ',
                style: TextStyle(color: _dialogTextColor))),
        content: CustomFormField(
          controller: ctrl,
          hint: 'المبلغ (<= ${due.toStringAsFixed(2)})',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: _dialogSecondaryButtonColor,
              foregroundColor: _dialogTextColor,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.mainColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('التالي'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    double amount = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0.0;
    if (amount <= 0) return;
    if (amount > due) amount = due;

    final method = await _askForPaymentMethod(isFullPayment: false);
    if (method == null) return;

    await _processPaymentOnServer(
        receiptId: id, amount: amount, method: method, receiptRow: r);
  }

  // ====== تاريخ ======
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      await _load(date: selectedDate);
    }
  }

  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: Text('المشتريات الآجلة',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        actions: [
          IconButton(
            tooltip: "إعادة تحميل",
            onPressed: () => _load(date: selectedDate),
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          )
        ],
      ),
      body: _loading
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
          : _error != null
              ? Center(
                  child: Text('حدث خطأ: $_error',
                      style: TextStyle(color: Colors.redAccent)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _pickDate,
                            child: Column(
                              children: [
                                Text('التاريخ',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextLight,
                                        fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(_formatSelectedDate(selectedDate),
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: _rows.isEmpty
                            ? const EmptyStateCard(
                                icon: Icons.pending_actions,
                                title: 'لا توجد مشتريات آجلة',
                                message: 'لا توجد مشتريات آجلة في هذا التاريخ.',
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                itemCount: _rows.length,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 20),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  final id = (r['id'] ?? r['receipt_id']) is num
                                      ? (r['id'] ?? r['receipt_id']) as int
                                      : (i + 1);
                                  final title =
                                      r['product_name'] ?? r['barcode'] ?? '—';

                                  // read paid from total_paid / paid_amount / paid
                                  final paid = _getNumericField(
                                      r,
                                      [
                                        'total_paid',
                                        'paid_amount',
                                        'paid',
                                        'paidAmount'
                                      ],
                                      0.0);

                                  // prefer credit_amount as "due", fallback to due/due_amount fields
                                  final due = _getNumericField(
                                      r,
                                      [
                                        'credit_amount',
                                        'creditAmount',
                                        'due',
                                        'due_amount',
                                        'dueAmount'
                                      ],
                                      0.0);

                                  final created = (r['created_at'] ??
                                          r['receipt_date'] ??
                                          '')
                                      .toString();
                                  final paymentType = _normalizePaymentType(r);

                                  return Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: Card(
                                      color: AppColorsDark.bgCardColor,
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      ConstrainedBox(
                                                        constraints:
                                                            const BoxConstraints(
                                                                minWidth: 160,
                                                                maxWidth: 520),
                                                        child: Text('$title',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                                color:
                                                                    _cardTextColor,
                                                                fontSize: 18,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold)),
                                                      ),
                                                      _buildPaymentChip(
                                                          paymentType,
                                                          creditAmount: due),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  _buildInfoRow("استلم:",
                                                      "${r['received_by'] ?? r['cashier_name'] ?? ''}"),
                                                  _buildInfoRow("كمية:",
                                                      "${r['cartons'] ?? 0} كرتينات + ${r['units'] ?? 0} وحدات"),
                                                  _buildInfoRow("المدفوع:",
                                                      paid.toStringAsFixed(2),
                                                      valueColor: Colors.green),
                                                  _buildInfoRow("المتبقي/آجل:",
                                                      due.toStringAsFixed(2),
                                                      valueColor: Colors
                                                          .redAccent[200]),
                                                  _buildInfoRow("التاريخ:",
                                                      _fmtDate(created)),
                                                ],
                                              ),
                                            ),
                                            PopupMenuButton<String>(
                                              iconColor: Theme.of(context)
                                                  .iconTheme
                                                  .color,
                                              onSelected: (v) async {
                                                if (v == 'partial') {
                                                  await _partialPay(id);
                                                } else if (v == 'full') {
                                                  await _markPaid(id);
                                                }
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'partial',
                                                    child: Text('دفع جزء')),
                                                PopupMenuItem(
                                                    value: 'full',
                                                    child:
                                                        Text('دفعت بالكامل')),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
                text: "$label ",
                style: TextStyle(color: _cardLabelColor, fontSize: 14)),
            TextSpan(
                text: value,
                style: TextStyle(
                    color: valueColor ?? _cardTextColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
