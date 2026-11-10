<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/news_schema.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing article id'], 400);
}

try {
    $db = Database::getInstance();

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

    $newsColumns = array_fill_keys($existingCols, true);
    if (isset($data['source_name']) || isset($data['source_id'])) {
        $sourceName = sanitize_string($data['source_name'] ?? $data['source_id'], 255);
        $sourceUrl = filter_var(
            sanitize_string($data['source_url'] ?? '', 512),
            FILTER_SANITIZE_URL
        );
        [$sourceColumn, $sourceValue] = news_source_write_value(
            $db,
            $newsColumns,
            $sourceName,
            $sourceUrl
        );
        if ($sourceColumn !== null) {
            unset($data['source_name'], $data['source_id']);
            $data[$sourceColumn] = $sourceValue;
        }
    }
    if (isset($data['sourceUrl']) && !isset($data['source_url_article'])) {
        $data['source_url_article'] = $data['sourceUrl'];
    }
    if (isset($data['imageUrl']) && !isset($data['image_url'])) {
        $data['image_url'] = $data['imageUrl'];
    }

    if (isset($data['category'])) {
        $category = sanitize_string($data['category'], 64);
        $categoryExists = $db->query(
            'SELECT id FROM yn_categories WHERE id = ? LIMIT 1',
            [$category]
        )->fetch();
        if (!$categoryExists) {
            json_response(['error' => 'Category does not exist'], 400);
        }
        $data['category'] = $category;
    }

    $allowedFields = [
        'title', 'summary', 'content', 'language', 'category',
        'source_id', 'source_name', 'source_url', 'source_score',
        'source_url_article', 'image_url', 'published_at', 'status',
    ];
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
    $updatedAt = in_array('updated_at', $existingCols) ? ', updated_at = NOW()' : '';
    $sql = "UPDATE yn_news SET " . implode(', ', $updates) . $updatedAt . " WHERE id = ?";
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
