import 'dart:convert';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/Api/Admin/Products.dart';
import '../../models/product.dart';

class ProcessReturnDialog extends StatefulWidget {
  final int originalSaleId;
  final List<Map<String, dynamic>> items; // items from getSaleItemsBySaleId (passed by caller)
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
  final TextEditingController _replacementBarcodeController = TextEditingController();
  bool _processing = false;
  bool _isExchange = false;

  // selected productId -> qtyToReturn
  final Map<int, int> _selectedQty = {};
  final Map<int, bool> _selected = {};

  // replacement productId -> qtyToAdd
  final Map<int, int> _replacementQty = {};
  // replacement product info stored with keys used later: 'selling_price' and 'total_units', 'name', 'barcode'
  final Map<int, Map<String, dynamic>> _replacementProducts = {};

  static const String apiBase = 'https://nabawisolution.com/invoice_reciept.php';

  @override
  void initState() {
    super.initState();
    for (final it in widget.items) {
      final pid = ((it['product_id'] as num?)?.toInt() ?? int.tryParse(it['product_id']?.toString() ?? '') ?? 0);
      _selected[pid] = false;
      final orig = _originalQty(pid);
      _selectedQty[pid] = orig > 0 ? 1 : 0; // default to 1 if original had stock
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
    return (it['qty'] as num?)?.toInt()
        ?? (it['quantity'] as num?)?.toInt()
        ?? (it['count'] as num?)?.toInt()
        ?? (int.tryParse(it['qty']?.toString() ?? '') ?? (int.tryParse(it['quantity']?.toString() ?? '') ?? 0));
  }

  // compute line total using the original unit price from the sale record
  double _lineTotal(int productId) {
    final found = widget.items.firstWhere(
            (e) {
          final id = (e['product_id'] is num) ? (e['product_id'] as num).toInt() : (int.tryParse(e['product_id']?.toString() ?? '') ?? 0);
          return id == productId;
        },
        orElse: () => <String, dynamic>{});
    if (found == null || (found is Map && found.isEmpty)) return 0.0;
    final price = (found['price'] as num?)?.toDouble()
        ?? (found['selling_price'] as num?)?.toDouble()
        ?? 0.0;
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
    if (cur < available) setState(() => _replacementQty[pid] = cur + 1);
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كمية كافية للاستبدال')));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المنتج بالباركود $code غير موجود')));
        _replacementBarcodeController.clear();
        return;
      }

      final product = Product.fromMap(apiProduct);
      final pid = product.id!;
      final available = product.totalUnits ?? 0;
      if (available <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج غير متوفر')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في جلب المنتج: $e')));
      _replacementBarcodeController.clear();
    }
  }

  Future<void> _process() async {
    final returnsChosen = _selected.entries.where((e) => e.value == true).map((e) => e.key).toList();
    if (returnsChosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر عنصر واحد على الأقل للمرتجع')));
      return;
    }
    if (_isExchange && _replacementQty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف عناصر بديلة لعملية الاستبدال')));
      return;
    }

    setState(() => _processing = true);

    // تأكد أن اسم الكاشير (الذي يقوم بالعملية) موجود
    final String actorCashier = widget.cashierUsername.trim();
    if (actorCashier.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اسم الكاشير غير معروف. الرجاء تسجيل الدخول أو التحقق من حسابك.'))
        );
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
          final id = (e['product_id'] is num) ? (e['product_id'] as num).toInt() : (int.tryParse(e['product_id']?.toString() ?? '') ?? 0);
          return id == pid;
        }, orElse: () => <String, dynamic>{});
        if (it.isEmpty) continue;
        final unitPrice = (it['price'] as num?)?.toDouble() ?? (it['selling_price'] as num?)?.toDouble() ?? 0.0;
        final name = (it['product_name'] ?? it['name'] ?? '').toString();
        // use 'qty' key to match server expectations
        returnItems.add({'product_id': pid, 'qty': qty, 'price': unitPrice, 'name': name});
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
        exchangeItems.add({'product_id': pid, 'qty': qty, 'price': unitPrice, 'name': name});
        totalExchangeCost += unitPrice * qty;
      }

      // compute net and decide refund/paid
      final double netRaw = totalExchangeCost - totalReturnValue;
      final double net = double.parse(netRaw.toStringAsFixed(2));
      final double refundAmount = net < 0 ? -net : 0.0;
      final double paidAmount = net > 0 ? net : 0.0;

      // determine paymentMethod: use 'cash' for payments, 'refund' when cashier returns money (server will interpret)
      final String paymentMethod = paidAmount > 0 ? 'cash' : (refundAmount > 0 ? 'refund' : 'cash');

      final uri = Uri.parse(apiBase);

      final body = {
        'action': 'process_return',
        'original_invoice_id': widget.originalSaleId,
        'return_items': returnItems,
        'exchange_items': exchangeItems,
        'refund_amount': refundAmount,
        'paid': paidAmount,
        'paymentMethod': paymentMethod,
        // الأهم: هنا نضع اسم الكاشير الذي يقوم بالعملية
        'cashierUsername': actorCashier,
        'return_note': _isExchange ? 'Exchange (via app)' : 'Refund (via app)',
        'debug': false,
        'create_child': true,
      };

      debugPrint('[ProcessReturn] payload: ${jsonEncode(body)}');

      final resp = await http
          .post(uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        throw Exception('خطأ من الخادم ${resp.statusCode}: ${resp.body}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('استجابة غير متوقعة من الخادم: ${resp.body}');
      }
      if (decoded['success'] != true) {
        throw Exception(decoded['error'] ?? decoded['message'] ?? 'خطأ غير معروف من الخادم');
      }

      // notify parent to refresh and close dialog
      widget.onDone();

      String idShown = '';
      if (decoded.containsKey('child_record_id') && decoded['child_record_id'] != null) idShown = decoded['child_record_id'].toString();
      else if (decoded.containsKey('return_invoice_id') && decoded['return_invoice_id'] != null) idShown = decoded['return_invoice_id'].toString();
      else if (decoded.containsKey('updated_invoice_id') && decoded['updated_invoice_id'] != null) idShown = decoded['updated_invoice_id'].toString();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت العملية بنجاح${idShown.isNotEmpty ? ' — رقم: $idShown' : ''}')));
        Navigator.pop(context, widget.originalSaleId);
      }
    } catch (e, st) {
      debugPrint('ProcessReturn error: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التطبيق: $e')));
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
                child:
                Text(
                  name,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15
                  ),
                )
            ),
            const SizedBox(width: 8),
            Text(
              'متاح : $available',
              style: TextStyle(
                  fontSize: 17,
                  color: Colors.white
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
                onPressed: () => _decReplacementQty(pid),
                icon:Icon(
                  Icons.remove_circle_outline,color: Colors.white70,)
            ),
            Text(
              '$qty',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17
              ),
            ),
            IconButton(
                onPressed: () => _incReplacementQty(pid),
                icon:Icon(
                  Icons.add_circle_outline,
                  color: Colors.white70,
                )
            ),
            IconButton(
                onPressed: () => setState(() { _replacementProducts.remove(pid); _replacementQty.remove(pid); }),
                icon:Icon(
                    Icons.delete,
                    color: Colors.red.withOpacity(0.8)
                )
            ),
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
            Text('المشتري يدفع: $amountStr', style: TextStyle(color: Colors.green[700], fontSize: 18, fontWeight: FontWeight.bold)),
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
            Text('الكاشير يرجع للعميل: $amountStr', style: TextStyle(color: Colors.red[700], fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else {
      paymentStatusWidget = Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(resultMessage, style: TextStyle(color: Colors.white)),
      );
    }

    return AlertDialog(
      backgroundColor: AppColorsDark.bgColor,
      title: Center(
        child: const Text(
          'معالجة مرتجع / استبدال',
          style: TextStyle(
              fontSize: 17,
              color: Colors.white
          ),
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
                    label: const Text(
                      'استرجاع',
                      style: TextStyle(
                        fontSize: 17,
                        color: Colors.white,
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
                        color: !_isExchange ? AppColorsDark.mainColor : AppColorsDark.bgCardColor,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text(
                      'استبدال',
                      style: TextStyle(
                        fontSize: 17,
                        color: Colors.white,
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
                        color: _isExchange ? AppColorsDark.mainColor : AppColorsDark.bgCardColor,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    ' : النوع',
                    style: TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  ' : اختر العناصر التي سيتم إرجاعها والكمية',
                  style: TextStyle(
                      fontSize: 17,
                      color: Colors.white
                  ),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelect(pid),
                                    activeColor: AppColorsDark.mainColor,
                                    checkColor: Colors.white,
                                    fillColor: MaterialStateProperty.resolveWith<Color>((states) {
                                      if (states.contains(MaterialState.selected)) {
                                        return AppColorsDark.mainColor;
                                      }
                                      return Colors.grey.withOpacity(0.1);
                                    })
                                ),
                                Expanded(
                                    child: Text(
                                      '$name',
                                      style: TextStyle(
                                          color: Colors.white
                                      ),
                                    )
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${price.toStringAsFixed(2)}  : السعر',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'مباع : $origQty',
                                      style: const TextStyle(
                                        color: Colors.white,
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
                                      icon: const Icon(Icons.remove_circle_outline,
                                        color: Colors.white70,
                                      )
                                  ),
                                  Text(
                                    '$selQty',
                                    style: const TextStyle(
                                        color: Colors.white
                                    ),
                                  ),
                                  IconButton(
                                      onPressed: () => _incReturnQty(pid),
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        color: Colors.white70,
                                      )
                                  ),
                                  const Text(
                                    ' : كمية الإرجاع',
                                    style: TextStyle(
                                        color: Colors.white
                                    ),
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
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'أضف عناصر بدل (امسح الباركود):',
                      style: TextStyle(
                          color: Colors.white
                      ),
                    )
                ),
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
                      onPressed: () => _addReplacementByBarcode(_replacementBarcodeController.text),
                      infinity: false,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_replacementProducts.isEmpty)
                  const Text(
                    'لا توجد عناصر بديلة مضافة',
                    style: TextStyle(
                        color: Colors.white
                    ),
                  )
                else
                  SizedBox(height: 120, child: ListView(children: _replacementProducts.keys.map((pid) => _buildReplacementTile(pid)).toList())),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: paymentStatusWidget,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: const Text(
                  'اضغط تطبيق — النظام سيحدث الفاتورة والمخزون تلقائياً.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13
                  ),
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
            child:Text(
              'إلغاء',
              style: TextStyle(
                  color: Colors.white
              ),
            )
        ),
        ElevatedButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.bgCardColor,
            ),
            onPressed: _processing ? null : _process,
            child: _processing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text(
              'تطبيق',
              style: TextStyle(
                  color: Colors.white
              ),
            )
        ),
      ],
    );
  }
}
