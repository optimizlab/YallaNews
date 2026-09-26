<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(3600);

try {
    $db = Database::getInstance();

    $countryCode = $_GET['country_code'] ?? null;
    $language = $_GET['language'] ?? null;
    $lastVisited = $_GET['last_visited'] ?? null;
    $fields = $_GET['fields'] ?? 'full';

    $sql = "SELECT id, name, url, category, country, language, status, score, last_crawled 
            FROM yn_sources 
            WHERE status = 'published'";
    
    $params = [];
    
    if ($countryCode) {
        $sql .= " AND country = :country_code";
        $params[':country_code'] = $countryCode;
    }
    
    if ($language) {
        $sql .= " AND language = :language";
        $params[':language'] = $language;
    }
    
    if ($lastVisited) {
        $sql .= " AND (last_crawled IS NULL OR last_crawled < :last_visited)";
        $params[':last_visited'] = intval($lastVisited);
    }
    
    $sql .= " ORDER BY score DESC";
    $stmt = $db->getPDO()->prepare($sql);
    $stmt->execute($params);
    $sources = $stmt->fetchAll();

    if ($fields === 'urls') {
        $urls = array_map(function($s) {
            return $s['url'];
        }, $sources);
        
        json_response([
            'success' => true,
            'urls' => $urls
        ]);
    } else {
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
    }

} catch (Exception $e) {
    error_log('List sources error: ' . $e->getMessage());
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => 'Failed to fetch sources',
        'details' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ]);
}
?>
