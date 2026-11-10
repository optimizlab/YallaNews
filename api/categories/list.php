<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/category_helpers.php';

no_cache_headers();

try {
    $db = Database::getInstance();
    $all = ($_GET['all'] ?? '') === '1';

    $categoryColumns = category_table_columns($db);
    $selectCols = category_select_columns($categoryColumns);

    $sql = 'SELECT ' . implode(', ', array_unique($selectCols)) . ' FROM yn_categories';
    if (!$all && isset($categoryColumns['active'])) {
        $sql .= ' WHERE active = 1';
    }
    $sql .= isset($categoryColumns['sort_order'])
        ? ' ORDER BY sort_order ASC, name ASC'
        : ' ORDER BY name ASC';

    $categories = $db->query($sql)->fetchAll();
    $formatted = array_map('format_category', $categories);

    json_response([
        'success' => true,
        'categories' => $formatted,
        'count' => count($formatted),
    ]);
} catch (Exception $e) {
    error_log('List categories error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch categories'], 500);
}
