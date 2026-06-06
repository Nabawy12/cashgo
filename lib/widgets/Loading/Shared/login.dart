import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../utils/colors.dart';
// داخل ملف login_screen.dart أو ملف widgets منفصل

Widget _buildShimmerLine(
    {double height = 16, double widthFactor = 0.9, BorderRadius? radius}) {
  return FractionallySizedBox(
    widthFactor: widthFactor,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius ?? BorderRadius.circular(8),
      ),
    ),
  );
}

class LoginLoadingShimmer extends StatelessWidget {
  final Color? baseColor;
  final Color highlightColor;

  const LoginLoadingShimmer({
    Key? key,
    this.baseColor,
    this.highlightColor = AppColorsDark.mainColor, // lighter gray
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final base = baseColor ?? AppColorsDark.bgCardColor;
    final highlight = highlightColor;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // logo placeholder
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),

              // space
              const SizedBox(height: 12),

              // username field placeholder
              _buildShimmerLine(
                  height: 50,
                  widthFactor: 1.0,
                  radius: BorderRadius.circular(12)),
              const SizedBox(height: 12),

              // password field placeholder
              _buildShimmerLine(
                  height: 50,
                  widthFactor: 1.0,
                  radius: BorderRadius.circular(12)),
              const SizedBox(height: 10),

              // error line placeholder (small)
              _buildShimmerLine(
                  height: 14,
                  widthFactor: 0.6,
                  radius: BorderRadius.circular(8)),
              const SizedBox(height: 16),

              // button placeholder
              _buildShimmerLine(
                  height: 52,
                  widthFactor: 0.7,
                  radius: BorderRadius.circular(24)),
            ],
          ),
        ),
      ),
    );
  }
}
