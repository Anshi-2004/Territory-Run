import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config/api_constants.dart';
import '../models/territory_cell.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../theme/app_theme.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();
  bool _autoFollowRunner = true;
  String _selectedActivity = "walk";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMapAndLocation();
    });
  }

  Future<void> _initializeMapAndLocation() async {
    final game = Provider.of<GameProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // Acquire user's real local area via GPS or IP Geolocation
    final loc = await game.initUserLocation();
    final center = loc ?? game.currentLocation;

    if (mounted) {
      _mapController.move(center, 16.0);
    }

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
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  void _onMapTapped(LatLng tapPoint, List<TerritoryCellModel> cells) {
    TerritoryCellModel? closestCell;
    double minDistance = 220.0;

    for (final cell in cells) {
      if (cell.polygonPoints.isNotEmpty) {
        double sumLat = 0;
        double sumLng = 0;
        for (final p in cell.polygonPoints) {
          sumLat += p.latitude;
          sumLng += p.longitude;
        }
        final center = LatLng(sumLat / cell.polygonPoints.length, sumLng / cell.polygonPoints.length);
        final dist = const Distance().as(LengthUnit.Meter, tapPoint, center);
        if (dist < minDistance) {
          minDistance = dist;
          closestCell = cell;
        }
      }
    }

    final game = Provider.of<GameProvider>(context, listen: false);
    game.inspectCell(closestCell);
  }

  void _openSearchDialog() {
    final game = Provider.of<GameProvider>(context, listen: false);
    final searchController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Jump to Local Area / City",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: searchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search neighborhood, street, or city...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.neonCyan),
                      filled: true,
                      fillColor: AppTheme.surfaceLight,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded, color: AppTheme.neonCyan),
                        onPressed: () async {
                          if (searchController.text.trim().isEmpty) return;
                          setSheetState(() => isSearching = true);
                          final found = await game.locationService.searchPlaces(searchController.text);
                          setSheetState(() {
                            results = found;
                            isSearching = false;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (val) async {
                      if (val.trim().isEmpty) return;
                      setSheetState(() => isSearching = true);
                      final found = await game.locationService.searchPlaces(val);
                      setSheetState(() {
                        results = found;
                        isSearching = false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (isSearching)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: AppTheme.neonCyan),
                      ),
                    )
                  else if (results.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                        itemBuilder: (context, i) {
                          final item = results[i];
                          return ListTile(
                            leading: const Icon(Icons.location_on, color: AppTheme.neonCyan),
                            title: Text(
                              item['display_name'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                            onTap: () {
                              final lat = item['lat'] as double;
                              final lng = item['lng'] as double;
                              final targetLoc = LatLng(lat, lng);
                              Navigator.pop(ctx);
                              game.jumpToLocation(targetLoc);
                              _mapController.move(targetLoc, 16.0);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: ApiConstants.baseUrl);
    String testStatus = "";
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppTheme.surfaceLight, width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.wifi_tethering, color: AppTheme.neonCyan),
                  SizedBox(width: 10),
                  Text("Server Connection", style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "For physical devices on local Wi-Fi, enter your computer's IP (e.g. http://192.168.1.X:8000) or an Ngrok tunnel URL.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Backend Base URL",
                      labelStyle: const TextStyle(color: AppTheme.neonCyan),
                      hintText: "http://192.168.1.50:8000",
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: AppTheme.surfaceLight,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (testStatus.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      testStatus,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: testStatus.contains("Connected") ? AppTheme.tacticalGreen : AppTheme.neonPink,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setModalState(() {
                            isTesting = true;
                            testStatus = "Testing...";
                          });
                          final testUrl = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
                          try {
                            final res = await ApiConstants.testEndpoint(testUrl);
                            setModalState(() {
                              isTesting = false;
                              testStatus = res ? "Connected! Server online." : "Failed to reach server";
                            });
                          } catch (_) {
                            setModalState(() {
                              isTesting = false;
                              testStatus = "Error connecting";
                            });
                          }
                        },
                  child: const Text("TEST PING", style: TextStyle(color: AppTheme.neonCyan)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonCyan),
                  onPressed: () async {
                    await ApiConstants.setCustomBaseUrl(controller.text);
                    if (context.mounted) {
                      Navigator.pop(dialogCtx);
                      _initializeMapAndLocation();
                    }
                  },
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final game = context.watch<GameProvider>();
    final player = auth.player;

    // Auto-follow runner if active tracking and follow mode is enabled
    if (_autoFollowRunner && (game.isTracking || game.locationService.hasInitialGpsLock)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(game.currentLocation, _mapController.camera.zoom);
        } catch (_) {}
      });
    }

    // Check if a circle was completed and conquered!
    if (game.lastCircleCelebration != null) {
      final cel = game.lastCircleCelebration!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTheme.neonCyan, width: 2),
            ),
            title: const Row(
              children: [
                Icon(Icons.workspace_premium_rounded, color: AppTheme.goldAmber, size: 28),
                SizedBox(width: 8),
                Text("CIRCLE CONQUERED!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              "🎉 Magnificent run! You completed the loop and conquered ${cel['enclosed_cells_count']} hexagons across ${cel['enclosed_area_m2']} m²!\n\nAll enclosed territory has been claimed with your banner.",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonCyan),
                onPressed: () {
                  Navigator.pop(ctx);
                  game.clearCircleCelebration();
                },
                child: const Text("GLORIOUS!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      });
    }

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
      final isInspected = game.inspectedCell?.h3Index == cell.h3Index;
      final fillColor = isInspected
          ? AppTheme.goldAmber.withAlpha(160)
          : cell.displayColor.withAlpha(isOwnCell ? 140 : 85);
      final borderColor = isInspected ? Colors.white : cell.displayColor;

      return Polygon(
        points: cell.polygonPoints,
        color: fillColor,
        borderColor: borderColor,
        borderStrokeWidth: isInspected ? 3.5 : (isOwnCell ? 2.5 : 1.5),
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
              initialZoom: 16.0,
              minZoom: 3,
              maxZoom: 19,
              onTap: (tapPosition, point) => _onMapTapped(point, game.cells),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  if (_autoFollowRunner) {
                    setState(() => _autoFollowRunner = false);
                  }
                  final c = camera.center;
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
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.territoryrun.mobile',
              ),

              // Hexagon Territory Polygons
              PolygonLayer(polygons: polygons),

              // Active Route Boundary Polyline
              if (game.sessionPath.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: game.sessionPath,
                      color: AppTheme.neonCyan,
                      strokeWidth: 5.0,
                    ),
                    // Dashed closure guide when runner is approaching start point
                    if (game.isNearLoopStart && game.loopStartPoint != null)
                      Polyline(
                        points: [game.sessionPath.last, game.loopStartPoint!],
                        color: AppTheme.goldAmber,
                        strokeWidth: 3.5,
                        strokeCap: StrokeCap.round,
                      ),
                  ],
                ),

              // Markers: Loop Start Flag + Current Location
              MarkerLayer(
                markers: [
                  // Circle Loop Start Flag
                  if (game.isTracking && game.loopStartPoint != null)
                    Marker(
                      point: game.loopStartPoint!,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.goldAmber.withAlpha(220),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(color: AppTheme.goldAmber.withAlpha(180), blurRadius: 12),
                          ],
                        ),
                        child: const Icon(Icons.flag_rounded, color: Colors.black, size: 22),
                      ),
                    ),

                  // Current Location Marker with Heading Indicator
                  Marker(
                    point: game.currentLocation,
                    width: 52,
                    height: 52,
                    child: Transform.rotate(
                      angle: (game.currentHeading * (3.141592653589793 / 180.0)),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.neonCyan.withAlpha(210),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withAlpha(160),
                              blurRadius: 15,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Top Tactical Status Header & Area Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Player Callsign Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor.withAlpha(235),
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

                  // Real-Time Live Status Badge
                  _LiveWsStatusBadge(state: game.wsConnectionState),

                  // Actions: Search City, Locate Me, Server Settings, Follow Toggle
                  Row(
                    children: [
                      // Search Area / City Button
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceColor.withAlpha(230),
                        ),
                        icon: const Icon(Icons.search, color: AppTheme.neonCyan, size: 20),
                        tooltip: "Search City / Area",
                        onPressed: _openSearchDialog,
                      ),
                      const SizedBox(width: 6),
                      // Locate Me Button
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceColor.withAlpha(230),
                        ),
                        icon: const Icon(Icons.my_location, color: AppTheme.tacticalGreen, size: 20),
                        tooltip: "Locate My Area",
                        onPressed: () async {
                          final loc = await game.initUserLocation();
                          if (loc != null && mounted) {
                            setState(() => _autoFollowRunner = true);
                            _mapController.move(loc, 16.5);
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      // Auto-Follow Toggle
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: _autoFollowRunner
                              ? AppTheme.neonCyan.withAlpha(50)
                              : AppTheme.surfaceColor.withAlpha(230),
                          side: BorderSide(
                            color: _autoFollowRunner ? AppTheme.neonCyan : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        icon: Icon(
                          _autoFollowRunner ? Icons.gps_fixed : Icons.gps_not_fixed,
                          color: _autoFollowRunner ? AppTheme.neonCyan : Colors.white70,
                          size: 19,
                        ),
                        tooltip: _autoFollowRunner ? "Auto-Follow Locked" : "Center & Lock Follow",
                        onPressed: () {
                          setState(() => _autoFollowRunner = !_autoFollowRunner);
                          _mapController.move(game.currentLocation, 16.5);
                        },
                      ),
                      const SizedBox(width: 6),
                      // Server Settings
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.surfaceColor.withAlpha(230),
                        ),
                        icon: const Icon(Icons.wifi_tethering, color: Colors.white70, size: 19),
                        tooltip: "Server Config",
                        onPressed: _showServerConfigDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 3. Hexagon Inspection Bottom Card
          if (game.inspectedCell != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: game.isTracking ? 240 : 200,
              child: _HexagonInspectionCard(
                cell: game.inspectedCell!,
                currentUserId: player?.id,
                onClose: () => game.inspectCell(null),
              ),
            ),

          // 4. Bottom HUD / Circle Conquest Tracking Panel
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor.withAlpha(245),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: game.isNearLoopStart
                      ? AppTheme.goldAmber
                      : (game.isTracking ? AppTheme.neonCyan : AppTheme.surfaceLight),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(160),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!game.isTracking) ...[
                    // Mode Selector (Live GPS vs Demo Simulator)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ModeChip(
                          icon: Icons.satellite_alt_rounded,
                          label: "LIVE GPS",
                          selected: game.trackingMode == TrackingMode.realGps,
                          onTap: () async {
                            game.setTrackingMode(TrackingMode.realGps);
                            final loc = await game.initUserLocation();
                            if (loc != null && mounted) {
                              _mapController.move(loc, 16.5);
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        _ModeChip(
                          icon: Icons.videogame_asset_outlined,
                          label: "SIMULATE CIRCLE",
                          selected: game.trackingMode == TrackingMode.simulation,
                          onTap: () {
                            game.setTrackingMode(TrackingMode.simulation);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Pre-session Activity Type Selector
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ActivityChip(
                          icon: Icons.directions_walk,
                          label: "WALK (1.0x)",
                          selected: _selectedActivity == "walk",
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
                        label: Text(
                          game.trackingMode == TrackingMode.realGps
                              ? "START CIRCLE CONQUEST"
                              : "START SIMULATION CIRCLE",
                          style: const TextStyle(letterSpacing: 0.8, fontWeight: FontWeight.w900),
                        ),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _autoFollowRunner = true);
                          final success = await game.startTrackingSession(
                            activityType: _selectedActivity,
                            mode: game.trackingMode,
                          );
                          if (!mounted) return;
                          if (!success) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("Failed to start session. Check GPS permission."),
                                backgroundColor: AppTheme.neonPink,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ] else ...[
                    // Loop Status Guidance Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: game.isNearLoopStart
                            ? AppTheme.goldAmber.withAlpha(40)
                            : AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: game.isNearLoopStart ? AppTheme.goldAmber : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            game.isNearLoopStart
                                ? Icons.check_circle_outline_rounded
                                : Icons.sync_rounded,
                            size: 16,
                            color: game.isNearLoopStart ? AppTheme.goldAmber : AppTheme.neonCyan,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            game.isNearLoopStart
                                ? "READY TO CLOSE CIRCLE! (${game.distanceToLoopStart.toStringAsFixed(0)}m to start flag)"
                                : (game.canCloseLoop
                                    ? "Circle eligible! Head back to start flag (${game.distanceToLoopStart.toStringAsFixed(0)}m)"
                                    : "Drawing perimeter... (Run at least 80m to complete loop)"),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: game.isNearLoopStart ? AppTheme.goldAmber : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Active Real-Time Session Stats HUD
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
                          value: game.sessionDistanceM >= 1000
                              ? "${(game.sessionDistanceM / 1000.0).toStringAsFixed(2)} km"
                              : "${game.sessionDistanceM.toStringAsFixed(0)} m",
                          color: AppTheme.neonCyan,
                        ),
                        _StatWidget(
                          label: "SPEED",
                          value: "${game.currentSpeedKmh.toStringAsFixed(1)} km/h",
                          color: AppTheme.goldAmber,
                        ),
                        _StatWidget(
                          label: "PACE",
                          value: game.currentPaceString,
                          color: AppTheme.tacticalGreen,
                        ),
                        _StatWidget(
                          label: "HEXAGONS",
                          value: "${game.sessionCapturedCount}",
                          color: AppTheme.neonPink,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Action Buttons: Complete Circle vs Finish Run
                    Row(
                      children: [
                        // Complete Circle Button (Prominent when closing)
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: game.isNearLoopStart ? AppTheme.goldAmber : AppTheme.neonCyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.circle_outlined, size: 22),
                            label: Text(
                              game.isNearLoopStart ? "CLOSE CIRCLE NOW!" : "COMPLETE CIRCLE",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                            ),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              if (!game.canCloseLoop) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text("Run a complete perimeter of at least 80m before closing circle!"),
                                    backgroundColor: AppTheme.goldAmber,
                                  ),
                                );
                                return;
                              }
                              await game.closeCurrentLoop();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Finish Session Button
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonPink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.stop_rounded, size: 22),
                            label: const Text(
                              "FINISH",
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
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
                                      "Session Finished! Distance: ${res['distance_meters']}m | Hexagons Captured: ${res['cells_captured_count']}",
                                    ),
                                    backgroundColor: AppTheme.tacticalGreen,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
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
}

class _LiveWsStatusBadge extends StatelessWidget {
  final WsConnectionState state;

  const _LiveWsStatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    Color dotColor = Colors.grey;
    String label = "OFFLINE";

    switch (state) {
      case WsConnectionState.connected:
        dotColor = AppTheme.tacticalGreen;
        label = "LIVE STREAM";
        break;
      case WsConnectionState.connecting:
        dotColor = AppTheme.goldAmber;
        label = "SYNCING";
        break;
      case WsConnectionState.disconnected:
        dotColor = Colors.grey;
        label = "STANDBY";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withAlpha(220),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dotColor.withAlpha(120), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withAlpha(150),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: dotColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.neonCyan.withAlpha(50) : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.neonCyan : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? AppTheme.neonCyan : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            Icon(icon, size: 15, color: selected ? AppTheme.neonCyan : Colors.white70),
            const SizedBox(width: 5),
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
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8B949E),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _HexagonInspectionCard extends StatelessWidget {
  final TerritoryCellModel cell;
  final String? currentUserId;
  final VoidCallback onClose;

  const _HexagonInspectionCard({
    required this.cell,
    required this.currentUserId,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = currentUserId != null && cell.ownerId == currentUserId;
    final statusColor = isMine ? AppTheme.neonCyan : (cell.ownerId != null ? AppTheme.neonPink : AppTheme.goldAmber);
    final statusText = isMine
        ? "DEFENDING ZONE"
        : (cell.ownerId != null ? "RIVAL TERRITORY" : "UNCLAIMED SECTOR");

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withAlpha(245),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(160),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ],
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "H3 Hex: ${cell.h3Index}",
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                "Defense Score: ${cell.ownerScore.toStringAsFixed(1)}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Text(
                isMine ? "Defend with loops" : "Enclose in a circle to conquer",
                style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
