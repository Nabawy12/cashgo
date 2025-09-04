import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';

class ProcessReturnDialog extends StatefulWidget {
  final int originalSaleId;
  final List<Map<String, dynamic>> items; // items from getSaleItemsBySaleId
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
  final Map<int, Map<String, dynamic>> _replacementProducts = {};

  @override
  void initState() {
    super.initState();
    for (final it in widget.items) {
      final pid = (it['product_id'] as num).toInt();
      _selected[pid] = false;
      _selectedQty[pid] = 1;
    }
  }

  @override
  void dispose() {
    _replacementBarcodeController.dispose();
    super.dispose();
  }

  int _originalQty(int productId) {
    final found = widget.items.where((e) => (e['product_id'] as num).toInt() == productId);
    if (found.isEmpty) return 0;
    final it = found.first;
    return (it['quantity'] as num?)?.toInt() ?? 0;
  }

  double _lineTotal(int productId) {
    final it = widget.items.firstWhere((e) => (e['product_id'] as num).toInt() == productId);
    final price = (it['price'] as num?)?.toDouble() ?? 0.0;
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
            title: Center(child: const Text('اختر المنتج',style: TextStyle(color: Colors.white),)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 0.5),
                itemBuilder: (context, i) {
                  final name = (products[i]['name'] ?? '').toString();
                  return ListTile(
                    title: Text(name,style: TextStyle(color: Colors.white,fontSize: 20),),
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
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('إلغاء',style: TextStyle(color: Colors.white),),
              ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _addReplacementByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return;

    // جيب كل المنتجات بالباركود (ممكن يرجع أكتر من صف)
    final productsList = await DBHelper.instance.getProductsByBarcodeList(code);

    if (productsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الباكود غير موجود')),
      );
      _replacementBarcodeController.clear();
      return;
    }

    Map<String, dynamic>? chosenMap;
    if (productsList.length == 1) {
      chosenMap = productsList.first;
    } else {
      // اعرض حوار اختيار (اسم المنتج فقط)
      chosenMap = await showProductChoiceDialog(context, productsList);
      if (chosenMap == null) {
        _replacementBarcodeController.clear();
        return;
      }
    }

    final pid = (chosenMap['id'] as num).toInt();
    final available = (chosenMap['total_units'] as num?)?.toInt() ?? 0;

    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المنتج غير متوفر')),
      );
      _replacementBarcodeController.clear();
      return;
    }

    setState(() {
      _replacementProducts[pid] = chosenMap!;
      final cur = _replacementQty[pid] ?? 0;
      _replacementQty[pid] = (cur + 1) <= available ? (cur + 1) : available;
    });

    _replacementBarcodeController.clear();
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
    try {
      // build maps
      final Map<int, int> returnsMap = {};
      for (final pid in returnsChosen) {
        returnsMap[pid] = _selectedQty[pid] ?? 0;
      }

      final Map<int, int> additionsMap = {};
      for (final entry in _replacementQty.entries) {
        final pid = entry.key;
        final qty = entry.value;
        if (qty > 0) additionsMap[pid] = qty;
      }

      // compute paidDelta: positive => customer paid extra, negative => cashier refunded
      // Use precise sign for DB, but UI shows abs()
      final net = _netDiff;
      double paidDelta = net; // net can be negative => means cashier refunds abs(net)
      // round to 2 decimals
      paidDelta = double.parse(paidDelta.toStringAsFixed(2));

      // call DBHelper to modify original sale
      await DBHelper.instance.applyReturnExchangeToSale(
        saleId: widget.originalSaleId,
        returnsMap: returnsMap,
        additionsMap: additionsMap,
        paidDelta: paidDelta,
        note: _isExchange ? 'Exchange (auto)' : 'Refund (auto)',
      );

      widget.onDone();

      // return saleId so caller (CashierScreen) can clear cart and show message
      if (mounted) Navigator.pop(context, widget.originalSaleId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التطبيق: $e')));
    } finally {
      setState(() => _processing = false);
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

    return AlertDialog(
      
      backgroundColor: AppColorsDark.bgColor,
      title: Align(
        alignment: Alignment.center,
        child: Expanded(
          child: const Text(
              'معالجة مرتجع / استبدال',
            style: TextStyle(
              fontSize: 17,
              color: Colors.white
            ),
          ),
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: SizedBox(
          width: double.maxFinite,
          height: 660,
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
                      if (!v) return; // لو هو بالفعل مختار، متعملش أي حاجة
                      setState(() => _isExchange = false);
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
                      if (!v) return; // لو هو بالفعل مختار، متعملش أي حاجة
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
                    final origQty = (it['quantity'] as num?)?.toInt() ?? 0;
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
              SizedBox(height: 10),
              Align(
                  alignment: Alignment.center,
                  child: Text(
                      'قيمة المرتجع: ${refundedVal.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17
                    ),
                  ),
              ),
              SizedBox(height: 10),
              Align(
                  alignment: Alignment.center,
                  child: Text(
                      'تكلفة البدائل: ${addedVal.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16
                    ),
                  )
              ),
              SizedBox(height: 10),
              Align(
                  alignment: Alignment.center,
                  child: Text(
                      'الفرق (بدل - مرتجع): ${netVal.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15
                    ),
                  )
              ),
              SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: Text(
                    resultMessage,
                  style: TextStyle(
                      color: Colors.white,
                    fontWeight: FontWeight.bold,
                      fontSize: 18,
                  ),
                ),
              ),
              SizedBox(height: 20),
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
            onPressed: _processing ? null : _process, child: _processing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) :
          const Text(
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