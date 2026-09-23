<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('like:' . get_client_ip(), 60, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);

validate_required(['articleId' => $articleId]);

try {
    $db = Database::getInstance();

    $sql = "INSERT IGNORE INTO yn_user_liked_articles (user_id, article_id, created_at) VALUES (?, ?, NOW())";
    $db->query($sql, [$userId, $articleId]);

    json_response([
        'success' => true,
        'message' => 'Article liked successfully'
    ]);

} catch (Exception $e) {
    error_log('Like error: ' . $e->getMessage());
    json_response(['error' => 'Failed to like article'], 500);
}
?>
