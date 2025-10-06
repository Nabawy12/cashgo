// settings_page_server.dart
import 'dart:convert';
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/Api/Admin/settings.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _adminUsername = '';
  bool _loadingAdmin = true;

  List<Map<String, dynamic>> _cashiers = [];
  bool _loadingCashiers = false;

  String? _adminPassword;

  final TextEditingController _adminOldPassController = TextEditingController();
  final TextEditingController _adminNewUserController = TextEditingController();
  final TextEditingController _adminNewPassController = TextEditingController();
  final _adminFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadAdmin();
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      if (!_loadingCashiers && _cashiers.isEmpty) _loadCashiers();
    }
  }

  // تحويل آمن لأنواع id المختلفة
  int _toIntId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.parse(v);
    throw Exception('Invalid id type: ${v.runtimeType}');
  }

  Future<void> _loadAdmin() async {
    setState(() => _loadingAdmin = true);
    try {
      final users = await ApiService.getUsers();
      if (kDebugMode) print('DEBUG getUsers (admin): $users');
      final admin = users.firstWhere((u) => (u['role'] ?? '') == 'admin', orElse: () => {});
      if (admin.isNotEmpty) {
        _adminUsername = (admin['username'] ?? '').toString();
        _adminNewUserController.text = _adminUsername;
      } else {
        _adminUsername = '';
        _adminNewUserController.clear();
      }
    } catch (e) {
      _showSnack('فشل تحميل بيانات المشرف: ${e.toString()}');
    } finally {
      setState(() => _loadingAdmin = false);
    }
  }

  Future<void> _loadCashiers() async {
    setState(() => _loadingCashiers = true);
    try {
      final users = await ApiService.getUsers();
      if (kDebugMode) print('DEBUG getUsers (cashiers): $users');
      final cashiers = users.where((u) => (u['role'] ?? '') == 'cashier').toList();
      // تضيف حقول محلية: selected و parse للصلاحيات إن وُجدت
      final parsed = List<Map<String, dynamic>>.from(cashiers).map((c) {
        final m = Map<String, dynamic>.from(c);
        m['selected'] = m['selected'] ?? false;
        // توقع أن الصلاحيات يمكن أن تكون Map أو List — نحول ل Map مع مفاتيح ثابتة
        final perms = <String, bool>{
          'invoice_log': false,
          'receive_from_suppliers': false,
          'wallet_tx': false,
          'pay_credit': false,
          'discount': false,
        };
        if (m['permissions'] != null) {
          final p = m['permissions'];
          if (p is Map) {
            perms['invoice_log'] = (p['invoice_log'] == true);
            perms['receive_from_suppliers'] = (p['receive_from_suppliers'] == true);
            perms['wallet_tx'] = (p['wallet_tx'] == true);
            perms['pay_credit'] = (p['pay_credit'] == true);
            perms['discount'] = (p['discount'] == true);
          } else if (p is List) {
            // لو جت كـ List من مفاتيح
            perms['invoice_log'] = p.contains('invoice_log');
            perms['receive_from_suppliers'] = p.contains('receive_from_suppliers');
            perms['wallet_tx'] = p.contains('wallet_tx');
            perms['pay_credit'] = p.contains('pay_credit');
            perms['discount'] = p.contains('discount');
          }
        }
        m['permissions_parsed'] = perms;
        return m;
      }).toList();
      setState(() => _cashiers = parsed);
    } catch (e) {
      _showSnack('فشل تحميل الكاشير: ${e.toString()}');
    } finally {
      setState(() => _loadingCashiers = false);
    }
  }

  Future<String?> _requireAdminPassword() async {
    if (_adminPassword != null && _adminPassword!.isNotEmpty) return _adminPassword;
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: const Text('مطلوب كلمة مرور المشرف', style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل كلمة مرور المشرف لتنفيذ العملية', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          CustomFormField(
            controller: ctrl,
            hint: 'كلمة المرور',
            isPassword: true,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('إلغاء', style: TextStyle(color: Colors.white,fontSize: 17))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('تأكيد', style: TextStyle(color: Colors.white,fontSize: 17))),
        ],
      ),
    );
    if (res == null || res.isEmpty) return null;
    _adminPassword = res;
    return _adminPassword;
  }

  void _clearAdminPassword() {
    _adminPassword = null;
    _adminOldPassController.clear();
  }

  Future<void> _changeAdminInfo() async {
    if (!_adminFormKey.currentState!.validate()) return;
    final newUser = _adminNewUserController.text.trim();
    final newPass = _adminNewPassController.text.trim();
    if (_adminUsername.isEmpty) {
      _showSnack(
          'لم يتم العثور على مشرف على السيرفر',

      );
      return;
    }

    try {
      final adminRecUsers = await ApiService.getUsers();
      final adminRec = adminRecUsers.firstWhere((u) => (u['role'] ?? '') == 'admin', orElse: () => {});
      if (adminRec.isEmpty || adminRec['id'] == null) {
        _showSnack('سجل المشرف غير موجود في السيرفر');
        return;
      }
      final adminId = _toIntId(adminRec['id']);

      if (newUser != _adminUsername && newUser.isNotEmpty) {
        final exists = adminRecUsers.where((u) => (u['username'] ?? '') == newUser).isNotEmpty;
        if (exists) {
          _showSnack('اسم المستخدم الجديد مستخدم بالفعل');
          return;
        }
      }

      final pass = await _requireAdminPassword();
      if (pass == null) { _showSnack('تم إلغاء العملية'); return; }

      await ApiService.updateUser(adminId, username: newUser, password: newPass.isEmpty ? null : newPass, adminUser: _adminUsername, adminPass: pass);

      _adminUsername = newUser;
      _adminOldPassController.clear();
      _adminNewPassController.clear();
      _showSnack('تم تحديث بيانات المشرف بنجاح');
      await _loadAdmin();
    } catch (e) {
      _showSnack('فشل التحديث: ${e.toString()}');
      _clearAdminPassword();
    }
  }

  Future<void> _showAddCashierDialog() async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController usernameCtrl = TextEditingController();
    final TextEditingController passwordCtrl = TextEditingController();

    // صلاحيات افتراضية
    Map<String, bool> perms = {
      'invoice_log': false,
      'receive_from_suppliers': false,
      'wallet_tx': false,
      'pay_credit': false,
      'discount': false,
    };

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Center(child: Text('إضافة كاشير جديد', style: TextStyle(color: Colors.white))),
        content: StatefulBuilder(builder: (context, setStateDialog) {
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomFormField(controller: usernameCtrl, hint: 'اسم المستخدم', validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال اسم المستخدم' : null),
                  const SizedBox(height: 10),
                  CustomFormField(controller: passwordCtrl, isPassword: true, hint: 'كلمة المرور', validator: (v) => (v == null || v.trim().length < 3) ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل' : null),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: Text('الصلاحيات (اختياري)', style: TextStyle(color: Colors.white70))),
                  CheckboxListTile(
                    value: perms['invoice_log'],
                    onChanged: (v) => setStateDialog(() => perms['invoice_log'] = v ?? false),
                    title: Text('سجل الفواتير', style: TextStyle(color: Colors.white)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['receive_from_suppliers'],
                    onChanged: (v) => setStateDialog(() => perms['receive_from_suppliers'] = v ?? false),
                    title: Text('استلام من الموردين', style: TextStyle(color: Colors.white)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['wallet_tx'],
                    onChanged: (v) => setStateDialog(() => perms['wallet_tx'] = v ?? false),
                    title: Text('سحب وإيداع من المحفظة', style: TextStyle(color: Colors.white)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['pay_credit'],
                    onChanged: (v) => setStateDialog(() => perms['pay_credit'] = v ?? false),
                    title: Text('دفع الكريدت', style: TextStyle(color: Colors.white)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }),
        actions: [
          TextButton(style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor), onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
          CustomButton(infinity: false, text: 'إضافة', onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final username = usernameCtrl.text.trim();
            final password = passwordCtrl.text.trim();
            try {
              final pass = await _requireAdminPassword();
              if (pass == null) { _showSnack('تم إلغاء العملية'); return; }
              await ApiService.createUser(username, password, role: 'cashier', adminUser: _adminUsername, adminPass: pass, extraBody: {'permissions': perms});
              Navigator.pop(context, true);
            } catch (e) {
              _showSnack('فشل الإضافة: ${e.toString()}');
              _clearAdminPassword();
            }
          }),
        ],
      ),
    );

    if (res == true) await _loadCashiers();
  }

  Future<void> _showEditCashierDialog(Map<String, dynamic> cashier) async {
    // مفتاح Form محلي (سيكون متاح طوال حياة الـ dialog)
    final formKey = GlobalKey<FormState>();
    final TextEditingController usernameCtrl = TextEditingController(text: cashier['username'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();

    // احتفظ بنسخة متغيرة من الصلاحيات على مستوى الدالة
    Map<String, bool> perms = Map<String, bool>.from(cashier['permissions_parsed'] ?? {
      'invoice_log': false,
      'receive_from_suppliers': false,
      'wallet_tx': false,
      'pay_credit': false,
      'discount': false,
    });

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Center(child: Text('تعديل كاشير', style: TextStyle(color: Colors.white))),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          // نضع الـ Form حول كل المحتوى حتى يكون currentState موجود دائماً
          child: // داخل _showEditCashierDialog — استبدل الـ DefaultTabController القديم بهذا:
          Form(
            key: formKey,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  // TabBar بنفس ستايل الصفحة
                  TabBar(
                    tabs: const [
                      Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text('البيانات'))),
                      Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text('الصلاحيات'))),
                    ],
                    // خصائص متطابقة مع الـ TabBar في AppBar
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    overlayColor: MaterialStatePropertyAll(Colors.transparent),
                    indicator: BoxDecoration(
                      border: Border.all(color: AppColorsDark.mainColor, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    // لو حابب تشبه بالضبط عدّل padding داخل Tabs كما تريد
                    dividerHeight: 0,
                  ),

                  // المحتوى
                  Expanded(
                    child: TabBarView(
                      children: [
                        // تب البيانات
                        SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: [
                                const SizedBox(height: 20),
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
                              ],
                            ),
                          ),
                        ),

                        // تب الصلاحيات (كما كان)
                        StatefulBuilder(builder: (context, setStatePerm) {
                          return SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: Column(
                                  children: [
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['invoice_log'],
                                      onChanged: (v) => setStatePerm(() => perms['invoice_log'] = v ?? false),
                                      title: Text('سجل الفواتير', style: TextStyle(color: Colors.white)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    // باقي الـ CheckboxListTile كما في الكود الأصلي...
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['receive_from_suppliers'],
                                      onChanged: (v) => setStatePerm(() => perms['receive_from_suppliers'] = v ?? false),
                                      title: Text('استلام من الموردين', style: TextStyle(color: Colors.white)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['wallet_tx'],
                                      onChanged: (v) => setStatePerm(() => perms['wallet_tx'] = v ?? false),
                                      title: Text('سحب وإيداع من المحفظة', style: TextStyle(color: Colors.white)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['pay_credit'],
                                      onChanged: (v) => setStatePerm(() => perms['pay_credit'] = v ?? false),
                                      title: Text('دفع الكريدت', style: TextStyle(color: Colors.white)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['discount'],
                                      onChanged: (v) => setStatePerm(() => perms['discount'] = v ?? false),
                                      title: Text('الخصم', style: TextStyle(color: Colors.white)),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor),
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
          CustomButton(
            infinity: false,
            text: 'حفظ',
            onPressed: () async {
              // تحقق بأمان: formKey قد يكون موجود دائماً لكن نتحقق دفاعياً
              if (formKey.currentState != null) {
                final ok = formKey.currentState!.validate();
                if (!ok) {
                  // إذا فشل التحقق نوقف الحفظ
                  return;
                }
              }

              final username = usernameCtrl.text.trim();
              final password = passwordCtrl.text.trim();

              try {
                if (cashier['id'] == null) {
                  _showSnack('خطأ: id المستخدم غير موجود');
                  return;
                }
                final id = _toIntId(cashier['id']);

                final pass = await _requireAdminPassword();
                if (pass == null) { _showSnack('تم إلغاء العملية'); return; }

                if (kDebugMode) print('DEBUG saving perms for user $id : $perms');

                await ApiService.updateUser(
                  id,
                  username: username.isEmpty ? null : username,
                  password: password.isEmpty ? null : password,
                  adminUser: _adminUsername,
                  adminPass: pass,
                  extraBody: {'permissions': perms},
                );

                // حدّث النسخة المحلية قبل إعادة التحميل أو الإغلاق (أحساس فوري)
                cashier['permissions_parsed'] = Map<String, bool>.from(perms);

                if (kDebugMode) print('DEBUG updateUser succeeded for $id');
                Navigator.pop(context, true);
              } catch (e) {
                _showSnack('فشل التعديل: ${e.toString()}');
                _clearAdminPassword();
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
        title: Center(child: const Text('حذف كاشير', style: TextStyle(color: Colors.white))),
        content: Text('هل تريد حذف ${cashier['username']}؟ هذه العملية لا يمكن التراجع عنها.', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(style: TextButton.styleFrom(backgroundColor: AppColorsDark.bgCardColor), onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white))),
          CustomButton(infinity: false, text: 'حذف', onPressed: () async { Navigator.pop(context, true); }),
        ],
      ),
    );

    if (res == true) {
      try {
        final id = _toIntId(cashier['id']);
        final pass = await _requireAdminPassword();
        if (pass == null) { _showSnack('تم إلغاء الحذف'); return; }
        await ApiService.deleteUser(id, adminUser: _adminUsername, adminPass: pass);
        await _loadCashiers();
      } catch (e) {
        _showSnack('فشل الحذف: ${e.toString()}');
        _clearAdminPassword();
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        msg,
      textAlign: TextAlign.right,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white70),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        scrolledUnderElevation: 0.0,
        elevation: 0.0,
        title: const Text('الإعدادات', style: TextStyle(color: Colors.white, fontSize: 25)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          padding: EdgeInsetsGeometry.symmetric(horizontal: 20),
          unselectedLabelColor: Colors.white70,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          indicator: BoxDecoration(border: Border.all(color: AppColorsDark.mainColor, width: 2), borderRadius: BorderRadius.circular(12)),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          tabs: const [
            Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text('المشرف',style: TextStyle(fontSize: 17),))),
            Tab(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text('الكاشير',style: TextStyle(fontSize: 17),))),
          ],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [_buildAdminTab(), _buildCashierTab()]),
    );
  }

  Widget _buildAdminTab() {
    if (_loadingAdmin) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(child: Text('تعديل بيانات المشرف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
          const SizedBox(height: 20),
          Form(
            key: _adminFormKey,
            child: Column(children: [
              CustomFormField(controller: _adminNewUserController, hint: 'اسم المستخدم', validator: (v) => (v == null || v.trim().isEmpty) ? 'يرجى ادخال اسم المستخدم' : null),
              const SizedBox(height: 10),
              CustomFormField(controller: _adminNewPassController, isPassword: true, hint: 'كلمة المرور الجديدة', validator: (v) => (v == null || v.trim().length < 3) ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل' : null),
              const SizedBox(height: 20),
              CustomButton(text: 'حفظ التغييرات', onPressed: _changeAdminInfo),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildCashierTab() {
    if (_loadingCashiers) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadCashiers,
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(12.0), child: CustomButton(text: 'إضافة كاشير جديد', onPressed: _showAddCashierDialog, color: AppColorsDark.mainColor.withOpacity(0.5))),
        Expanded(child: ListView.builder(padding: const EdgeInsets.all(12), itemCount: _cashiers.length, itemBuilder: (context, idx) {
          final c = _cashiers[idx];
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Card(
              color: AppColorsDark.bgCardColor,
              child: Padding(
                padding: EdgeInsetsGeometry.symmetric(vertical: 15),
                child: ListTile(
                  title: Text(" الاسم:  ${c['username'] ?? ''}", style: const TextStyle(color: Colors.white, fontSize: 19)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditCashierDialog(c), color: Colors.white70,iconSize: 25,),
                    IconButton(icon: const Icon(Icons.delete), onPressed: () => _confirmDeleteCashier(c), color: Colors.red.withOpacity(0.8),iconSize: 25,),
                  ]),
                ),
              ),
            ),
          );
        })),
      ]),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _adminOldPassController.dispose();
    _adminNewUserController.dispose();
    _adminNewPassController.dispose();
    super.dispose();
  }
}
