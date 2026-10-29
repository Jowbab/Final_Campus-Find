import 'dart:io';

import 'package:campus_find/auth_api.dart';
import 'package:campus_find/campus_item.dart';
import 'package:campus_find/item_store.dart';
import 'package:campus_find/local_json_auth_api.dart';
import 'package:campus_find/local_json_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late LocalJsonStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('campusfind_test_');
    storage = LocalJsonStorage(customDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalJsonAuthApi', () {
    test('registers a user, requires verification, and signs in', () async {
      final api = LocalJsonAuthApi(storage: storage);

      // Register new user
      await api.register(
        name: 'Alice Campus',
        email: 'ALICE@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      // Verify file was created and contains the unverified user
      final file = File('${tempDir.path}/campusfind_users.json');
      expect(await file.exists(), isTrue);

      // Attempting to login before email verification throws 403
      expect(
        () => api.login(email: 'alice@example.com', password: 'password123'),
        throwsA(
          isA<AuthApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('Verify your email')),
        ),
      );

      // Verify email with code 123456
      final session = await api.verifyEmail(
        email: 'alice@example.com',
        code: '123456',
      );

      expect(session.user['email'], 'alice@example.com');
      expect(session.user['name'], 'Alice Campus');
      expect(session.user['isVerified'], isTrue);
      expect(session.token, isNotNull);

      // Login succeeds now
      final loginSession = await api.login(
        email: ' alice@EXAMPLE.com ',
        password: 'password123',
      );
      expect(loginSession.user['id'], session.user['id']);

      // Profile update works and saves to JSON
      final updatedUser = await api.updateProfile(
        token: loginSession.token,
        name: 'Alice Updated',
        email: 'alice@example.com',
        phone: '+639123456789',
        facebookLink: 'https://facebook.com/alice',
        instagramLink: 'https://instagram.com/alice',
      );
      expect(updatedUser['phone'], '+639123456789');
    });

    test('rejects duplicate email and mismatched passwords', () async {
      final api = LocalJsonAuthApi(storage: storage);

      await api.register(
        name: 'Bob',
        email: 'bob@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      // Duplicate email rejection
      expect(
        () => api.register(
          name: 'Bob Two',
          email: 'BOB@example.com',
          password: 'password456',
          confirmPassword: 'password456',
        ),
        throwsA(
          isA<AuthApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('already exists')),
        ),
      );

      // Mismatched passwords rejection
      expect(
        () => api.register(
          name: 'Charlie',
          email: 'charlie@example.com',
          password: 'password123',
          confirmPassword: 'different-password',
        ),
        throwsA(
          isA<AuthApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('do not match')),
        ),
      );
    });

    test('persists accounts across multiple API instances', () async {
      final api1 = LocalJsonAuthApi(storage: storage);
      await api1.register(
        name: 'Persistent User',
        email: 'persist@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await api1.verifyEmail(email: 'persist@example.com', code: '123456');

      // Reopen storage with fresh API instance
      final api2 = LocalJsonAuthApi(storage: storage);
      final session = await api2.login(
        email: 'persist@example.com',
        password: 'password123',
      );
      expect(session.user['name'], 'Persistent User');
    });
  });

  group('ItemStore with LocalJsonStorage', () {
    test('persists items to JSON and reloads them', () async {
      final store1 = ItemStore(storage: storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Add a custom item
      final newItem = CampusItem(
        id: 'test-item-1',
        title: 'Water Bottle',
        description: 'Stainless steel bottle found in library',
        type: ItemType.found,
        category: ItemCategory.other,
        location: 'Library',
        contact: 'finder@campus.edu',
        postedAt: DateTime.now(),
      );
      store1.add(newItem);

      // Verify file was written
      final file = File('${tempDir.path}/campusfind_items.json');
      expect(await file.exists(), isTrue);

      // Create a second store instance pointing to same storage
      final store2 = ItemStore(storage: storage);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final loadedItem = store2.byId('test-item-1');
      expect(loadedItem, isNotNull);
      expect(loadedItem!.title, 'Water Bottle');
      expect(loadedItem.location, 'Library');
    });
  });
}

