<?php
declare(strict_types=1);

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

    // Defensive: check if category column/table exist before querying
    $categoryColumns = [];
    try {
        $categoryColumns = category_table_columns($db);
    } catch (Exception $e) {
        error_log('category_table_columns failed: ' . $e->getMessage());
    }

    $formattedCategory = null;
    if (!empty($categoryColumns)) {
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
    }

    // Build insert columns defensively based on what exists in yn_sources
    $sourceColumns = [];
    try {
        $cols = $db->query('SHOW COLUMNS FROM yn_sources')->fetchAll(PDO::FETCH_COLUMN, 0);
        $sourceColumns = array_fill_keys($cols, true);
    } catch (Exception $e) {
        error_log('SHOW COLUMNS yn_sources failed: ' . $e->getMessage());
    }

    $insert = [
        'id' => $id,
        'name' => $name,
        'url' => $url,
        'category' => $category,
        'status' => $status,
        'score' => $score,
    ];
    if (isset($sourceColumns['country'])) $insert['country'] = $country;
    if (isset($sourceColumns['language'])) $insert['language'] = $language;
    if (isset($sourceColumns['last_crawled'])) $insert['last_crawled'] = null;

    $insertColumns = array_keys($insert);
    $placeholders = array_fill(0, count($insertColumns), '?');
    $db->query(
        'INSERT INTO yn_sources (' . implode(', ', $insertColumns) . ') VALUES (' . implode(', ', $placeholders) . ')',
        array_values($insert)
    );

    json_response([
        'success' => true,
        'message' => 'Source created successfully',
        'source' => [
            'id' => $id,
            'name' => $name,
            'url' => $url,
            'category' => $category,
            'categoryName' => $formattedCategory ? $formattedCategory['name'] : $category,
            'categoryNameEn' => $formattedCategory ? $formattedCategory['nameEn'] : '',
            'categoryNameFr' => $formattedCategory ? $formattedCategory['nameFr'] : '',
            'categoryNameTr' => $formattedCategory ? $formattedCategory['nameTr'] : '',
            'categoryTranslations' => $formattedCategory ? $formattedCategory['translations'] : [],
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
