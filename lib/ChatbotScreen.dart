import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'config/api_keys.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // Store messages for display
  List<ChatMessage> _messages = [];

  // Store conversation history for API
  List<Map<String, dynamic>> _conversationHistory = [];

  // Multiple API Keys
  final List<String> _apiKeys = ApiKeys.geminiKeys;

  int _currentKeyIndex = 0;

  @override
  void initState() {
    super.initState();
    // Add welcome message
    _messages.add(ChatMessage(
      text: "Hello! I'm your medical assistant. How can I help you today?",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _getNextApiKey() {
    String key = _apiKeys[_currentKeyIndex];
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    return key;
  }

  void _scrollToBottom() {
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> askGemini() async {
    if (_controller.text.trim().isEmpty) return;

    String userMessage = _controller.text;
    _controller.clear();

    // Add user message to UI
    setState(() {
      _messages.add(ChatMessage(
        text: userMessage,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });

    _scrollToBottom();

    // Add user message to API history
    _conversationHistory.add({
      "role": "user",
      "parts": [{"text": userMessage}]
    });

    int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        String apiKey = _getNextApiKey();

        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            "x-goog-api-key": apiKey
          },
          body: jsonEncode({
            "contents": _conversationHistory,
            "systemInstruction": {
              "parts": [
                {
                  "text": "You are メディナビ, an experienced nurse practitioner having an in-depth consultation with a patient. Your goal is to understand their health situation completely before giving advice.\n\nConversation Style:\n- Think and respond like a real healthcare professional in a consultation\n- Ask relevant follow-up questions to understand their condition better (like: 'How long have you been experiencing this?', 'Have you noticed any other symptoms?', 'Are you taking any medications?')\n- Show genuine empathy and concern\n- Use natural, warm language - never robotic or list-based\n- Remember all details they share and reference them naturally\n\nMedical Approach:\n- Ask diagnostic questions when they mention symptoms (severity, duration, triggers, accompanying symptoms)\n- Inquire about medical history, allergies, current medications when relevant\n- Assess urgency - if symptoms sound serious, recommend seeing a doctor immediately\n- For non-urgent issues, provide caring advice and home remedies\n- Ask about their location when you need to recommend hospitals or clinics\n\nHospital Recommendations:\n- When their condition requires medical attention, ask: 'Where are you located? I can help you find nearby hospitals or clinics.'\n- Once you know their location, recommend specific hospitals, urgent care centers, or specialist clinics appropriate for their condition\n- Suggest what type of specialist they should see (e.g., 'You might want to see a cardiologist for this')\n- Mention emergency services (call ambulance/emergency number) for serious symptoms\n\nImportant Guidelines:\n- Never use bullet points, asterisks, or formatted lists\n- Keep responses conversational and caring, like talking to a friend\n- Balance asking questions with providing support\n- Don't overwhelm with too many questions at once (2-3 questions max)\n- Always remind them gently that you're here to help guide them, but a doctor's examination is important for accurate diagnosis\n\nYour ultimate goal: Help them understand their health concern, decide if they need to see a doctor, and guide them to appropriate care."
                }
              ]
            },
            "generationConfig": {
              "temperature": 0.85,
              "topP": 0.9,
              "topK": 45,
              "maxOutputTokens": 2048
            }
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String aiResponse = data['candidates'][0]['content']['parts'][0]['text'];

          _conversationHistory.add({
            "role": "model",
            "parts": [{"text": aiResponse}]
          });

          setState(() {
            _messages.add(ChatMessage(
              text: aiResponse,
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isLoading = false;
          });

          _scrollToBottom();
          return;

        } else if (response.statusCode == 429 || response.statusCode == 503) {
          retryCount++;
          if (retryCount < maxRetries) {
            int waitTime = (2 * retryCount);
            await Future.delayed(Duration(seconds: waitTime));
          } else {
            setState(() {
              _messages.add(ChatMessage(
                text: "I'm currently overloaded. Please try again in a moment.",
                isUser: false,
                timestamp: DateTime.now(),
              ));
              _isLoading = false;
            });
            _scrollToBottom();
            return;
          }
        } else {
          setState(() {
            _messages.add(ChatMessage(
              text: "Sorry, I encountered an error. Please try again.",
              isUser: false,
              timestamp: DateTime.now(),
            ));
            _isLoading = false;
          });
          _scrollToBottom();
          return;
        }
      } catch (e) {
        setState(() {
          _messages.add(ChatMessage(
            text: "Network error. Please check your connection.",
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isLoading = false;
        });
        _scrollToBottom();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        title: Text('AI Medical Assistant'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _conversationHistory.clear();
                _messages.add(ChatMessage(
                  text: "Chat cleared. How can I help you?",
                  isUser: false,
                  timestamp: DateTime.now(),
                ));
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat messages area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ChatBubble(message: _messages[index]);
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  SizedBox(width: 16),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Typing...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                      onSubmitted: (_) => askGemini(),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: IconButton(
                      onPressed: _isLoading ? null : askGemini,
                      icon: Icon(Icons.send, color: Colors.white),
                      padding: EdgeInsets.all(0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Chat Message Model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

// Chat Bubble Widget
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.deepPurple,
              radius: 16,
              child: Icon(Icons.medical_services, size: 18, color: Colors.white),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? Colors.deepPurple
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (message.isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.blue,
              radius: 16,
              child: Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}