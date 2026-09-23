import 'server_api_service.dart';

class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final List<String> following;
  final List<String> followers;
  final List<String> likedArticles;
  final List<String> savedArticles;
  final DateTime createdAt;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
    this.following = const [],
    this.followers = const [],
    this.likedArticles = const [],
    this.savedArticles = const [],
    required this.createdAt,
  });

  factory UserProfile.fromSnapshot(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['id'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      photoUrl: data['photoUrl'],
      phoneNumber: data['phoneNumber'],
      following: const [],
      followers: const [],
      likedArticles: const [],
      savedArticles: const [],
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'following': following,
      'followers': followers,
      'likedArticles': likedArticles,
      'savedArticles': savedArticles,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    List<String>? following,
    List<String>? followers,
    List<String>? likedArticles,
    List<String>? savedArticles,
    DateTime? createdAt,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      following: following ?? this.following,
      followers: followers ?? this.followers,
      likedArticles: likedArticles ?? this.likedArticles,
      savedArticles: savedArticles ?? this.savedArticles,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class UserService {
  static Future<UserProfile?> getCurrentUser() async {
    final isLoggedIn = await ServerApiService.isLoggedIn();
    if (!isLoggedIn) return null;
    final data = await ServerApiService.getJson('users/get.php');
    if (data['success'] != true || data['user'] == null) return null;
    return UserProfile.fromSnapshot(Map<String, dynamic>.from(data['user']));
  }

  static Future<void> createUserProfile(UserProfile profile) async {
    await ServerApiService.postJson('users/update.php', profile.toJson());
  }

  static Future<void> followUser(String targetUid) async {
    await ServerApiService.postJson('follows/follow.php', {'followingId': targetUid});
  }

  static Future<void> unfollowUser(String targetUid) async {
    await ServerApiService.postJson('follows/unfollow.php', {'followingId': targetUid});
  }

  static Future<void> toggleLikeArticle(String articleId) async {
    await ServerApiService.postJson('likes/like.php', {'articleId': articleId});
  }

  static Future<void> saveArticle(String articleId) async {
    await ServerApiService.postJson('saves/save.php', {'articleId': articleId});
  }

  static Future<void> unsaveArticle(String articleId) async {
    await ServerApiService.postJson('saves/unsave.php', {'articleId': articleId});
  }
}
