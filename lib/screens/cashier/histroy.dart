// returndailog.dart
// A defensive, non-recursive implementation of ProcessReturnDialog
// Designed to be used either inside a dialog or as a full-screen route/page.

import 'package:flutter/material.dart';
import 'package:cashgo/utils/colors.dart';

class ProcessReturnDialog extends StatefulWidget {
  final int originalSaleId;
  final List<Map<String, dynamic>> items;
  final String cashierUsername;
  final FutureOr<void> Function()? onDone;

  const ProcessReturnDialog({
    Key? key,
    required this.originalSaleId,
    required this.items,
    required this.cashierUsername,
    this.onDone,
  }) : super(key: key);

  @override
  State<ProcessReturnDialog> createState() => _ProcessReturnDialogState();
}

class _ProcessReturnDialogState extends State<ProcessReturnDialog> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  // defensive: avoid building infinite loops
  int _buildCount = 0;

  // items that will be processed as returns/exchanges
  final List<Map<String, dynamic>> _selectedReturnItems = [];

  bool _processing = false;

  @override
  void initState() {
    super.initState();
    // nothing heavy in build; any async work should be done here
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  void _addByBarcode() {
    final code = _barcodeController.text.trim();
    if (code.isEmpty) {
      _showSnack('ادخل باركود');
      return;
    }

    // try to find product in provided items first
    final match = widget.items.firstWhere(
          (it) {
        final b = (it['barcode'] ?? it['code'] ?? '').toString();
        return b == code;
      },
      orElse: () => {},
    );

    if (match.isEmpty) {
      _showSnack('لم يتم العثور على منتج بهذا الباركود');
      return;
    }

    setState(() {
      // clone minimal fields so we don't mutate original
      _selectedReturnItems.add({
        'product_name': match['product_name'] ?? match['name'] ?? 'منتج',
        'barcode': match['barcode'] ?? match['code'] ?? code,
        'price': (match['price'] as num?)?.toDouble() ?? 0.0,
        'quantity': 1,
      });
      _barcodeController.clear();
      _barcodeFocus.requestFocus();
    });
  }

  double get _returnValue {
    double sum = 0.0;
    for (final it in _selectedReturnItems) {
      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
      sum += price * qty;
    }
    return sum;
  }

  void _removeReturnItem(int index) {
    setState(() => _selectedReturnItems.removeAt(index));
  }

  Future<void> _applyReturns() async {
    if (_selectedReturnItems.isEmpty) {
      _showSnack('لا توجد عناصر للمرتجع');
      return;
    }

    setState(() => _processing = true);
    try {
      // هنا عادةً تنفذ منطق تحديث قاعدة البيانات، سحب رصيد، إضافة فاتورة مرتجع...
      // سنضع try/catch لحماية من أي استثناء.

      await Future.delayed(const Duration(milliseconds: 300)); // محاكاة عمل async

      // استدعاء callback اذا وُجد
      if (widget.onDone != null) {
        await widget.onDone!();
      }

      // اغلق الواجهة مع إرجاع id (مثلاً رقم مرتجع جديد)
      if (mounted) Navigator.of(context).pop<int>(1);
    } catch (e, st) {
      debugPrint('Exception while applying returns: $e\n$st');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('خطأ أثناء المعالجة'),
            content: SingleChildScrollView(child: Text(e.toString())),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    if (_buildCount > 200) {
      // very defensive: if we see extreme rebuilds, show a clear widget
      debugPrint('⚠️ ProcessReturnDialog: excessive build calls ($_buildCount) — returning error view');
      return Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColorsDark.bgCardColor, borderRadius: BorderRadius.circular(8)),
          child: const Text('خطأ: إعادة بناء متكررة', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    // Main UI
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 800),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColorsDark.bgCardColor, borderRadius: BorderRadius.circular(8)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('معالجة مرتجع / بدل', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Summary
                  Row(
                    children: [
                      Expanded(child: Text('فاتورة: #\${widget.originalSaleId}', style: const TextStyle(color: Colors.white70))),
                      Text('الكاشير: \${widget.cashierUsername}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Barcode input + Add button
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _barcodeController,
                          focusNode: _barcodeFocus,
                          decoration: InputDecoration(
                            hintText: 'امسح باركود البديل أو اكتب و اضغط إضافة',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.black12,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (_) => _addByBarcode(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addByBarcode,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                        child: const Text('أضف'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // List of selected return items
                  Expanded(
                    child: _selectedReturnItems.isEmpty
                        ? Center(child: Text('لا توجد عناصر مضافة', style: TextStyle(color: Colors.white70)))
                        : SingleChildScrollView(
                      child: Column(
                        children: List.generate(_selectedReturnItems.length, (index) {
                          final it = _selectedReturnItems[index];
                          final name = it['product_name']?.toString() ?? 'منتج';
                          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                          final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                          return Card(
                            color: Colors.transparent,
                            child: ListTile(
                              title: Text(name, style: const TextStyle(color: Colors.white)),
                              subtitle: Text('الكمية: \$qty × \${price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                                  onPressed: () {
                                    setState(() {
                                      if (it['quantity'] is num && (it['quantity'] as num) > 1) {
                                        it['quantity'] = (it['quantity'] as num) - 1;
                                      }
                                    });
                                  },
                                ),
                                Text('\${it['quantity']}', style: const TextStyle(color: Colors.white)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                                  onPressed: () {
                                    setState(() {
                                      it['quantity'] = (it['quantity'] as num?)?.toInt() ?? 0 + 1;
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  onPressed: () => _removeReturnItem(index),
                                ),
                              ]),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Totals and actions
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('قيمة المرتجعات:', style: TextStyle(color: Colors.white70)),
                          Text(_returnValue.toStringAsFixed(2), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _processing ? null : () => Navigator.of(context).pop(),
                            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _processing ? null : _applyReturns,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                            child: _processing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تطبيق'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
