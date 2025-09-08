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
    // don't overwrite user's input for receiving cartons/units: show current stock separately
    _existingUnitsCtrl.text = remainder.toString();

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

    setState(() => _loading = true);
    try {
      // جلب السجل الحالي مباشرة من جدول products
      final db = await DBHelper.instance.database;
      final rows = await db.query('products', where: 'id = ?', whereArgs: [_selectedProductId], limit: 1);
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم أجد المنتج في قاعدة البيانات.')));
        setState(() => _loading = false);
        return;
      }
      final current = Map<String, dynamic>.from(rows.first);

      // قراءة القيم الحالية من الداتا بيس بحذر (عدة أسماء محتملة للحقل)
      int dbUnitsInCarton = 0;
      try {
        if (current['units_in_carton'] != null) dbUnitsInCarton = (current['units_in_carton'] as num).toInt();
        else if (current['unitsInCarton'] != null) dbUnitsInCarton = (current['unitsInCarton'] as num).toInt();
        else if (current['unit_in_carton'] != null) dbUnitsInCarton = (current['unit_in_carton'] as num).toInt();
      } catch (_) {}
      int dbQuantity = 0;
      try {
        if (current['quantity'] != null) dbQuantity = (current['quantity'] as num).toInt();
      } catch (_) {}

      // القيمة التي يريد المستخدم حفظها في الحقل (الوحدات الفردية الحالية)
      int newRemainder = int.tryParse(_existingUnitsCtrl.text.trim()) ?? 0;
      if (newRemainder < 0) newRemainder = 0;

      // نقيد الباقي بحيث لا نغير عدد الكراتين هنا
      if (dbUnitsInCarton > 0) {
        final maxRemainder = dbUnitsInCarton - 1;
        if (newRemainder > maxRemainder) {
          newRemainder = maxRemainder;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تم حفظ الوحدات الفردية لكن تم تقليصها إلى الحد الأقصى ($maxRemainder) لأننا لا نغيّر الكراتين هنا.'),
          ));
        }
      }

      // إعداد خريطة للتحديث مع الحفاظ على quantity كما هي
      final prodUpdate = Map<String, dynamic>.from(current);
      prodUpdate['id'] = _selectedProductId;
      prodUpdate['units_remainder'] = newRemainder;
      // لا نغير 'quantity' ولا 'units_in_carton' هنا

      // نُحدّث حقول اختيارية من الفورم إذا كانت موجودة (حتى لا نمسح بيانات مهمة)
      if (_barcodeCtrl.text.trim().isNotEmpty) prodUpdate['barcode'] = _barcodeCtrl.text.trim();
      if (_nameCtrl.text.trim().isNotEmpty) prodUpdate['name'] = _nameCtrl.text.trim();
      if (_purchasePricePerCartonCtrl.text.trim().isNotEmpty) {
        final v = double.tryParse(_purchasePricePerCartonCtrl.text.replaceAll(',', '').trim());
        if (v != null) prodUpdate['purchase_price'] = v;
      }
      if (_sellingPriceIfNewCtrl.text.trim().isNotEmpty) {
        final v = double.tryParse(_sellingPriceIfNewCtrl.text.replaceAll(',', '').trim());
        if (v != null) prodUpdate['selling_price'] = v;
      }

      await DBHelper.instance.updateProduct(prodUpdate);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الوحدات الفردية بنجاح')));

      await _loadProducts();
      _fillFieldsFromProduct(prodUpdate);
    } catch (e) {
      debugPrint('Error updating product: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ أثناء تحديث المنتج: $e')));
    } finally {
      setState(() => _loading = false);
    }
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

          // reset existing units display
          _existingUnitsCtrl.text = '0';

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
                        controller: _existingUnitsCtrl,
                        hint: 'الوحدات الفردية الحالية (قابلة للتعديل)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(width: 5,),
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
