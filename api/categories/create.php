<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
no_cache_headers();

$data = get_json_input();
$id = strtolower(trim(sanitize_string($data['id'] ?? '', 64)));
$name = sanitize_string($data['name'] ?? '', 128);
$nameEn = sanitize_string($data['nameEn'] ?? $data['name_en'] ?? $name, 128);
$sortOrder = intval($data['sortOrder'] ?? $data['sort_order'] ?? 0);
$active = isset($data['active']) ? (intval($data['active']) ? 1 : 0) : 1;

if (empty($id) || empty($name)) {
    json_response(['error' => 'Missing category id or name'], 400);
}

// Convert id to slug format
$id = preg_replace('/[^a-z0-9_-]/', '', str_replace(' ', '-', $id));

try {
    $db = Database::getInstance();

    $exists = $db->query("SELECT id FROM yn_categories WHERE id = ? LIMIT 1", [$id])->fetch();
    if ($exists) {
        json_response(['error' => 'Category ID already exists'], 409);
    }

    $db->query(
        "INSERT INTO yn_categories (id, name, name_en, sort_order, active) VALUES (?, ?, ?, ?, ?)",
        [$id, $name, $nameEn, $sortOrder, $active]
    );

    json_response([
        'success' => true,
        'message' => 'Category created successfully',
        'category' => [
            'id' => $id,
            'name' => $name,
            'nameEn' => $nameEn,
            'sortOrder' => $sortOrder,
            'active' => (bool)$active
        ]
    ]);
} catch (Exception $e) {
    error_log('Create category error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create category', 'details' => $e->getMessage()], 500);
}
?>
