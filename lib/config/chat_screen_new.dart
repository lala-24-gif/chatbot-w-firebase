import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'chat_service.dart';
import 'api_keys.dart';

class ChatScreen extends StatefulWidget {
  final String userName;
  final String userId;
  final String? existingChatId;

  const ChatScreen({
    Key? key,
    required this.userName,
    required this.userId,
    this.existingChatId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  final FlutterTts _flutterTts = FlutterTts();

  String? _currentChatId;
  bool _isLoading = false;
  bool _showGreeting = true;
  bool _isSpeaking = false;
  String? _speakingMessageId;

  // API Keys
  final List<String> _apiKeys = ApiKeys.geminiKeys;
  int _currentKeyIndex = 0;
  List<Map<String, dynamic>> _conversationHistory = [];

  // Settings
  bool _isDetailedMode = true;
  bool _isEnglish = false;

  // Colors
  final Color primaryBlue = const Color(0xFF5DADE2);
  final Color lightBlue = const Color(0xFF42a5f5);
  final Color veryLightBlue = const Color(0xFFe3f2fd);
  final Color successGreen = const Color(0xFF4caf50);
  final Color warningRed = const Color(0xFFf44336);
  final Color infoYellow = const Color(0xFFffc107);

  @override
  void initState() {
    super.initState();
    _initializeTts();
    if (widget.existingChatId != null) {
      _currentChatId = widget.existingChatId;
      _showGreeting = false;
      _loadExistingConversation();
    } else {
      _createNewChat();
    }
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage(_isEnglish ? 'en-US' : 'ja-JP');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
        _speakingMessageId = null;
      });
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
        _speakingMessageId = null;
      });
    });
  }

  Future<void> _speak(String text, String messageId) async {
    if (_isSpeaking && _speakingMessageId == messageId) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
        _speakingMessageId = null;
      });
    } else {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = true;
        _speakingMessageId = messageId;
      });
      await _flutterTts.speak(text);
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
      _speakingMessageId = null;
    });
  }

  Future<void> _createNewChat() async {
    String chatId = await _chatService.createNewChat(widget.userId);
    setState(() {
      _currentChatId = chatId;
    });
  }

  Future<void> _loadExistingConversation() async {
    final messages = await FirebaseFirestore.instance
        .collection('chats')
        .doc(_currentChatId!)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();

    if (_conversationHistory.isEmpty) {
      for (var doc in messages.docs) {
        final data = doc.data();
        final sender = data['sender'] as String;
        final message = data['message'] as String;

        _conversationHistory.add({
          "role": sender == 'user' ? 'user' : 'model',
          "parts": [
            {"text": message}
          ]
        });
      }
    }
  }

  String _getNextApiKey() {
    String key = _apiKeys[_currentKeyIndex];
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    return key;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  String _getSystemInstruction() {
    if (_isEnglish) {
      String instruction = '''LANGUAGE: ENGLISH ONLY - NO JAPANESE ALLOWED
YOU MUST RESPOND ONLY IN ENGLISH.
DO NOT USE ANY JAPANESE CHARACTERS.
EVERY SINGLE WORD MUST BE IN ENGLISH.

You are a compassionate and knowledgeable medical assistant chatbot for a Japanese hospital finder app.

REMEMBER: RESPOND ONLY IN ENGLISH. NOT JAPANESE.''';

      if (_isDetailedMode) {
        return '''$instruction

IMPORTANT FORMATTING RULES:
- Use section headers with emojis for visual clarity
- Start each major section on a new line with a header
- Use bullet points (•) for lists
- Add line breaks between sections for readability

Your communication style:
- Start with empathy
- Use clear, structured formatting with visual sections
- Be thorough but organized
- Always maintain a supportive tone

Response Structure:
When users describe symptoms, provide responses in this EXACT format:

💙 **Understanding Your Concern**
[1-2 sentences acknowledging their concern]

✅ **Possible Common Causes**
- [Cause 1]
- [Cause 2]
- [Cause 3]

💡 **What You Can Try Now**
- [Self-care tip 1]
- [Self-care tip 2]
- [Self-care tip 3]

⚠️ **Seek Medical Help If You Have:**
- [Warning sign 1]
- [Warning sign 2]
- [Warning sign 3]

🏥 **Recommended Department**
[Department name in Japanese and English with brief explanation]

Important reminders:
- For emergencies: "🚨 Call 119 immediately"
- Always remind: "⚕️ This is not a diagnosis. Please consult a doctor."

Available departments (provide BOTH Japanese and English names):
- 内科 (Internal Medicine) - general illness, fever, fatigue
- 外科 (Surgery) - injuries, wounds
- 整形外科 (Orthopedics) - bone/joint issues
- 皮膚科 (Dermatology) - skin problems
- 眼科 (Ophthalmology) - eye issues
- 耳鼻咽喉科 (ENT) - ear, nose, throat
- 歯科 (Dentistry) - dental issues
- 小児科 (Pediatrics) - children
- 産婦人科 (OB/GYN) - women's health
- 精神科/心療内科 (Psychiatry) - mental health

CRITICAL: ALL EXPLANATIONS AND TEXT MUST BE IN ENGLISH. Only department names can include Japanese.''';
      } else {
        return '''$instruction

IMPORTANT: Use emojis and clear formatting even in quick mode.

Response Format (Quick Mode):
💙 [Brief empathetic acknowledgment IN ENGLISH]

💡 [Quick self-care tip IN ENGLISH]

🏥 [Recommended department with name in Japanese and English]

⚠️ [One critical warning sign if needed IN ENGLISH]

For emergencies: "🚨 Call 119 now"

Keep total response under 100 words but use emojis and line breaks for clarity.
ALL TEXT MUST BE IN ENGLISH.''';
      }
    } else {
      String instruction = '''言語: 日本語のみ - 英語使用禁止
必ず日本語のみで返答してください。
英語を一切使用しないでください。
すべての単語は日本語でなければなりません。

あなたは日本の病院検索アプリの思いやりのある知識豊富な医療アシスタントチャットボットです。

覚えておいてください: 日本語のみで返答してください。英語は使わないでください。''';

      if (_isDetailedMode) {
        return '''$instruction

重要な書式ルール:
- 視覚的な明瞭さのために絵文字付きのセクションヘッダーを使用する
- 各主要セクションをヘッダー付きの新しい行で開始する
- リストには箇条書き(•)を使用する
- 読みやすさのためにセクション間に改行を追加する

コミュニケーションスタイル:
- 共感から始める
- 視覚的なセクションで明確で構造化された書式を使用する
- 徹底的だが整理されている
- 常にサポート的なトーンを維持する

応答構造:
ユーザーが症状を説明する場合、この正確な形式で応答を提供してください:

💙 **あなたの懸念を理解しています**
[懸念を認める1-2文]

✅ **考えられる一般的な原因**
- [原因1]
- [原因2]
- [原因3]

💡 **今すぐ試せること**
- [セルフケアのヒント1]
- [セルフケアのヒント2]
- [セルフケアのヒント3]

⚠️ **次の場合は医療機関を受診してください:**
- [警告サイン1]
- [警告サイン2]
- [警告サイン3]

🏥 **推奨される診療科**
[日本語と英語での診療科名と簡単な説明]

重要なリマインダー:
- 緊急の場合: "🚨 すぐに119に電話してください"
- 常に注意: "⚕️ これは診断ではありません。医師に相談してください。"

利用可能な診療科:
- 内科 (Internal Medicine) - 一般的な病気、発熱、疲労
- 外科 (Surgery) - 怪我、傷
- 整形外科 (Orthopedics) - 骨/関節の問題
- 皮膚科 (Dermatology) - 皮膚の問題
- 眼科 (Ophthalmology) - 目の問題
- 耳鼻咽喉科 (ENT) - 耳、鼻、喉
- 歯科 (Dentistry) - 歯の問題
- 小児科 (Pediatrics) - 子供
- 産婦人科 (OB/GYN) - 女性の健康
- 精神科/心療内科 (Psychiatry) - メンタルヘルス''';
      } else {
        return '''$instruction

重要: クイックモードでも絵文字と明確な書式を使用してください。

応答形式(クイックモード):
💙 [簡潔な共感的な認識]

💡 [クイックセルフケアのヒント]

🏥 [日本語と英語での診療科名を含む推奨診療科]

⚠️ [必要に応じて1つの重要な警告サイン]

緊急の場合: "🚨 今すぐ119に電話してください"

合計応答を100語以内に保ちますが、明確さのために絵文字と改行を使用してください。''';
      }
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _currentChatId == null) return;

    String userMessage = _messageController.text.trim();
    _messageController.clear();

    await _stopSpeaking();

    setState(() {
      _showGreeting = false;
      _isLoading = true;
    });

    await _chatService.saveMessage(
      chatId: _currentChatId!,
      message: userMessage,
      sender: 'user',
    );

    _conversationHistory.add({
      "role": "user",
      "parts": [
        {"text": userMessage}
      ]
    });

    String aiResponse = await _getAIResponse(userMessage);

    await _chatService.saveMessage(
      chatId: _currentChatId!,
      message: aiResponse,
      sender: 'ai',
    );

    await _chatService.updateLastMessage(_currentChatId!, userMessage);

    setState(() {
      _isLoading = false;
    });

    _scrollToBottom();
  }

  Future<String> _getAIResponse(String userMessage) async {
    print('Starting Gemini API call for message: $userMessage');

    int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        String apiKey = _getNextApiKey();
        print('Using API key index: $_currentKeyIndex');

        final response = await http.post(
          Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent'),
          headers: {
            'Content-Type': 'application/json',
            "x-goog-api-key": apiKey
          },
          body: jsonEncode({
            "contents": _conversationHistory,
            "systemInstruction": {
              "parts": [
                {"text": _getSystemInstruction()}
              ]
            },
            "generationConfig": {
              "temperature": 0.85,
              "topP": 0.9,
              "topK": 45,
              "maxOutputTokens": 2048
            }
          }),
        ).timeout(const Duration(seconds: 30));

        print('Gemini API response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String aiResponse =
          data['candidates'][0]['content']['parts'][0]['text'];

          print('Gemini API success!');

          _conversationHistory.add({
            "role": "model",
            "parts": [
              {"text": aiResponse}
            ]
          });

          return aiResponse;
        } else if (response.statusCode == 429 || response.statusCode == 503) {
          print('Gemini API rate limit or service unavailable, retry $retryCount');
          retryCount++;
          if (retryCount < maxRetries) {
            int waitTime = (2 * retryCount);
            await Future.delayed(Duration(seconds: waitTime));
          } else {
            return _isEnglish
                ? "I'm currently overloaded. Please try again in a moment."
                : "申し訳ございませんが、現在サーバーが混雑しています。少し時間をおいて再度お試しください。";
          }
        } else {
          print('Gemini API error: ${response.statusCode} - ${response.body}');
          return _isEnglish
              ? "Sorry, I encountered an error. Please try again."
              : "申し訳ございませんが、エラーが発生しました。もう一度お試しください。";
        }
      } catch (e) {
        print('Gemini API exception: $e');
        return _isEnglish
            ? "Network error. Please check your connection."
            : "ネットワークエラーが発生しました。接続を確認してください。";
      }
    }

    return _isEnglish
        ? "Sorry, I couldn't respond."
        : "申し訳ございませんが、応答できませんでした。";
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 45,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    _isEnglish ? 'Settings' : '設定',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _isEnglish ? '🌐 Language' : '🌐 言語',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _buildLanguageCard(
                          flag: '🇬🇧',
                          label: 'English',
                          isSelected: _isEnglish,
                          onTap: () async {
                            await _stopSpeaking();
                            setState(() {
                              _isEnglish = true;
                              _conversationHistory.clear();
                            });
                            await _flutterTts.setLanguage('en-US');

                            Navigator.pop(context);

                            if (_currentChatId != null) {
                              await _chatService.saveMessage(
                                chatId: _currentChatId!,
                                message: "Language switched to English. I will now respond only in English.",
                                sender: 'ai',
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildLanguageCard(
                          flag: '🇯🇵',
                          label: '日本語',
                          isSelected: !_isEnglish,
                          onTap: () async {
                            await _stopSpeaking();
                            setState(() {
                              _isEnglish = false;
                              _conversationHistory.clear();
                            });
                            await _flutterTts.setLanguage('ja-JP');

                            Navigator.pop(context);

                            if (_currentChatId != null) {
                              await _chatService.saveMessage(
                                chatId: _currentChatId!,
                                message: "言語を日本語に切り替えました。これからは日本語のみで応答します。",
                                sender: 'ai',
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _isEnglish ? '💬 Response Type' : '💬 応答タイプ',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _buildModeCard(
                    icon: Icons.bolt_rounded,
                    title: _isEnglish ? 'Quick Mode' : 'クイックモード',
                    subtitle: _isEnglish ? 'Fast answers' : '迅速な回答',
                    isSelected: !_isDetailedMode,
                    color: Colors.orange,
                    onTap: () {
                      setState(() {
                        _isDetailedMode = false;
                        _conversationHistory.clear();
                      });
                      Navigator.pop(context);
                    },
                  ),

                  const SizedBox(height: 12),

                  _buildModeCard(
                    icon: Icons.description_rounded,
                    title: _isEnglish ? 'Detailed Mode' : '詳細モード',
                    subtitle: _isEnglish ? 'Full guidance' : '完全なガイダンス',
                    isSelected: _isDetailedMode,
                    color: primaryBlue,
                    onTap: () {
                      setState(() {
                        _isDetailedMode = true;
                        _conversationHistory.clear();
                      });
                      Navigator.pop(context);
                    },
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLanguageCard({
    required String flag,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? veryLightBlue : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryBlue : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? primaryBlue : Colors.black87,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, color: primaryBlue, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle, color: color, size: 20),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: primaryBlue,
        toolbarHeight: 70,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.medical_services_rounded,
                  color: primaryBlue, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isEnglish ? 'Medical Assistant' : '医療アシスタント',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _isDetailedMode
                        ? (_isEnglish ? 'Detailed' : '詳細')
                        : (_isEnglish ? 'Quick' : 'クイック'),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            _stopSpeaking();
            Navigator.pop(context);
          },
        ),
        actions: [
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.white),
              onPressed: _stopSpeaking,
              tooltip: _isEnglish ? 'Stop Speaking' : '音声停止',
            ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 28),
            color: Colors.white,
            onPressed: _showSettingsBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              _stopSpeaking();
              _createNewChat();
              setState(() {
                _showGreeting = true;
                _conversationHistory.clear();
              });
            },
          ),
        ],
      ),
      body: _currentChatId == null
          ? const Center(
        child: CircularProgressIndicator(color: Color(0xFF5DADE2)),
      )
          : Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [veryLightBlue, Colors.white],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _chatService.getChatHistory(_currentChatId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(child: Text('エラー: ${snapshot.error}'));
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  List<ChatMessage> messages = snapshot.data!;

                  if (messages.isEmpty && _showGreeting) {
                    return _buildGreetingScreen();
                  }

                  // Auto-scroll to bottom when new messages arrive
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages.length && _isLoading) {
                        return _buildLoadingMessage();
                      }

                      ChatMessage message = messages[index];
                      bool isUser = message.sender == 'user';
                      String messageId = '${message.timestamp.millisecondsSinceEpoch}';

                      return ChatBubble(
                        message: message,
                        userName: widget.userName,
                        primaryBlue: primaryBlue,
                        isEnglish: _isEnglish,
                        onSpeak: isUser ? null : () => _speak(message.message, messageId),
                        isSpeaking: !isUser && _isSpeaking && _speakingMessageId == messageId,
                      );
                    },
                  );
                },
              ),
            ),
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                        AlwaysStoppedAnimation<Color>(primaryBlue),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEnglish ? 'Thinking...' : '考え中...',
                      style: TextStyle(
                        fontSize: 17,
                        color: primaryBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingScreen() {
    int hour = DateTime.now().hour;
    String greeting = hour < 12
        ? (_isEnglish ? 'Good morning' : 'おはようございます')
        : hour < 18
        ? (_isEnglish ? 'Good afternoon' : 'こんにちは')
        : (_isEnglish ? 'Good evening' : 'こんばんは');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.medical_services_outlined,
                size: 60,
                color: primaryBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '$greeting、${widget.userName}さん',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _isEnglish
                  ? 'I\'m your medical assistant.\nHow can I help you today?'
                  : '医療アシスタントです。\nどのようなご相談でしょうか?',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF7F8C8D),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingMessage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: primaryBlue,
            child:
            const Icon(Icons.medical_services, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isEnglish ? 'Typing...' : '入力中...',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF7F8C8D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: veryLightBlue,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: primaryBlue.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(fontSize: 17, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: _isEnglish ? 'Type message...' : 'メッセージを入力...',
                    hintStyle:
                    TextStyle(fontSize: 17, color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryBlue, lightBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _isLoading ? null : _sendMessage,
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 24),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _flutterTts.stop();
    super.dispose();
  }
}

// Chat Bubble Widget
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final String userName;
  final Color primaryBlue;
  final bool isEnglish;
  final VoidCallback? onSpeak;
  final bool isSpeaking;

  const ChatBubble({
    super.key,
    required this.message,
    required this.userName,
    required this.primaryBlue,
    required this.isEnglish,
    this.onSpeak,
    this.isSpeaking = false,
  });

  @override
  Widget build(BuildContext context) {
    bool isUser = message.sender == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.medical_services_rounded,
                  size: 22, color: Colors.white),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUser ? primaryBlue : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isUser ? Colors.transparent : Colors.grey.shade200,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isUser
                                ? (isEnglish ? 'You' : 'あなた')
                                : (isEnglish ? 'Assistant' : 'アシスタント'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isUser
                                  ? Colors.white.withOpacity(0.9)
                                  : primaryBlue,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatTime(message.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: isUser
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message.message,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: isUser ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isUser && onSpeak != null) ...[
                  const SizedBox(height: 6),
                  IconButton(
                    icon: Icon(
                      isSpeaking ? Icons.stop_circle : Icons.volume_up,
                      color: isSpeaking ? Colors.red : primaryBlue,
                      size: 22,
                    ),
                    onPressed: onSpeak,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: isSpeaking
                        ? (isEnglish ? 'Stop' : '停止')
                        : (isEnglish ? 'Speak' : '読み上げ'),
                  ),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1e88e5),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1e88e5).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.person_rounded,
                  size: 22, color: Colors.white),
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