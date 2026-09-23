class NewsSource {
  final int id;
  final String country;
  final String countryCode;
  final String name;
  final String url;
  final String category;
  final String type;
  final String language;
  final int rank;

  NewsSource({
    required this.id,
    required this.country,
    required this.countryCode,
    required this.name,
    required this.url,
    required this.category,
    required this.type,
    required this.language,
    required this.rank,
  });

  factory NewsSource.fromMap(Map<String, dynamic> map) {
    return NewsSource(
      id: map['id'] as int,
      country: map['country'] as String,
      countryCode: map['country_code'] as String,
      name: map['name'] as String,
      url: map['url'] as String,
      category: map['category'] as String,
      type: map['type'] as String,
      language: map['language'] as String,
      rank: map['rank'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'country': country,
      'country_code': countryCode,
      'name': name,
      'url': url,
      'category': category,
      'type': type,
      'language': language,
      'rank': rank,
    };
  }
}
