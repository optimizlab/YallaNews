<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing article id'], 400);
}

try {
    $db = Database::getInstance();

    $allowedFields = ['title', 'summary', 'content', 'language', 'category', 'source_name', 'source_url', 'source_score', 'source_url_article', 'image_url', 'published_at', 'status'];
    $updates = [];
    $params = [];

    $rawInput = file_get_contents('php://input');
    if (empty($rawInput)) {
        json_response(['error' => 'Empty request body'], 400);
    }
    $data = json_decode($rawInput, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        json_response(['error' => 'Invalid JSON'], 400);
    }

    // Detect existing columns in yn_news
    $colsStmt = $db->query("SHOW COLUMNS FROM yn_news");
    $existingCols = [];
    while ($colRow = $colsStmt->fetch(PDO::FETCH_ASSOC)) {
        $existingCols[] = $colRow['Field'];
    }

    $allowedFields = ['title', 'summary', 'content', 'language', 'category', 'source_id', 'source_name', 'source_url', 'source_score', 'source_url_article', 'image_url', 'published_at', 'status'];

    if (isset($data['source_id']) && !isset($data['source_name'])) {
        $data['source_name'] = $data['source_id'];
    }
    if (isset($data['source_name']) && !isset($data['source_id'])) {
        $data['source_id'] = $data['source_name'];
    }
    if (isset($data['sourceUrl']) && !isset($data['source_url_article'])) {
        $data['source_url_article'] = $data['sourceUrl'];
    }
    if (isset($data['imageUrl']) && !isset($data['image_url'])) {
        $data['image_url'] = $data['imageUrl'];
    }

    foreach ($allowedFields as $field) {
        if (isset($data[$field]) && in_array($field, $existingCols)) {
            $updates[] = "$field = ?";
            $params[] = $data[$field];
        }
    }

    if (empty($updates)) {
        json_response(['error' => 'No valid fields to update'], 400);
    }

    $params[] = $id;
    $sql = "UPDATE yn_news SET " . implode(', ', $updates) . ", updated_at = NOW() WHERE id = ?";
    $db->query($sql, $params);

    json_response([
        'success' => true,
        'message' => 'Article updated successfully'
    ]);

} catch (Exception $e) {
    error_log('Update article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update article'], 500);
}
?>
