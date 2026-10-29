import 'package:campus_find/auth_store.dart';
import 'package:campus_find/item_store.dart';
import 'package:campus_find/login_screen.dart';
import 'package:campus_find/main.dart';
import 'package:campus_find/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_api.dart';

void main() {
  testWidgets('shows the login page after the splash screen', (tester) async {
    await tester.pumpWidget(
      CampusFindApp(
        store: ItemStore(seed: []),
        authStore: AuthStore(api: FakeAuthApi()),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
