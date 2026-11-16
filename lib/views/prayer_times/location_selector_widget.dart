import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../l10n/app_localizations.dart';
import '../../models/city_registry.dart';
import '../../services/prayer/repository.dart';

class LocationSelectorWidget extends StatefulWidget {
  final PrayerTimesRepository repository;
  final ValueChanged<CityEntry> onCitySelected;

  const LocationSelectorWidget({
    super.key,
    required this.repository,
    required this.onCitySelected,
  });

  @override
  State<LocationSelectorWidget> createState() => _LocationSelectorWidgetState();
}

class _LocationSelectorWidgetState extends State<LocationSelectorWidget> {
  String? _selectedCountrySlug;
  List<CityEntry> _filteredCities = [];
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  Future<void> _loadCountries() async {
    final cities = widget.repository.allCities;
    if (!mounted) return;
    setState(() {
      _filteredCities = cities;
      if (cities.isNotEmpty) {
        _selectedCountrySlug = cities.first.countrySlug;
      }
    });
  }

  List<String> _getCountrySlugs() {
    final slugs = <String>{};
    for (final city in widget.repository.allCities) {
      slugs.add(city.countrySlug);
    }
    return slugs.toList();
  }

  List<CityEntry> _getCitiesForCountry(String countrySlug) {
    return widget.repository.citiesByCountry[countrySlug] ?? const [];
  }

  List<CityEntry> _getFilteredCities() {
    final countrySlug = _selectedCountrySlug;
    if (countrySlug == null) return const [];
    final cities = _getCitiesForCountry(countrySlug);
    if (_searchQuery.isEmpty) return cities;
    final query = _searchQuery.toLowerCase();
    return cities.where((c) =>
        c.cityName.toLowerCase().contains(query) ||
        c.countryName.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRtl = _isRtl(l10n);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.translate('selectCity'),
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          _buildCurrentLocationCard(l10n),
          const SizedBox(height: 16),
          Text(
            l10n.translate('currentLocation'),
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildCountrySelector(l10n),
          const SizedBox(height: 12),
          _buildCitySearch(l10n),
          const SizedBox(height: 12),
          _buildCityList(l10n, isRtl),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  bool _isRtl(AppLocalizations l10n) {
    final code = l10n.translate('languageCode');
    return code == 'ar' || code == 'fa';
  }

  Widget _buildCurrentLocationCard(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.my_location_rounded, size: 48,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            l10n.translate('useCurrentLocation'),
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('gpsDenied'),
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _detectGps,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.gps_fixed_rounded, size: 18),
              label: Text(l10n.translate('useCurrentLocation')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _detectGps() async {
    setState(() => _isLoading = true);
    try {
      // The repository uses LocationManager internally which detects via GPS
      final result = await widget.repository.getToday();
      if (!mounted) return;
      if (result.times.cityName.isNotEmpty) {
        final city = CityEntry(
          slug: result.times.citySlug,
          countrySlug: result.times.countrySlug,
          countryIso: result.times.countryIso,
          countryName: result.times.countryName,
          cityName: result.times.cityName,
          latitude: result.times.latitude ?? 0,
          longitude: result.times.longitude ?? 0,
          timeZone: result.times.timeZone,
        );
        widget.onCitySelected(city);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Widget _buildCountrySelector(AppLocalizations l10n) {
    final countrySlugs = _getCountrySlugs();
    return DropdownButtonFormField<String>(
      value: _selectedCountrySlug,
      decoration: InputDecoration(
        labelText: l10n.translate('currentCountry'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: countrySlugs.map((slug) {
        final cities = _getCitiesForCountry(slug);
        final countryName = cities.isNotEmpty ? cities.first.countryName : slug;
        return DropdownMenuItem(
          value: slug,
          child: Text(countryName),
        );
      }).toList(),
      onChanged: (val) {
        if (val == null) return;
        setState(() {
          _selectedCountrySlug = val;
          _searchQuery = '';
        });
      },
    );
  }

  Widget _buildCitySearch(AppLocalizations l10n) {
    return TextField(
      decoration: InputDecoration(
        labelText: l10n.translate('searchCity'),
        hintText: l10n.translate('searchCity'),
        prefixIcon: const Icon(Icons.search_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (val) {
        setState(() => _searchQuery = val);
      },
    );
  }

  Widget _buildCityList(AppLocalizations l10n, bool isRtl) {
    final cities = _getFilteredCities();
    if (cities.isEmpty) {
      return Center(
        child: Text(
          l10n.translate('noArticles'),
          style: GoogleFonts.outfit(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cities.length,
      itemBuilder: (context, index) {
        final city = cities[index];
        return ListTile(
          leading: const Icon(Icons.location_city_rounded),
          title: Text(
            city.cityName,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(city.countryName),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => widget.onCitySelected(city),
        );
      },
    );
  }
}
