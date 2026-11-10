<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/category_helpers.php';

require_post();
require_admin();
no_cache_headers();

$data = get_json_input();
$id = strtolower(trim(sanitize_string($data['id'] ?? '', 64)));
$id = preg_replace('/[^a-z0-9_-]/', '', str_replace(' ', '-', $id));
$names = category_names_from_input($data);
$sortOrder = intval($data['sortOrder'] ?? $data['sort_order'] ?? 0);
$active = isset($data['active']) ? (intval($data['active']) ? 1 : 0) : 1;

if ($id === '') {
    json_response(['error' => 'Missing or invalid category id'], 400);
}
require_category_names($names);

$translations = [
    'ar' => $names['name'],
    'en' => $names['name_en'],
    'fr' => $names['name_fr'],
    'tr' => $names['name_tr'],
];

try {
    $db = Database::getInstance();
    $categoryColumns = category_table_columns($db);
    if (!isset($categoryColumns['name_translation'])
        && (!isset($categoryColumns['name_en']) || !isset($categoryColumns['name_fr']) || !isset($categoryColumns['name_tr']))) {
        throw new RuntimeException('Category table has no complete translation columns');
    }

    $exists = $db->query(
        'SELECT id FROM yn_categories WHERE id = ? LIMIT 1',
        [$id]
    )->fetch();
    if ($exists) {
        json_response(['error' => 'Category ID already exists'], 409);
    }

    $insert = [
        'id' => $id,
        'name' => $names['name'],
    ];
    if (isset($categoryColumns['name_translation'])) {
        $insert['name_translation'] = json_encode($translations, JSON_UNESCAPED_UNICODE);
    }
    foreach (['name_en', 'name_fr', 'name_tr'] as $column) {
        if (isset($categoryColumns[$column])) {
            $insert[$column] = $names[$column];
        }
    }
    if (isset($categoryColumns['sort_order'])) {
        $insert['sort_order'] = $sortOrder;
    }
    if (isset($categoryColumns['active'])) {
        $insert['active'] = $active;
    }
    $insertColumns = array_keys($insert);
    $placeholders = array_fill(0, count($insertColumns), '?');
    $db->query(
        'INSERT INTO yn_categories (' . implode(', ', $insertColumns) . ') VALUES (' . implode(', ', $placeholders) . ')',
        array_values($insert)
    );

    $selectColumns = category_select_columns($categoryColumns);
    $category = $db->query(
        'SELECT ' . implode(', ', $selectColumns) . ' FROM yn_categories WHERE id = ?',
        [$id]
    )->fetch();

    json_response([
        'success' => true,
        'message' => 'Category created successfully',
        'category' => format_category($category),
    ], 201);
} catch (Exception $e) {
    error_log('Create category error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create category'], 500);
}
