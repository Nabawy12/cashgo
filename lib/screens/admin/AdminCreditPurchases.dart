import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/db/db_helper.dart';
import '../../utils/colors.dart';

class AdminLaterPurchasesScreen extends StatefulWidget {
  const AdminLaterPurchasesScreen({Key? key}) : super(key: key);

  @override
  State<AdminLaterPurchasesScreen> createState() =>
      _AdminLaterPurchasesScreenState();
}

class _AdminLaterPurchasesScreenState extends State<AdminLaterPurchasesScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  // ===== جديد: فلتر التاريخ =====
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // نحمّل افتراضياً سجلات يوم اليوم
    _load(date: selectedDate);
  }

  /// الآن _load يدعم تمرير تاريخ (فلترة لليوم المحدد).
  Future<void> _load({DateTime? date}) async {
    setState(() => _loading = true);
    try {
      final rows = await DBHelper.instance.getCreditPurchaseReceipts();

      if (date != null) {
        // فلترة محلياً لنفس اليوم (year/month/day)
        _rows = rows.where((r) {
          final raw = (r['created_at'] ?? r['date'] ?? '').toString();
          final dt = _parseDateOnly(raw);
          if (dt == null) return false;
          return dt.year == date.year && dt.month == date.month && dt.day == date.day;
        }).toList();
      } else {
        _rows = rows;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Error loading credit purchase receipts: $e');
      rethrow;
    }
  }

  // ------------ helpers for payment processing ------------

  String _fmtDate(String s) {
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
      default:
        return Colors.grey[400];
    }
  }
  /// مساعد لتحليل التاريخ بصيغ متعددة إلى DateTime (يُستخدم للفلترة)
  DateTime? _parseDateOnly(String raw) {
    if (raw.isEmpty) return null;
    // محاولة تحويل مباشر من ISO
    try {
      final dt = DateTime.parse(raw);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      // محاولة regex yyyy-mm-dd
      final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
      if (m != null) {
        final y = int.tryParse(m.group(1) ?? '') ?? 0;
        final mo = int.tryParse(m.group(2) ?? '') ?? 0;
        final d = int.tryParse(m.group(3) ?? '') ?? 0;
        if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
      }
      // محاولة تفكيك أجزاء شائعة dd/mm/yyyy أو yyyy/mm/dd أو أجزاء مفصولة
      final parts = raw.split(RegExp(r'[\s/\\\-]')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 3) {
        // إذا الجزء الأول طول 4 => yyyy/mm/dd
        if (parts[0].length == 4) {
          final y = int.tryParse(parts[0]) ?? 0;
          final mo = int.tryParse(parts[1]) ?? 0;
          final d = int.tryParse(parts[2]) ?? 0;
          if (y > 0 && mo > 0 && d > 0) return DateTime(y, mo, d);
        } else {
          // افتراض dd/mm/yyyy
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
    final pt = (r['payment_type'] ?? r['paymentType'] ?? '').toString().trim().toLowerCase();
    if (pt.isEmpty) return 'cash';
    if (pt == 'wallet' || pt == 'card' || pt == 'cash') return pt;
    if (pt.contains('card')) return 'card';
    if (pt.contains('wallet') || pt.contains('محفظ')) return 'wallet';
    return 'cash';
  }


  Widget _buildPaymentChip(String paymentType) {
    final label = paymentType == 'cash'
        ? 'نقدي'
        : paymentType == 'wallet'
        ? 'محفظة إلكترونية'
        : paymentType == 'card'
        ? 'بطاقة'
        : paymentType;
    return Container(
      decoration: BoxDecoration(
        color: _paymentColor(paymentType)!.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _paymentColor(paymentType) ?? Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0,vertical: 8),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }

  // Ask payment method (cash / wallet) and then call processor
  /// Show a styled dialog with radio buttons and return the chosen method ('cash' or 'wallet').
  /// If user cancels, returns null.
  Future<void> _askPaymentMethodAndProcess({
    required int receiptId,
    required double amount,
    required double dueAmount,
    required bool isFullPayment,
  }) async {
    // Show a single dialog where the selection persists until the user confirms.
    final picked = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String selected = 'cash'; // default selection
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Center(
                child: Text(
                  isFullPayment ? 'دفع المبلغ كاملاً' : 'دفع جزء من المبلغ',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // show amount info
                  Text(
                    'المبلغ: EGP ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColorsDark.bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(children: [
                      RadioListTile<String>(
                        value: 'cash',
                        groupValue: selected,
                        title: const Text('نقدي', style: TextStyle(color: Colors.white)),
                        activeColor: AppColorsDark.mainColor,
                        onChanged: (v) => setState2(() => selected = v ?? 'cash'),
                      ),
                      Divider(height: 1, color: Colors.white12),
                      RadioListTile<String>(
                        value: 'wallet',
                        groupValue: selected,
                        title: const Text('محفظة إلكترونية', style: TextStyle(color: Colors.white)),
                        activeColor: AppColorsDark.mainColor,
                        onChanged: (v) => setState2(() => selected = v ?? 'wallet'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اختر طريقة الدفع ثم اضغط إتمام لتأكيد العملية.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () => Navigator.of(ctx2).pop(null),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.mainColor),
                  onPressed: () => Navigator.of(ctx2).pop(selected),
                  child: const Text('إتمام', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }),
        );
      },
    );

    // If user cancelled dialog
    if (picked == null) return;

    // call processor with the selected method
    await _processPayment(receiptId: receiptId, amount: amount, method: picked);
  }

  Future<void> _processPayment({
    required int receiptId,
    required double amount,
    required String method, // 'cash' | 'wallet'
  }) async {
    setState(() => _loading = true);
    final db = DBHelper.instance;
    final currentUser = await db.getCurrentUser();
    final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : 'admin';

    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المبلغ غير صالح')));
      setState(() => _loading = false);
      return;
    }

    try {
      if (method == 'wallet') {
        // check wallet balance
        await db.ensureCardWalletTable();
        final walletLatest = await db.getLatestCardWalletAmount();
        if (walletLatest + 0.000001 < amount) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الرصيد في المحفظة غير كافٍ: ${walletLatest.toStringAsFixed(2)}')));
          setState(() => _loading = false);
          return;
        }

        // deduct wallet first (reserve)
        await db.changeCardWalletBy(-amount, username, note: 'Payment towards purchase id $receiptId (-${amount.toStringAsFixed(2)})');

        // try to add payment
        try {
          await db.addPaymentToPurchase(receiptId, amount);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسجيل الدفعة (محفظة) EGP ${amount.toStringAsFixed(2)}')));
        } catch (e) {
          // rollback wallet
          try {
            await db.changeCardWalletBy(amount, username, note: 'Rollback payment reserve for purchase id $receiptId (+${amount.toStringAsFixed(2)})');
          } catch (roll) {
            debugPrint('Rollback wallet failed: $roll');
          }
          rethrow;
        }
      } else {
        // cash: subtract from drawer starting amount (record new starting = latest - amount)
        final latestStarting = await db.getLatestDrawerStartingAmount();
        final newStarting = latestStarting - amount;
        await db.setDrawerStartingAmount(newStarting, username, note: 'Payment for purchase id $receiptId (-${amount.toStringAsFixed(2)})');

        // try to add payment
        try {
          await db.addPaymentToPurchase(receiptId, amount);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تسجيل الدفعة نقداً EGP ${amount.toStringAsFixed(2)}')));
        } catch (e) {
          // rollback drawer to previous starting
          try {
            await db.setDrawerStartingAmount(latestStarting, username, note: 'Rollback payment for purchase id $receiptId (+${amount.toStringAsFixed(2)})');
          } catch (roll) {
            debugPrint('Rollback drawer failed: $roll');
          }
          rethrow;
        }
      }

      // success -> reload
      await _load(date: selectedDate);
    } catch (e) {
      debugPrint('Error processing payment: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل الدفعة: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------ handlers for menu actions ------------

  Future<void> _markPaid(int id) async {
    // full payment -> amount = due
    final r = _rows.firstWhere((e) => (e['id'] as num).toInt() == id);
    final due = (r['due_amount'] as num?)?.toDouble() ?? 0.0;
    if (due <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مبلغ مستحق')));
      return;
    }

    // ask payment method then process
    await _askPaymentMethodAndProcess(receiptId: id, amount: due, dueAmount: due, isFullPayment: true);
  }

  Future<void> _partialPay(int id) async {
    final r = _rows.firstWhere((e) => (e['id'] as num).toInt() == id);
    final due = (r['due_amount'] as num?)?.toDouble() ?? 0.0;
    if (due <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مبلغ مستحق')));
      return;
    }

    final ctrl = TextEditingController();
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgCardColor,
        title: Center(child: const Text('دفع جزء من المبلغ', style: TextStyle(color: Colors.white))),
        content: CustomFormField(
          controller: ctrl,
          hint: 'المبلغ (<= المبلغ المتبقي: ${due.toStringAsFixed(2)})',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('التالي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    double amount = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0.0;
    if (amount <= 0) return;
    if (amount > due) amount = due;

    // now ask payment method and process
    await _askPaymentMethodAndProcess(receiptId: id, amount: amount, dueAmount: due, isFullPayment: false);
  }

  // ------------ UI ------------

  // ====== جديد: اختيار التاريخ ======
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

  // عرض التاريخ day/month/year مثل 22/8/2025
  String _formatSelectedDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        title: const Text(
          'المشتريات الآجلة',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        actions: [
          IconButton(
            tooltip: "إعادة تحميل",
            onPressed: () => _load(date: selectedDate),
            icon: const Icon(Icons.refresh, color: Colors.white70),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Scrollbar(
        thumbVisibility: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickDate,
                    child: Column(
                      children: [
                        Text(
                          'التاريخ',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        // عرض التاريخ فقط بدون أيقونة
                        Text(
                          _formatSelectedDate(selectedDate),
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView.builder(
                itemCount: _rows.length,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final id = (r['id'] as num).toInt();
                  final title = r['product_name'] ?? r['barcode'] ?? '—';
                  final paid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
                  final due = (r['due_amount'] as num?)?.toDouble() ?? 0.0;
                  final created = r['created_at'] ?? '';
                  final paymentType = _normalizePaymentType(r);
                  final paidColor = _paymentColor(paymentType) ?? Colors.white;

                  // card style similar to paid screen: show payment chip and colored paid value
                  return Directionality(
                    textDirection: TextDirection.rtl,
                    child: Card(
                      color: AppColorsDark.bgCardColor,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$title',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildPaymentChip(paymentType),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow("استلم:", "${r['received_by'] ?? ''}"),
                                  _buildInfoRow("كمية:", "${r['cartons'] ?? 0} كرتينات + ${r['units'] ?? 0} وحدات"),
                                  _buildInfoRow("المدفوع:", paid.toStringAsFixed(2), valueColor:Colors.green),
                                  _buildInfoRow("المتبقي:", due.toStringAsFixed(2), valueColor: Colors.redAccent[200]),
                                  _buildInfoRow("التاريخ:", _fmtDate(created)),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              iconColor: Colors.white70,
                              onSelected: (v) async {
                                if (v == 'partial') {
                                  await _partialPay(id);
                                } else if (v == 'full') {
                                  await _markPaid(id);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'partial', child: Text('دفع جزء')),
                                PopupMenuItem(value: 'full', child: Text('دفعت بالكامل')),
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
          ],
        ),
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
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
