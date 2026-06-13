// tool/seed_customers.dart
import 'package:flutter/widgets.dart';
import 'package:cashgo/services/db/db_helper.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await DBHelper.instance.database;

  for (int i = 1; i <= 1000; i++) {
    await DBHelper.instance.findOrCreateCustomer(
      phone: '010${i.toString().padLeft(8, '0')}',
      name: 'Test Customer $i',
    );
  }

  print('Done');
}