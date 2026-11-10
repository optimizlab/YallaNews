// Ask This News - Chat Interface with Article Context
// Allows users to ask questions about the current article

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
      text: 'Hello! I\'ve read this article. What would you like to know?',
      isUser: false,
      timestamp: DateTime.now(),
    ));
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

      final result = await AIService.instance.generate(
        prompt: '$contextStr\n\nQuestion: $text\n\nAnswer based on the article content:',
        maxTokens: 300,
        temperature: 0.3,
      );

      final responseText = result['text'] as String? ?? 'I couldn\'t generate a response.';

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
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _buildChatContent(context, theme, l10n),
        ),
      ],
    );
  }

  Widget _buildChatContent(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    if (!_isExpanded) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 400,
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
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
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    final List<Widget> children = <Widget>[];

    if (!msg.isUser) {
      children.add(
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      );
      children.add(const SizedBox(width: 8));

      children.add(
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: msg.isUser
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                bottomRight: Radius.circular(msg.isUser ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.isError)
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Error',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                Text(
                  msg.text,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    height: 1.5,
                    color: msg.isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
),
          ),
),
        );
      }
      if (msg.isUser) {
        children.add(const SizedBox(width: 8));
        children.add(
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.colorScheme.primary,
            child: Icon(
              Icons.person_rounded,
              size: 16,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        );
      }

      return Row(
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _focusNode.dispose();
    super.dispose();
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