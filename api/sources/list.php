<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../categories/category_helpers.php';

$all = isset($_GET['all']) && $_GET['all'] == '1';

cache_headers($all ? 60 : 3600);

try {
    $db = Database::getInstance();
    $categoryColumns = category_table_columns($db);
    $categorySelect = implode(', ', category_join_translation_select($categoryColumns));

    $countryCode = $_GET['country_code'] ?? $_GET['country'] ?? null;
    $language = $_GET['language'] ?? null;
    $status = $_GET['status'] ?? null;
    $search = $_GET['search'] ?? null;
    $lastVisited = $_GET['last_visited'] ?? null;
    $fields = $_GET['fields'] ?? 'full';

    [$page, $limit, $offset] = get_pagination_params();

    $sql = "SELECT s.id, s.name, s.url, s.category, s.country, s.language,
                   s.status, s.score, s.last_crawled,
                   $categorySelect
            FROM yn_sources s
            LEFT JOIN yn_categories c ON s.category = c.id";
    $params = [];
    $where = [];

    if (!$all) {
        $where[] = "s.status = 'published'";
    }

    if ($countryCode) {
        $where[] = "s.country = :country";
        $params[':country'] = $countryCode;
    }

    if ($language) {
        $where[] = "s.language = :language";
        $params[':language'] = $language;
    }

    if ($status) {
        $where[] = "s.status = :status";
        $params[':status'] = $status;
    }

    if ($search) {
        $where[] = "(s.name LIKE :search OR s.url LIKE :search)";
        $params[':search'] = '%' . $search . '%';
    }

    if ($lastVisited) {
        $where[] = "(s.last_crawled IS NULL OR s.last_crawled < :last_visited)";
        $params[':last_visited'] = intval($lastVisited);
    }

    if (!empty($where)) {
        $sql .= " WHERE " . implode(' AND ', $where);
    }

    // Count total
    $countSql = "SELECT COUNT(*) as cnt FROM (" . $sql . ") as t";
    $countStmt = $db->getPDO()->prepare($countSql);
    $countStmt->execute($params);
    $total = intval($countStmt->fetch()['cnt'] ?? 0);

    $sql .= " ORDER BY s.score DESC, s.name ASC LIMIT :limit OFFSET :offset";
    $stmt = $db->getPDO()->prepare($sql);
    foreach ($params as $key => $val) {
        $stmt->bindValue($key, $val);
    }
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
    $stmt->execute();
    $sources = $stmt->fetchAll();

    if ($fields === 'urls') {
        $urls = array_map(function($s) {
            return $s['url'];
        }, $sources);

        json_response([
            'success' => true,
            'urls' => $urls,
            'count' => count($urls)
        ]);
    } else {
        $formatted = array_map(function($s) {
            return [
                'id' => $s['id'],
                'name' => $s['name'],
                'url' => $s['url'],
                'category' => $s['category'],
                'categoryName' => $s['category_name'] ?? '',
                'categoryNameEn' => $s['category_name_en'] ?? '',
                'categoryNameFr' => $s['category_name_fr'] ?? '',
                'categoryNameTr' => $s['category_name_tr'] ?? '',
                'categoryTranslations' => [
                    'ar' => $s['category_name'] ?? '',
                    'en' => $s['category_name_en'] ?? '',
                    'fr' => $s['category_name_fr'] ?? '',
                    'tr' => $s['category_name_tr'] ?? '',
                ],
                'country' => $s['country'],
                'language' => $s['language'],
                'status' => $s['status'],
                'score' => floatval($s['score']),
                'lastCrawled' => $s['last_crawled'] ? intval($s['last_crawled']) : null
            ];
        }, $sources);

        json_response([
            'success' => true,
            'sources' => $formatted,
            'count' => count($formatted),
            'total' => $total,
            'page' => $page,
            'limit' => $limit
        ]);
    }

} catch (Exception $e) {
    error_log('List sources error: ' . $e->getMessage());
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => 'Failed to fetch sources',
        'details' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ]);
}
?>
