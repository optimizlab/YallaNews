import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../services/category_service.dart';
import '../services/server_api_service.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({Key? key}) : super(key: key);

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    CategoryService.instance.addListener(_onCategoriesChanged);
  }

  @override
  void dispose() {
    CategoryService.instance.removeListener(_onCategoriesChanged);
    super.dispose();
  }

  void _onCategoriesChanged() {
    if (mounted) {
      setState(() {
        _categories = CategoryService.instance.categories;
      });
    }
  }

  Future<void> _loadCategories() async {
    await CategoryService.instance.loadCategories();
    if (mounted) {
      setState(() {
        _categories = CategoryService.instance.categories;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = _categories;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.translate('searchHintExplore'),
                hintStyle: GoogleFonts.outfit(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.translate('mainCategories'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (categories.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.translate('noCategoriesAvailable') ?? 'No categories available'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 900;
                final isTablet = constraints.maxWidth >= 600 && constraints.maxWidth < 900;
                final crossAxisCount = isDesktop ? 4 : (isTablet ? 3 : 2);
                return GridView.count(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: categories.map((category) {
                final id = category['id']?.toString() ?? 'general';
                final name = category['name']?.toString() ?? id;
                final nameEn = category['nameEn']?.toString() ?? id;
                final count = category['newsCount']?.toString() ?? '0';
                final icon = _categoryIcon(id);
                final color = _categoryColor(id);
                final displayKey = (AppLocalizations.of(context)?.locale?.languageCode ?? 'ar') == 'ar' ? name : nameEn;
                return _buildCategoryCard(context, id, displayKey, count, icon, color);
              }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String id) {
    switch (id.toLowerCase()) {
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'technology':
        return Icons.computer_rounded;
      case 'politics':
        return Icons.public_rounded;
      case 'entertainment':
        return Icons.movie_rounded;
      case 'business':
        return Icons.trending_up_rounded;
      case 'health':
        return Icons.medical_services_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _categoryColor(String id) {
    switch (id.toLowerCase()) {
      case 'sports':
        return const Color(0xFF2E7D32);
      case 'technology':
        return const Color(0xFF6A1B9A);
      case 'politics':
        return const Color(0xFFC62828);
      case 'entertainment':
        return const Color(0xFFE65100);
      case 'business':
        return const Color(0xFF1565C0);
      case 'health':
        return const Color(0xFF00838F);
      default:
        return const Color(0xFF546E7A);
    }
  }

  Widget _buildCategoryCard(BuildContext context, String key, String title, String count, IconData icon, Color color) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.translate('newsCount').replaceAll('{count}', count),
              style: GoogleFonts.outfit(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}