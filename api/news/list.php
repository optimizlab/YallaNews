<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(60);

list($page, $limit, $offset) = get_pagination_params();

$category = sanitize_string($_GET['category'] ?? '', 64);
$language = sanitize_string($_GET['language'] ?? '', 8);
$search = sanitize_string($_GET['search'] ?? '', 200);
$sortBy = in_array($_GET['sort'] ?? 'published_at', ['published_at', 'created_at', 'title']) ? ($_GET['sort'] ?? 'published_at') : 'published_at';
$sortOrder = in_array(strtoupper($_GET['order'] ?? 'DESC'), ['ASC', 'DESC']) ? strtoupper($_GET['order']) : 'DESC';

try {
    $db = Database::getInstance();

    $where = ["n.status = 'published'"];
    $params = [];

    if ($category) {
        $where[] = "n.category = ?";
        $params[] = $category;
    }

    if ($language) {
        $where[] = "n.language = ?";
        $params[] = $language;
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
                   n.source_id, n.source_url_article, 
                   n.image_url, n.published_at, n.status,
                   c.name as category_name, c.name_en as category_name_en
             FROM yn_news n
             LEFT JOIN yn_categories c ON n.category = c.id
             WHERE $whereClause
             ORDER BY n.$sortBy $sortOrder
             LIMIT ? OFFSET ?";

    $params[] = $limit;
    $params[] = $offset;
    $stmt = $db->query($sql, $params);
    $articles = $stmt->fetchAll();

    $formatted = array_map(function($a) {
        $imageUrl = $a['image_url'];
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
            'categoryName' => $a['category_name'],
            'categoryNameEn' => $a['category_name_en'],
            'source' => [
                'name' => $a['source_id'],
                'url' => '',
                'score' => 0.0
            ],
            'sourceUrl' => $a['source_url_article'],
            'imageUrl' => $imageUrl,
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
