import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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
  LatLng _currentLocation = const LatLng(37.7749, -122.4194); // Default center fallback
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
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

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

  /// Obtains current real GPS coordinates on startup to center the map
  Future<LatLng?> initDeviceLocation() async {
    try {
      final hasPerm = await checkPermission();
      if (!hasPerm) return null;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
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
    } catch (e) {
      debugPrint("Error acquiring initial GPS location: $e");
      return null;
    }
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

  /// Starts realistic synthetic movement simulation along a heading
  /// speedKmh: walking (5 km/h), jogging (9 km/h), running (12 km/h)
  void startSimulation({
    double speedKmh = 6.0,
    double headingDegrees = 45.0,
    LatLng? startFrom,
  }) {
    stopTracking();
    if (startFrom != null) {
      _currentLocation = startFrom;
    }
    _mode = TrackingMode.simulation;
    _isSimulating = true;
    _currentSpeedKmh = speedKmh;
    _currentHeading = headingDegrees;

    const intervalSec = 1.0;
    final speedMps = speedKmh / 3.6;
    final distanceStepM = speedMps * intervalSec;

    final latRad = _currentLocation.latitude * (pi / 180.0);
    final headingRad = headingDegrees * (pi / 180.0);

    final dLat = (distanceStepM * cos(headingRad)) / 111320.0;
    final dLng = (distanceStepM * sin(headingRad)) / (111320.0 * cos(latRad));

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final wander = (Random().nextDouble() - 0.5) * 0.1;
      _currentLocation = LatLng(
        _currentLocation.latitude + dLat + (wander * dLat),
        _currentLocation.longitude + dLng + (wander * dLng),
      );

      final ping = LocationPing(
        _currentLocation,
        DateTime.now().toUtc(),
        speedMps: speedMps,
        headingDegrees: headingDegrees,
        accuracyMeters: 5.0,
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
