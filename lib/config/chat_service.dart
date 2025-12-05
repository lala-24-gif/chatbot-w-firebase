import 'package:cloud_firestore/cloud_firestore.dart';

// ChatMessage model class
class ChatMessage {
  final String message;
  final String sender; // 'user' or 'ai'
  final DateTime timestamp;

  ChatMessage({
    required this.message,
    required this.sender,
    required this.timestamp,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      message: data['message'] ?? '',
      sender: data['sender'] ?? 'user',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new chat
  Future<String> createNewChat(String userId) async {
    try {
      final chatRef = await _firestore.collection('chats').add({
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
      return chatRef.id;
    } catch (e) {
      print('Error creating chat: $e');
      rethrow;
    }
  }

  // Save a message to a chat
  Future<void> saveMessage({
    required String chatId,
    required String message,
    required String sender,
  }) async {
    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'message': message,
        'sender': sender,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving message: $e');
      rethrow;
    }
  }

  // Update last message in chat document
  Future<void> updateLastMessage(String chatId, String lastMessage) async {
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': lastMessage,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating last message: $e');
      rethrow;
    }
  }

  // Get chat history as a stream
  Stream<List<ChatMessage>> getChatHistory(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ChatMessage.fromFirestore(doc);
      }).toList();
    });
  }

  // Delete a chat and all its messages
  Future<void> deleteChat(String chatId) async {
    try {
      // Delete all messages in the chat
      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      for (var doc in messagesSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete the chat document
      await _firestore.collection('chats').doc(chatId).delete();
    } catch (e) {
      print('Error deleting chat: $e');
      rethrow;
    }
  }

  // Get all chats for a user
  Stream<QuerySnapshot> getUserChats(String userId) {
    return _firestore
        .collection('chats')
        .where('userId', isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  // Delete all chats for a user
  Future<void> deleteAllUserChats(String userId) async {
    try {
      final chatsSnapshot = await _firestore
          .collection('chats')
          .where('userId', isEqualTo: userId)
          .get();

      for (var chatDoc in chatsSnapshot.docs) {
        await deleteChat(chatDoc.id);
      }
    } catch (e) {
      print('Error deleting all chats: $e');
      rethrow;
    }
  }

  // Clear messages in a chat (keep the chat, delete messages)
  Future<void> clearChatMessages(String chatId) async {
    try {
      final messagesSnapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      for (var doc in messagesSnapshot.docs) {
        await doc.reference.delete();
      }

      // Update chat document
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error clearing messages: $e');
      rethrow;
    }
  }

  // Check if a chat exists
  Future<bool> chatExists(String chatId) async {
    try {
      final doc = await _firestore.collection('chats').doc(chatId).get();
      return doc.exists;
    } catch (e) {
      print('Error checking chat existence: $e');
      return false;
    }
  }

  // Get chat details
  Future<DocumentSnapshot?> getChatDetails(String chatId) async {
    try {
      return await _firestore.collection('chats').doc(chatId).get();
    } catch (e) {
      print('Error getting chat details: $e');
      return null;
    }
  }

  // Get message count for a chat
  Future<int> getMessageCount(String chatId) async {
    try {
      final snapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();
      return snapshot.docs.length;
    } catch (e) {
      print('Error getting message count: $e');
      return 0;
    }
  }
}