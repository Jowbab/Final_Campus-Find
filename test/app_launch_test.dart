import 'package:campus_find/auth_store.dart';
import 'package:campus_find/home_screen.dart';
import 'package:campus_find/item_store.dart';
import 'package:campus_find/login_screen.dart';
import 'package:campus_find/main.dart';
import 'package:campus_find/splash_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_api.dart';

void main() {
  testWidgets('shows the login page after the splash screen', (tester) async {
    await tester.pumpWidget(
      CampusFindApp(
        store: ItemStore(seed: []),
        authStore: AuthStore(
          api: FakeAuthApi(),
          storage: _MemorySecureStorage(),
        ),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('shows login instead of restoring a saved session',
      (tester) async {
    final api = FakeAuthApi();
    final storage = _MemorySecureStorage();
    final initialAuthStore = AuthStore(api: api, storage: storage);
    await initialAuthStore.register(
      name: 'Campus User',
      email: 'user@example.com',
      password: 'password123',
      confirmPassword: 'password123',
    );
    await initialAuthStore.verifyEmail(
      email: 'user@example.com',
      code: '123456',
    );

    await tester.pumpWidget(
      CampusFindApp(
        store: ItemStore(seed: []),
        authStore: AuthStore(api: api, storage: storage),
      ),
    );

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}
