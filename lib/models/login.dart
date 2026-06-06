import 'package:intl/intl.dart';

class Session {
  static String? currentUsername;
  static String? currentRole;
  static String? currentToken;
  static String? currentDateTime;
  static String? endDateTime;

  static void updateDateTime() {
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy hh:mm a');
    currentDateTime = formatter.format(now);
  }

  static void updateDateTime_end() {
    final now = DateTime.now();
    final formatter = DateFormat('dd/MM/yyyy hh:mm a');
    endDateTime = formatter.format(now);
  }

  static bool invoice_log = false;
  static bool receive_from_suppliers = false;
  static bool pay_credit = false;
  static bool discount = false;
  static bool canViewCredit = false;
}
