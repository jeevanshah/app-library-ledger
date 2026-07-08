import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';

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

  List<Category> _defaultCategories() {
    return [
      Category(name: 'Productivity', color: const Color(0xFF4CAF50)),
      Category(name: 'Notes / Journaling', color: const Color(0xFF2196F3)),
      Category(name: 'Finance', color: const Color(0xFFFFC107)),
      Category(name: 'Health / Fitness', color: const Color(0xFFF44336)),
      Category(name: 'Media / Streaming', color: const Color(0xFF9C27B0)),
      Cate