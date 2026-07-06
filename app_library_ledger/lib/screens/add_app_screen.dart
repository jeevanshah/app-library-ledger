import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:hugeicons/hugeicons.dart';
import '../models/app_model.dart';
import '../models/category_model.dart';
import '../services/storage_service.dart';

final Map<String, Map<String, dynamic>> _popularApps = {
  // Media & Entertainment
  'Netflix': {'category': 'Media / Streaming', 'cost': 15.49, 'cycle': 'monthly'},
  'Spotify': {'category': 'Media / Streaming', 'cost': 10.99, 'cycle': 'monthly'},
  'Disney+': {'category': 'Media / Streaming', 'cost': 10.99, 'cycle': 'monthly'},
  'YouTube Premium': {'category': 'Media / Streaming', 'cost': 13.99, 'cycle': 'monthly'},
  'Apple Music': {'category': 'Media / Streaming', 'cost': 10.99, 'cycle': 'monthly'},
  'Hulu': {'category': 'Media / Streaming', 'cost': 7.99, 'cycle': 'monthly'},
  'HBO Max': {'category': 'Media / Streaming', 'cost': 15.99, 'cycle': 'monthly'},
  'Paramount+': {'category': 'Media / Streaming', 'cost': 9.99, 'cycle': 'monthly'},
  'Peacock': {'category': 'Media / Streaming', 'cost': 5.99, 'cycle': 'monthly'},
  'Apple TV+': {'category': 'Media / Streaming', 'cost': 6.99, 'cycle': 'monthly'},
  'Prime Video': {'category': 'Media / Streaming', 'cost': 8.99, 'cycle': 'monthly'},
  'Crunchyroll': {'category': 'Media / Streaming', 'cost': 7.99, 'cycle': 'monthly'},
  'Audible': {'category': 'Media / Streaming', 'cost': 14.95, 'cycle': 'monthly'},
  'Tidal': {'category': 'Media / Streaming', 'cost': 9.99, 'cycle': 'monthly'},
  'Deezer': {'category': 'Media / Streaming', 'cost': 9.99, 'cycle': 'monthly'},
  
  // Productivity & Work
  'Microsoft 365': {'category': 'Productivity', 'cost': 6.99, 'cycle': 'monthly'},
  'Adobe Creative Cloud': {'category': 'Productivity', 'cost': 54.99, 'cycle': 'monthly'},
  'Canva Pro': {'category': 'Productivity', 'cost': 12.99, 'cycle': 'monthly'},
  'Notion': {'category': 'Productivity', 'cost': 8.00, 'cycle': 'monthly'},
  'Evernote': {'category': 'Notes / Journaling', 'cost': 7.99, 'cycle': 'monthly'},
  'ChatGPT Plus': {'category': 'Productivity', 'cost': 20.00, 'cycle': 'monthly'},
  'Dropbox': {'category': 'Productivity', 'cost': 9.99, 'cycle': 'monthly'},
  'Google One': {'category': 'Utilities', 'cost': 1.99, 'cycle': 'monthly'},
  'iCloud': {'category': 'Utilities', 'cost': 0.99, 'cycle': 'monthly'},
  'Slack': {'category': 'Productivity', 'cost': 7.25, 'cycle': 'monthly'},
  'Zoom': {'category': 'Productivity', 'cost': 14.99, 'cycle': 'monthly'},
  'Grammarly': {'category': 'Productivity', 'cost': 12.00, 'cycle': 'monthly'},
  'Dashlane': {'category': 'Utilities', 'cost': 4.99, 'cycle': 'monthly'},
  '1Password': {'category': 'Utilities', 'cost': 2.99, 'cycle': 'monthly'},
  'LastPass': {'category': 'Utilities', 'cost': 3.00, 'cycle': 'monthly'},
  
  // Shopping & Services
  'Amazon Prime': {'category': 'Shopping', 'cost': 14.99, 'cycle': 'monthly'},
  'Instacart+': {'category': 'Shopping', 'cost': 9.99, 'cycle': 'monthly'},
  'DoorDash': {'category': 'Shopping', 'cost': 9.99, 'cycle': 'monthly'},
  'Uber One': {'category': 'Shopping', 'cost': 9.99, 'cycle': 'monthly'},
  'Grubhub+': {'category': 'Shopping', 'cost': 9.99, 'cycle': 'monthly'},
  
  // Telecom & Utilities
  'Vodafone': {'category': 'Utilities', 'cost': 25.00, 'cycle': 'monthly'},
  'Verizon': {'category': 'Utilities', 'cost': 30.00, 'cycle': 'monthly'},
  'T-Mobile': {'category': 'Utilities', 'cost': 28.00, 'cycle': 'monthly'},
  'AT&T': {'category': 'Utilities', 'cost': 30.00, 'cycle': 'monthly'},
  'Orange': {'category': 'Utilities', 'cost': 25.00, 'cycle': 'monthly'},
  'O2': {'category': 'Utilities', 'cost': 24.00, 'cycle': 'monthly'},
  'EE': {'category': 'Utilities', 'cost': 26.00, 'cycle': 'monthly'},
  'Three': {'category': 'Utilities', 'cost': 23.00, 'cycle': 'monthly'},
  
  // Social & Communication
  'LinkedIn Premium': {'category': 'Social', 'cost': 29.99, 'cycle': 'monthly'},
  'Twitter Blue': {'category': 'Social', 'cost': 8.00, 'cycle': 'monthly'},
  'Discord Nitro': {'category': 'Social', 'cost': 9.99, 'cycle': 'monthly'},
  'Telegram Premium': {'category': 'Social', 'cost': 4.99, 'cycle': 'monthly'},
  
  // Gaming
  'PlayStation Plus': {'category': 'Productivity', 'cost': 9.99, 'cycle': 'monthly'},
  'Xbox Game Pass': {'category': 'Productivity', 'cost': 9.99, 'cycle': 'monthly'},
  'Nintendo Switch Online': {'category': 'Productivity', 'cost': 3.99, 'cycle': 'monthly'},
  'GeForce NOW': {'category': 'Productivity', 'cost': 9.99, 'cycle': 'monthly'},
  
  // Fitness & Health
  'Peloton': {'category': 'Health / Fitness', 'cost': 12.99, 'cycle': 'monthly'},
  'Headspace': {'category': 'Health / Fitness', 'cost': 12.99, 'cycle': 'monthly'},
  'Calm': {'category': 'Health / Fitness', 'cost': 14.99, 'cycle': 'monthly'},
  'MyFitnessPal': {'category': 'Health / Fitness', 'cost': 9.99, 'cycle': 'monthly'},
  'Strava': {'category': 'Health / Fitness', 'cost': 7.99, 'cycle': 'monthly'},
  
  // Learning & Education
  'Duolingo Plus': {'category': 'Education', 'cost': 6.99, 'cycle': 'monthly'},
  'Coursera Plus': {'category': 'Education', 'cost': 59.00, 'cycle': 'monthly'},
  'Skillshare': {'category': 'Education', 'cost': 13.99, 'cycle': 'monthly'},
  'MasterClass': {'category': 'Education', 'cost': 15.00, 'cycle': 'monthly'},
  'Brilliant': {'category': 'Education', 'cost': 12.49, 'cycle': 'monthly'},
  
  // UK-Specific Apps
  'Sky TV': {'category': 'Media / Streaming', 'cost': 26.00, 'cycle': 'monthly'},
  'Sky Sports': {'category': 'Media / Streaming', 'cost': 34.00, 'cycle': 'monthly'},
  'BT Sport': {'category': 'Media / Streaming', 'cost': 25.00, 'cycle': 'monthly'},
  'NOW TV': {'category': 'Media / Streaming', 'cost': 9.99, 'cycle': 'monthly'},
  'BBC iPlayer': {'category': 'Media / Streaming', 'cost': 0.00, 'cycle': 'monthly'},
  'ITV Hub+': {'category': 'Media / Streaming', 'cost': 5.99, 'cycle': 'monthly'},
  'Sky Mobile': {'category': 'Utilities', 'cost': 20.00, 'cycle': 'monthly'},
  'Virgin Media': {'category': 'Utilities', 'cost': 35.00, 'cycle': 'monthly'},
  'Tesco Mobile': {'category': 'Utilities', 'cost': 15.00, 'cycle': 'monthly'},
  'Giffgaff': {'category': 'Utilities', 'cost': 10.00, 'cycle': 'monthly'},
  'Deliveroo Plus': {'category': 'Shopping', 'cost': 3.49, 'cycle': 'monthly'},
  'Just Eat': {'category': 'Shopping', 'cost': 0.00, 'cycle': 'monthly'},
  'Tesco Clubcard Plus': {'category': 'Shopping', 'cost': 7.99, 'cycle': 'monthly'},
  'Sainsburys Nectar': {'category': 'Shopping', 'cost': 0.00, 'cycle': 'monthly'},
  
  // Australia-Specific Apps
  'Foxtel': {'category': 'Media / Streaming', 'cost': 49.00, 'cycle': 'monthly'},
  'Kayo Sports': {'category': 'Media / Streaming', 'cost': 25.00, 'cycle': 'monthly'},
  'Stan': {'category': 'Media / Streaming', 'cost': 12.00, 'cycle': 'monthly'},
  'Binge': {'category': 'Media / Streaming', 'cost': 10.00, 'cycle': 'monthly'},
  'Optus Sport': {'category': 'Media / Streaming', 'cost': 6.99, 'cycle': 'monthly'},
  'Telstra': {'category': 'Utilities', 'cost': 55.00, 'cycle': 'monthly'},
  'Optus': {'category': 'Utilities', 'cost': 45.00, 'cycle': 'monthly'},
  'Vodafone AU': {'category': 'Utilities', 'cost': 40.00, 'cycle': 'monthly'},
  'Woolworths Everyday Rewards': {'category': 'Shopping', 'cost': 0.00, 'cycle': 'monthly'},
  'Coles Plus': {'category': 'Shopping', 'cost': 0.00, 'cycle': 'monthly'},
  'Menulog Plus': {'category': 'Shopping', 'cost': 6.99, 'cycle': 'monthly'},
  'Uber Eats Pass': {'category': 'Shopping', 'cost': 9.99, 'cycle': 'monthly'},
};

String _suggestCategory(String appName) {
  final lower = appName.toLowerCase();
  if (_popularApps.containsKey(appName)) {
    return _popularApps[appName]!['category'] as String;
  }
  if (lower.contains('note') || lower.contains('evernote') || lower.contains('onenote')) return 'Notes / Journaling';
  if (lower.contains('bank') || lower.contains('pay') || lower.contains('wallet')) return 'Finance';
  if (lower.contains('fit') || lower.contains('health') || lower.contains('workout')) return 'Health / Fitness';
  if (lower.contains('music') || lower.contains('video') || lower.contains('stream')) return 'Media / Streaming';
  if (lower.contains('social') || lower.contains('chat') || lower.contains('message')) return 'Social';
  if (lower.contains('shop') || lower.contains('store') || lower.contains('amazon')) return 'Shopping';
  if (lower.contains('learn') || lower.contains('course') || lower.contains('study')) return 'Education';
  return 'Productivity';
}

String _generateUrl(String appName) {
  final slug = appName.toLowerCase().replaceAll(' ', '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
  return 'https://apps.apple.com/app/$slug';
}

class AddAppScreen extends StatefulWidget {
  final List<Category> categories;
  final AppEntry? appToEdit;

  const AddAppScreen({required this.categories, this.appToEdit, super.key});

  @override
  State<AddAppScreen> createState() => _AddAppScreenState();
}

class _AddAppScreenState extends State<AddAppScreen> {
  late TextEditingController _nameController;
  late TextEditingController _linkController;
  late TextEditingController _notesController;
  String? _selectedCategory;
  bool _showCustomCategory = false;
  late TextEditingController _customCategoryController;
  bool _isSubscription = false;
  late TextEditingController _costController;
  String _billingCycle = 'monthly';
  DateTime? _nextRenewalDate;
  List<String> _appSuggestions = [];
  bool _isPromotionalPrice = false;
  late TextEditingController _regularPriceController;
  DateTime? _promotionEndsDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _linkController = TextEditingController();
    _notesController = TextEditingController();
    _customCategoryController = TextEditingController();
    _costController = TextEditingController();
    _regularPriceController = TextEditingController();
    _selectedCategory = widget.categories.isNotEmpty
        ? widget.categories[0].name
        : 'Productivity';
    
    // If editing, populate fields
    if (widget.appToEdit != null) {
      final app = widget.appToEdit!;
      _nameController.text = app.name;
      _linkController.text = app.appStoreLink;
      _selectedCategory = app.category;
      _notesController.text = app.notes ?? '';
      _isSubscription = app.isActiveSubscription;
      if (app.subscriptionCost != null) {
        _costController.text = app.subscriptionCost.toString();
      }
      _billingCycle = app.billingCycle ?? 'monthly';
      _nextRenewalDate = app.nextRenewalDate;
      _isPromotionalPrice = app.isPromotionalPrice;
      if (app.regularPrice != null) {
        _regularPriceController.text = app.regularPrice.toString();
      }
      _promotionEndsDate = app.promotionEndsDate;
    }
    
    _nameController.addListener(() {
      final query = _nameController.text;
      if (query.length >= 2 && widget.appToEdit == null) {
        setState(() {
          _appSuggestions = _popularApps.keys
              .where((app) => app.toLowerCase().contains(query.toLowerCase()))
              .take(5)
              .toList();
        });
      } else {
        setState(() => _appSuggestions = []);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    _notesController.dispose();
    _customCategoryController.dispose();
    _costController.dispose();
    _regularPriceController.dispose();
    super.dispose();
  }

  Future<void> _saveApp() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter app name')),
      );
      return;
    }

    final category =
        _showCustomCategory ? _customCategoryController.text : _selectedCategory!;

    final appLink = _linkController.text.isEmpty
        ? _generateUrl(_nameController.text)
        : _linkController.text;

    final app = AppEntry(
      id: widget.appToEdit?.id,  // Keep existing ID if editing
      name: _nameController.text,
      appStoreLink: appLink,
      category: category,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      isActiveSubscription: _isSubscription,
      subscriptionCost: _isSubscription && _costController.text.isNotEmpty
          ? double.tryParse(_costController.text)
          : null,
      billingCycle: _isSubscription ? _billingCycle : null,
      nextRenewalDate: _isSubscription ? _nextRenewalDate : null,
      isPromotionalPrice: _isPromotionalPrice,
      regularPrice: _isPromotionalPrice && _regularPriceController.text.isNotEmpty
          ? double.tryParse(_regularPriceController.text)
          : null,
      promotionEndsDate: _isPromotionalPrice ? _promotionEndsDate : null,
    );

    await StorageService().saveApp(app);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _applyAppSuggestion(String appName) {
    _nameController.text = appName;
    if (_popularApps.containsKey(appName)) {
      final appData = _popularApps[appName]!;
      _selectedCategory = appData['category'] as String;
      if (!_isSubscription) {
        _isSubscription = true;
        _costController.text = (appData['cost'] as double).toString();
        _billingCycle = appData['cycle'] as String;
      }
    } else {
      _selectedCategory = _suggestCategory(appName);
    }
    setState(() => _appSuggestions = []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.appToEdit != null;
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          isEditing ? 'Edit Subscription' : 'Add Subscription',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saveApp,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01, size: 18),
            label: Text('Save'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              padding: EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.3),
              theme.colorScheme.secondaryContainer.withOpacity(0.2),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Name Section
                _buildGlassmorphicSection(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedMenu03, 
                            color: theme.colorScheme.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'App Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      _buildModernTextField(
                        controller: _nameController,
                        label: 'App Name',
                        hint: 'e.g., Netflix, Spotify',
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedSmartPhone01, size: 20),
                        required: true,
                      ),
                      
                      // Dynamic suggestions
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _appSuggestions.isNotEmpty
                            ? Container(
                                key: const ValueKey('suggestions'),
                                margin: EdgeInsets.only(top: 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _appSuggestions.map((suggestion) {
                                    return ActionChip(
                                      avatar: HugeIcon(icon: HugeIcons.strokeRoundedMagicWand02, size: 14),
                                      label: Text(suggestion),
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        _applyAppSuggestion(suggestion);
                                      },
                                      backgroundColor: theme.colorScheme.primaryContainer,
                                      labelStyle: TextStyle(
                                        color: theme.colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              )
                            : SizedBox.shrink(key: const ValueKey('no-suggestions')),
                      ),
                      
                      SizedBox(height: 16),
                      _buildModernTextField(
                        controller: _linkController,
                        label: 'App Store Link',
                        hint: 'Optional - auto-generated if left empty',
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedLink01, size: 20),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Category Section
                _buildGlassmorphicSection(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedTag02, 
                            color: theme.colorScheme.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Category',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCategory,
                            isExpanded: true,
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowDown01, size: 14),
                            items: widget.categories
                                .map((category) => category.name)
                                .toSet()
                                .map((categoryName) {
                              final category = widget.categories.firstWhere(
                                (cat) => cat.name == categoryName,
                              );
                              return DropdownMenuItem(
                                value: category.name,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: category.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(category.name),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = value);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Subscription Section
                _buildGlassmorphicSection(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedCreditCard, 
                            color: theme.colorScheme.primary, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Subscription',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Switch(
                            value: _isSubscription,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _isSubscription = value);
                            },
                          ),
                        ],
                      ),
                      
                      AnimatedSize(
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: _isSubscription
                            ? Column(
                                children: [
                                  SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _buildModernTextField(
                                          controller: _costController,
                                          label: 'Cost',
                                          hint: '0.00',
                                          icon: HugeIcon(icon: HugeIcons.strokeRoundedDollar01, size: 20),
                                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: theme.colorScheme.outline.withOpacity(0.2),
                                            ),
                                          ),
                                          padding: EdgeInsets.symmetric(horizontal: 16),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _billingCycle,
                                              isExpanded: true,
                                              items: ['monthly', 'yearly'].map((cycle) {
                                                return DropdownMenuItem(
                                                  value: cycle,
                                                  child: Text(cycle.substring(0, 1).toUpperCase() + cycle.substring(1)),
                                                );
                                              }).toList(),
                                              onChanged: (value) {
                                                HapticFeedback.selectionClick();
                                                setState(() => _billingCycle = value!);
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 16),
                                  InkWell(
                                    onTap: () async {
                                      HapticFeedback.lightImpact();
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: _nextRenewalDate ?? DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now().add(Duration(days: 365 * 2)),
                                      );
                                      if (date != null) {
                                        setState(() => _nextRenewalDate = date);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: theme.colorScheme.outline.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          HugeIcon(icon: HugeIcons.strokeRoundedCalendar03, 
                                            color: theme.colorScheme.primary, size: 18),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Next Renewal',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  _nextRenewalDate == null
                                                      ? 'Tap to select'
                                                      : '${_nextRenewalDate!.day}/${_nextRenewalDate!.month}/${_nextRenewalDate!.year}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 14),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Promotional Price Section
                AnimatedSize(
                  duration: Duration(milliseconds: 300),
                  child: _isSubscription
                      ? _buildGlassmorphicSection(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  HugeIcon(icon: HugeIcons.strokeRoundedTag01, 
                                    color: theme.colorScheme.primary, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Promotional Price',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: _isPromotionalPrice,
                                    onChanged: (value) {
                                      HapticFeedback.lightImpact();
                                      setState(() => _isPromotionalPrice = value);
                                    },
                                  ),
                                ],
                              ),
                              
                              AnimatedSize(
                                duration: Duration(milliseconds: 300),
                                child: _isPromotionalPrice
                                    ? Column(
                                        children: [
                                          SizedBox(height: 16),
                                          _buildModernTextField(
                                            controller: _regularPriceController,
                                            label: 'Regular Price',
                                            hint: '0.00',
                                            icon: HugeIcon(icon: HugeIcons.strokeRoundedDollar01, size: 20),
                                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                                          ),
                                          SizedBox(height: 16),
                                          InkWell(
                                            onTap: () async {
                                              HapticFeedback.lightImpact();
                                              final date = await showDatePicker(
                                                context: context,
                                                initialDate: _promotionEndsDate ?? DateTime.now(),
                                                firstDate: DateTime.now(),
                                                lastDate: DateTime.now().add(Duration(days: 365)),
                                              );
                                              if (date != null) {
                                                setState(() => _promotionEndsDate = date);
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              padding: EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: theme.colorScheme.outline.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  HugeIcon(icon: HugeIcons.strokeRoundedCalendarRemove01, 
                                                    color: theme.colorScheme.error, size: 18),
                                                  SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          'Promotion Ends',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: theme.colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          _promotionEndsDate == null
                                                              ? 'Tap to select'
                                                              : '${_promotionEndsDate!.day}/${_promotionEndsDate!.month}/${_promotionEndsDate!.year}',
                                                          style: TextStyle(
                                                            fontSize: 16,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 14),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : SizedBox.shrink(),
                              ),
                            ],
                          ),
                        )
                      : SizedBox.shrink(),
                ),
                
                SizedBox(height: 16),
                
                // Notes Section
                _buildGlassmorphicSection(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          HugeIcon(icon: HugeIcons.strokeRoundedStickyNote02, 
                            color: theme.colorScheme.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Notes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: _notesController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'Add any additional notes...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassmorphicSection(BuildContext context,
      {required Widget child}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            if (required)
              Text(
                ' *',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onTap: () => HapticFeedback.selectionClick(),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
