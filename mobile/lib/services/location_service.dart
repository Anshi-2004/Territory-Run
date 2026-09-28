import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum TrackingMode { realGps, simulation }

class LocationPing {
  final LatLng point;
  final DateTime timestamp;
  final double? speedMps;
  final double? headingDegrees;
  final double? accuracyMeters;

  LocationPing(
    this.point,
    this.timestamp, {
    this.speedMps,
    this.headingDegrees,
    this.accuracyMeters,
  });

  double get speedKmh => (speedMps ?? 0.0) * 3.6;

  Map<String, dynamic> toJson() => {
    "lat": point.latitude,
    "lng": point.longitude,
    "timestamp": timestamp.toUtc().toIso8601String(),
  };
}

class LocationService {
  LatLng _currentLocation = const LatLng(19.1258, 73.0004); // Default center fallback
  bool _hasInitialGpsLock = false;
  TrackingMode _mode = TrackingMode.realGps;

  bool _isTrackingGps = false;
  bool _isSimulating = false;

  double _currentSpeedKmh = 0.0;
  double _currentHeading = 0.0;
  double _currentAccuracyM = 0.0;

  StreamSubscription<Position>? _gpsSubscription;
  Timer? _simulationTimer;
  final _locationController = StreamController<LocationPing>.broadcast();

  LatLng get currentLocation => _currentLocation;
  bool get hasInitialGpsLock => _hasInitialGpsLock;
  TrackingMode get mode => _mode;
  bool get isTracking => _isTrackingGps || _isSimulating;
  bool get isTrackingGps => _isTrackingGps;
  bool get isSimulating => _isSimulating;

  double get currentSpeedKmh => _currentSpeedKmh;
  double get currentHeading => _currentHeading;
  double get currentAccuracyM => _currentAccuracyM;

  Stream<LocationPing> get onLocationChanged => _locationController.stream;

  void setMode(TrackingMode newMode) {
    _mode = newMode;
  }

  void setLocation(LatLng loc) {
    _currentLocation = loc;
    _locationController.add(
      LocationPing(_currentLocation, DateTime.now().toUtc()),
    );
  }

  /// Verifies location permission and requests if not determined yet.
  Future<bool> checkPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (e) {
      debugPrint("Error checking location permission: $e");
      return false;
    }
  }

  /// Obtains current real GPS coordinates on startup, with IP Geolocation fallback
  Future<LatLng?> initDeviceLocation() async {
    // 1. Try native GPS
    try {
      final hasPerm = await checkPermission();
      if (hasPerm) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );

        _currentLocation = LatLng(pos.latitude, pos.longitude);
        _currentSpeedKmh = (pos.speed > 0 ? pos.speed : 0) * 3.6;
        _currentHeading = pos.heading;
        _currentAccuracyM = pos.accuracy;
        _hasInitialGpsLock = true;

        _locationController.add(
          LocationPing(
            _currentLocation,
            DateTime.now().toUtc(),
            speedMps: pos.speed,
            headingDegrees: pos.heading,
            accuracyMeters: pos.accuracy,
          ),
        );

        return _currentLocation;
      }
    } catch (e) {
      debugPrint("GPS location check note: $e");
    }

    // 2. Fast IP Geolocation fallback (guarantees user's actual city / area)
    try {
      final ipLoc = await fetchIpLocation();
      if (ipLoc != null) {
        _currentLocation = ipLoc;
        _hasInitialGpsLock = true;
        _locationController.add(
          LocationPing(_currentLocation, DateTime.now().toUtc(), accuracyMeters: 1000),
        );
        return _currentLocation;
      }
    } catch (e) {
      debugPrint("IP fallback note: $e");
    }

    return _currentLocation;
  }

  /// Fallback IP Geolocation to resolve user's local city & area
  Future<LatLng?> fetchIpLocation() async {
    try {
      final res = await http.get(Uri.parse("http://ip-api.com/json/")).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'success') {
          final lat = (data['lat'] as num).toDouble();
          final lon = (data['lon'] as num).toDouble();
          return LatLng(lat, lon);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Free OpenStreetMap search to find and jump to any local neighborhood or street
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final url = "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5";
      final res = await http.get(
        Uri.parse(url),
        headers: {"User-Agent": "TerritoryRunApp/1.0"},
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        return list.map((item) {
          return {
            "display_name": item['display_name'] ?? '',
            "lat": double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0,
            "lng": double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0,
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Begins streaming real GPS points from hardware
  Future<bool> startRealGpsTracking({int distanceFilterMeters = 3}) async {
    stopTracking();
    final hasPerm = await checkPermission();
    if (!hasPerm) {
      return false;
    }

    _mode = TrackingMode.realGps;
    _isTrackingGps = true;

    try {
      final locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilterMeters,
      );

      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position pos) {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _currentSpeedKmh = (pos.speed > 0 ? pos.speed : 0) * 3.6;
          _currentHeading = pos.heading;
          _currentAccuracyM = pos.accuracy;
          _hasInitialGpsLock = true;

          final ping = LocationPing(
            _currentLocation,
            DateTime.now().toUtc(),
            speedMps: pos.speed,
            headingDegrees: pos.heading,
            accuracyMeters: pos.accuracy,
          );

          _locationController.add(ping);
        },
        onError: (err) {
          debugPrint("GPS stream error: $err");
        },
      );

      return true;
    } catch (e) {
      debugPrint("Failed to start GPS stream: $e");
      _isTrackingGps = false;
      return false;
    }
  }

  /// Starts realistic synthetic movement simulation along a circle or route
  void startSimulation({
    double speedKmh = 7.0,
    double headingDegrees = 45.0,
    LatLng? startFrom,
    bool simulateLoop = true,
  }) {
    stopTracking();
    if (startFrom != null) {
      _currentLocation = startFrom;
    }
    _mode = TrackingMode.simulation;
    _isSimulating = true;
    _currentSpeedKmh = speedKmh;

    final startCenter = _currentLocation;
    double currentAngle = 0.0;
    // Radius of circular simulation path ≈ 120 meters
    const radiusM = 130.0;
    final latRad = startCenter.latitude * (pi / 180.0);
    final dLatM = 111320.0;
    final dLngM = 111320.0 * cos(latRad);

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (simulateLoop) {
        // Increment angle along circular loop (completes circle in ~60-70 seconds)
        currentAngle += 0.09;
        final offsetLat = (radiusM * sin(currentAngle)) / dLatM;
        final offsetLng = (radiusM * (1 - cos(currentAngle))) / dLngM;
        _currentLocation = LatLng(startCenter.latitude + offsetLat, startCenter.longitude + offsetLng);
        _currentHeading = (currentAngle * (180.0 / pi)) % 360.0;
      } else {
        final speedMps = speedKmh / 3.6;
        final distanceStepM = speedMps * 1.0;
        final headingRad = headingDegrees * (pi / 180.0);
        final dLat = (distanceStepM * cos(headingRad)) / 111320.0;
        final dLng = (distanceStepM * sin(headingRad)) / (111320.0 * cos(latRad));
        _currentLocation = LatLng(_currentLocation.latitude + dLat, _currentLocation.longitude + dLng);
      }

      final ping = LocationPing(
        _currentLocation,
        DateTime.now().toUtc(),
        speedMps: speedKmh / 3.6,
        headingDegrees: _currentHeading,
        accuracyMeters: 4.0,
      );

      _locationController.add(ping);
    });
  }

  void stopTracking() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _isTrackingGps = false;

    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
  }

  void dispose() {
    stopTracking();
    _locationController.close();
  }
}
