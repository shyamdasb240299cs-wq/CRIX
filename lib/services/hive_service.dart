import 'package:hive/hive.dart';
import '../models/chat_message.dart';

class HiveService {
  static const String _boxName = 'crixy_chat_box';

  Future<void> saveMessage(ChatMessage message) async {
    final box = await Hive.openBox<ChatMessage>(_boxName);
    await box.put(message.id, message);
  }

  Future<List<ChatMessage>> loadMessages() async {
    final box = await Hive.openBox<ChatMessage>(_boxName);
    final messages = box.values.toList();
    // Sort by timestamp
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<void> clearChat() async {
    final box = await Hive.openBox<ChatMessage>(_boxName);
    await box.clear();
  }
}
