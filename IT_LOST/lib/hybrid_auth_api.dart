import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'local_json_auth_api.dart';

class HybridAuthApi extends AuthApi {
  HybridAuthApi({
    required this.remoteApi,
    required this.localApi,
  });

  final AuthApi remoteApi;
  final LocalJsonAuthApi localApi;
  bool _useLocalOnly = false;

  bool _isConnectionError(Object error) {
    if (error is AuthApiException) {
      final msg = error.message.toLowerCase();
      return msg.contains('could not reach the server') ||
          msg.contains('connection') ||
          msg.contains('failed host lookup') ||
          msg.contains('refused') ||
          msg.contains('timeout');
    }
    return error is TimeoutException;
  }

  Future<T> _run<T>(
    Future<T> Function(AuthApi api) action, {
    required Future<T> Function() onLocalFallback,
  }) async {
    if (_useLocalOnly) {
      return onLocalFallback();
    }
    try {
      return await action(remoteApi);
    } catch (e) {
      if (_isConnectionError(e)) {
        debugPrint(
          '[HybridAuthApi] Server unreachable. Switching seamlessly to local JSON storage.',
        );
        _useLocalOnly = true;
        return onLocalFallback();
      }
      rethrow;
    }
  }

  @override
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) =>
      _run(
        (api) => api.register(
          name: name,
          email: email,
          password: password,
          confirmPassword: confirmPassword,
        ),
        onLocalFallback: () => localApi.register(
          name: name,
          email: email,
          password: password,
          confirmPassword: confirmPassword,
        ),
      );

  @override
  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) =>
      _run(
        (api) => api.verifyEmail(email: email, code: code),
        onLocalFallback: () => localApi.verifyEmail(email: email, code: code),
      );

  @override
  Future<void> resendVerification(String email) => _run(
        (api) => api.resendVerification(email),
        onLocalFallback: () => localApi.resendVerification(email),
      );

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) =>
      _run(
        (api) => api.login(email: email, password: password),
        onLocalFallback: () => localApi.login(email: email, password: password),
      );

  @override
  Future<Map<String, dynamic>> getMe([String? token]) => _run(
        (api) => api.getMe(token),
        onLocalFallback: () => localApi.getMe(token),
      );

  @override
  Future<Map<String, dynamic>> updateProfile({
    String? token,
    required String name,
    required String email,
    required String phone,
    required String facebookLink,
    required String instagramLink,
  }) =>
      _run(
        (api) => api.updateProfile(
          token: token,
          name: name,
          email: email,
          phone: phone,
          facebookLink: facebookLink,
          instagramLink: instagramLink,
        ),
        onLocalFallback: () => localApi.updateProfile(
          token: token,
          name: name,
          email: email,
          phone: phone,
          facebookLink: facebookLink,
          instagramLink: instagramLink,
        ),
      );

  @override
  Future<void> logout([String? token]) async {
    await _run(
      (api) => api.logout(token),
      onLocalFallback: () => localApi.logout(token),
    );
  }

  @override
  Future<void> requestPasswordReset(String email) => _run(
        (api) => api.requestPasswordReset(email),
        onLocalFallback: () => localApi.requestPasswordReset(email),
      );

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) =>
      _run(
        (api) => api.resetPassword(
          email: email,
          code: code,
          password: password,
          confirmPassword: confirmPassword,
        ),
        onLocalFallback: () => localApi.resetPassword(
          email: email,
          code: code,
          password: password,
          confirmPassword: confirmPassword,
        ),
      );
}

