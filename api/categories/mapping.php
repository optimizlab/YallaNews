<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/category_helpers.php';

no_cache_headers();

try {
    $db = Database::getInstance();
    $categoryColumns = category_table_columns($db);
    $selectColumns = category_select_columns($categoryColumns);
    $where = isset($categoryColumns['active']) ? ' WHERE active = 1' : '';
    $stmt = $db->query(
        'SELECT ' . implode(', ', $selectColumns) . ' FROM yn_categories' . $where
    );
    $mapping = [];

    foreach ($stmt->fetchAll() as $category) {
        $formatted = format_category($category);
        $id = (string)$category['id'];
        $mapping[strtoupper($id)] = $id;
        foreach ($formatted['translations'] as $name) {
            $name = trim($name);
            if ($name !== '') {
                $mapping[strtoupper($name)] = $id;
            }
        }
    }

    json_response([
        'success' => true,
        'mapping' => $mapping,
    ]);
} catch (Exception $e) {
    error_log('Category mapping error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch category mapping'], 500);
}
