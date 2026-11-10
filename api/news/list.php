<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../categories/category_helpers.php';
require_once __DIR__ . '/news_schema.php';

list($page, $limit, $offset) = get_pagination_params();

$category = sanitize_string($_GET['category'] ?? '', 64);
$language = sanitize_string($_GET['language'] ?? '', 8);
$includeAllStatuses = ($_GET['include_all'] ?? '') === '1';
$relatedOnly = ($_GET['related'] ?? '') === '1';
$excludeUrl = sanitize_string($_GET['exclude_url'] ?? '', 2048);
$search = sanitize_string($_GET['search'] ?? '', 200);
$sortParam = $_GET['sort'] ?? 'published_at';
$sortOrder = in_array(strtoupper($_GET['order'] ?? 'DESC'), ['ASC', 'DESC']) ? strtoupper($_GET['order']) : 'DESC';

$sortColumnMap = [
    'published_at' => 'n.published_at',
    'date' => 'n.published_at',
    'created_at' => 'n.created_at',
    'title' => 'n.title',
    'views' => 'views_count',
    'source' => 'source_name',
    'category' => 'n.category'
];
$sortColumn = $sortColumnMap[$sortParam] ?? 'n.published_at';

if ($relatedOnly && (empty($category) || strtolower($category) === 'all' || empty($language))) {
    json_response([
        'success' => false,
        'error' => 'Related news requires both category and language',
    ], 400);
}

if ($includeAllStatuses) {
    no_cache_headers();
    require_admin();
} else {
    cache_headers(60);
}

try {
    $db = Database::getInstance();
    $newsColumns = news_table_columns($db);
    $sourceNameExpression = news_source_name_expression($newsColumns);
    $sourceUrlExpression = news_source_url_expression($newsColumns);
    $sourceJoin = news_source_join($newsColumns);
    if ($sortParam === 'source') {
        $sortColumn = $sourceNameExpression;
    }

    $categoryColumns = category_table_columns($db);
    $categorySelect = implode(', ', category_join_translation_select($categoryColumns));

    $where = $includeAllStatuses ? ['1 = 1'] : ["n.status = 'published'"];
    $params = [];

    if ($category) {
        $where[] = "n.category = ?";
        $params[] = $category;
    }

    if ($language) {
        $where[] = "n.language = ?";
        $params[] = $language;
    }

    if ($relatedOnly && $excludeUrl !== '') {
        $where[] = "(n.source_url_article IS NULL OR n.source_url_article <> ?)";
        $params[] = $excludeUrl;
    }

    if ($search) {
        $where[] = "(n.title LIKE ? OR n.summary LIKE ?)";
        $searchTerm = "%$search%";
        $params[] = $searchTerm;
        $params[] = $searchTerm;
    }

    $whereClause = implode(' AND ', $where);

    $countSql = "SELECT COUNT(*) FROM yn_news n WHERE $whereClause";
    $stmt = $db->query($countSql, $params);
    $total = intval($stmt->fetchColumn());

    $sql = "SELECT n.id, n.title, n.summary, n.content, n.language, n.category,
                   $sourceNameExpression AS source_id, $sourceUrlExpression AS source_url,
                   n.source_url_article,
                   n.image_url, n.published_at, n.status,
                   $categorySelect,
                   (SELECT COUNT(*) FROM yn_user_reading_history rh WHERE rh.article_id = n.id) AS views_count
             FROM yn_news n
             $sourceJoin
             LEFT JOIN yn_categories c ON n.category = c.id
             WHERE $whereClause
             ORDER BY $sortColumn $sortOrder, n.published_at DESC
             LIMIT ? OFFSET ?";

    $params[] = $limit;
    $params[] = $offset;
    $stmt = $db->query($sql, $params);
    $articles = $stmt->fetchAll();

    $formatted = array_map(function($a) {
        $imageUrl = $a['image_url'];
        $categoryTranslations = [
            'ar' => (string)($a['category_name'] ?? ''),
            'en' => (string)($a['category_name_en'] ?? ''),
            'fr' => (string)($a['category_name_fr'] ?? ''),
            'tr' => (string)($a['category_name_tr'] ?? ''),
        ];
        $language = strtolower((string)($a['language'] ?? ''));
        $localizedCategoryName = $categoryTranslations[$language] ?? '';
        if ($localizedCategoryName === '') {
            $localizedCategoryName = $categoryTranslations['ar'] ?: (string)($a['category'] ?? '');
        }
        if (empty($imageUrl) || str_contains($imageUrl, 'bing.com/images/search')) {
            $seed = crc32($a['id'] ?? $a['title']);
            $imageUrl = "https://placehold.co/600x400/EEE/31343C?text=" . urlencode($a['category'] ?? 'news') . "+$seed";
        }
        return [
            'id' => $a['id'],
            'title' => $a['title'],
            'summary' => $a['summary'],
            'content' => $a['content'],
            'language' => $a['language'],
            'category' => $a['category'],
            'categoryName' => $localizedCategoryName,
            'categoryNameAr' => $categoryTranslations['ar'],
            'categoryNameEn' => $a['category_name_en'],
            'categoryNameFr' => $a['category_name_fr'],
            'categoryNameTr' => $a['category_name_tr'],
            'categoryTranslations' => $categoryTranslations,
            'source' => [
                'name' => $a['source_id'],
                'url' => $a['source_url'],
                'score' => 0.0
            ],
            'sourceUrl' => $a['source_url_article'],
            'imageUrl' => $imageUrl,
            'viewsCount' => intval($a['views_count'] ?? 0),
            'publishedAt' => intval($a['published_at']),
            'status' => $a['status']
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
    error_log('List articles error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch articles'], 500);
}
?>
