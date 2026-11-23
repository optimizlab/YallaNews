import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/city_registry.dart';
import '../services/app_settings.dart';
import 'splash_page.dart';
import 'auth/login_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({Key? key}) : super(key: key);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _WelcomeStep { language, location }

class _WelcomePageState extends State<WelcomePage> {
  _WelcomeStep _step = _WelcomeStep.language;
  bool _isLoading = false;

  String? _selectedLanguage;
  String? _selectedCountrySlug;
  CityEntry? _selectedCity;
  String _citySearch = '';

  static const Map<String, String> _countryLocale = {
    'morocco': 'ar',
    'france': 'fr',
    'saudi-arabia': 'ar',
    'egypt': 'ar',
    'senegal': 'fr',
    'united-arab-emirates': 'ar',
    'turkey': 'tr',
    'indonesia': 'ar',
    'pakistan': 'ar',
    'malaysia': 'ar',
    'iran': 'ar',
  };

  List<String> get _countrySlugs => CityRegistry.instance.countrySlugs..sort();

  String _countryName(String slug, AppLocalizations l10n) {
    final translated = l10n.translate('country_$slug');
    return translated == 'country_$slug' ? slug : translated;
  }

  List<CityEntry> _citiesForCountry(String slug) {
    return CityRegistry.instance.citiesForCountry(slug)..sort(
          (a, b) => a.cityName.compareTo(b.cityName),
        );
  }

  List<CityEntry> _filteredCities() {
    if (_selectedCountrySlug == null) return const [];
    final query = _citySearch.toLowerCase();
    return _citiesForCountry(_selectedCountrySlug!).where((c) =>
        c.cityName.toLowerCase().contains(query) ||
        c.countryName.toLowerCase().contains(query)).toList();
  }

  bool get _canProceed =>
      _selectedLanguage != null &&
      _selectedCountrySlug != null &&
      _selectedCity != null;

  Future<void> _next() async {
    if (_step == _WelcomeStep.location) {
      if (!_canProceed) return;
      await _finish();
      if (mounted) _showAuthOptions();
      return;
    }
    if (_selectedLanguage == null) return;
    setState(() => _step = _WelcomeStep.location);
  }

  Future<void> _goBack() async {
    if (_step == _WelcomeStep.location) {
      setState(() => _step = _WelcomeStep.language);
    }
  }

  Future<void> _finish() async {
    if (!_canProceed) return;
    setState(() => _isLoading = true);
    try {
      final countryEntry = CityRegistry.instance
          .all
          .firstWhere((c) => c.countrySlug == _selectedCountrySlug);
      final locale = _countryLocale[_selectedCountrySlug] ?? 'ar';
      await AppSettings.instance.setLocale(Locale(locale));
      await AppSettings.instance.setCountryCode(countryEntry.countryIso);
      await AppSettings.instance.setPrayerLocation(
          _selectedCountrySlug!, _selectedCity!.slug);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAuthOptions() async {
    await _finish();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A2A4A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(context).translate('connect'),
                  style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _authenticate();
                  },
                  icon: const Icon(Icons.email_rounded, color: Colors.white),
                  label: Text(AppLocalizations.of(context).translate('email'),
                      style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ).copyWith(elevation: WidgetStateProperty.all(0)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _authenticateWithPhone();
                  },
                  icon: const Icon(Icons.phone_rounded, color: Colors.white),
                  label: Text(AppLocalizations.of(context).translate('phone'),
                      style: const TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ).copyWith(elevation: WidgetStateProperty.all(0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await AppSettings.instance.completeFirstRun();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashPage()),
        );
      } else {
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticateWithPhone() async {
    setState(() => _isLoading = true);
    try {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (result == true && mounted) {
        await AppSettings.instance.completeFirstRun();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SplashPage()),
        );
      } else {
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepContent(l10n),
            _buildBottomBar(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(AppLocalizations l10n) {
    switch (_step) {
      case _WelcomeStep.language:
        return _buildLanguagePage(l10n);
      case _WelcomeStep.location:
        return _buildLocationPage(l10n);
    }
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == _WelcomeStep.location) ...[
                OutlinedButton(
                  onPressed: _isLoading ? null : _goBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1565C0),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l10n.translate('back'),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
              ],
              ElevatedButton(
                onPressed: _isLoading || !_canProceed ? null : _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _step == _WelcomeStep.language
                      ? l10n.translate('next')
                      : l10n.translate('getStarted'),
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagePage(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.language_rounded,
                size: 56, color: Color(0xFF1565C0)),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.translate('welcomeLanguageTitle'),
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.translate('welcomeLanguageDesc'),
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                fontSize: 15,
                color: const Color(0xFFB0BEC5),
                height: 1.6),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final entry in [
                {'code': 'ar', 'key': 'languageArabic'},
                {'code': 'en', 'key': 'languageEnglish'},
                {'code': 'fr', 'key': 'languageFrench'},
                {'code': 'tr', 'key': 'languageTurkish'},
              ])
                _buildLanguageChip(l10n, entry['code']!, entry['key']!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageChip(AppLocalizations l10n, String code, String key) {
    final selected = _selectedLanguage == code;
    return ChoiceChip(
      label: Text(l10n.translate(key),
          style: GoogleFonts.outfit(
              color: selected ? Colors.white : const Color(0xFFB0BEC5),
              fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) async {
        _selectedLanguage = code;
        await AppSettings.instance.setLocale(Locale(code));
        if (mounted) setState(() {});
        await _next();
      },
      selectedColor: const Color(0xFF1565C0),
      backgroundColor: const Color(0xFF242840),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildLocationPage(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.location_city_rounded,
                      size: 56, color: Color(0xFFC62828)),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.translate('onboardLocationTitle'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.translate('onboardLocationDesc'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                      fontSize: 15,
                      color: const Color(0xFFB0BEC5),
                      height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.translate('onboardCountry'),
            style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
          const SizedBox(height: 8),
          _buildCountryDropdown(l10n),
          const SizedBox(height: 24),
          Text(
            l10n.translate('onboardCity'),
            style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              labelText: l10n.translate('searchCity'),
              hintText: l10n.translate('searchCity'),
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: const Color(0xFF242840),
            ),
            onChanged: (val) => setState(() => _citySearch = val),
          ),
          const SizedBox(height: 12),
          _buildCityList(l10n),
        ],
      ),
    );
  }

  Widget _buildCountryDropdown(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF242840),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCountrySlug,
          isExpanded: true,
          hint: Text(l10n.translate('onboardCountry'),
              style: GoogleFonts.outfit(fontSize: 15, color: Colors.white70)),
          items: _countrySlugs.map((slug) {
            return DropdownMenuItem(
              value: slug,
              child: Text(_countryName(slug, l10n),
                  style: GoogleFonts.outfit(fontSize: 15)),
            );
          }).toList(),
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _selectedCountrySlug = val;
              _selectedCity = null;
              _citySearch = '';
            });
          },
        ),
      ),
    );
  }

  Widget _buildCityList(AppLocalizations l10n) {
    final cities = _filteredCities();
    if (cities.isEmpty) {
      return Center(
        child: Text(
          l10n.translate('noArticles'),
          style: GoogleFonts.outfit(color: const Color(0xFFB0BEC5)),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: cities.map((city) {
        final isSelected = _selectedCity?.cacheKey == city.cacheKey;
        return ListTile(
          leading: const Icon(Icons.location_city_rounded),
          title: Text(
            city.cityName,
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? const Color(0xFF1565C0)
                    : Colors.white),
          ),
          subtitle: Text(_countryName(city.countrySlug, l10n),
              style: const TextStyle(color: Color(0xFFB0BEC5))),
          selected: isSelected,
          trailing: isSelected
              ? const Icon(Icons.check_rounded)
              : const Icon(Icons.chevron_right_rounded),
          onTap: () => setState(() => _selectedCity = city),
        );
      }).toList(),
    );
  }
}
