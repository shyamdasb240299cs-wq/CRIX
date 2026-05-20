import 'package:shared_preferences/shared_preferences.dart';

class CrixyService {
  static const String _introKey = 'hasSeenCrixyIntro';
  static const String _lastInsightDateKey = 'crixyLastInsightDate';

  Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introKey) ?? false;
  }

  Future<void> setSeenIntro(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introKey, value);
  }

  Future<String> getLastInsightDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastInsightDateKey) ?? '';
  }

  Future<void> setLastInsightDate(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastInsightDateKey, value);
  }
}
