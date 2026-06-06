import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../utils/colors.dart';
import '../../empty_state_card.dart';

/// Shimmer skeleton for the CartList you posted.
/// Shows [itemCount] shimmering cards to mimic the real list while loading.
class CartListShimmer extends StatelessWidget {
  final int itemCount;
  final double cardRadius;
  final EdgeInsetsGeometry padding;

  const CartListShimmer({
    Key? key,
    this.itemCount = 3,
    this.cardRadius = 15,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
  }) : super(key: key);

  Widget _shimmerBox(
      {double height = 12,
      double width = double.infinity,
      BorderRadius? borderRadius}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: AppColorsDark.bgCardColor,
        borderRadius: borderRadius ?? BorderRadius.circular(6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) {
      return const EmptyStateCard(
        icon: Icons.shopping_cart_outlined,
        title: 'السلة فارغة',
        message: 'ابدأ بإضافة منتجات إلى الفاتورة.',
      );
    }

    // Shimmer colors: adjust if you want lighter/darker look
    final base = AppColorsDark.bgCardColor;
    final highlight = AppColorsDark.mainColor;

    return ListView.builder(
      itemCount: 1,
      itemBuilder: (context, index) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: padding,
            child: Card(
              color: AppColorsDark.bgCardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(cardRadius),
                side: BorderSide(color: AppColorsDark.mainColor),
              ),
              elevation: 5,
              child: Shimmer.fromColors(
                baseColor: base,
                highlightColor: highlight,
                child: ListTile(
                  // Title area (product name skeleton)
                  title: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _shimmerBox(
                        height: 18,
                        width: MediaQuery.of(context).size.width * 0.5,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  // Subtitle area (price & available)
                  subtitle: Padding(
                    padding: const EdgeInsets.only(
                        bottom: 15, left: 15, right: 15, top: 15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _shimmerBox(
                        height: 14,
                        width: MediaQuery.of(context).size.width * 0.4,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  // Trailing: quantity controls + subtotal + delete icon (all skeleton)
                  trailing: SizedBox(
                    width: 260,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // minus button skeleton
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // qty box skeleton
                        _shimmerBox(
                            height: 34,
                            width: 48,
                            borderRadius: BorderRadius.circular(6)),
                        const SizedBox(width: 8),
                        // plus button skeleton
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // subtotal skeleton
                        _shimmerBox(
                            height: 16,
                            width: 56,
                            borderRadius: BorderRadius.circular(6)),
                        const SizedBox(width: 12),
                        // delete icon skeleton (small square)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
