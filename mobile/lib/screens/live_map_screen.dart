import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  void _loadInitialData() {
    final game = Provider.of<GameProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    final center = game.currentLocation;
    if (auth.player != null) {
      game.connectRealtime(auth.player!.id, center);
    }

    game.fetchViewportCells(
      minLng: center.longitude - 0.04,
      minLat: center.latitude - 0.04,
      maxLng: center.longitude + 0.04,
      maxLat: center.latitude + 0.04,
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final game = context.watch<GameProvider>();
    final player = auth.player;

    // Check if there is an active displaced alert
    if (game.lastDisplacedAlert != null) {
      final alert = game.lastDisplacedAlert!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.neonPink,
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert['message'] ?? "Your territory was captured!",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        game.clearDisplacedAlert();
      });
    }

    // Build Polygons for Map
    final polygons = game.cells.map((cell) {
      final isOwnCell = player != null && cell.ownerId == player.id;
      final fillColor = cell.displayColor.withAlpha(isOwnCell ? 130 : 85);
      final borderColor = cell.displayColor;

      return Polygon(
        points: cell.polygonPoints,
        color: fillColor,
        borderColor: borderColor,
        borderStrokeWidth: isOwnCell ? 3.0 : 1.5,
      );
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          // 1. Interactive Flutter Map with OpenStreetMap tiles
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: game.currentLocation,
              initialZoom: 15.5,
              minZoom: 3,
              maxZoom: 19,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  final c = camera.center;
                  // Dynamically refresh viewport cells when user pans
                  game.updateViewportBbox(
                    c.longitude - 0.03,
                    c.latitude - 0.03,
                    c.longitude + 0.03,
                    c.latitude + 0.03,
                  );
                }
              },
            ),
            children: [
              // OpenStreetMap Tile Layer
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.territoryrun.mobile',
              ),

              // Hexagon Territory Polygons
              PolygonLayer(polygons: polygons),

              // Active Route Polyline
              if (game.sessionPath.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: game.sessionPath,
                      color: AppTheme.neonCyan,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),

              // Current Location Marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: game.currentLocation,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.neonCyan.withAlpha(200),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.neonCyan.withAlpha(160),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: Colors.black,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Top Tactical Status Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Player Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withAlpha(230),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.surfaceLight, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: player != null
                                ? Color(int.parse("0xFF${player.colorHex.replaceAll('#', '')}"))
                                : AppTheme.neonCyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          player?.username ?? "Conqueror",
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // Map Refresh & Recenter Buttons
                  Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceColor.withAlpha(230),
                        ),
                        icon: const Icon(Icons.my_location, color: AppTheme.neonCyan, size: 20),
                        onPressed: () {
                          _mapController.move(game.currentLocation, 16.0);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceColor.withAlpha(230),
                        ),
                        icon: game.isLoadingCells
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.neonCyan),
                              )
                            : const Icon(Icons.refresh, color: Colors.white, size: 20),
                        onPressed: _loadInitialData,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom HUD / Tracking Session Panel
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withAlpha(240),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: game.isTracking ? AppTheme.neonCyan : AppTheme.surfaceLight,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(150),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!game.isTracking) ...[
                    // Pre-session Activity Type Selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ActivityChip(
                          icon: Icons.directions_walk,
                          label: "WALK (1.0x)",
                          selected: game.activityType == "walk",
                          onTap: () => setState(() => _selectedActivity = "walk"),
                        ),
                        _ActivityChip(
                          icon: Icons.directions_run,
                          label: "JOG (1.3x)",
                          selected: _selectedActivity == "jog",
                          onTap: () => setState(() => _selectedActivity = "jog"),
                        ),
                        _ActivityChip(
                          icon: Icons.flash_on,
                          label: "RUN (1.6x)",
                          selected: _selectedActivity == "run",
                          onTap: () => setState(() => _selectedActivity = "run"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Start Tracking Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        label: const Text(
                          "START CONQUEST SESSION",
                          style: TextStyle(letterSpacing: 1.0, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final success = await game.startTrackingSession(
                            activityType: _selectedActivity,
                            simulate: true,
                          );
                          if (!mounted) return;
                          if (!success) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("Failed to start tracking session"),
                                backgroundColor: AppTheme.neonPink,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ] else ...[
                    // Active Session Stats HUD
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatWidget(
                          label: "TIME",
                          value: _formatDuration(game.elapsedSeconds),
                          color: Colors.white,
                        ),
                        _StatWidget(
                          label: "DISTANCE",
                          value: "${(game.sessionDistanceM).toStringAsFixed(0)} m",
                          color: AppTheme.neonCyan,
                        ),
                        _StatWidget(
                          label: "CAPTURED",
                          value: "${game.sessionCapturedCount}",
                          color: AppTheme.tacticalGreen,
                        ),
                        _StatWidget(
                          label: "RATE",
                          value: "${_selectedActivity.toUpperCase()} (${_getActivityMultiplier(_selectedActivity)})",
                          color: AppTheme.goldAmber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Stop Tracking Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonPink,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 28),
                        label: const Text(
                          "FINISH & CLAIM SESSION",
                          style: TextStyle(letterSpacing: 1.0, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final res = await game.stopTrackingSession();
                          if (!mounted) return;
                          if (res != null) {
                            auth.refreshProfile();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Session finished! Distance: ${res['distance_meters']}m | Cells Captured: ${res['cells_captured_count']}",
                                ),
                                backgroundColor: AppTheme.tacticalGreen,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _selectedActivity = "walk";

  String _getActivityMultiplier(String act) {
    if (act == "run") return "1.6x";
    if (act == "jog") return "1.3x";
    return "1.0x";
  }
}

class _ActivityChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.neonCyan.withAlpha(40) : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.neonCyan : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: selected ? AppTheme.neonCyan : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppTheme.neonCyan : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatWidget extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatWidget({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8B949E),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}
