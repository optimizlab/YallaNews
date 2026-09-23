<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(60);

$userId = sanitize_string($_GET['user_id'] ?? '', 64);
$articleId = sanitize_string($_GET['article_id'] ?? '', 64);

if (!$userId || !$articleId) {
    json_response(['error' => 'Missing required parameters: user_id, article_id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT COUNT(*) FROM yn_user_liked_articles WHERE user_id = ? AND article_id = ?";
    $stmt = $db->query($sql, [$userId, $articleId]);
    $liked = $stmt->fetchColumn() > 0;

    json_response([
        'success' => true,
        'liked' => $liked
    ]);

} catch (Exception $e) {
    error_log('Check like error: ' . $e->getMessage());
    json_response(['error' => 'Failed to check like status'], 500);
}
?>
