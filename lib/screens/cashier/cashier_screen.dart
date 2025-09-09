// lib/screens/cashier/cashier_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:cashgo/models/login.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../shared/login_screen.dart';
import 'ReceiveFromSupplier.dart';
import 'histroy.dart';

// ضع هذه التعاريف أعلى الملف (قبل CashierScreen)
class ArrowDownIntent extends Intent { const ArrowDownIntent(); }
class ArrowUpIntent extends Intent { const ArrowUpIntent(); }
class EnterIntent extends Intent { const EnterIntent(); }
class EscapeIntent extends Intent { const EscapeIntent(); }


class CashierScreen extends StatefulWidget {
  static const routName = "/Cashier";
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
  bool _dialogOpening = false;
  final nameFocus = FocusNode();



  // --------- Discount state ----------
  // design: percent-only discount (as requested), from 0% to 50% step 5
  String _discountType = 'percent';
  double _discountValue = 0.0; // e.g. 5.0 means 5%
  List<Map<String, dynamic>> _inlineSearchResults = [];
  bool _inlineLoading = false;
  Timer? _inlineDebounce;
  int _inlineSelectedIndex = -1;
  final ScrollController _inlineScrollController = ScrollController();
  final FocusNode _inlineKeyboardNode = FocusNode();

  Future<void> _scrollInlineToIndex(int index) async {
    if (!_inlineScrollController.hasClients) return;
    final itemHeight = 72.0; // تقريب ارتفاع ListTile؛ عدِّل لو كان مختلف
    final offset = (index * itemHeight).clamp(0.0, _inlineScrollController.position.maxScrollExtent);
    await _inlineScrollController.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
  }

  void _handleInlineKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return; // تعامل فقط مع أحداث الضغط
    if (_inlineSearchResults.isEmpty) return;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _inlineSelectedIndex = (_inlineSelectedIndex + 1).clamp(0, _inlineSearchResults.length - 1);
      });
      _scrollInlineToIndex(_inlineSelectedIndex);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _inlineSelectedIndex = (_inlineSelectedIndex - 1).clamp(0, _inlineSearchResults.length - 1);
      });
      _scrollInlineToIndex(_inlineSelectedIndex);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final idx = _inlineSelectedIndex >= 0 ? _inlineSelectedIndex : 0;
      if (idx >= 0 && idx < _inlineSearchResults.length) {
        final item = _inlineSearchResults[idx];

        // منع الاستدعاء المزدوج
        if (_dialogOpening) return;
        _dialogOpening = true;

        Future.microtask(() async {
          try {
            await _showProductDetailDialog(item);
          } finally {
            if (!mounted) return;
            setState(() {
              _inlineSearchResults = [];
              _inlineLoading = false;
              _inlineSelectedIndex = -1;
              _dialogOpening = false;
            });
          }
        });
      }
    } else if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _inlineSearchResults = [];
        _inlineLoading = false;
        _inlineSelectedIndex = -1;
      });
    }
  }



  void _scheduleInlineSearch(String q) {
    _inlineDebounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _inlineSearchResults = [];
        _inlineLoading = false;
      });
      return;
    }
    _inlineDebounce = Timer(const Duration(milliseconds: 300), () => _runInlineSearch(q));
  }

  Future<void> _runInlineSearch(String q) async {
    setState(() {
      _inlineLoading = true;
    });
    try {
      final rows = await DBHelper.instance.searchProductsByName(q, limit: 50);
      setState(() {
        _inlineSearchResults = rows;
      });
    } catch (e) {
      debugPrint('inline search error: $e');
      setState(() {
        _inlineSearchResults = [];
      });
    } finally {
      if (mounted) setState(() => _inlineLoading = false);
    }
  }

  /// Add a product (map) to cart easily (default qty = 1). Shows snackbars on errors.
  void _addProductMapToCart(Map<String, dynamic> productMap, {int qty = 1}) {
    final pid = (productMap['id'] as num?)?.toInt();
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج غير صالح')));
      return;
    }

    // Ensure total_units computed like in your detail dialog
    if (!productMap.containsKey('total_units')) {
      final cartons = (productMap['quantity'] as num?)?.toInt() ?? 0;
      final unitsInCarton = (productMap['units_in_carton'] as num?)?.toInt() ?? 0;
      final remainder = (productMap['units_remainder'] as num?)?.toInt() ?? 0;
      productMap['units_remainder'] = remainder;
      productMap['total_units'] = cartons * unitsInCarton + remainder;
    }

    final available = (productMap['total_units'] as num?)?.toInt() ?? 0;
    final already = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;

    if (already + qty > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كمية كافية')));
      return;
    }

    setState(() {
      if (_cart.containsKey(pid)) {
        _cart[pid]!.quantity += qty;
      } else {
        final prodModel = Product.fromMap(productMap);
        _cart[pid] = CartItem(product: prodModel, quantity: qty);
      }

      // after adding we may want to clear suggestions and the input:
      _inlineSearchResults = [];
      _barcodeController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $qty من ${productMap['name']}')));
    FocusScope.of(context).requestFocus(_barcodeFocus);
  }


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
    _inlineDebounce?.cancel();
    _inlineScrollController.dispose();
    _inlineKeyboardNode.dispose();
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
      // تأكد من وجود جداول أساسية
      await dbHelper.ensureCardWalletTable();
      await dbHelper.ensureCashDrawerTable();
      await dbHelper.ensureDrawerWithdrawnColumnExists(); // موجودة في DBHelper اللي بعته

      // تأكد من وجود العمود drawer_withdrawn_amount في جدول sales (لو مش موجود - أضفه هنا)
      final dbForMigration = await dbHelper.database;
      try {
        final cols = await dbForMigration.rawQuery("PRAGMA table_info('sales');");
        final hasWithdrawnAmount = cols.any((c) => (c['name'] as String?) == 'drawer_withdrawn_amount');
        if (!hasWithdrawnAmount) {
          await dbForMigration.execute('ALTER TABLE sales ADD COLUMN drawer_withdrawn_amount REAL DEFAULT 0;');
          debugPrint('Migration: added drawer_withdrawn_amount column to sales');
        }
      } catch (e, st) {
        // لو فشل التحقق/الإضافة، نكتفي باللوق وحاول تتابع — العملية قد تفشل لاحقًا لو استدعى الكود العمود
        debugPrint('Warning: ensure drawer_withdrawn_amount column check failed: $e\n$st');
      }

      final currentUser = await dbHelper.getCurrentUser();
      final username = (currentUser != null && currentUser['username'] != null)
          ? currentUser['username'] as String
          : widget.cashierUsername;

      // أعد تحميل القيم المعروضة (لو عندك)
      await _loadCardTotals();

      // اقرأ القيم الأساسية من DB (نحتاجها للحسابات والـ rollback المحتمل)
      final latestWallet = await dbHelper.getLatestCardWalletAmount();
      final latestDrawerStarting = await dbHelper.getLatestDrawerStartingAmount();

      final db = await dbHelper.database;
      const double eps = 0.0001;

      if (fromDrawerToWallet) {
        // سحب من الدُرج إلى المحفظة
        await db.transaction((txn) async {
          // 1) حساب إجمالي المبلغ المتاح من فواتير الكاش (نأخذ بعين الاعتبار المسحوبات الجزئية)
          final totalRow = await txn.rawQuery(
            '''
          SELECT SUM(
            CASE
              WHEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0)) > 0
              THEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0))
              ELSE 0
            END
          ) as total_available
          FROM sales
          WHERE payment_method = ?
          ''',
            ['cash'],
          );

          final availableFromSales = (totalRow.isNotEmpty && totalRow.first['total_available'] != null)
              ? (totalRow.first['total_available'] as num).toDouble()
              : 0.0;

          // التأكد أن المجموع الكلي (sales available + starting) يغطي الطلب
          if (availableFromSales + latestDrawerStarting + eps < amount) {
            throw 'لا يوجد ما يكفي في الدرج (المتوفر من فواتير الكاش: ${availableFromSales.toStringAsFixed(2)} ، وبداية الدرج: ${latestDrawerStarting.toStringAsFixed(2)})';
          }

          double remaining = amount;

          // 2) اختر فواتير الكاش بالترتيب القديم → جديد (نقرأ net وdrawer_withdrawn_amount)
          final rows = await txn.rawQuery(
            '''
          SELECT id,
                 (COALESCE(paid_amount,0) - COALESCE(change_amount,0)) AS net,
                 COALESCE(drawer_withdrawn_amount,0) as withdrawn
          FROM sales
          WHERE payment_method = ?
          ORDER BY date ASC
          ''',
            ['cash'],
          );

          // 3) تكرار الفواتير واستهلاك المبلغ (قد نأخذ جزءاً من الفاتورة)
          for (final r in rows) {
            if (remaining <= eps) break;
            final int id = (r['id'] as num).toInt();
            final double net = (r['net'] as num).toDouble();
            final double alreadyWithdrawn = (r['withdrawn'] as num).toDouble();
            final double availableFromThisSale = (net - alreadyWithdrawn).clamp(0.0, double.infinity);
            if (availableFromThisSale <= eps) continue; // لا شيء متاح من هذه الفاتورة

            if (availableFromThisSale <= remaining + eps) {
              // نأخذ ما تبقى من هذه الفاتورة بالكامل (قد يكون جزءًا يكمل الفاتورة)
              final double newWithdrawn = (alreadyWithdrawn + availableFromThisSale).clamp(0.0, net);
              await txn.rawUpdate(
                'UPDATE sales SET drawer_withdrawn_amount = ?, drawer_withdrawn = ? WHERE id = ?',
                [newWithdrawn, (newWithdrawn + eps >= net) ? 1 : 0, id],
              );
              remaining -= availableFromThisSale;
              // استمر للفاتورة التالية
            } else {
              // نحتاج فقط جزءًا من هذه الفاتورة ليغطّي remaining
              final double take = remaining;
              final double newWithdrawn = (alreadyWithdrawn + take).clamp(0.0, net);
              await txn.rawUpdate(
                'UPDATE sales SET drawer_withdrawn_amount = ?, drawer_withdrawn = ? WHERE id = ?',
                [newWithdrawn, (newWithdrawn + eps >= net) ? 1 : 0, id],
              );
              remaining = 0.0;
              break;
            }
          }

          // 4) إذا بقي مبلغ (remaining) — نخصمه من بداية الدُرج (latestDrawerStarting)
          if (remaining > eps) {
            final double deductFromStarting = remaining;
            final double newStarting = (latestDrawerStarting - deductFromStarting).clamp(0.0, double.infinity);
            final now = DateTime.now().toIso8601String();
            await txn.insert('cash_drawer', {
              'amount': newStarting,
              'updated_by': username,
              'note': 'سحب إلى المحفظة (-${amount.toStringAsFixed(2)})',
              'created_at': now,
            });
            // remaining أصبح 0 بعد خصم البداية
            remaining = 0.0;
          } else {
            // حالة استهلاك كامل من الفواتير فقط — لو أردت توثيق تصفير بداية الدرج يمكنك إضافته كما قبلاً
            if ((amount >= (latestDrawerStarting + availableFromSales) - eps) && latestDrawerStarting > eps) {
              final now = DateTime.now().toIso8601String();
              await txn.insert('cash_drawer', {
                'amount': 0.0,
                'updated_by': username,
                'note': 'سحب إلى المحفظة — تصفير الدرج بعد استهلاك كامل الرصيد',
                'created_at': now,
              });
            }
          }

          // 5) أخيراً: أدخل قيد في card_wallet (زيادة المحفظة بالمبلغ المنقول)
          final now = DateTime.now().toIso8601String();
          await txn.insert('card_wallet', {
            'amount': amount,
            'updated_by': username,
            'note': 'تحويل من الدرج إلى المحفظة',
            'created_at': now,
          });
        }); // نهاية الـ transaction

        // بعد النجاح: أعد تحميل القيم في الواجهة
        await _loadCardTotals();
      } else {
        // from wallet -> drawer (إيداع)
        if (amount > latestWallet + 0.000001) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('الرصيد في المحفظة غير كافٍ. المتاح: EGP ${latestWallet.toStringAsFixed(2)}')));
          return;
        }

        await db.transaction((txn) async {
          final now = DateTime.now().toIso8601String();
          // نخصم من المحفظة (سجل قيد سالب)
          await txn.insert('card_wallet', {
            'amount': -amount,
            'updated_by': username,
            'note': 'تحويل إلى الدرج (-${amount.toStringAsFixed(2)})',
            'created_at': now,
          });

          // ثم نسجل بداية درج جديدة (نضيف المبلغ إلى latestDrawerStarting)
          final newStarting = latestDrawerStarting + amount;
          await txn.insert('cash_drawer', {
            'amount': newStarting,
            'updated_by': username,
            'note': 'إيداع من المحفظة (+${amount.toStringAsFixed(2)})',
            'created_at': now,
          });
        });

        // reload UI values
        await _loadCardTotals();
      }
    } catch (e, st) {
      debugPrint('transferBetweenDrawerAndWallet failed: $e\n$st');
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
      } else
      if (paymentMethod == 'cash') {
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
        else if (method == 'wallet') salesPaidCard += net;
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
  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColorsDark.bgCardColor,
          title: const Text('تأكيد الخروج',style: TextStyle(color: Colors.white),),
          content: const Text('هل أنت متأكد من الخروج؟',style: TextStyle(color: Colors.white70),),
          actions: [
            TextButton(

              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('تأكيد',style: TextStyle(color: Colors.white),),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء',style: TextStyle(color: Colors.white70),),
            ),

          ],
        ),
      ),
    );

    if (shouldExit == true && mounted) {
      // تذهب إلى LoginScreen وتزيل باقي الشاشة من الستاك
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }


  Future<void> _openNameSearchDialog({String initialQuery = ''}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            List<Map<String, dynamic>> results = [];
            bool loading = false;
            Timer? debounce;
            final controller = TextEditingController(text: initialQuery);
            final FocusNode textFocus = FocusNode();
            final FocusNode keyFocus = FocusNode();
            final ScrollController scrollController = ScrollController();
            int selectedIndex = -1;

            Future<void> runSearch(String q) async {
              setState2(() => loading = true);
              try {
                final rows = await DBHelper.instance.searchProductsByName(q, limit: 50);
                setState2(() {
                  results = rows;
                  selectedIndex = results.isNotEmpty ? 0 : -1;
                });
              } catch (e) {
                debugPrint('searchProductsByName error: $e');
                setState2(() { results = []; selectedIndex = -1; });
              } finally {
                setState2(() => loading = false);
              }
            }

            void scheduleSearch(String q) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 300), () {
                if (q.trim().isNotEmpty) runSearch(q);
                else setState2(() { results = []; selectedIndex = -1; });
              });
            }

            void ensureSelectedVisible() {
              if (!scrollController.hasClients || selectedIndex < 0) return;
              const itemHeight = 72.0;
              final offset = (selectedIndex * itemHeight).clamp(0.0, scrollController.position.maxScrollExtent);
              scrollController.animateTo(offset, duration: const Duration(milliseconds: 150), curve: Curves.easeInOut);
            }

            void _ensureKeyFocusAndUnfocusTextIfNeeded() {
              if (textFocus.hasFocus) {
                try { textFocus.unfocus(); } catch (_) {}
              }
              if (!keyFocus.hasFocus) {
                FocusScope.of(ctx2).requestFocus(keyFocus);
              }
            }

            if (initialQuery.trim().isNotEmpty && results.isEmpty && !loading) {
              Future.microtask(() => runSearch(initialQuery));
            }
            String customInputText = controller.text;

            Widget buildCustomInput() {
              return GestureDetector(
                onTap: () {
                  // اطلب الفوكس لكي نلتقط مفاتيح الكيبورد عبر RawKeyboardListener
                  if (!textFocus.hasFocus) FocusScope.of(ctx2).requestFocus(textFocus);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColorsDark.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          customInputText.isEmpty ? 'اكتب اسم المنتج...' : customInputText,
                          style: TextStyle(
                            color: customInputText.isEmpty ? Colors.white38 : Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (loading)
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator())
                      else if (customInputText.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () {
                            setState2(() {
                              customInputText = '';
                              controller.text = '';
                              results = [];
                              selectedIndex = -1;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              );
            }

            return Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.arrowDown): const ArrowDownIntent(),
                LogicalKeySet(LogicalKeyboardKey.arrowUp): const ArrowUpIntent(),
                LogicalKeySet(LogicalKeyboardKey.enter): const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.numpadEnter): const EnterIntent(),
                LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ArrowDownIntent: CallbackAction<ArrowDownIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex = (selectedIndex + 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  ArrowUpIntent: CallbackAction<ArrowUpIntent>(onInvoke: (intent) {
                    _ensureKeyFocusAndUnfocusTextIfNeeded();
                    if (results.isNotEmpty) {
                      setState2(() {
                        selectedIndex = (selectedIndex - 1).clamp(0, results.length - 1);
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) => ensureSelectedVisible());
                    }
                    return null;
                  }),
                  EnterIntent: CallbackAction<EnterIntent>(onInvoke: (intent) {
                    if (selectedIndex >= 0 && selectedIndex < results.length) {
                      final item = results[selectedIndex];
                      if (_dialogOpening) return null;
                      _dialogOpening = true;
                      Future.microtask(() async {
                        try {
                          await _showProductDetailDialog(item);
                        } finally {
                          if (!mounted) return;
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                            _dialogOpening = false;
                          });
                        }
                      });
                    } else {
                      if (controller.text.trim().isNotEmpty) runSearch(controller.text.trim());
                    }
                    return null;
                  }),
                  EscapeIntent: CallbackAction<EscapeIntent>(onInvoke: (intent) {
                    Navigator.of(ctx2).pop();
                    return null;
                  }),
                },

                child: RawKeyboardListener(
                  focusNode: textFocus,
                  onKey: (RawKeyEvent event) {
                    if (event is RawKeyDownEvent) {
                      final key = event.logicalKey;

                      // handle printable characters (event.character may be null on some platforms, but often works on macOS)
                      final char = (event.character ?? '');
                      if (char.isNotEmpty && char.codeUnitAt(0) != 10 && !event.isControlPressed && !event.isMetaPressed) {
                        // append printable character
                        setState2(() {
                          customInputText += char;
                          controller.text = customInputText;
                        });
                        scheduleSearch(customInputText);
                        return;
                      }

                      if (key == LogicalKeyboardKey.backspace) {
                        setState2(() {
                          if (customInputText.isNotEmpty) {
                            customInputText = customInputText.substring(0, customInputText.length - 1);
                            controller.text = customInputText;
                            if (customInputText.trim().isEmpty) {
                              results = [];
                              selectedIndex = -1;
                            } else {
                              scheduleSearch(customInputText);
                            }
                          }
                        });
                        return;
                      }

                      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
                        // نفّذ بحث نهائي أو افتح العنصر المختار
                        if (customInputText.trim().isNotEmpty && results.isEmpty) {
                          runSearch(customInputText.trim());
                        } else if (selectedIndex >= 0 && selectedIndex < results.length) {
                          final item = results[selectedIndex];
                          if (_dialogOpening) return;
                          _dialogOpening = true;
                          Future.microtask(() async {
                            try {
                              await _showProductDetailDialog(item);
                            } finally {
                              if (!mounted) return;
                              setState(() {
                                _inlineSearchResults = [];
                                _inlineLoading = false;
                                _inlineSelectedIndex = -1;
                                _dialogOpening = false;
                              });
                            }
                          });
                        }
                        return;
                      }

                      if (key == LogicalKeyboardKey.escape) {
                        Navigator.of(ctx2).pop();
                        return;
                      }

                      // arrows: نحول الفوكس إلى keyFocus لأننا نريد أنها تستخدم لتنقّل النتائج
                      if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
                        // ننقل الفوكس لالتقاط الأسهم في المكان اللي يتعامل مع التنقّل (keyFocus موجود في الـ dialog)
                        if (!keyFocus.hasFocus) FocusScope.of(ctx2).requestFocus(keyFocus);

                        // وإذا أردتي يمكن هنا أيضًا التحكم المباشر بتغيير selectedIndex
                        if (results.isNotEmpty) {
                          setState2(() {
                            if (key == LogicalKeyboardKey.arrowDown) {
                              selectedIndex = (selectedIndex + 1).clamp(0, results.length - 1);
                            } else {
                              selectedIndex = (selectedIndex - 1).clamp(0, results.length - 1);
                            }
                          });
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            // scroll to selected
                            const itemHeight = 72.0;
                            if (scrollController.hasClients && selectedIndex >= 0) {
                              final offset = (selectedIndex * itemHeight).clamp(0.0, scrollController.position.maxScrollExtent);
                              scrollController.animateTo(offset, duration: const Duration(milliseconds: 150), curve: Curves.easeInOut);
                            }
                          });
                        }
                        return;
                      }
                    }
                  },
                  child: buildCustomInput(),
                ),
              ),
            );
          }),
        );
      },
    );
  }
  Future<void> _showProductDetailDialog(Map<String, dynamic> product) async {
    if (!product.containsKey('total_units')) {
      final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
      final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
    }

    // NOTE: we intentionally do NOT dispose this controller here to avoid a race where
    // framework tries to re-add listeners while the controller was disposed (hot reload / pop races).
    final qtyController = TextEditingController(text: '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        int qty = 1;
        final available = (product['total_units'] as num?)?.toInt() ?? 0;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(builder: (ctx2, setState2) {
            final name = (product['name'] ?? '').toString();
            final price = (product['selling_price'] ?? product['sellingPrice'] ?? 0.0);
            final desc = (product['description'] ?? '').toString();

            // extracted add-to-cart logic so we can call it from button and onSubmitted
            Future<void> addRequested() async {
              final pid = (product['id'] as num?)?.toInt();
              if (pid == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج غير صالح')));
                return;
              }
              final already = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;
              final requested = qty <= 0 ? 1 : qty; // default 1 if empty or zero
              if (already + requested > available) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كمية كافية')));
                return;
              }

              // Update outer state (the cart)
              if (mounted) {
                setState(() {
                  if (_cart.containsKey(pid)) {
                    _cart[pid]!.quantity += requested;
                  } else {
                    final prodModel = Product.fromMap(product);
                    _cart[pid] = CartItem(product: prodModel, quantity: requested);
                  }
                });
              }

              // close dialog and give feedback
              Navigator.of(ctx2).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة $requested قطعة من ${product['name']}')));
                _barcodeController.clear();
                FocusScope.of(context).requestFocus(_barcodeFocus);
              }
            }

            return AlertDialog(
              backgroundColor: AppColorsDark.bgCardColor,
              title: Text(name, style: const TextStyle(color: Colors.white)),
              content: SingleChildScrollView( // prevents overflow when keyboard opens
                child: SizedBox(
                  width: 320,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (desc.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(desc, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.right),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('السعر: ${price.toString()}', style: const TextStyle(color: Colors.white70)),
                          Text('متاح: $available', style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: qty > 1
                                ? () {
                              setState2(() {
                                qty = (qty - 1).clamp(0, available);
                                qtyController.value = TextEditingValue(
                                  text: qty.toString(),
                                  selection: TextSelection.collapsed(offset: qty.toString().length),
                                );
                              });
                            }
                                : null,
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColorsDark.bgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: TextField(
                              controller: qtyController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 18),
                              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                              onChanged: (v) {
                                setState2(() {
                                  final trimmed = v.trim();
                                  if (trimmed.isEmpty) {
                                    qty = 0;
                                  } else {
                                    final parsed = int.tryParse(trimmed) ?? 0;
                                    qty = parsed;
                                    if (qty > available) {
                                      qty = available;
                                      qtyController.value = TextEditingValue(
                                        text: qty.toString(),
                                        selection: TextSelection.collapsed(offset: qty.toString().length),
                                      );
                                    }
                                  }
                                });
                              },
                              // handle Enter key as "Add"
                              onSubmitted: (v) async {
                                final trimmed = v.trim();
                                if (trimmed.isEmpty) {
                                  qty = 1;
                                } else {
                                  qty = int.tryParse(trimmed) ?? 1;
                                }
                                if (qty > available) qty = available;
                                await addRequested();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: qty < available
                                ? () {
                              setState2(() {
                                qty = (qty + 1).clamp(0, available);
                                qtyController.value = TextEditingValue(
                                  text: qty.toString(),
                                  selection: TextSelection.collapsed(offset: qty.toString().length),
                                );
                              });
                            }
                                : null,
                            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgColor),
                  onPressed: () {
                    Navigator.of(ctx2).pop();
                    Future.microtask(() {
                      _barcodeController.clear();
                      FocusScope.of(context).requestFocus(_barcodeFocus);
                    });
                  },
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final trimmed = qtyController.text.trim();
                    if (trimmed.isEmpty) {
                      qty = 1;
                    } else {
                      qty = int.tryParse(trimmed) ?? 1;
                    }
                    if (qty > available) qty = available;
                    await addRequested();
                  },
                  child: const Text('أضف إلى السلة'),
                ),
              ],
            );
          }),
        );
      },
    );

    // note: intentionally not disposing qtyController here to avoid a race that causes
    // "used after being disposed" in some hot-reload / pop timing scenarios.
    // If you prefer, you can schedule a dispose later:
    // Future.delayed(Duration(seconds: 5), () { qtyController.dispose(); });
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
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
              onPressed: () => _confirmExit(),
            ),
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
                    NumberFormat("#,###").format(_cardTotalAvailable),
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
                  NumberFormat("#,###").format(Drawer),
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
                  child: Focus(
                    focusNode: _inlineKeyboardNode,
                    onKey: (FocusNode node, RawKeyEvent event) {
                      if (event is RawKeyDownEvent) {
                        final key = event.logicalKey;
                        if (key == LogicalKeyboardKey.arrowDown) {
                          setState(() {
                            _inlineSelectedIndex = (_inlineSelectedIndex + 1).clamp(0, _inlineSearchResults.length - 1);
                          });
                          _scrollInlineToIndex(_inlineSelectedIndex);
                          return KeyEventResult.handled;
                        } else if (key == LogicalKeyboardKey.arrowUp) {
                          setState(() {
                            _inlineSelectedIndex = (_inlineSelectedIndex - 1).clamp(0, _inlineSearchResults.length - 1);
                          });
                          _scrollInlineToIndex(_inlineSelectedIndex);
                          return KeyEventResult.handled;
                        } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
                          // <-- التغيير: نتعامل مع Enter فقط لو في نتائج للبحث بالكلمة
                          if (_inlineSearchResults.isNotEmpty) {
                            final idx = _inlineSelectedIndex >= 0 ? _inlineSelectedIndex : 0;
                            if (_dialogOpening) return KeyEventResult.handled;
                            _dialogOpening = true;
                            Future.microtask(() async {
                              try {
                                await _showProductDetailDialog(_inlineSearchResults[idx]);
                              } finally {
                                if (!mounted) return;
                                setState(() {
                                  _inlineSearchResults = [];
                                  _inlineLoading = false;
                                  _inlineSelectedIndex = -1;
                                  _dialogOpening = false;
                                });
                              }
                            });
                            return KeyEventResult.handled;
                          }
                          // لو مفيش نتائج، متقبّضش على Enter هنا علشان يسمح بعمل onSubmitted (الباركود)
                          return KeyEventResult.ignored;
                        } else if (key == LogicalKeyboardKey.escape) {
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                          });
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: TextField(
                        controller: _barcodeController,
                        focusNode: _barcodeFocus,
                        onTap: () {
                          // تأكد إن node الخاص بالكيبورد يستلم الفوكس أيضاً عند الضغط في الحقل
                          if (!_inlineKeyboardNode.hasFocus) FocusScope.of(context).requestFocus(_inlineKeyboardNode);
                        },
                        onChanged: (v) {
                          final trimmed = v.trim();
                          final containsLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(trimmed);
                          if (containsLetters) {
                            _scheduleInlineSearch(trimmed);
                          } else {
                            _inlineDebounce?.cancel();
                            setState(() {
                              _inlineSearchResults = [];
                              _inlineLoading = false;
                              _inlineSelectedIndex = -1;
                            });
                          }
                        },
                        onSubmitted: (v) async {
                          final trimmed = v.trim();
                          if (trimmed.isEmpty) return;

                          final containsLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(trimmed);

                          if (containsLetters) {
                            if (_inlineSearchResults.isNotEmpty) {
                              final first = _inlineSearchResults.first;
                              if (_dialogOpening) return;
                              _dialogOpening = true;
                              try {
                                await _showProductDetailDialog(first);
                              } finally {
                                if (!mounted) return;
                                setState(() {
                                  _inlineSearchResults = [];
                                  _inlineLoading = false;
                                  _inlineSelectedIndex = -1;
                                  _dialogOpening = false;
                                });
                              }
                            } else {
                              await _openNameSearchDialog(initialQuery: trimmed);
                            }
                          } else {
                            // === barcode path: بحث بالباركود وإضافة للسلة ===
                            await _onBarcodeSubmitted(trimmed);

                            // تنظيف الحقل وإرجاع الفوكس للباركود (مريح للكاشير)
                            if (!mounted) return;
                            setState(() {
                              _barcodeController.clear();
                              _inlineSearchResults = [];
                              _inlineSelectedIndex = -1;
                            });
                            FocusScope.of(context).requestFocus(_barcodeFocus);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'امسح الباركود أو اكتب اسم المنتج ثم اضغط Enter',
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () async {
                              final q = _barcodeController.text.trim();
                              if (q.isEmpty) return;
                              final containsLetters = RegExp(r'[A-Za-z\u0621-\u064A]').hasMatch(q);
                              if (containsLetters) {
                                _scheduleInlineSearch(q);
                                if (!_inlineKeyboardNode.hasFocus) FocusScope.of(context).requestFocus(_inlineKeyboardNode);
                              } else {
                                await _onBarcodeSubmitted(q);
                              }
                            },
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        ),
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.text,
                      ),
                    ),
                  ),


                ),
                SizedBox(width: 12),
                CustomButton(
                  text: 'اضافه',
                  onPressed: () => _onBarcodeSubmitted(_barcodeController.text),
                  infinity: false,
                ),

              ],
            ),
            SizedBox(height: 15,),
            // show inline results area
            if (_inlineLoading || _inlineSearchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColorsDark.bgCardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 300),
                child: _inlineLoading
                    ? const Center(child: Text('جاري البحث...', style: TextStyle(color: Colors.white70)))
                    : ListView.separated(
                  controller: _inlineScrollController,
                  shrinkWrap: true,
                  itemCount: _inlineSearchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 0.5, color: Colors.white10),
                  itemBuilder: (context, i) {
                    final item = _inlineSearchResults[i];
                    final name = (item['name'] ?? '').toString();
                    final barcode = (item['barcode'] ?? '').toString();
                    final price = (item['selling_price'] ?? item['sellingPrice'] ?? '').toString();
                    final stock = (item['total_units'] ?? 0).toString();
                    final isSelected = i == _inlineSelectedIndex;

                    return Container(
                      color: isSelected ? Colors.white10 : Colors.transparent,
                      child: ListTile(
                        tileColor: Colors.transparent,
                        title: Text(name, style: TextStyle(color: isSelected ? Colors.white : Colors.white, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text('باركود: $barcode  •  سعر: $price  •  متاح: $stock',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        onTap: () async {
                          final item = _inlineSearchResults[i];
                          await _showProductDetailDialog(item);
                          if (!mounted) return;
                          setState(() {
                            _inlineSearchResults = [];
                            _inlineLoading = false;
                            _inlineSelectedIndex = -1;
                          });
                        },

                      ),
                    );
                  },
                ),
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
                      Future.microtask(() {
                        _barcodeController.clear();
                        FocusScope.of(context).requestFocus(_barcodeFocus);
                      });
                    },
                    onSaveAsLater: (){
                      _saveSale(requireFullPayment: false, paymentMethod: 'credit');
                      Future.microtask(() {
                        _barcodeController.clear();
                        FocusScope.of(context).requestFocus(_barcodeFocus);
                      });
                    },
                    onSaveAsCard: () {
                      _saveSale(requireFullPayment: true, paymentMethod: 'wallet');
                      Future.microtask(() {
                        _barcodeController.clear();
                        FocusScope.of(context).requestFocus(_barcodeFocus);
                      });
                    },
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
