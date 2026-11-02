<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

try {
    $db = Database::getInstance();

    $page = max(1, intval($_GET['page'] ?? 1));
    $limit = min(100, max(1, intval($_GET['limit'] ?? 20)));
    $offset = ($page - 1) * $limit;
    $search = sanitize_string($_GET['search'] ?? '', 100);
    $articleId = sanitize_string($_GET['articleId'] ?? '', 64);

    $where = [];
    $params = [];

    if (!empty($search)) {
        $where[] = "(c.text LIKE ? OR c.user_name LIKE ?)";
        $params[] = "%$search%";
        $params[] = "%$search%";
    }
    if (!empty($articleId)) {
        $where[] = "c.article_id = ?";
        $params[] = $articleId;
    }

    $whereClause = !empty($where) ? "WHERE " . implode(' AND ', $where) : "";

    $countStmt = $db->query("SELECT COUNT(*) as total FROM yn_comments c $whereClause", $params);
    $total = intval($countStmt->fetch()['total'] ?? 0);

    $sql = "SELECT c.id, c.article_id, c.user_id, c.user_name, c.text, c.parent_id, c.created_at,
                   n.title as article_title 
            FROM yn_comments c 
            LEFT JOIN yn_news n ON c.article_id = n.id 
            $whereClause 
            ORDER BY c.created_at DESC 
            LIMIT $limit OFFSET $offset";
    $stmt = $db->query($sql, $params);
    $comments = $stmt->fetchAll();

    $formatted = array_map(function($c) {
        return [
            'id' => $c['id'],
            'articleId' => $c['article_id'],
            'articleTitle' => $c['article_title'] ?? 'مقال',
            'userId' => $c['user_id'],
            'userName' => $c['user_name'],
            'text' => $c['text'],
            'parentId' => $c['parent_id'],
            'createdAt' => $c['created_at']
        ];
    }, $comments);

    json_response([
        'success' => true,
        'comments' => $formatted,
        'total' => $total,
        'page' => $page,
        'limit' => $limit,
        'pages' => ceil($total / $limit)
    ]);
} catch (Exception $e) {
    error_log('List comments error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch comments', 'details' => $e->getMessage()], 500);
}
?>
