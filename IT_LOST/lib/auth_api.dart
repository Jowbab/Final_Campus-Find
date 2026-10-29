import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'auth_http_client.dart';

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String? token;
  final Map<String, dynamic> user;
}

class AuthApi {
  AuthApi({http.Client? client, String? baseUrl})
    : _client = client ?? createAuthHttpClient(),
      _baseUrl = resolveAuthApiBaseUrl(
        configuredUrl: baseUrl ?? const String.fromEnvironment('AUTH_API_URL'),
      );

  final http.Client _client;
  final String _baseUrl;
  static const _timeout = Duration(seconds: 15);

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    await _request(
      'POST',
      '/auth/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'confirmPassword': confirmPassword,
      },
    );
  }

  Future<AuthSession> verifyEmail({
    required String email,
    required String code,
  }) async => _parseSession(
    await _request(
      'POST',
      '/auth/verify-email',
      body: {'email': email, 'code': code},
    ),
  );

  Future<void> resendVerification(String email) async {
    await _request(
      'POST',
      '/auth/resend-verification',
      body: {'email': email},
    );
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async => _parseSession(
    await _request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    ),
  );

  Future<Map<String, dynamic>> getMe([String? token]) async {
    final result = await _request('GET', '/auth/me', token: token);
    return _parseUser(result['user']);
  }

  Future<void> requestPasswordReset(String email) async {
    await _request(
      'POST',
      '/auth/password-reset/request',
      body: {'email': email},
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String confirmPassword,
  }) async {
    await _request(
      'POST',
      '/auth/password-reset/confirm',
      body: {
        'email': email,
        'code': code,
        'password': password,
        'confirmPassword': confirmPassword,
      },
    );
  }

  Future<Map<String, dynamic>> updateProfile({
    String? token,
    required String name,
    required String email,
    required String phone,
    required String facebookLink,
    required String instagramLink,
  }) async {
    final result = await _request(
      'PUT',
      '/auth/profile',
      token: token,
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'facebookLink': facebookLink,
        'instagramLink': instagramLink,
      },
    );
    return _parseUser(result['user']);
  }

  Future<void> logout([String? token]) async {
    await _request('POST', '/auth/logout', token: token);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object>? body,
    String? token,
  }) async {
    try {
      final headers = <String, String>{'content-type': 'application/json'};
      if (token != null) headers['authorization'] = 'Bearer $token';
      final uri = Uri.parse('$_baseUrl$path');
      final response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
        _ => _client.post(uri, headers: headers, body: jsonEncode(body)),
      }.timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final decoded = _decodeMap(response.body);
        final message = decoded?['error'];
        throw AuthApiException(
          message is String ? message : 'Unable to complete your request.',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode == 204 || response.body.isEmpty) return {};
      final decoded = _decodeMap(response.body);
      if (decoded == null) {
        throw const AuthApiException('The server returned an invalid response.');
      }
      return decoded;
    } on AuthApiException {
      rethrow;
    } on TimeoutException {
      throw const AuthApiException('The server took too long to respond.');
    } on http.ClientException {
      throw const AuthApiException(
        'Could not reach the server. Check that it is running and try again.',
      );
    } catch (_) {
      throw const AuthApiException(
        'Could not reach the server. Check the API address and your connection.',
      );
    }
  }

  AuthSession _parseSession(Map<String, dynamic> result) {
    final token = result['token'];
    if ((!kIsWeb && (token is! String || token.isEmpty)) ||
        (token != null && token is! String)) {
      throw const AuthApiException('The server returned an invalid session.');
    }
    return AuthSession(
      token: token as String?,
      user: _parseUser(result['user']),
    );
  }

  Map<String, dynamic> _parseUser(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const AuthApiException('The server returned invalid account details.');
    }
    return value;
  }

  Map<String, dynamic>? _decodeMap(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

String resolveAuthApiBaseUrl({
  String? configuredUrl,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  final configured = configuredUrl?.trim() ?? '';
  if (configured.isNotEmpty) return configured.replaceFirst(RegExp(r'/$'), '');
  if (isWeb) return 'http://localhost:3000';

  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'http://10.0.2.2:3000',
    TargetPlatform.iOS => 'http://127.0.0.1:3000',
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => 'http://127.0.0.1:3000',
    _ => 'http://127.0.0.1:3000',
  };
}
