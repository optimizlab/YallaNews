<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(3600);

try {
    $db = Database::getInstance();

    $sql = "SELECT id, name, url, category, country, language, status, score, last_crawled 
            FROM yn_sources 
            WHERE status = 'published' 
            ORDER BY score DESC";
    $stmt = $db->query($sql);
    $sources = $stmt->fetchAll();

    $formatted = array_map(function($s) {
        return [
            'id' => $s['id'],
            'name' => $s['name'],
            'url' => $s['url'],
            'category' => $s['category'],
            'country' => $s['country'],
            'language' => $s['language'],
            'status' => $s['status'],
            'score' => floatval($s['score']),
            'lastCrawled' => $s['last_crawled'] ? intval($s['last_crawled']) : null
        ];
    }, $sources);

    json_response([
        'success' => true,
        'sources' => $formatted
    ]);

} catch (Exception $e) {
    error_log('List sources error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch sources'], 500);
}
?>
