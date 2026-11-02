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

    $sql = "SELECT n.*,
                   c.name as category_name, c.name_en as category_name_en
            FROM yn_news n
            LEFT JOIN yn_categories c ON n.category = c.id
            WHERE n.id = ?
            LIMIT 1";
    $stmt = $db->query($sql, [$id]);
    $article = $stmt->fetch();

    if (!$article) {
        json_response(['error' => 'Article not found'], 404);
    }

    $sourceName = $article['source_name'] ?? $article['source_id'] ?? '';
    $sourceUrl = $article['source_url'] ?? '';
    $sourceUrlArticle = $article['source_url_article'] ?? $article['source_url'] ?? '';

    json_response([
        'success' => true,
        'article' => [
            'id' => $article['id'],
            'title' => $article['title'],
            'summary' => $article['summary'],
            'content' => $article['content'],
            'language' => $article['language'] ?? 'ar',
            'category' => $article['category'],
            'categoryName' => $article['category_name'] ?? $article['category'],
            'categoryNameEn' => $article['category_name_en'] ?? '',
            'source' => [
                'name' => $sourceName,
                'url' => $sourceUrl,
                'score' => floatval($article['source_score'] ?? 0.0)
            ],
            'sourceName' => $sourceName,
            'sourceUrl' => $sourceUrlArticle,
            'sourceUrlArticle' => $sourceUrlArticle,
            'imageUrl' => $article['image_url'],
            'publishedAt' => intval($article['published_at']),
            'status' => $article['status'] ?? 'published'
        ]
    ]);

} catch (Exception $e) {
    error_log('Get article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch article'], 500);
}
?>
