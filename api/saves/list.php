<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../news/news_schema.php';

no_cache_headers();
$userId = require_auth();

list($page, $limit, $offset) = get_pagination_params();

try {
    $db = Database::getInstance();
    $newsColumns = news_table_columns($db);
    $sourceNameExpression = news_source_name_expression($newsColumns);
    $sourceJoin = news_source_join($newsColumns);

    $countSql = "SELECT COUNT(*) FROM yn_user_saved_articles WHERE user_id = ?";
    $stmt = $db->query($countSql, [$userId]);
    $total = intval($stmt->fetchColumn());

    $sql = "SELECT n.id, n.title, n.summary, n.content, n.image_url, n.published_at, n.category, n.source_url_article,
                   $sourceNameExpression AS source_name
            FROM yn_user_saved_articles s
            JOIN yn_news n ON s.article_id = n.id
            $sourceJoin
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
            'content' => $a['content'] ?? '',
            'imageUrl' => $a['image_url'],
            'sourceUrl' => !empty($a['source_url_article']) ? $a['source_url_article'] : $a['id'],
            'publishedAt' => intval($a['published_at']),
            'category' => $a['category'],
            'source' => ['name' => $a['source_name'] ?? '']
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
