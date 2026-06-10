import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  static Database? _database;

  DBHelper._init();

  static String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  static String _newSalt() {
    return sha256
        .convert(utf8.encode(DateTime.now().microsecondsSinceEpoch.toString()))
        .toString()
        .substring(0, 16);
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_system.db_v2.187');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      } catch (e) {
        print('sqflite_common_ffi init failed: $e');
      }
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 151,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureUnitsRemainderColumn(db);
        await _ensureSaleColumns(db);
        await _ensureSaleItemsPurchasePriceColumn(db);
        await _ensureProductDatesColumns(db);
        await _ensureExpirySeenColumn(db);
        await _ensureLowStockSeenColumn(db);
        await _ensurePurchaseReceiptsTable(db);
        await _ensurePurchaseReceiptsColumns(db);
        await _ensureCashDrawerTable(db);
        await _ensureIsCurrentUserColumn(db);
        await _ensureSalePaymentMethodColumn(db);
        await _ensureSaleCardTransferredColumn(db);
        await _ensureSaleDiscountColumns(db);
        await _ensureDrawerWithdrawnAmountColumn(db);
        await _ensureUserAuthColumns(db);
        await _migratePlaintextUsers(db);
        await _ensureCloseShiftsTable(db);
        await _ensureShiftSettingsTable(db);
        await _ensureAppSettingsTable(db);
        await _ensureShopExternalExpensesTable(db);
      },
      onOpen: (db) async {
        try {
          await _ensureUnitsRemainderColumn(db);
        } catch (_) {}
        try {
          await _ensureSaleColumns(db);
        } catch (_) {}
        try {
          await _ensureSaleItemsPurchasePriceColumn(db);
        } catch (_) {}
        try {
          await _ensureProductDatesColumns(db);
        } catch (_) {}
        try {
          await _ensureExpirySeenColumn(db);
        } catch (_) {}
        try {
          await _ensureLowStockSeenColumn(db);
        } catch (_) {}
        try {
          await _ensurePurchaseReceiptsTable(db);
        } catch (_) {}
        try {
          await _ensurePurchaseReceiptsColumns(db);
        } catch (_) {}
        try {
          await _ensureCashDrawerTable(db);
        } catch (_) {}

        try {
          await _ensureIsCurrentUserColumn(db);
        } catch (_) {}

        try {
          await _ensureSalePaymentMethodColumn(db);
        } catch (_) {}

        try {
          await _ensureSaleCardTransferredColumn(db);
        } catch (_) {}

        try {
          await _ensureSaleDiscountColumns(db);
        } catch (_) {}
        try {
          await _ensureProductDatesColumns(db);
        } catch (_) {}

        try {
          await _ensureDrawerWithdrawnAmountColumn(db);
        } catch (_) {}
        try {
          await _ensureUserAuthColumns(db);
        } catch (_) {}
        try {
          await _migratePlaintextUsers(db);
        } catch (_) {}
        try {
          await _ensureCloseShiftsTable(db);
        } catch (_) {}
        try {
          await _ensureShiftSettingsTable(db);
        } catch (_) {}
        try {
          await _ensureAppSettingsTable(db);
        } catch (_) {}
        try {
          await _ensureShopExternalExpensesTable(db);
        } catch (_) {}
      },
    );
  }

  Future _createDB(Database db, int version) async {
    // users
    await db.execute(
      """CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        can_view_credit INTEGER NOT NULL DEFAULT 0
      )""",
    );

    await db.execute(
      """CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )""",
    );

    await db.execute(
      """CREATE TABLE shop_external_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        expense_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )""",
    );

    // products
    await db.execute(
      """CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        name TEXT NOT NULL,
        purchase_price REAL NOT NULL,
        selling_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        units_in_carton INTEGER NOT NULL,
        units_remainder INTEGER NOT NULL DEFAULT 0,
        production_date TEXT,
        expiry_date TEXT,
        low_stock_seen INTEGER NOT NULL DEFAULT 0,
        expiry_seen INTEGER NOT NULL DEFAULT 0
      )""",
    );

// داخل _createDB -> CREATE TABLE sales ( ... )
    await db.execute(
      """CREATE TABLE sales (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    total REAL NOT NULL,
    date TEXT NOT NULL,
    cashier_username TEXT,
    paid_amount REAL NOT NULL DEFAULT 0,
    change_amount REAL NOT NULL DEFAULT 0,
    is_credit INTEGER NOT NULL DEFAULT 0,
    is_return INTEGER NOT NULL DEFAULT 0,
    return_of_sale_id INTEGER,
    return_note TEXT,
    customer_name TEXT,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    discount_type TEXT NOT NULL DEFAULT 'fixed',
    discount_value REAL NOT NULL DEFAULT 0,
    credit_paid_by TEXT,
    credit_paid_at TEXT,
    -- new columns to track drawer clearing
    drawer_withdrawn INTEGER NOT NULL DEFAULT 0,
    drawer_withdrawn_amount REAL NOT NULL DEFAULT 0
  )""",
    );

    // sale_items
    await db.execute(
      """CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        purchase_price_per_unit REAL NOT NULL DEFAULT 0,
        returned INTEGER NOT NULL DEFAULT 0,
        returned_quantity INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )""",
    );

    // sale_returns
    await db.execute(
      """CREATE TABLE sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        cashier_username TEXT,
        paid_delta REAL NOT NULL DEFAULT 0,
        refund_amount REAL NOT NULL DEFAULT 0,
        note TEXT
      )""",
    );

    // sale_return_items
    await db.execute(
      """CREATE TABLE sale_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        qty INTEGER NOT NULL,
        is_replacement INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL,
        FOREIGN KEY (return_id) REFERENCES sale_returns(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )""",
    );

    // purchase_receipts (log of supplier receipts) - includes payment tracking
    await db.execute(
      """CREATE TABLE purchase_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        product_name TEXT,
        barcode TEXT,
        received_by TEXT,
        cashier_username TEXT,
        cartons INTEGER NOT NULL DEFAULT 0,
        units INTEGER NOT NULL DEFAULT 0,
        units_in_carton INTEGER NOT NULL DEFAULT 1,
        purchase_price_per_carton REAL,
        purchase_price_per_unit REAL,
        payment_type TEXT NOT NULL DEFAULT 'cash',
        paid_amount REAL NOT NULL DEFAULT 0,
        due_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )""",
    );

    // default users
    await db.insert('users', {
      'username': 'admin',
      'password': '1234',
      'role': 'admin',
    });
    await db.insert('users', {
      'username': 'cashier',
      'password': '1234',
      'role': 'cashier',
    });
  }

  Future<void> _ensureUserAuthColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(users);");

    Future<void> addIfMissing(String name, String sql) async {
      if (!cols.any((c) => c['name'] == name)) {
        await db.execute(sql);
      }
    }

    await addIfMissing(
        'password_hash', 'ALTER TABLE users ADD COLUMN password_hash TEXT;');
    await addIfMissing('salt', 'ALTER TABLE users ADD COLUMN salt TEXT;');
    await addIfMissing(
        'permissions', 'ALTER TABLE users ADD COLUMN permissions TEXT;');
    await addIfMissing('can_view_credit',
        'ALTER TABLE users ADD COLUMN can_view_credit INTEGER NOT NULL DEFAULT 0;');
  }

  Future<void> _migratePlaintextUsers(Database db) async {
    await _ensureUserAuthColumns(db);
    final rows = await db.query('users');
    for (final row in rows) {
      final currentHash = (row['password_hash'] ?? '').toString();
      final password = (row['password'] ?? '').toString();
      if (currentHash.isNotEmpty ||
          password.isEmpty ||
          password == '__hashed__') continue;
      final salt = _newSalt();
      await db.update(
        'users',
        {
          'password_hash': _hashPassword(password, salt),
          'salt': salt,
          'password': '__hashed__',
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> _ensureCloseShiftsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS close_shifts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cashier_name TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        opening_balance REAL NOT NULL DEFAULT 0,
        total_sales REAL NOT NULL DEFAULT 0,
        cash_sales REAL NOT NULL DEFAULT 0,
        gross_sales REAL NOT NULL DEFAULT 0,
        returns_delta REAL NOT NULL DEFAULT 0,
        total_expenses REAL NOT NULL DEFAULT 0,
        cash_expenses REAL NOT NULL DEFAULT 0,
        net_profit REAL NOT NULL DEFAULT 0,
        closing_balance REAL NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    final cols = await db.rawQuery("PRAGMA table_info(close_shifts);");
    Future<void> addIfMissing(String name, String sql) async {
      if (!cols.any((c) => c['name'] == name)) {
        await db.execute(sql);
      }
    }

    await addIfMissing('opening_balance',
        'ALTER TABLE close_shifts ADD COLUMN opening_balance REAL NOT NULL DEFAULT 0;');
    await addIfMissing('total_sales',
        'ALTER TABLE close_shifts ADD COLUMN total_sales REAL NOT NULL DEFAULT 0;');
    await addIfMissing('cash_sales',
        'ALTER TABLE close_shifts ADD COLUMN cash_sales REAL NOT NULL DEFAULT 0;');
    await addIfMissing('gross_sales',
        'ALTER TABLE close_shifts ADD COLUMN gross_sales REAL NOT NULL DEFAULT 0;');
    await addIfMissing('returns_delta',
        'ALTER TABLE close_shifts ADD COLUMN returns_delta REAL NOT NULL DEFAULT 0;');
    await addIfMissing('total_expenses',
        'ALTER TABLE close_shifts ADD COLUMN total_expenses REAL NOT NULL DEFAULT 0;');
    await addIfMissing('cash_expenses',
        'ALTER TABLE close_shifts ADD COLUMN cash_expenses REAL NOT NULL DEFAULT 0;');
    await addIfMissing('net_profit',
        'ALTER TABLE close_shifts ADD COLUMN net_profit REAL NOT NULL DEFAULT 0;');
    await addIfMissing('closing_balance',
        'ALTER TABLE close_shifts ADD COLUMN closing_balance REAL NOT NULL DEFAULT 0;');
    await addIfMissing(
        'note', 'ALTER TABLE close_shifts ADD COLUMN note TEXT;');
  }

  Future<void> _ensureShiftSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shift_settings (
        key TEXT PRIMARY KEY,
        value REAL NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _ensureAppSettingsTable(Database db) async {
    await db.execute(
      """CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )""",
    );
  }

  Future<void> _ensureShopExternalExpensesTable(Database db) async {
    await db.execute(
      """CREATE TABLE IF NOT EXISTS shop_external_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        expense_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )""",
    );
  }

  // ----------------- migrations helpers (same as before) -----------------
  Future<void> _ensureUnitsRemainderColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final has = cols.any((c) => c['name'] == 'units_remainder');
    if (!has) {
      await db.execute(
          'ALTER TABLE products ADD COLUMN units_remainder INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'units_remainder': 0});
    }
  }

  Future<void> ensureUnitsRemainderColumn() async {
    final db = await instance.database;
    await _ensureUnitsRemainderColumn(db);
  }

  Future<void> _ensureSaleColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing('paid_amount',
        'ALTER TABLE sales ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0;');
    await addIfMissing('change_amount',
        'ALTER TABLE sales ADD COLUMN change_amount REAL NOT NULL DEFAULT 0;');
    await addIfMissing('is_credit',
        'ALTER TABLE sales ADD COLUMN is_credit INTEGER NOT NULL DEFAULT 0;');
    await addIfMissing('is_return',
        'ALTER TABLE sales ADD COLUMN is_return INTEGER NOT NULL DEFAULT 0;');
    await addIfMissing('return_of_sale_id',
        'ALTER TABLE sales ADD COLUMN return_of_sale_id INTEGER;');
    await addIfMissing(
        'return_note', "ALTER TABLE sales ADD COLUMN return_note TEXT;");
    // new: customer_name column
    await addIfMissing(
        'customer_name', "ALTER TABLE sales ADD COLUMN customer_name TEXT;");
    await addIfMissing(
        'credit_paid_by', "ALTER TABLE sales ADD COLUMN credit_paid_by TEXT;");
    await addIfMissing(
        'credit_paid_at', "ALTER TABLE sales ADD COLUMN credit_paid_at TEXT;");
  }

  Future<void> ensureSaleColumns() async {
    final db = await instance.database;
    await _ensureSaleColumns(db);
  }

  Future<void> _ensureSaleItemsPurchasePriceColumn(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(sale_items);');
    if (cols.isEmpty) return;
    final hasPurchasePrice =
        cols.any((c) => c['name'] == 'purchase_price_per_unit');
    if (!hasPurchasePrice) {
      await db.execute(
          'ALTER TABLE sale_items ADD COLUMN purchase_price_per_unit REAL NOT NULL DEFAULT 0;');
      await db.rawUpdate('''
        UPDATE sale_items
        SET purchase_price_per_unit = (
          SELECT CASE
            WHEN COALESCE(p.units_in_carton, 0) > 0
            THEN COALESCE(p.purchase_price, 0) / p.units_in_carton
            ELSE COALESCE(p.purchase_price, 0)
          END
          FROM products p WHERE p.id = sale_items.product_id
        )
        WHERE purchase_price_per_unit = 0
      ''');
      debugPrint(
          '[Migration] sale_items.purchase_price_per_unit added and backfilled');
    } else {
      debugPrint(
          '[Migration] sale_items.purchase_price_per_unit already exists');
    }
    final hasReturned = cols.any((c) => c['name'] == 'returned');
    if (!hasReturned) {
      await db.execute(
          'ALTER TABLE sale_items ADD COLUMN returned INTEGER NOT NULL DEFAULT 0;');
      debugPrint('[Migration] sale_items.returned added');
    }
    final hasReturnedQuantity =
        cols.any((c) => c['name'] == 'returned_quantity');
    if (!hasReturnedQuantity) {
      await db.execute(
          'ALTER TABLE sale_items ADD COLUMN returned_quantity INTEGER NOT NULL DEFAULT 0;');
      await db.rawUpdate('''
        UPDATE sale_items
        SET returned_quantity = quantity
        WHERE COALESCE(returned,0) = 1
          AND COALESCE(returned_quantity,0) = 0
      ''');
      debugPrint('[Migration] sale_items.returned_quantity added');
    }
  }

  Future<void> ensureSaleReturnsColumns() async {
    final db = await instance.database;
    await _ensureSaleReturnsColumns(db);
  }

  Future<void> _ensureSaleReturnsColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sale_returns);");
    if (cols.isEmpty) return;
    final hasRefundAmount = cols.any((c) => c['name'] == 'refund_amount');
    if (!hasRefundAmount) {
      await db.execute(
          'ALTER TABLE sale_returns ADD COLUMN refund_amount REAL NOT NULL DEFAULT 0;');
      await db.rawUpdate('''
        UPDATE sale_returns
        SET refund_amount = CASE
          WHEN COALESCE(paid_delta,0) < 0 THEN ABS(COALESCE(paid_delta,0))
          ELSE 0
        END
      ''');
    }
  }

  Future<void> _ensureProductDatesColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");

    if (!cols.any((c) => c['name'] == 'production_date')) {
      await db.execute('ALTER TABLE products ADD COLUMN production_date TEXT;');
    }

    if (!cols.any((c) => c['name'] == 'expiry_date')) {
      await db.execute('ALTER TABLE products ADD COLUMN expiry_date TEXT;');
    }
  }

  Future<void> ensureProductDatesColumns() async {
    final db = await instance.database;
    await _ensureProductDatesColumns(db);
  }

  Future<void> _ensureExpirySeenColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final hasColumn = cols.any((c) => c['name'] == 'expiry_seen');

    if (!hasColumn) {
      await db.execute(
          'ALTER TABLE products ADD COLUMN expiry_seen INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'expiry_seen': 0});
    }
  }

  Future<void> ensureExpirySeenColumn() async {
    final db = await instance.database;
    await _ensureExpirySeenColumn(db);
  }

  Future<void> _ensureLowStockSeenColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(products);");
    final hasColumn = cols.any((c) => c['name'] == 'low_stock_seen');

    if (!hasColumn) {
      await db.execute(
          'ALTER TABLE products ADD COLUMN low_stock_seen INTEGER NOT NULL DEFAULT 0;');
      await db.update('products', {'low_stock_seen': 0});
    }
  }

  Future<void> ensureLowStockSeenColumn() async {
    final db = await instance.database;
    await _ensureLowStockSeenColumn(db);
  }

  // Ensure purchase_receipts table exists (for migrations)
  Future<void> _ensurePurchaseReceiptsTable(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='purchase_receipts';");
    final exists = tables.isNotEmpty;
    if (!exists) {
      await db.execute(
        """CREATE TABLE purchase_receipts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER,
          product_name TEXT,
          barcode TEXT,
          received_by TEXT,
          cashier_username TEXT,
          cartons INTEGER NOT NULL DEFAULT 0,
          units INTEGER NOT NULL DEFAULT 0,
          units_in_carton INTEGER NOT NULL DEFAULT 1,
          purchase_price_per_carton REAL,
          purchase_price_per_unit REAL,
          payment_type TEXT NOT NULL DEFAULT 'cash',
          paid_amount REAL NOT NULL DEFAULT 0,
          due_amount REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          FOREIGN KEY(product_id) REFERENCES products(id)
        )""",
      );
    }
  }

  Future<void> ensurePurchaseReceiptsTable() async {
    final db = await instance.database;
    await _ensurePurchaseReceiptsTable(db);
  }

  // Ensure purchase_receipts columns (for older table versions)
  Future<void> _ensurePurchaseReceiptsColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(purchase_receipts);");
    if (cols.isEmpty) return; // table might not exist (handled elsewhere)

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing('payment_type',
        "ALTER TABLE purchase_receipts ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'cash';");
    await addIfMissing('paid_amount',
        "ALTER TABLE purchase_receipts ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0;");
    await addIfMissing('paid_cash',
        'ALTER TABLE purchase_receipts ADD COLUMN paid_cash REAL NOT NULL DEFAULT 0;');
    await addIfMissing('paid_wallet',
        'ALTER TABLE purchase_receipts ADD COLUMN paid_wallet REAL NOT NULL DEFAULT 0;');
    await addIfMissing('due_amount',
        "ALTER TABLE purchase_receipts ADD COLUMN due_amount REAL NOT NULL DEFAULT 0;");
    await addIfMissing('cashier_username',
        "ALTER TABLE purchase_receipts ADD COLUMN cashier_username TEXT;");
    await db.rawUpdate(
      '''
      UPDATE purchase_receipts
      SET cashier_username = received_by
      WHERE (cashier_username IS NULL OR TRIM(cashier_username) = '')
        AND received_by IS NOT NULL
        AND TRIM(received_by) != ''
      ''',
    );
  }

  Future<void> ensurePurchaseReceiptsColumns() async {
    final db = await instance.database;
    await _ensurePurchaseReceiptsColumns(db);
  }

  // ----------------- auth / CRUD / helpers (mostly same as previous) -----------------
  Future<Map<String, dynamic>?> login(String username, String password) async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    await _migratePlaintextUsers(db);
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (result.isNotEmpty) {
      final user = Map<String, dynamic>.from(result.first);
      final salt = (user['salt'] ?? '').toString();
      final hash = (user['password_hash'] ?? '').toString();
      final legacyPassword = (user['password'] ?? '').toString();
      final matchesHash =
          salt.isNotEmpty && hash == _hashPassword(password, salt);
      final matchesLegacy = legacyPassword.isNotEmpty &&
          legacyPassword != '__hashed__' &&
          legacyPassword == password;
      if (matchesHash || matchesLegacy) {
        if (matchesLegacy) {
          final newSalt = _newSalt();
          await db.update(
            'users',
            {
              'password_hash': _hashPassword(password, newSalt),
              'salt': newSalt,
              'password': '__hashed__',
            },
            where: 'id = ?',
            whereArgs: [user['id']],
          );
          user['password'] = '__hashed__';
        }
        return _normaliseUserRow(user);
      }
    }
    return null;
  }

  Future<int> changePassword(String username, String newPassword) async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    final salt = _newSalt();
    return await db.update(
      'users',
      {
        'password': '__hashed__',
        'password_hash': _hashPassword(newPassword, salt),
        'salt': salt,
      },
      where: 'username = ?',
      whereArgs: [username],
    );
  }

  Map<String, dynamic> _normaliseUserRow(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    out.remove('password_hash');
    out.remove('salt');
    out.remove('password');
    final rawPermissions = row['permissions'];
    final canViewCredit = (row['can_view_credit'] as num?)?.toInt() == 1 ||
        row['can_view_credit'] == true ||
        row['can_view_credit']?.toString() == '1';
    if (rawPermissions is String && rawPermissions.trim().isNotEmpty) {
      try {
        out['permissions'] = jsonDecode(rawPermissions);
      } catch (_) {
        out['permissions'] = rawPermissions;
      }
    } else {
      out['permissions'] = {
        'invoice_log': false,
        'receive_from_suppliers': false,
        'pay_credit': false,
        'discount': false,
      };
    }
    if (out['permissions'] is Map) {
      out['permissions'] = Map<String, dynamic>.from(out['permissions'])
        ..['can_view_credit'] = canViewCredit;
    }
    out['can_view_credit'] = canViewCredit ? 1 : 0;
    return out;
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    await _migratePlaintextUsers(db);
    final rows = await db.query('users', orderBy: 'role ASC, username ASC');
    return rows
        .map((row) => _normaliseUserRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<int> insertUser({
    required String username,
    required String password,
    String role = 'cashier',
    Map<String, dynamic>? permissions,
    bool canViewCredit = false,
  }) async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    final salt = _newSalt();
    return await db.insert('users', {
      'username': username,
      'password': '__hashed__',
      'password_hash': _hashPassword(password, salt),
      'salt': salt,
      'role': role,
      'permissions': jsonEncode(permissions ?? {}),
      'can_view_credit': canViewCredit ? 1 : 0,
    });
  }

  Future<int> updateUserLocal(
    int id, {
    String? username,
    String? password,
    String? role,
    Map<String, dynamic>? permissions,
    bool? canViewCredit,
  }) async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    final values = <String, dynamic>{};
    if (username != null && username.trim().isNotEmpty)
      values['username'] = username.trim();
    if (role != null && role.trim().isNotEmpty) values['role'] = role.trim();
    if (permissions != null) values['permissions'] = jsonEncode(permissions);
    if (canViewCredit != null) {
      values['can_view_credit'] = canViewCredit ? 1 : 0;
    }
    if (password != null && password.isNotEmpty) {
      final salt = _newSalt();
      values['password'] = '__hashed__';
      values['password_hash'] = _hashPassword(password, salt);
      values['salt'] = salt;
    }
    if (values.isEmpty) return 0;
    return await db.update('users', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteUserLocal(int id) async {
    final db = await instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    return await db.insert('products', {
      'barcode': product['barcode'] ?? '',
      'name': product['name'] ?? '',
      'purchase_price': (product['purchase_price'] ?? 0).toDouble(),
      'selling_price': (product['selling_price'] ?? 0).toDouble(),
      'units_in_carton': product['units_in_carton'] ?? 0,
      'quantity': product['quantity'] ?? 0,
      'units_remainder': product['units_remainder'] ?? 0,
      'production_date': product['production_date'] ?? '',
      'expiry_date': product['expiry_date'] ?? '',
      'low_stock_seen': product['low_stock_seen'] ?? 0,
      'expiry_seen': product['expiry_seen'] ?? 0,
    });
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    final db = await instance.database;
    final products = await db.query('products', orderBy: 'name');

    return products.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<int> updateProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {
        'barcode': product['barcode'],
        'name': product['name'],
        'purchase_price': product['purchase_price'],
        'selling_price': product['selling_price'],
        'units_in_carton': product['units_in_carton'],
        'quantity': product['quantity'],
        'units_remainder': product['units_remainder'] ?? 0,
        'production_date': product['production_date'],
        'expiry_date': product['expiry_date'],
      },
      where: 'id = ?',
      whereArgs: [product['id']],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    final saleRows = await db.query('sale_items',
        where: 'product_id = ?', whereArgs: [id], limit: 1);
    final returnRows = await db.query('sale_return_items',
        where: 'product_id = ?', whereArgs: [id], limit: 1);
    final purchaseRows = await db.query('purchase_receipts',
        where: 'product_id = ?', whereArgs: [id], limit: 1);
    if (saleRows.isNotEmpty ||
        returnRows.isNotEmpty ||
        purchaseRows.isNotEmpty) {
      throw 'لا يمكن حذف منتج له سجل مبيعات أو مشتريات. يمكن تعديل الكمية بدلاً من الحذف.';
    }
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getProductById(int id) async {
    final db = await instance.database;
    final res =
        await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (res.isEmpty) return null;
    final product = Map<String, dynamic>.from(res.first);
    final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
    final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
    final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    product['units_remainder'] = remainder;
    product['total_units'] = cartons * unitsInCarton + remainder;
    return product;
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final db = await instance.database;
    final res = await db.query('products',
        where: 'barcode = ?', whereArgs: [barcode], limit: 1);
    if (res.isNotEmpty) {
      final product = Map<String, dynamic>.from(res.first);
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
      return product;
    }
    return null;
  }

  // في DBHelper:
// يبحث باستخدام LIKE ويرجع قائمة منتجات مع حقل total_units محسوب
  Future<List<Map<String, dynamic>>> searchProductsByName(String q,
      {int limit = 50}) async {
    final db = await instance.database;
    final pattern = '%${q.replaceAll("'", "''")}%';
    final rows = await db.rawQuery(
      "SELECT * FROM products WHERE name LIKE ? COLLATE NOCASE OR barcode LIKE ? LIMIT ?",
      [pattern, pattern, limit],
    );

    // احسب total_units لكل نتيجة مثل getProductByBarcode
    final List<Map<String, dynamic>> results = [];
    for (final r in rows) {
      final product = Map<String, dynamic>.from(r);
      final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
      final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
      results.add(product);
    }
    return results;
  }

// يجلب منتج واحد مطابقًا تمامًا للاسم (limit = 1) ويحسب total_units
  Future<Map<String, dynamic>?> getProductByName(String name) async {
    final db = await instance.database;
    final res = await db.query('products',
        where: 'name = ?', whereArgs: [name], limit: 1);
    if (res.isNotEmpty) {
      final product = Map<String, dynamic>.from(res.first);
      final cartons = (product['quantity'] as num?)?.toInt() ?? 0;
      final unitsInCarton = (product['units_in_carton'] as num?)?.toInt() ?? 0;
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      product['units_remainder'] = remainder;
      product['total_units'] = cartons * unitsInCarton + remainder;
      return product;
    }
    return null;
  }

  // ----------------- sales & sale_items -----------------
  Future<int> createSale({
    required double total,
    required String cashierUsername,
    double paidAmount = 0.0,
    double changeAmount = 0.0,
    bool isCredit = false,
    bool isReturn = false,
    int? returnOfSaleId,
    String? returnNote,
    String? customerName,
    String paymentMethod = 'cash',
    String discountType = 'fixed', // 'fixed' | 'percent'
    double discountValue = 0.0,
  }) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();

    // حساب قيمة الخصم وتطبيقها على المجموع الممرّر
    double discountAmount = 0.0;
    if (discountType == 'percent') {
      discountAmount = total * (discountValue / 100.0);
    } else {
      discountAmount = discountValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > total) discountAmount = total;

    final finalTotal = (total - discountAmount);

    final id = await db.insert('sales', {
      'total': finalTotal,
      'date': now,
      'cashier_username': cashierUsername,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'is_credit': isCredit ? 1 : 0,
      'is_return': isReturn ? 1 : 0,
      'return_of_sale_id': returnOfSaleId,
      'return_note': returnNote ?? '',
      'customer_name': customerName ?? '',
      'payment_method': paymentMethod,
      'discount_type': discountType,
      'discount_value': discountValue,
    });
    return id;
  }

  Future<int> insertSaleItem({
    required int saleId,
    required int productId,
    required int quantity,
    required double price,
    double purchasePricePerUnit = 0.0,
  }) async {
    final db = await instance.database;
    await _ensureSaleItemsPurchasePriceColumn(db);
    double unitCost = purchasePricePerUnit;
    if (unitCost <= 0) {
      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final product = rows.first;
        final purchasePricePerCarton =
            (product['purchase_price'] as num?)?.toDouble() ?? 0.0;
        final unitsInCarton =
            (product['units_in_carton'] as num?)?.toInt() ?? 1;
        final uic = unitsInCarton > 0 ? unitsInCarton : 1;
        unitCost = purchasePricePerCarton / uic;
      }
    }
    return await db.insert('sale_items', {
      'sale_id': saleId,
      'product_id': productId,
      'quantity': quantity,
      'price': price,
      'purchase_price_per_unit': unitCost,
      'returned': 0,
      'returned_quantity': 0,
    });
  }

  Future<int> createSaleWithItems({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double total,
    required double paid,
    required String cashierUsername,
    required String paymentMethod,
    bool requireFullPayment = false,
    String? customerName,
    String discountType = 'fixed',
    double discountValue = 0.0,
  }) async {
    final db = await instance.database;
    await _ensureSaleItemsPurchasePriceColumn(db);
    return await db.transaction<int>((txn) async {
      final change = paid >= total ? paid - total : 0.0;
      final saleId = await txn.insert('sales', {
        'total': total,
        'date': DateTime.now().toIso8601String(),
        'cashier_username': cashierUsername,
        'paid_amount': paid,
        'change_amount': change,
        'is_credit': paymentMethod == 'credit' ? 1 : 0,
        'is_return': 0,
        'return_of_sale_id': null,
        'return_note': '',
        'customer_name': customerName ?? '',
        'payment_method': paymentMethod,
        'discount_type': discountType,
        'discount_value': discountValue,
      });

      for (final item in items) {
        final productId = (item['product_id'] as num?)?.toInt() ??
            int.tryParse(item['product_id']?.toString() ?? '') ??
            0;
        final qty = (item['qty'] as num?)?.toInt() ??
            (item['quantity'] as num?)?.toInt() ??
            int.tryParse(item['qty']?.toString() ?? '') ??
            0;
        final price = (item['price'] as num?)?.toDouble() ??
            double.tryParse(item['price']?.toString() ?? '') ??
            0.0;
        if (productId <= 0 || qty <= 0) continue;
        final rows = await txn.query('products',
            where: 'id = ?', whereArgs: [productId], limit: 1);
        final product = rows.isNotEmpty ? rows.first : <String, Object?>{};
        final unitsInCarton =
            (product['units_in_carton'] as num?)?.toInt() ?? 1;
        final purchasePricePerCarton =
            (product['purchase_price'] as num?)?.toDouble() ?? 0.0;
        final uic = unitsInCarton > 0 ? unitsInCarton : 1;
        final purchasePricePerUnit = purchasePricePerCarton / uic;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': productId,
          'quantity': qty,
          'price': price,
          'purchase_price_per_unit': purchasePricePerUnit,
          'returned': 0,
          'returned_quantity': 0,
        });

        if (rows.isEmpty) continue;
        final currentCartons = (product['quantity'] as num?)?.toInt() ?? 0;
        final currentRemainder =
            (product['units_remainder'] as num?)?.toInt() ?? 0;
        final currentUnits = currentCartons * unitsInCarton + currentRemainder;
        final remaining = (currentUnits - qty).clamp(0, currentUnits);
        await txn.update(
          'products',
          {
            'quantity': unitsInCarton > 0 ? remaining ~/ unitsInCarton : 0,
            'units_remainder':
                unitsInCarton > 0 ? remaining % unitsInCarton : remaining,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
      }

      return saleId;
    });
  }

  Future<int> reduceProductStockByUnits(int productId, int unitsSold) async {
    if (unitsSold <= 0) return 0;
    final db = await instance.database;
    final res = await db.query('products',
        where: 'id = ?', whereArgs: [productId], limit: 1);
    if (res.isEmpty) return 0;
    final product = Map<String, dynamic>.from(res.first);

    final unitsInCarton = (product['units_in_carton'] as num).toInt();
    final currentCartons = (product['quantity'] as num).toInt();
    final currentRemainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    final currentTotalUnits = currentCartons * unitsInCarton + currentRemainder;

    final remainingUnits =
        (currentTotalUnits - unitsSold).clamp(0, currentTotalUnits);

    final newCartons =
        unitsInCarton > 0 ? (remainingUnits ~/ unitsInCarton) : 0;
    final newRemainder =
        unitsInCarton > 0 ? (remainingUnits % unitsInCarton) : remainingUnits;

    return await db.update(
      'products',
      {
        'quantity': newCartons,
        'units_remainder': newRemainder,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> increaseProductStockByUnits(int productId, int unitsToAdd) async {
    if (unitsToAdd <= 0) return 0;
    final db = await instance.database;
    final res = await db.query('products',
        where: 'id = ?', whereArgs: [productId], limit: 1);
    if (res.isEmpty) return 0;
    final product = Map<String, dynamic>.from(res.first);

    final unitsInCarton = (product['units_in_carton'] as num).toInt();
    final currentCartons = (product['quantity'] as num).toInt();
    final currentRemainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
    final currentTotalUnits = currentCartons * unitsInCarton + currentRemainder;

    final newTotalUnits = currentTotalUnits + unitsToAdd;

    final newCartons = unitsInCarton > 0 ? (newTotalUnits ~/ unitsInCarton) : 0;
    final newRemainder =
        unitsInCarton > 0 ? (newTotalUnits % unitsInCarton) : newTotalUnits;

    return await db.update(
      'products',
      {
        'quantity': newCartons,
        'units_remainder': newRemainder,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  double calculateTotalProfit({
    required double cartonPurchasePrice,
    required double unitSellingPrice,
    required int unitsInCarton,
    required int cartonsQuantity,
  }) {
    double totalSelling = unitSellingPrice * unitsInCarton * cartonsQuantity;
    double totalPurchase = cartonPurchasePrice * cartonsQuantity;
    return totalSelling - totalPurchase;
  }

  Future<int> getLowStockUnseenCount() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE (quantity * units_in_carton + units_remainder) < ? AND COALESCE(low_stock_seen, 0) = 0',
      [5],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getLowStockUnseenProducts() async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT *, COALESCE(low_stock_seen,0) as low_stock_seen, (quantity * units_in_carton + units_remainder) as total_units FROM products WHERE (quantity * units_in_carton + units_remainder) < ? AND COALESCE(low_stock_seen, 0) = 0 ORDER BY total_units ASC',
      [5],
    );
    return rows;
  }

  Future<int> setProductLowStockSeen(int productId, bool seen) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'low_stock_seen': seen ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> markAllLowStockSeen() async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'low_stock_seen': 1},
      where: '(quantity * units_in_carton + units_remainder) < ?',
      whereArgs: [5],
    );
  }

  Future<int> getExpiringUnseenCount({required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ? AND COALESCE(expiry_seen, 0) = 0',
      ['', thresholdStr],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getExpiringUnseenProducts(
      {required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    final rows = await db.rawQuery(
      'SELECT *, COALESCE(expiry_seen, 0) as expiry_seen FROM products WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ? AND COALESCE(expiry_seen, 0) = 0 ORDER BY date(expiry_date) ASC',
      ['', thresholdStr],
    );
    return rows;
  }

  Future<int> setProductExpirySeen(int productId, bool seen) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'expiry_seen': seen ? 1 : 0},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<int> markAllExpirySeen({required int daysThreshold}) async {
    final db = await instance.database;
    final now = DateTime.now();
    final thresholdDate = now.add(Duration(days: daysThreshold));
    final thresholdStr = thresholdDate.toIso8601String().split('T').first;

    return await db.rawUpdate(
      'UPDATE products SET expiry_seen = 1 WHERE expiry_date IS NOT NULL AND expiry_date != ? AND date(expiry_date) <= ?',
      ['', thresholdStr],
    );
  }

  // ----------------- sales listing and sale_items -----------------
  Future<List<Map<String, dynamic>>> getAllSales() async {
    final db = await instance.database;
    final rows = await db.query('sales', orderBy: 'date DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getSaleItemsBySaleId(int saleId) async {
    final db = await instance.database;
    await _ensureSaleItemsPurchasePriceColumn(db);
    final rows = await db.rawQuery(
      '''
    SELECT si.*, p.name as product_name, p.barcode as product_barcode
    FROM sale_items si
    LEFT JOIN products p ON p.id = si.product_id
    WHERE si.sale_id = ?
    ''',
      [saleId],
    );
    return rows;
  }

  // get sale_returns rows for a sale
  Future<List<Map<String, dynamic>>> getSaleReturnsBySaleId(int saleId) async {
    final db = await instance.database;
    final rows = await db.query('sale_returns',
        where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'date DESC');
    return rows;
  }

  // get sale_return_items for a sale (join with sale_returns)
  Future<List<Map<String, dynamic>>> getSaleReturnItemsForSale(
      int saleId) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT sri.*, sr.date as return_date, sr.paid_delta as paid_delta, sr.note as return_note,
             p.name as product_name, p.barcode as product_barcode
      FROM sale_return_items sri
      JOIN sale_returns sr ON sr.id = sri.return_id
      LEFT JOIN products p ON p.id = sri.product_id
      WHERE sr.sale_id = ?
      ''',
      [saleId],
    );
    return rows;
  }

  Future<double> getTotalForDate(String dateOnly) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      "SELECT SUM(total) as day_total FROM sales WHERE date LIKE ?",
      ['$dateOnly%'],
    );
    return (rows.isNotEmpty && rows.first['day_total'] != null)
        ? (rows.first['day_total'] as num).toDouble()
        : 0.0;
  }

  Future<int> markSaleAsReturn(int originalSaleId,
      {required int returnSaleId, String? note}) async {
    final db = await instance.database;
    return await db.update(
      'sales',
      {
        'is_return': 1,
        'return_of_sale_id': returnSaleId,
        'return_note': note ?? '',
      },
      where: 'id = ?',
      whereArgs: [originalSaleId],
    );
  }

  /// Apply return/exchange WITHOUT modifying the original sale rows.
  /// - We create a sale_returns row and sale_return_items (is_replacement = 0 for returned items,
  ///   is_replacement = 1 for replacements)
  /// - Adjust product stock accordingly (restore returned units, reduce replacement units)
  /// - We append return_note on the original sale (so UI knows there's a return),
  ///   but we DO NOT modify sale_items nor sales.total/paid_amount/change_amount.
  /// Apply return/exchange and MODIFY the original sale row and sale_items,
  /// while still logging the action in sale_returns / sale_return_items.
  Future<void> applyReturnExchangeToSale({
    required int saleId,
    required Map<int, int> returnsMap,
    required Map<int, int> additionsMap,
    required double paidDelta,
    required String note,
  }) async {
    final db = await instance.database;
    await _ensureSaleItemsPurchasePriceColumn(db);
    await _ensureSaleReturnsColumns(db);

    await db.transaction((txn) async {
      final saleRows = await txn.query('sales',
          where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw 'Original sale not found';
      final sale = saleRows.first;
      final oldNote = (sale['return_note'] ?? '').toString();
      final now = DateTime.now().toIso8601String();

      final returnRowId = await txn.insert('sale_returns', {
        'sale_id': saleId,
        'date': now,
        'cashier_username': sale['cashier_username'] ?? '',
        'paid_delta': paidDelta,
        'refund_amount': paidDelta < 0 ? paidDelta.abs() : 0.0,
        'note': note,
      });

      for (final entry in returnsMap.entries) {
        final pid = entry.key;
        final qtyReturn = entry.value;
        if (qtyReturn <= 0) continue;

        final itemRows = await txn.query(
          'sale_items',
          where:
              'sale_id = ? AND product_id = ? AND COALESCE(returned_quantity,0) < COALESCE(quantity,0)',
          whereArgs: [saleId, pid],
          limit: 1,
        );
        if (itemRows.isEmpty) {
          throw 'هذا المنتج تم استرجاعه بالفعل';
        }
        final saleItem = Map<String, dynamic>.from(itemRows.first);
        final soldQty = (saleItem['quantity'] as num?)?.toInt() ?? 0;
        final alreadyReturned =
            (saleItem['returned_quantity'] as num?)?.toInt() ?? 0;
        final availableToReturn = soldQty - alreadyReturned;
        if (qtyReturn > availableToReturn) {
          throw 'الكمية المطلوبة أكبر من الكمية المتاحة للمرتجع';
        }
        final prodRows = await txn.query('products',
            where: 'id = ?', whereArgs: [pid], limit: 1);
        if (prodRows.isEmpty) throw 'Product $pid not found in products table';
        final price = ((saleItem['price'] as num?)?.toDouble() ?? 0.0);

        await txn.insert('sale_return_items', {
          'return_id': returnRowId,
          'product_id': pid,
          'qty': qtyReturn,
          'is_replacement': 0,
          'price': price,
        });

        final saleItemId = (saleItem['id'] as num?)?.toInt();
        if (saleItemId != null) {
          final newReturnedQty = alreadyReturned + qtyReturn;
          final fullyReturned = newReturnedQty >= soldQty;
          await txn.update(
            'sale_items',
            {
              'returned_quantity': newReturnedQty,
              'returned': fullyReturned ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [saleItemId],
          );
          debugPrint(
              '[Return] updated sale_item id=$saleItemId product=$pid returnedQty=$newReturnedQty/$soldQty fullyReturned=$fullyReturned');
        }

        final prod = Map<String, dynamic>.from(prodRows.first);
        final unitsInCarton = (prod['units_in_carton'] as num).toInt();
        final currentCartons = (prod['quantity'] as num).toInt();
        final currentRemainder =
            (prod['units_remainder'] as num?)?.toInt() ?? 0;
        final newTotal =
            currentCartons * unitsInCarton + currentRemainder + qtyReturn;
        await txn.update(
            'products',
            {
              'quantity': unitsInCarton > 0 ? (newTotal ~/ unitsInCarton) : 0,
              'units_remainder':
                  unitsInCarton > 0 ? (newTotal % unitsInCarton) : newTotal,
            },
            where: 'id = ?',
            whereArgs: [pid]);
      }

      for (final entry in additionsMap.entries) {
        final pid = entry.key;
        final qtyAdd = entry.value;
        if (qtyAdd <= 0) continue;

        final prodRows = await txn.query('products',
            where: 'id = ?', whereArgs: [pid], limit: 1);
        if (prodRows.isEmpty) throw 'Replacement product $pid not found';
        final prod = Map<String, dynamic>.from(prodRows.first);
        final unitsInCarton = (prod['units_in_carton'] as num).toInt();
        final currentCartons = (prod['quantity'] as num).toInt();
        final currentRemainder =
            (prod['units_remainder'] as num?)?.toInt() ?? 0;
        final currentTotal = currentCartons * unitsInCarton + currentRemainder;
        if (qtyAdd > currentTotal)
          throw 'Not enough stock for replacement product ${prod['name']}';
        final price = (prod['selling_price'] as num?)?.toDouble() ?? 0.0;

        await txn.insert('sale_return_items', {
          'return_id': returnRowId,
          'product_id': pid,
          'qty': qtyAdd,
          'is_replacement': 1,
          'price': price,
        });

        final newTotal = currentTotal - qtyAdd;
        await txn.update(
            'products',
            {
              'quantity': unitsInCarton > 0 ? (newTotal ~/ unitsInCarton) : 0,
              'units_remainder':
                  unitsInCarton > 0 ? (newTotal % unitsInCarton) : newTotal,
            },
            where: 'id = ?',
            whereArgs: [pid]);
      }

      final combinedNote = (oldNote.isEmpty ? '' : '$oldNote | ') + note;
      await txn.update(
          'sales',
          {
            'return_note': combinedNote,
          },
          where: 'id = ?',
          whereArgs: [saleId]);
    });
  }

  Future<List<Map<String, dynamic>>> getProductsByName(String query) async {
    final db = await instance.database;
    final q = query.trim();
    if (q.isEmpty) return [];

    final like = '%$q%';
    final rows = await db.query(
      'products',
      where: 'name LIKE ? COLLATE NOCASE OR barcode LIKE ?',
      whereArgs: [like, like],
      orderBy: 'name',
    );

    return rows.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getTopSellingProducts({
    required String period, // 'day' | 'week' | 'month' | 'year'
    int limit = 10,
  }) async {
    final db = await instance.database;
    final now = DateTime.now();

    DateTime start;
    final end = DateTime(now.year, now.month, now.day); // date-only for today

    switch (period) {
      case 'day':
        start = end;
        break;
      case 'week':
        start = end
            .subtract(const Duration(days: 6)); // آخر 7 أيام (بما فيها اليوم)
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = end;
    }

    final startStr = start.toIso8601String().split('T').first;
    final endStr = end.toIso8601String().split('T').first;

    final rows = await db.rawQuery(
      '''
    SELECT p.id as product_id, p.name as product_name, p.barcode as product_barcode,
           SUM(si.quantity) as units_sold,
           SUM(si.quantity * si.price) as revenue
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    JOIN products p ON p.id = si.product_id
    WHERE date(s.date) BETWEEN ? AND ?
    GROUP BY p.id
    ORDER BY units_sold DESC
    LIMIT ?
    ''',
      [startStr, endStr, limit],
    );

    return rows.map((r) {
      return {
        'product_id': r['product_id'],
        'product_name': r['product_name'],
        'product_barcode': r['product_barcode'],
        'units_sold': (r['units_sold'] as num?)?.toInt() ?? 0,
        'revenue': (r['revenue'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> receiveFromSupplier({
    String? barcode,
    String? name,
    required int cartons,
    required int units,
    double? purchasePricePerCarton,
    double? purchasePricePerUnit,
    double? sellingPricePerUnitIfNew,
    int unitsInCartonIfNew = 1,
    required String receivedBy,
    String paymentType = 'cash',
    double paidAmount = 0.0,
  }) async {
    final db = await instance.database;

    final b = (barcode ?? '').trim();
    final n = (name ?? '').trim();

    Map<String, dynamic>? found;
    if (b.isNotEmpty) {
      final res = await db.query('products',
          where: 'barcode = ?', whereArgs: [b], limit: 1);
      if (res.isNotEmpty) found = Map<String, dynamic>.from(res.first);
    }
    if (found == null && n.isNotEmpty) {
      final res = await db.query('products',
          where: 'name LIKE ? COLLATE NOCASE', whereArgs: [n], limit: 1);
      if (res.isNotEmpty) found = Map<String, dynamic>.from(res.first);
    }

    final now = DateTime.now().toIso8601String();

    if (found != null) {
      final pid = (found['id'] as num).toInt();
      final unitsInCarton = (found['units_in_carton'] as num).toInt();
      final totalUnitsToAdd = cartons * unitsInCarton + units;

      if (totalUnitsToAdd > 0) {
        await increaseProductStockByUnits(pid, totalUnitsToAdd);
      }

      double unitPrice = 0.0;
      if (purchasePricePerUnit != null) {
        unitPrice = purchasePricePerUnit;
      } else if (purchasePricePerCarton != null && unitsInCarton > 0) {
        unitPrice = purchasePricePerCarton / unitsInCarton;
      } else if ((found['purchase_price'] as num?) != null &&
          (found['purchase_price'] as num) > 0 &&
          unitsInCarton > 0) {
        // fallback to stored purchase price (assumed carton price)
        unitPrice = (found['purchase_price'] as num).toDouble() /
            (unitsInCarton > 0 ? unitsInCarton : 1);
      }

      double? newCartonPrice;
      if (purchasePricePerCarton != null) {
        newCartonPrice = purchasePricePerCarton;
      } else if (purchasePricePerUnit != null) {
        newCartonPrice =
            purchasePricePerUnit * (unitsInCarton > 0 ? unitsInCarton : 1);
      }

      if (newCartonPrice != null) {
        await db.update('products', {'purchase_price': newCartonPrice},
            where: 'id = ?', whereArgs: [pid]);
      }

      final totalCost = unitPrice * totalUnitsToAdd;
      double due = totalCost - paidAmount;
      if (due < 0) due = 0.0;

      await db.insert('purchase_receipts', {
        'product_id': pid,
        'product_name': found['name'] ?? '',
        'barcode': found['barcode'] ?? '',
        'received_by': receivedBy,
        'cashier_username': receivedBy,
        'cartons': cartons,
        'units': units,
        'units_in_carton': unitsInCarton,
        'purchase_price_per_carton': newCartonPrice,
        'purchase_price_per_unit': unitPrice > 0 ? unitPrice : null,
        'payment_type': paymentType,
        'paid_amount': paidAmount,
        'paid_cash': (paymentType == 'cash') ? paidAmount : 0.0,
        'paid_wallet': (paymentType == 'wallet' || paymentType == 'card')
            ? paidAmount
            : 0.0,
        'due_amount': due,
        'created_at': now,
      });

      return {
        'status': 'ok',
        'product_created': false,
        'product_id': pid,
        'added_units': totalUnitsToAdd,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'due_amount': due,
      };
    } else {
      if (sellingPricePerUnitIfNew == null) {
        return {
          'status': 'need_selling_price',
          'message':
              'Product not found. Please provide sellingPricePerUnitIfNew and unitsInCartonIfNew to create.',
          'suggested_name': n,
          'suggested_barcode': b,
        };
      }

      final cartonPrice = purchasePricePerCarton ??
          (purchasePricePerUnit != null
              ? purchasePricePerUnit * unitsInCartonIfNew
              : null) ??
          0.0;

      final initialCartons = cartons;
      final initialRemainder = units;
      final totalUnits = initialCartons * unitsInCartonIfNew + initialRemainder;

      final unitPrice = purchasePricePerUnit ??
          (unitsInCartonIfNew > 0 ? (cartonPrice / unitsInCartonIfNew) : 0.0);
      final totalCost = unitPrice * totalUnits;
      double due = totalCost - paidAmount;
      if (due < 0) due = 0.0;

      final newId = await db.insert('products', {
        'barcode': b,
        'name': n,
        'purchase_price': cartonPrice,
        'selling_price': sellingPricePerUnitIfNew,
        'units_in_carton': unitsInCartonIfNew,
        'quantity': initialCartons,
        'units_remainder': initialRemainder,
        'production_date': '',
        'expiry_date': '',
        'low_stock_seen': 0,
        'expiry_seen': 0,
      });

      // log receipt
      await db.insert('purchase_receipts', {
        'product_id': newId,
        'product_name': n,
        'barcode': b,
        'received_by': receivedBy,
        'cashier_username': receivedBy,
        'cartons': cartons,
        'units': units,
        'units_in_carton': unitsInCartonIfNew,
        'purchase_price_per_carton': cartonPrice,
        'purchase_price_per_unit': unitPrice > 0 ? unitPrice : null,
        'payment_type': paymentType,
        'paid_amount': paidAmount,
        'paid_cash': (paymentType == 'cash') ? paidAmount : 0.0,
        'paid_wallet': (paymentType == 'wallet' || paymentType == 'card')
            ? paidAmount
            : 0.0,
        'due_amount': due,
        'created_at': now,
      });

      return {
        'status': 'ok',
        'product_created': true,
        'product_id': newId,
        'added_units': totalUnits,
        'total_cost': totalCost,
        'paid_amount': paidAmount,
        'due_amount': due,
      };
    }
  }

  Future<List<Map<String, dynamic>>> getPaidPurchaseReceipts() async {
    final db = await instance.database;
    final rows = await db.query('purchase_receipts',
        where:
            'due_amount = 0 OR (paid_amount IS NOT NULL AND paid_amount > 0 AND due_amount = 0)',
        orderBy: 'created_at DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getCreditPurchaseReceipts() async {
    final db = await instance.database;
    final rows = await db.query('purchase_receipts',
        where: 'due_amount > 0', orderBy: 'created_at DESC');
    return rows;
  }

  Future<int> addPaymentToPurchase(int receiptId, double amount,
      {String paymentMethod = 'cash'}) async {
    if (amount <= 0) return 0;
    final db = await instance.database;
    await _ensurePurchaseReceiptsColumns(db);
    return await db.transaction((txn) async {
      final rows = await txn.query('purchase_receipts',
          where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw 'Receipt not found';
      final r = Map<String, dynamic>.from(rows.first);
      final currentPaid = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final currentDue = (r['due_amount'] as num?)?.toDouble() ?? 0.0;
      final currentPaidCash = (r['paid_cash'] as num?)?.toDouble() ?? 0.0;
      final currentPaidWallet = (r['paid_wallet'] as num?)?.toDouble() ?? 0.0;
      final normalizedMethod = paymentMethod.trim().toLowerCase();
      final newPaidCash = normalizedMethod == 'cash'
          ? currentPaidCash + amount
          : currentPaidCash;
      final newPaidWallet =
          normalizedMethod == 'wallet' || normalizedMethod == 'card'
              ? currentPaidWallet + amount
              : currentPaidWallet;
      final newPaid = currentPaid + amount;
      double newDue = currentDue - amount;
      if (newDue < 0) newDue = 0.0;
      String newPaymentType;
      if (newPaidCash > 0 && newPaidWallet > 0) {
        newPaymentType = 'mixed';
      } else if (newPaidWallet > 0) {
        newPaymentType = 'wallet';
      } else {
        newPaymentType = 'cash';
      }
      final updated = await txn.update(
          'purchase_receipts',
          {
            'paid_amount': newPaid,
            'due_amount': newDue,
            'paid_cash': newPaidCash,
            'paid_wallet': newPaidWallet,
            'payment_type': newPaymentType,
          },
          where: 'id = ?',
          whereArgs: [receiptId]);
      return updated;
    });
  }

// داخل DBHelper class

  Future<void> _ensureCashDrawerTable(Database db) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_drawer';");
    final exists = tables.isNotEmpty;
    if (!exists) {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_drawer (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        updated_by TEXT,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    }
  }

  Future<void> ensureCashDrawerTable() async {
    final db = await instance.database;
    await _ensureCashDrawerTable(db);
  }

  Future<double> getLatestDrawerStartingAmount() async {
    final db = await instance.database;
    final rows = await db
        .rawQuery('SELECT amount FROM cash_drawer ORDER BY id DESC LIMIT 1');
    if (rows.isEmpty) return 0.0;
    return (rows.first['amount'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> setDrawerStartingAmount(double amount, String updatedBy,
      {String note = ''}) async {
    final db = await instance.database;
    // تأكد أن الجدول موجود (مفيد لو نسيت استدعاءه في onOpen)
    await _ensureCashDrawerTable(db);
    final now = DateTime.now().toIso8601String();
    return await db.insert('cash_drawer', {
      'amount': amount,
      'updated_by': updatedBy,
      'note': note,
      'created_at': now,
    });
  }

  Future<Map<String, double>> getDrawerTotals(
      {String? fromDate, String? toDate}) async {
    final db = await instance.database;

    // تحقق من وجود عمود drawer_withdrawn_amount
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final hasWithdrawnFlag =
        cols.any((c) => (c['name'] as String) == 'drawer_withdrawn');
    final hasWithdrawnAmount =
        cols.any((c) => (c['name'] as String) == 'drawer_withdrawn_amount');

    String dateCondition = '';
    List<Object?> args = [];
    if (fromDate != null && toDate != null) {
      dateCondition = "AND date(date) BETWEEN ? AND ?";
      args = [fromDate, toDate];
    } else if (fromDate != null) {
      dateCondition = "AND date(date) >= ?";
      args = [fromDate];
    } else if (toDate != null) {
      dateCondition = "AND date(date) <= ?";
      args = [toDate];
    }

    // نكوّن شرط الكاش بحيث إننا نطرح drawer_withdrawn_amount إذا كان موجود
    String salesNetCashSql;
    if (hasWithdrawnAmount) {
      // نحسب SUM(MAX(net - drawer_withdrawn_amount, 0))
      salesNetCashSql =
          'SELECT SUM(CASE WHEN ((COALESCE(paid_amount,0)-COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0)) > 0 THEN ((COALESCE(paid_amount,0)-COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0)) ELSE 0 END) as sales_net_cash '
          'FROM sales WHERE payment_method = ? $dateCondition';
    } else if (hasWithdrawnFlag) {
      // قديم: استبعد الفواتير المعلّمة drawer_withdrawn = 1
      salesNetCashSql =
          'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_cash '
          'FROM sales WHERE payment_method = ? AND COALESCE(drawer_withdrawn,0) = 0 $dateCondition';
    } else {
      // لا عمود تتبع: اجمع كل النقدي
      salesNetCashSql =
          'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_cash '
          'FROM sales WHERE payment_method = ? $dateCondition';
    }

    final salesRow = await db.rawQuery(salesNetCashSql, ['cash', ...args]);
    final salesNetCash =
        (salesRow.isNotEmpty && salesRow.first['sales_net_cash'] != null)
            ? (salesRow.first['sales_net_cash'] as num).toDouble()
            : 0.0;

    final cardRow = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_card FROM sales WHERE payment_method = ? $dateCondition',
      ['card', ...args],
    );
    final salesNetCard =
        (cardRow.isNotEmpty && cardRow.first['sales_net_card'] != null)
            ? (cardRow.first['sales_net_card'] as num).toDouble()
            : 0.0;

    // بقية الحسابات كما كانت
    String purchaseDateCond = '';
    List<Object?> purchaseArgs = [];
    if (fromDate != null && toDate != null) {
      purchaseDateCond = "AND date(created_at) BETWEEN ? AND ?";
      purchaseArgs = [fromDate, toDate];
    } else if (fromDate != null) {
      purchaseDateCond = "AND date(created_at) >= ?";
      purchaseArgs = [fromDate];
    } else if (toDate != null) {
      purchaseDateCond = "AND date(created_at) <= ?";
      purchaseArgs = [toDate];
    }
    final purchaseRow = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0)) as purchase_paid_cash FROM purchase_receipts WHERE payment_type = ? $purchaseDateCond',
      ['cash', ...purchaseArgs],
    );
    final purchasePaidCash = (purchaseRow.isNotEmpty &&
            purchaseRow.first['purchase_paid_cash'] != null)
        ? (purchaseRow.first['purchase_paid_cash'] as num).toDouble()
        : 0.0;

    String returnsDateCond = '';
    List<Object?> returnsArgs = [];
    if (fromDate != null && toDate != null) {
      returnsDateCond = "WHERE date(date) BETWEEN ? AND ?";
      returnsArgs = [fromDate, toDate];
    } else if (fromDate != null) {
      returnsDateCond = "WHERE date(date) >= ?";
      returnsArgs = [fromDate];
    } else if (toDate != null) {
      returnsDateCond = "WHERE date(date) <= ?";
      returnsArgs = [toDate];
    }

    await _ensureSaleReturnsColumns(db);
    final returnsRow = await db.rawQuery(
        'SELECT SUM(CASE WHEN COALESCE(refund_amount,0) > 0 THEN -COALESCE(refund_amount,0) ELSE COALESCE(paid_delta,0) END) as returns_delta FROM sale_returns $returnsDateCond',
        returnsArgs);
    final returnsDelta =
        (returnsRow.isNotEmpty && returnsRow.first['returns_delta'] != null)
            ? (returnsRow.first['returns_delta'] as num).toDouble()
            : 0.0;

    return {
      'sales_net_cash': salesNetCash,
      'sales_net_card': salesNetCard,
      'purchase_paid_cash': purchasePaidCash,
      'returns_delta': returnsDelta,
    };
  }

  Future<double> computeCurrentDrawerAmount(
      {String? fromDate, String? toDate}) async {
    final starting = await getLatestDrawerStartingAmount();
    final totals = await getDrawerTotals(fromDate: fromDate, toDate: toDate);

    final salesNetCash = totals['sales_net_cash'] ?? 0.0; // فقط النقد
    final purchasePaidCash = totals['purchase_paid_cash'] ?? 0.0;
    final returnsDelta = totals['returns_delta'] ?? 0.0;

    // formula: current = starting + sales_net_cash + returns_delta - purchase_paid_cash
    final current = starting + salesNetCash + returnsDelta - purchasePaidCash;
    return current;
  }

  Future<List<Map<String, dynamic>>> getCreditSales() async {
    final db = await instance.database;
    final rows = await db.query('sales',
        where: 'is_credit = ?', whereArgs: [1], orderBy: 'date DESC');
    return rows;
  }

  Future<List<Map<String, dynamic>>> searchCreditSalesByCustomer(
      String query) async {
    final db = await instance.database;
    final q = query.trim();
    if (q.isEmpty) return getCreditSales();
    final like = '%$q%';
    final rows = await db.query(
      'sales',
      where: "is_credit = 1 AND (customer_name LIKE ? COLLATE NOCASE)",
      whereArgs: [like],
      orderBy: 'date DESC',
    );
    return rows;
  }

  Future<int> markSaleAsPaid(
    int saleId, {
    String paymentMethod = 'cash',
    double? paidAmount,
    String? paidBy,
    DateTime? paidAt,
  }) async {
    final db = await instance.database;
    await _ensureSaleColumns(db);
    final rows =
        await db.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
    if (rows.isEmpty) throw 'Sale not found';
    final total = (rows.first['total'] as num?)?.toDouble() ?? 0.0;
    final paid = paidAmount ?? total;
    final change = (paid >= total) ? (paid - total) : 0.0;
    final updated = await db.update(
      'sales',
      {
        'is_credit': 0,
        'paid_amount': paid,
        'change_amount': change,
        'payment_method': paymentMethod,
        'credit_paid_by': paidBy,
        'credit_paid_at': paidAt?.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
    return updated;
  }

  Future<void> _ensureIsCurrentUserColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(users);");
    final has = cols.any((c) => c['name'] == 'is_current');
    if (!has) {
      await db.execute(
          'ALTER TABLE users ADD COLUMN is_current INTEGER NOT NULL DEFAULT 0;');
      await db.update('users', {'is_current': 0});
    }
  }

  Future<void> ensureIsCurrentUserColumn() async {
    final db = await instance.database;
    await _ensureIsCurrentUserColumn(db);
  }

  Future<void> setCurrentUserByUsername(String username) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.update('users', {'is_current': 0});
      await txn.update('users', {'is_current': 1},
          where: 'username = ?', whereArgs: [username]);
    });
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final db = await instance.database;
    await _ensureUserAuthColumns(db);
    await _ensureIsCurrentUserColumn(db);
    final rows = await db.query('users',
        where: 'is_current = ?', whereArgs: [1], limit: 1);
    if (rows.isNotEmpty) {
      return _normaliseUserRow(Map<String, dynamic>.from(rows.first));
    }
    return null;
  }

  Future<int> clearCurrentUser() async {
    final db = await instance.database;
    return await db.update('users', {'is_current': 0});
  }

  Future<int> renameUserAndPropagate(int userId, String newUsername) async {
    final db = await instance.database;

    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw 'User not found';
    final oldUsername = (rows.first['username'] ?? '').toString();

    if (oldUsername == newUsername) return 0;

    return await db.transaction<int>((txn) async {
      final updatedUser = await txn.update('users', {'username': newUsername},
          where: 'id = ?', whereArgs: [userId]);
      await txn.update('sales', {'cashier_username': newUsername},
          where: 'cashier_username = ?', whereArgs: [oldUsername]);
      await txn.update('sale_returns', {'cashier_username': newUsername},
          where: 'cashier_username = ?', whereArgs: [oldUsername]);
      await txn.update('purchase_receipts',
          {'received_by': newUsername, 'cashier_username': newUsername},
          where: 'received_by = ? OR cashier_username = ?',
          whereArgs: [oldUsername, oldUsername]);
      await txn.update('cash_drawer', {'updated_by': newUsername},
          where: 'updated_by = ?', whereArgs: [oldUsername]);

      return updatedUser;
    });
  }

  Future<void> _ensureSalePaymentMethodColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => c['name'] == 'payment_method');
    if (!has) {
      await db.execute(
          "ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash';");
      await db.update('sales', {'payment_method': 'cash'});
    }
  }

  Future<void> ensureSalePaymentMethodColumn() async {
    final db = await instance.database;
    await _ensureSalePaymentMethodColumn(db);
  }

  Future<void> _ensureSaleCardTransferredColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => c['name'] == 'card_transferred');
    if (!has) {
      await db.execute(
          'ALTER TABLE sales ADD COLUMN card_transferred INTEGER NOT NULL DEFAULT 0;');
      await db.update('sales', {'card_transferred': 0});
    }
  }

  Future<void> ensureSaleCardTransferredColumn() async {
    final db = await instance.database;
    await _ensureSaleCardTransferredColumn(db);
  }

  Future<double> getUntransferredCardAmount(
      {String? fromDate, String? toDate}) async {
    final db = await instance.database;

    String dateCondition = '';
    List<Object?> args = [];
    if (fromDate != null && toDate != null) {
      dateCondition = "AND date(date) BETWEEN ? AND ?";
      args = [fromDate, toDate];
    } else if (fromDate != null) {
      dateCondition = "AND date(date) >= ?";
      args = [fromDate];
    } else if (toDate != null) {
      dateCondition = "AND date(date) <= ?";
      args = [toDate];
    }

    final row = await db.rawQuery(
      'SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as card_untransferred FROM sales WHERE payment_method = ? AND COALESCE(card_transferred,0) = 0 $dateCondition',
      ['card', ...args],
    );

    return (row.isNotEmpty && row.first['card_untransferred'] != null)
        ? (row.first['card_untransferred'] as num).toDouble()
        : 0.0;
  }

  Future<List<Map<String, dynamic>>> getProductsByBarcodeList(
      String barcode) async {
    final db = await instance.database;
    final b = barcode.trim();
    if (b.isEmpty) return [];

    final rows = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [b],
      orderBy: 'name',
    );

    return rows.map((product) {
      final cartons = (product['quantity'] as num).toInt();
      final unitsInCarton = (product['units_in_carton'] as num).toInt();
      final remainder = (product['units_remainder'] as num?)?.toInt() ?? 0;
      final totalUnits = cartons * unitsInCarton + remainder;
      return {
        ...product,
        'units_remainder': remainder,
        'total_units': totalUnits,
      };
    }).toList();
  }

  Future<String?> getLastDrawerEntryByUser(String username) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT created_at FROM cash_drawer WHERE updated_by = ? ORDER BY id DESC LIMIT 1',
      [username],
    );
    if (rows.isNotEmpty) return (rows.first['created_at'] as String?);
    return null;
  }

  Future<List<Map<String, dynamic>>> getSalesByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT * FROM sales WHERE cashier_username = ? AND date(date) BETWEEN ? AND ? ORDER BY date ASC',
      [cashierUsername, fromDate, toDate],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getPurchaseReceiptsByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT * FROM purchase_receipts
      WHERE cashier_username = ?
        AND date(created_at) BETWEEN ? AND ?
      ORDER BY created_at ASC
      ''',
      [username, fromDate, toDate],
    );
    return rows;
  }

  Future<double> getCardAmountByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sum_card
    FROM sales
    WHERE payment_method = 'card'
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['sum_card'] != null)
        ? (rows.first['sum_card'] as num).toDouble()
        : 0.0;
  }

  Future<double> getCreditOutstandingByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(total,0) - COALESCE(paid_amount,0)) as credit_out
    FROM sales
    WHERE is_credit = 1
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    final val = (rows.isNotEmpty && rows.first['credit_out'] != null)
        ? (rows.first['credit_out'] as num).toDouble()
        : 0.0;
    return val < 0 ? 0.0 : val;
  }

  Future<double> getPurchaseReceiptsOutstandingByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(due_amount,0)) as total_due
    FROM purchase_receipts
    WHERE cashier_username = ?
      AND date(created_at) BETWEEN ? AND ?
    ''',
      [username, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['total_due'] != null)
        ? (rows.first['total_due'] as num).toDouble()
        : 0.0;
  }

  Future<double> getLatestDrawerStartingAmountByUser(String username) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      'SELECT amount FROM cash_drawer WHERE updated_by = ? ORDER BY id DESC LIMIT 1',
      [username],
    );
    if (rows.isNotEmpty && rows.first['amount'] != null) {
      return (rows.first['amount'] as num).toDouble();
    }
    return 0.0;
  }

  Future<double> getSalesNetCashByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_net_cash
    FROM sales
    WHERE payment_method = 'cash'
      AND cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['sales_net_cash'] != null)
        ? (rows.first['sales_net_cash'] as num).toDouble()
        : 0.0;
  }

  Future<double> getReturnsDeltaByCashierBetweenDates({
    required String cashierUsername,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    await _ensureSaleReturnsColumns(db);
    final rows = await db.rawQuery(
      '''
    SELECT SUM(CASE WHEN COALESCE(refund_amount,0) > 0 THEN -COALESCE(refund_amount,0) ELSE COALESCE(paid_delta,0) END) as returns_delta
    FROM sale_returns
    WHERE cashier_username = ?
      AND date(date) BETWEEN ? AND ?
    ''',
      [cashierUsername, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['returns_delta'] != null)
        ? (rows.first['returns_delta'] as num).toDouble()
        : 0.0;
  }

  Future<double> getPurchasePaidCashByUserBetweenDates({
    required String username,
    required String fromDate,
    required String toDate,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
    SELECT SUM(COALESCE(paid_amount,0)) as purchase_paid
    FROM purchase_receipts
    WHERE cashier_username = ?
      AND date(created_at) BETWEEN ? AND ?
    ''',
      [username, fromDate, toDate],
    );
    return (rows.isNotEmpty && rows.first['purchase_paid'] != null)
        ? (rows.first['purchase_paid'] as num).toDouble()
        : 0.0;
  }

// 1) داخل كلاس DBHelper: دالة الترحيل الخاصة بخصم الفاتورة
  Future<void> _ensureSaleDiscountColumns(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");

    Future<void> addIfMissing(String name, String sql) async {
      final has = cols.any((c) => c['name'] == name);
      if (!has) {
        await db.execute(sql);
      }
    }

    await addIfMissing(
      'discount_type',
      "ALTER TABLE sales ADD COLUMN discount_type TEXT NOT NULL DEFAULT 'fixed';",
    );
    await addIfMissing(
      'discount_value',
      "ALTER TABLE sales ADD COLUMN discount_value REAL NOT NULL DEFAULT 0;",
    );
  }

// 2) غلاف عام للنداء من خارج الكلاس (مثلاً: من _saveSale أو init)
  Future<void> ensureSaleDiscountColumns() async {
    final db = await instance.database;
    await _ensureSaleDiscountColumns(db);
  }

  Future<Map<String, double>> computeSaleTotalWithDiscountFromItems(int saleId,
      {String? discountType, double? discountValue}) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
        'SELECT SUM(quantity * price) as subtotal FROM sale_items WHERE sale_id = ?',
        [saleId]);
    final subtotal = (rows.isNotEmpty && rows.first['subtotal'] != null)
        ? (rows.first['subtotal'] as num).toDouble()
        : 0.0;

    // إذا لم يُمرّر نوع/قيمة خصم، حاول قراءته من جدول sales
    String dType = discountType ?? 'fixed';
    double dValue = discountValue ?? 0.0;
    if (discountType == null || discountValue == null) {
      final sRows = await db.query('sales',
          where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (sRows.isNotEmpty) {
        dType = (sRows.first['discount_type'] ?? 'fixed').toString();
        dValue = (sRows.first['discount_value'] as num?)?.toDouble() ?? 0.0;
      }
    }

    double discountAmount = 0.0;
    if (dType == 'percent') {
      discountAmount = subtotal * (dValue / 100.0);
    } else {
      discountAmount = dValue;
    }
    if (discountAmount < 0) discountAmount = 0.0;
    if (discountAmount > subtotal) discountAmount = subtotal;

    final finalTotal = subtotal - discountAmount;
    return {
      'subtotal': subtotal,
      'discount': discountAmount,
      'total': finalTotal,
    };
  }

  Future<int> applyDiscountToSale({
    required int saleId,
    required String discountType, // 'fixed' | 'percent'
    required double discountValue,
  }) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      final saleRows = await txn.query('sales',
          where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (saleRows.isEmpty) throw 'Sale not found';
      final sale = saleRows.first;
      final oldPaid = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
      final oldNote = (sale['return_note'] ?? '').toString();

      // حساب subtotal من sale_items
      final sumRow = await txn.rawQuery(
          'SELECT SUM(quantity * price) AS subtotal FROM sale_items WHERE sale_id = ?',
          [saleId]);
      final subtotal = (sumRow.isNotEmpty && sumRow.first['subtotal'] != null)
          ? (sumRow.first['subtotal'] as num).toDouble()
          : 0.0;

      // حساب قيمة الخصم
      double discountAmount = 0.0;
      if (discountType == 'percent') {
        discountAmount = subtotal * (discountValue / 100.0);
      } else {
        discountAmount = discountValue;
      }
      if (discountAmount < 0) discountAmount = 0.0;
      if (discountAmount > subtotal) discountAmount = subtotal;

      final newTotal = subtotal - discountAmount;

      double newPaid = oldPaid;
      if (newPaid < 0) newPaid = 0.0;

      double newChange = 0.0;
      int isCredit = 0;
      if (newPaid >= newTotal) {
        newChange = newPaid - newTotal;
        isCredit = 0;
      } else {
        newChange = 0.0;
        isCredit = 1;
      }

      final updated = await txn.update(
          'sales',
          {
            'total': newTotal,
            'discount_type': discountType,
            'discount_value': discountValue,
            'paid_amount': newPaid,
            'change_amount': newChange,
            'is_credit': isCredit,
          },
          where: 'id = ?',
          whereArgs: [saleId]);

      return updated;
    });
  }

  // Ensure column exists (run-once safe)
  Future<void> ensureDrawerWithdrawnColumnExists() async {
    final db = await database;
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => (c['name'] as String) == 'drawer_withdrawn');
    if (!has) {
      await db.execute(
          "ALTER TABLE sales ADD COLUMN drawer_withdrawn INTEGER DEFAULT 0;");
    }
  }

// Mark all eligible cash sales as withdrawn (optionally filter by cashier)
  Future<void> markAllCashSalesAsDrawerWithdrawn(
      {String? cashierUsername}) async {
    await ensureDrawerWithdrawnColumnExists();
    final db = await database;
    String where =
        "payment_method = 'cash' AND COALESCE(drawer_withdrawn,0) = 0";
    List<dynamic> args = [];
    if (cashierUsername != null && cashierUsername.isNotEmpty) {
      where += " AND cashier_username = ?";
      args.add(cashierUsername);
    }
    await db.update('sales', {'drawer_withdrawn': 1},
        where: where, whereArgs: args);
  }

  /// حساب ملخّص يومي *بلا تخزين* (on-the-fly)
  /// date: التاريخ المطلوب (ستُحوَّل إلى YYYY-MM-DD)
  /// excludeDrawerWithdrawn: لو true (افتراضي) سيتم استثناء الفواتير التي وُسِمَت drawer_withdrawn = 1
  Future<Map<String, double>> computeDailySummary(DateTime date,
      {bool excludeDrawerWithdrawn = true}) async {
    final db = await instance.database;
    final dateOnly = date.toIso8601String().split('T').first; // YYYY-MM-DD

    // هل العمود drawer_withdrawn موجود؟
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final hasDrawerWithdrawn =
        cols.any((c) => (c['name'] as String) == 'drawer_withdrawn');

    // شرط الفلاتر حسب وجود العمود ورغبتك
    String cashWhere = "payment_method = 'cash'";
    if (excludeDrawerWithdrawn && hasDrawerWithdrawn) {
      cashWhere += " AND COALESCE(drawer_withdrawn,0) = 0";
    }

    // إجمالي المبيعات (عمود total من sales) لذلك نأخذ SUM(total)
    final salesTotalRow = await db.rawQuery(
      "SELECT SUM(COALESCE(total,0)) as sales_total FROM sales WHERE date(date) = ?",
      [dateOnly],
    );
    final salesTotal =
        (salesTotalRow.isNotEmpty && salesTotalRow.first['sales_total'] != null)
            ? (salesTotalRow.first['sales_total'] as num).toDouble()
            : 0.0;

    // ما تم تحصيله نقدًا (net = paid_amount - change_amount) مع إمكانية استثناء drawer_withdrawn
    final salesPaidCashRow = await db.rawQuery(
      "SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_paid_cash FROM sales WHERE $cashWhere AND date(date) = ?",
      [dateOnly],
    );
    final salesPaidCash = (salesPaidCashRow.isNotEmpty &&
            salesPaidCashRow.first['sales_paid_cash'] != null)
        ? (salesPaidCashRow.first['sales_paid_cash'] as num).toDouble()
        : 0.0;

    // ما تم تحصيله بوسائل دفع غير نقدية (payment_method 'card' أو 'wallet')
    final salesPaidCardRow = await db.rawQuery(
      "SELECT SUM(COALESCE(paid_amount,0) - COALESCE(change_amount,0)) as sales_paid_card "
      "FROM sales WHERE (payment_method = 'card' OR payment_method = 'wallet' OR lower(payment_method) LIKE '%card%') AND date(date) = ?",
      [dateOnly],
    );
    final salesPaidCard = (salesPaidCardRow.isNotEmpty &&
            salesPaidCardRow.first['sales_paid_card'] != null)
        ? (salesPaidCardRow.first['sales_paid_card'] as num).toDouble()
        : 0.0;

    // ما دفع للنقد في سندات الشراء لنفس اليوم
    final purchasesRow = await db.rawQuery(
      "SELECT SUM(COALESCE(paid_amount,0)) as purchases_paid_cash FROM purchase_receipts WHERE payment_type = 'cash' AND date(created_at) = ?",
      [dateOnly],
    );
    final purchasesPaidCash = (purchasesRow.isNotEmpty &&
            purchasesRow.first['purchases_paid_cash'] != null)
        ? (purchasesRow.first['purchases_paid_cash'] as num).toDouble()
        : 0.0;

    // مجموع المرتجعات لليوم: refund_amount للخصم الجزئي، و paid_delta للبدل/البيانات القديمة
    await _ensureSaleReturnsColumns(db);
    final returnsRow = await db.rawQuery(
      "SELECT SUM(CASE WHEN COALESCE(refund_amount,0) > 0 THEN -COALESCE(refund_amount,0) ELSE COALESCE(paid_delta,0) END) as returns_delta FROM sale_returns WHERE date(date) = ?",
      [dateOnly],
    );
    final returnsDelta =
        (returnsRow.isNotEmpty && returnsRow.first['returns_delta'] != null)
            ? (returnsRow.first['returns_delta'] as num).toDouble()
            : 0.0;

    return {
      'sales_total': salesTotal,
      'sales_paid_cash': salesPaidCash,
      'sales_paid_card': salesPaidCard,
      'purchases_paid_cash': purchasesPaidCash,
      'returns_delta': returnsDelta,
    };
  }

// examples to add into DBHelper class

// getProducts with offset+limit (pagination)
  Future<List<Map<String, dynamic>>> getProducts(
      {int offset = 0, int limit = 50}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      orderBy: 'id ASC',
      limit: limit,
      offset: offset,
    );
    return maps;
  }

// search products by name or barcode (returns ALL matches)
  Future<List<Map<String, dynamic>>> searchProducts(String q) async {
    final db = await database;
    final pattern = '%${q.replaceAll("'", "''").toLowerCase()}%';
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      "SELECT * FROM products WHERE LOWER(name) LIKE ? OR LOWER(barcode) LIKE ? ORDER BY id ASC",
      [pattern, pattern],
    );
    return maps;
  }

  /// داخل class DBHelper { ... }
  Future<void> wipeAllExceptProducts({bool keepUsers = false}) async {
    final db = await database; // <-- هنا getter موجود لأن إحنا داخل الكلاس
    await db.transaction((txn) async {
      final tablesRes = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
      final allTables = tablesRes.map((r) => r['name'] as String).toList();

      final keep = <String>{'products'};
      if (keepUsers) keep.add('users');

      final preferredOrder = [
        'sale_return_items',
        'sale_returns',
        'sale_items',
        'sales',
        'purchase_receipts',
        'cash_drawer',
        'users',
      ];

      Future<void> _deleteTable(String tableName) async {
        try {
          await txn.delete(tableName);
        } catch (e) {
          try {
            await txn.execute('DELETE FROM $tableName;');
          } catch (_) {}
        }
        try {
          await txn.execute(
              'DELETE FROM sqlite_sequence WHERE name = ?;', [tableName]);
        } catch (_) {}
      }

      final remaining = Set<String>.from(allTables)..removeAll(keep);

      for (final t in preferredOrder) {
        if (remaining.contains(t)) {
          await _deleteTable(t);
          remaining.remove(t);
        }
      }

      for (final t in remaining) {
        if (t == 'products' || t.startsWith('sqlite_')) continue;
        await _deleteTable(t);
      }
    });
  }

// inside class DBHelper

  Future<void> _ensureDrawerWithdrawnAmountColumn(Database db) async {
    final cols = await db.rawQuery("PRAGMA table_info(sales);");
    final has = cols.any((c) => c['name'] == 'drawer_withdrawn_amount');
    if (!has) {
      // إضافة العمود كـ REAL أو NUMERIC حسب حاجتك؛ افتراضي 0
      await db.execute(
          "ALTER TABLE sales ADD COLUMN drawer_withdrawn_amount REAL NOT NULL DEFAULT 0;");
      // (اختياري) نملأ القيم القديمة بصفر
      await db.update('sales', {'drawer_withdrawn_amount': 0});
    }
  }

  Future<void> ensureDrawerWithdrawnAmountColumn() async {
    final db = await instance.database;
    await _ensureDrawerWithdrawnAmountColumn(db);
  }

// ضمن class DBHelper { ... }

  /// نفّذ هذا مرة عند init لنتأكد أن العمود synced موجود
  Future<void> ensureSyncedColumn() async {
    final db = await database;
    final info = await db.rawQuery("PRAGMA table_info(products)");
    final hasSynced = info.any((col) => (col['name'] as String) == 'synced');
    if (!hasSynced) {
      await db
          .execute("ALTER TABLE products ADD COLUMN synced INTEGER DEFAULT 0");
    }
  }

  /// علّم المنتج كمُزامَن بعد نجاح الرفع (set synced = 1)
  Future<int> markProductSynced(int id) async {
    final db = await database;
    return await db.update(
      'products',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertCloseShift({
    required String cashierName,
    required String startTime,
    required String endTime,
    double openingBalance = 0.0,
    double totalSales = 0.0,
    double cashSales = 0.0,
    double grossSales = 0.0,
    double returnsDelta = 0.0,
    double totalExpenses = 0.0,
    double cashExpenses = 0.0,
    double netProfit = 0.0,
    double closingBalance = 0.0,
    String? note,
  }) async {
    final db = await database;
    await _ensureCloseShiftsTable(db);
    return await db.insert('close_shifts', {
      'cashier_name': cashierName,
      'start_time': startTime,
      'end_time': endTime,
      'opening_balance': openingBalance,
      'total_sales': totalSales,
      'cash_sales': cashSales,
      'gross_sales': grossSales,
      'returns_delta': returnsDelta,
      'total_expenses': totalExpenses,
      'cash_expenses': cashExpenses,
      'net_profit': netProfit,
      'closing_balance': closingBalance,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  double _numFromRow(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<void> setFixedShiftOpeningBalance(double amount) async {
    final db = await database;
    await _ensureShiftSettingsTable(db);
    await _ensureCashDrawerTable(db);
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'shift_settings',
      {
        'key': 'opening_balance',
        'value': amount,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<double> getFixedShiftOpeningBalance() async {
    final db = await database;
    await _ensureShiftSettingsTable(db);
    final rows = await db.query(
      'shift_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['opening_balance'],
      limit: 1,
    );
    if (rows.isNotEmpty) return _numFromRow(rows.first, 'value');
    return 0.0;
  }

  Future<Map<String, double>> computeCloseShiftSummary({
    required String cashierName,
    required String fromDateTime,
    required String toDateTime,
  }) async {
    final db = await database;
    await _ensureSaleColumns(db);
    await _ensureSaleReturnsColumns(db);
    await _ensureCashDrawerTable(db);
    await _ensureDrawerWithdrawnAmountColumn(db);
    await _ensureShiftSettingsTable(db);

    final openingBalance = await getFixedShiftOpeningBalance();
    final diagnosticRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS sales_count, MIN(date) AS min_date, MAX(date) AS max_date
      FROM sales
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
      ''',
      [cashierName.trim()],
    );
    debugPrint(
        '[CloseShiftSummaryDiagnostic] cashier=${cashierName.trim()} fromDateTime=$fromDateTime toDateTime=$toDateTime salesRange=${diagnosticRows.isNotEmpty ? diagnosticRows.first : {}}');

    final cashRows = await db.rawQuery(
      '''
      SELECT SUM(
        CASE
          WHEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0)) > 0
          THEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0))
          ELSE 0
        END
	      ) AS cash_sales
	      FROM sales
	      WHERE LOWER(TRIM(COALESCE(payment_method,''))) = 'cash'
	        AND NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
	        AND (
	          (
	            TRIM(COALESCE(cashier_username,'')) = ?
	            AND (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
	            AND datetime(date) BETWEEN datetime(?) AND datetime(?)
	          )
	          OR
	          (
	            TRIM(COALESCE(credit_paid_by,'')) = ?
	            AND datetime(credit_paid_at) BETWEEN datetime(?) AND datetime(?)
	          )
	        )
	      ''',
      [
        cashierName.trim(),
        fromDateTime,
        toDateTime,
        cashierName.trim(),
        fromDateTime,
        toDateTime,
      ],
    );
    final cashSales =
        cashRows.isNotEmpty ? _numFromRow(cashRows.first, 'cash_sales') : 0.0;

    final unpaidCreditRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS excluded_unpaid_credit
      FROM sales
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
        AND NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
        AND COALESCE(is_credit,0) = 1
        AND COALESCE(paid_amount,0) < COALESCE(total,0)
        AND datetime(date) BETWEEN datetime(?) AND datetime(?)
      ''',
      [cashierName.trim(), fromDateTime, toDateTime],
    );
    final excludedUnpaidCredit = unpaidCreditRows.isNotEmpty
        ? _numFromRow(unpaidCreditRows.first, 'excluded_unpaid_credit').toInt()
        : 0;
    debugPrint(
        '[CloseShiftSummary] cashier=${cashierName.trim()} excludedUnpaidCreditSales=$excludedUnpaidCredit from=$fromDateTime to=$toDateTime');

    final salesRows = await db.rawQuery(
      '''
	      SELECT SUM(COALESCE(total,0)) AS gross_sales
	      FROM sales
	      WHERE NOT (COALESCE(is_return,0) = 1 AND COALESCE(return_of_sale_id,0) > 0)
	        AND NOT (COALESCE(is_credit,0) = 1 AND COALESCE(paid_amount,0) < COALESCE(total,0))
	        AND (
	          (
	            TRIM(COALESCE(cashier_username,'')) = ?
	            AND (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
	            AND datetime(date) BETWEEN datetime(?) AND datetime(?)
	          )
	          OR
	          (
	            TRIM(COALESCE(credit_paid_by,'')) = ?
	            AND datetime(credit_paid_at) BETWEEN datetime(?) AND datetime(?)
	          )
	        )
	      ''',
      [
        cashierName.trim(),
        fromDateTime,
        toDateTime,
        cashierName.trim(),
        fromDateTime,
        toDateTime,
      ],
    );
    final grossSales = salesRows.isNotEmpty
        ? _numFromRow(salesRows.first, 'gross_sales')
        : 0.0;

    final returnsRows = await db.rawQuery(
      '''
      SELECT SUM(CASE WHEN COALESCE(refund_amount,0) > 0 THEN -COALESCE(refund_amount,0) ELSE COALESCE(paid_delta,0) END) AS returns_delta
      FROM sale_returns
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
        AND datetime(date) BETWEEN datetime(?) AND datetime(?)
      ''',
      [cashierName.trim(), fromDateTime, toDateTime],
    );
    final returnsDelta = returnsRows.isNotEmpty
        ? _numFromRow(returnsRows.first, 'returns_delta')
        : 0.0;

    final expenseRows = await db.rawQuery(
      '''
      SELECT SUM(COALESCE(paid_cash,0) + COALESCE(paid_wallet,0)) AS total_expenses,
             SUM(COALESCE(paid_cash,0)) AS cash_expenses,
             SUM(COALESCE(paid_wallet,0)) AS wallet_expenses
      FROM purchase_receipts
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
        AND datetime(created_at) > datetime(?)
        AND datetime(created_at) <= datetime(?)
      ''',
      [cashierName.trim(), fromDateTime, toDateTime],
    );
    final totalExpenses = expenseRows.isNotEmpty
        ? _numFromRow(expenseRows.first, 'total_expenses')
        : 0.0;
    final cashExpenses = expenseRows.isNotEmpty
        ? _numFromRow(expenseRows.first, 'cash_expenses')
        : 0.0;
    final totalSales = (grossSales + returnsDelta).clamp(0.0, double.infinity);
    final netProfit = totalSales - totalExpenses;
    final returnsImpactOnCash = returnsDelta < 0 ? returnsDelta : 0.0;
    final closingBalance =
        openingBalance + cashSales + returnsImpactOnCash - cashExpenses;

    debugPrint(
        '[CloseShiftSummary] cashier=${cashierName.trim()} from=$fromDateTime to=$toDateTime gross=$grossSales cash=$cashSales expenses=$totalExpenses returns=$returnsDelta totalSales=$totalSales returnsCashImpact=$returnsImpactOnCash closing=$closingBalance');

    return {
      'opening_balance': openingBalance,
      'cash_sales': cashSales,
      'gross_sales': grossSales,
      'returns_delta': returnsDelta,
      'cash_expenses': cashExpenses,
      'total_sales': totalSales,
      'total_expenses': totalExpenses,
      'net_profit': netProfit,
      'closing_balance': closingBalance,
    };
  }

  Future<int> closeShiftAndResetDrawer({
    required String cashierName,
    required String startTime,
    required String endTime,
    required double openingBalance,
    required double totalSales,
    required double cashSales,
    required double grossSales,
    required double returnsDelta,
    required double totalExpenses,
    required double cashExpenses,
    required double netProfit,
    required double closingBalance,
    required String fromDateTime,
    required String toDateTime,
  }) async {
    final db = await database;
    await _ensureCloseShiftsTable(db);
    await _ensureCashDrawerTable(db);
    await ensureDrawerWithdrawnColumnExists();
    await _ensureDrawerWithdrawnAmountColumn(db);
    await _ensureAppSettingsTable(db);

    return await db.transaction<int>((txn) async {
      final now = DateTime.now().toIso8601String();
      debugPrint(
          '[CloseShiftSave] cashier=$cashierName totalSales=$totalSales cashSales=$cashSales grossSales=$grossSales returnsDelta=$returnsDelta expenses=$totalExpenses cashExpenses=$cashExpenses closing=$closingBalance');
      final shiftId = await txn.insert('close_shifts', {
        'cashier_name': cashierName,
        'start_time': startTime,
        'end_time': endTime,
        'opening_balance': openingBalance,
        'total_sales': totalSales,
        'cash_sales': cashSales,
        'gross_sales': grossSales,
        'returns_delta': returnsDelta,
        'total_expenses': totalExpenses,
        'cash_expenses': cashExpenses,
        'net_profit': netProfit,
        'closing_balance': closingBalance,
        'note': 'Closed locally and reset drawer to opening balance',
        'created_at': now,
      });

      await txn.rawUpdate(
        '''
        UPDATE sales
        SET drawer_withdrawn = 1,
            drawer_withdrawn_amount = COALESCE(paid_amount,0) - COALESCE(change_amount,0)
        WHERE LOWER(TRIM(COALESCE(payment_method,''))) = 'cash'
          AND TRIM(COALESCE(cashier_username,'')) = ?
          AND (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
          AND datetime(date) BETWEEN datetime(?) AND datetime(?)
          AND COALESCE(drawer_withdrawn,0) = 0
        ''',
        [cashierName.trim(), fromDateTime, toDateTime],
      );

      await txn.rawUpdate(
        '''
        UPDATE sales
        SET drawer_withdrawn = 1,
            drawer_withdrawn_amount = COALESCE(paid_amount,0) - COALESCE(change_amount,0)
        WHERE LOWER(TRIM(COALESCE(payment_method,''))) = 'cash'
          AND TRIM(COALESCE(credit_paid_by,'')) = ?
          AND datetime(credit_paid_at) BETWEEN datetime(?) AND datetime(?)
          AND COALESCE(drawer_withdrawn,0) = 0
        ''',
        [cashierName.trim(), fromDateTime, toDateTime],
      );

      await txn.insert('cash_drawer', {
        'amount': openingBalance,
        'updated_by': cashierName,
        'note': 'Reset after close shift #$shiftId',
        'created_at': now,
      });

      await txn.insert(
        'app_settings',
        {
          'key': _currentShiftStartSettingKey(cashierName),
          'value': endTime,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return shiftId;
    });
  }

  Future<List<Map<String, dynamic>>> getCloseShifts(
      {String? cashierName}) async {
    final db = await database;
    await _ensureCloseShiftsTable(db);
    if (cashierName != null && cashierName.trim().isNotEmpty) {
      return await db.query(
        'close_shifts',
        where: 'cashier_name = ?',
        whereArgs: [cashierName.trim()],
        orderBy: 'end_time DESC',
      );
    }
    return await db.query('close_shifts', orderBy: 'end_time DESC');
  }

  String _currentShiftStartSettingKey(String cashierName) {
    return 'current_shift_start_${cashierName.trim().toLowerCase()}';
  }

  DateTime? _parseDbDateTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed) ??
        DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
  }

  Future<String> getCurrentShiftStartDateTime(String cashierName) async {
    final db = await database;
    final username = cashierName.trim();
    final ultimateFallback =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
    await _ensureCloseShiftsTable(db);
    await _ensureAppSettingsTable(db);
    final rows = await db.query(
      'close_shifts',
      columns: ['end_time'],
      where: "TRIM(COALESCE(cashier_name, '')) = ?",
      whereArgs: [username],
      orderBy: 'datetime(end_time) DESC',
      limit: 1,
    );
    final lastClosedEnd = rows.isNotEmpty && rows.first['end_time'] != null
        ? rows.first['end_time'].toString()
        : '2000-01-01 00:00:00';

    final storedStart = await getAppSetting(_currentShiftStartSettingKey(
      username,
    ));
    if (storedStart == null || storedStart.trim().isEmpty) {
      if (lastClosedEnd.startsWith('2000-')) {
        debugPrint(
            '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$ultimateFallback source=ultimate_24h_fallback reason=no_app_settings_or_close_shift');
        return ultimateFallback;
      }
      debugPrint(
          '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$lastClosedEnd source=close_shifts reason=no_app_settings_start');
      return lastClosedEnd;
    }

    final storedDate = _parseDbDateTime(storedStart);
    final lastClosedDate = _parseDbDateTime(lastClosedEnd);
    if (storedDate == null || lastClosedDate == null) {
      if (lastClosedEnd.startsWith('2000-')) {
        debugPrint(
            '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$ultimateFallback source=ultimate_24h_fallback reason=parse_failed_and_no_close_shift');
        return ultimateFallback;
      }
      debugPrint(
          '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$lastClosedEnd source=close_shifts reason=parse_failed');
      return lastClosedEnd;
    }
    final returning =
        storedDate.isAfter(lastClosedDate) ? storedStart : lastClosedEnd;
    if (returning.startsWith('2000-')) {
      debugPrint(
          '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$ultimateFallback source=ultimate_24h_fallback reason=resolved_to_2000');
      return ultimateFallback;
    }
    debugPrint(
        '[ShiftStart] cashier=$cashierName storedStart=$storedStart lastClosedEnd=$lastClosedEnd returning=$returning source=${storedDate.isAfter(lastClosedDate) ? 'app_settings' : 'close_shifts'}');
    return returning;
  }

  Future<void> ensureCurrentShiftStartDateTime({
    required String cashierName,
    required String fallbackStartTime,
  }) async {
    final db = await database;
    final username = cashierName.trim();
    if (username.isEmpty) return;

    await _ensureCloseShiftsTable(db);
    await _ensureAppSettingsTable(db);
    await ensureDrawerWithdrawnColumnExists();

    final key = _currentShiftStartSettingKey(username);
    final existing = await getAppSetting(key);
    if (existing != null && existing.trim().isNotEmpty) return;

    final rows = await db.query(
      'close_shifts',
      columns: ['end_time'],
      where: "TRIM(COALESCE(cashier_name, '')) = ?",
      whereArgs: [username],
      orderBy: 'datetime(end_time) DESC',
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['end_time'] != null) {
      await setAppSetting(key, rows.first['end_time'].toString());
      return;
    }

    final unclosedSales = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM sales
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
        AND COALESCE(drawer_withdrawn,0) = 0
      ''',
      [username],
    );
    final count = unclosedSales.isNotEmpty
        ? (unclosedSales.first['count'] as num?)?.toInt() ?? 0
        : 0;
    if (count > 0) return;

    await setAppSetting(key, fallbackStartTime);
  }

  Future<double> computeCurrentShiftDrawerBalance(String cashierName) async {
    final db = await database;
    await _ensureSaleColumns(db);
    await _ensureSaleReturnsColumns(db);
    final username = cashierName.trim();
    if (username.isEmpty) return await getFixedShiftOpeningBalance();

    final openingBalance = await getFixedShiftOpeningBalance();
    final shiftStart = await getCurrentShiftStartDateTime(username);
    final now = DateTime.now().toIso8601String();

    // Sum all cash sales since shift start. Do not filter by drawer_withdrawn,
    // because a cashier may log out and back in before closing the shift.
    final rows = await db.rawQuery(
      '''
      SELECT SUM(
        CASE
          WHEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0)) > 0
          THEN ((COALESCE(paid_amount,0) - COALESCE(change_amount,0)) - COALESCE(drawer_withdrawn_amount,0))
          ELSE 0
        END
      ) AS cash_sales
      FROM sales
      WHERE LOWER(COALESCE(payment_method,'')) = 'cash'
        AND (
          (
            TRIM(COALESCE(cashier_username,'')) = ?
            AND COALESCE(is_credit,0) = 0
            AND (credit_paid_at IS NULL OR TRIM(COALESCE(credit_paid_at,'')) = '')
            AND datetime(date) > datetime(?)
            AND datetime(date) <= datetime(?)
          )
          OR (
            TRIM(COALESCE(credit_paid_by,'')) = ?
            AND datetime(credit_paid_at) > datetime(?)
            AND datetime(credit_paid_at) <= datetime(?)
          )
        )
      ''',
      [username, shiftStart, now, username, shiftStart, now],
    );
    final cashSales =
        rows.isNotEmpty ? _numFromRow(rows.first, 'cash_sales') : 0.0;
    final returnsRows = await db.rawQuery(
      '''
      SELECT SUM(CASE WHEN COALESCE(refund_amount,0) > 0 THEN -COALESCE(refund_amount,0) ELSE COALESCE(paid_delta,0) END) AS returns_delta
      FROM sale_returns
      WHERE TRIM(COALESCE(cashier_username,'')) = ?
        AND datetime(date) > datetime(?)
        AND datetime(date) <= datetime(?)
      ''',
      [username, shiftStart, now],
    );
    final returnsDelta = returnsRows.isNotEmpty
        ? _numFromRow(returnsRows.first, 'returns_delta')
        : 0.0;
    debugPrint(
        '[DrawerBalance] cashier=$username shiftStart=$shiftStart now=$now opening=$openingBalance cashSales=$cashSales returns=$returnsDelta');

    return openingBalance + cashSales + returnsDelta;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await database;
    await _ensureAppSettingsTable(db);
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getAppSetting(String key) async {
    final db = await database;
    await _ensureAppSettingsTable(db);
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<Map<String, String>> getShopSettings() async {
    return {
      'shop_name': await getAppSetting('shop_name') ?? 'CashGo',
      'shop_address': await getAppSetting('shop_address') ?? '',
      'shop_phone': await getAppSetting('shop_phone') ?? '',
    };
  }

  Future<void> saveShopSettings({
    required String shopName,
    required String address,
    required String phone,
  }) async {
    await setAppSetting(
        'shop_name', shopName.trim().isEmpty ? 'CashGo' : shopName.trim());
    await setAppSetting('shop_address', address.trim());
    await setAppSetting('shop_phone', phone.trim());
  }

  Future<String> getThemePreference() async {
    return await getAppSetting('theme_mode') ?? 'dark';
  }

  Future<void> saveThemePreference(String mode) async {
    await setAppSetting('theme_mode', mode == 'light' ? 'light' : 'dark');
  }

  Future<List<Map<String, dynamic>>> getProfitReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    final fromStr = DateTime(from.year, from.month, from.day).toIso8601String();
    final toStr =
        DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final rows = await db.rawQuery(
      '''
	      SELECT
	        p.id AS product_id,
	        p.name AS product_name,
	        p.barcode AS barcode,
	        COALESCE(p.purchase_price,0) AS purchase_price,
	        COALESCE(p.selling_price,0) AS selling_price,
	        COALESCE(p.units_in_carton,1) AS units_in_carton,
	        SUM(COALESCE(si.quantity,0)) - COALESCE(ret.returned_qty, 0) AS quantity_sold,
	        (SUM(COALESCE(si.quantity,0) * COALESCE(si.price,0)) - COALESCE(ret.returned_revenue, 0)) AS revenue,
	        (SUM((COALESCE(si.price,0) - COALESCE(si.purchase_price_per_unit,0)) * COALESCE(si.quantity,0)) - COALESCE(ret.returned_profit, 0)) AS profit
	      FROM sale_items si
	      JOIN sales s ON s.id = si.sale_id
	      JOIN products p ON p.id = si.product_id
	      LEFT JOIN (
	        SELECT
	          sri.product_id,
	          SUM(COALESCE(sri.qty, 0)) AS returned_qty,
	          SUM(COALESCE(sri.qty, 0) * COALESCE(sri.price, 0)) AS returned_revenue,
	          SUM(COALESCE(sri.qty, 0) * (COALESCE(sri.price, 0) - COALESCE(si2.purchase_price_per_unit, 0))) AS returned_profit
	        FROM sale_return_items sri
	        JOIN sale_returns sr ON sr.id = sri.return_id
	        JOIN sale_items si2 ON si2.sale_id = sr.sale_id AND si2.product_id = sri.product_id
	        WHERE COALESCE(sri.is_replacement, 0) = 0
	          AND datetime(sr.date) >= datetime(?)
	          AND datetime(sr.date) <= datetime(?)
	        GROUP BY sri.product_id
	      ) ret ON ret.product_id = p.id
	      WHERE COALESCE(s.is_return,0) = 0
	        AND datetime(s.date) >= datetime(?)
	        AND datetime(s.date) <= datetime(?)
	      GROUP BY p.id, p.name, p.barcode, p.purchase_price, p.selling_price, p.units_in_carton
	      HAVING quantity_sold > 0
	      ORDER BY profit DESC
	      ''',
      [fromStr, toStr, fromStr, toStr],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<int> addShopExternalExpense({
    required String title,
    required double amount,
    required DateTime date,
  }) async {
    final db = await database;
    await _ensureShopExternalExpensesTable(db);
    return db.insert('shop_external_expenses', {
      'title': title.trim(),
      'amount': amount,
      'expense_date':
          DateTime(date.year, date.month, date.day).toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> deleteShopExternalExpense(int id) async {
    final db = await database;
    await _ensureShopExternalExpensesTable(db);
    return db.delete(
      'shop_external_expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getShopExternalExpenses({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    await _ensureShopExternalExpensesTable(db);
    final fromStr = DateTime(from.year, from.month, from.day).toIso8601String();
    final toStr =
        DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT *
      FROM shop_external_expenses
      WHERE datetime(expense_date) >= datetime(?)
        AND datetime(expense_date) <= datetime(?)
      ORDER BY datetime(expense_date) DESC, id DESC
      ''',
      [fromStr, toStr],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getShopPaidPurchases({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await database;
    await _ensurePurchaseReceiptsTable(db);
    await _ensurePurchaseReceiptsColumns(db);
    final fromStr = DateTime(from.year, from.month, from.day).toIso8601String();
    final toStr =
        DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final rows = await db.rawQuery(
      '''
      SELECT *,
             CASE
               WHEN (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0)) > 0
               THEN (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0))
               ELSE COALESCE(paid_amount,0)
             END AS paid_total
      FROM purchase_receipts
      WHERE datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
        AND (
          (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0)) > 0
          OR COALESCE(paid_amount,0) > 0
        )
      ORDER BY datetime(created_at) DESC, id DESC
      ''',
      [fromStr, toStr],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> getDailyShopProfitReport({
    required int year,
    required int month,
  }) async {
    final db = await database;
    await _ensureSaleItemsPurchasePriceColumn(db);
    await _ensureSaleReturnsColumns(db);
    await _ensurePurchaseReceiptsTable(db);
    await _ensurePurchaseReceiptsColumns(db);

    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 0, 23, 59, 59);
    final fromStr = from.toIso8601String();
    final toStr = to.toIso8601String();

    final salesRows = await db.rawQuery(
      '''
      SELECT date(s.date) AS day,
             SUM((COALESCE(si.price,0) - COALESCE(si.purchase_price_per_unit,0)) * COALESCE(si.quantity,0)) AS sales_profit
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE COALESCE(s.is_return,0) = 0
        AND datetime(s.date) >= datetime(?)
        AND datetime(s.date) <= datetime(?)
      GROUP BY date(s.date)
      ''',
      [fromStr, toStr],
    );

    final returnsRows = await db.rawQuery(
      '''
      SELECT date(sr.date) AS day,
             SUM(COALESCE(sri.qty,0) * (COALESCE(sri.price,0) - COALESCE(si.purchase_price_per_unit,0))) AS returned_profit
      FROM sale_return_items sri
      JOIN sale_returns sr ON sr.id = sri.return_id
      JOIN sale_items si ON si.sale_id = sr.sale_id AND si.product_id = sri.product_id
      WHERE COALESCE(sri.is_replacement,0) = 0
        AND datetime(sr.date) >= datetime(?)
        AND datetime(sr.date) <= datetime(?)
      GROUP BY date(sr.date)
      ''',
      [fromStr, toStr],
    );

    final expensesRows = await db.rawQuery(
      '''
      SELECT date(expense_date) AS day,
             SUM(COALESCE(amount,0)) AS external_expenses
      FROM shop_external_expenses
      WHERE datetime(expense_date) >= datetime(?)
        AND datetime(expense_date) <= datetime(?)
      GROUP BY date(expense_date)
      ''',
      [fromStr, toStr],
    );

    final purchasesRows = await db.rawQuery(
      '''
      SELECT date(created_at) AS day,
             SUM(
               CASE
                 WHEN (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0)) > 0
                 THEN (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0))
                 ELSE COALESCE(paid_amount,0)
               END
             ) AS paid_purchases
      FROM purchase_receipts
      WHERE datetime(created_at) >= datetime(?)
        AND datetime(created_at) <= datetime(?)
        AND (
          (COALESCE(paid_cash,0) + COALESCE(paid_wallet,0)) > 0
          OR COALESCE(paid_amount,0) > 0
        )
      GROUP BY date(created_at)
      ''',
      [fromStr, toStr],
    );

    final salesByDay = <String, double>{};
    for (final row in salesRows) {
      salesByDay[(row['day'] ?? '').toString()] =
          _numFromRow(row, 'sales_profit');
    }

    final returnsByDay = <String, double>{};
    for (final row in returnsRows) {
      returnsByDay[(row['day'] ?? '').toString()] =
          _numFromRow(row, 'returned_profit').abs();
    }

    final expensesByDay = <String, double>{};
    for (final row in expensesRows) {
      expensesByDay[(row['day'] ?? '').toString()] =
          _numFromRow(row, 'external_expenses');
    }

    final paidPurchasesByDay = <String, double>{};
    for (final row in purchasesRows) {
      paidPurchasesByDay[(row['day'] ?? '').toString()] =
          _numFromRow(row, 'paid_purchases');
    }

    final daysInMonth = DateTime(year, month + 1, 0).day;
    final out = <Map<String, dynamic>>[];
    for (var day = 1; day <= daysInMonth; day++) {
      final d = DateTime(year, month, day);
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final grossProfit = salesByDay[key] ?? 0.0;
      final returnsProfit = returnsByDay[key] ?? 0.0;
      final externalExpenses = expensesByDay[key] ?? 0.0;
      final paidPurchases = paidPurchasesByDay[key] ?? 0.0;
      final shopProfit = grossProfit - returnsProfit;
      out.add({
        'date': key,
        'gross_profit': grossProfit,
        'returns_profit': returnsProfit,
        'profit': shopProfit,
        'external_expenses': externalExpenses,
        'paid_purchases': paidPurchases,
        'net_profit': shopProfit - externalExpenses - paidPurchases,
      });
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> getStockReport() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        *,
        (COALESCE(quantity,0) * COALESCE(units_in_carton,1) + COALESCE(units_remainder,0)) AS total_units,
        CASE
          WHEN COALESCE(units_in_carton,0) > 0
          THEN COALESCE(purchase_price,0) / units_in_carton
          ELSE COALESCE(purchase_price,0)
        END AS unit_purchase_price,
        ((COALESCE(quantity,0) * COALESCE(units_in_carton,1) + COALESCE(units_remainder,0)) *
          CASE
            WHEN COALESCE(units_in_carton,0) > 0
            THEN COALESCE(purchase_price,0) / units_in_carton
            ELSE COALESCE(purchase_price,0)
          END
        ) AS inventory_value
      FROM products
      ORDER BY name COLLATE NOCASE ASC
      ''',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
