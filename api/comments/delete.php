<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_delete();
$userId = require_auth();
check_rate_limit('comment_delete:' . get_client_ip(), 30, 300);

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing comment id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "DELETE FROM yn_comments WHERE id = ? AND user_id = ?";
    $db->query($sql, [$id, $userId]);

    json_response([
        'success' => true,
        'message' => 'Comment deleted successfully'
    ]);

} catch (Exception $e) {
    error_log('Delete comment error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete comment'], 500);
}
?>
