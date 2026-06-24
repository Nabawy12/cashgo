import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import '../../services/db/db_helper.dart';


class ActivationService {
  static const String _secretSalt = 'CashGo-Vape-Secret-2026-X9kP';

  static const int trialDays = 7;

  static const String _kDeviceId = 'device_id';
  static const String _kFirstRun = 'first_run_date';
  static const String _kActivated = 'is_activated';
  static const String _kActivationCode = 'activation_code_used';

  /// يرجع device_id الحالي، أو يولّد واحد جديد لو أول مرة.
  static Future<String> getOrCreateDeviceId() async {
    final existing = await DBHelper.instance.getAppSetting(_kDeviceId);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final newId = _generateDeviceId();
    await DBHelper.instance.setAppSetting(_kDeviceId, newId);
    return newId;
  }

  /// يولّد device id بصيغة قصيرة وسهلة القراءة/الكتابة تليفونيًا
  /// مثال: CG-7F3K-9XQ2
  static String _generateDeviceId() {
    final rnd = Random.secure();
    String block(int len) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // بدون حروف ملتبسة
      return List.generate(len, (_) => chars[rnd.nextInt(chars.length)])
          .join();
    }

    return 'CG-${block(4)}-${block(4)}';
  }

  /// يسجل أول تشغيل للتطبيق (يُنادى مرة واحدة بس فعليًا، باقي المرات هترجع
  /// القيمة المخزنة لأنها موجودة).
  static Future<DateTime> ensureFirstRunDate() async {
    final existing = await DBHelper.instance.getAppSetting(_kFirstRun);
    if (existing != null && existing.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(existing);
      if (parsed != null) return parsed;
    }
    final now = DateTime.now();
    await DBHelper.instance.setAppSetting(_kFirstRun, now.toIso8601String());
    return now;
  }

  static Future<bool> isActivated() async {
    final v = await DBHelper.instance.getAppSetting(_kActivated);
    return v == '1';
  }

  /// عدد الأيام المتبقية من الفترة التجريبية (0 لو خلصت)
  static Future<int> remainingTrialDays() async {
    final firstRun = await ensureFirstRunDate();
    final elapsed = DateTime.now().difference(firstRun).inDays;
    final remaining = trialDays - elapsed;
    return remaining < 0 ? 0 : remaining;
  }

  /// هل التطبيق مقفول دلوقتي؟ (انتهت الفترة ومفيش تفعيل)
  static Future<bool> isLocked() async {
    if (await isActivated()) return false;
    final remaining = await remainingTrialDays();
    return remaining <= 0;
  }

  /// المعادلة اللي بتحول device_id لكود تفعيل متوقع.
  /// لازم تكون نفسها بالظبط في سكريبت التوليد بتاعك.
  static String _expectedCodeFor(String deviceId) {
    final raw = '$deviceId::$_secretSalt';
    final hash = sha256.convert(utf8.encode(raw)).toString().toUpperCase();
    // ناخد 8 خانات من الهاش ونقسمها لمجموعتين سهلة الكتابة: XXXX-XXXX
    final shortCode = hash.substring(0, 8);
    return '${shortCode.substring(0, 4)}-${shortCode.substring(4, 8)}';
  }

  /// يتحقق من الكود اللي كتبه العميل. لو صحيح، يفعّل التطبيق محليًا.
  static Future<bool> tryActivate(String enteredCode) async {
    final deviceId = await getOrCreateDeviceId();
    final expected = _expectedCodeFor(deviceId);
    final normalizedEntered =
    enteredCode.trim().toUpperCase().replaceAll(' ', '');
    final normalizedExpected = expected.replaceAll(' ', '');

    if (normalizedEntered == normalizedExpected) {
      await DBHelper.instance.setAppSetting(_kActivated, '1');
      await DBHelper.instance.setAppSetting(_kActivationCode, normalizedEntered);
      return true;
    }
    return false;
  }
}
