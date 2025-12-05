import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String message;
  final String sender;
  final DateTime timestamp;

  ChatMessage({
    required this.message,
    required this.sender,
    required this.timestamp,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      message: data['message'] ?? '',
      sender: data['sender'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create new chat
  Future<String> createNewChat(String userId) async {
    DocumentReference chatRef = await _firestore.collection('chats').add({
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
    return chatRef.id;
  }

  // Save message
  Future<void> saveMessage({
    required String chatId,
    required String message,
    required String sender,
  }) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'message': message,
      'sender': sender,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Get chat history
  Stream<List<ChatMessage>> getChatHistory(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc))
          .toList();
    });
  }

  // Update last message
  Future<void> updateLastMessage(String chatId, String message) async {
    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': message,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

  // Get user's chats
  Stream<QuerySnapshot> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('userId', isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  // Delete chat - THIS IS THE MISSING METHOD
  Future<void> deleteChat(String chatId) async {
    // First, delete all messages in the chat
    var messages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    for (var doc in messages.docs) {
      await doc.reference.delete();
    }

    // Then delete the chat document itself
    await _firestore.collection('chats').doc(chatId).delete();
  }
}