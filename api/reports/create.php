<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
check_rate_limit('report_create:' . get_client_ip(), 30, 300);

$userId = require_auth();

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? '', 64);
$reason = sanitize_string($data['reason'] ?? '', 2000);

validate_required([
    'articleId' => $articleId,
    'reason' => $reason,
]);

try {
    $db = Database::getInstance();

    // Resolve the article: accept either the server id or the source URL.
    $resolvedId = $articleId;
    if (str_starts_with($articleId, 'http://') || str_starts_with($articleId, 'https://')) {
        $found = $db->query("SELECT id FROM yn_news WHERE source_url_article = ? LIMIT 1", [$articleId])->fetch();
        if ($found) {
            $resolvedId = $found['id'];
        } else {
            json_response(['error' => 'Article not found'], 404);
            return;
        }
    } else {
        $exists = $db->query('SELECT id FROM yn_news WHERE id = ? LIMIT 1', [$resolvedId])->fetch();
        if (!$exists) {
            json_response(['error' => 'Article not found'], 404);
            return;
        }
    }

    // Avoid duplicate pending reports from the same user on the same article
    $dup = $db->query(
        'SELECT id FROM yn_news_reports WHERE article_id = ? AND reported_by = ? AND status = "pending" LIMIT 1',
        [$resolvedId, $userId]
    )->fetch();
    if ($dup) {
        json_response([
            'success' => true,
            'id' => $dup['id'],
            'message' => 'You have already reported this article',
            'duplicate' => true,
        ], 200);
        return;
    }

    // Reporter display name
    $reporterName = '';
    $userRow = $db->query('SELECT display_name FROM yn_users WHERE id = ? LIMIT 1', [$userId])->fetch();
    if ($userRow) {
        $reporterName = sanitize_string($userRow['display_name'] ?? '', 255);
    }

    $id = generate_secure_id('report_');
    $db->query(
        'INSERT INTO yn_news_reports (id, article_id, reported_by, reported_by_name, reason, status, created_at) VALUES (?, ?, ?, ?, ?, "pending", NOW())',
        [$id, $resolvedId, $userId, $reporterName, $reason]
    );

    json_response([
        'success' => true,
        'id' => $id,
        'message' => 'Report submitted successfully',
    ], 201);

} catch (Exception $e) {
    error_log('Report article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to submit report'], 500);
}
?>
