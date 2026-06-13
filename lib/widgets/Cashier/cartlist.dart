import 'package:flutter/material.dart';

import '../../models/cart.dart';
import '../../utils/colors.dart';
import '../empty_state_card.dart';

typedef OnChangeQty = void Function(int productId, int newQty);
typedef OnRemove = void Function(int productId);
typedef OnEditQty = void Function(int productId);

class CartList extends StatelessWidget {
  final Map<int, CartItem> cart;
  final OnChangeQty onChangeQty;
  final OnRemove onRemove;
  final OnEditQty onEditQty;

  const CartList(
      {super.key,
      required this.cart,
      required this.onChangeQty,
      required this.onRemove,
      required this.onEditQty});

  @override
  Widget build(BuildContext context) {
    if (cart.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.shopping_cart_outlined,
        title: 'السلة فارغة',
        message: 'ابدأ بمسح باركود أو البحث باسم المنتج لإضافته إلى الفاتورة',
      );
    }
    return ListView.builder(
      itemCount: cart.length,
      itemBuilder: (context, index) {
        final entry = cart.entries.elementAt(index);
        final pid = entry.key;
        final item = entry.value;
        final available = (item.product.totalUnits - item.quantity)
            .clamp(0, item.product.totalUnits);
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Card(
              color: AppColorsDark.bgCardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: AppColorsDark.mainColor)),
              borderOnForeground: true,
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "المنتج: ${item.product.name}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          color: AppColorsDark.mainTextDark,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'سعر الوحدة: ${item.product.sellingPrice.toStringAsFixed(2)} | المتاح: $available',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          color: AppColorsDark.mainTextLight,
                          fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        IconButton(
                            onPressed: () =>
                                onChangeQty(pid, item.quantity - 1),
                            icon: Icon(
                              Icons.remove,
                              color: Theme.of(context).iconTheme.color,
                              size: 20,
                            )),
                        GestureDetector(
                            onTap: () => onEditQty(pid),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppColorsDark.mainColor
                                            .withOpacity(0.5))),
                                child: Text(
                                  item.quantity.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColorsDark.mainTextDark,
                                      fontSize: 17),
                                ))),
                        IconButton(
                          onPressed: () => onChangeQty(pid, item.quantity + 1),
                          icon: Icon(
                            Icons.add,
                            color: Theme.of(context).iconTheme.color,
                            size: 20,
                          ),
                        ),
                        Text(
                          item.subtotal.toStringAsFixed(2),
                          style: TextStyle(
                              fontSize: 15, color: AppColorsDark.mainTextDark),
                        ),
                        IconButton(
                          tooltip: "ازاله المنتج",
                          onPressed: () => onRemove(pid),
                          icon: Icon(
                            Icons.delete_forever,
                            size: 20,
                            color: Colors.red.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
