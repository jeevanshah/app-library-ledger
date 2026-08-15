import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../models/spend_ledger_entry.dart';
import 'notification_service.dart';

class StorageService {
  static const String _appsKey = 'apps';
  static const String _categoriesKey = 'categories';
  static const String _ledgerKey = 'spend_ledger';

  static final StorageService _instance = StorageService._internal();

  factory StorageService() {
    return _instance;
  }

  StorageService._internal();

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // App methods
  /// Upsert: replaces the entry with the same id, or appends if new.
  /// (Restored after the folder-flatten recovery reverted this to a
  /// blind add, which made every edit create a duplicate entry.)
  Future<void> saveApp(AppEntry app) async {
    final apps = await getApps();
    final index = apps.indexWhere((a) => a.id == app.id);
    if (index >= 0) {
      apps[index] = app;
    } else {
      apps.add(app);
    }
    await _saveApps(apps);
  }

  Future<void> deleteApp(String id) async {
    final apps = await getApps();
    apps.removeWhere((app) => app.id == id);
    await _saveApps(apps);
  }

  Future<List<AppEntry>> getApps() async {
    final json = _prefs.getString(_appsKey);
    if (json == null) return [];
    final List<dynamic> decoded = jsonDecode(json);
    return decoded.map((e) => AppEntry.fromJson(e)).toList();
  }

  Future<void> _saveApps(List<AppEntry> apps) async {
    final json = jsonEncode(apps.map((e) => e.toJson()).toList());
    await _prefs.setString(_appsKey, json);
  }

  // Category methods
  Future<void> saveCategory(Category category) async {
    final categories = await getCategories();
    final index = categories.indexWhere((c) => c.name == category.name);
    if (index >= 0) {
      categories[index] = category;
    } else {
      categories.add(category);
    }
    await _saveCategories(categories);
  }

  Future<void> renameCategory(String oldName, Category updated) async {
    final categories = await getCategories();
    final index = categories.indexWhere((c) => c.name == oldName);
    if (index >= 0) {
      categories[index] = updated;
      await _saveCategories(categories);
    }
  }

  Future<int> appCountForCategory(String name) async {
    final apps = await getApps();
    return apps.where((a) => a.category == name).length;
  }

  Future<void> saveCategoryOrder(List<Category> ordered) async {
    await _saveCategories(ordered);
  }

  Future<void> deleteCategory(String name) async {
    final categories = await getCategories();
    categories.removeWhere((c) => c.name == name);
    await _saveCategories(categories);
  }

  Future<List<Category>> getCategories() async {
    final json = _prefs.getString(_categoriesKey);
    if (json == null) return _defaultCategories();
    final List<dynamic> decoded = jsonDecode(json);
    return decoded.map((e) => Category.fromJson(e)).toList();
  }

  Future<void> _saveCategories(List<Category> categories) async {
    final json = jsonEncode(categories.map((e) => e.toJson()).toList());
    await _prefs.setString(_categoriesKey, json);
  }

  // Spend ledger methods

  Future<List<SpendLedgerEntry>> getSpendLedger() async {
    final json = _prefs.getString(_ledgerKey);
    if (json == null) return [];
    final List<dynamic> decoded = jsonDecode(json);
    return decoded.map((e) => SpendLedgerEntry.fromJson(e)).toList();
  }

  Future<void> appendLedgerEntry(SpendLedgerEntry entry) async {
    final ledger = await getSpendLedger();
    ledger.add(entry);
    await _saveSpendLedger(ledger);
  }

  Future<void> _saveSpendLedger(List<SpendLedgerEntry> ledger) async {
    final json = jsonEncode(ledger.map((e) => e.toJson()).toList());
    await _prefs.setString(_ledgerKey, json);
  }

  /// Runs once per app launch (see main.dart): for every active
  /// subscription whose renewal date has already passed, logs a real
  /// "billed" ledger entry at the price/cycle known at the time and
  /// rolls the date forward — turning a stale date into an accurate
  /// one and building real spend history going forward. Capped per
  /// entry so a long-neglected app can't flood the ledger in one pass;
  /// any remainder catches up on the next launch.
  Future<void> reconcileBilling() async {
    const maxCatchUpCycles = 24;
    final apps = await getApps();
    final ledger = await getSpendLedger();
    final now = DateTime.now();
    var appsChanged = false;
    var ledgerChanged = false;
    final caughtUp = <AppEntry>[];

    for (var i = 0; i < apps.length; i++) {
      var a = apps[i];
      if (!a.isActiveSubscription ||
          a.nextRenewalDate == null ||
          a.billingCycle == null) {
        continue;
      }
      var cycles = 0;
      while (a.nextRenewalDate!.isBefore(now) && cycles < maxCatchUpCycles) {
        ledger.add(
          SpendLedgerEntry(
            entryId: a.id,
            appName: a.name,
            date: a.nextRenewalDate!,
            amount: a.subscriptionCost ?? 0,
            kind: LedgerEventKind.billed,
            category: a.category,
          ),
        );
        ledgerChanged = true;
        a = a.copyWith(
          nextRenewalDate: defaultRenewalDate(a.billingCycle!, a.nextRenewalDate!),
        );
        appsChanged = true;
        cycles++;
      }
      apps[i] = a;
      if (cycles > 0) caughtUp.add(a);
    }

    if (appsChanged) await _saveApps(apps);
    if (ledgerChanged) await _saveSpendLedger(ledger);

    for (final a in caughtUp) {
      try {
        await NotificationService().announceRenewalCaughtUp(a);
      } catch (e) {
        debugPrint('Renewal catch-up notification failed: $e');
      }
    }
  }

  /// Export all user subscriptions, categories, and ledger entries as a JSON string.
  Future<String> exportAllJson() async {
    final apps = await getApps();
    final categories = await getCategories();
    final ledger = await getSpendLedger();
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'apps': apps.map((a) => a.toJson()).toList(),
      'categories': categories.map((c) => c.toJson()).toList(),
      'ledger': ledger.map((l) => l.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Import user subscriptions, categories, and ledger entries from a JSON string.
  Future<bool> importAllJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      if (decoded.containsKey('apps')) {
        final List<dynamic> appsList = decoded['apps'];
        final apps = appsList.map((e) => AppEntry.fromJson(e as Map<String, dynamic>)).toList();
        await _saveApps(apps);
        await NotificationService().rescheduleAll(apps);
      }
      if (decoded.containsKey('categories')) {
        final List<dynamic> catsList = decoded['categories'];
        final cats = catsList.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
        await _saveCategories(cats);
      }
      if (decoded.containsKey('ledger')) {
        final List<dynamic> ledgerList = decoded['ledger'];
        final ledger = ledgerList.map((e) => SpendLedgerEntry.fromJson(e as Map<String, dynamic>)).toList();
        await _saveSpendLedger(ledger);
      }
      return true;
    } catch (e) {
      debugPrint('Error importing JSON data: $e');
      return false;
    }
  }

  /// Reset all stored apps, ledger, and restore default categories.
  Future<void> clearAllData() async {
    await _prefs.remove(_appsKey);
    await _prefs.remove(_ledgerKey);
    await _prefs.remove(_categoriesKey);
    await NotificationService().cancelAll();
  }

  /// Injects realistic test subscriptions and 4-month spend history for diagnostic testing.
  Future<void> seedSampleData() async {
    final now = DateTime.now();
    final apps = <AppEntry>[
      AppEntry(
        id: 'sample_netflix',
        name: 'Netflix Standard',
        appStoreLink: '',
        category: 'Media / Streaming',
        createdAt: now.subtract(const Duration(days: 120)),
        isActiveSubscription: true,
        billingCycle: 'monthly',
        subscriptionCost: 16.99,
        nextRenewalDate: now.add(const Duration(days: 4)),
      ),
      AppEntry(
        id: 'sample_spotify',
        name: 'Spotify Premium',
        appStoreLink: '',
        category: 'Media / Streaming',
        createdAt: now.subtract(const Duration(days: 90)),
        isActiveSubscription: true,
        billingCycle: 'monthly',
        subscriptionCost: 6.99,
        isPromotionalPrice: true,
        regularPrice: 13.99,
        promotionEndsDate: now.add(const Duration(days: 12)),
        nextRenewalDate: now.add(const Duration(days: 12)),
      ),
      AppEntry(
        id: 'sample_icloud',
        name: 'iCloud+ 200GB',
        appStoreLink: '',
        category: 'Utilities',
        createdAt: now.subtract(const Duration(days: 180)),
        isActiveSubscription: true,
        billingCycle: 'monthly',
        subscriptionCost: 4.49,
        nextRenewalDate: now.add(const Duration(days: 18)),
      ),
      AppEntry(
        id: 'sample_chatgpt',
        name: 'ChatGPT Plus',
        appStoreLink: '',
        category: 'Productivity',
        createdAt: now.subtract(const Duration(days: 60)),
        isActiveSubscription: true,
        billingCycle: 'monthly',
        subscriptionCost: 20.00,
        nextRenewalDate: now.add(const Duration(days: 25)),
      ),
      AppEntry(
        id: 'sample_audible',
        name: 'Audible Membership',
        appStoreLink: '',
        category: 'Education',
        createdAt: now.subtract(const Duration(days: 45)),
        isActiveSubscription: true,
        billingCycle: 'monthly',
        subscriptionCost: 7.99,
        isPromotionalPrice: true,
        regularPrice: 16.45,
        promotionEndsDate: now.add(const Duration(days: 28)),
        nextRenewalDate: now.add(const Duration(days: 28)),
      ),
    ];

    await _saveApps(apps);

    // Build historical ledger entries for the past 4 months
    final ledger = <SpendLedgerEntry>[];
    for (var m = 4; m >= 1; m--) {
      final billDate = DateTime(now.year, now.month - m, 15);
      ledger.add(
        SpendLedgerEntry(
          entryId: 'sample_netflix',
          appName: 'Netflix Standard',
          date: billDate,
          amount: 16.99,
          kind: LedgerEventKind.billed,
          category: 'Media / Streaming',
        ),
      );
      ledger.add(
        SpendLedgerEntry(
          entryId: 'sample_spotify',
          appName: 'Spotify Premium',
          date: billDate,
          amount: 6.99,
          kind: LedgerEventKind.billed,
          category: 'Media / Streaming',
        ),
      );
      ledger.add(
        SpendLedgerEntry(
          entryId: 'sample_icloud',
          appName: 'iCloud+ 200GB',
          date: billDate,
          amount: 4.49,
          kind: LedgerEventKind.billed,
          category: 'Utilities',
        ),
      );
      if (m <= 2) {
        ledger.add(
          SpendLedgerEntry(
            entryId: 'sample_chatgpt',
            appName: 'ChatGPT Plus',
            date: billDate,
            amount: 20.00,
            kind: LedgerEventKind.billed,
            category: 'Productivity',
          ),
        );
      }
    }

    // Add a price changed event for Netflix from 14.99 -> 16.99 2 months ago
    ledger.add(
      SpendLedgerEntry(
        entryId: 'sample_netflix',
        appName: 'Netflix Standard',
        date: DateTime(now.year, now.month - 2, 10),
        amount: 16.99,
        previousAmount: 14.99,
        kind: LedgerEventKind.priceChanged,
        category: 'Media / Streaming',
      ),
    );

    await _saveSpendLedger(ledger);
    await NotificationService().rescheduleAll(apps);
  }

  /// Returns raw dump of stored keys in SharedPreferences.
  Map<String, dynamic> getRawDatabaseDump() {
    final keys = _prefs.getKeys();
    final map = <String, dynamic>{};
    for (final k in keys) {
      map[k] = _prefs.get(k);
    }
    return map;
  }

  // Kept in sync with AppTokens.categories — same names, same hex, so the
  // seeded default and the token-driven lookup never disagree. None of
  // these use green/yellow/orange/red: those are reserved for savings,
  // time-pressure, CTA, and error semantics respectively.
  List<Category> _defaultCategories() {
    return [
      Category(name: 'Productivity', color: const Color(0xFF6366F1)),
      Category(name: 'Notes / Journaling', color: const Color(0xFFA855F7)),
      Category(name: 'Finance', color: const Color(0xFF5B21B6)),
      Category(name: 'Health / Fitness', color: const Color(0xFF0284C7)),
      Category(name: 'Media / Streaming', color: const Color(0xFFEC4899)),
      Category(name: 'Utilities', color: const Color(0xFF06B6D4)),
      Category(name: 'Social', color: const Color(0xFF3B82F6)),
      Category(name: 'Education', color: const Color(0xFF701A75)),
      Category(name: 'Shopping', color: const Color(0xFFC026D3)),
      Category(name: 'Travel', color: const Color(0xFF14B8A6)),
    ];
  }
}
