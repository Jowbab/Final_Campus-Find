import 'package:campus_find/auth_store.dart';
import 'package:campus_find/home_screen.dart';
import 'package:campus_find/item_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_auth_api.dart';

void main() {
  testWidgets('shows the reference home grid and filters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: ItemStore(seed: sampleItems()),
          authStore: AuthStore(api: FakeAuthApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lost & Found'), findsOneWidget);
    expect(find.text('Black wallet'), findsOneWidget);
    expect(find.text('House keys'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Lost'), findsOneWidget);
    expect(find.text('Found'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('bottom tabs open messages and editable profile fields', (
    tester,
  ) async {
    final authStore = AuthStore(api: FakeAuthApi());
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: ItemStore(seed: sampleItems()),
          authStore: authStore,
          accountName: 'Campus User',
          onSignOut: authStore.signOut,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Messages').last);
    await tester.pumpAndSettle();
    expect(find.text('No messages yet.'), findsOneWidget);

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Facebook profile link'), findsOneWidget);
    expect(find.text('Instagram profile link'), findsOneWidget);
    expect(find.text('Save profile'), findsOneWidget);
  });

  testWidgets('Report tab opens the existing report form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: ItemStore(seed: sampleItems()),
          authStore: AuthStore(api: FakeAuthApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report').last);
    await tester.pumpAndSettle();
    expect(find.text('Report an item'), findsOneWidget);
  });
}
