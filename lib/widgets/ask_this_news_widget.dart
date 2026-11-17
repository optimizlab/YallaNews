// Ask This News - Chat Interface with Article Context
// Uses the embedded AI (yalla_core via AIService) for grounded, smart answers,
// with a deterministic extractive fallback when the native model is unavailable.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../l10n/app_localizations.dart';
import '../models/news_model.dart';
import '../services/ai_service.dart';
import '../widgets/cached_news_image.dart';

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
  bool _aiReady = false;
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

    AIService.instance.addListener(_onAiChanged);
    _aiReady = AIService.instance.isReady;
    // initialize() rethrows on failure (missing native library / model dir),
    // so swallow the error here — the widget still works offline via fallback.
    unawaited(AIService.instance.initialize().catchError((_) => null));

    _messages.add(ChatMessage(
      text: 'Hello! I have read this article. What would you like to know?',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  void _onAiChanged() {
    if (!mounted) return;
    setState(() => _aiReady = AIService.instance.isReady);
  }

  @override
  void dispose() {
    AIService.instance.removeListener(_onAiChanged);
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
      String responseText;
      if (_aiReady) {
        responseText = await _generateAiAnswer(text);
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
            text: _aiReady
                ? 'I could not generate a response right now. Asking based on the article instead.\n\n${_fallbackAnswer(text)}'
                : 'Sorry, I encountered an error: ${e.toString()}',
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

  /// Grounded generation using the embedded AI (yalla_core inference engine).
  /// Answers strictly from the article, in the user's language, with conversation
  /// history so it behaves as a real multi-turn chatbot.
  Future<String> _generateAiAnswer(String question) async {
    final content = widget.article.content.trim();
    final trimmedContent = content.length > 2500
        ? '${content.substring(0, 2500)}...'
        : content;

    final recent = _messages.length <= 8
        ? _messages
        : _messages.sublist(_messages.length - 8);
    final history = <String>[];
    for (final m in recent) {
      if (m.isUser) {
        history.add('User: ${m.text}');
      } else if (!m.isError) {
        history.add('Assistant: ${m.text}');
      }
    }
    final historyBlock = history.isNotEmpty ? history.join('\n') + '\n' : '';

    final prompt = '''You are a helpful news assistant answering questions strictly about the article below.
Rules:
- Base every answer ONLY on the article title, summary, and content provided.
- If the answer is not in the article, say so clearly instead of inventing facts.
- Be concise, accurate, and helpful.
- Reply in the same language as the user's question.
- Do not include meta-commentary, just the answer.

ARTICLE
Title: ${widget.article.title}
Source: ${widget.article.displaySourceName}
Category: ${widget.article.language.isNotEmpty ? widget.article.language : 'unknown'} | ${widget.article.category}
Summary: ${widget.article.summary}
Content: $trimmedContent

$historyBlock
User: $question
Assistant:''';

    final result = await AIService.instance.generate(
      prompt: prompt,
      maxTokens: 400,
      temperature: 0.3,
      topP: 0.9,
    );

    final text = (result['text'] as String?)?.trim() ?? '';
    if (text.isNotEmpty) return text;

    // Empty generation -> fall back to extractive answer.
    return _fallbackAnswer(question);
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _aiReady
                            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _aiReady ? Icons.auto_awesome_rounded : Icons.offline_bolt_rounded,
                            size: 10,
                            color: _aiReady
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _aiReady ? 'AI ready' : 'Offline',
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _aiReady
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Animate the actual available height instead of relying on
              // AnimatedSize's intrinsic measurement of a Column containing an
              // Expanded child (which yields zero-height ListView + dead input).
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isExpanded ? constraints.maxHeight : 0,
                child: _isExpanded
                    ? _buildChatContent(context, theme, l10n)
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatContent(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    if (!_isExpanded) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        _buildNewsCard(context, theme, l10n),
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
    );
  }

  Widget _buildNewsCard(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    final imageUrl = widget.article.imageUrl;
    final hasImage = imageUrl.isNotEmpty &&
        !imageUrl.contains('placehold.co') &&
        !imageUrl.contains('placeholder');

    final title = widget.article.title;
    final desc = widget.article.summary.isNotEmpty
        ? widget.article.summary
        : (widget.article.shortTitle.isNotEmpty
            ? widget.article.shortTitle
            : widget.article.content);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              SizedBox(
                width: 92,
                height: 92,
                child: CachedNewsImage(
                  imageUrl: imageUrl,
                  fallbackImageUrl: NewsModel.getFallbackImage(widget.article.category),
                  searchQuery: '${widget.article.title} ${widget.article.category}',
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.article_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 32,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 92,
                height: 92,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.article_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 32,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                              height: 1.25,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.article.category,
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.source_rounded,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.article.displaySourceName.isNotEmpty
                              ? widget.article.displaySourceName
                              : l10n.translate('unknownSource'),
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      desc.isNotEmpty
                          ? desc.length > 140
                              ? '${desc.substring(0, 140)}...'
                              : desc
                          : l10n.translate('executiveSummary'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        color: desc.isNotEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                        fontStyle: desc.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
              mainAxisSize: MainAxisSize.min,
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
