<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
no_cache_headers();

$data = get_json_input();
$id = sanitize_string($data['id'] ?? '', 64);
$name = sanitize_string($data['name'] ?? '', 128);
$nameEn = sanitize_string($data['nameEn'] ?? $data['name_en'] ?? $name, 128);
$sortOrder = isset($data['sortOrder']) ? intval($data['sortOrder']) : null;
$active = isset($data['active']) ? (intval($data['active']) ? 1 : 0) : null;

if (empty($id)) {
    json_response(['error' => 'Missing category id'], 400);
}

try {
    $db = Database::getInstance();

    $exists = $db->query("SELECT id FROM yn_categories WHERE id = ? LIMIT 1", [$id])->fetch();
    if (!$exists) {
        json_response(['error' => 'Category not found'], 404);
    }

    $updates = [];
    $params = [];

    if (!empty($name)) {
        $updates[] = "name = ?";
        $params[] = $name;
    }
    if (!empty($nameEn)) {
        $updates[] = "name_en = ?";
        $params[] = $nameEn;
    }
    if ($sortOrder !== null) {
        $updates[] = "sort_order = ?";
        $params[] = $sortOrder;
    }
    if ($active !== null) {
        $updates[] = "active = ?";
        $params[] = $active;
    }

    if (!empty($updates)) {
        $params[] = $id;
        $sql = "UPDATE yn_categories SET " . implode(', ', $updates) . " WHERE id = ?";
        $db->query($sql, $params);
    }

    json_response([
        'success' => true,
        'message' => 'Category updated successfully'
    ]);
} catch (Exception $e) {
    error_log('Update category error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update category', 'details' => $e->getMessage()], 500);
}
?>
