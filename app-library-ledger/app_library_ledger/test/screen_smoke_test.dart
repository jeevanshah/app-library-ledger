// Runtime smoke tests for the screens touched during the UIUX overhaul pass.
//
// flutter analyze cannot catch Flutter-runtime widget-tree assertions (e.g. a
// Positioned that isn't a direct Stack child, or a DropdownButton/showDatePicker
// value that doesn't match its constraints) — those only surface when the
// widget tree is actually built and interacted with. These tests exercise the
// exact edge cases that previously crashed the app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_library_ledger/models/app_model.dart';
import 'package:app_library_ledger/models/category_model.dart';
import 'package:app_library_ledger/screens/add_app_screen.dart';
import 'package:app_library_ledger/screens/categories_screen.dart';
import 'package:app_library_ledger/screens/library_screen.dart';
import 'package:app_library_ledger/screens/onboarding_screen.dart';
import 'package:app_library_ledger/screens/splash_screen.dart';
import 'package:app_library_ledger/services/storage_service.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LibraryScreen', () {
    testWidgets('renders a list card for an app with a past renewal date', (
      tester,
    ) async {
      // Regression test for the Positioned-inside-Row crash: Positioned must
      // be a direct Stack child, and this only throws when the card actually
      // builds/lays out.
      final storage = StorageService();
      await storage.init();
      await storage.saveApp(
        AppEntry(
          name: 'Netflix',
          appStoreLink: 'https://netflix.com',
          category: 'Media / Streaming',
          isActiveSubscription: true,
          subscriptionCost: 15.49,
          billingCycle: 'monthly',
          nextRenewalDate: DateTime.now().subtract(const Duration(days: 3)),
        ),
      );

      await tester.pumpWidget(_wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Netflix'), findsOneWidget);
    });

    testWidgets('renders empty state with zero apps/categories', (
      tester,
    ) async {
      final storage = StorageService();
      await storage.init();

      await tester.pumpWidget(_wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to the Dashboard tab renders without error', (
      tester,
    ) async {
      final storage = StorageService();
      await storage.init();
      await storage.saveApp(
        AppEntry(
          name: 'Spotify',
          appStoreLink: 'https://spotify.com',
          category: 'Media / Streaming',
          isActiveSubscription: true,
          subscriptionCost: 11.99,
          billingCycle: 'monthly',
          nextRenewalDate: DateTime.now().add(const Duration(days: 10)),
        ),
      );

      await tester.pumpWidget(_wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.show_chart_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('AddAppScreen', () {
    testWidgets('add mode with zero categories does not crash', (tester) async {
      // Regression test: DropdownButton/category picker used to assert when
      // no category existed to select.
      await tester.pumpWidget(_wrap(const AddAppScreen(categories: [])));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Select a category'), findsOneWidget);
    });

    testWidgets('editing an app whose category was deleted resolves safely', (
      tester,
    ) async {
      // Regression test: editing an app whose `category` string no longer
      // exists in the categories list used to crash the dropdown.
      final orphanedApp = AppEntry(
        name: 'Old App',
        appStoreLink: 'https://example.com',
        category: 'DeletedCategory',
        isActiveSubscription: true,
        subscriptionCost: 4.99,
        billingCycle: 'monthly',
        nextRenewalDate: DateTime.now().subtract(const Duration(days: 5)),
      );

      await tester.pumpWidget(
        _wrap(
          AddAppScreen(
            categories: [Category(name: 'Productivity', color: Colors.indigo)],
            appToEdit: orphanedApp,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the renewal date field with a past due date opens the '
        'picker without throwing', (tester) async {
      // Regression test: showDatePicker asserted when initialDate (the
      // stored past-due date) was before firstDate (today).
      final app = AppEntry(
        name: 'Adobe CC',
        appStoreLink: 'https://adobe.com',
        category: 'Productivity',
        isActiveSubscription: true,
        subscriptionCost: 54.99,
        billingCycle: 'monthly',
        nextRenewalDate: DateTime.now().subtract(const Duration(days: 30)),
      );

      await tester.pumpWidget(
        _wrap(
          AddAppScreen(
            categories: [Category(name: 'Productivity', color: Colors.indigo)],
            appToEdit: app,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_today_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The native date-picker dialog should be showing.
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('quick-add tile fills the form without crashing', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const AddAppScreen(categories: [])));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Netflix').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('CategoriesScreen', () {
    testWidgets('renders with a mix of in-use and empty categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CategoriesScreen(
            categories: [
              Category(name: 'Productivity', color: Colors.indigo),
              Category(name: 'Travel', color: Colors.teal),
            ],
            spending: const {'Productivity': 74.99},
            appCounts: const {'Productivity': 2},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Productivity'), findsOneWidget);
      expect(find.text('Travel'), findsOneWidget);
    });
  });

  group('OnboardingScreen', () {
    testWidgets('renders all four pages without error', (tester) async {
      var completed = false;
      await tester.pumpWidget(
        _wrap(OnboardingScreen(onComplete: () => completed = true)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(completed, isFalse);
    });
  });

  group('SplashScreen', () {
    testWidgets(
      'disposing before the delayed animation callbacks fire does not throw',
      (tester) async {
        // Regression test: Future.delayed(...).then(_textCtrl.forward()) /
        // _ringCtrl callbacks fired without a mounted guard and could hit a
        // disposed AnimationController.
        await tester.pumpWidget(_wrap(SplashScreen(onComplete: () {})));
        await tester.pump(const Duration(milliseconds: 100));

        // Replace the widget tree before the 400ms/600ms delayed callbacks
        // fire, forcing SplashScreen.dispose() while they're still pending.
        await tester.pumpWidget(_wrap(const SizedBox()));

        // Let every still-pending timer (400ms, 600ms, 2000ms) actually
        // elapse so none are left dangling at test teardown — the mounted
        // guard should make each a no-op instead of throwing.
        await tester.pump(const Duration(seconds: 3));

        expect(tester.takeException(), isNull);
      },
    );
  });
}
