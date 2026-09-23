<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing article id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "DELETE FROM yn_news WHERE id = ?";
    $db->query($sql, [$id]);

    json_response([
        'success' => true,
        'message' => 'Article deleted successfully'
    ]);

} catch (Exception $e) {
    error_log('Delete article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete article'], 500);
}
?>
