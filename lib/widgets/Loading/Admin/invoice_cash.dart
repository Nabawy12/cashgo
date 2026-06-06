// lib/widgets/loading_shimmer.dart
import 'package:flutter/material.dart';
import 'package:cashgo/utils/colors.dart';

/// LoadingShimmer
/// ويدجت قابل لإعادة الاستخدام لعرض تأثير shimmer بسيط.
/// الاستخدام الافتراضي يعتمد على AppColors.bgCardColor و AppColors.mainColor
class LoadingShimmer extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Duration period;
  final Color baseColor;
  final Color highlightColor;
  final bool circular; // لو true يصبح شكل دائري (مثلاً لأفاتار)

  LoadingShimmer({
    Key? key,
    this.width,
    this.height,
    this.borderRadius,
    this.padding,
    this.period = const Duration(milliseconds: 1200),
    Color? baseColor,
    Color? highlightColor,
    this.circular = false,
  })  : baseColor = baseColor ?? AppColorsDark.bgCardColor,
        highlightColor =
            highlightColor ?? AppColorsDark.mainColor.withOpacity(0.8),
        super(key: key);

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant LoadingShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
      _controller
        ..stop()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  LinearGradient _buildGradient(double slide) {
    // نمرر الـ slide كـ transform بدل محاولة استدعاء transform على الغاديانت
    return LinearGradient(
      begin: Alignment(-1.0, -0.3),
      end: Alignment(1.0, 0.3),
      colors: [
        widget.baseColor,
        widget.highlightColor,
        widget.baseColor,
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: _SlidingGradientTransform(slide: slide),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = widget.borderRadius ??
        BorderRadius.circular(widget.circular ? 999 : 8.0);

    return Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // slide in range -1 .. 1
            final double slide = (_controller.value * 2) - 1;

            return ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // الخلفية الثابتة (base color)
                  Container(color: widget.baseColor),
                  // الشيمر كـ ShaderMask فوق الخلفية
                  ShaderMask(
                    shaderCallback: (rect) {
                      return _buildGradient(slide).createShader(rect);
                    },
                    blendMode: BlendMode.srcATop,
                    child: Container(
                      color: Colors.white.withOpacity(
                          1.0), // اللون هنا لا يهم لكون blendMode srcATop
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Helper: transforms gradient by translating it horizontally
class _SlidingGradientTransform extends GradientTransform {
  final double slide; // -1..1

  const _SlidingGradientTransform({required this.slide});

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    // move horizontally by fraction of width
    final double tx = bounds.width * slide;
    return Matrix4.translationValues(tx, 0.0, 0.0);
  }
}
