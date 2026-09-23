import 'package:flutter/material.dart';
import 'server_api_service.dart';
import '../services/server_api_service.dart';

class Comment {
  final String id;
  final String articleId;
  final String userId;
  final String userName;
  final String text;
  final DateTime createdAt;
  final String? parentId;

  Comment({
    required this.id,
    required this.articleId,
    required this.userId,
    required this.userName,
    required this.text,
    required this.createdAt,
    this.parentId,
  });

  factory Comment.fromMap(String id, Map<String, dynamic> data) {
    return Comment(
      id: id,
      articleId: data['articleId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      text: data['text'] ?? '',
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
      parentId: data['parentId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'articleId': articleId,
      'userId': userId,
      'userName': userName,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'parentId': parentId,
    };
  }

  Comment copyWith({
    String? id,
    String? articleId,
    String? userId,
    String? userName,
    String? text,
    DateTime? createdAt,
    String? parentId,
  }) {
    return Comment(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
    );
  }
}

class CommentService {
  static Future<void> addComment(Comment comment) async {
    await ServerApiService.postJson('comments/create.php', {
      'articleId': comment.articleId,
      'userName': comment.userName,
      'text': comment.text,
      'parentId': comment.parentId,
    });
  }

  static Future<List<Comment>> getComments(String articleId) async {
    final comments = await ServerApiService.getComments(articleId);
    return comments.map((c) => Comment.fromMap(c['id'] ?? '', c)).toList();
  }
}
