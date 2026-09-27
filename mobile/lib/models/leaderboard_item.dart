import 'package:flutter/material.dart';

class LeaderboardItem {
  final int rank;
  final String playerId;
  final String username;
  final String colorHex;
  final double totalTerritoryAreaM2;
  final double totalTerritoryAreaKm2;

  LeaderboardItem({
    required this.rank,
    required this.playerId,
    required this.username,
    required this.colorHex,
    required this.totalTerritoryAreaM2,
    required this.totalTerritoryAreaKm2,
  });

  Color get displayColor {
    try {
      final hex = colorHex.replaceAll("#", "");
      return Color(int.parse("0xFF$hex"));
    } catch (_) {
      return const Color(0xFF3388FF);
    }
  }

  factory LeaderboardItem.fromJson(Map<String, dynamic> json) {
    return LeaderboardItem(
      rank: json['rank'] ?? 0,
      playerId: json['player_id'] ?? '',
      username: json['username'] ?? '',
      colorHex: json['color_hex'] ?? '#3388FF',
      totalTerritoryAreaM2: (json['total_territory_area_m2'] as num?)?.toDouble() ?? 0.0,
      totalTerritoryAreaKm2: (json['total_territory_area_km2'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
