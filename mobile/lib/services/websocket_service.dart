import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_constants.dart';
import '../models/territory_cell.dart';

typedef CellDeltaCallback = void Function(TerritoryCellModel updatedCell);
typedef NotificationCallback = void Function(Map<String, dynamic> notification);

enum WsConnectionState { disconnected, connecting, connected }

class WebSocketService {
  WebSocketChannel? _mapChannel;
  WebSocketChannel? _playerChannel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  WsConnectionState _connectionState = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _connectionState;

  // Stored state for auto-reconnection
  List<double>? _lastBbox;
  String? _lastPlayerId;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;

  CellDeltaCallback? onCellUpdated;
  NotificationCallback? onNotificationReceived;
  void Function(WsConnectionState state)? onConnectionStateChanged;

  void _setConnectionState(WsConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      onConnectionStateChanged?.call(newState);
    }
  }

  void connectMapViewport({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) {
    _lastBbox = [minLng, minLat, maxLng, maxLat];
    disconnectMap();

    try {
      _setConnectionState(WsConnectionState.connecting);
      final wsUrl = "${ApiConstants.wsUrl}/ws/map/$minLng,$minLat,$maxLng,$maxLat";
      _mapChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _mapChannel!.stream.listen(
        (message) {
          _setConnectionState(WsConnectionState.connected);
          _reconnectAttempts = 0;
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
          } catch (e) {
            debugPrint("Error parsing WebSocket message: $e");
          }
        },
        onError: (err) {
          debugPrint("WebSocket map channel error: $err");
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
      );

      _startHeartbeat();
    } catch (e) {
      debugPrint("WebSocket connection failed: $e");
      _handleDisconnect();
    }
  }

  void connectPlayerAlerts(String playerId) {
    _lastPlayerId = playerId;
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
          } catch (e) {
            debugPrint("Error parsing player alert: $e");
          }
        },
        onError: (err) {
          debugPrint("Player WebSocket error: $err");
        },
        onDone: () {},
      );
    } catch (e) {
      debugPrint("Player WebSocket failed to connect: $e");
    }
  }

  void updateViewportBbox(double minLng, double minLat, double maxLng, double maxLat) {
    _lastBbox = [minLng, minLat, maxLng, maxLat];
    if (_mapChannel != null && _connectionState == WsConnectionState.connected) {
      try {
        _mapChannel!.sink.add("update_bbox:$minLng,$minLat,$maxLng,$maxLat");
      } catch (_) {}
    }
  }

  void _handleDisconnect() {
    if (_isDisposed) return;
    _setConnectionState(WsConnectionState.disconnected);

    // Schedule auto-reconnect with exponential backoff (up to 15s)
    _reconnectTimer?.cancel();
    final delaySeconds = (_reconnectAttempts < 5) ? (2 << _reconnectAttempts) : 15;
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_isDisposed) return;
      if (_lastBbox != null) {
        connectMapViewport(
          minLng: _lastBbox![0],
          minLat: _lastBbox![1],
          maxLng: _lastBbox![2],
          maxLat: _lastBbox![3],
        );
      }
      if (_lastPlayerId != null) {
        connectPlayerAlerts(_lastPlayerId!);
      }
    });
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
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    disconnectMap();
    disconnectPlayer();
    _setConnectionState(WsConnectionState.disconnected);
  }
}
