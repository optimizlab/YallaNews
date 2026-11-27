
import 'prayer_times.dart';

/// A city with stable coordinates and IANA timezone used to convert Waqtazan's
/// UTC prayer instants into the city's local time.
class CityEntry {
  const CityEntry({
    required this.slug,
    required this.countrySlug,
    required this.countryIso,
    required this.countryName,
    required this.cityName,
    required this.latitude,
    required this.longitude,
    required this.timeZone,
  });

  final String slug;
  final String countrySlug;
  final String countryIso;
  final String countryName;
  final String cityName;
  final double latitude;
  final double longitude;
  final String timeZone;

  String get cacheKey => '$countrySlug|$slug';
}

/// Self-contained registry of supported cities. No external backend is used;
/// entries can be extended as more cities are needed.
class CityRegistry {
  CityRegistry._();
  static final CityRegistry instance = CityRegistry._();

  static const List<CityEntry> _cities = <CityEntry>[
    // Morocco (Africa/Casablanca)
    CityEntry(
      slug: 'casablanca',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Casablanca',
      latitude: 33.5731,
      longitude: -7.5898,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'rabat',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Rabat',
      latitude: 34.0209,
      longitude: -6.8416,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'marrakech',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Marrakech',
      latitude: 31.6295,
      longitude: -7.9811,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'fez',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Fez',
      latitude: 34.0331,
      longitude: -4.9994,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'tangier',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Tangier',
      latitude: 35.7595,
      longitude: -5.8340,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'agadir',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Agadir',
      latitude: 30.4278,
      longitude: -9.5981,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'meknes',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Meknes',
      latitude: 33.8935,
      longitude: -5.5473,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'oujda',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Oujda',
      latitude: 34.6814,
      longitude: -1.9091,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'kenitra',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Kenitra',
      latitude: 34.2610,
      longitude: -6.5802,
      timeZone: 'Africa/Casablanca',
    ),
    CityEntry(
      slug: 'tetouan',
      countrySlug: 'morocco',
      countryIso: 'MA',
      countryName: 'Morocco',
      cityName: 'Tetouan',
      latitude: 35.5693,
      longitude: -5.3634,
      timeZone: 'Africa/Casablanca',
    ),
    // France (Europe/Paris)
    CityEntry(
      slug: 'paris',
      countrySlug: 'france',
      countryIso: 'FR',
      countryName: 'France',
      cityName: 'Paris',
      latitude: 48.8566,
      longitude: 2.3522,
      timeZone: 'Europe/Paris',
    ),
    CityEntry(
      slug: 'marseille',
      countrySlug: 'france',
      countryIso: 'FR',
      countryName: 'France',
      cityName: 'Marseille',
      latitude: 43.2965,
      longitude: 5.3698,
      timeZone: 'Europe/Paris',
    ),
    CityEntry(
      slug: 'lyon',
      countrySlug: 'france',
      countryIso: 'FR',
      countryName: 'France',
      cityName: 'Lyon',
      latitude: 45.7640,
      longitude: 4.8357,
      timeZone: 'Europe/Paris',
    ),
    // Saudi Arabia (Asia/Riyadh)
    CityEntry(
      slug: 'riyadh',
      countrySlug: 'saudi-arabia',
      countryIso: 'SA',
      countryName: 'Saudi Arabia',
      cityName: 'Riyadh',
      latitude: 24.7136,
      longitude: 46.6753,
      timeZone: 'Asia/Riyadh',
    ),
    CityEntry(
      slug: 'makkah',
      countrySlug: 'saudi-arabia',
      countryIso: 'SA',
      countryName: 'Saudi Arabia',
      cityName: 'Makkah',
      latitude: 21.4225,
      longitude: 39.8262,
      timeZone: 'Asia/Riyadh',
    ),
    CityEntry(
      slug: 'madinah',
      countrySlug: 'saudi-arabia',
      countryIso: 'SA',
      countryName: 'Saudi Arabia',
      cityName: 'Madinah',
      latitude: 24.4539,
      longitude: 39.6134,
      timeZone: 'Asia/Riyadh',
    ),
    CityEntry(
      slug: 'jeddah',
      countrySlug: 'saudi-arabia',
      countryIso: 'SA',
      countryName: 'Saudi Arabia',
      cityName: 'Jeddah',
      latitude: 21.2854,
      longitude: 39.2376,
      timeZone: 'Asia/Riyadh',
    ),
    // Egypt (Africa/Cairo)
    CityEntry(
      slug: 'cairo',
      countrySlug: 'egypt',
      countryIso: 'EG',
      countryName: 'Egypt',
      cityName: 'Cairo',
      latitude: 30.0444,
      longitude: 31.2357,
      timeZone: 'Africa/Cairo',
    ),
    CityEntry(
      slug: 'alexandria',
      countrySlug: 'egypt',
      countryIso: 'EG',
      countryName: 'Egypt',
      cityName: 'Alexandria',
      latitude: 31.2001,
      longitude: 29.9187,
      timeZone: 'Africa/Cairo',
    ),
    // Senegal (Africa/Dakar)
    CityEntry(
      slug: 'dakar',
      countrySlug: 'senegal',
      countryIso: 'SN',
      countryName: 'Senegal',
      cityName: 'Dakar',
      latitude: 14.7167,
      longitude: -17.4677,
      timeZone: 'Africa/Dakar',
    ),
    // United Arab Emirates (Asia/Dubai)
    CityEntry(
      slug: 'abu-dhabi',
      countrySlug: 'united-arab-emirates',
      countryIso: 'AE',
      countryName: 'United Arab Emirates',
      cityName: 'Abu Dhabi',
      latitude: 24.4539,
      longitude: 54.3773,
      timeZone: 'Asia/Dubai',
    ),
    CityEntry(
      slug: 'dubai',
      countrySlug: 'united-arab-emirates',
      countryIso: 'AE',
      countryName: 'United Arab Emirates',
      cityName: 'Dubai',
      latitude: 25.2048,
      longitude: 55.2708,
      timeZone: 'Asia/Dubai',
    ),
    // Turkey (Europe/Istanbul)
    CityEntry(
      slug: 'istanbul',
      countrySlug: 'turkey',
      countryIso: 'TR',
      countryName: 'Turkey',
      cityName: 'Istanbul',
      latitude: 41.0082,
      longitude: 28.9784,
      timeZone: 'Europe/Istanbul',
    ),
    // Indonesia (Asia/Jakarta)
    CityEntry(
      slug: 'jakarta',
      countrySlug: 'indonesia',
      countryIso: 'ID',
      countryName: 'Indonesia',
      cityName: 'Jakarta',
      latitude: -6.2088,
      longitude: 106.8456,
      timeZone: 'Asia/Jakarta',
    ),
    // Pakistan (Asia/Karachi)
    CityEntry(
      slug: 'karachi',
      countrySlug: 'pakistan',
      countryIso: 'PK',
      countryName: 'Pakistan',
      cityName: 'Karachi',
      latitude: 24.8607,
      longitude: 67.0011,
      timeZone: 'Asia/Karachi',
    ),
    // Malaysia (Asia/Kuala_Lumpur)
    CityEntry(
      slug: 'kuala-lumpur',
      countrySlug: 'malaysia',
      countryIso: 'MY',
      countryName: 'Malaysia',
      cityName: 'Kuala Lumpur',
      latitude: 3.1390,
      longitude: 101.6869,
      timeZone: 'Asia/Kuala_Lumpur',
    ),
    // Iran (Asia/Tehran)
    CityEntry(
      slug: 'tehran',
      countrySlug: 'iran',
      countryIso: 'IR',
      countryName: 'Iran',
      cityName: 'Tehran',
      latitude: 35.6762,
      longitude: 51.4151,
      timeZone: 'Asia/Tehran',
    ),
    // Algeria (Africa/Algiers)
    CityEntry(
      slug: 'algiers',
      countrySlug: 'algeria',
      countryIso: 'DZ',
      countryName: 'Algeria',
      cityName: 'Algiers',
      latitude: 36.7538,
      longitude: 3.0588,
      timeZone: 'Africa/Algiers',
    ),
    CityEntry(
      slug: 'oran',
      countrySlug: 'algeria',
      countryIso: 'DZ',
      countryName: 'Algeria',
      cityName: 'Oran',
      latitude: 35.6969,
      longitude: -0.6331,
      timeZone: 'Africa/Algiers',
    ),
    CityEntry(
      slug: 'constantine',
      countrySlug: 'algeria',
      countryIso: 'DZ',
      countryName: 'Algeria',
      cityName: 'Constantine',
      latitude: 36.3650,
      longitude: 6.6147,
      timeZone: 'Africa/Algiers',
    ),
    // Tunisia (Africa/Tunis)
    CityEntry(
      slug: 'tunis',
      countrySlug: 'tunisia',
      countryIso: 'TN',
      countryName: 'Tunisia',
      cityName: 'Tunis',
      latitude: 36.8065,
      longitude: 10.1815,
      timeZone: 'Africa/Tunis',
    ),
    CityEntry(
      slug: 'sfax',
      countrySlug: 'tunisia',
      countryIso: 'TN',
      countryName: 'Tunisia',
      cityName: 'Sfax',
      latitude: 34.7406,
      longitude: 10.7603,
      timeZone: 'Africa/Tunis',
    ),
    // Jordan (Asia/Amman)
    CityEntry(
      slug: 'amman',
      countrySlug: 'jordan',
      countryIso: 'JO',
      countryName: 'Jordan',
      cityName: 'Amman',
      latitude: 31.9454,
      longitude: 35.9284,
      timeZone: 'Asia/Amman',
    ),
    // Palestine (Asia/Hebron)
    CityEntry(
      slug: 'jerusalem',
      countrySlug: 'palestine',
      countryIso: 'PS',
      countryName: 'Palestine',
      cityName: 'Jerusalem',
      latitude: 31.7683,
      longitude: 35.2137,
      timeZone: 'Asia/Hebron',
    ),
    CityEntry(
      slug: 'gaza',
      countrySlug: 'palestine',
      countryIso: 'PS',
      countryName: 'Palestine',
      cityName: 'Gaza City',
      latitude: 31.5017,
      longitude: 34.4668,
      timeZone: 'Asia/Hebron',
    ),
    CityEntry(
      slug: 'ramallah',
      countrySlug: 'palestine',
      countryIso: 'PS',
      countryName: 'Palestine',
      cityName: 'Ramallah',
      latitude: 31.8994,
      longitude: 35.2042,
      timeZone: 'Asia/Hebron',
    ),
    // Lebanon (Asia/Beirut)
    CityEntry(
      slug: 'beirut',
      countrySlug: 'lebanon',
      countryIso: 'LB',
      countryName: 'Lebanon',
      cityName: 'Beirut',
      latitude: 33.8938,
      longitude: 35.5018,
      timeZone: 'Asia/Beirut',
    ),
    // Iraq (Asia/Baghdad)
    CityEntry(
      slug: 'baghdad',
      countrySlug: 'iraq',
      countryIso: 'IQ',
      countryName: 'Iraq',
      cityName: 'Baghdad',
      latitude: 33.3153,
      longitude: 44.3661,
      timeZone: 'Asia/Baghdad',
    ),
    // Sudan (Africa/Khartoum)
    CityEntry(
      slug: 'khartoum',
      countrySlug: 'sudan',
      countryIso: 'SD',
      countryName: 'Sudan',
      cityName: 'Khartoum',
      latitude: 15.5007,
      longitude: 32.5599,
      timeZone: 'Africa/Khartoum',
    ),
    // Libya (Africa/Tripoli)
    CityEntry(
      slug: 'tripoli',
      countrySlug: 'libya',
      countryIso: 'LY',
      countryName: 'Libya',
      cityName: 'Tripoli',
      latitude: 32.8872,
      longitude: 13.1913,
      timeZone: 'Africa/Tripoli',
    ),
    // Yemen (Asia/Aden)
    CityEntry(
      slug: 'sanaa',
      countrySlug: 'yemen',
      countryIso: 'YE',
      countryName: 'Yemen',
      cityName: "Sana'a",
      latitude: 15.3694,
      longitude: 44.1910,
      timeZone: 'Asia/Aden',
    ),
    CityEntry(
      slug: 'aden',
      countrySlug: 'yemen',
      countryIso: 'YE',
      countryName: 'Yemen',
      cityName: 'Aden',
      latitude: 12.7803,
      longitude: 45.0325,
      timeZone: 'Asia/Aden',
    ),
    // Oman (Asia/Muscat)
    CityEntry(
      slug: 'muscat',
      countrySlug: 'oman',
      countryIso: 'OM',
      countryName: 'Oman',
      cityName: 'Muscat',
      latitude: 23.5880,
      longitude: 58.3829,
      timeZone: 'Asia/Muscat',
    ),
    // Kuwait (Asia/Kuwait)
    CityEntry(
      slug: 'kuwait-city',
      countrySlug: 'kuwait',
      countryIso: 'KW',
      countryName: 'Kuwait',
      cityName: 'Kuwait City',
      latitude: 29.3117,
      longitude: 47.4818,
      timeZone: 'Asia/Kuwait',
    ),
    // Qatar (Asia/Qatar)
    CityEntry(
      slug: 'doha',
      countrySlug: 'qatar',
      countryIso: 'QA',
      countryName: 'Qatar',
      cityName: 'Doha',
      latitude: 25.2867,
      longitude: 51.5334,
      timeZone: 'Asia/Qatar',
    ),
    // Bahrain (Asia/Bahrain)
    CityEntry(
      slug: 'manama',
      countrySlug: 'bahrain',
      countryIso: 'BH',
      countryName: 'Bahrain',
      cityName: 'Manama',
      latitude: 26.2285,
      longitude: 50.5861,
      timeZone: 'Asia/Bahrain',
    ),
    // United States (America/New_York)
    CityEntry(
      slug: 'new-york',
      countrySlug: 'united-states',
      countryIso: 'US',
      countryName: 'United States',
      cityName: 'New York',
      latitude: 40.7128,
      longitude: -74.0060,
      timeZone: 'America/New_York',
    ),
    CityEntry(
      slug: 'los-angeles',
      countrySlug: 'united-states',
      countryIso: 'US',
      countryName: 'United States',
      cityName: 'Los Angeles',
      latitude: 34.0522,
      longitude: -118.2437,
      timeZone: 'America/Los_Angeles',
    ),
    // United Kingdom (Europe/London)
    CityEntry(
      slug: 'london',
      countrySlug: 'united-kingdom',
      countryIso: 'GB',
      countryName: 'United Kingdom',
      cityName: 'London',
      latitude: 51.5074,
      longitude: -0.1278,
      timeZone: 'Europe/London',
    ),
    // Canada (America/Toronto)
    CityEntry(
      slug: 'toronto',
      countrySlug: 'canada',
      countryIso: 'CA',
      countryName: 'Canada',
      cityName: 'Toronto',
      latitude: 43.6532,
      longitude: -79.3832,
      timeZone: 'America/Toronto',
    ),
    // Australia (Australia/Sydney)
    CityEntry(
      slug: 'sydney',
      countrySlug: 'australia',
      countryIso: 'AU',
      countryName: 'Australia',
      cityName: 'Sydney',
      latitude: -33.8688,
      longitude: 151.2093,
      timeZone: 'Australia/Sydney',
    ),
    // Germany (Europe/Berlin)
    CityEntry(
      slug: 'berlin',
      countrySlug: 'germany',
      countryIso: 'DE',
      countryName: 'Germany',
      cityName: 'Berlin',
      latitude: 52.5200,
      longitude: 13.4050,
      timeZone: 'Europe/Berlin',
    ),
    // India (Asia/Kolkata)
    CityEntry(
      slug: 'new-delhi',
      countrySlug: 'india',
      countryIso: 'IN',
      countryName: 'India',
      cityName: 'New Delhi',
      latitude: 28.6139,
      longitude: 77.2090,
      timeZone: 'Asia/Kolkata',
    ),
    CityEntry(
      slug: 'mumbai',
      countrySlug: 'india',
      countryIso: 'IN',
      countryName: 'India',
      cityName: 'Mumbai',
      latitude: 19.0760,
      longitude: 72.8777,
      timeZone: 'Asia/Kolkata',
    ),
    // Bangladesh (Asia/Dhaka)
    CityEntry(
      slug: 'dhaka',
      countrySlug: 'bangladesh',
      countryIso: 'BD',
      countryName: 'Bangladesh',
      cityName: 'Dhaka',
      latitude: 23.8103,
      longitude: 90.4125,
      timeZone: 'Asia/Dhaka',
    ),
    // Nigeria (Africa/Lagos)
    CityEntry(
      slug: 'lagos',
      countrySlug: 'nigeria',
      countryIso: 'NG',
      countryName: 'Nigeria',
      cityName: 'Lagos',
      latitude: 6.5244,
      longitude: 3.3792,
      timeZone: 'Africa/Lagos',
    ),
    // South Africa (Africa/Johannesburg)
    CityEntry(
      slug: 'johannesburg',
      countrySlug: 'south-africa',
      countryIso: 'ZA',
      countryName: 'South Africa',
      cityName: 'Johannesburg',
      latitude: -26.2041,
      longitude: 28.0473,
      timeZone: 'Africa/Johannesburg',
    ),
    // Brazil (America/Sao_Paulo)
    CityEntry(
      slug: 'sao-paulo',
      countrySlug: 'brazil',
      countryIso: 'BR',
      countryName: 'Brazil',
      cityName: 'São Paulo',
      latitude: -23.5505,
      longitude: -46.6333,
      timeZone: 'America/Sao_Paulo',
    ),
    // Japan (Asia/Tokyo)
    CityEntry(
      slug: 'tokyo',
      countrySlug: 'japan',
      countryIso: 'JP',
      countryName: 'Japan',
      cityName: 'Tokyo',
      latitude: 35.6762,
      longitude: 139.6503,
      timeZone: 'Asia/Tokyo',
    ),
    // Singapore (Asia/Singapore)
    CityEntry(
      slug: 'singapore',
      countrySlug: 'singapore',
      countryIso: 'SG',
      countryName: 'Singapore',
      cityName: 'Singapore',
      latitude: 1.3521,
      longitude: 103.8198,
      timeZone: 'Asia/Singapore',
    ),
  ];

  /// All known cities.
  List<CityEntry> get all => List.unmodifiable(_cities);

  /// Lookup by stable country + city slugs.
  CityEntry? bySlug(String countrySlug, String citySlug) {
    try {
      return _cities.firstWhere(
        (c) => c.countrySlug == countrySlug && c.slug == citySlug,
      );
    } catch (_) {
      return null;
    }
  }

  /// Lookup by city slug alone.
  CityEntry? byCitySlug(String citySlug) {
    try {
      return _cities.firstWhere((c) => c.slug == citySlug);
    } catch (_) {
      return null;
    }
  }

  /// All cities for a country slug.
  List<CityEntry> citiesForCountry(String countrySlug) {
    return _cities.where((c) => c.countrySlug == countrySlug).toList();
  }

  /// Distinct country slugs known to the registry.
  List<String> get countrySlugs {
    final set = _cities.map((c) => c.countrySlug).toSet();
    return set.toList();
  }

  /// Find the closest known city to a coordinate (great-circle distance), used
  /// to resolve a GPS fix to a timezone when Waqtazan's nearest endpoint is
  /// unavailable. Returns null when the registry is empty.
  CityEntry? nearest(double latitude, double longitude) {
    if (_cities.isEmpty) return null;
    CityEntry? best;
    double bestDistance = double.infinity;
    for (final city in _cities) {
      final d = _haversine(latitude, longitude, city.latitude, city.longitude);
      if (d < bestDistance) {
        bestDistance = d;
        best = city;
      }
    }
    return best;
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = (0.5 - (0.5 * _cos(dLat))) +
        _cos(_degreesToRadians(lat1)) *
            _cos(_degreesToRadians(lat2)) *
            (0.5 - (0.5 * _cos(dLon)));
    return 2 * earthRadiusKm * _asin(_sqrt(a));
  }

  static double _degreesToRadians(double deg) => deg * (3.141592653589793 / 180);
  static double _cos(double x) {
    var result = 1.0;
    var term = 1.0;
    for (var i = 1; i <= 12; i++) {
      term *= -(x * x) / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  static double _sqrt(double x) {
    if (x < 0) return 0;
    var guess = x;
    for (var i = 0; i < 10; i++) {
      guess = 0.5 * (guess + x / guess);
    }
    return guess;
  }

  static double _asin(double x) {
    if (x <= -1) return -3.141592653589793 / 2;
    if (x >= 1) return 3.141592653589793 / 2;
    return _atan(x / _sqrt(1 - x * x));
  }

  static double _atan(double x) {
    if (x.abs() > 1) {
      return (x > 0 ? 1 : -1) * (3.141592653589793 / 2 - _atan(1 / x));
    }
    var result = 0.0;
    var term = x;
    var xSquared = x * x;
    for (var i = 0; i < 20; i++) {
      result += term;
      term *= -xSquared * (2 * i + 1) / (2 * i + 3);
    }
    return result;
  }
}
