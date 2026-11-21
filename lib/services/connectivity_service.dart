import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ConnectivityService {
  ConnectivityService._();

  static Future<bool> isWifi() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return true;
    }
    try {
      return true; // Desktop: assume connectivity
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasInternet() async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return true;
    }
    try {
      return true;
    } catch (_) {
      return false;
    }
  }
}
