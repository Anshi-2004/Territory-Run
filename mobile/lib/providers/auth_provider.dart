import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/player_model.dart';

class AuthProvider with ChangeNotifier {
  final ApiService apiService;
  PlayerModel? _player;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider(this.apiService);

  PlayerModel? get player => _player;
  bool get isAuthenticated => apiService.token != null && _player != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> tryAutoLogin() async {
    _isLoading = true;
    notifyListeners();
    try {
      await apiService.init();
      if (apiService.token != null) {
        _player = await apiService.getMe();
      }
    } catch (_) {
      await apiService.clearToken();
      _player = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String username,
    required String password,
    String colorHex = "#00F0FF",
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await apiService.register(
        email: email,
        username: username,
        password: password,
        colorHex: colorHex,
      );
      _player = await apiService.getMe();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await apiService.login(email: email, password: password);
      _player = await apiService.getMe();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll("Exception: ", "");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile({String? username, String? colorHex}) async {
    try {
      final updated = await apiService.updateMe(username: username, colorHex: colorHex);
      _player = updated;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshProfile() async {
    try {
      final updated = await apiService.getMe();
      _player = updated;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    await apiService.clearToken();
    _player = null;
    notifyListeners();
  }
}
