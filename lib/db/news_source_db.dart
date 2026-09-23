import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class NewsSource {
  final int? id;
  final String country;
  final String countryCode;
  final String name;
  final String url;
  final String category;
  final String type;
  final String language; // comma‑separated list
  final int rank;

  NewsSource({
    this.id,
    required this.country,
    required this.countryCode,
    required this.name,
    required this.url,
    required this.category,
    required this.type,
    required this.language,
    required this.rank,
  });

  Map<String, dynamic> toMap() => {
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

  static NewsSource fromMap(Map<String, dynamic> map) => NewsSource(
        id: map['id'] as int?,
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

class NewsSourceDb {
  static final NewsSourceDb instance = NewsSourceDb._internal();
  Database? _db;

  NewsSourceDb._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, 'news_source.db');
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE news_source (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          country TEXT,
          country_code TEXT,
          name TEXT,
          url TEXT,
          category TEXT,
          type TEXT,
          language TEXT,
          rank INTEGER
        );
      ''');
    });
  }

  Future<void> insertAll(List<NewsSource> sources) async {
    final db = await database;
    final batch = db.batch();
    for (var s in sources) {
      batch.insert('news_source', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<NewsSource>> getAll() async {
    final db = await database;
    final maps = await db.query('news_source');
    return List.generate(maps.length, (i) => NewsSource.fromMap(maps[i]));
  }
}
