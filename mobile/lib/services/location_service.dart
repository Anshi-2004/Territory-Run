import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';

class LocationPing {
  final LatLng point;
  final DateTime timestamp;

  LocationPing(this.point, this.timestamp);

  Map<String, dynamic> toJson() => {
    "lat": point.latitude,
    "lng": point.longitude,
    "timestamp": timestamp.toUtc().toIso8601String(),
  };
}

class LocationService {
  LatLng _currentLocation = const LatLng(37.7749, -122.4194); // Default: San Francisco / City center
  bool _isSimulating = false;
  Timer? _simulationTimer;
  final _locationController = StreamController<LocationPing>.broadcast();

  LatLng get currentLocation => _currentLocation;
  bool get isSimulating => _isSimulating;
  Stream<LocationPing> get onLocationChanged => _locationController.stream;

  void setLocation(LatLng loc) {
    _currentLocation = loc;
    _locationController.add(LocationPing(_currentLocation, DateTime.now()));
  }

  /// Starts realistic synthetic movement simulation along a heading
  /// speedKmh: walking (5 km/h), jogging (9 km/h), running (12 km/h)
  void startSimulation({
    double speedKmh = 6.0,
    double headingDegrees = 45.0,
    LatLng? startFrom,
  }) {
    stopSimulation();
    if (startFrom != null) {
      _currentLocation = startFrom;
    }
    _isSimulating = true;

    // Emit 1 ping per second
    const intervalSec = 1.0;
    final speedMps = speedKmh / 3.6;
    final distanceStepM = speedMps * intervalSec;

    // Convert distance step to degrees latitude and longitude
    final latRad = _currentLocation.latitude * (pi / 180.0);
    final headingRad = headingDegrees * (pi / 180.0);

    final dLat = (distanceStepM * cos(headingRad)) / 111320.0;
    final dLng = (distanceStepM * sin(headingRad)) / (111320.0 * cos(latRad));

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Add slight organic wandering (-5 to +5 degrees)
      final wander = (Random().nextDouble() - 0.5) * 0.1;
      _currentLocation = LatLng(
        _currentLocation.latitude + dLat + (wander * dLat),
        _currentLocation.longitude + dLng + (wander * dLng),
      );
      _locationController.add(LocationPing(_currentLocation, DateTime.now()));
    });
  }

  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
  }

  void dispose() {
    stopSimulation();
    _locationController.close();
  }
}
