// settings_page_server.dart
import 'package:cashgo/utils/colors.dart';
import 'package:cashgo/widgets/custom_button.dart';
import 'package:cashgo/widgets/custom_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/app_settings_controller.dart';
import '../../services/Api/Admin/settings.dart';
import '../../services/db/db_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String _adminUsername = '';
  bool _loadingAdmin = true;

  List<Map<String, dynamic>> _cashiers = [];
  bool _loadingCashiers = false;

  String? _adminPassword;

  final TextEditingController _adminOldPassController = TextEditingController();
  final TextEditingController _adminNewUserController = TextEditingController();
  final TextEditingController _adminNewPassController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _shopAddressController = TextEditingController();
  final TextEditingController _shopPhoneController = TextEditingController();
  final _adminFormKey = GlobalKey<FormState>();
  bool _settingsLoading = false;
  bool _lightMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadAdmin();
    _loadShopSettings();
  }

  Future<void> _loadShopSettings() async {
    setState(() => _settingsLoading = true);
    try {
      final settings = await DBHelper.instance.getShopSettings();
      final theme = await DBHelper.instance.getThemePreference();
      _shopNameController.text = settings['shop_name'] ?? 'CashGo';
      _shopAddressController.text = settings['shop_address'] ?? '';
      _shopPhoneController.text = settings['shop_phone'] ?? '';
      _lightMode = theme == 'light';
    } finally {
      if (mounted) setState(() => _settingsLoading = false);
    }
  }

  Future<void> _saveShopSettings() async {
    await DBHelper.instance.saveShopSettings(
      shopName: _shopNameController.text,
      address: _shopAddressController.text,
      phone: _shopPhoneController.text,
    );
    _showSnack('تم حفظ إعدادات المتجر');
  }

  Future<void> _setLightMode(bool value) async {
    setState(() => _lightMode = value);
    await AppSettingsController.setThemeMode(
      value ? ThemeMode.light : ThemeMode.dark,
    );
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

  bool _truthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  Future<void> _loadAdmin() async {
    setState(() => _loadingAdmin = true);
    try {
      final users = await ApiService.getUsers();
      if (kDebugMode) print('DEBUG getUsers (admin): $users');
      final admin = users.firstWhere((u) => (u['role'] ?? '') == 'admin',
          orElse: () => {});
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
      final cashiers =
          users.where((u) => (u['role'] ?? '') == 'cashier').toList();
      // تضيف حقول محلية: selected و parse للصلاحيات إن وُجدت
      final parsed = List<Map<String, dynamic>>.from(cashiers).map((c) {
        final m = Map<String, dynamic>.from(c);
        m['selected'] = m['selected'] ?? false;
        // توقع أن الصلاحيات يمكن أن تكون Map أو List — نحول ل Map مع مفاتيح ثابتة
        final perms = <String, bool>{
          'invoice_log': false,
          'receive_from_suppliers': false,
          'pay_credit': false,
          'discount': false,
          'can_view_credit': false,
        };
        if (m['permissions'] != null) {
          final p = m['permissions'];
          if (p is Map) {
            perms['invoice_log'] = _truthy(p['invoice_log']);
            perms['receive_from_suppliers'] =
                _truthy(p['receive_from_suppliers']);
            perms['pay_credit'] = _truthy(p['pay_credit']);
            perms['discount'] = _truthy(p['discount']);
            perms['can_view_credit'] = _truthy(p['can_view_credit']);
          } else if (p is List) {
            // لو جت كـ List من مفاتيح
            perms['invoice_log'] = p.contains('invoice_log');
            perms['receive_from_suppliers'] =
                p.contains('receive_from_suppliers');
            perms['pay_credit'] = p.contains('pay_credit');
            perms['discount'] = p.contains('discount');
            perms['can_view_credit'] = p.contains('can_view_credit');
          }
        }
        perms['can_view_credit'] =
            perms['can_view_credit'] == true || _truthy(m['can_view_credit']);
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
    if (_adminPassword != null && _adminPassword!.isNotEmpty)
      return _adminPassword;
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Text('مطلوب كلمة مرور المشرف',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('أدخل كلمة مرور المشرف لتنفيذ العملية',
              style: TextStyle(color: AppColorsDark.mainTextLight)),
          const SizedBox(height: 8),
          CustomFormField(
            controller: ctrl,
            hint: 'كلمة المرور',
            isPassword: true,
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                      fontSize: 17))),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: Text('تأكيد',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white,
                      fontSize: 17))),
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
        'لم يتم العثور على مشرف',
      );
      return;
    }

    try {
      final adminRecUsers = await ApiService.getUsers();
      final adminRec = adminRecUsers
          .firstWhere((u) => (u['role'] ?? '') == 'admin', orElse: () => {});
      if (adminRec.isEmpty || adminRec['id'] == null) {
        _showSnack('سجل المشرف غير موجود');
        return;
      }
      final adminId = _toIntId(adminRec['id']);

      if (newUser != _adminUsername && newUser.isNotEmpty) {
        final exists = adminRecUsers
            .where((u) => (u['username'] ?? '') == newUser)
            .isNotEmpty;
        if (exists) {
          _showSnack('اسم المستخدم الجديد مستخدم بالفعل');
          return;
        }
      }

      final pass = await _requireAdminPassword();
      if (pass == null) {
        _showSnack('تم إلغاء العملية');
        return;
      }

      await ApiService.updateUser(adminId,
          username: newUser,
          password: newPass.isEmpty ? null : newPass,
          adminUser: _adminUsername,
          adminPass: pass);

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
      'pay_credit': false,
      'discount': false,
      'can_view_credit': false,
    };

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Center(
            child: Text('إضافة كاشير جديد',
                style: TextStyle(color: AppColorsDark.mainTextDark))),
        content: StatefulBuilder(builder: (context, setStateDialog) {
          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomFormField(
                      controller: usernameCtrl,
                      hint: 'اسم المستخدم',
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى ادخال اسم المستخدم'
                          : null),
                  const SizedBox(height: 10),
                  CustomFormField(
                      controller: passwordCtrl,
                      isPassword: true,
                      hint: 'كلمة المرور',
                      validator: (v) => (v == null || v.trim().length < 3)
                          ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل'
                          : null),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerRight,
                      child: Text('الصلاحيات (اختياري)',
                          style:
                              TextStyle(color: AppColorsDark.mainTextLight))),
                  CheckboxListTile(
                    value: perms['invoice_log'],
                    onChanged: (v) =>
                        setStateDialog(() => perms['invoice_log'] = v ?? false),
                    title: Text('سجل الفواتير',
                        style: TextStyle(color: AppColorsDark.mainTextDark)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['receive_from_suppliers'],
                    onChanged: (v) => setStateDialog(
                        () => perms['receive_from_suppliers'] = v ?? false),
                    title: Text('استلام من الموردين',
                        style: TextStyle(color: AppColorsDark.mainTextDark)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['pay_credit'],
                    onChanged: (v) =>
                        setStateDialog(() => perms['pay_credit'] = v ?? false),
                    title: Text('دفع الآجل',
                        style: TextStyle(color: AppColorsDark.mainTextDark)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                  CheckboxListTile(
                    value: perms['can_view_credit'],
                    onChanged: (v) => setStateDialog(
                        () => perms['can_view_credit'] = v ?? false),
                    title: Text('عرض الفواتير الآجلة',
                        style: TextStyle(color: AppColorsDark.mainTextDark)),
                    controlAffinity: ListTileControlAffinity.leading,
                    tileColor: Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          CustomButton(
              infinity: false,
              text: 'إضافة',
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final username = usernameCtrl.text.trim();
                final password = passwordCtrl.text.trim();
                try {
                  final pass = await _requireAdminPassword();
                  if (pass == null) {
                    _showSnack('تم إلغاء العملية');
                    return;
                  }
                  await ApiService.createUser(username, password,
                      role: 'cashier',
                      adminUser: _adminUsername,
                      adminPass: pass,
                      extraBody: {'permissions': perms});
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
    final TextEditingController usernameCtrl =
        TextEditingController(text: cashier['username'] ?? '');
    final TextEditingController passwordCtrl = TextEditingController();

    // احتفظ بنسخة متغيرة من الصلاحيات على مستوى الدالة
    Map<String, bool> perms =
        Map<String, bool>.from(cashier['permissions_parsed'] ??
            {
              'invoice_log': false,
              'receive_from_suppliers': false,
              'pay_credit': false,
              'discount': false,
              'can_view_credit': false,
            });

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColorsDark.bgColor,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Center(
              child: Text('تعديل كاشير',
                  style: TextStyle(color: AppColorsDark.mainTextDark))),
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
                      Tab(
                          child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              child: Text('البيانات'))),
                      Tab(
                          child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              child: Text('الصلاحيات'))),
                    ],
                    // خصائص متطابقة مع الـ TabBar في AppBar
                    labelColor: AppColorsDark.mainTextDark,
                    unselectedLabelColor: AppColorsDark.mainTextLight,
                    overlayColor: MaterialStatePropertyAll(Colors.transparent),
                    indicator: BoxDecoration(
                      border:
                          Border.all(color: AppColorsDark.mainColor, width: 2),
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
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'يرجى ادخال اسم المستخدم'
                                          : null,
                                ),
                                const SizedBox(height: 10),
                                CustomFormField(
                                  controller: passwordCtrl,
                                  isPassword: true,
                                  hint:
                                      'كلمة المرور (اتركها فارغة إذا لا تريد تغييرها)',
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
                                      onChanged: (v) => setStatePerm(() =>
                                          perms['invoice_log'] = v ?? false),
                                      title: Text('سجل الفواتير',
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    // باقي الـ CheckboxListTile كما في الكود الأصلي...
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['receive_from_suppliers'],
                                      onChanged: (v) => setStatePerm(() =>
                                          perms['receive_from_suppliers'] =
                                              v ?? false),
                                      title: Text('استلام من الموردين',
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['pay_credit'],
                                      onChanged: (v) => setStatePerm(() =>
                                          perms['pay_credit'] = v ?? false),
                                      title: Text('دفع الآجل',
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['can_view_credit'],
                                      onChanged: (v) => setStatePerm(() =>
                                          perms['can_view_credit'] =
                                              v ?? false),
                                      title: Text('عرض الفواتير الآجلة',
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      tileColor: Colors.transparent,
                                    ),
                                    CheckboxListTile(
                                      activeColor: AppColorsDark.mainColor,
                                      value: perms['discount'],
                                      onChanged: (v) => setStatePerm(
                                          () => perms['discount'] = v ?? false),
                                      title: Text('الخصم',
                                          style: TextStyle(
                                              color:
                                                  AppColorsDark.mainTextDark)),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
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
            style: TextButton.styleFrom(
                backgroundColor: AppColorsDark.bgCardColor),
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء',
                style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.black
                        : Colors.white)),
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
                if (pass == null) {
                  _showSnack('تم إلغاء العملية');
                  return;
                }

                if (kDebugMode)
                  print('DEBUG saving perms for user $id : $perms');

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
        title: Center(
            child: Text('حذف كاشير',
                style: TextStyle(color: AppColorsDark.mainTextDark))),
        content: Text(
            'هل تريد حذف ${cashier['username']}؟ هذه العملية لا يمكن التراجع عنها.',
            style: TextStyle(color: AppColorsDark.mainTextDark)),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                  backgroundColor: AppColorsDark.bgCardColor),
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.black
                          : Colors.white))),
          CustomButton(
              infinity: false,
              text: 'حذف',
              onPressed: () async {
                Navigator.pop(context, true);
              }),
        ],
      ),
    );

    if (res == true) {
      try {
        final id = _toIntId(cashier['id']);
        final pass = await _requireAdminPassword();
        if (pass == null) {
          _showSnack('تم إلغاء الحذف');
          return;
        }
        await ApiService.deleteUser(id,
            adminUser: _adminUsername, adminPass: pass);
        await _loadCashiers();
      } catch (e) {
        _showSnack('فشل الحذف: ${e.toString()}');
        _clearAdminPassword();
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Directionality(
        textDirection: TextDirection.rtl,
        child: Text(
          msg,
          textAlign: TextAlign.right,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorsDark.bgColor,
      appBar: AppBar(
        iconTheme: IconThemeData(color: AppColorsDark.mainTextLight),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        scrolledUnderElevation: 0.0,
        elevation: 0.0,
        title: Text('الإعدادات',
            style: TextStyle(color: AppColorsDark.mainTextDark, fontSize: 25)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColorsDark.mainTextDark,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          unselectedLabelColor: AppColorsDark.mainTextLight,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          indicator: BoxDecoration(
              border: Border.all(color: AppColorsDark.mainColor, width: 2),
              borderRadius: BorderRadius.circular(12)),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          tabs: const [
            Tab(
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'المشرف',
                      style: TextStyle(fontSize: 17),
                    ))),
            Tab(
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'الكاشير',
                      style: TextStyle(fontSize: 17),
                    ))),
            Tab(
                child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'المتجر',
                      style: TextStyle(fontSize: 17),
                    ))),
          ],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [
        _buildAdminTab(),
        _buildCashierTab(),
        _buildShopSettingsTab(),
      ]),
    );
  }

  Widget _buildAdminTab() {
    if (_loadingAdmin) return const Center(child: CircularProgressIndicator());
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // كارت معلومات المشرف الحالية
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColorsDark.mainColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColorsDark.mainColor.withOpacity(0.15),
                  child: Icon(Icons.admin_panel_settings_rounded,
                      color: AppColorsDark.mainColor, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المشرف الحالي',
                        style: TextStyle(
                            color: AppColorsDark.mainTextLight, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(_adminUsername,
                        style: TextStyle(
                            color: AppColorsDark.mainTextDark,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // فورم التعديل
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Form(
              key: _adminFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تعديل البيانات',
                      style: TextStyle(
                          color: AppColorsDark.mainTextDark,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 14),
                  CustomFormField(
                    controller: _adminNewUserController,
                    hint: 'اسم المستخدم',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'يرجى ادخال اسم المستخدم'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  CustomFormField(
                    controller: _adminNewPassController,
                    isPassword: true,
                    hint: 'كلمة المرور الجديدة',
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'يجب أن تكون كلمة المرور 3 أحرف على الأقل'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  CustomButton(text: 'حفظ التغييرات', onPressed: _changeAdminInfo),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCashierTab() {
    if (_loadingCashiers)
      return const Center(child: CircularProgressIndicator());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_cashiers.length} كاشير',
                style: TextStyle(
                    color: AppColorsDark.mainTextLight, fontSize: 13),
              ),
              ElevatedButton.icon(
                onPressed: _showAddCashierDialog,
                icon: const Icon(Icons.person_add_rounded,
                    size: 16, color: Colors.white),
                label: const Text('إضافة كاشير',
                    style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColorsDark.mainColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cashiers.isEmpty
              ? Center(
              child: Text('لا يوجد كاشير مضاف',
                  style: TextStyle(color: AppColorsDark.mainTextLight)))
              : RefreshIndicator(
            onRefresh: _loadCashiers,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _cashiers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, idx) {
                final c = _cashiers[idx];
                final perms = (c['permissions_parsed']
                as Map<String, bool>?) ??
                    {};
                final activePerms = <String>[];
                if (perms['invoice_log'] == true)
                  activePerms.add('سجل الفواتير');
                if (perms['receive_from_suppliers'] == true)
                  activePerms.add('استلام موردين');
                if (perms['pay_credit'] == true)
                  activePerms.add('دفع الآجل');
                if (perms['discount'] == true) activePerms.add('خصم');
                if (perms['can_view_credit'] == true)
                  activePerms.add('عرض الآجل');

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColorsDark.bgCardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                        AppColorsDark.mainColor.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor:
                            AppColorsDark.mainColor.withOpacity(0.15),
                            child: Text(
                              (c['username'] ?? '?')
                                  .toString()
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                  color: AppColorsDark.mainColor,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c['username'] ?? '',
                              style: TextStyle(
                                  color: AppColorsDark.mainTextDark,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit_rounded,
                                color: AppColorsDark.mainColor, size: 20),
                            onPressed: () => _showEditCashierDialog(c),
                            tooltip: 'تعديل',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded,
                                color: Colors.redAccent, size: 20),
                            onPressed: () => _confirmDeleteCashier(c),
                            tooltip: 'حذف',
                          ),
                        ],
                      ),
                      if (activePerms.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: activePerms.map((p) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColorsDark.mainColor
                                    .withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColorsDark.mainColor
                                        .withOpacity(0.3)),
                              ),
                              child: Text(p,
                                  style: TextStyle(
                                      color: AppColorsDark.mainColor,
                                      fontSize: 11)),
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text('لا توجد صلاحيات مخصصة',
                            style: TextStyle(
                                color: AppColorsDark.mainTextLight,
                                fontSize: 11)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildShopSettingsTab() {
    if (_settingsLoading)
      return const Center(child: CircularProgressIndicator());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // بيانات المتجر
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storefront_rounded,
                        color: AppColorsDark.mainColor, size: 18),
                    const SizedBox(width: 8),
                    Text('بيانات المتجر',
                        style: TextStyle(
                            color: AppColorsDark.mainTextDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 14),
                CustomFormField(
                  controller: _shopNameController,
                  hint: 'اسم المتجر',
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _shopAddressController,
                  hint: 'العنوان',
                ),
                const SizedBox(height: 10),
                CustomFormField(
                  controller: _shopPhoneController,
                  hint: 'رقم الهاتف',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: 'حفظ إعدادات المتجر',
                  onPressed: _saveShopSettings,
                  color: AppColorsDark.mainColor.withOpacity(0.8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // المظهر
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColorsDark.bgCardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _lightMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: _lightMode ? Colors.amberAccent : Colors.blueAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المظهر',
                          style: TextStyle(
                              color: AppColorsDark.mainTextDark,
                              fontWeight: FontWeight.bold)),
                      Text(_lightMode ? 'الوضع الفاتح' : 'الوضع الداكن',
                          style: TextStyle(
                              color: AppColorsDark.mainTextLight, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: _lightMode,
                  onChanged: _setLightMode,
                  activeColor: AppColorsDark.mainColor,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _adminOldPassController.dispose();
    _adminNewUserController.dispose();
    _adminNewPassController.dispose();
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _shopPhoneController.dispose();
    super.dispose();
  }
}
