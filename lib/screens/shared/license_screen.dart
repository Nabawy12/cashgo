import 'package:cashgo/services/license_service.dart';
import 'package:cashgo/utils/colors.dart';
import 'package:flutter/material.dart';

class LicenseScreen extends StatefulWidget {
  static const routeName = '/license';

  final VoidCallback onActivated;

  const LicenseScreen({super.key, required this.onActivated});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await LicenseService.activate(_codeController.text);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _loading = false;
        _error = 'كود غير صحيح';
      });
      return;
    }

    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardColor =
        isLight ? Theme.of(context).cardColor : AppColorsDark.bgCardColor;
    final textColor = isLight ? Colors.black : Colors.white;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    color: cardColor,
                    elevation: 10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                      side: BorderSide(
                        color: AppColorsLight.mainColor.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              color: AppColorsLight.mainColor
                                  .withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_clock_outlined,
                              color: AppColorsLight.mainColor,
                              size: 38,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'انتهت صلاحية البرنامج، يرجى إدخال كود التفعيل',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _codeController,
                            enabled: !_loading,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.ltr,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'XXXX-XXXX-XXXX',
                              errorText: _error,
                              prefixIcon: const Icon(Icons.vpn_key_outlined),
                            ),
                            onSubmitted: (_) => _activate(),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _activate,
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'تفعيل',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
