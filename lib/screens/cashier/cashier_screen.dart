import 'package:flutter/material.dart';
import '../../models/cart.dart';
import '../../models/product.dart';
import '../../services/cashier/print.dart';
import '../../services/db/db_helper.dart';
import '../../widgets/Cashier/barcode.dart';
import '../../widgets/Cashier/cartlist.dart';
import '../../widgets/Cashier/payment_controller.dart';
import '../../widgets/Cashier/receipt_widget.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocus);
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _paidController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeSubmitted(String code) async {
    final query = code.trim();
    if (query.isEmpty) return;

    Map<String, dynamic>? productMap;

    // Try by barcode first (existing behavior)
    productMap = await DBHelper.instance.getProductByBarcode(query);

    // If not found by barcode, try search by name
    if (productMap == null) {
      // افترض وجود دالة ترجع List<Map<String, dynamic>>
      final List<Map<String, dynamic>>? matches = await DBHelper.instance.getProductsByName(query);

      if (matches == null || matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المنتج "$query" غير موجود')));
        _barcodeController.clear();
        FocusScope.of(context).requestFocus(_barcodeFocus);
        return;
      }

      if (matches.length == 1) {
        productMap = matches.first;
      } else {
        // أكثر من نتيجة: عرض BottomSheet للاختيار
        final selected = await showModalBottomSheet<Map<String, dynamic>?>(
          context: context,
          builder: (ctx) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text('اختر المنتج المطلوب (${matches.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = matches[i];
                        final name = m['name']?.toString() ?? 'بدون اسم';
                        final barcode = m['barcode']?.toString() ?? '';
                        final price = (m['sellingPrice'] != null) ? m['sellingPrice'].toString() : '';
                        return ListTile(
                          title: Text(name),
                          subtitle: Text('باركود: $barcode ${price.isNotEmpty ? '— سعر: $price' : ''}'),
                          onTap: () => Navigator.of(ctx).pop(m),
                        );
                      },
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                ],
              ),
            );
          },
        );

        if (selected == null) {
          _barcodeController.clear();
          FocusScope.of(context).requestFocus(_barcodeFocus);
          return;
        } else {
          productMap = selected;
        }
      }
    }

    final product = Product.fromMap(productMap);
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
      if (_cart.containsKey(pid)) _cart[pid]!.quantity += 1;
      else _cart[pid] = CartItem(product: product, quantity: 1);
    });

    _barcodeController.clear();
    FocusScope.of(context).requestFocus(_barcodeFocus);
  }

  double get _total => computeTotal(_cart);
  double get _paid => double.tryParse(_paidController.text.replaceAll(',', '')) ?? 0.0;

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

  Future<void> _saveSale({required bool requireFullPayment}) async {
    if (_cart.isEmpty) return;
    final total = _total;
    final paid = _paid;
    if (requireFullPayment && paid < total) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('العميل لم يدفع كامل المبلغ')));
      return;
    }

    setState(() => _saving = true);
    try {
      for (final entry in _cart.entries) {
        final cartItem = entry.value;
        final productMap = await DBHelper.instance.getProductByBarcode(cartItem.product.barcode);
        if (productMap == null) throw 'المنتج غير موجود';
        final productFresh = Product.fromMap(productMap);
        if (cartItem.quantity > productFresh.totalUnits) {
          throw 'لا توجد كمية كافية لـ ${productFresh.name}';
        }
      }

      final isCredit = paid < total;
      final changeAmount = paid >= total ? (paid - total) : 0.0;

      final saleId = await DBHelper.instance.createSale(
        total: total,
        cashierUsername: widget.cashierUsername,
        paidAmount: paid,
        changeAmount: changeAmount,
        isCredit: isCredit,
        isReturn: false,
        returnOfSaleId: null,
        returnNote: null,
      );

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

      if (paid >= total) {
        final change = paid - total;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الحفظ — الباقي: ${change.toStringAsFixed(2)}')));
      } else {
        final remaining = total - paid;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ الفاتورة كآجل — المتبقي: ${remaining.toStringAsFixed(2)}')));
      }

      // print via PrintService (captures the RepaintBoundary)
      await PrintService.captureAndPrint(_receiptKey);

      setState(() {
        _cart.clear();
        _paidController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ الفاتورة: $e')));
    } finally {
      setState(() => _saving = false);
      FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receiptWidth = 380.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('شاشة الكاشير'),
        actions: [
          IconButton(
            tooltip: 'الفواتير السابقة',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => PreviousSalesScreen(cashierUsername: widget.cashierUsername)));
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          BarcodeInput(
            controller: _barcodeController,
            focusNode: _barcodeFocus,
            onSubmitted: _onBarcodeSubmitted,
            onAddPressed: () => _onBarcodeSubmitted(_barcodeController.text),
          ),
          const SizedBox(height: 12),
          Expanded(child: CartList(cart: _cart, onChangeQty: _changeQuantity, onRemove: (pid) => setState(() => _cart.remove(pid)), onEditQty: _editQuantityDialog)),
          const SizedBox(height: 12),
          PaymentControls(
            paidController: _paidController,
            addQuickPaid: _addQuickPaid,
            setQuickPaid: _setQuickPaid,
            total: _total,
            saving: _saving,
            onPayAndSave: () => _saveSale(requireFullPayment: true),
            onSaveAsCredit: () => _saveSale(requireFullPayment: false),
          ),
          const SizedBox(height: 12),
          Offstage(
            offstage: true, // تغيير إلى false للتصحيح ورؤية الإيصال
            child: RepaintBoundary(
              key: _receiptKey,
              child: ReceiptWidget(cart: _cart, paid: _paid, cashierUsername: widget.cashierUsername, width: receiptWidth, useCairo: true),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
