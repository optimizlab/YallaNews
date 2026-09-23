<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('follow:' . get_client_ip(), 60, 300);

$data = get_json_input();

$followingId = sanitize_string($data['followingId'] ?? '', 64);

validate_required(['followingId' => $followingId]);

if ($followingId === $userId) {
    json_response(['error' => 'Cannot follow yourself'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "INSERT IGNORE INTO yn_user_following (follower_id, following_id, created_at) VALUES (?, ?, NOW())";
    $db->query($sql, [$userId, $followingId]);

    json_response([
        'success' => true,
        'message' => 'Followed successfully'
    ]);

} catch (Exception $e) {
    error_log('Follow error: ' . $e->getMessage());
    json_response(['error' => 'Failed to follow'], 500);
}
?>
