// lib/screens/cashier/cashier_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:cashgo/models/login.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart' hide TextDirection ;
import '../../models/cart.dart';
import '../../models/product.dart';
import '../../services/cashier/print.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/cartlist.dart';
import '../../widgets/Cashier/close_shieft.dart';
import '../../widgets/Cashier/payment_controller.dart';
import '../../widgets/Cashier/receipt_widget.dart';
import 'ReceiveFromSupplier.dart';
import 'histroy.dart';

class CashierScreen extends StatefulWidget {
  final String cashierUsername;
  const CashierScreen({super.key, this.cashierUsername = 'cashier'});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  final TextEditingController _paidController = TextEditingController();
  final Map<int, CartItem> _cart = {};
  bool _saving = false;

  final GlobalKey _receiptKey = GlobalKey();

  String? _currentUsername; // اسم الكاشير الحقيقي المأخوذ من DB

  // --- card/wallet totals to show to cashier ---
  double _walletAmount = 0.0;        // latest card_wallet amount
  double _cardReceived = 0.0;       // untransferred card payments from sales
  double _cardTotalAvailable = 0.0; // wallet + untransferred
  double Drawer = 0.0; // wallet + untransferred

  // --------- Discount state ----------
  // design: percent-only discount (as requested), from 0% to 50% step 5
  String _discountType = 'percent';
  double _discountValue = 0.0; // e.g. 5.0 means 5%

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocus);
    });
    _loadCurrentUser();
    _loadCardTotals(); // load wallet + card totals for display
  }

  Future<void> _loadCurrentUser() async {
    try {
      final cur = await DBHelper.instance.getCurrentUser();
      if (cur != null) {
        setState(() {
          _currentUsername = (cur['username'] ?? '').toString();
        });
        Session.currentUsername = _currentUsername;
        Session.currentRole = (cur['role'] ?? Session.currentRole) as String?;
      } else {
        // fallback to widget prop if DB has no current user
        setState(() {
          _currentUsername = widget.cashierUsername;
        });
      }
    } catch (e) {
      debugPrint('Failed to load current user: $e');
      setState(() {
        _currentUsername = widget.cashierUsername;
      });
    }
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _paidController.dispose();
    super.dispose();
  }

  // ------------------ داخل _CashierScreenState ------------------

  Future<void> _onBarcodeSubmitted(String code) async {
    final barcode = code.trim();
    if (barcode.isEmpty) return;

    // حاول تجيب كل المنتجات بنفس الباركود
    final productsList = await DBHelper.instance.getProductsByBarcodeList(barcode);

    if (productsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('المنتج بالباركود $barcode غير موجود')),
      );
      _barcodeController.clear();
      FocusScope.of(context).requestFocus(_barcodeFocus);
      return;
    }

    Map<String, dynamic>? chosenMap;
    if (productsList.length == 1) {
      chosenMap = productsList.first;
    } else {
      // اعرض حوار اختيار للمستخدم لو في أكثر من نتيجة
      chosenMap = await showProductChoiceDialog(context, productsList);
      if (chosenMap == null) {
        // المستخدم ألغى الاختيار
        _barcodeController.clear();
        FocusScope.of(context).requestFocus(_barcodeFocus);
        return;
      }
    }

    // تحويل إلى نموذج المنتج والتعامل كالسابق
    final product = Product.fromMap(chosenMap);
    final available = product.totalUnits;
    final pid = product.id!;
    final alreadyInCart = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;

    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكمية نفدت')));
      _barcodeController.clear();
      FocusScope.of(context).requestFocus(_barcodeFocus);
      return;
    }
    if (alreadyInCart + 1 > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن إضافة أكثر من المتاح')));
      _barcodeController.clear();
      FocusScope.of(context).requestFocus(_barcodeFocus);
      return;
    }

    setState(() {
      if (_cart.containsKey(pid)) {
        _cart[pid]!.quantity += 1;
      } else {
        _cart[pid] = CartItem(product: product, quantity: 1);
      }
    });

    _barcodeController.clear();
    FocusScope.of(context).requestFocus(_barcodeFocus);
  }

  /// Dialog يعرِض أسماء المنتجات فقط، ويُرجع خريطة المنتج المختار أو null عند الإلغاء.
  Future<Map<String, dynamic>?> showProductChoiceDialog(
      BuildContext context,
      List<Map<String, dynamic>> products,
      ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AppColorsDark.bgColor,
            title: Center(child: const Text('اختر المنتج', style: TextStyle(color: Colors.white))),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 0.5),
                itemBuilder: (context, i) {
                  final name = (products[i]['name'] ?? '').toString();
                  return ListTile(
                    title: Text(name, style: TextStyle(color: Colors.white, fontSize: 20)),
                    onTap: () {
                      Navigator.of(context).pop(products[i]);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor,
                ),
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  double get _total => computeTotal(_cart);
  double get _paid => double.tryParse(_paidController.text.replaceAll(',', '')) ?? 0.0;

  // effective total after applying invoice-level discount
  double get _effectiveTotal {
    final subtotal = _total;
    if (_discountType == 'percent' && _discountValue > 0) {
      final disc = subtotal * (_discountValue / 100.0);
      return (subtotal - disc).clamp(0.0, double.infinity);
    }
    return subtotal;
  }

  void _addQuickPaid(double amount) {
    final current = _paid;
    final newPaid = current + amount;
    _paidController.text = newPaid.toStringAsFixed(2);
    setState(() {});
  }

  void _setQuickPaid(double amount) {
    _paidController.text = amount.toStringAsFixed(2);
    setState(() {});
  }

  void _changeQuantity(int productId, int newQty) async {
    if (!_cart.containsKey(productId)) return;
    final productMap = await DBHelper.instance.getProductByBarcode((_cart[productId]!.product.barcode));
    if (productMap == null) return;
    final product = Product.fromMap(productMap);
    final available = product.totalUnits;
    if (newQty <= 0) {
      setState(() => _cart.remove(productId));
    } else if (newQty > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كمية كافية')));
    } else {
      setState(() => _cart[productId]!.quantity = newQty);
    }
  }

  Future<void> _editQuantityDialog(int productId) async {
    if (!_cart.containsKey(productId)) return;
    final current = _cart[productId]!.quantity;
    final controller = TextEditingController(text: current.toString());
    final res = await showDialog<int?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الكمية'),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'ادخل الكمية (قطع)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () { final v = int.tryParse(controller.text) ?? current; Navigator.of(ctx).pop(v); }, child: const Text('موافق')),
        ],
      ),
    );
    if (res != null) _changeQuantity(productId, res);
  }

  // دالة جديدة تطلب اسم العميل عند حفظ فاتورة آجل
  Future<String?> _askForCustomerName() async {
    final controller = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SizedBox(
        width: 150,
        height: 100,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: Center(child: const Text('اسم العميل للفاتورة الآجلة', style: TextStyle(color: Colors.white))),
          content: CustomFormField(
            controller: controller,
            hint: 'اكتب اسم العميل أو الجهة',
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
            ),
            CustomButton(
              infinity: false,
              text: 'حفظ',
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    return res;
  }

  // ===================================================================
  // === Functions to show and maintain combined card/wallet totals ====
  // ===================================================================

  /// Safely compute the true untransferred card amount.
  /// Works across DB versions (supports card_transferred_amount or card_transferred flag if present).
  Future<double> _getUntransferredCardAmountSafe() async {
    final db = await DBHelper.instance.database;

    // check which columns exist
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final hasTransferredAmount = cols.any((c) => (c['name'] as String) == 'card_transferred_amount');
    final hasCardTransferredFlag = cols.any((c) => (c['name'] as String) == 'card_transferred');

    String sql;
    List<Object?> args = ['card'];

    if (hasTransferredAmount) {
      sql = '''
        SELECT SUM(
          (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(card_transferred_amount,0)
        ) AS card_untransferred
        FROM sales
        WHERE payment_method = ?
          AND ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(card_transferred_amount,0)) > 0
      ''';
    } else if (hasCardTransferredFlag) {
      sql = '''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) AS card_untransferred
        FROM sales
        WHERE payment_method = ?
          AND COALESCE(card_transferred,0) = 0
      ''';
    } else {
      sql = '''
        SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) AS card_untransferred
        FROM sales
        WHERE payment_method = ?
      ''';
    }

    final rows = await db.rawQuery(sql, args);
    final value = (rows.isNotEmpty && rows.first['card_untransferred'] != null)
        ? (rows.first['card_untransferred'] as num).toDouble()
        : 0.0;
    return value < 0 ? 0.0 : value;
  }

  Future<void> _loadCardTotals() async {
    try {
      final dbHelper = DBHelper.instance;
      final db = await dbHelper.database;
      await dbHelper.ensureCardWalletTable();
      final walletLatest = await dbHelper.getLatestCardWalletAmount();
      final untransferred = await _getUntransferredCardAmountSafe();
      final starting = await dbHelper.getLatestDrawerStartingAmount();
      double salesNetCash = 0.0;
      try {
        final totals = await dbHelper.getDrawerTotals(fromDate: null, toDate: null);
        salesNetCash = (totals['sales_net_cash'] as num?)?.toDouble()
            ?? (totals['sales_net'] as num?)?.toDouble()
            ?? 0.0;
      } catch (e) {
        debugPrint('Could not get totals for drawer during closeShift: $e');
        salesNetCash = 0.0;
      }
      double purchasePaidCash = 0.0;
      try {
        // محاولة استعلام SUM مباشرة
        final rows = await db.rawQuery(
            "SELECT SUM(COALESCE(paid_amount,0)) AS total FROM purchase_receipts WHERE payment_type = 'cash'"
        );
        purchasePaidCash = (rows.isNotEmpty && rows.first['total'] != null)
            ? (rows.first['total'] as num).toDouble()
            : 0.0;
      } catch (e) {
        debugPrint('Failed to compute purchasePaidCash in closeShift: $e');
        // fallback: جمع من getPaidPurchaseReceipts
        try {
          final paidReceipts = await dbHelper.getPaidPurchaseReceipts();
          double sum = 0.0;
          for (final r in paidReceipts) {
            final type = r['payment_type'] as String? ?? 'cash';
            if (type == 'cash') sum += (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
          }
          purchasePaidCash = sum;
        } catch (e2) {
          debugPrint('Fallback also failed: $e2');
          purchasePaidCash = 0.0;
        }
      }
      final computedFromParts = starting + salesNetCash - purchasePaidCash;
      final adjustedCurrent = computedFromParts < 0.0 ? 0.0 : computedFromParts;

      // ===== استخدم adjustedCurrent في التقرير بدل computeCurrentDrawerAmount =====

      if (!mounted) return;
      setState(() {
        _walletAmount = walletLatest;
        _cardReceived = untransferred;
        _cardTotalAvailable = (_walletAmount) + (_cardReceived);
        Drawer = adjustedCurrent;

      });
    } catch (e, st) {
      debugPrint('Failed to load card totals: $e\n$st');
    }
  }


  Future<void> _transferBetweenDrawerAndWallet(double amount, {required bool fromDrawerToWallet}) async {
    if (amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صالحًا أكبر من صفر')));
      return;
    }

    setState(() => _saving = true);
    final dbHelper = DBHelper.instance;
    try {
      await dbHelper.ensureCardWalletTable();
      await dbHelper.ensureCashDrawerTable();

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null) ? currentUser['username'] as String : widget.cashierUsername;

      // تحقق من التوفّر
      final latestWallet = await dbHelper.getLatestCardWalletAmount();
      final latestDrawerStarting = await dbHelper.getLatestDrawerStartingAmount();

      if (fromDrawerToWallet) {
        // نأخذ من الدرج → نزيد المحفظة
        final computedCurrent = await dbHelper.computeCurrentDrawerAmount();
        if (amount > computedCurrent + 0.000001) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الرصيد في الدرج غير كافٍ. المتاح: EGP ${computedCurrent.toStringAsFixed(2)}')));
          return;
        }

        // حساب القيمة الجديدة للدرج
        final newStarting = (latestDrawerStarting - amount).clamp(0.0, double.infinity);

        // خطوة آمنة: نحدّث الدُرج أولًا ثم نزيد المحفظة. إذا فشل أي منهما نحاول عمل تراجع (rollback) قدر الإمكان.
        try {
          await dbHelper.setDrawerStartingAmount(newStarting, username, note: 'سحب إلى المحفظة (-${amount.toStringAsFixed(2)})');
        } catch (e) {
          debugPrint('Failed to set drawer starting amount before wallet change: $e');
          throw 'فشل تحديث الدرج';
        }

        try {
          await dbHelper.changeCardWalletBy(amount, username, note: 'تحويل من الدرج إلى المحفظة');
        } catch (e) {
          debugPrint('Failed to change wallet after drawer update: $e');
          // حاول استرجاع قيمة الدرج الأصلية
          try {
            await dbHelper.setDrawerStartingAmount(latestDrawerStarting, username, note: 'Rollback: failed wallet credit after drawer debit');
          } catch (e2) {
            debugPrint('Rollback failed: $e2');
          }
          throw 'فشل تسجيل التحويل إلى المحفظة';
        }

      } else {
        // from wallet -> drawer (إيداع: ننقص المحفظة ونزيد الدرج)
        if (amount > latestWallet + 0.000001) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الرصيد في المحفظة غير كافٍ. المتاح: EGP ${latestWallet.toStringAsFixed(2)}')));
          return;
        }

        final newStarting = latestDrawerStarting + amount;

        // نخصم من المحفظة أولاً ثم نزيد الدُرج. إذا فشل تحديث الدُرج نحاول اعادة المبلغ إلى المحفظة.
        try {
          await dbHelper.changeCardWalletBy(-amount, username, note: 'تحويل إلى الدرج (-${amount.toStringAsFixed(2)})');
        } catch (e) {
          debugPrint('Failed to debit wallet before drawer update: $e');
          throw 'فشل خصم المبلغ من المحفظة';
        }

        try {
          await dbHelper.setDrawerStartingAmount(newStarting, username, note: 'إيداع من المحفظة (+${amount.toStringAsFixed(2)})');
        } catch (e) {
          debugPrint('Failed to set drawer starting after wallet debit: $e');
          // حاول استرجاع المبلغ للمحفظة
          try {
            await dbHelper.changeCardWalletBy(amount, username, note: 'Rollback: failed drawer credit after wallet debit');
          } catch (e2) {
            debugPrint('Rollback wallet failed: $e2');
          }
          throw 'فشل ايداع المبلغ في الدرج';
        }
      }

      // بعد التحديثات: اقرأ القيم من DB وضبط الواجهة
      final walletAfter = await dbHelper.getLatestCardWalletAmount();
      final untransferredAfter = await _getUntransferredCardAmountSafe();
      if (mounted) {
        setState(() {
          _walletAmount = walletAfter;
          _cardReceived = untransferredAfter;
          _cardTotalAvailable = _walletAmount + _cardReceived;
        });
      }

      // Debug - اطبع للكونسول للتأكد
      debugPrint('TRANSFER DONE: fromDrawerToWallet=$fromDrawerToWallet amount=$amount; walletBefore=$latestWallet walletAfter=$walletAfter; drawerBefore=$latestDrawerStarting drawerAfter=${fromDrawerToWallet ? (latestDrawerStarting - amount) : (latestDrawerStarting + amount)}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fromDrawerToWallet
            ? 'تم نقل EGP ${amount.toStringAsFixed(2)} من الدرج إلى المحفظة'
            : 'تم نقل EGP ${amount.toStringAsFixed(2)} من المحفظة إلى الدرج')));
      }

    } catch (e, st) {
      debugPrint('transferBetweenDrawerAndWallet (helpers) failed: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحويل: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // opens dialog to deposit/withdraw from wallet (keeps previous behavior)
  Future<void> _openCardWalletDialog() async {
    final username = _currentUsername ?? widget.cashierUsername;
    bool isDeposit = true;
    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        double dialogWallet = _walletAmount;
        bool isProcessing = false;

        return StatefulBuilder(builder: (ctx2, setState2) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Center(child: const Text('محفظة الكارت', style: TextStyle(color: Colors.white))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الرصيد الحالي: ${_cardTotalAvailable.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: isDeposit ? Colors.green : AppColorsDark.bgColor),
                          onPressed: isProcessing ? null : () => setState2(() => isDeposit = true),
                          child: const Text('إيداع',style: TextStyle(
                              color: Colors.white
                          ),),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: !isDeposit ? Colors.red : AppColorsDark.bgColor),
                          onPressed: isProcessing ? null : () => setState2(() => isDeposit = false),
                          child: const Text('سحب',style: TextStyle(
                              color: Colors.white
                          ),),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CustomFormField(
                    controller: controller,
                    hint: 'ادخل المبلغ',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                CustomButton(
                  infinity: false,
                  text: 'تنفيذ',
                  onPressed: isProcessing
                      ? null
                      : () async {
                    final raw = controller.text.trim();
                    final value = double.tryParse(raw.replaceAll(',', '')) ?? 0.0;
                    if (value <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صحيحًا')));
                      return;
                    }

                    setState2(() => isProcessing = true);

                    try {
                      // NEW BEHAVIOR:
                      // - If isDeposit == true => transfer from wallet -> drawer (إيداع: يزيد الدرج وينقص المحفظة)
                      // - If isDeposit == false => transfer from drawer -> wallet (سحب: ينقص الدرج ويزيد المحفظة)
                      if (isDeposit) {
                        await _transferBetweenDrawerAndWallet(value, fromDrawerToWallet: false);
                      } else {
                        await _transferBetweenDrawerAndWallet(value, fromDrawerToWallet: true);
                      }

                      // canonical reload after success
                      await _loadCardTotals();

                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isDeposit
                          ? 'تم الإيداع — تم نقل EGP ${value.toStringAsFixed(2)} من المحفظة إلى الدرج'
                          : 'تم السحب — تم نقل EGP ${value.toStringAsFixed(2)} من الدرج إلى المحفظة')));
                    } catch (e) {
                      debugPrint('Withdraw/Deposit failed: $e');
                      // rollback to canonical DB values to avoid inconsistent negative UI
                      await _loadCardTotals();
                      setState2(() => dialogWallet = _walletAmount);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تنفيذ العملية: $e')));
                    } finally {
                      setState2(() => isProcessing = false);
                    }
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ------------- Discount dialog -------------
  Future<void> _showDiscountDialog() async {
    final options = List.generate(11, (i) => i * 5); // 0,5,10,...,50
    int selected = _discountValue.toInt();

    final res = await showDialog<int?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Center(child: const Text('اختر نسبة الخصم', style: TextStyle(color: Colors.white))),
              content: SizedBox(
                width: double.maxFinite,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((v) {
                    final isSelected = v == selected;
                    return ChoiceChip(
                      label: Text('$v%'),
                      selected: isSelected,
                      backgroundColor: AppColorsDark.bgColor,
                      selectedColor: Colors.green,
                      labelStyle: const TextStyle(color: Colors.white),
                      onSelected: (_) {
                        setState2(() => selected = v);
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () => Navigator.of(ctx2).pop(null),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                CustomButton(
                  infinity: false,
                  text: 'تطبيق',
                  onPressed: () => Navigator.of(ctx2).pop(selected),
                ),
              ],
            );
          }),
        );
      },
    );

    if (res != null) {
      setState(() {
        _discountValue = res.toDouble();
        _discountType = 'percent';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تطبيق خصم ${_discountValue.toStringAsFixed(0)}% — الإجمالي الآن: ${_effectiveTotal.toStringAsFixed(2)}')),
      );
    }
  }

  // تم إضافة باراميتر paymentMethod فقط (قيمة افتراضية 'cash')
  Future<void> _saveSale({required bool requireFullPayment, String paymentMethod = 'cash'}) async {
    if (_cart.isEmpty) return;

    // subtotal before discount (for messages or storing if needed)
    final subtotal = _total;
    final total = _effectiveTotal; // بعد تطبيق الخصم

    String? customerName;
    if (paymentMethod == 'credit' && paymentMethod != 'wallet') {
      // legacy behaviour: if someone still uses 'credit' as deferred invoice,
      // ask for customer name
      customerName = await _askForCustomerName();
      if (customerName == null || customerName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء حفظ الفاتورة: يجب إدخال اسم العميل للفواتير الآجلة')),
        );
        return;
      }
    }

    // If paymentMethod == 'wallet' we treat it as payment via the electronic wallet (card_wallet).
    // For card/wallet payments we force paid == total (full payment).
    final paid = (paymentMethod == 'card' || paymentMethod == 'wallet') ? total : _paid;

    if (requireFullPayment && paid < total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('العميل لم يدفع كامل المبلغ')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // validate stock before writing
      for (final entry in _cart.entries) {
        final cartItem = entry.value;
        final productMap = await DBHelper.instance.getProductByBarcode(cartItem.product.barcode);
        if (productMap == null) throw 'المنتج غير موجود';
        final productFresh = Product.fromMap(productMap);
        if (cartItem.quantity > productFresh.totalUnits) {
          throw 'لا توجد كمية كافية لـ ${productFresh.name}';
        }
      }

      final isCredit = (paymentMethod == 'credit' && paymentMethod != 'wallet');
      final changeAmount = (paid >= total) ? (paid - total) : 0.0;

      final cashierNameToUse = _currentUsername ?? widget.cashierUsername;

      // SPECIAL: if using wallet payment, first record the incoming card-wallet amount
      if (paymentMethod == 'wallet') {
        // Deposit the sale amount into the card_wallet. This represents money received via the
        // electronic card channel and stored in the app wallet.
        try {
          await DBHelper.instance.changeCardWalletBy(total, cashierNameToUse, note: 'دفع بواسطه المحفظة للفاتورة');
          await _loadCardTotals(); // update wallet + combined total
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إضافة ${total.toStringAsFixed(2)} إلى المحفظة — الرصيد الآن: ${_walletAmount.toStringAsFixed(2)}')));
        } catch (e) {
          debugPrint('Failed to deposit to card wallet: $e');
          throw 'فشل تسجيل الدفع في المحفظة';
        }
      }

      // create sale (note: pass paymentMethod explicitly and discount fields)
      final saleId = await DBHelper.instance.createSale(
        total: total,
        cashierUsername: cashierNameToUse,
        paidAmount: paid,
        changeAmount: changeAmount,
        isCredit: isCredit,
        isReturn: false,
        returnOfSaleId: null,
        returnNote: null,
        customerName: customerName,
        paymentMethod: paymentMethod, // <-- تغير هنا: خزّن الطريقة كما هي (لا نحول wallet -> card)
        discountType: _discountType,
        discountValue: _discountValue,
      );

      // insert sale items and update stock
      for (final entry in _cart.entries) {
        final pid = entry.key;
        final cartItem = entry.value;
        await DBHelper.instance.insertSaleItem(
          saleId: saleId,
          productId: pid,
          quantity: cartItem.quantity,
          price: cartItem.product.sellingPrice,
        );
        await DBHelper.instance.reduceProductStockByUnits(pid, cartItem.quantity);
      }

      // Ensure the sale row is marked as paid and has correct payment_method
      // <-- مرّرنا paymentMethod كما هو بدل إجبار 'card' عند وجود 'wallet'
      if (paymentMethod == 'card' || paymentMethod == 'wallet') {
        await DBHelper.instance.markSaleAsPaid(saleId, paymentMethod: paymentMethod, paidAmount: total);
      } else if (paymentMethod == 'cash') {
        await DBHelper.instance.markSaleAsPaid(saleId, paymentMethod: 'cash', paidAmount: paid);
      }

      // user messages
      if (paymentMethod == 'credit' && paymentMethod != 'wallet') {
        final remaining = total - paid;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ الفاتورة كآجل باسم $customerName — المتبقي: ${remaining.toStringAsFixed(2)}')),
        );
      } else if (paymentMethod == 'card') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ — تم الدفع بالكارت بالكامل')),
        );
      } else if (paymentMethod == 'wallet') {
        // wallet-specific snackbar already shown after deposit
      } else { // cash
        final change = paid - total;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ — الباقي: ${change.toStringAsFixed(2)}')),
        );
      }

      // printing (overlay-based, more reliable)
      bool printSuccess = false;
      try {
        await Future.delayed(const Duration(milliseconds: 250)); // للقليل من الاستقرار قبل الطباعة

        // Clone the cart data for printing so later clears don't affect the printed receipt.
        final printedCart = Map<int, CartItem>.from(_cart);

        // Create a ReceiptWidget instance copied from current data.
        final receiptWidget = ReceiptWidget(
          cart: printedCart,
          paid: paid,
          cashierUsername: cashierNameToUse,
          width: 220,
          useCairo: true,
          discountType: _discountType,
          discountValue: _discountValue,
        );


        // Use the overlay capture + print method (no short timeout).
        await PrintService.printWidgetUsingOverlay(context, receiptWidget, width: 220, pixelRatio: 2.0);
        printSuccess = true;
        debugPrint('Print succeeded (overlay method).');
      } catch (e, st) {
        debugPrint('Print failed (overlay method): $e\n$st');
      }

      if (!printSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل الطباعة. يمكنك المحاولة لاحقًا من صفحة الطباعة.')),
        );
      }

      // clear cart & paid field & reset discount
      setState(() {
        _cart.clear();
        _paidController.clear();
        _discountValue = 0.0; // reset discount after successful save
        debugPrint("Cart cleared, items = ${_cart.length}");
      });

      // IMPORTANT: after saving, reload card totals to reflect any new wallet additions or sales state
      await _loadCardTotals();
    }catch (e, st) {
      debugPrint('Failed to save sale — error: $e\nstack:\n$st');
      // optional: show full error in a dialog for debugging (you can remove later)
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('خطأ أثناء حفظ الفاتورة'),
          content: SingleChildScrollView(child: Text('$e\n\n$st')),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('حسناً'))],
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حفظ الفاتورة: $e')),
      );
    } finally {
      setState(() => _saving = false);
      FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }

  bool _closingShift = false;

  // 3) دالة إغلاق الشفت (تجميع + طباعة)
  Future<void> _closeShift() async {
    final username = _currentUsername ?? widget.cashierUsername;
    setState(() => _closingShift = true);

    try {
      final now = DateTime.now();

      // استخدم بداية اليوم فقط -> هذا يضمن التقفيل سيكون خاص باليوم الحالي
      final startOfDay = DateTime(now.year, now.month, now.day);
      final fromDateStr = startOfDay.toIso8601String().split('T').first;
      final toDateStr = fromDateStr; // يوم واحد (اليوم)

      // جلب مبيعات الكاشير لليوم
      final sales = await DBHelper.instance.getSalesByCashierBetweenDates(
        cashierUsername: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      // جلب عناصر كل فاتورة
      final Map<int, List<Map<String, dynamic>>> saleItemsMap = {};
      for (final s in sales) {
        final sid = (s['id'] as num).toInt();
        final items = await DBHelper.instance.getSaleItemsBySaleId(sid);
        saleItemsMap[sid] = items;
      }

      // جلب سندات الشراء المسجلة بواسطة الكاشير لليوم
      final purchases = await DBHelper.instance.getPurchaseReceiptsByUserBetweenDates(
        username: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      // حسابات تجميعية بسيطة (يمكنك تعديل العرض لاحقاً)
      double salesTotal = 0.0;
      double salesPaidCash = 0.0;
      double salesPaidCard = 0.0;
      for (final s in sales) {
        final total = (s['total'] as num?)?.toDouble() ?? 0.0;
        final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final change = (s['change_amount'] as num?)?.toDouble() ?? 0.0;
        final method = (s['payment_method'] ?? 'cash').toString();
        salesTotal += total;
        final net = (paid - change);
        if (method == 'cash') salesPaidCash += net;
        else if (method == 'card') salesPaidCard += net;
      }

      double purchasesPaid = 0.0;
      for (final p in purchases) {
        purchasesPaid += (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
      }

      // ===== هنا نحسب adjustedCurrent بنفس منطق الدالة اللي بعتهالك =====
      // نأخذ: starting + salesNetCash - purchasePaidCash ، ثم نمنع السالب
      final dbHelper = DBHelper.instance;
      final db = await dbHelper.database;

      // 1) starting
      final starting = await dbHelper.getLatestDrawerStartingAmount();

      // 2) sales net cash: نحاول الحصول من totals إذا متاح، وإلا نستخدم استعلام احتياطي
      double salesNetCash = 0.0;
      try {
        final totals = await dbHelper.getDrawerTotals(fromDate: null, toDate: null);
        salesNetCash = (totals['sales_net_cash'] as num?)?.toDouble()
            ?? (totals['sales_net'] as num?)?.toDouble()
            ?? 0.0;
      } catch (e) {
        debugPrint('Could not get totals for drawer during closeShift: $e');
        salesNetCash = 0.0;
      }

      // 3) purchasePaidCash: مجموع المدفوعات النقدية على سندات الشراء (بدون فلترة)
      double purchasePaidCash = 0.0;
      try {
        // محاولة استعلام SUM مباشرة
        final rows = await db.rawQuery(
            "SELECT SUM(COALESCE(paid_amount,0)) AS total FROM purchase_receipts WHERE payment_type = 'cash'"
        );
        purchasePaidCash = (rows.isNotEmpty && rows.first['total'] != null)
            ? (rows.first['total'] as num).toDouble()
            : 0.0;
      } catch (e) {
        debugPrint('Failed to compute purchasePaidCash in closeShift: $e');
        // fallback: جمع من getPaidPurchaseReceipts
        try {
          final paidReceipts = await dbHelper.getPaidPurchaseReceipts();
          double sum = 0.0;
          for (final r in paidReceipts) {
            final type = r['payment_type'] as String? ?? 'cash';
            if (type == 'cash') sum += (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
          }
          purchasePaidCash = sum;
        } catch (e2) {
          debugPrint('Fallback also failed: $e2');
          purchasePaidCash = 0.0;
        }
      }

      final computedFromParts = starting + salesNetCash - purchasePaidCash;
      final adjustedCurrent = computedFromParts < 0.0 ? 0.0 : computedFromParts;

      // ===== استخدم adjustedCurrent في التقرير بدل computeCurrentDrawerAmount =====
      final drawerCurrent = adjustedCurrent;

      final walletAmount = await dbHelper.getLatestCardWalletAmount();
      final untransferredCard = await _getUntransferredCardAmountSafe();
      final cardTotalAvailable = untransferredCard + walletAmount;
      final cardForCashier = await DBHelper.instance.getCardAmountByCashierBetweenDates(
        cashierUsername: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      final creditOutstandingForCashier = await DBHelper.instance.getCreditOutstandingByCashierBetweenDates(
        cashierUsername: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      final purchaseReceiptsOutstandingForUser = await DBHelper.instance.getPurchaseReceiptsOutstandingByUserBetweenDates(
        username: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
      );

      // build report widget (ShiftReportWidget is assumed to accept these fields)
      final reportWidget = ShiftReportWidget(
        cashierUsername: username,
        fromDate: fromDateStr,
        toDate: toDateStr,
        sales: sales,
        saleItemsMap: saleItemsMap,
        purchases: purchases,
        totals: {
          'sales_total': salesTotal,
          'sales_paid_cash': salesPaidCash,
          'sales_paid_card': salesPaidCard,
          'purchases_paid': purchasesPaid,
        },
        width: 280,
        drawerCurrent: drawerCurrent,
        cardForCashier: cardTotalAvailable,
        creditOutstandingForCashier: creditOutstandingForCashier,
        purchaseReceiptsOutstandingForUser: purchaseReceiptsOutstandingForUser,
      );

      // طباعة التقرير
      try {
        await PrintService.printWidgetUsingOverlay(context, reportWidget, width: 280, pixelRatio: 2.0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم طباعة تقرير الشفت لليوم')));
      } catch (e, st) {
        debugPrint('Shift print failed: $e\n$st');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل طباعة تقرير الشفت')));
      }

    } catch (e, st) {
      debugPrint('Error while closing shift: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تقفيل الشفت: $e')));
    } finally {
      setState(() => _closingShift = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptWidth = 380.0;
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white70),

        leadingWidth: 200,
        toolbarHeight: 65,
        leading: Row(
          children: [
            BackButton(color: Colors.white70),
            SizedBox(width: 20,),
            InkWell(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 5,),
                  IconButton(
                    tooltip: 'المحفظه الالكترونيه',
                    icon: const Icon(Icons.account_balance_wallet),
                    onPressed: _openCardWalletDialog,
                  ),
                  Text(
                    _cardTotalAvailable.toStringAsFixed(1),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            SizedBox(width: 20,),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 10,),

                Tooltip(
                  message: "المبلغ الموجود في الدرج",
                  child: SvgPicture.asset(
                    "assets/icons/drawer.svg",
                    color: Colors.white70,
                    width: 25,
                    height: 25,
                  ),
                ),
                SizedBox(height: 10,),
                Text(
                  Drawer.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ],
        ),

        title: Text(
          '${_currentUsername ?? widget.cashierUsername}',
          style: const TextStyle(color: Colors.white, fontSize: 27),
        ),

        actions: [
          IconButton(
            tooltip: 'الفواتير السابقة',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PreviousSalesScreen(
                    cashierUsername: _currentUsername ?? widget.cashierUsername,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'استلام بضاعه',
            icon: const Icon(Icons.category),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReceiveFromSupplierScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'تقفيل الشفت',
            icon: const Icon(Icons.lock_clock),
            onPressed: _closingShift ? null : _closeShift,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: CustomFormField(
                    hint: 'امسح الباركود أو اكتب واضغط Enter',
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,
                    onFieldSubmitted: _onBarcodeSubmitted,
                  ),
                ),
                SizedBox(width: 12),
                CustomButton(
                  text: 'اضافه',
                  onPressed: () => _onBarcodeSubmitted(_barcodeController.text),
                  infinity: false,
                )
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: CartList(
                cart: _cart,
                onChangeQty: _changeQuantity,
                onRemove: (pid) => setState(() => _cart.remove(pid)),
                onEditQty: _editQuantityDialog,
              ),
            ),
            const SizedBox(height: 12),
            // Payment controls + discount button row
            Row(
              children: [
                Expanded(
                  child: PaymentControls(
                    paidController: _paidController,
                    addQuickPaid: _addQuickPaid,
                    setQuickPaid: _setQuickPaid,
                    total: _effectiveTotal, // مهم: عرض الإجمالي بعد الخصم
                    saving: _saving,
                    onPayAndSave: () {
                      setState(() {});
                      _saveSale(requireFullPayment: true, paymentMethod: 'cash');
                    },
                    onSaveAsLater: () => _saveSale(requireFullPayment: false, paymentMethod: 'credit'),
                    onSaveAsCard: () => _saveSale(requireFullPayment: true, paymentMethod: 'wallet'),
                    // If you want a BUTTON specifically to pay via the app wallet, you can hook it to:
                    // onSaveAsWallet: () => _saveSale(requireFullPayment: true, paymentMethod: 'wallet'),
                  ),
                ),
                const SizedBox(width: 8),
                // زر الخصم
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _showDiscountDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _discountValue > 0 ? Colors.orange : AppColorsDark.bgColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_offer, color: Colors.white),
                        const SizedBox(height: 2),
                        Text(
                          _discountValue > 0 ? '${_discountValue.toStringAsFixed(0)}%' : 'خصم',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Offstage(
              offstage: true, // تغيير إلى false للتصحيح ورؤية الإيصال
              child: RepaintBoundary(
                key: _receiptKey,
                child: ReceiptWidget(cart: _cart, paid: _paid, cashierUsername: _currentUsername ?? widget.cashierUsername, width: receiptWidth, useCairo: true),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}
