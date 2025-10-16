import 'package:flutter/material.dart';

import '../../models/cart.dart';
import '../../utils/colors.dart';

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
    if (cart.isEmpty) return const Center(child: Text(
        'السلة فارغة',
      style: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w400,
      ),
    ));
    return ListView.builder(
      itemCount: cart.length,
      itemBuilder: (context, index) {
        final entry = cart.entries.elementAt(index);
        final pid = entry.key;
        final item = entry.value;
        final available = item.product.totalUnits;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsetsGeometry.symmetric(vertical: 20),
            child: Card(
              color: AppColorsDark.bgCardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadiusGeometry.circular(15),
                side: BorderSide(
                  color: AppColorsDark.mainColor
                )
              ),
              borderOnForeground: true,
              elevation: 5,
              child: ListTile(
                title: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text(
                      "المنتج: ${item.product.name}",
                    style: TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      fontWeight: FontWeight.w500
                    ),
                  ),
                ),
                subtitle: Padding(
                  padding: EdgeInsetsGeometry.only(bottom: 10,left: 10,right: 10),
                  child: Text(
                      'سعر الوحدة: ${
                          item.product.sellingPrice.toStringAsFixed(2)
                      } | المتاح: $available',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400
                    ),
                  ),
                ),
                trailing: SizedBox(
                  width: 260,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                    IconButton(
                        onPressed: () => onChangeQty(pid, item.quantity - 1),
                        icon:  Icon(
                            Icons.remove,
                          color: Colors.white,
                          size: 20,
                        )
                    ),
                    GestureDetector(
                        onTap: () => onEditQty(pid),
                        child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColorsDark.mainColor.withOpacity(0.5))),
                            child: Text(
                                item.quantity.toString(), textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17
                              ),
                            )
                        )
                    ),
                    IconButton(
                        onPressed: () => onChangeQty(pid, item.quantity + 1),
                        icon: Icon(
                            Icons.add,
                          color: Colors.white,
                          size: 20,
                        ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                        item.subtotal.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white
                      ),
                    ),
                    IconButton(
                        tooltip: "ازاله المننج",
                        onPressed: () => onRemove(pid),
                        icon: Icon(
                            Icons.delete_forever,
                          size: 20,
                          color: Colors.red.withOpacity(0.8),
                        ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
