// Copy of your PreviousSalesScreen with imports adjusted
import 'package:flutter/material.dart';
import '../../services/db/db_helper.dart';

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
              // open ProcessReturnDialog (import it where you place it)
              // final changed = await _openProcessReturnDialog(saleId);
              // if (changed != null) { if (mounted) Navigator.pop(context, changed); }
            },
            child: const Text('معالجة مرتجع / بدل'),
          ),
        ],
      ),
    );
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
