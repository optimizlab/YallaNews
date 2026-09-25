<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();

$input = get_json_input();
$url = sanitize_string($input['url'] ?? '', 512);
$id = sanitize_string($input['id'] ?? '', 64);
$score = isset($input['score']) ? floatval($input['score']) : null;

if (empty($url) && empty($id)) {
    json_response(['error' => 'Missing source url or id'], 400);
}

if ($score === null) {
    json_response(['error' => 'Missing score'], 400);
}

$score = max(0.00, min(0.99, round($score, 2)));

try {
    $db = Database::getInstance();

    if (!empty($id)) {
        $stmt = $db->prepare("UPDATE yn_sources SET score = :score WHERE id = :id");
        $stmt->execute([':score' => $score, ':id' => $id]);
    } else {
        $stmt = $db->prepare("UPDATE yn_sources SET score = :score WHERE url = :url");
        $stmt->execute([':score' => $score, ':url' => $url]);
    }

    json_response(['success' => true]);
} catch (Exception $e) {
    error_log('Update source score error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update source score'], 500);
}
