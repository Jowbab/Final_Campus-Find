import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_store.dart';
import 'home_screen.dart';
import 'item_store.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final authStore = AuthStore();
  final itemStore = ItemStore();
  runApp(
    CampusFindApp(
      store: itemStore,
      authStore: authStore,
    ),
  );
}

class CampusFindApp extends StatelessWidget {
  const CampusFindApp({
    super.key,
    required this.store,
    required this.authStore,
  }); 

  final ItemStore store;
  final AuthStore authStore;

  @override
  Widget build(BuildContext context) {
    const canvas = Color(0xFFF4F6F9);
    const primary = Color(0xFF2186E5);
    return MaterialApp(
      title: 'CampusFind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: Color(0xFF202124),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: Color(0xFF737B88)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFFE0E4E9)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: Color(0xFFE0E4E9)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? primary
                  : const Color(0xFF737B88),
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
      home: _AppGate(store: store, authStore: authStore),
    );
  }
}

class _AppGate extends StatefulWidget {
  const _AppGate({required this.store, required this.authStore});

  final ItemStore store;
  final AuthStore authStore;

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _splashComplete = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.authStore.restore(restoreExistingSession: false));
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) {
      return SplashScreen(
        onFinished: () => setState(() => _splashComplete = true),
      );
    }

    return ListenableBuilder(
      listenable: widget.authStore,
      builder: (context, _) {
        if (widget.authStore.isSignedIn) {
          return HomeScreen(
            store: widget.store,
            authStore: widget.authStore,
            accountName: widget.authStore.accountName,
            onSignOut: widget.authStore.signOut,
          );
        }

        return LoginScreen(authStore: widget.authStore);
      },
    );
  }
}
