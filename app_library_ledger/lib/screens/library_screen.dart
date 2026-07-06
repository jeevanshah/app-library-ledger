import 'package:flutter/material.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../services/storage_service.dart';
import 'add_app_screen.dart';
import 'categories_screen.dart';
import 'dart:html' as html;
import 'package:fl_chart/fl_chart.dart';
import 'package:hugeicons/hugeicons.dart';
import '../theme/app_theme.dart';

// Helper function to get app logo with first letter
Widget getAppLogo(String appName, Color categoryColor) {
  final initial = appName.isNotEmpty ? appName[0].toUpperCase() : '?';
  
  // Use first letter with gradient
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [categoryColor, categoryColor.withOpacity(0.7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: categoryColor.withOpacity(0.3),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
    ),
  );
}

// Helper function to get category icon
IconData getCategoryIcon(String categoryName) {
  switch (categoryName.toLowerCase()) {
    case 'productivity':
      return Icons.work_rounded;
    case 'notes / journaling':
      return Icons.edit_note_rounded;
    case 'finance':
      return Icons.account_balance_wallet_rounded;
    case 'health / fitness':
      return Icons.fitness_center_rounded;
    case 'media / streaming':
      return Icons.movie_rounded;
    case 'utilities':
      return Icons.build_rounded;
    case 'social':
      return Icons.people_rounded;
    case 'education':
      return Icons.school_rounded;
    case 'shopping':
      return Icons.shopping_bag_rounded;
    case 'travel':
      return Icons.flight_rounded;
    default:
      return Icons.apps_rounded;
  }
}
class LibraryScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;
  
  const LibraryScreen({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late List<AppEntry> _apps = [];
  late List<Category> _categories = [];
  String _searchQuery = '';
  String? _selectedCategory;
  bool _showSubscriptionsOnly = false;
  String? _selectedBillingCycle; // null, 'monthly', 'yearly'
  String _sortBy = 'name'; // 'name', 'price', 'renewal', 'recent'
  int _selectedTabIndex = 0; // 0 = list, 1 = dashboard

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final apps = await StorageService().getApps();
    final categories = await StorageService().getCategories();
    setState(() {
      _apps = apps;
      _categories = categories;
    });
  }

  List<AppEntry> _getFilteredApps() {
    var filtered = _apps
        .where((app) =>
            app.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (_selectedCategory != null && _selectedCategory != 'All') {
      filtered = filtered.where((app) => app.category == _selectedCategory).toList();
    }

    if (_showSubscriptionsOnly) {
      filtered = filtered.where((app) => app.isActiveSubscription).toList();
    }

    if (_selectedBillingCycle != null) {
      filtered = filtered.where((app) => 
        app.isActiveSubscription && app.billingCycle == _selectedBillingCycle
      ).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'price':
        filtered.sort((a, b) => (b.subscriptionCost ?? 0).compareTo(a.subscriptionCost ?? 0));
        break;
      case 'renewal':
        filtered.sort((a, b) {
          final aDate = a.nextRenewalDate ?? DateTime(2099);
          final bDate = b.nextRenewalDate ?? DateTime(2099);
          return aDate.compareTo(bDate);
        });
        break;
      case 'recent':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      default: // name
        filtered.sort((a, b) => a.name.compareTo(b.name));
    }

    return filtered;
  }

  double _getTotalMonthlyCost() {
    return _apps.where((app) => app.isActiveSubscription).fold(0.0, (sum, app) {
      if (app.subscriptionCost == null) return sum;
      if (app.billingCycle == 'yearly') {
        return sum + (app.subscriptionCost! / 12);
      }
      return sum + app.subscriptionCost!;
    });
  }

  double _getAverageCost() {
    final subs = _apps.where((app) => app.isActiveSubscription).toList();
    if (subs.isEmpty) return 0;
    return _getTotalMonthlyCost() / subs.length;
  }

  AppEntry? _getMostExpensive() {
    if (_apps.isEmpty) return null;
    AppEntry? max;
    for (var app in _apps.where((a) => a.isActiveSubscription)) {
      if (max == null || (app.subscriptionCost ?? 0) > (max.subscriptionCost ?? 0)) {
        max = app;
      }
    }
    return max;
  }

  Map<String, double> _getSpendingByCategory() {
    final spending = <String, double>{};
    for (var app in _apps.where((a) => a.isActiveSubscription)) {
      if (app.subscriptionCost == null) continue;
      final cost = app.billingCycle == 'yearly'
          ? app.subscriptionCost! / 12
          : app.subscriptionCost!;
      spending[app.category] = (spending[app.category] ?? 0) + cost;
    }
    return spending;
  }

  Map<String, int> _getCategoryCounts() {
    final counts = <String, int>{};
    for (var app in _apps) {
      counts[app.category] = (counts[app.category] ?? 0) + 1;
    }
    return counts;
  }

  void _navigateToAddApp() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAppScreen(categories: _categories),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  void _showAppDetails(AppEntry app) async {
    // Open app URL in browser/app store
    // For now, just navigate to edit
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAppScreen(categories: _categories),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  void _navigateToCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoriesScreen(categories: _categories),
      ),
    );
    await _loadData();
  }

  void _exportData() {
    // Generate CSV
    final buffer = StringBuffer();
    buffer.writeln('Name,Category,Cost,Billing Cycle,Next Renewal,App Store Link,Notes,Is Promo,Regular Price,Promo Ends');
    
    for (final app in _apps) {
      buffer.write('"${app.name}",');
      buffer.write('"${app.category}",');
      buffer.write('${app.subscriptionCost ?? '0'},');
      buffer.write('${app.billingCycle ?? 'N/A'},');
      buffer.write('${app.nextRenewalDate != null ? '${app.nextRenewalDate!.month}/${app.nextRenewalDate!.day}/${app.nextRenewalDate!.year}' : 'N/A'},');
      buffer.write('"${app.appStoreLink}",');
      buffer.write('"${(app.notes ?? '').replaceAll('"', '""')}",');
      buffer.write('${app.isPromotionalPrice ? 'Yes' : 'No'},');
      buffer.write('${app.regularPrice ?? '0'},');
      buffer.writeln('${app.promotionEndsDate != null ? '${app.promotionEndsDate!.month}/${app.promotionEndsDate!.day}/${app.promotionEndsDate!.year}' : 'N/A'}');
    }

    final csvData = buffer.toString();
    
    // Create download link with readable date
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    // Create blob and download
    final blob = html.Blob([csvData], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    (html.document.createElement('a') as html.AnchorElement)
      ..href = url
      ..download = 'subscriptions_$dateStr.csv'
      ..click();
    
    html.Url.revokeObjectUrl(url);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Exported ${_apps.length} subscriptions to CSV'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCategoryFilter() {
    final categoryCounts = _getCategoryCounts();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter by Category',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.apps_rounded,
                  color: _selectedCategory == null 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.grey),
              title: const Text('All'),
              trailing: Text('${_apps.length}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  )),
              selected: _selectedCategory == null,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                setState(() => _selectedCategory = null);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final count = categoryCounts[cat.name] ?? 0;
                  final isSelected = _selectedCategory == cat.name;
                  return ListTile(
                    leading: Icon(
                      getCategoryIcon(cat.name),
                      color: isSelected ? Theme.of(context).colorScheme.primary : cat.color,
                    ),
                    title: Text(cat.name),
                    trailing: Text('$count',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                        )),
                    selected: isSelected,
                    selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () {
                      setState(() => _selectedCategory = cat.name);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Billing Cycle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedBillingCycle == null,
                  onSelected: (selected) {
                    setState(() => _selectedBillingCycle = null);
                    Navigator.pop(context);
                  },
                ),
                FilterChip(
                  label: const Text('Monthly'),
                  avatar: Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: _selectedBillingCycle == 'monthly' ? Colors.white : null,
                  ),
                  selected: _selectedBillingCycle == 'monthly',
                  onSelected: (selected) {
                    setState(() => _selectedBillingCycle = selected ? 'monthly' : null);
                    Navigator.pop(context);
                  },
                ),
                FilterChip(
                  label: const Text('Yearly'),
                  avatar: Icon(
                    Icons.event_rounded,
                    size: 16,
                    color: _selectedBillingCycle == 'yearly' ? Colors.white : null,
                  ),
                  selected: _selectedBillingCycle == 'yearly',
                  onSelected: (selected) {
                    setState(() => _selectedBillingCycle = selected ? 'yearly' : null);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _navigateToCategories();
              },
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Manage Categories'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'App Library Ledger',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (_apps.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _exportData,
              tooltip: 'Export data',
            ),
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.dark 
                  ? Icons.light_mode_rounded 
                  : Icons.dark_mode_rounded,
            ),
            onPressed: widget.onToggleTheme,
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SegmentedButton<int>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Library'),
                  icon: Icon(Icons.apps_rounded),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Dashboard'),
                  icon: Icon(Icons.dashboard_rounded),
                ),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (Set<int> newSelection) {
                setState(() {
                  _selectedTabIndex = newSelection.first;
                });
              },
            ),
          ),
          if (_selectedTabIndex == 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  hintText: 'Search your apps...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                ),
              ),
            ),
            // Sort and Filter controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sort_rounded, 
                            size: 18, 
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        const Text('Sort:', 
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DropdownButton<String>(
                              value: _sortBy,
                              underline: const SizedBox(),
                              isDense: true,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _sortBy = value);
                                }
                              },
                              items: [
                                DropdownMenuItem(
                                    value: 'name', 
                                    child: Row(
                                      children: [
                                        if (_sortBy == 'name')
                                          Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                                        if (_sortBy == 'name')
                                          const SizedBox(width: 4),
                                        const Text('Name', style: TextStyle(fontSize: 13)),
                                      ],
                                    )),
                                DropdownMenuItem(
                                    value: 'price', 
                                    child: Row(
                                      children: [
                                        if (_sortBy == 'price')
                                          Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                                        if (_sortBy == 'price')
                                          const SizedBox(width: 4),
                                        const Text('Price', style: TextStyle(fontSize: 13)),
                                      ],
                                    )),
                                DropdownMenuItem(
                                value: 'renewal', 
                                child: Row(
                                  children: [
                                    if (_sortBy == 'renewal')
                                      Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                                    if (_sortBy == 'renewal')
                                      const SizedBox(width: 4),
                                    const Text('Renewal', style: TextStyle(fontSize: 13)),
                                  ],
                                )),
                            DropdownMenuItem(
                                value: 'recent', 
                                child: Row(
                                  children: [
                                    if (_sortBy == 'recent')
                                      Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                                    if (_sortBy == 'recent')
                                      const SizedBox(width: 4),
                                    const Text('Recent', style: TextStyle(fontSize: 13)),
                                  ],
                                )),
                          ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: OutlinedButton.icon(
                      onPressed: _showCategoryFilter,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal, size: 14),
                      label: Text(
                        _selectedCategory ?? 
                        (_selectedBillingCycle != null 
                          ? _selectedBillingCycle == 'monthly' ? 'Monthly' : 'Yearly'
                          : 'Filter'),
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: (_selectedCategory != null || _selectedBillingCycle != null)
                            ? Theme.of(context).colorScheme.primaryContainer 
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Search and Filter Section
          if (_selectedTabIndex == 0) ...[
            // Promotional Price Alert
            if (_apps.any((app) => app.isPromotionalPrice && 
                app.promotionEndsDate != null && 
                app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Card(
                  elevation: 0,
                  color: Colors.orange[50],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange[700], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Price Increase Alert',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.orange[900],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_apps.where((app) => app.isPromotionalPrice && app.promotionEndsDate != null && app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30).length} subscription(s) ending promo soon',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_apps.any((app) => app.isActiveSubscription)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[700],
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.credit_card_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Monthly Subscriptions',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '\$${_getTotalMonthlyCost().toStringAsFixed(2)}/month',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        FilterChip(
                          label: Text(_showSubscriptionsOnly ? 'Show All' : 'Subs Only'),
                          selected: _showSubscriptionsOnly,
                          onSelected: (value) {
                            setState(() => _showSubscriptionsOnly = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _getFilteredApps().isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 2000),
                          tween: Tween(begin: 0.95, end: 1.05),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: child,
                            );
                          },
                          onEnd: () {
                            // Restart animation by rebuilding
                            if (mounted) setState(() {});
                          },
                          child: Container(
                          padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
                                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: HugeIcon(
                            icon: _apps.isEmpty ? HugeIcons.strokeRoundedMenu03 : HugeIcons.strokeRoundedSearchRemove,
                            size: 72,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          _apps.isEmpty
                              ? 'No Apps Yet'
                              : 'No Results Found',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _apps.isEmpty
                              ? 'Start tracking your subscriptions\nby adding your first app'
                              : 'Try adjusting your search or filters',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_apps.isEmpty) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _navigateToAddApp,
                            icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 18),
                            label: const Text('Add Your First App'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _getFilteredApps().length,
                    itemBuilder: (context, index) {
                      final app = _getFilteredApps()[index];
                      final category = _categories.firstWhere(
                        (c) => c.name == app.category,
                        orElse: () => Category(
                          name: app.category,
                          color: Colors.grey,
                        ),
                      );

                      return TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 300 + (index * 50)),
                        tween: Tween(begin: 0.0, end: 1.0),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: Opacity(
                              opacity: value,
                              child: child,
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'app-${app.id}',
                          child: Material(
                            color: Colors.transparent,
                            child: GlassmorphicContainer(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              padding: const EdgeInsets.all(20),
                              blur: 15,
                              opacity: 0.08,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.black.withOpacity(0.3)
                                      : category.color.withOpacity(0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                  spreadRadius: 2,
                                ),
                              ],
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () => _showAppDetails(app),
                                child: Row(
                                  children: [
                                    getAppLogo(app.name, category.color),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            app.name,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            app.category,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (app.isPromotionalPrice && app.promotionEndsDate != null) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30
                                                ? Colors.orange[100]
                                                : Colors.blue[50],
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30
                                                ? '⚠️ Price increases in ${app.promotionEndsDate!.difference(DateTime.now()).inDays} days'
                                                : 'Promo ends ${app.promotionEndsDate!.month}/${app.promotionEndsDate!.day}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30
                                                  ? Colors.orange[900]
                                                  : Colors.blue[900],
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (app.isActiveSubscription && app.nextRenewalDate != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.event_rounded, 
                                                size: 14, 
                                                color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Renews: ${app.nextRenewalDate!.month}/${app.nextRenewalDate!.day}/${app.nextRenewalDate!.year}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (app.isActiveSubscription) ...[
                                      if (app.isPromotionalPrice && app.promotionEndsDate != null) ...[
                                        Text(
                                          '\$${app.subscriptionCost?.toStringAsFixed(2) ?? '0.00'}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[600],
                                            decoration: TextDecoration.lineThrough,
                                          ),
                                        ),
                                        Icon(Icons.arrow_downward_rounded, 
                                            size: 12, 
                                            color: Colors.grey[600]),
                                        Text(
                                          '\$${app.regularPrice?.toStringAsFixed(2) ?? '0.00'}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: app.promotionEndsDate!.difference(DateTime.now()).inDays <= 30
                                                ? Colors.orange[700]
                                                : Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          '\$${app.subscriptionCost?.toStringAsFixed(2) ?? '0.00'}',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '/${app.billingCycle == 'yearly' ? 'year' : 'month'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, size: 16),
                                          tooltip: 'Edit',
                                          onPressed: () async {
                                            final result = await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => AddAppScreen(
                                                  categories: _categories,
                                                  appToEdit: app,
                                                ),
                                              ),
                                            );
                                            if (result == true) {
                                              await _loadData();
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 16),
                                          tooltip: 'Delete',
                                          onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete app?'),
                                            content: Text(
                                                'Remove "${app.name}" from your library?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(context, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          await StorageService().deleteApp(app.id);
                                          await _loadData();
                                        }
                                      },
                                    ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ), // Hero + GlassmorphicContainer
                  ); // TweenAnimationBuilder
                  },
                ),
            ),
          ],
          // Dashboard Tab
          if (_selectedTabIndex == 1) ...[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 600),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                      Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).colorScheme.primary,
                                  Theme.of(context).colorScheme.primary.withOpacity(0.7),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.calendar_month_rounded,
                                        size: 20, color: Colors.white.withOpacity(0.9)),
                                    const SizedBox(width: 6),
                                    Text('Monthly Total',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        )),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '\$${_getTotalMonthlyCost().toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28, 
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.shade400,
                                  Colors.purple.shade300,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purple.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.calculate_rounded,
                                        size: 20, color: Colors.white.withOpacity(0.9)),
                                    const SizedBox(width: 6),
                                    Text('Average/App',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        )),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '\$${_getAverageCost().toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28, 
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_getMostExpensive() != null)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.amber.shade400,
                              Colors.orange.shade300,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.star_rounded,
                                  size: 24, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Most Expensive',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      )),
                                  const SizedBox(height: 4),
                                  Text(
                                    _getMostExpensive()!.name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20, 
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${_getMostExpensive()!.subscriptionCost?.toStringAsFixed(2) ?? '0.00'}/${_getMostExpensive()!.billingCycle == 'yearly' ? 'year' : 'month'}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                        ], // End Column children for metrics
                      ), // End Column for metrics
                    ), // End TweenAnimationBuilder for metrics
                    const SizedBox(height: 24),
                    // Chart Section with animation
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 700),
                      tween: Tween(begin: 0.0, end: 1.0),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, 30 * (1 - value)),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    Row(
                      children: [
                        Icon(Icons.donut_small_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20),
                        const SizedBox(width: 8),
                        const Text('Spending by Category',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_getSpendingByCategory().isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: SizedBox(
                          height: 250,
                          child: PieChart(
                            PieChartData(
                              sections: _getSpendingByCategory()
                                  .entries
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) {
                                final category = e.value.key;
                                final amount = e.value.value;
                                final categoryObj = _categories.firstWhere(
                                  (c) => c.name == category,
                                  orElse: () => Category(
                                    name: category,
                                    color: Colors.grey,
                                  ),
                                );
                                return PieChartSectionData(
                                  color: categoryObj.color,
                                  value: amount,
                                  title: '\$${amount.toStringAsFixed(0)}',
                                  radius: 100,
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList(),
                              centerSpaceRadius: 50,
                              sectionsSpace: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._getSpendingByCategory().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _categories
                                        .firstWhere(
                                          (c) => c.name == e.key,
                                          orElse: () => Category(
                                            name: e.key,
                                            color: Colors.grey,
                                          ),
                                        )
                                        .color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(e.key)),
                                Text(
                                  '\$${e.value.toStringAsFixed(2)}/mo',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )),
                    ] else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.pie_chart_outline_rounded,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text('No subscription data yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ), // End Column for chart section
                  ), // End TweenAnimationBuilder for chart
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 500),
        tween: Tween(begin: 0.0, end: 1.0),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: child,
          );
        },
        child: FloatingActionButton.extended(
          onPressed: _navigateToAddApp,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 20),
          label: const Text('Add App'),
          elevation: 4,
        ),
      ),
    );
  }
}
