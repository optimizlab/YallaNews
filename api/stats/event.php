<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

// Public ingestion endpoint for the Flutter app.
// Rate limit per IP: 120 requests / 60s (each request may carry many events)
check_rate_limit('analytics_event_' . md5(get_client_ip() . ($_SERVER['HTTP_USER_AGENT'] ?? '')), 120, 60);

try {
    $db = Database::getInstance();

    // Auto-create analytics events table
    $db->query("CREATE TABLE IF NOT EXISTS `yn_analytics_events` (
      `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      `event_type` VARCHAR(32) NOT NULL,
      `session_id` VARCHAR(64) NOT NULL,
      `user_id` VARCHAR(64) DEFAULT NULL,
      `device_os` VARCHAR(32) DEFAULT 'unknown',
      `app_version` VARCHAR(16) DEFAULT '1.0.0',
      `country_code` VARCHAR(8) DEFAULT 'EG',
      `article_id` VARCHAR(255) DEFAULT NULL,
      `article_title` VARCHAR(500) DEFAULT NULL,
      `category` VARCHAR(64) DEFAULT NULL,
      `duration_ms` INT UNSIGNED DEFAULT 0,
      `metadata` JSON DEFAULT NULL,
      `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `idx_events_type` (`event_type`),
      KEY `idx_events_created` (`created_at`),
      KEY `idx_events_session` (`session_id`),
      KEY `idx_events_session_type` (`session_id`, `event_type`),
      KEY `idx_events_article` (`article_id`(191)),
      KEY `idx_events_category` (`category`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $data = get_json_input();

    $sessionId = sanitize_string($data['sessionId'] ?? $data['session_id'] ?? '', 64);
    if (empty($sessionId)) {
        $sessionId = md5(get_client_ip() . ($_SERVER['HTTP_USER_AGENT'] ?? 'device'));
    }
    $userId = sanitize_string($data['userId'] ?? get_authenticated_user_id() ?? '', 64);
    if (empty($userId)) $userId = null;
    $deviceOs = sanitize_string($data['deviceOs'] ?? $data['os'] ?? 'unknown', 32);
    $appVersion = sanitize_string($data['appVersion'] ?? '1.0.0', 16);
    $countryCode = strtoupper(sanitize_string($data['countryCode'] ?? '', 8));
    if (empty($countryCode) || $countryCode === 'XX') $countryCode = 'EG';

    $events = $data['events'] ?? null;
    if (!is_array($events) || empty($events)) {
        // Single-event form: { "type": "...", ... }
        $type = sanitize_string($data['type'] ?? $data['event'] ?? '', 32);
        if (empty($type)) {
            json_response(['error' => 'No events provided'], 400);
        }
        $events = [$data];
    }

    // Cap batch size to protect the server
    $events = array_slice($events, 0, 200);

    $allowedTypes = [
        'app_open', 'app_close', 'app_background', 'app_foreground',
        'article_open', 'article_read', 'article_scroll',
        'like', 'unlike', 'save', 'unsave', 'share', 'comment',
        'search', 'category_view', 'tts_play', 'tts_stop',
        'screen_view', 'session_ping', 'error'
    ];

    $rows = [];
    foreach ($events as $e) {
        if (!is_array($e)) continue;
        $type = sanitize_string($e['type'] ?? $e['event'] ?? '', 32);
        if (empty($type) || !in_array($type, $allowedTypes, true)) continue;

        $articleId = sanitize_string($e['articleId'] ?? $e['article_id'] ?? '', 255);
        $articleTitle = sanitize_string($e['articleTitle'] ?? $e['article_title'] ?? '', 500);
        $category = sanitize_string($e['category'] ?? '', 64);
        $durationMs = intval($e['durationMs'] ?? $e['duration_ms'] ?? 0);
        if ($durationMs < 0) $durationMs = 0;
        if ($durationMs > 86400000) $durationMs = 86400000;

        $meta = $e['metadata'] ?? null;
        if (is_array($meta)) $meta = json_encode($meta, JSON_UNESCAPED_UNICODE);
        if (is_string($meta) && strlen($meta) > 8000) $meta = substr($meta, 0, 8000);
        if (!is_string($meta) || $meta === '') $meta = null;
        if (is_string($meta)) json_decode($meta); // validate, ignore errors
        if (json_last_error() !== JSON_ERROR_NONE) $meta = null;

        // Client timestamp (ms) for accurate event ordering across batches
        $ts = isset($e['ts']) ? intval($e['ts']) : 0;
        if ($ts > 0) {
            $sec = intdiv($ts, 1000);
            $createdAt = date('Y-m-d H:i:s', $sec);
        } else {
            $createdAt = date('Y-m-d H:i:s');
        }

        $rows[] = [
            'type'      => $type,
            'articleId' => $articleId,
            'title'     => $articleTitle,
            'category'  => $category,
            'duration'  => $durationMs,
            'meta'      => $meta,
            'createdAt' => $createdAt,
        ];
    }

    if (empty($rows)) {
        json_response(['success' => true, 'inserted' => 0]);
    }

    // Single multi-row INSERT for the whole batch
    $placeholders = [];
    $params = [];
    foreach ($rows as $r) {
        $placeholders[] = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        $params[] = $r['type'];
        $params[] = $sessionId;
        $params[] = $userId;
        $params[] = $deviceOs;
        $params[] = $appVersion;
        $params[] = $countryCode;
        $params[] = $r['articleId'];
        $params[] = $r['title'];
        $params[] = $r['category'];
        $params[] = $r['duration'];
        $params[] = $r['meta'];
        $params[] = $r['createdAt'];
    }

    $db->query(
        "INSERT INTO yn_analytics_events
            (event_type, session_id, user_id, device_os, app_version, country_code, article_id, article_title, category, duration_ms, metadata, created_at)
         VALUES " . implode(', ', $placeholders),
        $params
    );

    json_response([
        'success'    => true,
        'inserted'   => count($rows),
        'sessionId'  => $sessionId,
        'serverTime' => time(),
    ]);

} catch (Exception $e) {
    error_log('Analytics event error: ' . $e->getMessage());
    // Ingest must never break the app: 200 with success=false so the client
    // keeps the events queued for retry on the next flush.
    json_response(['success' => false, 'error' => 'ingest_failed'], 200);
}
?>
