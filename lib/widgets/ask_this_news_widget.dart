// Ask This News - Chat Interface with Article Context

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/ai_service.dart';

class AskThisNewsWidget extends StatefulWidget {
  final NewsModel article;
  final bool startOpen;

  const AskThisNewsWidget({
    super.key,
    required this.article,
    this.startOpen = false,
  });

  @override
  State<AskThisNewsWidget> createState() => _AskThisNewsWidgetState();
}

class _AskThisNewsWidgetState extends State<AskThisNewsWidget>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isSending = false;
  bool _isExpanded = false;
  late AnimationController _animationController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    if (widget.startOpen) {
      _toggleExpanded();
    }

    _messages.add(ChatMessage(
      text: 'Hello! I have read this article. What would you like to know?',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isSending = true;
      _controller.clear();
    });

    _scrollToBottom();

    try {
      final contextStr = '''
Article Title: ${widget.article.title}
Article Summary: ${widget.article.summary}
Article Content: ${widget.article.content}
Category: ${widget.article.category}
Language: ${widget.article.language}
''';

      String responseText;
      if (AIService.instance.isReady) {
        final result = await AIService.instance.generate(
          prompt: '$contextStr\n\nQuestion: $text\n\nAnswer based on the article content:',
          maxTokens: 300,
          temperature: 0.3,
        );
        responseText = result['text'] as String? ?? 'I could not generate a response.';
      } else {
        responseText = _fallbackAnswer(text);
      }

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: responseText,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: 'Sorry, I encountered an error: ${e.toString()}',
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _fallbackAnswer(String question) {
    final lang = widget.article.language;
    final isArabic = lang == 'ar';
    final title = widget.article.title.trim();
    final summary = widget.article.summary.trim();
    final content = widget.article.content.trim();
    final category = widget.article.category.trim();

    final qLower = question.toLowerCase();
    final keywords = _extractKeywords(qLower);

    final candidates = <String>[];
    if (title.isNotEmpty) candidates.add(title);
    if (summary.isNotEmpty && summary.toLowerCase() != title.toLowerCase()) {
      candidates.add(summary);
    }
    candidates.addAll(_splitSentences(content));

    String best = '';
    int bestScore = 0;
    for (final s in candidates) {
      final sLower = s.toLowerCase();
      int score = 0;
      for (final kw in keywords) {
        if (sLower.contains(kw)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }

    final buffer = StringBuffer();
    if (bestScore > 0 && best.isNotEmpty) {
      if (isArabic) {
        buffer.writeln('بناءً على الخبر، الإجابة هي: $best');
      } else {
        buffer.writeln('Based on the article: $best');
      }
    } else if (summary.isNotEmpty) {
      if (isArabic) {
        buffer.writeln('لم أجد إجابة مباشرة لسؤالك ("$question") في محتوى الخبر.');
        buffer.writeln();
        buffer.writeln('ملخص الخبر: $summary');
      } else {
        buffer.writeln('I could not find a direct answer to your question ("$question") in the article.');
        buffer.writeln();
        buffer.writeln('Article summary: $summary');
      }
    } else if (title.isNotEmpty) {
      if (isArabic) {
        buffer.writeln('لم أجد إجابة مباشرة لسؤالك ("$question") في هذا الخبر.');
        buffer.writeln();
        buffer.writeln('عنوان الخبر: $title');
      } else {
        buffer.writeln('I could not find a direct answer to your question ("$question") in this article.');
        buffer.writeln();
        buffer.writeln('Article title: $title');
      }
    } else {
      if (isArabic) {
        buffer.writeln('عذراً، لا يمكنني الإجابة على سؤالك ("$question") لأن محتوى الخبر غير متاح.');
      } else {
        buffer.writeln('Sorry, I cannot answer your question ("$question") because the article content is not available.');
      }
    }

    if (isArabic) {
      buffer.writeln();
      buffer.writeln('• القسم: $category');
    } else {
      buffer.writeln();
      buffer.writeln('• Category: $category');
    }

    return buffer.toString().trim();
  }

  static List<String> _extractKeywords(String text) {
    final stopWords = <String>{
      'هذا','هذه','ذلك','الذي','التي','على','إلى','من','في','عن','مع','بعد','قبل',
      'كان','كانت','هو','هي','أنا','أنت','نحن','هم','هن','أو','و','ثم',
      'the','and','for','with','from','that','this','will','have','has','was','are',
      'is','it','you','your','what','who','where','when','why','how','can','could',
      'would','should','a','an','in','of','to','be','been','do','does','did','not',
      'no','yes','on','at','by','as','if','or','but','about'
    };
    final words = <String>[];
    for (final raw in text.split(RegExp(r'\s+'))) {
      final word = raw
          .replaceAll(RegExp(r'^[^\w\u0600-\u06FF]+|[^\w\u0600-\u06FF]+$'), '')
          .toLowerCase();
      if (word.length >= 3 &&
          !stopWords.contains(word) &&
          !RegExp(r'^\d+$').hasMatch(word)) {
        words.add(word);
      }
    }
    return words.toSet().toList();
  }

  static List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!؟])\s+'))
        .map((s) => s.trim())
        .where((s) => s.length >= 10)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.chat_rounded,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.translate('askThisNews'),
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            l10n.translate('askThisNewsSubtitle'),
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded ? _buildChatContent(context, theme, l10n) : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _buildChatContent(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    if (!_isExpanded) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(context, msg);
              },
            ),
          ),
          _buildInputArea(context, theme, l10n),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: l10n.translate('askQuestion'),
                  hintStyle: GoogleFonts.outfit(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                maxLines: null,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            _isSending
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: _sendMessage,
                    icon: Icon(
                      Icons.send_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      shape: const CircleBorder(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);

    if (msg.isUser) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.text,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.done_all_rounded,
                      size: 14,
                      color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context).translate('send'),
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.text,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            height: 1.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (msg.isError) ...[
              const SizedBox(height: 4),
              Text(
                'Error',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}