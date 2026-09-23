<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('history_add:' . get_client_ip(), 30, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);
$readAt = intval($data['readAt'] ?? time() * 1000);

validate_required(['articleId' => $articleId]);

try {
    $db = Database::getInstance();

    $sql = "INSERT INTO yn_user_reading_history (user_id, article_id, read_at, created_at) 
            VALUES (?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE read_at = VALUES(read_at), created_at = NOW()";
    $db->query($sql, [$userId, $articleId, $readAt]);

    json_response([
        'success' => true,
        'message' => 'Reading history updated successfully'
    ]);

} catch (Exception $e) {
    error_log('Add history error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update reading history'], 500);
}
?>
