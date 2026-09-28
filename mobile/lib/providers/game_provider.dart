import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/location_service.dart';
import '../models/territory_cell.dart';
import '../models/leaderboard_item.dart';
import '../models/notification_item.dart';

class GameProvider with ChangeNotifier {
  final ApiService apiService;
  final WebSocketService wsService = WebSocketService();
  final LocationService locationService = LocationService();

  // Tracking Mode (Real GPS vs Demo Simulation)
  TrackingMode _trackingMode = TrackingMode.realGps;
  TrackingMode get trackingMode => _trackingMode;

  // Territory Map State
  final Map<String, TerritoryCellModel> _cellsMap = {};
  List<TerritoryCellModel> get cells => _cellsMap.values.toList();
  bool _isLoadingCells = false;
  bool get isLoadingCells => _isLoadingCells;

  // Currently inspected cell on map tap
  TerritoryCellModel? _inspectedCell;
  TerritoryCellModel? get inspectedCell => _inspectedCell;

  // Active Tracking Session & Circle Loop State
  bool _isTracking = false;
  String? _activeRouteId;
  String _activityType = "walk"; // walk | jog | run
  DateTime? _sessionStartTime;
  int _elapsedSeconds = 0;
  double _sessionDistanceM = 0.0;
  int _sessionCapturedCount = 0;
  final List<LatLng> _sessionPath = [];
  LatLng? _loopStartPoint;
  Timer? _sessionTimer;
  StreamSubscription? _locationSub;

  // Circle Completion Celebration Result
  Map<String, dynamic>? _lastCircleCelebration;
  Map<String, dynamic>? get lastCircleCelebration => _lastCircleCelebration;

  bool get isTracking => _isTracking;
  String? get activeRouteId => _activeRouteId;
  String get activityType => _activityType;
  LatLng? get loopStartPoint => _loopStartPoint;

  int get elapsedSeconds {
    if (!_isTracking || _sessionStartTime == null) return _elapsedSeconds;
    return DateTime.now().difference(_sessionStartTime!).inSeconds;
  }

  double get sessionDistanceM => _sessionDistanceM;
  int get sessionCapturedCount => _sessionCapturedCount;
  List<LatLng> get sessionPath => List.unmodifiable(_sessionPath);
  LatLng get currentLocation => locationService.currentLocation;
  double get currentSpeedKmh => locationService.currentSpeedKmh;
  double get currentHeading => locationService.currentHeading;

  /// Distance from current position back to the circle loop start
  double get distanceToLoopStart {
    if (_loopStartPoint == null || _sessionPath.isEmpty) return double.infinity;
    return const Distance().as(LengthUnit.Meter, _sessionPath.last, _loopStartPoint!);
  }

  /// Runner has formed a path long enough (>= 80m and >= 6 points) to qualify for circle closure
  bool get canCloseLoop => _isTracking && _sessionPath.length >= 6 && _sessionDistanceM >= 80.0;

  /// Runner is approaching the start point (within 55m) and ready to close the circle
  bool get isNearLoopStart => canCloseLoop && distanceToLoopStart <= 55.0;

  String get currentPaceString {
    final secs = elapsedSeconds;
    if (_sessionDistanceM <= 10 || secs < 4) return "--:-- /km";
    final km = _sessionDistanceM / 1000.0;
    final minsPerKm = (secs / 60.0) / km;
    if (minsPerKm > 40 || minsPerKm.isNaN || minsPerKm.isInfinite) {
      return "--:-- /km";
    }
    final m = minsPerKm.floor();
    final s = ((minsPerKm - m) * 60).round();
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')} /km";
  }

  WsConnectionState get wsConnectionState => wsService.connectionState;

  // Leaderboard State
  List<LeaderboardItem> _leaderboard = [];
  String _currentScope = "city"; // local | city | country | global
  bool _isLoadingLeaderboard = false;
  List<LeaderboardItem> get leaderboard => _leaderboard;
  String get currentScope => _currentScope;
  bool get isLoadingLeaderboard => _isLoadingLeaderboard;

  // Notifications State
  List<NotificationItem> _notifications = [];
  bool _isLoadingNotifications = false;
  List<NotificationItem> get notifications => _notifications;
  bool get isLoadingNotifications => _isLoadingNotifications;
  int get unreadNotificationsCount => _notifications.where((n) => !n.isRead).length;

  // Last Displaced Event Alert (for Toast / Dialog)
  Map<String, dynamic>? _lastDisplacedAlert;
  Map<String, dynamic>? get lastDisplacedAlert => _lastDisplacedAlert;

  GameProvider(this.apiService) {
    _initWebSockets();
  }

  void _initWebSockets() {
    wsService.onCellUpdated = (updatedCell) {
      _cellsMap[updatedCell.h3Index] = updatedCell;
      notifyListeners();
    };

    wsService.onNotificationReceived = (alertData) {
      _lastDisplacedAlert = alertData;
      loadNotifications();
      notifyListeners();
    };

    wsService.onConnectionStateChanged = (_) {
      notifyListeners();
    };
  }

  void setTrackingMode(TrackingMode mode) {
    _trackingMode = mode;
    locationService.setMode(mode);
    notifyListeners();
  }

  void inspectCell(TerritoryCellModel? cell) {
    _inspectedCell = cell;
    notifyListeners();
  }

  void clearDisplacedAlert() {
    _lastDisplacedAlert = null;
    notifyListeners();
  }

  void clearCircleCelebration() {
    _lastCircleCelebration = null;
    notifyListeners();
  }

  /// Sets map position to a specific location (e.g., from search or GPS)
  void jumpToLocation(LatLng loc) {
    locationService.setLocation(loc);
    updateViewportBbox(
      loc.longitude - 0.04,
      loc.latitude - 0.04,
      loc.longitude + 0.04,
      loc.latitude + 0.04,
    );
    fetchViewportCells(
      minLng: loc.longitude - 0.04,
      minLat: loc.latitude - 0.04,
      maxLng: loc.longitude + 0.04,
      maxLat: loc.latitude + 0.04,
    );
    notifyListeners();
  }

  /// Acquires real GPS or IP location to show user's actual local neighborhood
  Future<LatLng?> initUserLocation() async {
    final loc = await locationService.initDeviceLocation();
    if (loc != null) {
      jumpToLocation(loc);
    }
    return loc;
  }

  void connectRealtime(String playerId, LatLng center) {
    wsService.connectPlayerAlerts(playerId);
    updateViewportBbox(
      center.longitude - 0.05,
      center.latitude - 0.05,
      center.longitude + 0.05,
      center.latitude + 0.05,
    );
  }

  Future<void> fetchViewportCells({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    _isLoadingCells = true;
    notifyListeners();
    try {
      final fetched = await apiService.fetchCellsInViewport(
        minLng: minLng,
        minLat: minLat,
        maxLng: maxLng,
        maxLat: maxLat,
      );
      for (final cell in fetched) {
        _cellsMap[cell.h3Index] = cell;
      }
    } catch (_) {}
    _isLoadingCells = false;
    notifyListeners();
  }

  void updateViewportBbox(double minLng, double minLat, double maxLng, double maxLat) {
    wsService.connectMapViewport(
      minLng: minLng,
      minLat: minLat,
      maxLng: maxLng,
      maxLat: maxLat,
    );
  }

  // --- Tracking Session & Circle Enclosure Control ---

  Future<bool> startTrackingSession({
    String activityType = "walk",
    TrackingMode? mode,
    bool simulate = false,
  }) async {
    final effectiveMode = mode ?? (simulate ? TrackingMode.simulation : _trackingMode);
    _trackingMode = effectiveMode;

    try {
      final routeId = await apiService.startRoute(activityType: activityType);
      _activeRouteId = routeId;
      _activityType = activityType;
      _isTracking = true;
      _sessionStartTime = DateTime.now();
      _elapsedSeconds = 0;
      _sessionDistanceM = 0.0;
      _sessionCapturedCount = 0;
      _sessionPath.clear();
      _sessionPath.add(locationService.currentLocation);
      _loopStartPoint = locationService.currentLocation;

      // Start periodic ticker
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _elapsedSeconds = DateTime.now().difference(_sessionStartTime!).inSeconds;
        notifyListeners();
      });

      // Buffer pings to record path telemetry on server
      final List<Map<String, dynamic>> pingBuffer = [];

      _locationSub?.cancel();
      _locationSub = locationService.onLocationChanged.listen((ping) async {
        _sessionPath.add(ping.point);
        if (_sessionPath.length >= 2) {
          final p1 = _sessionPath[_sessionPath.length - 2];
          final p2 = _sessionPath.last;
          final dist = const Distance().as(LengthUnit.Meter, p1, p2);
          _sessionDistanceM += dist;
        }

        pingBuffer.add(ping.toJson());
        notifyListeners();

        // Auto-close circle if runner physically returns to start point!
        if (canCloseLoop && distanceToLoopStart <= 35.0) {
          closeCurrentLoop();
        }

        // Flush batch pings every 2 points
        if (pingBuffer.length >= 2 && _activeRouteId != null) {
          final toSend = List<Map<String, dynamic>>.from(pingBuffer);
          pingBuffer.clear();
          try {
            await apiService.sendPings(_activeRouteId!, toSend);
          } catch (_) {}
        }
      });

      // Start GPS or circular simulation based on mode
      if (effectiveMode == TrackingMode.realGps) {
        final started = await locationService.startRealGpsTracking();
        if (!started) {
          locationService.startSimulation(
            speedKmh: activityType == "run" ? 11.5 : (activityType == "jog" ? 8.5 : 5.0),
            startFrom: locationService.currentLocation,
            simulateLoop: true,
          );
        }
      } else {
        locationService.startSimulation(
          speedKmh: activityType == "run" ? 11.5 : (activityType == "jog" ? 8.5 : 5.0),
          startFrom: locationService.currentLocation,
          simulateLoop: true,
        );
      }

      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Closes the current running circle, captures all enclosed territory hexagons, and starts the next loop!
  Future<Map<String, dynamic>?> closeCurrentLoop() async {
    if (_activeRouteId == null || _sessionPath.length < 4) return null;

    try {
      final loopPoints = _sessionPath.map((p) {
        return {
          "lat": p.latitude,
          "lng": p.longitude,
          "timestamp": DateTime.now().toUtc().isoformat(),
        };
      }).toList();

      final res = await apiService.closeLoop(
        routeId: _activeRouteId!,
        loopPoints: loopPoints,
        activityType: _activityType,
      );

      final capturedCells = res['captured_cells'] as List?;
      if (capturedCells != null && capturedCells.isNotEmpty) {
        _sessionCapturedCount += capturedCells.length;
        for (final delta in capturedCells) {
          final cell = TerritoryCellModel(
            h3Index: delta['h3_index'] ?? '',
            ownerId: delta['new_owner_id'],
            ownerColorHex: delta['color_hex'],
            ownerScore: (delta['score'] as num?)?.toDouble() ?? 0.0,
            lastClaimedAt: DateTime.now(),
            polygonPoints: TerritoryCellModel.fromJson(delta).polygonPoints,
          );
          _cellsMap[cell.h3Index] = cell;
        }
      }

      _lastCircleCelebration = res;

      // Reset loop start point to current position so the runner can start tracing the next circle!
      _loopStartPoint = _sessionPath.last;
      _sessionPath.clear();
      _sessionPath.add(_loopStartPoint!);

      notifyListeners();
      return res;
    } catch (e) {
      debugPrint("Error closing circle loop: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> stopTrackingSession() async {
    if (_activeRouteId == null) return null;

    _sessionTimer?.cancel();
    _locationSub?.cancel();
    locationService.stopTracking();

    try {
      final res = await apiService.endRoute(_activeRouteId!);
      _isTracking = false;
      _activeRouteId = null;
      _sessionStartTime = null;
      _loopStartPoint = null;
      notifyListeners();
      return res;
    } catch (_) {
      _isTracking = false;
      _activeRouteId = null;
      _sessionStartTime = null;
      _loopStartPoint = null;
      notifyListeners();
      return null;
    }
  }

  // --- Leaderboard ---

  Future<void> setLeaderboardScope(String scope) async {
    _currentScope = scope;
    await loadLeaderboard();
  }

  Future<void> loadLeaderboard() async {
    _isLoadingLeaderboard = true;
    notifyListeners();
    try {
      _leaderboard = await apiService.fetchLeaderboard(_currentScope);
    } catch (_) {}
    _isLoadingLeaderboard = false;
    notifyListeners();
  }

  // --- Notifications ---

  Future<void> loadNotifications() async {
    _isLoadingNotifications = true;
    notifyListeners();
    try {
      _notifications = await apiService.fetchNotifications();
    } catch (_) {}
    _isLoadingNotifications = false;
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    try {
      await apiService.markNotificationRead(id);
      for (final n in _notifications) {
        if (n.id == id) {
          n.isRead = true;
          break;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _locationSub?.cancel();
    wsService.dispose();
    locationService.dispose();
    super.dispose();
  }
}

extension DateTimeIso on DateTime {
  String isoformat() => toUtc().toIso8601String();
}
