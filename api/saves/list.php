<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();
$userId = require_auth();

list($page, $limit, $offset) = get_pagination_params();

try {
    $db = Database::getInstance();

    $countSql = "SELECT COUNT(*) FROM yn_user_saved_articles WHERE user_id = ?";
    $stmt = $db->query($countSql, [$userId]);
    $total = intval($stmt->fetchColumn());

    $sql = "SELECT n.id, n.title, n.summary, n.image_url, n.published_at, n.category
            FROM yn_user_saved_articles s
            JOIN yn_news n ON s.article_id = n.id
            WHERE s.user_id = ? AND n.status = 'published'
            ORDER BY s.created_at DESC
            LIMIT ? OFFSET ?";
    $stmt = $db->query($sql, [$userId, $limit, $offset]);
    $articles = $stmt->fetchAll();

    $formatted = array_map(function($a) {
        return [
            'id' => $a['id'],
            'title' => $a['title'],
            'summary' => $a['summary'],
            'imageUrl' => $a['image_url'],
            'publishedAt' => intval($a['published_at']),
            'category' => $a['category']
        ];
    }, $articles);

    json_response([
        'success' => true,
        'articles' => $formatted,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'totalPages' => (int) ceil($total / $limit)
        ]
    ]);

} catch (Exception $e) {
    error_log('List saved error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch saved articles'], 500);
}
?>
