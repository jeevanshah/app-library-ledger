import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../services/storage_service.dart';

class CategoriesScreen extends StatefulWidget {
  final List<Category> categories;

  const CategoriesScreen({required this.categories, super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late List<Category> _categories;

  @override
  void initState() {
    super.initState();
    _categories = widget.categories;
  }

  Future<void> _deleteCategory(String name) async {
    await StorageService().deleteCategory(name);
    setState(() {
      _categories.removeWhere((c) => c.name == name);
    });
  }

  void _renameCategory(Category category) {
    final controller = TextEditingController(text: category.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _submitRename(controller.text, category);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRename(String newName, Category category) async {
    if (newName.isNotEmpty) {
      await StorageService().deleteCategory(category.name);
      final newCategory = Category(
        name: newName,
        color: category.color,
        isCustom: category.isCustom,
      );
      await StorageService().saveCategory(newCategory);
      setState(() {
        _categories[_categories.indexOf(category)] = newCategory;
      });
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
      ),
      body: ListView.builder(
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return ListTile(
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: category.color,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(category.name),
            trailing: category.isCustom
                ? PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: () => _renameCategory(category),
                        child: const Text('Rename'),
                      ),
                      PopupMenuItem(
                        onTap: () => _deleteCategory(category.name),
                        child: const Text('Delete'),
                      ),
                    ],
                  )
                : null,
          );
        },
      ),
    );
  }
}
