import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_constants.dart';
import '../models/territory_cell.dart';

typedef CellDeltaCallback = void Function(TerritoryCellModel updatedCell);
typedef NotificationCallback = void Function(Map<String, dynamic> notification);

class WebSocketService {
  WebSocketChannel? _mapChannel;
  WebSocketChannel? _playerChannel;
  Timer? _heartbeatTimer;

  CellDeltaCallback? onCellUpdated;
  NotificationCallback? onNotificationReceived;

  void connectMapViewport({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) {
    disconnectMap();
    try {
      final wsUrl = "${ApiConstants.wsUrl}/ws/map/$minLng,$minLat,$maxLng,$maxLat";
      _mapChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _mapChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'cell_update' && data['delta'] != null) {
              final delta = data['delta'];
              final cell = TerritoryCellModel(
                h3Index: delta['h3_index'] ?? '',
                ownerId: delta['new_owner_id'],
                ownerColorHex: delta['color_hex'],
                ownerScore: (delta['score'] as num?)?.toDouble() ?? 0.0,
                lastClaimedAt: DateTime.now(),
                polygonPoints: _parseGeoJsonPoints(delta['geojson']),
              );
              onCellUpdated?.call(cell);
            }
          } catch (_) {}
        },
        onError: (err) {},
        onDone: () {},
      );

      _startHeartbeat();
    } catch (_) {}
  }

  void connectPlayerAlerts(String playerId) {
    disconnectPlayer();
    try {
      final wsUrl = "${ApiConstants.wsUrl}/ws/player/$playerId";
      _playerChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _playerChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'notification' && data['data'] != null) {
              onNotificationReceived?.call(data['data']);
            }
          } catch (_) {}
        },
        onError: (err) {},
        onDone: () {},
      );
    } catch (_) {}
  }

  void updateViewportBbox(double minLng, double minLat, double maxLng, double maxLat) {
    if (_mapChannel != null) {
      try {
        _mapChannel!.sink.add("update_bbox:$minLng,$minLat,$maxLng,$maxLat");
      } catch (_) {}
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      try {
        _mapChannel?.sink.add("ping");
        _playerChannel?.sink.add("ping");
      } catch (_) {}
    });
  }

  List<LatLng> _parseGeoJsonPoints(dynamic geojson) {
    final points = <LatLng>[];
    if (geojson != null && geojson['coordinates'] != null) {
      final rings = geojson['coordinates'] as List;
      if (rings.isNotEmpty) {
        final outer = rings[0] as List;
        for (final coord in outer) {
          if (coord is List && coord.length >= 2) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            points.add(LatLng(lat, lng));
          }
        }
      }
    }
    return points;
  }

  void disconnectMap() {
    _mapChannel?.sink.close();
    _mapChannel = null;
  }

  void disconnectPlayer() {
    _playerChannel?.sink.close();
    _playerChannel = null;
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    disconnectMap();
    disconnectPlayer();
  }
}
