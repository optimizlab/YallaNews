<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../categories/category_helpers.php';
require_once __DIR__ . '/news_schema.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing article id'], 400);
}

try {
    $db = Database::getInstance();
    $newsColumns = news_table_columns($db);
    $sourceNameExpression = news_source_name_expression($newsColumns);
    $sourceUrlExpression = news_source_url_expression($newsColumns);
    $sourceJoin = news_source_join($newsColumns);

    // Defensive category select
    $categoryColumns = [];
    $categorySelect = '';
    try {
        $categoryColumns = category_table_columns($db);
        if (!empty($categoryColumns)) {
            $categorySelect = implode(', ', category_join_translation_select($categoryColumns));
        }
    } catch (Exception $e) {
        error_log('category helpers failed: ' . $e->getMessage());
    }

    $sql = "SELECT n.*, $sourceNameExpression AS resolved_source_name,
               $sourceUrlExpression AS resolved_source_url,
               $categorySelect
            FROM yn_news n
            $sourceJoin
            LEFT JOIN yn_categories c ON n.category = c.id
            WHERE n.id = ?
            LIMIT 1";
    $stmt = $db->query($sql, [$id]);
    $article = $stmt->fetch();

    if (!$article) {
        json_response(['error' => 'Article not found'], 404);
    }

    $sourceName = $article['resolved_source_name'] ?? '';
    $sourceUrl = $article['resolved_source_url'] ?? '';
    $sourceUrlArticle = $article['source_url_article'] ?? $article['source_url'] ?? '';
    $categoryTranslations = [
        'ar' => (string)($article['category_name'] ?? ''),
        'en' => (string)($article['category_name_en'] ?? ''),
        'fr' => (string)($article['category_name_fr'] ?? ''),
        'tr' => (string)($article['category_name_tr'] ?? ''),
    ];
    $language = strtolower((string)($article['language'] ?? 'ar'));
    $localizedCategoryName = $categoryTranslations[$language] ?? '';
    if ($localizedCategoryName === '') {
        $localizedCategoryName = $categoryTranslations['ar'] ?: (string)$article['category'];
    }

    json_response([
        'success' => true,
        'article' => [
            'id' => $article['id'],
            'title' => $article['title'],
            'summary' => $article['summary'],
            'content' => $article['content'],
            'language' => $article['language'] ?? 'ar',
            'category' => $article['category'],
            'categoryName' => $localizedCategoryName,
            'categoryNameAr' => $categoryTranslations['ar'],
            'categoryNameEn' => $article['category_name_en'] ?? '',
            'categoryNameFr' => $article['category_name_fr'] ?? '',
            'categoryNameTr' => $article['category_name_tr'] ?? '',
            'categoryTranslations' => $categoryTranslations,
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
    json_response(['error' => 'Failed to fetch article', 'details' => $e->getMessage()], 500);
}
