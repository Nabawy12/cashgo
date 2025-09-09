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
  // for showing/editing existing single units
  final _existingUnitsCtrl = TextEditingController(text: '0');

  // merged نقدي و آجل into a single option: we'll infer "credit" vs "cash" from paid vs total
  String _paymentType = 'cash_or_credit';
  bool _loading = false;

  // NEW: track whether user manually edited the paid field
  bool _paidTouched = false;

  // NEW: focus node so we can lookup when user finishes barcode input
  final FocusNode _barcodeFocusNode = FocusNode();

  // products cache for picker
  List<Map<String, dynamic>> _products = [];
  bool _loadingProducts = false;

  // human-readable current stock summary
  String _currentStockText = '';
  int? _selectedProductId;

  @override
  void initState() {
    super.initState();
    // تأكد من أن قيمة الحقل المدفوع مناسبة لحالة الدفع الابتدائية
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateComputedPaid();
      _loadProducts();
    });

    // when barcode field loses focus, try to lookup the product and autofill
    _barcodeFocusNode.addListener(() {
      if (!_barcodeFocusNode.hasFocus) {
        _lookupBarcode();
      }
    });
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final rows = await DBHelper.instance.getAllProducts();
      setState(() {
        _products = rows;
      });
    } catch (e) {
      debugPrint('Error loading products: $e');
    }
    setState(() => _loadingProducts = false);
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

  /// Helper: try to extract a numeric field from product map using several common keys
  double _extractDoubleFromProduct(Map<String, dynamic> p, List<String> keys) {
    for (final k in keys) {
      if (p.containsKey(k) && p[k] != null) {
        final v = p[k];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
      }
    }
    return 0.0;
  }

  String? _extractStringFromProduct(Map<String, dynamic> p, List<String> keys) {
    for (final k in keys) {
      if (p.containsKey(k) && p[k] != null) {
        return p[k].toString();
      }
    }
    return null;
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

  /// Try to lookup product by barcode and autofill fields when found.
  Future<void> _lookupBarcode() async {
    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _loading = true);
    try {
      final db = DBHelper.instance;

      final product = await db.getProductByBarcode(barcode);

      // debug print of DB row to help if keys differ
      debugPrint('LOOKUP product row: $product');

      if (product == null) {
        // nothing found: do not clear all fields but inform user
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يتم العثور على منتج بهذا الباركود.')));
      } else {
        _fillFieldsFromProduct(Map<String, dynamic>.from(product));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ملء بيانات المنتج تلقائياً.')));
      }
    } catch (e) {
      debugPrint('Barcode lookup error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء جلب بيانات المنتج: $e')));
    }
    setState(() => _loading = false);
  }

  void _fillFieldsFromProduct(Map<String, dynamic> p) {
    // remember selected product id
    try {
      _selectedProductId = (p['id'] != null) ? (p['id'] as num).toInt() : null;
    } catch (e) {
      _selectedProductId = null;
    }

    final name = _extractStringFromProduct(p, ['name', 'product_name', 'title', 'title_ar']);

    // units in carton
    int unitsInCarton = 0;
    try {
      if (p.containsKey('units_in_carton') && p['units_in_carton'] != null) unitsInCarton = (p['units_in_carton'] as num).toInt();
      else if (p.containsKey('unitsInCarton') && p['unitsInCarton'] != null) unitsInCarton = (p['unitsInCarton'] as num).toInt();
      else if (p.containsKey('unit_in_carton') && p['unit_in_carton'] != null) unitsInCarton = (p['unit_in_carton'] as num).toInt();
    } catch (e) {
      unitsInCarton = 0;
    }

    // try to determine total units using a few heuristics / possible keys
    int totalUnits = 0;
    try {
      if (p.containsKey('total_units') && p['total_units'] != null) {
        totalUnits = (p['total_units'] as num).toInt();
      } else if (p.containsKey('units') && p['units'] != null) {
        totalUnits = (p['units'] as num).toInt();
      } else if (p.containsKey('units_remainder') && p['units_remainder'] != null) {
        final cartons = (p['quantity'] ?? 0) as num;
        final remainder = (p['units_remainder'] as num).toInt();
        totalUnits = cartons.toInt() * (unitsInCarton > 0 ? unitsInCarton : 0) + remainder;
      } else if (p.containsKey('units_outside') && p['units_outside'] != null) {
        final cartons = (p['quantity'] ?? 0) as num;
        final remainder = (p['units_outside'] as num).toInt();
        totalUnits = cartons.toInt() * (unitsInCarton > 0 ? unitsInCarton : 0) + remainder;
      } else if (p.containsKey('quantity') && p['quantity'] != null) {
        final q = (p['quantity'] as num).toInt();
        if (unitsInCarton > 0) {
          if (q > unitsInCarton * 5) {
            totalUnits = q; // treat as total units
          } else {
            totalUnits = q * unitsInCarton;
            if (p.containsKey('units_remainder') && p['units_remainder'] != null) {
              totalUnits += (p['units_remainder'] as num).toInt();
            }
          }
        } else {
          totalUnits = q;
        }
      }
    } catch (e) {
      totalUnits = 0;
    }

    totalUnits = totalUnits < 0 ? 0 : totalUnits;

    // derive cartons and remainder from totalUnits when possible
    int cartons = 0;
    int remainder = 0;
    if (unitsInCarton > 0 && totalUnits > 0) {
      cartons = totalUnits ~/ unitsInCarton;
      remainder = totalUnits % unitsInCarton;
    } else {
      try {
        cartons = (p['quantity'] ?? 0) as int;
      } catch (e) {
        cartons = ((p['quantity'] ?? 0) as num).toInt();
      }
      try {
        remainder = (p['units_remainder'] ?? p['units_outside'] ?? 0) as int;
      } catch (e) {
        remainder = ((p['units_remainder'] ?? p['units_outside'] ?? 0) as num).toInt();
      }
      if (unitsInCarton > 0) {
        totalUnits = cartons * unitsInCarton + remainder;
      } else {
        totalUnits = cartons + remainder;
      }
    }

    // prices
    final purchaseCarton = _extractDoubleFromProduct(p, ['purchase_price', 'purchase_price_per_carton', 'purchase_per_carton', 'price_carton']);
    final purchaseUnit = _extractDoubleFromProduct(p, ['purchase_price_per_unit', 'purchase_per_unit', 'price_unit']);
    final sellingUnit = _extractDoubleFromProduct(p, ['selling_price', 'selling_price_per_unit', 'price']);

    // fill form fields
    if (name != null) _nameCtrl.text = name;
    _unitsInCartonCtrl.text = (unitsInCarton > 0) ? unitsInCarton.toString() : '1';
    // show current stock as TOTAL UNITS in the editable "existing units" field
    // (this was changed to reflect the full count inside cartons)
    _existingUnitsCtrl.text = totalUnits.toString();

    if (purchaseCarton > 0) {
      _purchasePricePerCartonCtrl.text = purchaseCarton.toStringAsFixed(2);
      if (purchaseUnit <= 0 && unitsInCarton > 0) {
        _purchasePricePerUnitCtrl.text = (purchaseCarton / unitsInCarton).toStringAsFixed(2);
      } else if (purchaseUnit > 0) {
        _purchasePricePerUnitCtrl.text = purchaseUnit.toStringAsFixed(2);
      }
    } else if (purchaseUnit > 0) {
      _purchasePricePerUnitCtrl.text = purchaseUnit.toStringAsFixed(2);
    }

    if (sellingUnit > 0) {
      _sellingPriceIfNewCtrl.text = sellingUnit.toStringAsFixed(2);
    }

    // set a human readable stock summary so the user clearly sees the full count
    setState(() {
      _currentStockText = '$cartons كرتونة + $remainder قطعة = $totalUnits قطعة';
    });

    // ensure receive quantity inputs are present
    if (_cartonsCtrl.text.isEmpty) _cartonsCtrl.text = '0';
    if (_unitsCtrl.text.isEmpty) _unitsCtrl.text = '0';

    // reset paid touched so paid defaults to total cost
    _paidTouched = false;
    _updateComputedPaid();
  }

  /// Apply edits to the currently selected product's stock (cartons/units)
  Future<void> _applyStockEdit() async {
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد منتج محدد للتعديل.')));
      return;
    }

    // احصل القيمة الجديدة لعدد الوحدات داخل الكرتونة (user edited this)
    int newUnitsInCarton = int.tryParse(_unitsInCartonCtrl.text.trim()) ?? 0;
    if (newUnitsInCarton <= 0) newUnitsInCarton = 1; // لا نسمح بصفر أو سالب

    // اجمالي الوحدات الحالي (نأخذ قيمة الحقل القابلة للتعديل _existingUnitsCtrl كمصدر للحقيقة)
    int totalUnits = int.tryParse(_existingUnitsCtrl.text.trim()) ?? 0;
    if (totalUnits < 0) totalUnits = 0;

    // احسب كراتين وباقي بناءً على newUnitsInCarton بحيث يبقى totalUnits ثابتًا
    int cartons = 0;
    int remainder = 0;
    if (newUnitsInCarton > 0) {
      cartons = totalUnits ~/ newUnitsInCarton;
      remainder = totalUnits % newUnitsInCarton;
    } else {
      // تقيّد احترازي (لكن أعلاه ضمنا newUnitsInCarton >= 1)
      cartons = totalUnits;
      remainder = 0;
    }

    // جهّز خريطة التحديث (نحافظ على الحقول الأخرى من الفورم إن وُجدت)
    final prodUpdate = {
      'id': _selectedProductId,
      'barcode': _barcodeCtrl.text.trim(),
      'name': _nameCtrl.text.trim(),
      'units_in_carton': newUnitsInCarton,
      'quantity': cartons,
      'units_remainder': remainder,
      'purchase_price': double.tryParse(_purchasePricePerCartonCtrl.text.trim()) ?? 0.0,
      'selling_price': double.tryParse(_sellingPriceIfNewCtrl.text.trim()) ?? 0.0,
      'production_date': null,
      'expiry_date': null,
    };

    try {
      await DBHelper.instance.updateProduct(prodUpdate);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث المخزون بنجاح')));

      // reload products list (optional) and reflect UI changes
      await _loadProducts();

      // نعرض القيم الجديدة في الحقول
      final newTotalUnits = cartons * newUnitsInCarton + remainder;
      _existingUnitsCtrl.text = newTotalUnits.toString();
      _cartonsCtrl.text = cartons.toString();
      _unitsCtrl.text = remainder.toString();
      _unitsInCartonCtrl.text = newUnitsInCarton.toString();

      setState(() {
        _currentStockText = '$cartons كرتونة + $remainder قطعة = $newTotalUnits قطعة';
      });
    } catch (e) {
      debugPrint('Error updating product: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء تحديث المنتج: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final barcode = _barcodeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final cartonsInput = int.tryParse(_cartonsCtrl.text) ?? 0;
    final unitsInput = int.tryParse(_unitsCtrl.text) ?? 0;
    final unitsInCartonInput = int.tryParse(_unitsInCartonCtrl.text) ?? 1;
    final purchasePerCarton = double.tryParse(_purchasePricePerCartonCtrl.text.replaceAll(',', ''));
    final purchasePerUnit = double.tryParse(_purchasePricePerUnitCtrl.text.replaceAll(',', ''));
    final sellingIfNew = double.tryParse(_sellingPriceIfNewCtrl.text.replaceAll(',', ''));
    final rawPaid = double.tryParse(_paidAmountCtrl.text.replaceAll(',', '')) ?? 0.0;

    try {
      final totalCost = _computeTotalCost();

      // normalize paid value
      double paid = rawPaid;
      if (paid < 0) paid = 0.0;
      if (paid > totalCost) paid = totalCost;

      final dbHelper = DBHelper.instance;

      // ---------------------------
      // IMPORTANT: if product is selected, sync new units_in_carton BEFORE calling receiveFromSupplier
      // This preserves totalUnits and redistributes them using the new units_in_carton value.
      // ---------------------------
      if (_selectedProductId != null) {
        try {
          // Load product (getAllProducts returns total_units computed)
          final products = await DBHelper.instance.getAllProducts();
          final prod = products.firstWhere(
                (p) => (p['id'] as num).toInt() == _selectedProductId,
            orElse: () => {},
          );

          if (prod.isNotEmpty) {
            // compute current totalUnits (prefer total_units if present)
            int totalUnits = 0;
            try {
              if (prod.containsKey('total_units') && prod['total_units'] != null) {
                totalUnits = (prod['total_units'] as num).toInt();
              } else {
                final q = (prod['quantity'] as num?)?.toInt() ?? 0;
                final ui = (prod['units_in_carton'] as num?)?.toInt() ?? 1;
                final rem = (prod['units_remainder'] as num?)?.toInt() ?? 0;
                totalUnits = q * (ui > 0 ? ui : 1) + rem;
              }
            } catch (_) {
              totalUnits = 0;
            }

            // new units-in-carton from form (ensure >= 1)
            int newUnitsInCarton = unitsInCartonInput <= 0 ? 1 : unitsInCartonInput;

            // redistribute totalUnits into cartons + remainder using newUnitsInCarton
            int newCartons = 0;
            int newRemainder = 0;
            if (newUnitsInCarton > 0) {
              newCartons = totalUnits ~/ newUnitsInCarton;
              newRemainder = totalUnits % newUnitsInCarton;
            } else {
              newCartons = totalUnits;
              newRemainder = 0;
            }

            // prepare update map - preserve other fields where possible
            final prodUpdate = {
              'id': _selectedProductId,
              'barcode': prod['barcode'] ?? _barcodeCtrl.text.trim(),
              'name': prod['name'] ?? _nameCtrl.text.trim(),
              'units_in_carton': newUnitsInCarton,
              'quantity': newCartons,
              'units_remainder': newRemainder,
              'purchase_price': (prod['purchase_price'] as num?)?.toDouble() ?? (purchasePerCarton ?? 0.0),
              'selling_price': (prod['selling_price'] as num?)?.toDouble() ?? (sellingIfNew ?? 0.0),
              'production_date': prod['production_date'] ?? '',
              'expiry_date': prod['expiry_date'] ?? '',
            };

            await DBHelper.instance.updateProduct(prodUpdate);

            // update UI to reflect redistribution before adding new received cartons
            _unitsInCartonCtrl.text = newUnitsInCarton.toString();
            _cartonsCtrl.text = newCartons.toString();
            _unitsCtrl.text = newRemainder.toString();
            _existingUnitsCtrl.text = totalUnits.toString();
            setState(() {
              _currentStockText = '$newCartons كرتونة + $newRemainder قطعة = $totalUnits قطعة';
            });
          }
        } catch (e) {
          debugPrint('Warning: failed to sync units_in_carton before receive: $e');
          // لا نوقف العملية هنا — نتابع receiveFromSupplier لكن قد يستخدم القيمة القديمة في DB
        }
      }

      // ---------------------------
      // call receiveFromSupplier to persist the incoming receipt (this will use the updated units_in_carton)
      // ---------------------------
      final res = await dbHelper.receiveFromSupplier(
        barcode: barcode.isEmpty ? null : barcode,
        name: name.isEmpty ? null : name,
        cartons: cartonsInput,
        units: unitsInput,
        purchasePricePerCarton: purchasePerCarton,
        purchasePricePerUnit: purchasePerUnit,
        sellingPricePerUnitIfNew: sellingIfNew,
        unitsInCartonIfNew: unitsInCartonInput,
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

        // apply payment-side effects (drawer / card_wallet) as in original logic
        try {
          final currentUser = await dbHelper.getCurrentUser();
          final username = (currentUser != null && currentUser['username'] != null)
              ? currentUser['username'] as String
              : Session.currentUsername ?? 'admin';

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
              final notePrefix = (paid < totalCost) ? 'Partial payment for credit purchase' : 'Full cash payment for purchase';
              await dbHelper.setDrawerStartingAmount(
                newStarting,
                username,
                note: '$notePrefix -${paid.toStringAsFixed(2)}',
              );
            }
          }

          // show dialog summarizing result
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Center(child: const Text('تم الاستلام', style: TextStyle(color: Colors.white))),
              content: Text(
                'تم إضافة $added وحدة. الإجمالي: ${totalCostRes.toStringAsFixed(2)}. المدفوع: ${paid.toStringAsFixed(2)}. المتبقي: ${due.toStringAsFixed(2)}.',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('حسناً', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          // Reset form fields
          _formKey.currentState!.reset();
          _cartonsCtrl.text = '0';
          _unitsCtrl.text = '0';
          _unitsInCartonCtrl.text = '1';
          _purchasePricePerCartonCtrl.clear();
          _purchasePricePerUnitCtrl.clear();
          _sellingPriceIfNewCtrl.clear();

          _existingUnitsCtrl.text = '0';
          _paidAmountCtrl.text = totalCostRes.toStringAsFixed(2);
          _paidTouched = false;

          // reload any relevant aggregates
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

  /// Open a picker dialog to choose an existing product and autofill fields
  Future<void> _openProductPicker() async {
    await _loadProducts();
    String query = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          final filtered = query.trim().isEmpty
              ? _products
              : _products.where((p) {
            final name = (p['name'] ?? '').toString().toLowerCase();
            final barcode = (p['barcode'] ?? '').toString().toLowerCase();
            final q = query.toLowerCase();
            return name.contains(q) || barcode.contains(q);
          }).toList();

          return AlertDialog(
            backgroundColor: AppColorsDark.bgCardColor,
            title: const Text('اختر منتج', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(hintText: 'بحث بالاسم او الباركود'),
                    onChanged: (v) => setStateDialog(() => query = v),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  _loadingProducts
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                    height: 300,
                    child: filtered.isEmpty
                        ? const Center(child: Text('لا يوجد منتجات', style: TextStyle(color: Colors.white)))
                        : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white24),
                      itemBuilder: (_, i) {
                        final prod = filtered[i];
                        return ListTile(
                          title: Text(prod['name'] ?? '-', style: const TextStyle(color: Colors.white)),
                          subtitle: Text('Barcode: ${prod['barcode'] ?? '-'}', style: const TextStyle(color: Colors.white70)),
                          trailing: Text('Price: ${prod['selling_price'] ?? '-'}', style: const TextStyle(color: Colors.white)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _barcodeCtrl.text = (prod['barcode'] ?? '').toString();
                            _fillFieldsFromProduct(prod);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('اغلاق')),
            ],
          );
        });
      },
    );
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
                Row(
                  children: [
                    Expanded(
                      child: CustomFormField(
                        controller: _barcodeCtrl,
                        hint: 'باركود (اجباري)',
                        focusNode: _barcodeFocusNode,
                        onFieldSubmitted: (_) => _lookupBarcode(),
                        onChanged: (_) {
                          // clear name when barcode changed so user sees updated suggestion
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'اختر منتج من القائمة',
                      onPressed: _openProductPicker,
                      icon: const Icon(Icons.list, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _nameCtrl,
                  hint: 'اسم المنتج',
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CustomFormField(
                        controller: _existingUnitsCtrl,
                        hint: 'الوحدات الفردية الحالية (قابلة للتعديل)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'حفظ التعديل على المخزون الحالي',
                      icon: const Icon(Icons.save, color: Colors.white),
                      onPressed: _applyStockEdit,
                    ),
                  ],
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
