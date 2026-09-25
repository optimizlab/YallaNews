import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  final docsDir = await getApplicationDocumentsDirectory();
  print('Documents dir: ${docsDir.path}');
  
  final files = docsDir.listSync();
  for (final f in files) {
    print('  ${f.path} (${f is File ? "FILE" : "DIR"})');
  }
  
  final dbFile = File('${docsDir.path}/news_base_source.db');
  print('DB exists: ${dbFile.existsSync()}');
  if (dbFile.existsSync()) {
    print('DB size: ${dbFile.lengthSync()}');
  }
}
