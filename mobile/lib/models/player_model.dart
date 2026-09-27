class PlayerModel {
  final String id;
  final String username;
  final String email;
  final String colorHex;
  final double totalTerritoryAreaM2;
  final double totalTerritoryAreaKm2;
  final int coins;
  final DateTime createdAt;

  PlayerModel({
    required this.id,
    required this.username,
    required this.email,
    required this.colorHex,
    required this.totalTerritoryAreaM2,
    required this.totalTerritoryAreaKm2,
    required this.coins,
    required this.createdAt,
  });

  factory PlayerModel.fromJson(Map<String, dynamic> json) {
    return PlayerModel(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      colorHex: json['color_hex'] ?? '#3388FF',
      totalTerritoryAreaM2: (json['total_territory_area'] as num?)?.toDouble() ?? 0.0,
      totalTerritoryAreaKm2: (json['total_territory_area_km2'] as num?)?.toDouble() ?? 0.0,
      coins: json['coins'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  PlayerModel copyWith({
    String? username,
    String? colorHex,
    double? totalTerritoryAreaM2,
    double? totalTerritoryAreaKm2,
    int? coins,
  }) {
    return PlayerModel(
      id: id,
      username: username ?? this.username,
      email: email,
      colorHex: colorHex ?? this.colorHex,
      totalTerritoryAreaM2: totalTerritoryAreaM2 ?? this.totalTerritoryAreaM2,
      totalTerritoryAreaKm2: totalTerritoryAreaKm2 ?? this.totalTerritoryAreaKm2,
      coins: coins ?? this.coins,
      createdAt: createdAt,
    );
  }
}
