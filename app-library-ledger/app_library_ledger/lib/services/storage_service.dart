import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../theme/app_tokens.dart';

const String uncategorizedName = 'Uncategorized';

class StorageService {
  static const String _appsKey = 'apps';
  static const String _categoriesKey = 'categories';

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

  /// Removes [name] from the category list. Any apps still assigned to it are
  /// reassigned to `Uncategorized` (created on demand) so they never end up
  /// pointing at a category that no longer exists.
  Future<void> deleteCategory(String name) async {
    if (name == uncategorizedName) return;

    final apps = await getApps();
    final orphaned = apps.where((a) => a.category == name).toList();
    if (orphaned.isNotEmpty) {
      final categories = await getCategories();
      if (!categories.any((c) => c.name == uncategorizedName)) {
        categories.add(Category(name: uncategorizedName, color: Colors.grey));
        await _saveCategories(categories);
      }
      final reassigned = apps
          .map(
            (a) => a.category == name ? _withCategory(a, uncategorizedName) : a,
          )
          .toList();
      await _saveApps(reassigned);
    }

    final categories = await getCategories();
    categories.removeWhere((c) => c.name == name);
    await _saveCategories(categories);
  }

  /// Count of apps currently assigned to [name] — used to warn the user
  /// before a delete reassigns them to Uncategorized.
  Future<int> appCountForCategory(String name) async {
    final apps = await getApps();
    return apps.where((a) => a.category == name).length;
  }

  /// Renames a category (and re-colors it) while keeping every app that
  /// referenced [oldName] pointed at [updated] — unlike delete, a rename
  /// must never fall back to Uncategorized.
  Future<void> renameCategory(String oldName, Category updated) async {
    if (oldName != updated.name) {
      final apps = await getApps();
      final renamed = apps
          .map(
            (a) => a.category == oldName ? _withCategory(a, updated.name) : a,
          )
          .toList();
      await _saveApps(renamed);
    }

    final categories = await getCategories();
    categories.removeWhere((c) => c.name == oldName);
    categories.add(updated);
    await _saveCategories(categories);
  }

  AppEntry _withCategory(AppEntry a, String category) => AppEntry(
    id: a.id,
    name: a.name,
    appStoreLink: a.appStoreLink,
    category: category,
    packageName: a.packageName,
    notes: a.notes,
    createdAt: a.createdAt,
    subscriptionCost: a.subscriptionCost,
    billingCycle: a.billingCycle,
    nextRenewalDate: a.nextRenewalDate,
    isActiveSubscription: a.isActiveSubscription,
    isPromotionalPrice: a.isPromotionalPrice,
    regularPrice: a.regularPrice,
    promotionEndsDate: a.promotionEndsDate,
  );

  Future<List<Category>> getCategories() async {
    final json = _prefs.getString(_categoriesKey);
    if (json == null) return _defaultCategories();
    final List<dynamic> decoded = jsonDecode(json);
    return decoded.map((e) => Category.fromJson(e)).toList();
  }

  /// Persists a new sort order for the full category list (e.g. after a
  /// drag-to-reorder in the Categories screen).
  Future<void> saveCategoryOrder(List<Category> categories) async {
    await _saveCategories(categories);
  }

  Future<void> _saveCategories(List<Category> categories) async {
    final json = jsonEncode(categories.map((e) => e.toJson()).toList());
    await _prefs.setString(_categoriesKey, json);
  }

  List<Category> _defaultCategories() {
    return [
      for (final name in AppTokens.categories.keys)
        Category(name: name, color: AppTokens.categoryColor(name)),
    ];
  }
}
