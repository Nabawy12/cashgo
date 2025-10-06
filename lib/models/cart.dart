// Cart model utilities (CartItem + helpers)
import '../../models/product.dart';

class CartItem {
  final Product product;
  int quantity;
  CartItem({required this.product, required this.quantity});
  double get subtotal => product.sellingPrice * quantity;
}

double computeTotal(Map<int, CartItem> cart) {
  double t = 0;
  for (final item in cart.values) t += item.subtotal;
  return t;
}

int computeTotalQty(Map<int, CartItem> cart) {
  return cart.values.fold<int>(0, (prev, el) => prev + el.quantity);
}
