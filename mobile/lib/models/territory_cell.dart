import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class TerritoryCellModel {
  final String h3Index;
  final String? ownerId;
  final String? ownerUsername;
  final String? ownerColorHex;
  final double ownerScore;
  final DateTime? lastClaimedAt;
  final List<LatLng> polygonPoints;

  TerritoryCellModel({
    required this.h3Index,
    this.ownerId,
    this.ownerUsername,
    this.ownerColorHex,
    required this.ownerScore,
    this.lastClaimedAt,
    required this.polygonPoints,
  });

  Color get displayColor {
    if (ownerColorHex == null || ownerColorHex!.isEmpty) {
      return Colors.grey.withAlpha(80);
    }
    try {
      final hex = ownerColorHex!.replaceAll("#", "");
      final colorInt = int.parse("0xFF$hex");
      return Color(colorInt);
    } catch (_) {
      return const Color(0xFF3388FF);
    }
  }

  factory TerritoryCellModel.fromJson(Map<String, dynamic> json) {
    List<LatLng> points = [];
    final geojson = json['geojson'];
    if (geojson != null && geojson['coordinates'] != null) {
      final rings = geojson['coordinates'] as List;
      if (rings.isNotEmpty) {
        final outerRing = rings[0] as List;
        for (final coord in outerRing) {
          if (coord is List && coord.length >= 2) {
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            points.add(LatLng(lat, lng));
          }
        }
      }
    }

    return TerritoryCellModel(
      h3Index: json['h3_index'] ?? '',
      ownerId: json['owner_id'],
      ownerUsername: json['owner_username'],
      ownerColorHex: json['owner_color_hex'],
      ownerScore: (json['owner_score'] as num?)?.toDouble() ?? 0.0,
      lastClaimedAt: json['last_claimed_at'] != null
          ? DateTime.parse(json['last_claimed_at'])
          : null,
      polygonPoints: points,
    );
  }
}
