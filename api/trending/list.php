<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(1800);

$language = sanitize_string($_GET['language'] ?? 'ar', 8);
$limit = min(50, max(1, intval($_GET['limit'] ?? 10)));

try {
    $db = Database::getInstance();

    $sql = "SELECT id, query, count, language, created_at 
            FROM yn_trending_searches 
            WHERE language = ? 
            ORDER BY count DESC 
            LIMIT ?";
    $stmt = $db->query($sql, [$language, $limit]);
    $trending = $stmt->fetchAll();

    $formatted = array_map(function($t) {
        return [
            'id' => $t['id'],
            'query' => $t['query'],
            'count' => intval($t['count']),
            'language' => $t['language'],
            'createdAt' => intval($t['created_at'])
        ];
    }, $trending);

    json_response([
        'success' => true,
        'trending' => $formatted
    ]);

} catch (Exception $e) {
    error_log('List trending error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch trending searches'], 500);
}
?>
