<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

try {
    $db = Database::getInstance();

    // 1. Real-time presence & audience stats (from heartbeats)
    $liveCount = 0;
    $active24h = 0;
    $dau = 0;
    $totalInstalls = 0;
    $osStats = [];
    $countriesStats = [];
    $dailyStats = [];
    $hourlyStats = [];
    $newInstallsToday = 0;

    try {
        $liveStmt = $db->query("SELECT COUNT(*) as live_count FROM yn_active_sessions WHERE last_ping >= NOW() - INTERVAL 120 SECOND");
        $liveCount = intval($liveStmt->fetch()['live_count'] ?? 0);

        $active24hStmt = $db->query("SELECT COUNT(*) as active_24h FROM yn_active_sessions WHERE last_ping >= NOW() - INTERVAL 24 HOUR");
        $active24h = intval($active24hStmt->fetch()['active_24h'] ?? 0);

        $dauStmt = $db->query("SELECT COUNT(DISTINCT session_id) as dau FROM yn_active_sessions WHERE DATE(last_ping) = CURDATE()");
        $dau = intval($dauStmt->fetch()['dau'] ?? 0);

        $installsStmt = $db->query("SELECT COUNT(*) as total_installs FROM yn_active_sessions");
        $totalInstalls = intval($installsStmt->fetch()['total_installs'] ?? 0);

        $osStmt = $db->query("SELECT device_os, COUNT(*) as count FROM yn_active_sessions GROUP BY device_os ORDER BY count DESC");
        $osStats = $osStmt->fetchAll();

        // Countries breakdown
        $countryStmt = $db->query("SELECT country, country_code, COUNT(*) as count 
                                  FROM yn_active_sessions 
                                  GROUP BY country, country_code 
                                  ORDER BY count DESC LIMIT 10");
        $countriesStats = $countryStmt->fetchAll();

        // New installs today (unique devices flagged as first-run)
        $newInstallsStmt = $db->query("SELECT COUNT(*) as c FROM yn_active_sessions WHERE is_new_install = 1");
        $newInstallsToday = intval($newInstallsStmt->fetch()['c'] ?? 0);

        // Daily activity trend (past 7 days)
        $dailyStmt = $db->query("SELECT DATE(last_ping) as date, 
                                        COUNT(DISTINCT session_id) as active_count,
                                        SUM(CASE WHEN is_new_install = 1 THEN 1 ELSE 0 END) as installs_count
                                 FROM yn_active_sessions 
                                 WHERE last_ping >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
                                 GROUP BY DATE(last_ping)
                                 ORDER BY date ASC");
        $dailyStats = $dailyStmt->fetchAll();

        // Hourly activity (rolling 24h)
        $hourlyStmt = $db->query("SELECT HOUR(last_ping) as hour, COUNT(*) as count 
                                  FROM yn_active_sessions 
                                  WHERE last_ping >= NOW() - INTERVAL 24 HOUR 
                                  GROUP BY HOUR(last_ping) 
                                  ORDER BY hour ASC");
        $hourlyStats = $hourlyStmt->fetchAll();

    } catch (Exception $e) {
        // Table may not exist yet
    }

    // 1b. Real behavior analytics from tracked in-app events
    $realtimeEvents = [];
    $engagement = [
        'opensToday' => 0, 'readsToday' => 0, 'reads24h' => 0,
        'likesToday' => 0, 'savesToday' => 0, 'commentsToday' => 0,
        'sharesToday' => 0, 'searchesToday' => 0, 'appOpensToday' => 0,
        'eventsToday' => 0, 'events24h' => 0,
        'activeSessions24h' => 0, 'loggedInToday' => 0,
        'avgReadMs' => 0,
    ];
    $hasEvents = false;
    try {
        $chk = $db->query("SHOW TABLES LIKE 'yn_analytics_events'")->fetch();
        $hasEvents = !empty($chk);
    } catch (Exception $e) {}

    if ($hasEvents) {
        try {
            // Realtime series: events per minute for the last 30 minutes (server truth)
            $rtStmt = $db->query("SELECT DATE_FORMAT(created_at, '%H:%i') as minute, COUNT(*) as count 
                                  FROM yn_analytics_events 
                                  WHERE created_at >= NOW() - INTERVAL 30 MINUTE 
                                  GROUP BY DATE_FORMAT(created_at, '%H:%i') 
                                  ORDER BY minute ASC");
            $realtimeEvents = $rtStmt->fetchAll();
        } catch (Exception $e) {}

        try {
            $engStmt = $db->query("SELECT
                SUM(CASE WHEN event_type='article_open' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as opens_today,
                SUM(CASE WHEN event_type='article_read' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as reads_today,
                SUM(CASE WHEN event_type='article_read' THEN 1 ELSE 0 END) as reads_24h,
                SUM(CASE WHEN event_type='like' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as likes_today,
                SUM(CASE WHEN event_type='save' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as saves_today,
                SUM(CASE WHEN event_type='comment' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as comments_today,
                SUM(CASE WHEN event_type='share' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as shares_today,
                SUM(CASE WHEN event_type='search' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as searches_today,
                SUM(CASE WHEN event_type='app_open' AND DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as app_opens_today,
                SUM(CASE WHEN DATE(created_at)=CURDATE() THEN 1 ELSE 0 END) as events_today,
                SUM(CASE WHEN created_at >= NOW() - INTERVAL 24 HOUR THEN 1 ELSE 0 END) as events_24h,
                COUNT(DISTINCT CASE WHEN created_at >= NOW() - INTERVAL 24 HOUR THEN session_id END) as sessions_24h,
                COUNT(DISTINCT CASE WHEN DATE(created_at)=CURDATE() AND user_id IS NOT NULL THEN user_id END) as logged_today,
                AVG(CASE WHEN event_type='article_read' AND DATE(created_at)=CURDATE() THEN duration_ms ELSE NULL END) as avg_read_today
                FROM yn_analytics_events");
            $e = $engStmt->fetch();
            $engagement = [
                'opensToday' => intval($e['opens_today'] ?? 0),
                'readsToday' => intval($e['reads_today'] ?? 0),
                'reads24h' => intval($e['reads_24h'] ?? 0),
                'likesToday' => intval($e['likes_today'] ?? 0),
                'savesToday' => intval($e['saves_today'] ?? 0),
                'commentsToday' => intval($e['comments_today'] ?? 0),
                'sharesToday' => intval($e['shares_today'] ?? 0),
                'searchesToday' => intval($e['searches_today'] ?? 0),
                'appOpensToday' => intval($e['app_opens_today'] ?? 0),
                'eventsToday' => intval($e['events_today'] ?? 0),
                'events24h' => intval($e['events_24h'] ?? 0),
                'activeSessions24h' => intval($e['sessions_24h'] ?? 0),
                'loggedInToday' => intval($e['logged_today'] ?? 0),
                'avgReadMs' => intval($e['avg_read_today'] ?? 0),
            ];
        } catch (Exception $e) {}
    }

    // 2. Total News
    $newsStmt = $db->query("SELECT COUNT(*) as total_news, SUM(CASE WHEN status = 'published' THEN 1 ELSE 0 END) as published_news FROM yn_news");
    $newsRow = $newsStmt->fetch();
    $totalNews = intval($newsRow['total_news'] ?? 0);
    $publishedNews = intval($newsRow['published_news'] ?? 0);

    // 3. Total Categories
    $catStmt = $db->query("SELECT COUNT(*) as total_cats FROM yn_categories");
    $totalCategories = intval($catStmt->fetch()['total_cats'] ?? 0);

    // 4. Total Users
    $userStmt = $db->query("SELECT COUNT(*) as total_users FROM yn_users");
    $totalUsers = intval($userStmt->fetch()['total_users'] ?? 0);

    // 5. Total Comments
    $commentStmt = $db->query("SELECT COUNT(*) as total_comments FROM yn_comments");
    $totalComments = intval($commentStmt->fetch()['total_comments'] ?? 0);

    // 6. Total Likes & Saves
    $likesCount = 0;
    try {
        $likesStmt = $db->query("SELECT COUNT(*) as total_likes FROM yn_user_liked_articles");
        $likesCount = intval($likesStmt->fetch()['total_likes'] ?? 0);
    } catch (Exception $e) {}

    $savesCount = 0;
    try {
        $savesStmt = $db->query("SELECT COUNT(*) as total_saves FROM yn_user_saved_articles");
        $savesCount = intval($savesStmt->fetch()['total_saves'] ?? 0);
    } catch (Exception $e) {}

    // 7. News by category
    $catsBreakdown = [];
    try {
        $catNewsStmt = $db->query("SELECT category, COUNT(*) as count FROM yn_news GROUP BY category ORDER BY count DESC LIMIT 8");
        $catsBreakdown = $catNewsStmt->fetchAll();
    } catch (Exception $e) {}

    // 8. Recent Live Activities (content-level)
    $activities = [];

    // Latest comments
    try {
        $recentComments = $db->query("SELECT c.id, c.user_name, c.text, c.created_at, n.title as article_title 
            FROM yn_comments c 
            LEFT JOIN yn_news n ON c.article_id = n.id 
            ORDER BY c.created_at DESC LIMIT 5")->fetchAll();
        foreach ($recentComments as $rc) {
            $activities[] = [
                'type' => 'comment',
                'title' => 'تعليق جديد من ' . ($rc['user_name'] ?? 'مستخدم'),
                'desc' => mb_substr($rc['text'], 0, 80) . '...',
                'meta' => $rc['article_title'] ?? '',
                'time' => $rc['created_at']
            ];
        }
    } catch (Exception $e) {}

    // Latest news added
    try {
        $recentNews = $db->query("SELECT id, title, category, source_name, created_at FROM yn_news ORDER BY id DESC LIMIT 5")->fetchAll();
        foreach ($recentNews as $rn) {
            $activities[] = [
                'type' => 'news',
                'title' => 'خبر مضاف: ' . mb_substr($rn['title'], 0, 60),
                'desc' => 'المصدر: ' . ($rn['source_name'] ?? '') . ' | القسم: ' . ($rn['category'] ?? ''),
                'meta' => $rn['id'],
                'time' => $rn['created_at'] ?? date('Y-m-d H:i:s')
            ];
        }
    } catch (Exception $e) {}

    // Latest users registered
    try {
        $recentUsers = $db->query("SELECT id, display_name, email, role, created_at FROM yn_users ORDER BY created_at DESC LIMIT 5")->fetchAll();
        foreach ($recentUsers as $ru) {
            $activities[] = [
                'type' => 'user',
                'title' => 'مستخدم جديد: ' . ($ru['display_name'] ?? $ru['email']),
                'desc' => $ru['email'] . ' (' . ($ru['role'] ?? 'user') . ')',
                'meta' => $ru['id'],
                'time' => $ru['created_at']
            ];
        }
    } catch (Exception $e) {}

    // Latest tracked behavior events (reads, likes, searches...) — real user behavior
    $behaviorActivities = [];
    if ($hasEvents) {
        try {
            $bEvents = $db->query("SELECT event_type, article_title, category, duration_ms, metadata, created_at
                                   FROM yn_analytics_events
                                   WHERE event_type IN ('article_open','article_read','like','save','share','comment','search','app_open','tts_play')
                                   ORDER BY id DESC LIMIT 12")->fetchAll();
            $eventLabels = [
                'article_open' => 'فتح مقال',
                'article_read' => 'قراءة مقال',
                'like'         => 'إعجاب بمقال',
                'save'         => 'حفظ مقال',
                'share'        => 'مشاركة مقال',
                'comment'      => 'تعليق على مقال',
                'search'       => 'بحث',
                'app_open'     => 'فتح التطبيق',
                'tts_play'     => 'استماع صوتي',
            ];
            foreach ($bEvents as $ev) {
                $term = '';
                if (!empty($ev['metadata'])) {
                    $m = json_decode($ev['metadata'], true);
                    if (is_array($m) && isset($m['term'])) $term = $m['term'];
                }
                $desc = 'القسم: ' . ($ev['category'] ?: '-');
                if ($ev['duration_ms'] > 0) {
                    $sec = intdiv(intval($ev['duration_ms']), 1000);
                    $desc .= ' | المدة: ' . $sec . 'ث';
                }
                if ($term !== '') $desc .= ' | كلمة البحث: ' . $term;
                $behaviorActivities[] = [
                    'type' => 'behavior',
                    'event' => $ev['event_type'],
                    'title' => ($eventLabels[$ev['event_type']] ?? $ev['event_type']) . ': ' . mb_substr($ev['article_title'] ?: ($term ?: '-'), 0, 60),
                    'desc' => $desc,
                    'meta' => '',
                    'time' => $ev['created_at']
                ];
            }
        } catch (Exception $e) {}
    }

    // Sort all activities by time DESC
    usort($activities, function($a, $b) {
        return strtotime($b['time']) - strtotime($a['time']);
    });

    // 9. Final activity feed: real behavior events merged with content events
    $merged = array_merge($behaviorActivities, $activities);
    usort($merged, function($a, $b) {
        return strtotime($b['time']) - strtotime($a['time']);
    });
    $activities = array_slice($merged, 0, 15);

    json_response([
        'success' => true,
        'stats' => [
            'liveCount' => $liveCount,
            'active24h' => $active24h,
            'dau' => $dau,
            'totalInstalls' => $totalInstalls,
            'newInstallsToday' => $newInstallsToday,
            'totalNews' => $totalNews,
            'publishedNews' => $publishedNews,
            'totalCategories' => $totalCategories,
            'totalUsers' => $totalUsers,
            'totalComments' => $totalComments,
            'totalLikes' => $likesCount,
            'totalSaves' => $savesCount,
            'osStats' => $osStats,
            'countriesStats' => $countriesStats,
            'dailyStats' => $dailyStats,
            'hourlyStats' => $hourlyStats,
            'realtimeEvents' => $realtimeEvents,
            'engagement' => $engagement,
            'categoriesBreakdown' => $catsBreakdown,
            'recentActivities' => $activities,
            'timestamp' => time()
        ]
    ]);

} catch (Exception $e) {
    error_log('Stats get error: ' . $e->getMessage());
    json_response(['error' => 'Failed to load stats', 'details' => $e->getMessage()], 500);
}
?>
