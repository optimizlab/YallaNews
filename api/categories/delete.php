<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

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

    // Check if category has articles
    $countStmt = $db->query("SELECT COUNT(*) as count FROM yn_news WHERE category = ?", [$id]);
    $newsCount = intval($countStmt->fetch()['count'] ?? 0);

    if ($newsCount > 0) {
        // Soft delete / mark inactive if articles exist
        $db->query("UPDATE yn_categories SET active = 0 WHERE id = ?", [$id]);
        json_response([
            'success' => true,
            'message' => "Category has $newsCount articles; marked as inactive instead of permanent deletion",
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
    json_response(['error' => 'Failed to delete category', 'details' => $e->getMessage()], 500);
}
?>
