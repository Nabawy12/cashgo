// lib/screens/cashier/ReceiveFromSupplier.dart
import 'package:cashgo/screens/cashier/cashier_screen.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';

import '../../models/login.dart';
import '../../services/db/db_helper.dart';

class ReceiveFromSupplierScreen extends StatefulWidget {
  const ReceiveFromSupplierScreen({Key? key}) : super(key: key);

  @override
  State<ReceiveFromSupplierScreen> createState() => _ReceiveFromSupplierScreenState();
}

class _ReceiveFromSupplierScreenState extends State<ReceiveFromSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _cartonsCtrl = TextEditingController();
  final _unitsCtrl = TextEditingController();
  final _unitsInCartonCtrl = TextEditingController();
  final _purchasePricePerCartonCtrl = TextEditingController();
  final _purchasePricePerUnitCtrl = TextEditingController();
  final _sellingPriceIfNewCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();
  // merged نقدي و آجل into a single option: we'll infer "credit" vs "cash" from paid vs total
  String _paymentType = 'cash_or_credit';
  bool _loading = false;

  // NEW: track whether user manually edited the paid field
  bool _paidTouched = false;

  @override
  void initState() {
    super.initState();
    // تأكد من أن قيمة الحقل المدفوع مناسبة لحالة الدفع الابتدائية
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateComputedPaid());
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _cartonsCtrl.dispose();
    _unitsCtrl.dispose();
    _unitsInCartonCtrl.dispose();
    _purchasePricePerCartonCtrl.dispose();
    _purchasePricePerUnitCtrl.dispose();
    _sellingPriceIfNewCtrl.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  double _parseDouble(String? s) {
    if (s == null) return 0.0;
    return double.tryParse(s.replaceAll(',', '')) ?? 0.0;
  }

  int _parseInt(String? s) {
    if (s == null) return 0;
    return int.tryParse(s) ?? 0;
  }

  /// Compute total cost using the same logic DBHelper.receiveFromSupplier uses:
  /// - carton price if provided
  /// - fallback to perUnit * unitsInCarton when carton price missing
  /// - per-unit price is preferred when provided otherwise derived from carton price
  double _computeTotalCost() {
    final cartons = _parseInt(_cartonsCtrl.text);
    final units = _parseInt(_unitsCtrl.text);
    final unitsInCarton = _parseInt(_unitsInCartonCtrl.text).clamp(1, 1000000);
    final purchasePerCarton = _purchasePricePerCartonCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_purchasePricePerCartonCtrl.text.replaceAll(',', ''));
    final purchasePerUnit = _purchasePricePerUnitCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_purchasePricePerUnitCtrl.text.replaceAll(',', ''));

    // determine carton unit price and unit price
    double cartonPrice = 0.0;
    double unitPrice = 0.0;

    if (purchasePerCarton != null) {
      cartonPrice = purchasePerCarton;
      unitPrice = (purchasePerUnit != null) ? purchasePerUnit : (unitsInCarton > 0 ? purchasePerCarton / unitsInCarton : 0.0);
    } else {
      // no carton price
      if (purchasePerUnit != null) {
        unitPrice = purchasePerUnit;
        cartonPrice = purchasePerUnit * unitsInCarton;
      } else {
        // nothing provided -> 0
        cartonPrice = 0.0;
        unitPrice = 0.0;
      }
    }

    final total = cartons * cartonPrice + units * unitPrice;
    return total;
  }

  /// Update paid field depending on selected payment type and computed total.
  /// Behavior (after merging cash & credit into one option):
  /// - For the merged cash/credit option we default paid to full total unless user edited it.
  ///   If user later leaves a paid < total, that will be treated as credit on submit.
  /// - For wallet (محفظة إلكترونية) we keep the previous behavior (default to full unless user edited).
  void _updateComputedPaid() {
    final total = _computeTotalCost();
    // For both combined cash/credit and wallet, default to full payment unless user edited.
    if (!_paidTouched) {
      _paidAmountCtrl.text = total.toStringAsFixed(2);
    }
    setState(() {}); // refresh UI if needed
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final cartons = int.tryParse(_cartonsCtrl.text) ?? 0;
    final units = int.tryParse(_unitsCtrl.text) ?? 0;
    final unitsInCarton = int.tryParse(_unitsInCartonCtrl.text) ?? 1;
    final purchasePerCarton = double.tryParse(_purchasePricePerCartonCtrl.text.replaceAll(',', ''));
    final purchasePerUnit = double.tryParse(_purchasePricePerUnitCtrl.text.replaceAll(',', ''));
    final sellingIfNew = double.tryParse(_sellingPriceIfNewCtrl.text.replaceAll(',', ''));
    final rawPaid = double.tryParse(_paidAmountCtrl.text.replaceAll(',', '')) ?? 0.0;

    try {
      final totalCost = _computeTotalCost();

      // normalize paid value: cannot be negative and should not (sensibly) exceed total
      double paid = rawPaid;
      if (paid < 0) paid = 0.0;
      // allow paying up to total only (for all types). If you want to allow overpayments, change here.
      if (paid > totalCost) paid = totalCost;

      final dbHelper = DBHelper.instance;

      final res = await dbHelper.receiveFromSupplier(
        barcode: barcode.isEmpty ? null : barcode,
        name: name.isEmpty ? null : name,
        cartons: cartons,
        units: units,
        purchasePricePerCarton: purchasePerCarton,
        purchasePricePerUnit: purchasePerUnit,
        sellingPricePerUnitIfNew: sellingIfNew,
        unitsInCartonIfNew: unitsInCarton,
        receivedBy: Session.currentUsername!,
        paymentType: _paymentType,
        paidAmount: paid,
      );

      if (res['status'] == 'need_selling_price') {
        // product not found and UI must ask for selling price
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج غير موجود. الرجاء إدخال سعر البيع وإنشاء المنتج.')));
      } else if (res['status'] == 'ok') {
        final totalCostRes = (res['total_cost'] ?? 0.0) as double;
        final due = (res['due_amount'] ?? 0.0) as double;
        final added = res['added_units'] ?? 0;

        // After persisting the purchase_receipt, we need to reflect any paid amount
        // on the appropriate ledger/table:
        // - merged cash/credit:
        //     * if paid < total -> treat as partial credit payment (apply the "credit" behavior)
        //     * if paid == total -> treat as cash (keep previous cash behavior)
        // - wallet payments -> deduct from card_wallet (ledger)
        try {
          final currentUser = await dbHelper.getCurrentUser();
          final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : Session.currentUsername ?? 'admin';

          if (paid > 0) {
            if (_paymentType == 'wallet') {
              await dbHelper.ensureCardWalletTable();
              await dbHelper.changeCardWalletBy(
                -paid,
                username,
                note: 'Payment for purchase (wallet) -${paid.toStringAsFixed(2)}',
              );
            } else {
              // merged cash_or_credit -> infer: paid < totalCost => partial credit, paid == totalCost => full cash
              final latestStarting = await dbHelper.getLatestDrawerStartingAmount();
              final newStarting = latestStarting - paid;
              final notePrefix = (paid < totalCost)
                  ? 'Partial payment for credit purchase'
                  : 'Full cash payment for purchase';
              await dbHelper.setDrawerStartingAmount(
                newStarting,
                username,
                note: '$notePrefix -${paid.toStringAsFixed(2)}',
              );
            }
          }


          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Center(child: const Text('تم الاستلام',style: TextStyle(color: Colors.white),)),
              content: Text(
                'تم إضافة $added وحدة. الإجمالي: ${totalCostRes.toStringAsFixed(2)}. المدفوع: ${paid.toStringAsFixed(2)}. المتبقي: ${due.toStringAsFixed(2)}.',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                    style: TextButton.styleFrom(
                        backgroundColor: AppColorsDark.bgColor
                    ),
                    onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً',style: TextStyle(color: Colors.white),)),
              ],
            ),
          );

          // Reset form
          _formKey.currentState!.reset();
          _cartonsCtrl.text = '0';
          _unitsCtrl.text = '0';
          _unitsInCartonCtrl.text = '1';
          _purchasePricePerCartonCtrl.clear();
          _purchasePricePerUnitCtrl.clear();
          _sellingPriceIfNewCtrl.clear();

          // reset paid: for the merged behavior we default to full total after submit
          _paidAmountCtrl.text = totalCostRes.toStringAsFixed(2);
          _paidTouched = false;

          // reload any relevant aggregates (optional)
          await _loadAfterSubmit();
        } catch (e) {
          debugPrint('Error while applying post-payment effects: $e');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ أثناء تحديث الدرج/المحفظة: $e')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    }

    setState(() => _loading = false);
  }

  /// helper to reload any totals after successful submit (optional)
  Future<void> _loadAfterSubmit() async {
    try {
      // If you have functions to reload a parent page or totals, call them here.
      // For example: reloading wallet/drawer totals if this screen shows them.
      // Currently we keep it simple: just do nothing or you can integrate with a provider.
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // compute total to show live (optional)
    final computedTotal = _computeTotalCost();

    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: const IconThemeData(
          color: Colors.white70,
        ),
        title: const Text(
          'استلام بضاعة من المورد',
          style: TextStyle(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomFormField(
                  controller: _barcodeCtrl,
                  hint: 'باركود (اجباري)',
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _nameCtrl,
                  hint: 'اسم المنتج',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CustomFormField(
                        controller: _cartonsCtrl,
                        hint: 'عدد الكراتين',
                        onChanged: (_) => _updateComputedPaid(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CustomFormField(
                        controller: _unitsCtrl,
                        keyboardType: TextInputType.number,
                        hint: 'عدد وحدات فردية',
                        onChanged: (_) => _updateComputedPaid(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CustomFormField(
                        controller: _unitsInCartonCtrl,
                        keyboardType: TextInputType.number,
                        hint: 'وحدات في الكرتونة',
                        onChanged: (_) => _updateComputedPaid(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CustomFormField(
                        controller: _purchasePricePerCartonCtrl,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        hint: 'سعر شراء للكرتونة',
                        onChanged: (_) => _updateComputedPaid(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _purchasePricePerUnitCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  hint: 'سعر شراء للوحدة (اختياري)',
                  onChanged: (_) => _updateComputedPaid(),
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _sellingPriceIfNewCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  hint: 'سعر بيع للوحدة (إجباري إذا المنتج جديد)',
                  onChanged: (_) => _updateComputedPaid(),
                ),
                const SizedBox(height: 10),

                // نوع الدفع - مدمج (نقدي/آجل) و محفظة إلكترونية
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'نوع الدفع',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),

                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColorsDark.bgCardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColorsDark.strokColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonFormField<String>(
                        value: _paymentType,
                        items: const [
                          DropdownMenuItem(value: 'cash_or_credit', child: Text('نقدي / آجل', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 'wallet', child: Text('محفظة إلكترونية', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          setState(() => _paymentType = v ?? 'cash_or_credit');
                          _updateComputedPaid();
                        },
                        dropdownColor: AppColorsDark.bgCardColor,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        iconEnabledColor: Colors.white70,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                // show computed total for clarity (white text)
                Text(
                  'إجمالي التكلفة: ${computedTotal.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white,fontSize: 20),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _paidAmountCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  hint: 'المبلغ المدفوع الآن',
                  onChanged: (v) {
                    // mark that user edited the paid field manually
                    _paidTouched = true;
                  },
                ),
                const SizedBox(height: 20),
                CustomButton(
                  text: 'تسجيل الاستلام',
                  onPressed: () {
                    _submit();
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      CashierScreen.routName,
                          (Route<dynamic> route) => false,
                    );
                  },
                  isLoading: _loading,
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
