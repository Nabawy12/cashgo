import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool infinity;
  final bool isLoading;
  final Color color;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.infinity = true,
    this.isLoading = false,
    this.color = AppColorsDark.mainColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: infinity ? double.infinity : null,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
            elevation: 0.0,
          overlayColor: Colors.blueAccent.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: isLoading ? null : onPressed, // ✅ يوقف الضغط لو في لودينج
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: isLoading
              ? SizedBox(
            key: const ValueKey("loader"),
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
              : Text(
            text,
            key: const ValueKey("text"),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
