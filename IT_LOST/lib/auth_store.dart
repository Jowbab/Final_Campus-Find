import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_api.dart';
import 'hybrid_auth_api.dart';
import 'local_json_auth_api.dart';

class AuthStore extends ChangeNotifier {
  AuthStore({AuthApi? api, FlutterSecureStorage? storage})
    : _api = api ?? _resolveDefaultAuthApi(),
      _storage = storage ?? const FlutterSecureStorage();

  static AuthApi _resolveDefaultAuthApi() {
    final local = LocalJsonAuthApi();
    const configuredUrl = String.fromEnvironment('AUTH_API_URL');
    if (configuredUrl.isNotEmpty) {
      return HybridAuthApi(
        remoteApi: AuthApi(baseUrl: configuredUrl),
        localApi: local,
      );
    }
    return HybridAuthApi(
      remoteApi: AuthApi(),
      localApi: local,
    );
  }

  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';
  final AuthApi _api;
  final FlutterSecureStorage _storage;
  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = true;

  bool get isSignedIn => _user != null && (kIsWeb || _token != null);
  bool get isLoading => _isLoading;
  String? get token => _token;
  String? get accountName => _user?['name'] as String?;
  String? get accountEmail => _user?['email'] as String?;
  String? get accountPhone => _user?['phone'] as String?;
  String? get facebookLink => _user?['facebookLink'] as String?;
  String? get instagramLink => _user?['instagramLink'] as String?;

  Future<void> restore({bool restoreExistingSession = true}) async {
    try {
      if (restoreExistingSession) {
        _token = kIsWeb ? null : await _storage.read(key: _tokenKey);
        _user = _decodeCachedUser(await _storage.read(key: _userKey));
        if (_token != null || kIsWeb) {
          try {
            _user = await _api.getMe(_token);
            await _cacheUser(_user!);
          } on AuthApiException catch (error) {
            if (error.statusCode == 401) await _clearSession();
          } catch (_) {}
        }
      } else {
        await _clearSession();
      }
    } catch (_) {
      _token = null;
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      await _api.register(
        name: name,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
      );
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not complete registration. Please try again.';
    }
  }

  Future<String?> verifyEmail({
    required String email,
    required String code,
  }) async {
    try {
      await _acceptSession(await _api.verifyEmail(email: email, code: code));
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not verify your email. Please try again.';
    }
  }

  Future<String?> resendVerification(String email) async {
    try {
      await _api.resendVerification(email);
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not resend the verification code.';
    }
  }

  Future<String?> requestPasswordReset(String email) async {
    try {
      await _api.requestPasswordReset(email);
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not request a password reset.';
    }
  }

  Future<String?> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    try {
      await _api.resetPassword(
        email: email,
        code: code,
        password: password,
        confirmPassword: confirmPassword,
      );
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not reset your password.';
    }
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _api.login(email: email, password: password);
      await _acceptSession(session);
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not sign in. Please try again.';
    }
  }

  Future<String?> updateProfile({
    required String name,
    required String email,
    required String phone,
    required String facebookLink,
    required String instagramLink,
  }) async {
    final token = _token;
    if (token == null && !kIsWeb) return 'Sign in to edit your profile.';
    try {
      _user = await _api.updateProfile(
        token: token,
        name: name,
        email: email,
        phone: phone,
        facebookLink: facebookLink,
        instagramLink: instagramLink,
      );
      await _cacheUser(_user!);
      notifyListeners();
      return null;
    } on AuthApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not save your profile. Please try again.';
    }
  }

  Future<void> signOut() async {
    final token = _token;
    await _clearSession();
    _isLoading = false;
    notifyListeners();
    if (token != null || kIsWeb) {
      try {
        await _api.logout(token);
      } catch (_) {}
    }
  }

  Future<void> _acceptSession(AuthSession session) async {
    _token = session.token;
    _user = session.user;
    await _persistSession();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persistSession() async {
    if (kIsWeb) return;
    try {
      if (_token != null) await _storage.write(key: _tokenKey, value: _token);
      await _cacheUser(_user!);
    } catch (_) {}
  }

  Future<void> _cacheUser(Map<String, dynamic> user) async {
    try {
      await _storage.write(key: _userKey, value: jsonEncode(user));
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (_) {}
  }

  Map<String, dynamic>? _decodeCachedUser(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
