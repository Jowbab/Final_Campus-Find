import 'package:campus_find/auth_api.dart';

class FakeAuthApi extends AuthApi {
  final Map<String, Map<String, dynamic>> _users = {};
  final Map<String, String> _passwords = {};
  final Map<String, String> _verificationCodes = {};
  final Map<String, String> _resetCodes = {};
  int _nextId = 1;

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_users.containsKey(normalizedEmail)) {
      throw const AuthApiException(
        'An account with this email already exists.',
        statusCode: 409,
      );
    }
    final user = {
      'id': '${_nextId++}',
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': '',
      'facebookLink': '',
      'instagramLink': '',
      'isVerified': false,
    };
    _users[normalizedEmail] = user;
    _passwords[normalizedEmail] = password;
    _verificationCodes[normalizedEmail] = '123456';
  }

  @override
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_verificationCodes[normalizedEmail] != code) {
      throw const AuthApiException('Invalid or expired verification code.');
    }
    _verificationCodes.remove(normalizedEmail);
    final user = _users[normalizedEmail]!;
    user['isVerified'] = true;
    return AuthSession(token: 'fake-session-${user['id']}', user: user);
  }

  @override
  Future<void> resendVerification(String email) async {
    _verificationCodes[email.trim().toLowerCase()] = '123456';
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final user = _users[email.trim().toLowerCase()];
    if (user == null ||
      user['isVerified'] != true ||
      _passwords[email.trim().toLowerCase()] != password) {
      throw const AuthApiException('Email or password is incorrect.');
    }
    return AuthSession(token: 'fake-session-${user['id']}', user: user);
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
    final current = _users.values.firstWhere(
      (user) => token == 'fake-session-${user['id']}',
    );
    final normalizedEmail = email.trim().toLowerCase();
    if (_users.containsKey(normalizedEmail) &&
        !identical(_users[normalizedEmail], current)) {
      throw const AuthApiException(
        'An account with this email already exists.',
        statusCode: 409,
      );
    }
    final oldEmail = current['email'] as String;
    _users.remove(oldEmail);
    final storedPassword = _passwords.remove(oldEmail);
    current
      ..['name'] = name.trim()
      ..['email'] = normalizedEmail
      ..['phone'] = phone.trim()
      ..['facebookLink'] = facebookLink.trim()
      ..['instagramLink'] = instagramLink.trim();
    _users[normalizedEmail] = current;
    if (storedPassword != null) _passwords[normalizedEmail] = storedPassword;
    return current;
  }

  @override
  Future<Map<String, dynamic>> getMe([String? token]) async => _users.values.firstWhere(
        (user) => token == 'fake-session-${user['id']}',
      );

  @override
  Future<void> logout([String? token]) async {}

  @override
  Future<void> requestPasswordReset(String email) async {
    _resetCodes[email.trim().toLowerCase()] = '654321';
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_resetCodes[normalizedEmail] != code || password != confirmPassword) {
      throw const AuthApiException('Invalid or expired password reset code.');
    }
    _passwords[normalizedEmail] = password;
    _resetCodes.remove(normalizedEmail);
  }
}
