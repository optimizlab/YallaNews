<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('comment_create:' . get_client_ip(), 30, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);
$userName = sanitize_string($data['userName'] ?? '', 255);
$text = sanitize_string($data['text'] ?? '', 2000);
$parentId = sanitize_string($data['parentId'] ?? null, 64);

validate_required(['articleId' => $articleId, 'userName' => $userName, 'text' => $text]);

try {
    $db = Database::getInstance();
    $id = generate_secure_id('comment_');
    $createdAt = date('Y-m-d H:i:s');

    $sql = "INSERT INTO yn_comments (id, article_id, user_id, user_name, text, parent_id, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?)";
    $db->query($sql, [$id, $articleId, $userId, $userName, $text, $parentId, $createdAt]);

    json_response([
        'success' => true,
        'id' => $id,
        'message' => 'Comment created successfully'
    ], 201);

} catch (Exception $e) {
    error_log('Create comment error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create comment'], 500);
}
?>
