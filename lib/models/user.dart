class User {
  final int? id;
  final String username;
  final String password;
  final String role; // 'admin' or 'cashier'

  User(
      {this.id,
      required this.username,
      required this.password,
      required this.role});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'role': role,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int?,
      username: map['username'] as String,
      password: map['password'] as String,
      role: map['role'] as String,
    );
  }
}
