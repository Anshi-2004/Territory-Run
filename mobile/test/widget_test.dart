import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/main.dart';
import 'package:mobile/services/api_service.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/game_provider.dart';

void main() {
  testWidgets('App initializes and renders auth screen by default', (WidgetTester tester) async {
    final apiService = ApiService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(apiService)),
          ChangeNotifierProvider(create: (_) => GameProvider(apiService)),
        ],
        child: const TerritoryRunApp(),
      ),
    );

    // Verify Territory Run title is rendered
    expect(find.text('TERRITORY RUN'), findsOneWidget);
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
