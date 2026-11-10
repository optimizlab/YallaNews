<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(120);

$articleId = sanitize_string($_GET['article_id'] ?? $_GET['articleId'] ?? '', 512);

if (!$articleId) {
    json_response(['error' => 'Missing article_id parameter'], 400);
}

try {
    $db = Database::getInstance();

    // Support both direct article ID and article URL
    $resolvedId = $articleId;
    if (str_starts_with($articleId, 'http://') || str_starts_with($articleId, 'https://')) {
        $found = $db->query("SELECT id FROM yn_news WHERE source_url_article = ? LIMIT 1", [$articleId])->fetch();
        if ($found) {
            $resolvedId = $found['id'];
        }
    }

    $sql = "SELECT id, article_id, user_id, user_name, text, parent_id, created_at 
            FROM yn_comments 
            WHERE article_id = ? OR article_id = ?
            ORDER BY created_at ASC";
    $stmt = $db->query($sql, [$articleId, $resolvedId]);
    $comments = $stmt->fetchAll();

    $formatted = array_map(function($c) {
        return [
            'id' => $c['id'],
            'articleId' => $c['article_id'],
            'userId' => $c['user_id'],
            'userName' => $c['user_name'],
            'text' => $c['text'],
            'parentId' => $c['parent_id'],
            'createdAt' => $c['created_at']
        ];
    }, $comments);

    json_response([
        'success' => true,
        'comments' => $formatted
    ]);

} catch (Exception $e) {
    error_log('Get comments error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch comments'], 500);
}
?>
