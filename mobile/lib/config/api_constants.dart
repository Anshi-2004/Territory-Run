import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiConstants {
  static const String _prefServerUrlKey = "custom_server_url";
  static String? _customBaseUrl;

  static Future<void> loadCustomBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefServerUrlKey);
      if (saved != null && saved.isNotEmpty) {
        _customBaseUrl = saved.trim().replaceAll(RegExp(r'/+$'), '');
      }
    } catch (_) {}
  }

  static Future<void> setCustomBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    _customBaseUrl = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefServerUrlKey, cleaned);
    } catch (_) {}
  }

  static Future<void> resetBaseUrl() async {
    _customBaseUrl = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefServerUrlKey);
    } catch (_) {}
  }

  static String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 is the Android emulator's loopback alias to host 127.0.0.1
      return "http://10.0.2.2:8000";
    }
    // Default to localhost for desktop/iOS
    return "http://127.0.0.1:8000";
  }

  static String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == "https" ? "wss" : "ws";
    final portStr = uri.hasPort ? ":${uri.port}" : "";
    return "$wsScheme://${uri.host}$portStr";
  }

  static const String registerEndpoint = "/auth/register";
  static const String loginEndpoint = "/auth/login";
  static const String meEndpoint = "/players/me";
  static const String startRouteEndpoint = "/routes/start";
  static String pingRouteEndpoint(String routeId) => "/routes/$routeId/ping";
  static String endRouteEndpoint(String routeId) => "/routes/$routeId/end";
  static const String territoryCellsEndpoint = "/territory/cells";
  static String territoryCellDetailEndpoint(String h3Index) => "/territory/cell/$h3Index";
  static String leaderboardEndpoint(String scope) => "/leaderboard/$scope";
  static const String notificationsEndpoint = "/notifications";
  static String readNotificationEndpoint(String id) => "/notifications/$id/read";

  static Future<bool> testEndpoint(String url) async {
    try {
      final res = await http.get(Uri.parse("$url/health")).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
