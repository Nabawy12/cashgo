import 'package:flutter/material.dart';

import '../../models/cart.dart';

typedef OnChangeQty = void Function(int productId, int newQty);
typedef OnRemove = void Function(int productId);
typedef OnEditQty = void Function(int productId);

class CartList extends StatelessWidget {
  final Map<int, CartItem> cart;
  final OnChangeQty onChangeQty;
  final OnRemove onRemove;
  final OnEditQty onEditQty;

  const CartList({super.key, required this.cart, required this.onChangeQty, required this.onRemove, required this.onEditQty});

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) return const Center(child: Text('السلة فارغة'));
    return ListView.builder(
      itemCount: cart.length,
      itemBuilder: (context, index) {
        final entry = cart.entries.elementAt(index);
        final pid = entry.key;
        final item = entry.value;
        final available = item.product.totalUnits;
        return Card(
          child: ListTile(
            title: Text(item.product.name),
            subtitle: Text('سعر الوحدة: ${item.product.sellingPrice.toStringAsFixed(2)} | المتاح: $available'),
            trailing: SizedBox(
              width: 260,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(onPressed: () => onChangeQty(pid, item.quantity - 1), icon: const Icon(Icons.remove)),
                GestureDetector(onTap: () => onEditQty(pid), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)), child: Text(item.quantity.toString(), textAlign: TextAlign.center))),
                IconButton(onPressed: () => onChangeQty(pid, item.quantity + 1), icon: const Icon(Icons.add)),
                const SizedBox(width: 12),
                Text(item.subtotal.toStringAsFixed(2)),
                IconButton(onPressed: () => onRemove(pid), icon: const Icon(Icons.delete_forever)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
