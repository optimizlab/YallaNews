<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_admin();
no_cache_headers();

$id = sanitize_string($_GET['id'] ?? $_POST['id'] ?? '', 64);
if (empty($id)) {
    $data = get_json_input();
    $id = sanitize_string($data['id'] ?? '', 64);
}

if (empty($id)) {
    json_response(['error' => 'Missing category id'], 400);
}

try {
    $db = Database::getInstance();

    $countStmt = $db->query(
        'SELECT
            (SELECT COUNT(*) FROM yn_news WHERE category = ?) AS news_count,
            (SELECT COUNT(*) FROM yn_sources WHERE category = ?) AS source_count',
        [$id, $id]
    );
    $usage = $countStmt->fetch();
    $newsCount = intval($usage['news_count'] ?? 0);
    $sourceCount = intval($usage['source_count'] ?? 0);

    if ($newsCount > 0 || $sourceCount > 0) {
        $db->query("UPDATE yn_categories SET active = 0 WHERE id = ?", [$id]);
        json_response([
            'success' => true,
            'message' => "Category is used by $newsCount articles and $sourceCount sources; marked inactive",
            'softDeleted' => true
        ]);
        return;
    }

    $db->query("DELETE FROM yn_categories WHERE id = ?", [$id]);

    json_response([
        'success' => true,
        'message' => 'Category deleted successfully'
    ]);
} catch (Exception $e) {
    error_log('Delete category error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete category'], 500);
}
?>
