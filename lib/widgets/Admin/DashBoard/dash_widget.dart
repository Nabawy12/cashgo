import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../utils/colors.dart';

class DashboardWidget extends StatelessWidget {
  final String title;
  final String image; // يمكن أن يكون asset path أو http/https link
  final VoidCallback? onTap; // اختياري

  const DashboardWidget({
    Key? key,
    required this.title,
    required this.image,
    this.onTap,
  }) : super(key: key);

  bool _isNetwork(String path) => path.startsWith('http://') || path.startsWith('https://');
  bool _isSvg(String path) => path.toLowerCase().endsWith('.svg');

  Widget _buildImage() {
    if (_isNetwork(image)) {
      if (_isSvg(image)) {
        return SvgPicture.network(
          image,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        );
      } else {
        return Image.network(
          image,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        );
      }
    } else {
      if (_isSvg(image)) {
        return SvgPicture.asset(
          image,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          color: AppColorsDark.mainColor.withOpacity(0.5),
        );
      } else {
        return Image.asset(
          image,
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColorsDark.mainColor, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildImage(),
                const SizedBox(height: 15),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
