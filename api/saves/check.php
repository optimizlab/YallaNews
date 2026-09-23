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

    $sql = "SELECT COUNT(*) FROM yn_user_saved_articles WHERE user_id = ? AND article_id = ?";
    $stmt = $db->query($sql, [$userId, $articleId]);
    $saved = $stmt->fetchColumn() > 0;

    json_response([
        'success' => true,
        'saved' => $saved
    ]);

} catch (Exception $e) {
    error_log('Check save error: ' . $e->getMessage());
    json_response(['error' => 'Failed to check save status'], 500);
}
?>
