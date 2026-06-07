import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../services/Api/Admin/Products.dart';
import '../../services/db/db_helper.dart';
import '../../models/product.dart';

class ProcessReturnDialog extends StatefulWidget {
  final int originalSaleId;
  final List<Map<String, dynamic>>
      items; // items from getSaleItemsBySaleId (passed by caller)
  final String cashierUsername;
  final void Function() onDone; // notify parent to refresh

  const ProcessReturnDialog({
    super.key,
    required this.originalSaleId,
    required this.items,
    required this.cashierUsername,
    required this.onDone,
  });

  @override
  State<ProcessReturnDialog> createState() => _ProcessReturnDialogState();
}

class _ProcessReturnDialogState extends State<ProcessReturnDialog> {
  final TextEditingController _replacementBarcodeController =
      TextEditingController();
  bool _processing = false;
  bool _isExchange = false;

  // selected productId -> qtyToReturn
  final Map<int, int> _selectedQty = {};
  final Map<int, bool> _selected = {};

  // replacement productId -> qtyToAdd
  final Map<int, int> _replacementQty = {};
  // replacement product info stored with keys used later: 'selling_price' and 'total_units', 'name', 'barcode'
  final Map<int, Map<String, dynamic>> _replacementProducts = {};

  @override
  void initState() {
    super.initState();
    for (final it in widget.items) {
      final pid = ((it['product_id'] as num?)?.toInt() ??
          int.tryParse(it['product_id']?.toString() ?? '') ??
          0);
      _selected[pid] = false;
      final orig = _originalQty(pid);
      _selectedQty[pid] =
          orig > 0 ? 1 : 0; // default to 1 if original had stock
    }
  }

  @override
  void dispose() {
    _replacementBarcodeController.dispose();
    super.dispose();
  }

  // unified original quantity reader (handles qty, quantity, count)
  int _originalQty(int productId) {
    final found = widget.items.where((e) {
      final id = (e['product_id'] is num)
          ? (e['product_id'] as num).toInt()
          : (int.tryParse(e['product_id']?.toString() ?? '') ?? 0);
      return id == productId;
    });
    if (found.isEmpty) return 0;
    final it = found.first;
    return (it['qty'] as num?)?.toInt() ??
        (it['quantity'] as num?)?.toInt() ??
        (it['count'] as num?)?.toInt() ??
        (int.tryParse(it['qty']?.toString() ?? '') ??
            (int.tryParse(it['quantity']?.toString() ?? '') ?? 0));
  }

  // compute line total using the original unit price from the sale record
  double _lineTotal(int productId) {
    final found = widget.items.firstWhere((e) {
      final id = (e['product_id'] is num)
          ? (e['product_id'] as num).toInt()
          : (int.tryParse(e['product_id']?.toString() ?? '') ?? 0);
      return id == productId;
    }, orElse: () => <String, dynamic>{});
    if (found == null || (found is Map && found.isEmpty)) return 0.0;
    final price = (found['price'] as num?)?.toDouble() ??
        (found['selling_price'] as num?)?.toDouble() ??
        0.0;
    final qty = _selectedQty[productId] ?? 0;
    return price * qty;
  }

  double get _computedRefund {
    double sum = 0.0;
    for (final pid in _selected.keys) {
      if (_selected[pid] == true) {
        sum += _lineTotal(pid);
      }
    }
    return sum;
  }

  double get _replacementCost {
    double sum = 0.0;
    for (final pid in _replacementQty.keys) {
      final qty = _replacementQty[pid] ?? 0;
      final prod = _replacementProducts[pid];
      if (prod == null) continue;
      final price = (prod['selling_price'] as num?)?.toDouble() ?? 0.0;
      sum += price * qty;
    }
    return sum;
  }

  double get _netDiff => _replacementCost - _computedRefund;
  // positive => customer owes money; negative => cashier must refund

  void _toggleSelect(int pid) {
    setState(() {
      final cur = _selected[pid] ?? false;
      _selected[pid] = !cur;
      if (!cur) {
        final orig = _originalQty(pid);
        _selectedQty[pid] = orig > 0 ? 1 : 0;
      }
    });
  }

  void _incReturnQty(int pid) {
    final orig = _originalQty(pid);
    final cur = _selectedQty[pid] ?? 0;
    if (cur < orig) setState(() => _selectedQty[pid] = cur + 1);
  }

  void _decReturnQty(int pid) {
    final cur = _selectedQty[pid] ?? 0;
    if (cur > 1) setState(() => _selectedQty[pid] = cur - 1);
  }

  void _incReplacementQty(int pid) async {
    final prod = _replacementProducts[pid];
    if (prod == null) return;
    final available = (prod['total_units'] as num?)?.toInt() ?? 0;
    final cur = _replacementQty[pid] ?? 0;
    if (cur < available)
      setState(() => _replacementQty[pid] = cur + 1);
    else
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('المنتج نفذ من المخزن'),
        ),
      ));
  }

  void _decReplacementQty(int pid) {
    final cur = _replacementQty[pid] ?? 0;
    if (cur > 1) setState(() => _replacementQty[pid] = cur - 1);
  }

  /// Use ProductApi.getProductByBarcode (API lookup) instead of DB
  Future<void> _addReplacementByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return;

    try {
      final apiProduct = await ProductApi.getProductByBarcode(code);
      if (apiProduct == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('المنتج غير موجود'),
          ),
        ));
        _replacementBarcodeController.clear();
        return;
      }

      final product = Product.fromMap(apiProduct);
      final pid = product.id!;
      final available = product.totalUnits ?? 0;
      if (available <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('المنتج نفذ من المخزن'),
          ),
        ));
        _replacementBarcodeController.clear();
        return;
      }

      setState(() {
        _replacementProducts[pid] = {
          'id': pid,
          'name': product.name ?? '',
          'barcode': product.barcode ?? code,
          'selling_price': product.sellingPrice?.toDouble() ?? 0.0,
          'total_units': product.totalUnits ?? 0,
        };
        final cur = _replacementQty[pid] ?? 0;
        _replacementQty[pid] = (cur + 1) <= available ? (cur + 1) : available;
      });
      _replacementBarcodeController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('خطأ في جلب المنتج: $e'),
        ),
      ));
      _replacementBarcodeController.clear();
    }
  }

  // Update local meta for offline cash/credit totals.
  Future<void> _recordOfflineTotals(double amount, String paymentMethod) async {
    try {
      final meta = await Hive.openBox('meta');
      double cash = (meta.get('lastOfflineSale_cash') as num? ?? 0).toDouble();
      double credit =
          (meta.get('lastOfflineSale_credit') as num? ?? 0).toDouble();

      final pm = paymentMethod.toLowerCase();
      if (pm == 'cash') {
        cash += amount;
      } else if (pm == 'credit') {
        credit += amount;
      } else if (pm != 'wallet' && pm != 'card') {
        cash += amount;
      }

      await meta.put('lastOfflineSale_cash', cash);
      await meta.put('lastOfflineSale_credit', credit);
      await meta.put('lastOfflineSale', cash);
      debugPrint(
          '[ProcessReturn] recorded offline totals $amount via $paymentMethod -> cash=$cash credit=$credit totalDrawer=$cash');
    } catch (e, st) {
      debugPrint('[ProcessReturn] _recordOfflineTotals error: $e\n$st');
    }
  }

  Future<void> _process() async {
    final returnsChosen = _selected.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList();
    if (returnsChosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('اختر عنصر واحد على الأقل للمرتجع'),
        ),
      ));
      return;
    }
    if (_isExchange && _replacementQty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Directionality(
          textDirection: TextDirection.rtl,
          child: Text('أضف عناصر بديلة لعملية الاستبدال'),
        ),
      ));
      return;
    }

    setState(() => _processing = true);

    // تأكد أن اسم الكاشير (الذي يقوم بالعملية) موجود
    final String actorCashier = widget.cashierUsername.trim();
    if (actorCashier.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(
                'اسم الكاشير غير معروف. الرجاء تسجيل الدخول أو التحقق من حسابك.'),
          ),
        ));
        setState(() => _processing = false);
      }
      return;
    }

    try {
      // build return items using original sale unit prices and unified 'qty' key
      final List<Map<String, dynamic>> returnItems = [];
      double totalReturnValue = 0.0;
      for (final pid in returnsChosen) {
        final qty = _selectedQty[pid] ?? 0;
        if (qty <= 0) continue;
        final it = widget.items.firstWhere((e) {
          final id = (e['product_id'] is num)
              ? (e['product_id'] as num).toInt()
              : (int.tryParse(e['product_id']?.toString() ?? '') ?? 0);
          return id == pid;
        }, orElse: () => <String, dynamic>{});
        if (it.isEmpty) continue;
        final unitPrice = (it['price'] as num?)?.toDouble() ??
            (it['selling_price'] as num?)?.toDouble() ??
            0.0;
        final name = (it['product_name'] ?? it['name'] ?? '').toString();
        // use 'qty' key to match server expectations
        returnItems.add(
            {'product_id': pid, 'qty': qty, 'price': unitPrice, 'name': name});
        totalReturnValue += unitPrice * qty;
      }

      // build exchange items from replacementProducts
      final List<Map<String, dynamic>> exchangeItems = [];
      double totalExchangeCost = 0.0;
      for (final entry in _replacementQty.entries) {
        final pid = entry.key;
        final qty = entry.value;
        if (qty <= 0) continue;
        final prod = _replacementProducts[pid];
        if (prod == null) continue;
        final unitPrice = (prod['selling_price'] as num?)?.toDouble() ?? 0.0;
        final name = (prod['name'] ?? '').toString();
        exchangeItems.add(
            {'product_id': pid, 'qty': qty, 'price': unitPrice, 'name': name});
        totalExchangeCost += unitPrice * qty;
      }

      // compute net and decide refund/paid
      final double netRaw = totalExchangeCost - totalReturnValue;
      final double net = double.parse(netRaw.toStringAsFixed(2));
      final double refundAmount = net < 0 ? -net : 0.0;
      final double paidAmount = net > 0 ? net : 0.0;

      // determine paymentMethod: use 'cash' for payments, 'refund' when cashier returns money (server will interpret)
      final String paymentMethod =
          paidAmount > 0 ? 'cash' : (refundAmount > 0 ? 'refund' : 'cash');

      await DBHelper.instance.applyReturnExchangeToSale(
        saleId: widget.originalSaleId,
        returnsMap: {
          for (final it in returnItems)
            it['product_id'] as int: it['qty'] as int
        },
        additionsMap: {
          for (final it in exchangeItems)
            it['product_id'] as int: it['qty'] as int
        },
        paidDelta: paidAmount - refundAmount,
        note: _isExchange ? 'Exchange (local)' : 'Refund (local)',
      );

      final amountToRecord = paidAmount > 0 ? paidAmount : refundAmount;
      final pmForMeta = paymentMethod == 'refund' ? 'cash' : paymentMethod;
      await _recordOfflineTotals(amountToRecord, pmForMeta);

      widget.onDone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('تمت العملية بنجاح'),
          ),
        ));
        Navigator.pop(context, widget.originalSaleId);
      }
      return;
    } catch (e, st) {
      debugPrint('ProcessReturn error: $e\n$st');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text('فشل التطبيق: $e'),
          ),
        ));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _buildReplacementTile(int pid) {
    final prod = _replacementProducts[pid]!;
    final name = (prod['name'] ?? 'منتج').toString();
    final barcode = (prod['barcode'] ?? '').toString();
    final available = (prod['total_units'] as num?)?.toInt() ?? 0;
    final qty = _replacementQty[pid] ?? 0;

    return Card(
      color: AppColorsDark.bgCardColor,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(
              name,
              style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 15),
            )),
            const SizedBox(width: 8),
            Text(
              'متاح : $available',
              style: TextStyle(fontSize: 17, color: AppColorsDark.mainTextDark),
            ),
            const SizedBox(width: 8),
            IconButton(
                onPressed: () => _decReplacementQty(pid),
                icon: Icon(
                  Icons.remove_circle_outline,
                  color: Theme.of(context).iconTheme.color,
                )),
            Text(
              '$qty',
              style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 17),
            ),
            IconButton(
                onPressed: () => _incReplacementQty(pid),
                icon: Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(context).iconTheme.color,
                )),
            IconButton(
                onPressed: () => setState(() {
                      _replacementProducts.remove(pid);
                      _replacementQty.remove(pid);
                    }),
                icon: Icon(Icons.delete, color: Colors.red.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final refundedVal = _computedRefund;
    final addedVal = _replacementCost;
    final netVal = _netDiff;

    String resultMessage;
    String amountStr = (netVal.abs()).toStringAsFixed(2);
    if (netVal > 0.00001) {
      resultMessage = 'المشتري يدفع: $amountStr';
    } else if (netVal < -0.00001) {
      resultMessage = 'الكاشير يرجع للعميل: $amountStr';
    } else {
      resultMessage = 'لا يوجد فرق صافي (لا يوجد نقل نقدي)';
    }

    // prominent status widget to clearly show cashier what to do
    Widget paymentStatusWidget;
    if (netVal > 0.00001) {
      paymentStatusWidget = Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.12),
          border: Border.all(color: Colors.green, width: 1.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.attach_money, color: Colors.green),
            const SizedBox(width: 8),
            Text('المشتري يدفع: $amountStr',
                style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (netVal < -0.00001) {
      paymentStatusWidget = Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          border: Border.all(color: Colors.red, width: 1.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.reply, color: Colors.red),
            const SizedBox(width: 8),
            Text('الكاشير يرجع للعميل: $amountStr',
                style: TextStyle(
                    color: Colors.red[700],
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else {
      paymentStatusWidget = Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(resultMessage,
            style: TextStyle(color: AppColorsDark.mainTextDark)),
      );
    }

    return AlertDialog(
      backgroundColor: AppColorsDark.bgColor,
      title: Center(
        child: Text(
          'معالجة مرتجع / استبدال',
          style: TextStyle(fontSize: 17, color: AppColorsDark.mainTextDark),
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: SizedBox(
          width: double.maxFinite,
          height: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(
                      'استرجاع',
                      style: TextStyle(
                        fontSize: 17,
                        color: AppColorsDark.mainTextDark,
                      ),
                    ),
                    selected: !_isExchange,
                    onSelected: (v) {
                      if (!v) return;
                      setState(() {
                        _isExchange = false;
                        // clear any replacement items when switching back to simple return
                        _replacementProducts.clear();
                        _replacementQty.clear();
                      });
                    },
                    backgroundColor: AppColorsDark.bgCardColor,
                    selectedColor: AppColorsDark.bgCardColor,
                    checkmarkColor: AppColorsDark.mainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: !_isExchange
                            ? AppColorsDark.mainColor
                            : AppColorsDark.bgCardColor,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      'استبدال',
                      style: TextStyle(
                        fontSize: 17,
                        color: AppColorsDark.mainTextDark,
                      ),
                    ),
                    selected: _isExchange,
                    onSelected: (v) {
                      if (!v) return;
                      setState(() => _isExchange = true);
                    },
                    backgroundColor: AppColorsDark.bgCardColor,
                    selectedColor: AppColorsDark.bgCardColor,
                    checkmarkColor: AppColorsDark.mainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: _isExchange
                            ? AppColorsDark.mainColor
                            : AppColorsDark.bgCardColor,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    ' : النوع',
                    style: TextStyle(
                      fontSize: 17,
                      color: AppColorsDark.mainTextDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  ' : اختر العناصر التي سيتم إرجاعها والكمية',
                  style: TextStyle(
                      fontSize: 17, color: AppColorsDark.mainTextDark),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final it = widget.items[i];
                    final pid = (it['product_id'] as num).toInt();
                    final name = (it['product_name'] ?? 'منتج') as String;
                    final origQty = _originalQty(pid);
                    final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                    final selected = _selected[pid] ?? false;
                    final selQty = _selectedQty[pid] ?? 1;

                    return Card(
                      color: AppColorsDark.bgCardColor,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelect(pid),
                                    activeColor: AppColorsDark.mainColor,
                                    checkColor: Colors.white,
                                    fillColor: MaterialStateProperty
                                        .resolveWith<Color>((states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return AppColorsDark.mainColor;
                                      }
                                      return Colors.grey.withOpacity(0.1);
                                    })),
                                Expanded(
                                    child: Text(
                                  '$name',
                                  style: TextStyle(
                                      color: AppColorsDark.mainTextDark),
                                )),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${price.toStringAsFixed(2)}  : السعر',
                                      style: TextStyle(
                                        color: AppColorsDark.mainTextDark,
                                        fontSize: 17,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'مباع : $origQty',
                                      style: TextStyle(
                                        color: AppColorsDark.mainTextDark,
                                        fontSize: 17,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (selected)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                      onPressed: () => _decReturnQty(pid),
                                      icon: Icon(
                                        Icons.remove_circle_outline,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      )),
                                  Text(
                                    '$selQty',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark),
                                  ),
                                  IconButton(
                                      onPressed: () => _incReturnQty(pid),
                                      icon: Icon(
                                        Icons.add_circle_outline,
                                        color:
                                            Theme.of(context).iconTheme.color,
                                      )),
                                  Text(
                                    ' : كمية الإرجاع',
                                    style: TextStyle(
                                        color: AppColorsDark.mainTextDark),
                                  ),
                                ],
                              )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isExchange) ...[
                const SizedBox(height: 8),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'أضف عناصر بدل (امسح الباركود):',
                      style: TextStyle(color: AppColorsDark.mainTextDark),
                    )),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: CustomFormField(
                        controller: _replacementBarcodeController,
                        hint: 'امسح باركود البديل واضغط إضافة',
                        onFieldSubmitted: (v) => _addReplacementByBarcode(v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CustomButton(
                      text: 'أضف',
                      onPressed: () => _addReplacementByBarcode(
                          _replacementBarcodeController.text),
                      infinity: false,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_replacementProducts.isEmpty)
                  Text(
                    'لا توجد عناصر بديلة مضافة',
                    style: TextStyle(color: AppColorsDark.mainTextDark),
                  )
                else
                  SizedBox(
                      height: 120,
                      child: ListView(
                          children: _replacementProducts.keys
                              .map((pid) => _buildReplacementTile(pid))
                              .toList())),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: paymentStatusWidget,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: Text(
                  'اضغط تطبيق — النظام سيحدث الفاتورة والمخزون تلقائياً.',
                  style: TextStyle(
                      color: AppColorsDark.mainTextDark, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.bgCardColor,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.light
                      ? Colors.black
                      : Colors.white),
            )),
        ElevatedButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.bgCardColor,
            ),
            onPressed: _processing ? null : _process,
            child: _processing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    'تطبيق',
                    style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black
                            : Colors.white),
                  )),
      ],
    );
  }
}
