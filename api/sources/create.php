<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/../categories/category_helpers.php';

require_post();
no_cache_headers();
require_admin();

$data = get_json_input();
$id = strtolower(trim(sanitize_string($data['id'] ?? '', 64)));
$name = sanitize_string($data['name'] ?? '', 255);
$url = filter_var(sanitize_string($data['url'] ?? '', 512), FILTER_SANITIZE_URL);
$category = sanitize_string($data['category'] ?? 'general', 64);
$country = sanitize_string($data['country'] ?? null, 2);
$language = sanitize_string($data['language'] ?? 'ar', 8);
$status = in_array($data['status'] ?? 'published', ['published', 'draft', 'archived']) ? $data['status'] : 'published';
$score = isset($data['score']) ? max(0.00, min(0.99, round(floatval($data['score']), 2))) : 0.00;

if (empty($id) || empty($name) || empty($url)) {
    json_response(['error' => 'Missing source id, name or url'], 400);
}

// Convert id to slug format
$id = preg_replace('/[^a-z0-9_-]/', '', str_replace(' ', '-', $id));

if (empty($id)) {
    json_response(['error' => 'Invalid source id'], 400);
}

try {
    $db = Database::getInstance();

    $exists = $db->query("SELECT id FROM yn_sources WHERE id = ? LIMIT 1", [$id])->fetch();
    if ($exists) {
        json_response(['error' => 'Source ID already exists'], 409);
    }

    $categoryColumns = category_table_columns($db);
    $categorySelect = category_select_columns($categoryColumns);
    $categoryWhere = isset($categoryColumns['active'])
        ? ' WHERE id = ? AND active = 1 LIMIT 1'
        : ' WHERE id = ? LIMIT 1';
    $categoryRow = $db->query(
        'SELECT ' . implode(', ', $categorySelect) . ' FROM yn_categories' . $categoryWhere,
        [$category]
    )->fetch();
    if (!$categoryRow) {
        json_response(['error' => 'Category does not exist or is inactive'], 400);
    }
    $formattedCategory = format_category($categoryRow);

    $db->query(
        "INSERT INTO yn_sources (id, name, url, category, country, language, status, score) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [$id, $name, $url, $category, $country, $language, $status, $score]
    );

    json_response([
        'success' => true,
        'message' => 'Source created successfully',
        'source' => [
            'id' => $id,
            'name' => $name,
            'url' => $url,
            'category' => $category,
            'categoryName' => $formattedCategory['name'],
            'categoryNameEn' => $formattedCategory['nameEn'],
            'categoryNameFr' => $formattedCategory['nameFr'],
            'categoryNameTr' => $formattedCategory['nameTr'],
            'categoryTranslations' => $formattedCategory['translations'],
            'country' => $country,
            'language' => $language,
            'status' => $status,
            'score' => $score,
            'lastCrawled' => null
        ]
    ], 201);
} catch (Exception $e) {
    error_log('Create source error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create source', 'details' => $e->getMessage()], 500);
}
?>
