<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
no_cache_headers();
require_admin();

$data = get_json_input();
$id = sanitize_string($data['id'] ?? '', 64);
$name = sanitize_string($data['name'] ?? '', 255);
$url = filter_var(sanitize_string($data['url'] ?? '', 512), FILTER_SANITIZE_URL);
$category = sanitize_string($data['category'] ?? null, 64);
$country = sanitize_string($data['country'] ?? null, 2);
$language = sanitize_string($data['language'] ?? null, 8);
$status = isset($data['status']) && in_array($data['status'], ['published', 'draft', 'archived']) ? $data['status'] : null;
$score = isset($data['score']) ? max(0.00, min(0.99, round(floatval($data['score']), 2))) : null;

if (empty($id)) {
    json_response(['error' => 'Missing source id'], 400);
}

try {
    $db = Database::getInstance();

    $currentSource = $db->query(
        'SELECT id, category FROM yn_sources WHERE id = ? LIMIT 1',
        [$id]
    )->fetch();
    if (!$currentSource) {
        json_response(['error' => 'Source not found'], 404);
    }

    $updates = [];
    $params = [];

    if (!empty($name)) {
        $updates[] = "name = ?";
        $params[] = $name;
    }
    if (!empty($url)) {
        $updates[] = "url = ?";
        $params[] = $url;
    }
    if ($category !== null) {
        if ($category === '') {
            json_response(['error' => 'Category is required'], 400);
        }
        if ($category !== $currentSource['category']) {
            $catExists = $db->query(
                'SELECT id FROM yn_categories WHERE id = ? AND active = 1 LIMIT 1',
                [$category]
            )->fetch();
            if (!$catExists) {
                json_response(['error' => 'Category does not exist or is inactive'], 400);
            }
        }
        $updates[] = "category = ?";
        $params[] = $category;
    }
    if ($country !== null) {
        $updates[] = "country = ?";
        $params[] = $country;
    }
    if ($language !== null) {
        $updates[] = "language = ?";
        $params[] = $language;
    }
    if ($status !== null) {
        $updates[] = "status = ?";
        $params[] = $status;
    }
    if ($score !== null) {
        $updates[] = "score = ?";
        $params[] = $score;
    }

    if (!empty($updates)) {
        $params[] = $id;
        $sql = "UPDATE yn_sources SET " . implode(', ', $updates) . " WHERE id = ?";
        $db->query($sql, $params);
    }

    json_response([
        'success' => true,
        'message' => 'Source updated successfully'
    ]);
} catch (Exception $e) {
    error_log('Update source error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update source', 'details' => $e->getMessage()], 500);
}
?>
