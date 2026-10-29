import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'local_json_storage.dart';

class LocalJsonAuthApi extends AuthApi {
  LocalJsonAuthApi({
    LocalJsonStorage? storage,
    this.fileName = 'campusfind_users.json',
  }) : _storage = storage ?? LocalJsonStorage();

  final LocalJsonStorage _storage;
  final String fileName;
  Map<String, dynamic>? _cachedDatabase;

  static const String defaultVerificationCode = '123456';

  Future<Map<String, dynamic>> _loadDatabase() async {
    if (_cachedDatabase != null) return _cachedDatabase!;
    final data = await _storage.readJsonMap(fileName);
    if (data != null && data['users'] is List) {
      _cachedDatabase = data;
      return _cachedDatabase!;
    }

    final initialDb = <String, dynamic>{
      'version': 1,
      'nextUserId': 2,
      'users': <dynamic>[
        <String, dynamic>{
          'id': '1',
          'name': 'Campus Student',
          'email': 'student@campus.edu',
          'password': _hashPassword('password123'),
          'isVerified': true,
          'verificationCode': defaultVerificationCode,
          'phone': '09171234567',
          'facebookLink': '',
          'instagramLink': '',
          'createdAt': DateTime.now().toIso8601String(),
        },
      ],
    };

    _cachedDatabase = initialDb;
    await _storage.writeJsonMap(fileName, initialDb);
    return initialDb;
  }

  Future<void> _saveDatabase() async {
    if (_cachedDatabase != null) {
      await _storage.writeJsonMap(fileName, _cachedDatabase!);
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode('campus_salt_$password');
    return sha256.convert(bytes).toString();
  }

  bool _matchesPassword(String inputPassword, dynamic storedPassword) {
    if (storedPassword is! String) return false;
    return storedPassword == _hashPassword(inputPassword) ||
        storedPassword == inputPassword;
  }

  List<dynamic> _usersList(Map<String, dynamic> db) {
    final list = db['users'];
    if (list is List) return list;
    final newList = <dynamic>[];
    db['users'] = newList;
    return newList;
  }

  Map<String, dynamic>? _findUserByEmail(List<dynamic> users, String email) {
    final normalized = email.trim().toLowerCase();
    for (final entry in users) {
      if (entry is Map) {
        final entryEmail = entry['email']?.toString().toLowerCase();
        if (entryEmail == normalized) {
          return entry.cast<String, dynamic>();
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _findUserById(List<dynamic> users, String id) {
    for (final entry in users) {
      if (entry is Map) {
        if (entry['id']?.toString() == id) {
          return entry.cast<String, dynamic>();
        }
      }
    }
    return null;
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (name.trim().length < 2 || name.trim().length > 100) {
      throw const AuthApiException(
        'Enter a name between 2 and 100 characters.',
        statusCode: 400,
      );
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const AuthApiException(
        'Enter a valid email address.',
        statusCode: 400,
      );
    }
    if (password.length < 8) {
      throw const AuthApiException(
        'Password must be at least 8 characters.',
        statusCode: 400,
      );
    }
    if (password != confirmPassword) {
      throw const AuthApiException(
        'Passwords do not match.',
        statusCode: 400,
      );
    }

    final db = await _loadDatabase();
    final users = _usersList(db);

    if (_findUserByEmail(users, normalizedEmail) != null) {
      throw const AuthApiException(
        'An account with this email already exists.',
        statusCode: 409,
      );
    }

    final nextId = db['nextUserId'] ?? (users.length + 1);
    db['nextUserId'] = (nextId is int ? nextId : int.parse('$nextId')) + 1;

    final user = <String, dynamic>{
      'id': '$nextId',
      'name': name.trim(),
      'email': normalizedEmail,
      'password': _hashPassword(password),
      'isVerified': false,
      'verificationCode': defaultVerificationCode,
      'phone': '',
      'facebookLink': '',
      'instagramLink': '',
      'createdAt': DateTime.now().toIso8601String(),
    };

    users.add(user);
    await _saveDatabase();

    debugPrint(
      '[CampusFind Local JSON] Registered $normalizedEmail. Verification code: $defaultVerificationCode (saved to $fileName)',
    );
  }

  @override
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    final db = await _loadDatabase();
    final users = _usersList(db);
    final user = _findUserByEmail(users, email);

    if (user == null) {
      throw const AuthApiException(
        'Invalid or expired verification code.',
        statusCode: 400,
      );
    }

    final storedCode = user['verificationCode'] as String? ?? defaultVerificationCode;
    final enteredCode = code.trim();

    if (enteredCode != storedCode && enteredCode != defaultVerificationCode) {
      throw const AuthApiException(
        'Invalid or expired verification code.',
        statusCode: 400,
      );
    }

    user['isVerified'] = true;
    user['verifiedAt'] = DateTime.now().toIso8601String();
    await _saveDatabase();

    final token = 'local-session-${user['id']}';
    return AuthSession(token: token, user: _toPublicUser(user));
  }

  @override
  Future<void> resendVerification(String email) async {
    final db = await _loadDatabase();
    final users = _usersList(db);
    final user = _findUserByEmail(users, email);

    if (user != null && user['isVerified'] != true) {
      user['verificationCode'] = defaultVerificationCode;
      await _saveDatabase();
      debugPrint(
        '[CampusFind Local JSON] Resent code for $email: $defaultVerificationCode',
      );
    }
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final db = await _loadDatabase();
    final users = _usersList(db);
    final user = _findUserByEmail(users, email);

    if (user == null || !_matchesPassword(password, user['password'])) {
      throw const AuthApiException(
        'Email or password is incorrect.',
        statusCode: 401,
      );
    }

    if (user['isVerified'] != true) {
      throw const AuthApiException(
        'Verify your email before signing in.',
        statusCode: 403,
      );
    }

    final token = 'local-session-${user['id']}';
    return AuthSession(token: token, user: _toPublicUser(user));
  }

  @override
  Future<Map<String, dynamic>> getMe([String? token]) async {
    final db = await _loadDatabase();
    final users = _usersList(db);

    if (token != null && token.startsWith('local-session-')) {
      final userId = token.replaceFirst('local-session-', '');
      final user = _findUserById(users, userId);
      if (user != null) return _toPublicUser(user);
    }

    for (final entry in users) {
      if (entry is Map && entry['isVerified'] == true) {
        return _toPublicUser(entry.cast<String, dynamic>());
      }
    }

    if (users.isNotEmpty && users.first is Map) {
      return _toPublicUser((users.first as Map).cast<String, dynamic>());
    }

    throw const AuthApiException('User not found.', statusCode: 404);
  }

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? token,
    required String name,
    required String email,
    required String phone,
    required String facebookLink,
    required String instagramLink,
  }) async {
    final db = await _loadDatabase();
    final users = _usersList(db);

    Map<String, dynamic>? user;
    if (token != null && token.startsWith('local-session-')) {
      final userId = token.replaceFirst('local-session-', '');
      user = _findUserById(users, userId);
    }
    user ??= users.isNotEmpty && users.first is Map
        ? (users.first as Map).cast<String, dynamic>()
        : null;

    if (user == null) {
      throw const AuthApiException('User not found.', statusCode: 404);
    }

    final normalizedEmail = email.trim().toLowerCase();
    for (final entry in users) {
      if (entry is Map && entry['id'] != user['id']) {
        if (entry['email']?.toString().toLowerCase() == normalizedEmail) {
          throw const AuthApiException(
            'An account with this email already exists.',
            statusCode: 409,
          );
        }
      }
    }

    user['name'] = name.trim();
    user['email'] = normalizedEmail;
    user['phone'] = phone.trim();
    user['facebookLink'] = facebookLink.trim();
    user['instagramLink'] = instagramLink.trim();

    await _saveDatabase();
    return _toPublicUser(user);
  }

  @override
  Future<void> logout([String? token]) async {}

  @override
  Future<void> requestPasswordReset(String email) async {
    final db = await _loadDatabase();
    final users = _usersList(db);
    final user = _findUserByEmail(users, email);

    if (user != null) {
      user['resetCode'] = '654321';
      await _saveDatabase();
      debugPrint('[CampusFind Local JSON] Reset code for $email: 654321');
    }
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    if (password != confirmPassword) {
      throw const AuthApiException('Passwords do not match.', statusCode: 400);
    }
    final db = await _loadDatabase();
    final users = _usersList(db);
    final user = _findUserByEmail(users, email);

    if (user == null || (user['resetCode'] != code && code != '654321')) {
      throw const AuthApiException(
        'Invalid or expired password reset code.',
        statusCode: 400,
      );
    }

    user['password'] = _hashPassword(password);
    user.remove('resetCode');
    await _saveDatabase();
  }

  Map<String, dynamic> _toPublicUser(Map<String, dynamic> raw) => {
        'id': '${raw['id']}',
        'name': raw['name'] ?? '',
        'email': raw['email'] ?? '',
        'isVerified': raw['isVerified'] == true,
        'phone': raw['phone'] ?? '',
        'facebookLink': raw['facebookLink'] ?? '',
        'instagramLink': raw['instagramLink'] ?? '',
      };
}

