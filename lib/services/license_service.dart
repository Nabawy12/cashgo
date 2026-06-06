import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

class LicenseService {
  static const Duration activationDuration = Duration(minutes: 5);
  static const String _secret = 'CASHGO_SECRET_2025';
  static const String _boxName = 'meta';
  static const String _lastActivationTimeKey = 'lastActivationTime';
  static const String _licenseActivatedKey = 'licenseActivated';

  static Future<void> ensureStarted() async {
    final box = await _metaBox();
    if (box.get(_lastActivationTimeKey) == null) {
      await box.put(
          _lastActivationTimeKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  static Future<bool> isActive() async {
    if (await isPermanentlyActivated()) return true;

    await ensureStarted();
    final lastActivationTime = await _lastActivationTime();
    if (lastActivationTime == null) return false;
    return DateTime.now().difference(lastActivationTime) < activationDuration;
  }

  static Future<bool> isPermanentlyActivated() async {
    final box = await _metaBox();
    return box.get(_licenseActivatedKey) == true;
  }

  static Future<bool> activate(String code) async {
    final expectedCode = activationCodeForHostname(Platform.localHostname);
    if (_normalizeCode(code) != expectedCode) return false;

    final box = await _metaBox();
    await box.put(_licenseActivatedKey, true);
    await box.put(
        _lastActivationTimeKey, DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  static String activationCodeForHostname(String hostname) {
    final key = utf8.encode(_secret);
    final bytes = utf8.encode(hostname.trim());
    final digest = Hmac(sha256, key).convert(bytes).toString().toUpperCase();
    final rawCode = digest.substring(0, 12);
    return '${rawCode.substring(0, 4)}-${rawCode.substring(4, 8)}-${rawCode.substring(8, 12)}';
  }

  static Future<Box> _metaBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static Future<DateTime?> _lastActivationTime() async {
    final box = await _metaBox();
    final raw = box.get(_lastActivationTimeKey);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) {
      final asInt = int.tryParse(raw);
      if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.tryParse(raw);
    }
    return null;
  }

  static String _normalizeCode(String code) {
    final compact =
        code.trim().toUpperCase().replaceAll(RegExp(r'[^A-F0-9]'), '');
    if (compact.length < 12) return compact;
    final rawCode = compact.substring(0, 12);
    return '${rawCode.substring(0, 4)}-${rawCode.substring(4, 8)}-${rawCode.substring(8, 12)}';
  }
}
