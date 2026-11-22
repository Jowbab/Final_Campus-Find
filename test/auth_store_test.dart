import 'package:campus_find/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_api.dart';

void main() {
  group('AuthStore', () {
    test('registers an account, verifies email, and signs in', () async {
      final store = AuthStore(api: FakeAuthApi());

      final registerError = await store.register(
        name: 'Campus User',
        email: 'User@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      expect(registerError, isNull);
      expect(store.isSignedIn, isFalse);

      final verifyError = await store.verifyEmail(
        email: 'User@example.com',
        code: '123456',
      );

      expect(verifyError, isNull);
      expect(store.isSignedIn, isTrue);
      expect(store.accountName, 'Campus User');
      expect(store.accountEmail, 'user@example.com');
      expect(store.token, isNotNull);
    });

    test('signs in using verified account email', () async {
      final api = FakeAuthApi();
      final store = AuthStore(api: api);
      await store.register(
        name: 'Campus User',
        email: 'User@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await store.verifyEmail(email: 'user@example.com', code: '123456');
      await store.signOut();

      final error = await store.signIn(
        email: ' user@EXAMPLE.com ',
        password: 'password123',
      );

      expect(error, isNull);
      expect(store.isSignedIn, isTrue);
    });

    test('blocks sign-in for unverified account', () async {
      final store = AuthStore(api: FakeAuthApi());
      await store.register(
        name: 'Pending User',
        email: 'pending@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      final error = await store.signIn(
        email: 'pending@example.com',
        password: 'password123',
      );

      expect(error, 'Email or password is incorrect.');
      expect(store.isSignedIn, isFalse);
    });

    test('reports duplicate email and invalid credentials from API', () async {
      final store = AuthStore(api: FakeAuthApi());
      await store.register(
        name: 'Campus User',
        email: 'user@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await store.verifyEmail(email: 'user@example.com', code: '123456');
      await store.signOut();

      expect(
        await store.register(
          name: 'Another User',
          email: 'USER@example.com',
          password: 'password456',
          confirmPassword: 'password456',
        ),
        'An account with this email already exists.',
      );
      expect(
        await store.signIn(email: 'user@example.com', password: 'wrong-password'),
        'Email or password is incorrect.',
      );
      expect(store.isSignedIn, isFalse);
    });

    test('resends verification code successfully', () async {
      final store = AuthStore(api: FakeAuthApi());
      await store.register(
        name: 'Resend User',
        email: 'resend@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      final error = await store.resendVerification('resend@example.com');
      expect(error, isNull);
    });

    test('saves profile contact and social links to the API', () async {
      final store = AuthStore(api: FakeAuthApi());
      await store.register(
        name: 'Campus User',
        email: 'user@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await store.verifyEmail(email: 'user@example.com', code: '123456');

      final error = await store.updateProfile(
        name: 'Updated User',
        email: 'UPDATED@example.com',
        phone: '+639171234567',
        facebookLink: 'https://facebook.com/updated.user',
        instagramLink: 'https://instagram.com/updated.user',
      );

      expect(error, isNull);
      expect(store.accountName, 'Updated User');
      expect(store.accountEmail, 'updated@example.com');
      expect(store.accountPhone, '+639171234567');
      expect(store.facebookLink, 'https://facebook.com/updated.user');
      expect(store.instagramLink, 'https://instagram.com/updated.user');
    });
  });
}
