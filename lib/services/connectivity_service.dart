import 'package:connectivity_plus/connectivity_plus.dart';

/// Thin wrapper around connectivity_plus providing app-wide connectivity helpers.
class ConnectivityService {
  ConnectivityService._();

  /// Returns true **only** when the device is connected via Wi-Fi.
  static Future<bool> isWifi() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  /// Returns true when the device has any internet access (Wi-Fi or mobile data).
  static Future<bool> hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }
}
