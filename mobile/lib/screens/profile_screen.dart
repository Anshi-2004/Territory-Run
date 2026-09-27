import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _usernameController = TextEditingController();

  void _showEditUsernameDialog(BuildContext context, String currentUsername) {
    _usernameController.text = currentUsername;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Edit Callsign", style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: _usernameController,
          decoration: const InputDecoration(labelText: "New Username"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = _usernameController.text.trim();
              if (newName.length >= 3) {
                Provider.of<AuthProvider>(context, listen: false).updateProfile(username: newName);
                Navigator.pop(ctx);
              }
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final player = auth.player;

    if (player == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.neonCyan)),
      );
    }

    final playerColor = Color(int.parse("0xFF${player.colorHex.replaceAll('#', '')}"));

    return Scaffold(
      appBar: AppBar(
        title: const Text("COMMANDER PROFILE"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar & Identity Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.surfaceLight, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: playerColor.withAlpha(40),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Hexagon Crest with Player Color
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: playerColor.withAlpha(50),
                      border: Border.all(color: playerColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: playerColor.withAlpha(120),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Icon(Icons.shield_rounded, size: 40, color: playerColor),
                  ),
                  const SizedBox(height: 16),

                  // Username Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        player.username,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.neonCyan),
                        onPressed: () => _showEditUsernameDialog(context, player.username),
                      ),
                    ],
                  ),
                  Text(
                    player.email,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Statistics Grid
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: "TERRITORY",
                    value: "${player.totalTerritoryAreaKm2.toStringAsFixed(3)} km²",
                    subtitle: "${player.totalTerritoryAreaM2.toStringAsFixed(0)} m² claimed",
                    icon: Icons.hexagon_outlined,
                    iconColor: AppTheme.neonCyan,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _StatCard(
                    title: "WAR COINS",
                    value: "${player.coins}",
                    subtitle: "Earned via conquest",
                    icon: Icons.monetization_on_outlined,
                    iconColor: AppTheme.goldAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Territory Color Customizer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "CONQUEST BANNER COLOR",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Color(0xFF8B949E),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: AppTheme.playerColorPalette.map((hex) {
                      final c = Color(int.parse("0xFF${hex.replaceAll('#', '')}"));
                      final isSelected = player.colorHex.toUpperCase() == hex.toUpperCase();
                      return GestureDetector(
                        onTap: () {
                          auth.updateProfile(colorHex: hex);
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: c.withAlpha(180),
                                      blurRadius: 14,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.black, size: 22)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Logout Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.neonPink,
                side: const BorderSide(color: AppTheme.neonPink, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text(
                "DISCONNECT / LOGOUT",
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              onPressed: () {
                auth.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8B949E),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
