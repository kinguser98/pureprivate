import 'package:hive/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 3)
class User {
  @HiveField(0)
  final int id;
  
  @HiveField(1)
  final String username;
  
  @HiveField(2)
  final String? email;
  
  @HiveField(3)
  final String? token;
  
  @HiveField(4)
  final String? role;

  User({
    required this.id,
    required this.username,
    this.email,
    this.token,
    this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'],
      token: json['token'],
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'token': token,
      'role': role,
    };
  }

  bool get isAdmin => role == 'admin';
  
  @override
  String toString() => 'User(id: $id, username: $username, isAdmin: $isAdmin)';
}
