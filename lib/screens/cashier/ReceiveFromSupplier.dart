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
  State<ReceiveFromSupplierScreen> createState() =>
      _ReceiveFromSupplierScreenState();
}

class _ReceiveFromSupplierScreenState extends State<ReceiveFromSupplierScreen> {
  final _formKey = GlobalKey<FormState>();

  final _barcodeCtrl = TextEditingController(); // اختياري
  final _nameCtrl = TextEditingController();
  final _unitsCtrl = TextEditingController(text: '0');
  final _purchasePricePerUnitCtrl = TextEditingController();
  final _sellingPriceIfNewCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();
  final _existingUnitsCtrl = TextEditingController(text: '0');

  // Focus nodes
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _unitsFocusNode = FocusNode();
  final FocusNode _purchaseUnitFocusNode = FocusNode();
  final FocusNode _sellingFocusNode = FocusNode();
  final FocusNode _paidFocusNode = FocusNode();

  String _paymentType = 'cash_or_credit'; // 'cash_or_credit' or 'wallet'
  bool _loading = false;
  bool _paidTouched = false;
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateComputedPaid();
    });
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _nameCtrl.dispose();
    _unitsCtrl.dispose();
    _purchasePricePerUnitCtrl.dispose();
    _sellingPriceIfNewCtrl.dispose();
    _paidAmountCtrl.dispose();
    _existingUnitsCtrl.dispose();

    _barcodeFocusNode.dispose();
    _nameFocusNode.dispose();
    _unitsFocusNode.dispose();
    _purchaseUnitFocusNode.dispose();
    _sellingFocusNode.dispose();
    _paidFocusNode.dispose();

    super.dispose();
  }

  int _parseInt(String? s) {
    if (s == null) return 0;
    return int.tryParse(s) ?? 0;
  }

  double _parseDouble(String? s) {
    if (s == null) return 0.0;
    return double.tryParse(s.replaceAll(',', '')) ?? 0.0;
  }

  double _computeTotalCost() {
    final units = _parseInt(_unitsCtrl.text);
    final rawUnitText = _purchasePricePerUnitCtrl.text.trim();
    final purchasePerUnit = rawUnitText.isEmpty
        ? null
        : double.tryParse(rawUnitText.replaceAll(',', ''));
    return units * (purchasePerUnit ?? 0.0);
  }

  void _updateComputedPaid() {
    final total = _computeTotalCost();
    if (!_paidTouched) {
      _paidAmountCtrl.text = total.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _fillProductFields(Map<String, dynamic> product) {
    _selectedProductId = (product['id'] as num?)?.toInt();
    final name = (product['name'] ?? '').toString();
    final unitsInCarton = (product['units_in_carton'] != null)
        ? (int.tryParse(product['units_in_carton'].toString()) ?? 1)
        : 1;
    final totalUnits = (product['total_units'] != null)
        ? (int.tryParse(product['total_units'].toString()) ?? 0)
        : 0;

    final purchasePrice = (product['purchase_price'] != null)
        ? double.tryParse(product['purchase_price'].toString()) ?? 0.0
        : 0.0;
    final sellingPrice = (product['selling_price'] != null)
        ? double.tryParse(product['selling_price'].toString()) ?? 0.0
        : 0.0;

    if (name.isNotEmpty) _nameCtrl.text = name;

    _existingUnitsCtrl.text = totalUnits.toString();

    if (purchasePrice > 0) {
      final unitPrice = purchasePrice / (unitsInCarton > 0 ? unitsInCarton : 1);
      _purchasePricePerUnitCtrl.text = unitPrice.toStringAsFixed(2);
    } else {
      _purchasePricePerUnitCtrl.clear();
    }

    if (sellingPrice > 0) {
      _sellingPriceIfNewCtrl.text = sellingPrice.toStringAsFixed(2);
    }
  }

  Future<Map<String, dynamic>?> _chooseProductDialog(
    List<Map<String, dynamic>> products,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: Text(
            'اختر المنتج',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColorsDark.mainTextDark),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final product = products[index];
                final name = (product['name'] ?? '').toString();
                final stock = (product['total_units'] as num?)?.toInt() ?? 0;
                final purchase = (product['purchase_price'] as num?)
                        ?.toDouble()
                        .toStringAsFixed(2) ??
                    '0.00';
                return ListTile(
                  title: Text(name,
                      style: TextStyle(color: AppColorsDark.mainTextDark)),
                  subtitle: Text(
                    'المخزون: $stock | سعر الشراء: $purchase',
                    style: TextStyle(color: AppColorsDark.mainTextLight),
                  ),
                  onTap: () => Navigator.pop(ctx, product),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: Theme.of(ctx).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Lookup product from local SQLite by barcode and autofill form fields
  Future<void> _lookupBarcode() async {
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty) {
      // nothing to lookup
      return;
    }

    setState(() => _loading = true);
    try {
      final matches = await DBHelper.instance.getProductsByBarcodeList(barcode);
      final p = matches.length == 1
          ? matches.first
          : matches.length > 1
              ? await _chooseProductDialog(matches)
              : null;
      if (p != null) {
        _fillProductFields(p);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('تم ملء بيانات المنتج تلقائياً.'))));
        _paidTouched = false;
        _updateComputedPaid();
      } else {
        _selectedProductId = null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('المنتج غير موجود'))));
      }
    } catch (e) {
      debugPrint('Barcode lookup error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('خطأ أثناء البحث عن المنتج: $e'))));
    }
    setState(() => _loading = false);
  }

  Future<bool> _submit() async {
    if (!_formKey.currentState!.validate()) return false;
    setState(() => _loading = true);

    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final unitsInput = int.tryParse(_unitsCtrl.text) ?? 0;
    double? purchasePerUnit = _purchasePricePerUnitCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_purchasePricePerUnitCtrl.text.replaceAll(',', ''));

    final sellingIfNew = _sellingPriceIfNewCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_sellingPriceIfNewCtrl.text.replaceAll(',', ''));

    final rawPaid =
        double.tryParse(_paidAmountCtrl.text.replaceAll(',', '')) ?? 0.0;

    try {
      final totalCost = unitsInput * (purchasePerUnit ?? 0.0);

      double paid = rawPaid;
      if (paid < 0) paid = 0.0;
      if (paid > totalCost) paid = totalCost;

      // compute credit (what remains to be paid)
      final double creditAmount =
          (totalCost - paid) < 0 ? 0.0 : (totalCost - paid);
      final String paymentTypeToSave =
          _paymentType == 'wallet' ? 'wallet' : (paid > 0 ? 'cash' : 'credit');

      final data = await DBHelper.instance.receiveFromSupplier(
        barcode: barcode,
        name: name,
        productId: _selectedProductId,
        cartons: 0,
        units: unitsInput,
        purchasePricePerCarton: null,
        purchasePricePerUnit: purchasePerUnit,
        sellingPricePerUnitIfNew: sellingIfNew,
        unitsInCartonIfNew: 1,
        receivedBy: Session.currentUsername ?? 'unknown',
        paymentType: paymentTypeToSave,
        paidAmount: paid,
      );

      if (data['status'] == 'ok') {
        final totalCostRes =
            double.tryParse((data['total_cost'] ?? totalCost).toString()) ??
                totalCost;
        final paidRes =
            double.tryParse((data['paid_amount'] ?? paid).toString()) ?? paid;
        final dueRes = double.tryParse(
                (data['due_amount'] ?? (totalCostRes - paidRes)).toString()) ??
            (totalCostRes - paidRes);

        // try to read server returned credit, fallback to computed dueRes
        final creditRes = dueRes;

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColorsDark.bgCardColor,
            title: Center(
                child: Text('تم الاستلام',
                    style: TextStyle(color: AppColorsDark.mainTextDark))),
            content: Text(
              'تم تسجيل الاستلام.\nالإجمالي: ${totalCostRes.toStringAsFixed(2)}\nالمدفوع: ${paidRes.toStringAsFixed(2)}\nالمتبقي/آجل: ${creditRes.toStringAsFixed(2)}.',
              style: TextStyle(color: AppColorsDark.mainTextDark),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: AppColorsDark.bgColor),
                onPressed: () => Navigator.of(context).pop(),
                child: Text('حسناً',
                    style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black
                            : Colors.white)),
              ),
            ],
          ),
        );

        // reset form
        _formKey.currentState!.reset();
        _unitsCtrl.text = '0';
        _purchasePricePerUnitCtrl.clear();
        _sellingPriceIfNewCtrl.clear();
        _existingUnitsCtrl.text = '0';
        _selectedProductId = null;
        // set paid to total after reset to be consistent with computed default
        _paidAmountCtrl.text = totalCostRes.toStringAsFixed(2);
        _paidTouched = false;

        setState(() => _loading = false);
        return true;
      } else {
        final message = data['message'] ?? 'حدث خطأ غير متوقع';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Directionality(
                textDirection: TextDirection.rtl, child: Text(message))));
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
              textDirection: TextDirection.rtl,
              child: Text('حدث خطأ أثناء الإرسال: $e'))));
    }

    setState(() => _loading = false);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final computedTotal = _computeTotalCost();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        iconTheme: IconThemeData(
          color: Theme.of(context).iconTheme.color,
        ),
        title: Text(
          'استلام بضاعة من المورد',
          style: TextStyle(
            fontSize: 20,
            color: AppColorsDark.mainTextDark,
          ),
        ),
      ),
      // ADD: keyboard-aware padding and disable bounce
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 56.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barcode + lookup button
                    Row(
                      children: [
                        Expanded(
                          child: CustomFormField(
                            controller: _barcodeCtrl,
                            autoFocus: true,
                            label: true,
                            hint: 'باركود (اختياري)',
                            focusNode: _barcodeFocusNode,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) {
                              _lookupBarcode();
                              FocusScope.of(context)
                                  .requestFocus(_nameFocusNode);
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    CustomFormField(
                      controller: _nameCtrl,
                      label: true,
                      hint: 'اسم المنتج',
                      focusNode: _nameFocusNode,
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty)
                          return 'اسم المنتج مطلوب';
                        return null;
                      },
                      // onFieldSubmitted: (_) => FocusScope.of(context)
                      //     .requestFocus(_cartonsFocusNode),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Expanded(
                        //   child: CustomFormField(
                        //     controller: _cartonsCtrl,
                        //     label: true,
                        //     hint: 'عدد الكراتين',
                        //     focusNode: _cartonsFocusNode,
                        //     textInputAction: TextInputAction.next,
                        //     keyboardType: TextInputType.number,
                        //     onChanged: (_) => _updateComputedPaid(),
                        //     onFieldSubmitted: (_) => FocusScope.of(context)
                        //         .requestFocus(_unitsFocusNode),
                        //   ),
                        // ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CustomFormField(
                            controller: _unitsCtrl,
                            label: true,
                            keyboardType: TextInputType.number,
                            hint: 'عدد وحدات فردية',
                            focusNode: _unitsFocusNode,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _updateComputedPaid(),
                            // onFieldSubmitted: (_) => FocusScope.of(context)
                            //     .requestFocus(_unitsInCartonFocusNode),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Expanded(
                        //   child: CustomFormField(
                        //     // controller: _unitsInCartonCtrl,
                        //     label: true,
                        //     keyboardType: TextInputType.number,
                        //     hint: 'وحدات في الكرتونة',
                        //     // focusNode: _unitsInCartonFocusNode,
                        //     textInputAction: TextInputAction.next,
                        //     onChanged: (_) => _updateComputedPaid(),
                        //     // onFieldSubmitted: (_) => FocusScope.of(context)
                        //     //     .requestFocus(_purchaseCartonFocusNode),
                        //   ),
                        // ),
                        // const SizedBox(width: 10),
                        // Expanded(
                        //   child: CustomFormField(
                        //     // controller: _purchasePricePerCartonCtrl,
                        //     label: true,
                        //     keyboardType:
                        //         TextInputType.numberWithOptions(decimal: true),
                        //     hint: 'سعر شراء للكرتونة',
                        //     focusNode: _purchaseCartonFocusNode,
                        //     textInputAction: TextInputAction.next,
                        //     onChanged: (_) => _updateComputedPaid(),
                        //     onFieldSubmitted: (_) => FocusScope.of(context)
                        //         .requestFocus(_purchaseUnitFocusNode),
                        //   ),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CustomFormField(
                      controller: _purchasePricePerUnitCtrl,
                      label: true,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      hint: 'سعر شراء للوحدة (اختياري)',
                      focusNode: _purchaseUnitFocusNode,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _updateComputedPaid(),
                      onFieldSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(_sellingFocusNode),
                    ),
                    const SizedBox(height: 10),
                    CustomFormField(
                      controller: _sellingPriceIfNewCtrl,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      hint: 'سعر بيع للوحدة (إجباري إذا المنتج جديد)',
                      focusNode: _sellingFocusNode,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _updateComputedPaid(),
                      onFieldSubmitted: (_) =>
                          FocusScope.of(context).requestFocus(_paidFocusNode),
                    ),
                    const SizedBox(height: 10),

                    // existing units (informational)
                    CustomFormField(
                      controller: _existingUnitsCtrl,
                      hint: 'الوحدات الحالية (معلومة من المنتج)',
                      keyboardType: TextInputType.number,
                    ),

                    const SizedBox(height: 10),

                    // نوع الدفع
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'نوع الدفع',
                          style: TextStyle(
                            color: AppColorsDark.mainTextDark,
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
                            items: [
                              DropdownMenuItem(
                                  value: 'cash_or_credit',
                                  child: Text('نقدي / آجل',
                                      style: TextStyle(
                                          color: AppColorsDark.mainTextDark))),
                              DropdownMenuItem(
                                  value: 'wallet',
                                  child: Text('دفع بالمحفظة',
                                      style: TextStyle(
                                          color: AppColorsDark.mainTextDark))),
                            ],
                            onChanged: (v) {
                              setState(
                                  () => _paymentType = v ?? 'cash_or_credit');
                              _updateComputedPaid();
                            },
                            dropdownColor: AppColorsDark.bgCardColor,
                            style: TextStyle(
                                color: AppColorsDark.mainTextDark,
                                fontSize: 15),
                            iconEnabledColor: Theme.of(context).iconTheme.color,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 6),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),
                    Text(
                      'إجمالي التكلفة: ${computedTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColorsDark.mainTextDark,
                          fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    CustomFormField(
                      controller: _paidAmountCtrl,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      hint: 'المبلغ المدفوع الآن',
                      focusNode: _paidFocusNode,
                      textInputAction: TextInputAction.done,
                      onChanged: (v) {
                        _paidTouched = true;
                      },
                      onFieldSubmitted: (_) async {
                        await _submit();
                      },
                    ),
                    const SizedBox(height: 72),
                    CustomButton(
                      text: 'تسجيل الاستلام',
                      onPressed: () async {
                        final ok = await _submit();
                        if (ok) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            CashierScreen.routName,
                            (Route<dynamic> route) => false,
                          );
                        }
                      },
                      isLoading: _loading,
                    ),
                    const SizedBox(height: 72),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
