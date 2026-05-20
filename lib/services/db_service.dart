import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';

class DbService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get uid => _auth.currentUser?.uid;

  CollectionReference get _messagesRef {
    if (uid == null) {
      throw Exception('User not logged in');
    }
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('chats')
        .doc('crixy_chat')
        .collection('messages');
  }

  Future<void> saveMessage(ChatMessage message) async {
    if (uid == null) return;
    await _messagesRef.doc(message.id).set({
      'text': message.message,
      'isUser': message.isUser,
      'timestamp': message.timestamp.toIso8601String(),
    });
  }

  Future<List<ChatMessage>> loadMessages() async {
    if (uid == null) return [];

    try {
      final snapshot = await _messagesRef.orderBy('timestamp').get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return ChatMessage(
          id: doc.id,
          message: data['text']?.toString() ?? '',
          isUser: data['isUser'] == true,
          timestamp: DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
              DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearChat() async {
    if (uid == null) return;
    final snapshot = await _messagesRef.get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
