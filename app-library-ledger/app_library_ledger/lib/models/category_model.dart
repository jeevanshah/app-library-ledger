import 'package:flutter/material.dart';

class Category {
  final String name;
  final Color color;
  final bool isCustom;

  Category({
    required this.name,
    required this.color,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': color.toARGB32(),
        'isCustom': isCustom,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        name: json['name'],
        color: Color(json['color']),
        isCustom: json['isCustom'] ?? false,
      );
}
