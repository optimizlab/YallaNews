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
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}') ?? 0,
      country: '${map['country'] ?? ''}',
      countryCode: '${map['country_code'] ?? ''}',
      name: '${map['name'] ?? ''}',
      url: '${map['url'] ?? ''}',
      category: '${map['category'] ?? 'general_news'}',
      type: '${map['type'] ?? 'digital_news'}',
      language: '${map['language'] ?? 'ar'}',
      rank: map['rank'] is int ? map['rank'] as int : int.tryParse('${map['rank']}') ?? 0,
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
