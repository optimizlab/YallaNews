<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('unfollow:' . get_client_ip(), 60, 300);

$data = get_json_input();

$followingId = sanitize_string($data['followingId'] ?? '', 64);

validate_required(['followingId' => $followingId]);

try {
    $db = Database::getInstance();

    $sql = "DELETE FROM yn_user_following WHERE follower_id = ? AND following_id = ?";
    $db->query($sql, [$userId, $followingId]);

    json_response([
        'success' => true,
        'message' => 'Unfollowed successfully'
    ]);

} catch (Exception $e) {
    error_log('Unfollow error: ' . $e->getMessage());
    json_response(['error' => 'Failed to unfollow'], 500);
}
?>
