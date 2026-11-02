import 'package:yallanews/services/server_api_service.dart';

void main() async {
  try {
    print('Testing ServerApiService.getNews()...');
    final articles = await ServerApiService.getNews(limit: 20);
    print('Got articles: ${articles.length}');
    for (var a in articles) {
      print(' - [${a.category}] ${a.title}');
      print('   url: ${a.url}');
      print('   imageUrl: ${a.imageUrl}');
      print('   content len: ${a.content.length}, summary len: ${a.summary.length}');
    }
    
    print('\nTesting ServerApiService.getNews(language: "ar")...');
    final arArticles = await ServerApiService.getNews(limit: 20, language: 'ar');
    print('Got ar articles: ${arArticles.length}');
    for (var a in arArticles) {
      print(' - [${a.category}] ${a.title}');
    }
  } catch (e, st) {
    print('ERROR: $e');
    print(st);
  }
}
