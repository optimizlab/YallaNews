<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_admin();

$search = sanitize_string($_GET['search'] ?? '', 255);
[$page, $limit, $offset] = get_pagination_params();

$where = '';
$params = [];
if ($search !== '') {
    $where = 'WHERE (r.article_id LIKE ? OR nr.title LIKE ? OR r.reported_by_name LIKE ? OR r.reason LIKE ?)';
    $like = '%' . $search . '%';
    $params = [$like, $like, $like, $like];
}

try {
    $db = Database::getInstance();

    $countSql = "SELECT COUNT(*) AS cnt FROM yn_news_reports r
                 LEFT JOIN yn_news nr ON nr.id = r.article_id
                 $where";
    $total = intval($db->query($countSql, $params)->fetch()['cnt']);

    $sql = "SELECT r.id, r.article_id, r.reported_by, r.reported_by_name, r.reason, r.status, r.created_at,
                   nr.title AS article_title, nr.language AS article_language
            FROM yn_news_reports r
            LEFT JOIN yn_news nr ON nr.id = r.article_id
            $where
            ORDER BY r.created_at DESC
            LIMIT ? OFFSET ?";
    $stmt = $db->query($sql, array_merge($params, [$limit, $offset]));
    $rows = $stmt->fetchAll();

    $reports = array_map(function ($r) use ($db) {
        return [
            'id' => $r['id'],
            'articleId' => $r['article_id'],
            'articleTitle' => $r['article_title'] ?? '-',
            'articleLanguage' => $r['article_language'] ?? '',
            'reportedBy' => $r['reported_by'],
            'reportedByName' => $r['reported_by_name'],
            'reason' => $r['reason'],
            'status' => $r['status'],
            'createdAt' => $r['created_at'],
        ];
    }, $rows);

    json_response([
        'success' => true,
        'reports' => $reports,
        'pagination' => [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'totalPages' => max(1, ceil($total / $limit)),
        ],
    ]);

} catch (Exception $e) {
    error_log('List reports error: ' . $e->getMessage());
    json_response(['error' => 'Failed to load reports'], 500);
}
?>
