import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/db/db_helper.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({required this.product, required this.quantity});

  double get subtotal => product.sellingPrice * quantity;
}

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

  // عدّل اسم الطابعة حسب جهازك
  final String _printerQueueName = 'Printer_POS_80';

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
    final barcode = code.trim();
    if (barcode.isEmpty) return;

    final productMap = await DBHelper.instance.getProductByBarcode(barcode);

    if (productMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المنتج بالباركود $barcode غير موجود')));
      _barcodeController.clear();
      return;
    }

    final product = Product.fromMap(productMap);

    final available = product.totalUnits;
    final pid = product.id!;
    final alreadyInCart = _cart.containsKey(pid) ? _cart[pid]!.quantity : 0;

    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الكمية نفدت')));
      _barcodeController.clear();
      return;
    }

    if (alreadyInCart + 1 > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن إضافة أكثر من المتاح')));
      _barcodeController.clear();
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

  double get _total {
    double t = 0;
    for (final item in _cart.values) t += item.subtotal;
    return t;
  }

  double get _paid {
    final p = double.tryParse(_paidController.text.replaceAll(',', '')) ?? 0.0;
    return p;
  }

  double get _change => (_paid - _total);

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
      setState(() {
        _cart.remove(productId);
      });
    } else if (newQty > available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد كمية كافية')));
    } else {
      setState(() {
        _cart[productId]!.quantity = newQty;
      });
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
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'ادخل الكمية (قطع)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text) ?? current;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('موافق'),
          ),
        ],
      ),
    );

    if (res != null) {
      _changeQuantity(productId, res);
    }
  }


  Future<void> _printReceiptAsText({
    required int saleId,
    required double total,
    required double paid,
    required double change,
  }) async {
    try {
      final now = DateTime.now();
      final sb = StringBuffer();

      const left = '\x1b\x61\x00';
      const center = '\x1b\x61\x01';
      const right = '\x1b\x61\x02';
      const rle = '\u202B';
      const pdf = '\u202C';


      sb.writeln(center + '*** فاتورة بيع ***' + pdf);
      sb.writeln(''); // سطر فاضي يعمل مسافة
      sb.writeln(left + 'رقم الفاتورة: $saleId' + pdf);
      sb.writeln(''); // سطر فاضي يعمل مسافة
      sb.writeln(rle + 'الكاشير: ${widget.cashierUsername}' + pdf);
      sb.writeln(''); // سطر فاضي يعمل مسافة
      sb.writeln(rle + 'التاريخ: ${now.toLocal().toString().split('.').first}' + pdf);
      sb.writeln('----------------------------');

      for (final item in _cart.values) {
        final name = item.product.name.replaceAll('\n', ' ');
        final shortName = name.length > 18 ? name.substring(0, 18) + '...' : name;
        final qty = item.quantity;
        final price = item.product.sellingPrice.toStringAsFixed(2);
        final subtotal = item.subtotal.toStringAsFixed(2);
        sb.writeln(rle + '$shortName  $qty x $price = $subtotal' + pdf);
      }

      sb.writeln('----------------------------');
      sb.writeln(rle + 'الإجمالي: ${total.toStringAsFixed(2)}' + pdf);
      sb.writeln(''); // سطر فاضي يعمل مسافة
      sb.writeln(rle + 'المدفوع: ${paid.toStringAsFixed(2)}' + pdf);
      sb.writeln(''); // سطر فاضي يعمل مسافة
      sb.writeln(rle + (paid >= total ? 'الباقي: ${change.toStringAsFixed(2)}' : 'المتبقي: ${(total - paid).toStringAsFixed(2)}') + pdf);
      sb.writeln('');
      sb.writeln(rle + 'شكراً لزيارتكم' + pdf);
      sb.writeln('\n');

      final tmpDir = Directory.systemTemp;
      final utf8File = File('${tmpDir.path}/receipt_$saleId.utf8.txt');
      await utf8File.writeAsString(sb.toString(), encoding: utf8);

      final encodingsToTry = [
        'CP1256',
        'WINDOWS-1256',
        'CP864',
        'IBM864',
        'ISO-8859-6',
      ];

      Future<File?> _convertWithIconv(String targetEncoding) async {
        try {
          final convPath = '${tmpDir.path}/receipt_${saleId}_$targetEncoding.bin';
          final convFile = File(convPath);
          final cmd = 'iconv -f UTF-8 -t $targetEncoding "${utf8File.path}" > "${convFile.path}"';
          final res = await Process.run('/bin/sh', ['-c', cmd]);
          if (res.exitCode == 0) {
            return convFile;
          } else {
            debugPrint('iconv failed for $targetEncoding: ${res.stderr}');
            return null;
          }
        } catch (e) {
          debugPrint('iconv exception for $targetEncoding: $e');
          return null;
        }
      }

      File? converted;
      for (final enc in encodingsToTry) {
        converted = await _convertWithIconv(enc);
        if (converted != null && await converted.exists()) {
          debugPrint('Converted to $enc at ${converted.path}');
          break;
        }
      }

      if (converted == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم أتمكن من تحويل الترميز. تأكد أن `iconv` متوفر')));
        final resUtf = await Process.run('lp', ['-d', _printerQueueName, utf8File.path]);
        if (resUtf.exitCode == 0) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الفاتورة (UTF-8) — إن ظهرت غريبة فالطابعة لا تدعم UTF-8.')));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إرسال الملف (UTF-8): ${resUtf.stderr}')));
        }
        return;
      }

      try {
        final cutFeed = <int>[
          0x1B, 0x64, 0x01,
          0x1D, 0x56, 0x00,
        ];
        final convBytes = await converted.readAsBytes();
        final finalBytes = <int>[];
        finalBytes.addAll(convBytes);
        finalBytes.addAll(cutFeed);
        final finalFile = File('${tmpDir.path}/receipt_${saleId}_toPrint.bin');
        await finalFile.writeAsBytes(finalBytes);
        final result = await Process.run('lp', ['-d', _printerQueueName, '-o', 'raw', finalFile.path]);
        if (result.exitCode == 0) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الفاتورة للطباعة (بعد تحويل الترميز)')));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إرسال الملف المحوّل: ${result.stderr}')));
        }
        return;
      } catch (e) {
        debugPrint('خطأ أثناء إلحاق أو إرسال الملف المحوّل: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في التحويل/الإرسال: $e')));
        return;
      }
    } catch (e) {
      debugPrint('خطأ أثناء الطباعة كنص: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
    }
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

      // طباعة كنص RAW بشكل افتراضي (أكثر توافقًا مع طابعات الفواتير الحرارية)
      try {
        await _printReceiptAsText(
          saleId: saleId,
          total: total,
          paid: paid,
          change: changeAmount,
        );
      } catch (e) {
        debugPrint('فشل طباعة الفاتورة كنص RAW: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الطباعة: $e')));
      }

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

  Future<void> _openPreviousInvoices() async {
    final changedSaleId = await Navigator.push<int?>(
      context,
      MaterialPageRoute(
        builder: (_) => PreviousSalesScreen(
          cashierUsername: widget.cashierUsername,
          onReturnProcessed: (origSaleId, returnSaleId) {},
        ),
      ),
    );

    if (changedSaleId != null) {
      setState(() {
        _cart.clear();
        _paidController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تطبيق المرتجع/البَدْل (فاتورة #$changedSaleId). بدء فاتورة جديدة.')));
      FocusScope.of(context).requestFocus(_barcodeFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final paid = _paid;
    final canPayFully = paid >= total && total > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('شاشة الكاشير'),
        actions: [
          IconButton(
            tooltip: 'سجل الفواتير السابقة',
            icon: const Icon(Icons.history),
            onPressed: _openPreviousInvoices,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Barcode + Add
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,
                    decoration: const InputDecoration(
                      labelText: 'امسح الباركود أو اكتب واضغط Enter',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _onBarcodeSubmitted,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(onPressed: () => _onBarcodeSubmitted(_barcodeController.text), child: const Text('أضف')),
              ],
            ),

            const SizedBox(height: 12),

            // Cart list
            Expanded(
              child: _cart.isEmpty
                  ? const Center(child: Text('السلة فارغة'))
                  : ListView.builder(
                itemCount: _cart.length,
                itemBuilder: (context, index) {
                  final entry = _cart.entries.elementAt(index);
                  final pid = entry.key;
                  final item = entry.value;
                  final available = item.product.totalUnits;

                  return Card(
                    child: ListTile(
                      title: Text(item.product.name),
                      subtitle: Text('سعر الوحدة: ${item.product.sellingPrice.toStringAsFixed(2)} | المتاح: $available'),
                      trailing: SizedBox(
                        width: 260,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(onPressed: () => _changeQuantity(pid, item.quantity - 1), icon: const Icon(Icons.remove)),
                            GestureDetector(
                              onTap: () => _editQuantityDialog(pid),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.black26),
                                ),
                                child: Text(item.quantity.toString(), textAlign: TextAlign.center),
                              ),
                            ),
                            IconButton(onPressed: () => _changeQuantity(pid, item.quantity + 1), icon: const Icon(Icons.add)),
                            const SizedBox(width: 12),
                            Text(item.subtotal.toStringAsFixed(2)),
                            IconButton(
                              onPressed: () => setState(() => _cart.remove(pid)),
                              icon: const Icon(Icons.delete_forever),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Payment row
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي: ${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('عدد القطع: ${_cart.values.fold<int>(0, (p, n) => p + n.quantity)}', style: const TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _paidController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المدفوع',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Row(
                          children: [
                            ElevatedButton(onPressed: () => _setQuickPaid(20), child: const Text('20')),
                            const SizedBox(width: 6),
                            ElevatedButton(onPressed: () => _setQuickPaid(50), child: const Text('50')),
                            const SizedBox(width: 6),
                            ElevatedButton(onPressed: () => _setQuickPaid(100), child: const Text('100')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            ElevatedButton(onPressed: () => _addQuickPaid(10), child: const Text('+10')),
                            const SizedBox(width: 6),
                            ElevatedButton(onPressed: () => _addQuickPaid(20), child: const Text('+20')),
                          ],
                        )
                      ],
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (paid >= total)
                      Text('الباقي: ${_change.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.bold))
                    else
                      Text('المتبقي: ${(total - paid).toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: (canPayFully && !_saving) ? () => _saveSale(requireFullPayment: true) : null,
                          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payment),
                          label: const Text('دفع وحفظ'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: (!_saving && _cart.isNotEmpty) ? () => _saveSale(requireFullPayment: false) : null,
                          icon: !_saving ? const Icon(Icons.save) : const SizedBox.shrink(),
                          label: const Text('حفظ كآجل'),
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ملاحظات قصيرة:
// - زر "معاينة" الآن يعرض SupermarketReceipt (كصورة) للحفظ/الطباعة.
// - لا زال _showRawReceiptPreview متاحًا إذا أردت معاينة النص الثابت (RAW).
// - لحذف الاختبار لاحقًا: امسح زر المعاينة أو عدِّله حسب رغبتك.
// - تأكد أن اسم الطابعة صحيح وأن `lp` متوفر على الجهاز.

// -------------------- Widget: PreviousSalesScreen --------------------
class PreviousSalesScreen extends StatefulWidget {
  final String cashierUsername;
  final void Function(int originalSaleId, int returnSaleId)? onReturnProcessed;
  const PreviousSalesScreen({super.key, required this.cashierUsername, this.onReturnProcessed});

  @override
  State<PreviousSalesScreen> createState() => _PreviousSalesScreenState();
}

class _PreviousSalesScreenState extends State<PreviousSalesScreen> {
  bool loading = true;
  List<Map<String, dynamic>> sales = [];
  Map<int, List<Map<String, dynamic>>> saleItems = {};

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => loading = true);
    sales = await DBHelper.instance.getAllSales();
    setState(() {
      loading = false;
    });
  }

  Future<void> _ensureItems(int saleId) async {
    if (saleItems.containsKey(saleId)) return;
    final items = await DBHelper.instance.getSaleItemsBySaleId(saleId);
    saleItems[saleId] = items;
    setState(() {});
  }

  void _openSaleDetails(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num).toInt();
    await _ensureItems(saleId);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Text('فاتورة #$saleId'),
            const SizedBox(width: 8),
            if ((sale['is_return'] ?? 0) == 1) const Icon(Icons.cancel, color: Colors.red),
            if ((sale['return_note'] ?? '').toString().toLowerCase().contains('exchange')) const Icon(Icons.swap_horiz, color: Colors.green),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الإجمالي: ${(sale['total'] as num?)?.toDouble() ?? 0.0}'),
              Text('المدفوع: ${(sale['paid_amount'] as num?)?.toDouble() ?? 0.0}'),
              Text('الفكة: ${(sale['change_amount'] as num?)?.toDouble() ?? 0.0}'),
              const SizedBox(height: 8),
              const Text('العناصر:'),
              Builder(builder: (_) {
                final items = saleItems[saleId] ?? [];
                if (items.isEmpty) return const Text('لا توجد عناصر مسجلة لهذه الفاتورة');
                return SizedBox(
                  height: 150,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final name = (it['product_name'] ?? 'Product') as String;
                      final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      return ListTile(
                        title: Text(name),
                        subtitle: Text('الكمية: $qty × ${price.toStringAsFixed(2)}'),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final changed = await _openProcessReturnDialog(saleId);
              if (changed != null) {
                if (mounted) Navigator.pop(context, changed);
              }
            },
            child: const Text('معالجة مرتجع / بدل'),
          ),
        ],
      ),
    );
  }

  Future<int?> _openProcessReturnDialog(int originalSaleId) async {
    // ensure items loaded
    await _ensureItems(originalSaleId);
    final items = saleItems[originalSaleId] ?? [];
    // open dialog passing items & cashier username
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => ProcessReturnDialog(
        originalSaleId: originalSaleId,
        items: items,
        cashierUsername: widget.cashierUsername,
        onDone: () async {
          // refresh
          await _loadSales();
          await _ensureItems(originalSaleId);
        },
      ),
    );

    return result; // saleId or null
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفواتير السابقة'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: sales.length,
        itemBuilder: (context, idx) {
          final s = sales[idx];
          final saleId = (s['id'] as num).toInt();
          final total = (s['total'] as num?)?.toDouble() ?? 0.0;
          final paid = (s['paid_amount'] as num?)?.toDouble() ?? 0.0;
          final isReturn = (s['is_return'] ?? 0) == 1;
          final note = (s['return_note'] ?? '').toString();
          return Card(
            child: ListTile(
              onTap: () => _openSaleDetails(s),
              title: Row(
                children: [
                  Expanded(child: Text('#$saleId — ${s['date'] ?? ''}')),
                  if (isReturn) const Icon(Icons.cancel, color: Colors.red),
                  if (note.toLowerCase().contains('exchange')) const Icon(Icons.swap_horiz, color: Colors.green),
                ],
              ),
              subtitle: Text('الإجمالي: ${total.toStringAsFixed(2)} — المدفوع: ${paid.toStringAsFixed(2)}'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          );
        },
      ),
    );
  }
}

// -------------------- Dialog: ProcessReturnDialog (improved, AUTOMATIC calc, Arabic) --------------------
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

  Future<void> _addReplacementByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return;
    final prod = await DBHelper.instance.getProductByBarcode(code);
    if (prod == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الباكود غير موجود')));
      return;
    }
    final pid = (prod['id'] as num).toInt();
    final available = (prod['total_units'] as num?)?.toInt() ?? 0;
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('المنتج غير متوفر')));
      return;
    }

    setState(() {
      _replacementProducts[pid] = prod;
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
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(name)),
            Text('باركود: $barcode'),
            const SizedBox(width: 8),
            Text('متاح: $available'),
            const SizedBox(width: 8),
            IconButton(onPressed: () => _decReplacementQty(pid), icon: const Icon(Icons.remove_circle_outline)),
            Text('$qty'),
            IconButton(onPressed: () => _incReplacementQty(pid), icon: const Icon(Icons.add_circle_outline)),
            IconButton(onPressed: () => setState(() { _replacementProducts.remove(pid); _replacementQty.remove(pid); }), icon: const Icon(Icons.delete, color: Colors.red)),
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
      title: const Text('معالجة مرتجع / استبدال'),
      content: SizedBox(
        width: double.maxFinite,
        height: 560,
        child: Column(
          children: [
            Row(
              children: [
                const Text('النوع: '),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('استرجاع'), selected: !_isExchange, onSelected: (v) => setState(() => _isExchange = !v ? true : false)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('استبدال'), selected: _isExchange, onSelected: (v) => setState(() => _isExchange = v)),
                const SizedBox(width: 12),
                Expanded(child: Text(_isExchange ? '(اضف عناصر بدل بالاسكان)' : '(يحسب المرتجع تلقائياً)')),
              ],
            ),
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerLeft, child: Text('اختر العناصر التي سيتم إرجاعها والكمية:')),
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
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Checkbox(value: selected, onChanged: (_) => _toggleSelect(pid)),
                              Expanded(child: Text('$name')),
                              Text('مباع: $origQty'),
                              const SizedBox(width: 12),
                              Text('${price.toStringAsFixed(2)}'),
                            ],
                          ),
                          if (selected)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Text('كمية الإرجاع: '),
                                IconButton(onPressed: () => _decReturnQty(pid), icon: const Icon(Icons.remove_circle_outline)),
                                Text('$selQty'),
                                IconButton(onPressed: () => _incReturnQty(pid), icon: const Icon(Icons.add_circle_outline)),
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
              const Align(alignment: Alignment.centerLeft, child: Text('أضف عناصر بدل (امسح الباركود):')),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: TextField(controller: _replacementBarcodeController, decoration: const InputDecoration(hintText: 'امسح باركود البديل واضغط إضافة'), onSubmitted: (v) => _addReplacementByBarcode(v))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: () => _addReplacementByBarcode(_replacementBarcodeController.text), child: const Text('أضف')),
                ],
              ),
              const SizedBox(height: 8),
              if (_replacementProducts.isEmpty)
                const Text('لا توجد عناصر بديلة مضافة')
              else
                SizedBox(height: 120, child: ListView(children: _replacementProducts.keys.map((pid) => _buildReplacementTile(pid)).toList())),
            ],
            const SizedBox(height: 8),
            // computed values (Arabic, automatic)
            Align(alignment: Alignment.centerLeft, child: Text('قيمة المرتجع: ${refundedVal.toStringAsFixed(2)}')),
            Align(alignment: Alignment.centerLeft, child: Text('تكلفة البدائل: ${addedVal.toStringAsFixed(2)}')),
            Align(alignment: Alignment.centerLeft, child: Text('الفرق (بدل - مرتجع): ${netVal.toStringAsFixed(2)}')),
            const SizedBox(height: 6),
            // result message (Arabic, positive amounts)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(resultMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            const Text('اضغط تطبيق — النظام سيحدث الفاتورة والمخزون تلقائياً.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(onPressed: _processing ? null : _process, child: _processing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تطبيق')),
      ],
    );
  }
}

