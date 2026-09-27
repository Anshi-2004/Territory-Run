import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_constants.dart';
import '../models/player_model.dart';
import '../models/territory_cell.dart';
import '../models/leaderboard_item.dart';
import '../models/notification_item.dart';

class ApiService {
  String? _token;

  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  Map<String, String> _headers({bool auth = true}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth && _token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // Auth
  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    String colorHex = "#00E5FF",
  }) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.registerEndpoint}");
    final res = await http.post(
      uri,
      headers: _headers(auth: false),
      body: jsonEncode({
        "email": email,
        "username": username,
        "password": password,
        "color_hex": colorHex,
      }),
    );

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      await saveToken(data['access_token']);
      return data;
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? "Registration failed");
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.loginEndpoint}");
    final res = await http.post(
      uri,
      headers: _headers(auth: false),
      body: jsonEncode({
        "email": email,
        "password": password,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await saveToken(data['access_token']);
      return data;
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? "Invalid login credentials");
    }
  }

  // Player
  Future<PlayerModel> getMe() async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.meEndpoint}");
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      return PlayerModel.fromJson(jsonDecode(res.body));
    } else {
      throw Exception("Failed to load profile");
    }
  }

  Future<PlayerModel> updateMe({String? username, String? colorHex}) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.meEndpoint}");
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (colorHex != null) body['color_hex'] = colorHex;

    final res = await http.patch(uri, headers: _headers(), body: jsonEncode(body));
    if (res.statusCode == 200) {
      return PlayerModel.fromJson(jsonDecode(res.body));
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? "Failed to update profile");
    }
  }

  // Routes & Tracking
  Future<String> startRoute({String activityType = "walk"}) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.startRouteEndpoint}");
    final res = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({"activity_type": activityType}),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(res.body);
      return data['route_id'];
    } else {
      throw Exception("Failed to start tracking session");
    }
  }

  Future<Map<String, dynamic>> sendPings(String routeId, List<Map<String, dynamic>> pings) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.pingRouteEndpoint(routeId)}");
    final res = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({"pings": pings}),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? "Ping submission failed");
    }
  }

  Future<Map<String, dynamic>> endRoute(String routeId) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.endRouteEndpoint(routeId)}");
    final res = await http.post(uri, headers: _headers());
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    } else {
      throw Exception("Failed to end tracking session");
    }
  }

  // Territory
  Future<List<TerritoryCellModel>> fetchCellsInViewport({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    final uri = Uri.parse(
      "${ApiConstants.baseUrl}${ApiConstants.territoryCellsEndpoint}?bbox=$minLng,$minLat,$maxLng,$maxLat",
    );
    final res = await http.get(uri, headers: _headers(auth: false));
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((item) => TerritoryCellModel.fromJson(item)).toList();
    } else {
      return [];
    }
  }

  // Leaderboard
  Future<List<LeaderboardItem>> fetchLeaderboard(String scope) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.leaderboardEndpoint(scope)}");
    final res = await http.get(uri, headers: _headers(auth: false));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final List list = data['entries'] ?? [];
      return list.map((item) => LeaderboardItem.fromJson(item)).toList();
    } else {
      return [];
    }
  }

  // Notifications
  Future<List<NotificationItem>> fetchNotifications() async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.notificationsEndpoint}");
    final res = await http.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final List list = jsonDecode(res.body);
      return list.map((item) => NotificationItem.fromJson(item)).toList();
    } else {
      return [];
    }
  }

  Future<void> markNotificationRead(String id) async {
    final uri = Uri.parse("${ApiConstants.baseUrl}${ApiConstants.readNotificationEndpoint(id)}");
    await http.post(uri, headers: _headers());
  }
}
