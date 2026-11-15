<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(1800);

$language = sanitize_string($_GET['language'] ?? 'ar', 8);
list($page, $limit, $offset) = get_pagination_params();

try {
    $db = Database::getInstance();

    $countStmt = $db->query("SELECT COUNT(*) as total FROM yn_trending_searches WHERE language = ?", [$language]);
    $total = intval($countStmt->fetch()['total'] ?? 0);

    $sql = "SELECT id, query, count, language, created_at 
            FROM yn_trending_searches 
            WHERE language = ? 
            ORDER BY count DESC 
            LIMIT ? OFFSET ?";
    $stmt = $db->query($sql, [$language, $limit, $offset]);
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
        'trending' => $formatted,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'totalPages' => (int) ceil($total / $limit)
        ]
    ]);

} catch (Exception $e) {
    error_log('List trending error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch trending searches'], 500);
}
?>
