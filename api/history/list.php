<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();
$userId = require_auth();

list($page, $limit, $offset) = get_pagination_params();

try {
    $db = Database::getInstance();

    $countSql = "SELECT COUNT(*) FROM yn_user_reading_history WHERE user_id = ?";
    $stmt = $db->query($countSql, [$userId]);
    $total = intval($stmt->fetchColumn());

    $sql = "SELECT h.article_id, h.read_at, n.title, n.summary, n.image_url, n.published_at, n.category
            FROM yn_user_reading_history h
            JOIN yn_news n ON h.article_id = n.id
            WHERE h.user_id = ? AND n.status = 'published'
            ORDER BY h.read_at DESC
            LIMIT ? OFFSET ?";
    $stmt = $db->query($sql, [$userId, $limit, $offset]);
    $history = $stmt->fetchAll();

    $formatted = array_map(function($h) {
        return [
            'articleId' => $h['article_id'],
            'readAt' => intval($h['read_at']),
            'article' => [
                'title' => $h['title'],
                'summary' => $h['summary'],
                'imageUrl' => $h['image_url'],
                'publishedAt' => intval($h['published_at']),
                'category' => $h['category']
            ]
        ];
    }, $history);

    json_response([
        'success' => true,
        'history' => $formatted,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'totalPages' => (int) ceil($total / $limit)
        ]
    ]);

} catch (Exception $e) {
    error_log('List history error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch reading history'], 500);
}
?>
