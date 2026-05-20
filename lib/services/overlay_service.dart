import 'package:flutter/services.dart';

class OverlayService {
  static const MethodChannel _channel = MethodChannel('com.example.wallet_app/overlay');

  static Future<bool> checkPermission() async {
    try {
      final bool result = await _channel.invokeMethod('checkPermission');
      return result;
    } catch (e) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (e) {
      // Handle error
    }
  }

  static Future<void> startOverlay({
    required double expense,
    required double limit,
    required double left,
    required double income,
  }) async {
    try {
      await _channel.invokeMethod('startOverlay', <String, String>{
        'expense': '₹${expense.toStringAsFixed(0)}',
        'limit': '₹${limit.toStringAsFixed(0)}',
        'left': '₹${left.toStringAsFixed(0)}',
        'income': '₹${income.toStringAsFixed(0)}',
      });
    } catch (e) {
      // Handle error
    }
  }

  static Future<void> updateOverlay({
    required double expense,
    required double limit,
    required double left,
    required double income,
  }) async {
    try {
      await _channel.invokeMethod('updateOverlay', <String, String>{
        'expense': '₹${expense.toStringAsFixed(0)}',
        'limit': '₹${limit.toStringAsFixed(0)}',
        'left': '₹${left.toStringAsFixed(0)}',
        'income': '₹${income.toStringAsFixed(0)}',
      });
    } catch (e) {
      // Handle error
    }
  }

  static Future<void> stopOverlay() async {
    try {
      await _channel.invokeMethod('stopOverlay');
    } catch (e) {
      // Handle error
    }
  }

  static void initializeListener({
    required Function onOverlayClosed,
    required Function(String name, double amount, bool isIncome, String category) onOverlayAddTx,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOverlayClosed') {
        onOverlayClosed();
      } else if (call.method == 'onOverlayAddTx') {
        final args = call.arguments as Map;
        onOverlayAddTx(
          args['name'] as String,
          (args['amount'] as num).toDouble(),
          args['isIncome'] as bool,
          (args['category'] as String?) ?? 'Others',
        );
      }
    });
  }

  static Future<bool> isOverlayActive() async {
    try {
      final bool result = await _channel.invokeMethod('isOverlayActive');
      return result;
    } catch (e) {
      return false;
    }
  }
}
