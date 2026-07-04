import 'package:cashgo_supermarket/widgets/custom_form.dart';
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

class _AdminLaterPurchasesScreenState
    extends State<AdminLaterPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filteredRows = [];
  bool _loading = false;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _money =
  NumberFormat.currency(locale: 'ar', symbol: 'EGP ');

  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load(date: selectedDate);
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredRows = List.from(_rows);
      } else {
        _filteredRows = _rows.where((r) {
          final name =
          (r['product_name'] ?? r['supplier_name'] ?? r['barcode'] ?? '')
              .toString()
              .toLowerCase();
          final id = (r['id'] ?? r['receipt_id'] ?? '').toString();
          return name.contains(q) || id.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _load({DateTime? date}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DBHelper.instance.getCreditPurchaseReceipts();
      final filtered = rows.where((r) {
        final pt = _normalizePaymentType(r);
        final creditAmt = _getNumericField(r,
            ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount']);
        if (!(pt == 'credit' || creditAmt > 0.0)) return false;
        if (date == null) return true;
        final raw =
        (r['created_at'] ?? r['receipt_date'] ?? r['date'] ?? '').toString();
        final dt = _parseDateOnly(raw);
        if (dt == null) return false;
        return dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      }).toList();
      setState(() {
        _rows = filtered;
        _filteredRows = List.from(filtered);
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error: $e\n$st');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _fmtDate(String s) {
    if (s.isEmpty) return '-';
    try {
      return DateFormat('yyyy-MM-dd').format(DateTime.parse(s));
    } catch (_) {
      return s.split('T').first;
    }
  }

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
    if (pt.contains('credit') || pt.contains('آجل')) return 'credit';
    return 'cash';
  }

  double _getNumericField(Map<String, dynamic> r, List<String> keys,
      [double fallback = 0.0]) {
    for (final k in keys) {
      if (!r.containsKey(k)) continue;
      final v = r[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      final parsed = double.tryParse(v.toString().replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  String _getStatus(Map<String, dynamic> r) {
    final paid = _getNumericField(
        r, ['total_paid', 'paid_amount', 'paid', 'paidAmount']);
    final due = _getNumericField(
        r, ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount']);
    if (due <= 0.01) return 'مدفوع';
    if (paid > 0) return 'جزئي';
    return 'لم يتم الدفع';
  }

  Future<void> _processPaymentOnServer({
    required int receiptId,
    required double amount,
    required String method,
    Map<String, dynamic>? receiptRow,
  }) async {
    setState(() => _loading = true);
    try {
      await DBHelper.instance
          .addPaymentToPurchase(receiptId, amount, paymentMethod: method);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
              textDirection: TextDirection.rtl, child: Text('تمت المعالجة')),
        ));
      await _load(date: selectedDate);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('فشل تسجيل الدفعة: $e')),
        ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markPaid(int id) async {
    final r = _rows.firstWhere(
            (e) => (e['id'] ?? e['receipt_id']) == id,
        orElse: () => {});
    if (r.isEmpty) return;
    final due = _getNumericField(
        r, ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount']);
    if (due <= 0) return;
    _showPaymentSheet(r);
  }

  Future<void> _partialPay(int id) async {
    final r = _rows.firstWhere(
            (e) => (e['id'] ?? e['receipt_id']) == id,
        orElse: () => {});
    if (r.isEmpty) return;
    _showPaymentSheet(r, forcePartial: true);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      await _load(date: selectedDate);
    }
  }

  String _formatSelectedDate(DateTime dt) =>
      DateFormat('dd/MM/yyyy').format(dt);

  // ─── Bottom Sheet ───────────────────────────────────────────────────────────

  void _showPaymentSheet(Map<String, dynamic> r, {bool forcePartial = false}) {
    final id = (r['id'] ?? r['receipt_id']) is num
        ? (r['id'] ?? r['receipt_id']) as int
        : 0;
    final title = r['product_name'] ?? r['barcode'] ?? '—';
    final due = _getNumericField(
        r, ['credit_amount', 'creditAmount', 'due', 'due_amount', 'dueAmount']);
    final paid =
    _getNumericField(r, ['total_paid', 'paid_amount', 'paid', 'paidAmount']);
    final total = paid + due;

    String selectedMethod = 'cash';
    String selectedAmountType = forcePartial ? 'partial' : 'full';
    final amountController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColorsDark.bgCardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'INV-${id.toString().padLeft(4, '0')}',
                          style: TextStyle(
                              color: AppColorsDark.mainColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        Text(title,
                            style: TextStyle(
                                color: AppColorsDark.mainTextLight,
                                fontSize: 12)),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.shopping_bag_outlined,
                            color: AppColorsDark.mainColor, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'تسديد المشتريات الآجلة',
                          style: TextStyle(
                              color: AppColorsDark.mainTextDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, color: AppColorsDark.mainTextDark),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Amount cards ──
                Row(
                  children: [
                    Expanded(
                      child: _sheetCard('إجمالي الفاتورة',
                          _money.format(total), Colors.blueAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sheetCard(
                          'المتبقي', _money.format(due), Colors.greenAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Payment method ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اختر طريقة التسديد',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 10),
                          _methodTile(
                            label: 'نقدي',
                            value: 'cash',
                            icon: Icons.payments_rounded,
                            iconColor: Colors.greenAccent,
                            selected: selectedMethod,
                            onTap: () =>
                                setSheet(() => selectedMethod = 'cash'),
                          ),
                          const SizedBox(height: 8),
                          _methodTile(
                            label: 'محفظة',
                            value: 'wallet',
                            icon: Icons.account_balance_wallet_rounded,
                            iconColor: Colors.purpleAccent,
                            selected: selectedMethod,
                            onTap: () =>
                                setSheet(() => selectedMethod = 'wallet'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),

                    // ── Amount type ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اختر مبلغ التسديد',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () =>
                                setSheet(() => selectedAmountType = 'full'),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: 'full',
                                  groupValue: selectedAmountType,
                                  onChanged: (v) =>
                                      setSheet(() => selectedAmountType = v!),
                                  activeColor: AppColorsDark.mainColor,
                                ),
                                Expanded(
                                    child: Text('دفع كامل المبلغ',
                                        style: TextStyle(
                                            color: AppColorsDark.mainTextDark,
                                            fontSize: 13))),
                                Text(
                                  _money.format(due),
                                  style: TextStyle(
                                      color: AppColorsDark.mainColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () =>
                                setSheet(() => selectedAmountType = 'partial'),
                            child: Row(
                              children: [
                                Radio<String>(
                                  value: 'partial',
                                  groupValue: selectedAmountType,
                                  onChanged: (v) =>
                                      setSheet(() => selectedAmountType = v!),
                                  activeColor: AppColorsDark.mainColor,
                                ),
                                Text('دفع جزء من المبلغ',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          if (selectedAmountType == 'partial') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: amountController,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              style:
                              TextStyle(color: AppColorsDark.mainTextDark),
                              decoration: InputDecoration(
                                hintText: 'أدخل المبلغ',
                                hintStyle: TextStyle(
                                    color: AppColorsDark.mainTextLight),
                                suffixText: 'EGP',
                                suffixStyle: TextStyle(
                                    color: AppColorsDark.mainTextLight),
                                filled: true,
                                fillColor: AppColorsDark.bgColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Confirm button ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColorsDark.mainColor,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      double amount;
                      if (selectedAmountType == 'full') {
                        amount = due;
                      } else {
                        amount = double.tryParse(
                            amountController.text.replaceAll(',', '')) ??
                            0.0;
                        if (amount <= 0) return;
                        if (amount > due) amount = due;
                      }
                      await _processPaymentOnServer(
                          receiptId: id,
                          amount: amount,
                          method: selectedMethod,
                          receiptRow: r);
                    },
                    child: const Text('تأكيد التسديد',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColorsDark.bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColorsDark.mainTextLight, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _methodTile({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String selected,
    required VoidCallback onTap,
  }) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColorsDark.mainColor.withOpacity(0.12)
              : AppColorsDark.bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColorsDark.mainColor
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(label,
                style:
                TextStyle(color: AppColorsDark.mainTextDark, fontSize: 13)),
            const Spacer(),
            Radio<String>(
              value: value,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: AppColorsDark.mainColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Widgets ────────────────────────────────────────────────────────────────

  Widget _summaryCard(
      String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColorsDark.bgCardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    color: AppColorsDark.mainTextLight, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(
              color: AppColorsDark.mainTextLight,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _statusBadge(String status) {
    final color = status == 'مدفوع'
        ? Colors.greenAccent
        : status == 'جزئي'
        ? Colors.orangeAccent
        : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(status,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final totalCredit = _rows.fold(
        0.0,
            (sum, r) => sum +
            _getNumericField(r, [
              'credit_amount',
              'creditAmount',
              'due',
              'due_amount',
              'dueAmount'
            ]));
    final totalPaid = _rows.fold(
        0.0,
            (sum, r) => sum +
            _getNumericField(
                r, ['total_paid', 'paid_amount', 'paid', 'paidAmount']));

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: Text('المشتريات الآجلة',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: GestureDetector(
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatSelectedDate(selectedDate),
                    style: TextStyle(
                        color: AppColorsDark.mainTextDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.calendar_today_rounded,
                      size: 15, color: AppColorsDark.mainTextLight),
                ],
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'إعادة تحميل',
            onPressed: () => _load(date: selectedDate),
            icon: Icon(Icons.refresh, color: Theme.of(context).iconTheme.color),
          ),
        ],
      ),
      body: _loading
          ? ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => LoadingShimmer(
          height: 60,
          borderRadius: BorderRadius.circular(10),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      )
          : _error != null
          ? Center(
          child: Text('حدث خطأ: $_error',
              style: const TextStyle(color: Colors.redAccent)))
          : Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // ── Summary Cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _summaryCard(
                      'إجمالي المشتريات الآجلة',
                      _money.format(totalCredit),
                      Colors.blueAccent,
                      Icons.shopping_bag_outlined),
                  const SizedBox(width: 10),
                  _summaryCard(
                      'إجمالي المدفوع',
                      _money.format(totalPaid),
                      Colors.orangeAccent,
                      Icons.receipt_rounded),
                  const SizedBox(width: 10),
                  _summaryCard(
                      'المتبقي',
                      _money.format(totalCredit),
                      Colors.greenAccent,
                      Icons.account_balance_wallet_rounded),
                  const SizedBox(width: 10),
                  _summaryCard(
                      'عدد الفواتير',
                      '${_rows.length}',
                      Colors.purpleAccent,
                      Icons.format_list_numbered_rounded),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Search ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: AppColorsDark.mainTextDark),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search,
                      color: Theme.of(context).iconTheme.color),
                  hintText: 'ابحث برقم الفاتورة أو اسم المورد',
                  hintStyle:
                  TextStyle(color: AppColorsDark.mainTextLight),
                  filled: true,
                  fillColor: AppColorsDark.bgCardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Table Header ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColorsDark.bgCardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _headerCell('رقم الفاتورة', flex: 2),
                  _headerCell('اسم المورد', flex: 3),
                  _headerCell('تاريخ الفاتورة', flex: 2),
                  _headerCell('إجمالي الفاتورة', flex: 2),
                  _headerCell('المدفوع', flex: 2),
                  _headerCell('المتبقي', flex: 2),
                  _headerCell('الحالة', flex: 2),
                  _headerCell('الإجراءات', flex: 2),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // ── Rows ──
            Expanded(
              child: _filteredRows.isEmpty
                  ? const EmptyStateCard(
                icon: Icons.pending_actions,
                title: 'لا توجد مشتريات آجلة',
                message:
                'لا توجد مشتريات آجلة في هذا التاريخ.',
              )
                  : ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                itemCount: _filteredRows.length,
                separatorBuilder: (_, __) =>
                const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final r = _filteredRows[i];
                  final id =
                  (r['id'] ?? r['receipt_id']) is num
                      ? (r['id'] ?? r['receipt_id']) as int
                      : (i + 1);
                  final title =
                      r['product_name'] ?? r['barcode'] ?? '—';
                  final paid = _getNumericField(r, [
                    'total_paid',
                    'paid_amount',
                    'paid',
                    'paidAmount'
                  ]);
                  final due = _getNumericField(r, [
                    'credit_amount',
                    'creditAmount',
                    'due',
                    'due_amount',
                    'dueAmount'
                  ]);
                  final total = paid + due;
                  final created =
                  (r['created_at'] ?? r['receipt_date'] ?? '')
                      .toString();
                  final status = _getStatus(r);

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColorsDark.bgCardColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'INV-${id.toString().padLeft(4, '0')}',
                            style: TextStyle(
                                color: AppColorsDark.mainColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            title,
                            style: TextStyle(
                                color:
                                AppColorsDark.mainTextDark,
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _fmtDate(created),
                            style: TextStyle(
                                color:
                                AppColorsDark.mainTextLight,
                                fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _money.format(total),
                            style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _money.format(paid),
                            style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            _money.format(due),
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _statusBadge(status),
                        ),
                        Expanded(
                          flex: 2,
                          child: Row(
                            children: [
                              if (status != 'مدفوع')
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _showPaymentSheet(r),
                                  icon: const Icon(
                                      Icons.payment_rounded,
                                      size: 13),
                                  label: const Text('دفع',
                                      style: TextStyle(
                                          fontSize: 12)),
                                  style:
                                  ElevatedButton.styleFrom(
                                    backgroundColor:
                                    AppColorsDark.mainColor,
                                    foregroundColor:
                                    Colors.white,
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 10,
                                        vertical: 6),
                                    shape:
                                    RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                            8)),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap,
                                  ),
                                )
                              else
                                OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(
                                      Icons
                                          .remove_red_eye_rounded,
                                      size: 13),
                                  label: const Text('عرض',
                                      style: TextStyle(
                                          fontSize: 12)),
                                  style:
                                  OutlinedButton.styleFrom(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 10,
                                        vertical: 6),
                                    shape:
                                    RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius
                                            .circular(
                                            8)),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                    MaterialTapTargetSize
                                        .shrinkWrap,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              PopupMenuButton<String>(
                                iconColor: Theme.of(context)
                                    .iconTheme
                                    .color,
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                onSelected: (v) async {
                                  if (v == 'partial')
                                    await _partialPay(id);
                                  else if (v == 'full')
                                    await _markPaid(id);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'partial',
                                      child: Text('دفع جزء')),
                                  PopupMenuItem(
                                      value: 'full',
                                      child: Text(
                                          'دفعت بالكامل')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}