import 'dart:convert';

import 'package:campus_find/auth_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AuthApi', () {
    test('sends registration fields to the backend', () async {
      late http.Request capturedRequest;
      final api = AuthApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({'message': 'Check your email for a verification code.'}),
            201,
          );
        }),
      );

      await api.register(
        name: 'User',
        email: 'user@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      expect(capturedRequest.url.path, '/auth/register');
      expect(jsonDecode(capturedRequest.body), {
        'name': 'User',
        'email': 'user@example.com',
        'password': 'password123',
        'confirmPassword': 'password123',
      });
    });

    test('sends verification code and parses the server session', () async {
      late http.Request capturedRequest;
      final api = AuthApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'token': 'server-session-token',
              'user': {
                'id': '4',
                'name': 'User',
                'email': 'user@example.com',
                'isVerified': true,
              },
            }),
            200,
          );
        }),
      );

      final session = await api.verifyEmail(
        email: 'user@example.com',
        code: '123456',
      );

      expect(capturedRequest.url.path, '/auth/verify-email');
      expect(jsonDecode(capturedRequest.body), {
        'email': 'user@example.com',
        'code': '123456',
      });
      expect(session.token, 'server-session-token');
      expect(session.user['id'], '4');
    });

    test('sends resend-verification request', () async {
      late http.Request capturedRequest;
      final api = AuthApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'message': 'If this address needs verification, a code has been sent.',
            }),
            202,
          );
        }),
      );

      await api.resendVerification('user@example.com');

      expect(capturedRequest.url.path, '/auth/resend-verification');
      expect(jsonDecode(capturedRequest.body), {'email': 'user@example.com'});
    });

    test('surfaces duplicate-email conflict from API', () async {
      final api = AuthApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'An account with this email already exists.'}),
            409,
          ),
        ),
      );

      await expectLater(
        api.register(
          name: 'User',
          email: 'user@example.com',
          password: 'password123',
          confirmPassword: 'password123',
        ),
        throwsA(
          isA<AuthApiException>()
              .having((error) => error.statusCode, 'statusCode', 409)
              .having((error) => error.message, 'message', contains('already exists')),
        ),
      );
    });

    test('sends authenticated profile changes', () async {
      late http.Request capturedRequest;
      final api = AuthApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({
              'user': {
                'id': '4',
                'name': 'User',
                'email': 'user@example.com',
                'phone': '09171234567',
              },
            }),
            200,
          );
        }),
      );

      final user = await api.updateProfile(
        token: 'server-session-token',
        name: 'User',
        email: 'user@example.com',
        phone: '09171234567',
        facebookLink: '',
        instagramLink: '',
      );

      expect(capturedRequest.method, 'PUT');
      expect(capturedRequest.url.path, '/auth/profile');
      expect(capturedRequest.headers['authorization'], 'Bearer server-session-token');
      expect(user['phone'], '09171234567');
    });
  });

  group('resolveAuthApiBaseUrl', () {
    test('uses platform-specific development hosts', () {
      expect(
        resolveAuthApiBaseUrl(platform: TargetPlatform.android, isWeb: false),
        'http://10.0.2.2:3000',
      );
      expect(
        resolveAuthApiBaseUrl(platform: TargetPlatform.windows, isWeb: false),
        'http://127.0.0.1:3000',
      );
      expect(
        resolveAuthApiBaseUrl(platform: TargetPlatform.windows, isWeb: true),
        'http://localhost:3000',
      );
    });

    test('uses configured API URL when provided', () {
      expect(
        resolveAuthApiBaseUrl(configuredUrl: 'https://api.example.test/'),
        'https://api.example.test',
      );
    });
  });
}
