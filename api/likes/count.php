<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(30);

$articleId = sanitize_string($_GET['article_id'] ?? '', 64);

if (!$articleId) {
    json_response(['error' => 'Missing required parameter: article_id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT COUNT(*) FROM yn_user_liked_articles WHERE article_id = ?";
    $stmt = $db->query($sql, [$articleId]);
    $count = (int) $stmt->fetchColumn();

    json_response([
        'success' => true,
        'count'   => $count,
    ]);

} catch (Exception $e) {
    error_log('Like count error: ' . $e->getMessage());
    json_response(['error' => 'Failed to get like count'], 500);
}
?>
