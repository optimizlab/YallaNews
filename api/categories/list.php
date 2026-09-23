<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(3600);

try {
    $db = Database::getInstance();

    $sql = "SELECT id, name, name_en, sort_order, active FROM yn_categories WHERE active = 1 ORDER BY sort_order ASC";
    $stmt = $db->query($sql);
    $categories = $stmt->fetchAll();

    $formatted = array_map(function($c) {
        return [
            'id' => $c['id'],
            'name' => $c['name'],
            'nameEn' => $c['name_en'],
            'sortOrder' => intval($c['sort_order']),
            'active' => (bool) $c['active']
        ];
    }, $categories);

    json_response([
        'success' => true,
        'categories' => $formatted
    ]);

} catch (Exception $e) {
    error_log('List categories error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch categories'], 500);
}
?>
