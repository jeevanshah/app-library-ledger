import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettings {
  final bool enabled;
  final bool promoAlerts;
  final List<int> offsets;
  final int hour;
  final int minute;

  const NotificationSettings({
    this.enabled = true,
    this.promoAlerts = true,
    this.offsets = const [1, 7],
    this.hour = 10,
    this.minute = 0,
  });

  NotificationSettings copyWith({
    bool? enabled,
    bool? promoAlerts,
    List<int>? offsets,
    int? hour,
    int? minute,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    promoAlerts: promoAlerts ?? this.promoAlerts,
    offsets: offsets ?? this.offsets,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'promoAlerts': promoAlerts,
    'offsets': offsets,
    'hour': hour,
    'minute': minute,
  };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        enabled: json['enabled'] as bool? ?? true,
        promoAlerts: json['promoAlerts'] as bool? ?? true,
        offsets:
            (json['offsets'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [1, 7],
        hour: json['hour'] as int? ?? 10,
        minute: json['minute'] as int? ?? 0,
      );
}

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _key = 'notification_settings';
  static const _offersKey = 'offers_enabled';
  NotificationSettings? _cached;

  /// Single reactive source of truth for offers enabled state.
  /// All screens must read/write through this notifier.
  final ValueNotifier<bool> offersEnabled = ValueNotifier<bool>(false);

  Future<void> initOffersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    offersEnabled.value = prefs.getBool(_offersKey) ?? false;
  }

  Future<void> setOffersEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offersKey, value);
    offersEnabled.value = value;
  }

  Future<NotificationSettings> load() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _cached = const NotificationSettings();
      return _cached!;
    }
    try {
      _cached = NotificationSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      _cached = const NotificationSettings();
    }
    return _cached!;
  }

  Future<void> save(NotificationSettings s) async {
    _cached = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
  }
}
