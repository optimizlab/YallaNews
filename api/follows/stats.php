<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(120);

$userId = sanitize_string($_GET['user_id'] ?? '', 64);

if (!$userId) {
    json_response(['error' => 'Missing user_id parameter'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT COUNT(*) FROM yn_user_following WHERE follower_id = ?";
    $stmt = $db->query($sql, [$userId]);
    $followingCount = intval($stmt->fetchColumn());

    $sql = "SELECT COUNT(*) FROM yn_user_following WHERE following_id = ?";
    $stmt = $db->query($sql, [$userId]);
    $followersCount = intval($stmt->fetchColumn());

    json_response([
        'success' => true,
        'followingCount' => $followingCount,
        'followersCount' => $followersCount
    ]);

} catch (Exception $e) {
    error_log('Follow stats error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch follow stats'], 500);
}
?>
