<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/category_helpers.php';

require_post();
require_admin();
no_cache_headers();

$data = get_json_input();
$id = sanitize_string($data['id'] ?? '', 64);
$names = category_names_from_input($data);
$sortOrder = isset($data['sortOrder']) || isset($data['sort_order'])
    ? intval($data['sortOrder'] ?? $data['sort_order'])
    : null;
$active = isset($data['active']) ? (intval($data['active']) ? 1 : 0) : null;

if ($id === '') {
    json_response(['error' => 'Missing category id'], 400);
}

$translationsInput = $data['translations'] ?? $data['name_translation'] ?? [];
$languageMap = [
    'name' => 'ar',
    'name_en' => 'en',
    'name_fr' => 'fr',
    'name_tr' => 'tr',
];
$providedColumns = [];
foreach ($languageMap as $column => $lang) {
    $provided = false;
    if (is_array($translationsInput) && array_key_exists($lang, $translationsInput)) {
        $provided = true;
    } else {
        $keys = ['name' => ['name', 'nameAr', 'name_ar'], 'name_en' => ['nameEn', 'name_en'], 'name_fr' => ['nameFr', 'name_fr'], 'name_tr' => ['nameTr', 'name_tr']][$column];
        foreach ($keys as $key) {
            if (array_key_exists($key, $data)) {
                $provided = true;
                break;
            }
        }
    }
    if ($provided) {
        $providedColumns[$column] = $names[$column];
    }
}

foreach ($providedColumns as $column => $value) {
    if (empty($value)) {
        json_response([
            'error' => 'Category translation cannot be empty',
            'field' => $column,
        ], 400);
    }
}

try {
    $db = Database::getInstance();
    $categoryColumns = category_table_columns($db);
    if (!isset($categoryColumns['name_translation'])
        && (!isset($categoryColumns['name_en']) || !isset($categoryColumns['name_fr']) || !isset($categoryColumns['name_tr']))) {
        throw new RuntimeException('Category table has no complete translation columns');
    }

    $selectColumns = category_select_columns($categoryColumns);
    $exists = $db->query(
        'SELECT ' . implode(', ', $selectColumns) . ' FROM yn_categories WHERE id = ? LIMIT 1',
        [$id]
    )->fetch();
    if (!$exists) {
        json_response(['error' => 'Category not found'], 404);
    }

    $merged = [];
    $raw = $exists['name_translation'] ?? null;
    if (is_string($raw) && $raw !== '') {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            $merged = $decoded;
        }
    }
    foreach (['ar' => 'name', 'en' => 'name_en', 'fr' => 'name_fr', 'tr' => 'name_tr'] as $language => $column) {
        if (!empty($exists[$column])) {
            $merged[$language] = $exists[$column];
        }
    }
    if (!empty($providedColumns['name'])) {
        $merged['ar'] = $providedColumns['name'];
    }
    if (!empty($providedColumns['name_en'])) {
        $merged['en'] = $providedColumns['name_en'];
    }
    if (!empty($providedColumns['name_fr'])) {
        $merged['fr'] = $providedColumns['name_fr'];
    }
    if (!empty($providedColumns['name_tr'])) {
        $merged['tr'] = $providedColumns['name_tr'];
    }

    $updates = [];
    $params = [];
    if (!empty($providedColumns['name']) && isset($categoryColumns['name'])) {
        $updates[] = 'name = ?';
        $params[] = $providedColumns['name'];
    }
    foreach (['name_en', 'name_fr', 'name_tr'] as $column) {
        if (!empty($providedColumns[$column]) && isset($categoryColumns[$column])) {
            $updates[] = "$column = ?";
            $params[] = $providedColumns[$column];
        }
    }
    if ($providedColumns && isset($categoryColumns['name_translation'])) {
        $updates[] = 'name_translation = ?';
        $params[] = json_encode($merged, JSON_UNESCAPED_UNICODE);
    }
    if ($sortOrder !== null && isset($categoryColumns['sort_order'])) {
        $updates[] = 'sort_order = ?';
        $params[] = $sortOrder;
    }
    if ($active !== null && isset($categoryColumns['active'])) {
        $updates[] = 'active = ?';
        $params[] = $active;
    }

    if ($updates) {
        $params[] = $id;
        $db->query(
            'UPDATE yn_categories SET ' . implode(', ', $updates) . ' WHERE id = ?',
            $params
        );
    } elseif ($providedColumns || $sortOrder !== null || $active !== null) {
        json_response(['error' => 'Category schema does not support the requested fields'], 400);
    }

    $category = $db->query(
        'SELECT ' . implode(', ', $selectColumns) . ' FROM yn_categories WHERE id = ?',
        [$id]
    )->fetch();

    json_response([
        'success' => true,
        'message' => 'Category updated successfully',
        'category' => format_category($category),
    ]);
} catch (Exception $e) {
    error_log('Update category error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update category'], 500);
}
