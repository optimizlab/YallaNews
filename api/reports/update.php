<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
require_admin();

$data = get_json_input();

$id = sanitize_string($data['id'] ?? '', 64);
$status = sanitize_string($data['status'] ?? '', 32);

validate_required([
    'id' => $id,
    'status' => $status,
]);

if (!in_array($status, ['pending', 'reviewed', 'dismissed', 'resolved'], true)) {
    json_response(['error' => 'Invalid status'], 400);
}

try {
    $db = Database::getInstance();

    $existing = $db->query('SELECT id FROM yn_news_reports WHERE id = ? LIMIT 1', [$id])->fetch();
    if (!$existing) {
        json_response(['error' => 'Report not found'], 404);
    }

    $db->query(
        'UPDATE yn_news_reports SET status = ? WHERE id = ?',
        [$status, $id]
    );

    json_response([
        'success' => true,
        'message' => 'Report status updated',
    ]);

} catch (Exception $e) {
    error_log('Update report error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update report'], 500);
}
?>
