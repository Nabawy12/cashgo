import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../utils/colors.dart';

class DashboardWidget extends StatefulWidget {
  final String title;
  final String image;
  final Color color;
  final VoidCallback? onTap;

  const DashboardWidget({
    Key? key,
    required this.title,
    required this.image,
    required this.color,
    this.onTap,
  }) : super(key: key);

  @override
  State<DashboardWidget> createState() => _DashboardWidgetState();
}

class _DashboardWidgetState extends State<DashboardWidget> {
  double _scale = 1.0;

  bool _isNetwork(String path) =>
      path.startsWith('http://') || path.startsWith('https://');
  bool _isSvg(String path) => path.toLowerCase().endsWith('.svg');

  Widget _buildImage() {
    final size = 32.0;
    if (_isNetwork(widget.image)) {
      return _isSvg(widget.image)
          ? SvgPicture.network(widget.image,
          width: size, height: size, fit: BoxFit.contain)
          : Image.network(widget.image,
          width: size, height: size, fit: BoxFit.contain);
    } else {
      return _isSvg(widget.image)
          ? SvgPicture.asset(
        widget.image,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
      )
          : Image.asset(widget.image,
          width: size, height: size, fit: BoxFit.contain);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 130),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColorsDark.bgColor.withOpacity(0.6),
                  AppColorsDark.bgColor,
                ],
              ),
              border: Border.all(color: widget.color.withOpacity(0.35)),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withOpacity(0.15),
                  ),
                  child: _buildImage(),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: AppColorsDark.mainTextDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}