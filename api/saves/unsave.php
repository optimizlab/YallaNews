<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('unsave:' . get_client_ip(), 60, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);

validate_required(['articleId' => $articleId]);

try {
    $db = Database::getInstance();

    $sql = "DELETE FROM yn_user_saved_articles WHERE user_id = ? AND article_id = ?";
    $db->query($sql, [$userId, $articleId]);

    json_response([
        'success' => true,
        'message' => 'Article unsaved successfully'
    ]);

} catch (Exception $e) {
    error_log('Unsave error: ' . $e->getMessage());
    json_response(['error' => 'Failed to unsave article'], 500);
}
?>
