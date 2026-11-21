import 'dart:io';

class LaunchMode {
  static const LaunchMode externalApplication = LaunchMode._();
  const LaunchMode._();
}

Future<bool> launchUrl(Uri uri, {LaunchMode? mode}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    // On mobile with full plugin, this would call url_launcher
    return false;
  }
  return false;
}

Future<bool> canLaunchUrl(Uri uri) async => false;
