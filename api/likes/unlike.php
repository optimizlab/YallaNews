<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('unlike:' . get_client_ip(), 60, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);

validate_required(['articleId' => $articleId]);

try {
    $db = Database::getInstance();

    $sql = "DELETE FROM yn_user_liked_articles WHERE user_id = ? AND article_id = ?";
    $db->query($sql, [$userId, $articleId]);

    json_response([
        'success' => true,
        'message' => 'Article unliked successfully'
    ]);

} catch (Exception $e) {
    error_log('Unlike error: ' . $e->getMessage());
    json_response(['error' => 'Failed to unlike article'], 500);
}
?>
