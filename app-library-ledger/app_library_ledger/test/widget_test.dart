import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_library_ledger/models/app_model.dart';
import 'package:app_library_ledger/models/category_model.dart';
import 'package:app_library_ledger/services/analytics_service.dart';

void main() {
  group('AppEntry', () {
    test('creates with auto-generated id and createdAt', () {
      final app = AppEntry(
        name: 'Netflix',
        appStoreLink: 'https://netflix.com',
        category: 'Media',
      );
      expect(app.id, isNotEmpty);
      expect(app.name, 'Netflix');
      expect(app.createdAt, isNotNull);
    });

    test('toJson and fromJson roundtrip', () {
      final original = AppEntry(
        id: 'test-id',
        name: 'Spotify',
        appStoreLink: 'https://spotify.com',
        category: 'Media / Streaming',
        notes: 'Family plan',
        subscriptionCost: 15.99,
        billingCycle: 'monthly',
        isActiveSubscription: true,
        isPromotionalPrice: true,
        regularPrice: 19.99,
      );
      final json = original.toJson();
      final restored = AppEntry.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.subscriptionCost, original.subscriptionCost);
      expect(restored.isPromotionalPrice, true);
      expect(restored.regularPrice, 19.99);
    });
  });

  group('Category', () {
    test('toJson and fromJson roundtrip', () {
      final original = Category(
        name: 'Custom',
        color: Color(0xFF123456),
        isCustom: true,
      );
      final json = original.toJson();
      final restored = Category.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.isCustom, true);
    });
  });

  group('AnalyticsService', () {
    final analytics = AnalyticsService();

    test('getMonthlyCost for monthly subscription', () {
      final app = AppEntry(
        name: 'Test',
        appStoreLink: '',
        category: 'Test',
        subscriptionCost: 9.99,
        billingCycle: 'monthly',
        isActiveSubscription: true,
      );
      expect(analytics.getMonthlyCost(app), 9.99);
    });

    test('getMonthlyCost for yearly subscription', () {
      final app = AppEntry(
        name: 'Test',
        appStoreLink: '',
        category: 'Test',
        subscriptionCost: 120.0,
        billingCycle: 'yearly',
        isActiveSubscription: true,
      );
      expect(analytics.getMonthlyCost(app), 10.0);
    });

    test('getTotalMonthlyCost sums all active subscriptions', () {
      final apps = [
        AppEntry(
          name: 'A',
          appStoreLink: '',
          category: 'Test',
          subscriptionCost: 10.0,
          billingCycle: 'monthly',
          isActiveSubscription: true,
        ),
        AppEntry(
          name: 'B',
          appStoreLink: '',
          category: 'Test',
          subscriptionCost: 120.0,
          billingCycle: 'yearly',
          isActiveSubscription: true,
        ),
        AppEntry(
          name: 'C',
          appStoreLink: '',
          category: 'Test',
          subscriptionCost: 5.0,
          billingCycle: 'monthly',
          isActiveSubscription: false,
        ),
      ];
      expect(analytics.getTotalMonthlyCost(apps), 20.0); // 10 + (120/12=10)
    });

    test('health score is 100 when no active subscriptions', () {
      final apps = <AppEntry>[];
      expect(analytics.getSubHealthScore(apps), 100.0);
    });

    test('health label returns correct labels', () {
      expect(analytics.getHealthLabel(95), 'Excellent');
      expect(analytics.getHealthLabel(80), 'Good');
      expect(analytics.getHealthLabel(60), 'Fair');
      expect(analytics.getHealthLabel(40), 'Needs Attention');
      expect(analytics.getHealthLabel(20), 'Critical');
    });

    test('generateInsights returns info when no subscriptions', () {
      final insights = analytics.generateInsights([]);
      expect(insights.length, 1);
      expect(insights.first.title, 'Get Started');
    });
  });
}
