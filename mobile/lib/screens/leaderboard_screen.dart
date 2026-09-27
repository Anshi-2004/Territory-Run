import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../theme/app_theme.dart';
import '../models/leaderboard_item.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final List<String> scopes = ["local", "city", "country", "global"];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GameProvider>(context, listen: false).loadLeaderboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GameProvider>();
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.player?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SECTOR LEADERBOARDS"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.neonCyan),
            onPressed: () => game.loadLeaderboard(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Scope Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight),
            ),
            child: Row(
              children: scopes.map((s) {
                final isSelected = game.currentScope == s;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => game.setLeaderboardScope(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.neonCyan : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        s.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.black : Colors.white70,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // Leaderboard List
          Expanded(
            child: game.isLoadingLeaderboard
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.neonCyan),
                  )
                : game.leaderboard.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.emoji_events_outlined, size: 64, color: Colors.white.withAlpha(60)),
                            const SizedBox(height: 12),
                            const Text(
                              "No territory claimed in this sector yet.",
                              style: TextStyle(color: Colors.white60, fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => game.loadLeaderboard(),
                        color: AppTheme.neonCyan,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: game.leaderboard.length,
                          itemBuilder: (context, index) {
                            final item = game.leaderboard[index];
                            final isMe = item.playerId == currentUserId;
                            return _LeaderboardRow(item: item, isMe: isMe);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final LeaderboardItem item;
  final bool isMe;

  const _LeaderboardRow({
    required this.item,
    required this.isMe,
  });

  Color _rankColor() {
    if (item.rank == 1) return AppTheme.goldAmber;
    if (item.rank == 2) return const Color(0xFFC0C0C0);
    if (item.rank == 3) return const Color(0xFFCD7F32);
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.surfaceLight : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? AppTheme.neonCyan : AppTheme.surfaceLight,
          width: isMe ? 2.0 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Rank Badge
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.rank <= 3 ? _rankColor().withAlpha(40) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              "#${item.rank}",
              style: TextStyle(
                color: _rankColor(),
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Player Color Pip
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: item.displayColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: item.displayColor.withAlpha(150),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.username,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isMe ? AppTheme.neonCyan : Colors.white,
                  ),
                ),
                if (isMe)
                  const Text(
                    "YOU",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.neonCyan,
                      letterSpacing: 0.5,
                    ),
                  ),
              ],
            ),
          ),

          // Area Stats
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${item.totalTerritoryAreaKm2.toStringAsFixed(3)} km²",
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${item.totalTerritoryAreaM2.toStringAsFixed(0)} m²",
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8B949E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
