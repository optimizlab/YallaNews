<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(120);

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing article id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT n.id, n.title, n.summary, n.content, n.language, n.category, 
                   n.source_name, n.source_url, n.source_score, n.source_url_article, 
                   n.image_url, n.published_at, n.status,
                   c.name as category_name, c.name_en as category_name_en
            FROM yn_news n
            LEFT JOIN yn_categories c ON n.category = c.id
            WHERE n.id = ? AND n.status = 'published'
            LIMIT 1";
    $stmt = $db->query($sql, [$id]);
    $article = $stmt->fetch();

    if (!$article) {
        json_response(['error' => 'Article not found'], 404);
    }

    json_response([
        'success' => true,
        'article' => [
            'id' => $article['id'],
            'title' => $article['title'],
            'summary' => $article['summary'],
            'content' => $article['content'],
            'language' => $article['language'],
            'category' => $article['category'],
            'categoryName' => $article['category_name'],
            'categoryNameEn' => $article['category_name_en'],
            'source' => [
                'name' => $article['source_name'],
                'url' => $article['source_url'],
                'score' => floatval($article['source_score'])
            ],
            'sourceUrl' => $article['source_url_article'],
            'imageUrl' => $article['image_url'],
            'publishedAt' => intval($article['published_at']),
            'status' => $article['status']
        ]
    ]);

} catch (Exception $e) {
    error_log('Get article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch article'], 500);
}
?>
