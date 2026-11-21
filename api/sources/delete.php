<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();
require_admin();

$id = sanitize_string($_GET['id'] ?? $_POST['id'] ?? '', 64);
if (empty($id)) {
    $data = get_json_input();
    $id = sanitize_string($data['id'] ?? '', 64);
}

if (empty($id)) {
    json_response(['error' => 'Missing source id'], 400);
}

try {
    $db = Database::getInstance();

    $source = $db->query(
        'SELECT name, url FROM yn_sources WHERE id = ? LIMIT 1',
        [$id]
    )->fetch();

    $newsColumns = [];
    try {
        $cols = $db->query('SHOW COLUMNS FROM yn_news')->fetchAll(PDO::FETCH_COLUMN, 0);
        $newsColumns = array_fill_keys($cols, true);
    } catch (Exception $e) {
        error_log('SHOW COLUMNS yn_news failed: ' . $e->getMessage());
    }

    $conditions = [];
    $params = [];
    if (isset($newsColumns['source_id'])) {
        $conditions[] = 'source_id = ?';
        $params[] = $id;
    }
    if (isset($newsColumns['source_name']) && $source) {
        $conditions[] = 'source_name = ?';
        $params[] = $source['name'];
    }
    if (isset($newsColumns['source_url']) && $source) {
        $conditions[] = 'source_url = ?';
        $params[] = $source['url'];
    }
    $countStmt = $conditions
        ? $db->query('SELECT COUNT(*) AS count FROM yn_news WHERE ' . implode(' OR ', $conditions), $params)
        : null;
    $newsCount = 0;
    if ($countStmt) {
        $countRow = $countStmt->fetch();
        $newsCount = intval($countRow['count'] ?? 0);
    }

    if ($newsCount > 0) {
        $db->query("UPDATE yn_sources SET status = 'archived' WHERE id = ?", [$id]);
        json_response([
            'success' => true,
            'message' => "Source has $newsCount articles; archived instead of permanent deletion",
            'softDeleted' => true
        ]);
        return;
    }

    $db->query("DELETE FROM yn_sources WHERE id = ?", [$id]);

    json_response([
        'success' => true,
        'message' => 'Source deleted successfully'
    ]);
} catch (Exception $e) {
    error_log('Delete source error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete source', 'details' => $e->getMessage()], 500);
}
