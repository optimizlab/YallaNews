<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../categories/category_helpers.php';

require_get();

$id = sanitize_string($_GET['id'] ?? '', 64);
$all = isset($_GET['all']) && $_GET['all'] == '1';

if (empty($id)) {
    json_response(['error' => 'Missing source id'], 400);
}

try {
    $db = Database::getInstance();
    $categoryColumns = category_table_columns($db);
    $categorySelect = implode(', ', category_join_translation_select($categoryColumns));

    $sql = "SELECT s.id, s.name, s.url, s.category, s.country, s.language,
                   s.status, s.score, s.last_crawled,
                   $categorySelect
            FROM yn_sources s
            LEFT JOIN yn_categories c ON s.category = c.id
            WHERE s.id = ?";
    $params = [$id];

    if (!$all) {
        $sql .= " AND s.status = 'published'";
    }

    $stmt = $db->getPDO()->prepare($sql);
    $stmt->execute($params);
    $source = $stmt->fetch();

    if (!$source) {
        json_response(['error' => 'Source not found'], 404);
    }

    json_response([
        'success' => true,
        'source' => [
            'id' => $source['id'],
            'name' => $source['name'],
            'url' => $source['url'],
            'category' => $source['category'],
            'categoryName' => $source['category_name'] ?? '',
            'categoryNameEn' => $source['category_name_en'] ?? '',
            'categoryNameFr' => $source['category_name_fr'] ?? '',
            'categoryNameTr' => $source['category_name_tr'] ?? '',
            'categoryTranslations' => [
                'ar' => $source['category_name'] ?? '',
                'en' => $source['category_name_en'] ?? '',
                'fr' => $source['category_name_fr'] ?? '',
                'tr' => $source['category_name_tr'] ?? '',
            ],
            'country' => $source['country'],
            'language' => $source['language'],
            'status' => $source['status'],
            'score' => floatval($source['score']),
            'lastCrawled' => $source['last_crawled'] ? intval($source['last_crawled']) : null
        ]
    ]);

} catch (Exception $e) {
    error_log('Get source error: ' . $e->getMessage());
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => 'Failed to fetch source',
        'details' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ]);
}
?>
