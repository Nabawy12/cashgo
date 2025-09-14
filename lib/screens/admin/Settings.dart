import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../services/Api/Admin/settings.dart';
import '../../services/db/db_helper.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Admin info
  int? _adminId;
  String _adminUsername = '';

  // cashiers list
  List<Map<String, dynamic>> _cashiers = [];
  bool _loading = true;

  // controllers for admin form
  final TextEditingController _adminOldPassController = TextEditingController();
  final TextEditingController _adminNewUserController = TextEditingController();
  final TextEditingController _adminNewPassController = TextEditingController();
  final _adminFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await _loadAdmin();
    await _loadCashiers();
    setState(() => _loading = false);
  }

  Future<void> _loadAdmin() async {
    final db = await DBHelper.instance.database;
    final rows = await db.query('users', where: "role = ?", whereArgs: ['admin'], limit: 1);
    if (rows.isNotEmpty) {
      final r = rows.first;
      setState(() {
        _adminId = (r['id'] as num).toInt();
        _adminUsername = (r['username'] ?? '').toString();
        _adminNewUserController.text = _adminUsername;
      });
    }
  }

  Future<void> _loadCashiers() async {
    final db = await DBHelper.instance.database;
    final rows = await db.query('users', where: "role = ?", whereArgs: ['cashier'], orderBy: 'username');
    setState(() {
      _cashiers = rows;
    });
  }

  // ---------------- Admin actions ----------------
  Future<void> _changeAdminInfo() async {
    if (!_adminFormKey.currentState!.validate()) return;
    final oldPass = _adminOldPassController.text.trim();
    final newUser = _adminNewUserController.text.trim();
    final newPass = _adminNewPassController.text.trim();

    if (_adminId == null) {
      _showSnack('Admin user not found');
      return;
    }

    // verify old password using existing login() method
    final verified = await DBHelper.instance.login(_adminUsername, oldPass);
    if (verified == null) {
      _showSnack('كلمة المرور القديمة غير صحيحة');
      return;
    }

    final db = await DBHelper.instance.database;
    // check if username change collides with existing username
    if (newUser != _adminUsername) {
      final exists = await db.query('users', where: 'username = ?', whereArgs: [newUser], limit: 1);
      if (exists.isNotEmpty) {
        _showSnack('اسم المستخدم الجديد مستخدم بالفعل');
        return;
      }
    }

    // apply update inside a transaction
    await db.transaction((txn) async {
      // لو غير الاسم أو الباسورد
      final oldUsername = _adminUsername;

      if (newPass.isNotEmpty) {
        await txn.update('users', {'password': newPass}, where: 'id = ?', whereArgs: [_adminId]);
      }
      if (newUser.isNotEmpty && newUser != oldUsername) {
        await txn.update('users', {'username': newUser}, where: 'id = ?', whereArgs: [_adminId]);

        // propagate username to related tables
        await txn.update('sales', {'cashier_username': newUser}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
        await txn.update('sale_returns', {'cashier_username': newUser}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
        await txn.update('purchase_receipts', {'received_by': newUser}, where: 'received_by = ?', whereArgs: [oldUsername]);
        await txn.update('cash_drawer', {'updated_by': newUser}, where: 'updated_by = ?', whereArgs: [oldUsername]);
      }
    });

    _adminUsername = newUser;
    _adminOldPassController.clear();
    _adminNewPassController.clear();

    _showSnack('تم تحديث بيانات المشرف بنجاح');
    setState(() {});
  }

  // ---------------- Cashiers CRUD ----------------
  Future<void> _showAddCashierDialog() async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController usernameCtrl = TextEditingController();
    final TextEditingController passwordCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Center(child: Text(
            'إضافة كاشير جديد',
          style: TextStyle(
            color: Colors.white
          ),
        )
        ),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomFormField(
                  controller: usernameCtrl,
                  hint: 'اسم المستخدم',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال اسم المستخدم' : null,
              ),
              const SizedBox(height: 10),
              CustomFormField(
                controller: passwordCtrl,
                isPassword: true,
                hint: 'كلمة المرور',
                validator: (v) => (v == null || v.trim().length < 3) ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor,
              ),
              onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء',style: TextStyle(color: Colors.white),)
          ),
          CustomButton(
              infinity: false,
              text: 'إضافة',
              onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              final username = usernameCtrl.text.trim();
              final password = passwordCtrl.text.trim();
              try {
                await _createUser(username, password, role: 'cashier');
                Navigator.pop(context, true);
              } catch (e) {
                _showSnack('فشل الإضافة: ${e.toString()}');
              }
            },
          ),
        ],
      ),
    );

    if (res == true) await _loadCashiers();
  }

  Future<void> _showEditCashierDialog(Map<String, dynamic> cashier) async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController usernameCtrl = TextEditingController(text: cashier['username'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Center(child: Text('تعديل كاشير',style: TextStyle(color: Colors.white),)),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomFormField(
                controller: usernameCtrl,
                hint: 'اسم المستخدم',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال اسم المستخدم' : null,
              ),
              const SizedBox(height: 10),
              CustomFormField(
                controller: passwordCtrl,
                isPassword: true,
                hint: 'كلمة المرور (اتركها فارغة إذا لا تريد تغييرها)',
              ),
              SizedBox(height: 10,),
            ],
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor,
              ),
              onPressed: () => Navigator.pop(context, false), child: Text('إلغاء',style: TextStyle(color: Colors.white),)),
          CustomButton(
              infinity: false,
              text: 'حفظ',
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              final username = usernameCtrl.text.trim();
              final password = passwordCtrl.text.trim();
              try {
                await _updateUser(cashier['id'] as int, username: username, password: password.isEmpty ? null : password);
                Navigator.pop(context, true);
              } catch (e) {
                _showSnack('فشل التعديل: ${e.toString()}');
              }
            },
          ),
        ],
      ),
    );

    if (res == true) await _loadCashiers();
  }

  Future<void> _confirmDeleteCashier(Map<String, dynamic> cashier) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Center(child: const Text('حذف كاشير',style: TextStyle(color: Colors.white),)),
        content: Text('هل تريد حذف ${cashier['username']}؟ هذه العملية لا يمكن التراجع عنها.',style: TextStyle(color: Colors.white),),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: AppColorsDark.bgCardColor
            ),
              onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء',style: TextStyle(color: Colors.white),)),
          CustomButton(
              infinity: false,
              text: 'حذف',
            onPressed: () async {
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );

    if (res == true) {
      await _deleteUser(cashier['id'] as int);
      await _loadCashiers();
    }
  }

  // ---------------- DB helpers for users (simple CRUD) ----------------
  Future<int> _createUser(String username, String password, {required String role}) async {
    final db = await DBHelper.instance.database;
    // check duplicate
    final exists = await db.query('users', where: 'username = ?', whereArgs: [username], limit: 1);
    if (exists.isNotEmpty) throw 'اسم المستخدم موجود بالفعل';

    return await db.insert('users', {
      'username': username,
      'password': password,
      'role': role,
    });
  }

  Future<int> _updateUser(int id, {String? username, String? password}) async {
    final db = await DBHelper.instance.database;

    // get old username
    final oldRows = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    if (oldRows.isEmpty) return 0;
    final oldUsername = (oldRows.first['username'] ?? '').toString();

    // check duplicate if username changed
    if (username != null) {
      final rows = await db.query('users', where: 'username = ? AND id != ?', whereArgs: [username, id], limit: 1);
      if (rows.isNotEmpty) throw 'اسم المستخدم هذا مستخدم من قبل';
    }

    return await db.transaction<int>((txn) async {
      if (password != null) {
        await txn.update('users', {'password': password}, where: 'id = ?', whereArgs: [id]);
      }
      if (username != null && username.isNotEmpty && username != oldUsername) {
        await txn.update('users', {'username': username}, where: 'id = ?', whereArgs: [id]);

        // propagate to other tables
        await txn.update('sales', {'cashier_username': username}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
        await txn.update('sale_returns', {'cashier_username': username}, where: 'cashier_username = ?', whereArgs: [oldUsername]);
        await txn.update('purchase_receipts', {'received_by': username}, where: 'received_by = ?', whereArgs: [oldUsername]);
        await txn.update('cash_drawer', {'updated_by': username}, where: 'updated_by = ?', whereArgs: [oldUsername]);
      }
      return 1;
    });
  }

  Future<int> _deleteUser(int id) async {
    final db = await DBHelper.instance.database;
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- UI helpers ----------------
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: Colors.white70
        ),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        scrolledUnderElevation: 0.0,
        elevation: 0.0,
        title: const Text('الإعدادات',style: TextStyle(color: Colors.white,fontSize: 25),),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          indicator: BoxDecoration(
            border: Border.all(color: AppColorsDark.mainColor, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          tabs: const [
            Tab(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), // padding داخلي
                child: Text('المشرف'),
              ),
            ),
            Tab(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('الكاشير'),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildAdminTab(),
          _buildCashierTab(),
        ],
      ),
    );
  }

  Widget _buildAdminTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text(
                'تعديل بيانات المشرف',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white
                )
            )
            ),
            const SizedBox(height: 12),
            Form(
              key: _adminFormKey,
              child: Column(
                children: [
                  CustomFormField(
                      controller: _adminNewUserController,
                      hint: 'اسم المستخدم',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال اسم المستخدم' : null,
                  ),
                  const SizedBox(height: 10),
                  CustomFormField(
                    controller: _adminOldPassController,
                    isPassword: true,
                    hint: 'كلمة المرور القديمة (للتاكيد)',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال كلمة المرور القديمة' : null,
                  ),
                  const SizedBox(height: 10),
                  CustomFormField(
                    controller: _adminNewPassController,
                    isPassword: true,
                    hint: 'كلمة المرور الجديدة',
                    validator: (v) => (v == null || v.trim().length < 3) ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل' : null,
                  ),
                  const SizedBox(height: 20),
                  CustomButton(
                      text: 'حفظ التغييرات',
                      onPressed: _changeAdminInfo
                  ),
                  // Padding(
                  //   padding: const EdgeInsets.all(12.0),
                  //   child: CustomButton(
                  //     text: 'مزامنة مع السيرفر',
                  //     onPressed: () async {
                  //       await ApiService.syncUsers();
                  //       _showSnack("تمت المزامنة بنجاح");
                  //     },
                  //     color: AppColorsDark.mainColor.withOpacity(0.5),
                  //   ),
                  // ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashierTab() {
    return RefreshIndicator(
      onRefresh: _loadCashiers,
      child: Column(
        children: [
          // زرار اضافة كاشير
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: CustomButton(
              text: 'إضافة كاشير جديد',
              onPressed: _showAddCashierDialog,
              color: AppColorsDark.mainColor.withOpacity(0.5),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _cashiers.length,
              itemBuilder: (context, idx) {
                final c = _cashiers[idx];
                return Card(
                  color: AppColorsDark.bgCardColor,
                  child: ListTile(
                    leading: const Icon(Icons.person, color: Colors.white),
                    title: Text(
                      c['username'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 17),
                    ),
                    subtitle: Text(
                      'id: ${c['id'] ?? ''}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditCashierDialog(c),
                          color: Colors.white70,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _confirmDeleteCashier(c),
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _adminOldPassController.dispose();
    _adminNewUserController.dispose();
    _adminNewPassController.dispose();
    super.dispose();
  }
}
