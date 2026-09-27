import 'package:flutter/foundation.dart';

class ApiConstants {
  // In development:
  // For web or desktop: http://127.0.0.1:8000
  // For Android emulator: http://10.0.2.2:8000
  static String get baseUrl {
    if (kIsWeb) {
      return "http://127.0.0.1:8000";
    }
    // Default to localhost
    return "http://127.0.0.1:8000";
  }

  static String get wsUrl {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == "https" ? "wss" : "ws";
    return "$wsScheme://${uri.host}:${uri.port}";
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
}
