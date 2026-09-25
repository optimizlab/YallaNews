<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();

$input = get_json_input();
$url = sanitize_string($input['url'] ?? '', 512);
$id = sanitize_string($input['id'] ?? '', 64);
$lastCrawled = isset($input['last_crawled']) ? intval($input['last_crawled']) : time();

if (empty($url) && empty($id)) {
    json_response(['error' => 'Missing source url or id'], 400);
}

try {
    $db = Database::getInstance();

    if (!empty($id)) {
        $stmt = $db->prepare("UPDATE yn_sources SET last_crawled = :last WHERE id = :id");
        $stmt->execute([
            ':last' => $lastCrawled,
            ':id' => $id,
        ]);
    } else {
        $stmt = $db->prepare("UPDATE yn_sources SET last_crawled = :last WHERE url = :url");
        $stmt->execute([
            ':last' => $lastCrawled,
            ':url' => $url,
        ]);
    }

    json_response(['success' => true]);
} catch (Exception $e) {
    error_log('Update crawl time error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update crawl time'], 500);
}
