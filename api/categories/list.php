<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

try {
    $db = Database::getInstance();

    $all = isset($_GET['all']) && $_GET['all'] == '1';
    $sql = $all 
        ? "SELECT id, name, name_en, sort_order, active FROM yn_categories ORDER BY sort_order ASC, name ASC"
        : "SELECT id, name, name_en, sort_order, active FROM yn_categories WHERE active = 1 ORDER BY sort_order ASC, name ASC";

    $stmt = $db->query($sql);
    $categories = $stmt->fetchAll();

    $formatted = array_map(function($c) {
        return [
            'id' => $c['id'],
            'name' => $c['name'],
            'nameEn' => $c['name_en'] ?? $c['name'],
            'sortOrder' => intval($c['sort_order'] ?? 0),
            'active' => (bool) $c['active']
        ];
    }, $categories);

    json_response([
        'success' => true,
        'categories' => $formatted,
        'count' => count($formatted)
    ]);

} catch (Exception $e) {
    error_log('List categories error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch categories'], 500);
}
?>
