<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

// Admin-only: real user-behavior analytics aggregated from yn_analytics_events
require_admin();

try {
    $db = Database::getInstance();

    $default = [
        'totals' => [],
        'events24h' => [],
        'realtime' => [],
        'topArticles' => [],
        'topCategories' => [],
        'topSearches' => [],
        'topCountries' => [],
        'osStats' => [],
        'funnel' => [],
        'daily' => [],
        'recentEvents' => [],
        'serverTime' => time(),
    ];

    $tableExists = false;
    try {
        $chk = $db->query("SHOW TABLES LIKE 'yn_analytics_events'")->fetch();
        $tableExists = !empty($chk);
    } catch (Exception $e) {}

    if (!$tableExists) {
        json_response(['success' => true, 'behavior' => $default]);
    }

    // ── 1. Totals (24h / 7d / all) per event type ────────────────────────────
    $totals = [
        '24h' => [],
        '7d'  => [],
        'all' => [],
    ];
    $stmt = $db->query("SELECT event_type, 
                               SUM(CASE WHEN created_at >= NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END) as c24,
                               SUM(CASE WHEN created_at >= NOW() - INTERVAL 7 DAY THEN 1 ELSE 0 END) as c7,
                               COUNT(*) as c_all
                        FROM yn_analytics_events 
                        GROUP BY event_type");
    foreach ($stmt->fetchAll() as $row) {
        $totals['24h'][$row['event_type']] = intval($row['c24']);
        $totals['7d'][$row['event_type']]  = intval($row['c7']);
        $totals['all'][$row['event_type']] = intval($row['c_all']);
    }

    // Unique users/sessions per window
    $uniqStmt = $db->query("SELECT 
        COUNT(DISTINCT CASE WHEN created_at >= NOW() - INTERVAL 24 HOUR THEN session_id END) as sessions24,
        COUNT(DISTINCT CASE WHEN created_at >= NOW() - INTERVAL 24 HOUR THEN user_id END) as users24,
        COUNT(DISTINCT CASE WHEN created_at >= NOW() - INTERVAL 7 DAY THEN session_id END) as sessions7,
        COUNT(DISTINCT CASE WHEN created_at >= CURDATE() THEN session_id END) as sessions_today,
        COUNT(DISTINCT CASE WHEN created_at >= CURDATE() AND user_id IS NOT NULL THEN user_id END) as logged_today
        FROM yn_analytics_events");
    $uniq = $uniqStmt->fetch();

    // ── 2. Realtime series (events per minute, last 30 min) ──────────────────
    $rtStmt = $db->query("SELECT DATE_FORMAT(created_at, '%H:%i') as minute, COUNT(*) as count
                          FROM yn_analytics_events
                          WHERE created_at >= NOW() - INTERVAL 30 MINUTE
                          GROUP BY DATE_FORMAT(created_at, '%H:%i')
                          ORDER BY minute ASC");
    $realtime = $rtStmt->fetchAll();

    // ── 3. Top articles (7d) ─────────────────────────────────────────────────
    $topArticles = [];
    try {
        $topStmt = $db->query("SELECT article_id, article_title, category,
                                      SUM(CASE WHEN event_type = 'article_open' THEN 1 ELSE 0 END) as opens,
                                      SUM(CASE WHEN event_type = 'article_read' THEN 1 ELSE 0 END) as read_count,
                                      AVG(CASE WHEN event_type = 'article_read' THEN duration_ms ELSE NULL END) as avg_read_ms
                               FROM yn_analytics_events
                               WHERE event_type IN ('article_open','article_read')
                                 AND article_id IS NOT NULL
                                 AND created_at >= NOW() - INTERVAL 7 DAY
                               GROUP BY article_id, article_title, category
                               ORDER BY opens DESC
                               LIMIT 10");
        $topArticles = $topStmt->fetchAll();
    } catch (Exception $e) {}

    // ── 4. Top categories opened (7d) ────────────────────────────────────────
    $topCategories = [];
    try {
        $catStmt = $db->query("SELECT category, COUNT(*) as count
                               FROM yn_analytics_events
                               WHERE event_type = 'article_open' AND category IS NOT NULL AND category <> ''
                                 AND created_at >= NOW() - INTERVAL 7 DAY
                               GROUP BY category
                               ORDER BY count DESC
                               LIMIT 8");
        $topCategories = $catStmt->fetchAll();
    } catch (Exception $e) {}

    // ── 5. Top searches (7d) ─────────────────────────────────────────────────
    $topSearches = [];
    try {
        $searchStmt = $db->query("SELECT JSON_UNQUOTE(JSON_EXTRACT(metadata, '$.term')) as term, COUNT(*) as count
                                  FROM yn_analytics_events
                                  WHERE event_type = 'search'
                                    AND JSON_EXTRACT(metadata, '$.term') IS NOT NULL
                                    AND created_at >= NOW() - INTERVAL 7 DAY
                                  GROUP BY term
                                  ORDER BY count DESC
                                  LIMIT 8");
        $topSearches = $searchStmt->fetchAll();
    } catch (Exception $e) {}

    // ── 6. Top countries (24h) & OS breakdown ────────────────────────────────
    $topCountries = [];
    try {
        $cStmt = $db->query("SELECT country_code, COUNT(*) as count
                             FROM yn_analytics_events
                             WHERE created_at >= NOW() - INTERVAL 24 HOUR
                             GROUP BY country_code
                             ORDER BY count DESC LIMIT 10");
        $topCountries = $cStmt->fetchAll();
    } catch (Exception $e) {}

    $osStats = [];
    try {
        $oStmt = $db->query("SELECT device_os, COUNT(*) as count
                             FROM yn_analytics_events
                             WHERE created_at >= NOW() - INTERVAL 24 HOUR
                             GROUP BY device_os
                             ORDER BY count DESC");
        $osStats = $oStmt->fetchAll();
    } catch (Exception $e) {}

    // ── 7. Engagement funnel (7d) ────────────────────────────────────────────
    $funnel = [];
    try {
        $fStmt = $db->query("SELECT
            SUM(CASE WHEN event_type = 'article_open' THEN 1 ELSE 0 END) as opens,
            SUM(CASE WHEN event_type = 'article_read' THEN 1 ELSE 0 END) as read_count,
            SUM(CASE WHEN event_type = 'like' THEN 1 ELSE 0 END) as likes,
            SUM(CASE WHEN event_type = 'save' THEN 1 ELSE 0 END) as saves,
            SUM(CASE WHEN event_type = 'comment' THEN 1 ELSE 0 END) as comments,
            SUM(CASE WHEN event_type = 'share' THEN 1 ELSE 0 END) as shares,
            SUM(CASE WHEN event_type = 'search' THEN 1 ELSE 0 END) as searches,
            AVG(CASE WHEN event_type = 'article_read' THEN duration_ms ELSE NULL END) as avg_read_ms
            FROM yn_analytics_events
            WHERE created_at >= NOW() - INTERVAL 7 DAY");
        $f = $fStmt->fetch();
        $funnel = [
            'opens'    => intval($f['opens'] ?? 0),
            'reads'    => intval($f['read_count'] ?? 0),
            'likes'    => intval($f['likes'] ?? 0),
            'saves'    => intval($f['saves'] ?? 0),
            'comments' => intval($f['comments'] ?? 0),
            'shares'   => intval($f['shares'] ?? 0),
            'searches' => intval($f['searches'] ?? 0),
            'avgReadMs' => intval($f['avg_read_ms'] ?? 0),
        ];
    } catch (Exception $e) {}

    // ── 8. Daily retention (14d): sessions with app_open per day ─────────────
    $daily = [];
    try {
        $dStmt = $db->query("SELECT DATE(created_at) as date,
                                    COUNT(DISTINCT session_id) as sessions,
                                    SUM(CASE WHEN event_type = 'app_open' THEN 1 ELSE 0 END) as app_opens,
                                    SUM(CASE WHEN event_type = 'article_read' THEN 1 ELSE 0 END) as read_count
                             FROM yn_analytics_events
                             WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
                             GROUP BY DATE(created_at)
                             ORDER BY date ASC");
        $daily = $dStmt->fetchAll();
    } catch (Exception $e) {}

    // ── 9. Recent events stream (last 2h) ────────────────────────────────────
    $recentEvents = [];
    try {
        $rStmt = $db->query("SELECT event_type, article_title, category, device_os, country_code, duration_ms, metadata, created_at
                             FROM yn_analytics_events
                             WHERE created_at >= NOW() - INTERVAL 2 HOUR
                             ORDER BY id DESC LIMIT 20");
        $recentEvents = $rStmt->fetchAll();
    } catch (Exception $e) {}

    json_response([
        'success' => true,
        'behavior' => [
            'totals' => $totals,
            'unique' => [
                'sessions24' => intval($uniq['sessions24'] ?? 0),
                'users24' => intval($uniq['users24'] ?? 0),
                'sessions7' => intval($uniq['sessions7'] ?? 0),
                'sessionsToday' => intval($uniq['sessions_today'] ?? 0),
                'loggedToday' => intval($uniq['logged_today'] ?? 0),
            ],
            'realtime' => $realtime,
            'topArticles' => $topArticles,
            'topCategories' => $topCategories,
            'topSearches' => $topSearches,
            'topCountries' => $topCountries,
            'osStats' => $osStats,
            'funnel' => $funnel,
            'daily' => $daily,
            'recentEvents' => $recentEvents,
            'serverTime' => time(),
        ]
    ]);

} catch (Exception $e) {
    error_log('Behavior stats error: ' . $e->getMessage());
    json_response(['error' => 'Failed to load behavior stats', 'details' => $e->getMessage()], 500);
}
?>
