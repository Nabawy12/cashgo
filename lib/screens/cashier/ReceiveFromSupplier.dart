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
  final _cartonsCtrl = TextEditingController(text: '0');
  final _unitsCtrl = TextEditingController(text: '0');
  final _unitsInCartonCtrl = TextEditingController(text: '1');
  final _purchasePricePerCartonCtrl = TextEditingController();
  final _purchasePricePerUnitCtrl = TextEditingController();
  final _sellingPriceIfNewCtrl = TextEditingController();
  final _paidAmountCtrl = TextEditingController();
  final _existingUnitsCtrl = TextEditingController(text: '0');

  // Focus nodes
  final FocusNode _barcodeFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _cartonsFocusNode = FocusNode();
  final FocusNode _unitsFocusNode = FocusNode();
  final FocusNode _unitsInCartonFocusNode = FocusNode();
  final FocusNode _purchaseCartonFocusNode = FocusNode();
  final FocusNode _purchaseUnitFocusNode = FocusNode();
  final FocusNode _sellingFocusNode = FocusNode();
  final FocusNode _paidFocusNode = FocusNode();

  String _paymentType = 'cash_or_credit'; // 'cash_or_credit' or 'wallet'
  bool _loading = false;
  bool _paidTouched = false;

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
    _cartonsCtrl.dispose();
    _unitsCtrl.dispose();
    _unitsInCartonCtrl.dispose();
    _purchasePricePerCartonCtrl.dispose();
    _purchasePricePerUnitCtrl.dispose();
    _sellingPriceIfNewCtrl.dispose();
    _paidAmountCtrl.dispose();
    _existingUnitsCtrl.dispose();

    _barcodeFocusNode.dispose();
    _nameFocusNode.dispose();
    _cartonsFocusNode.dispose();
    _unitsFocusNode.dispose();
    _unitsInCartonFocusNode.dispose();
    _purchaseCartonFocusNode.dispose();
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
    final cartons = _parseInt(_cartonsCtrl.text);
    final units = _parseInt(_unitsCtrl.text);
    final unitsInCarton = _parseInt(_unitsInCartonCtrl.text).clamp(1, 1000000);

    final rawCartonText = _purchasePricePerCartonCtrl.text.trim();
    final rawUnitText = _purchasePricePerUnitCtrl.text.trim();

    final purchasePerCarton = rawCartonText.isEmpty
        ? null
        : double.tryParse(rawCartonText.replaceAll(',', ''));

    double? purchasePerUnit = rawUnitText.isEmpty
        ? null
        : double.tryParse(rawUnitText.replaceAll(',', ''));

    if (purchasePerUnit != null &&
        purchasePerUnit == 0.0 &&
        purchasePerCarton != null) {
      purchasePerUnit = null;
    }

    double cartonPrice = 0.0;
    double unitPrice = 0.0;

    if (purchasePerCarton != null) {
      cartonPrice = purchasePerCarton;
      unitPrice = (purchasePerUnit != null)
          ? purchasePerUnit
          : (unitsInCarton > 0 ? purchasePerCarton / unitsInCarton : 0.0);
    } else {
      if (purchasePerUnit != null) {
        unitPrice = purchasePerUnit;
        cartonPrice = purchasePerUnit * unitsInCarton;
      } else {
        cartonPrice = 0.0;
        unitPrice = 0.0;
      }
    }

    final total = cartons * cartonPrice + units * unitPrice;
    return total;
  }

  void _updateComputedPaid() {
    final total = _computeTotalCost();
    if (!_paidTouched) {
      _paidAmountCtrl.text = total.toStringAsFixed(2);
    }
    setState(() {});
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
      final p = await DBHelper.instance.getProductByBarcode(barcode);
      if (p != null) {
        final name = (p['name'] ?? '').toString();
        final unitsInCarton = (p['units_in_carton'] != null)
            ? (int.tryParse(p['units_in_carton'].toString()) ?? 1)
            : 1;
        final totalUnits = (p['total_units'] != null)
            ? (int.tryParse(p['total_units'].toString()) ?? 0)
            : 0;

        final purchasePrice = (p['purchase_price'] != null)
            ? double.tryParse(p['purchase_price'].toString()) ?? 0.0
            : 0.0;
        final sellingPrice = (p['selling_price'] != null)
            ? double.tryParse(p['selling_price'].toString()) ?? 0.0
            : 0.0;

        if (name.isNotEmpty) _nameCtrl.text = name;

        _unitsInCartonCtrl.text =
            unitsInCarton > 0 ? unitsInCarton.toString() : '1';
        _existingUnitsCtrl.text = totalUnits.toString();

        if (purchasePrice > 0) {
          _purchasePricePerCartonCtrl.text = purchasePrice.toStringAsFixed(2);
          if (unitsInCarton > 0) {
            final unitPrice = purchasePrice / unitsInCarton;
            _purchasePricePerUnitCtrl.text = unitPrice.toStringAsFixed(2);
          } else {
            _purchasePricePerUnitCtrl.text = '0.00';
          }
        } else {
          _purchasePricePerCartonCtrl.clear();
          _purchasePricePerUnitCtrl.clear();
        }

        if (sellingPrice > 0) {
          _sellingPriceIfNewCtrl.text = sellingPrice.toStringAsFixed(2);
        }

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Directionality(
                textDirection: TextDirection.rtl,
                child: Text('تم ملء بيانات المنتج تلقائياً.'))));
        _paidTouched = false;
        _updateComputedPaid();
      } else {
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
    final cartonsInput = int.tryParse(_cartonsCtrl.text) ?? 0;
    final unitsInput = int.tryParse(_unitsCtrl.text) ?? 0;
    final unitsInCartonInput = int.tryParse(_unitsInCartonCtrl.text) ?? 1;

    double? purchasePerCarton = _purchasePricePerCartonCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_purchasePricePerCartonCtrl.text.replaceAll(',', ''));
    double? purchasePerUnit = _purchasePricePerUnitCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_purchasePricePerUnitCtrl.text.replaceAll(',', ''));

    final sellingIfNew = _sellingPriceIfNewCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_sellingPriceIfNewCtrl.text.replaceAll(',', ''));

    final rawPaid =
        double.tryParse(_paidAmountCtrl.text.replaceAll(',', '')) ?? 0.0;

    if (purchasePerUnit != null &&
        purchasePerUnit == 0.0 &&
        purchasePerCarton != null) {
      purchasePerUnit = null;
    }

    double computeTotalFromValues({
      required int cartons,
      required int units,
      required int unitsInCarton,
      double? purchaseCarton,
      double? purchaseUnit,
    }) {
      final uic = unitsInCarton.clamp(1, 1000000);
      double cartonPrice = 0.0;
      double unitPrice = 0.0;

      if (purchaseCarton != null) {
        cartonPrice = purchaseCarton;
        unitPrice = (purchaseUnit != null)
            ? purchaseUnit
            : (uic > 0 ? purchaseCarton / uic : 0.0);
      } else {
        if (purchaseUnit != null) {
          unitPrice = purchaseUnit;
          cartonPrice = purchaseUnit * uic;
        } else {
          cartonPrice = 0.0;
          unitPrice = 0.0;
        }
      }

      return cartons * cartonPrice + units * unitPrice;
    }

    try {
      final totalCost = computeTotalFromValues(
        cartons: cartonsInput,
        units: unitsInput,
        unitsInCarton: unitsInCartonInput,
        purchaseCarton: purchasePerCarton,
        purchaseUnit: purchasePerUnit,
      );

      double paid = rawPaid;
      if (paid < 0) paid = 0.0;
      if (paid > totalCost) paid = totalCost;

      // compute credit (what remains to be paid)
      final double creditAmount =
          (totalCost - paid) < 0 ? 0.0 : (totalCost - paid);

      final data = await DBHelper.instance.receiveFromSupplier(
        barcode: barcode,
        name: name,
        cartons: cartonsInput,
        units: unitsInput,
        purchasePricePerCarton: purchasePerCarton,
        purchasePricePerUnit: purchasePerUnit,
        sellingPricePerUnitIfNew: sellingIfNew,
        unitsInCartonIfNew: unitsInCartonInput,
        receivedBy: Session.currentUsername ?? 'unknown',
        paymentType: creditAmount > 0 ? 'credit' : _paymentType,
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
        _cartonsCtrl.text = '0';
        _unitsCtrl.text = '0';
        _unitsInCartonCtrl.text = '1';
        _purchasePricePerCartonCtrl.clear();
        _purchasePricePerUnitCtrl.clear();
        _sellingPriceIfNewCtrl.clear();
        _existingUnitsCtrl.text = '0';
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
                      onFieldSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(_cartonsFocusNode),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: CustomFormField(
                            controller: _cartonsCtrl,
                            label: true,
                            hint: 'عدد الكراتين',
                            focusNode: _cartonsFocusNode,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _updateComputedPaid(),
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_unitsFocusNode),
                          ),
                        ),
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
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_unitsInCartonFocusNode),
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
                            label: true,
                            keyboardType: TextInputType.number,
                            hint: 'وحدات في الكرتونة',
                            focusNode: _unitsInCartonFocusNode,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _updateComputedPaid(),
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_purchaseCartonFocusNode),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CustomFormField(
                            controller: _purchasePricePerCartonCtrl,
                            label: true,
                            keyboardType:
                                TextInputType.numberWithOptions(decimal: true),
                            hint: 'سعر شراء للكرتونة',
                            focusNode: _purchaseCartonFocusNode,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _updateComputedPaid(),
                            onFieldSubmitted: (_) => FocusScope.of(context)
                                .requestFocus(_purchaseUnitFocusNode),
                          ),
                        ),
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
