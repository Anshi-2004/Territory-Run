import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'providers/auth_provider.dart';
import 'providers/game_provider.dart';
import 'theme/app_theme.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final apiService = ApiService();
  await apiService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(apiService)..tryAutoLogin()),
        ChangeNotifierProvider(create: (_) => GameProvider(apiService)),
      ],
      child: const TerritoryRunApp(),
    ),
  );
}

class TerritoryRunApp extends StatelessWidget {
  const TerritoryRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Territory Run',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (auth.isLoading && auth.player == null) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppTheme.neonCyan),
              ),
            );
          }
          if (auth.isAuthenticated) {
            return const MainNavigationScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}
