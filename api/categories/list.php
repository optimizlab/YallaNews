<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/category_helpers.php';

no_cache_headers();

try {
    $db = Database::getInstance();
    $all = ($_GET['all'] ?? '') === '1';

    $categoryColumns = [];
    try {
        $categoryColumns = category_table_columns($db);
    } catch (Exception $e) {
        error_log('category_table_columns failed: ' . $e->getMessage());
    }

    if (empty($categoryColumns)) {
        json_response([
            'success' => true,
            'categories' => [],
            'count' => 0,
        ]);
        return;
    }

    $selectCols = category_select_columns($categoryColumns);

    $sql = 'SELECT ' . implode(', ', array_unique($selectCols)) . ' FROM yn_categories';
    if (!$all && isset($categoryColumns['active'])) {
        $sql .= ' WHERE active = 1';
    }
    $sql .= isset($categoryColumns['sort_order'])
        ? ' ORDER BY sort_order ASC, name ASC'
        : ' ORDER BY name ASC';

    if (!$all) {
        list($page, $limit, $offset) = get_pagination_params();
        $countSql = 'SELECT COUNT(*) as total FROM yn_categories' . (isset($categoryColumns['active']) ? ' WHERE active = 1' : '');
        $countStmt = $db->query($countSql);
        $total = intval($countStmt->fetch()['total'] ?? 0);
        $sql .= ' LIMIT ? OFFSET ?';
        $categories = $db->query($sql, [$limit, $offset])->fetchAll();
    } else {
        $total = 0;
        $categories = $db->query($sql)->fetchAll();
    }
    $formatted = array_map('format_category', $categories);

    $response = [
        'success' => true,
        'categories' => $formatted,
        'count' => count($formatted),
    ];
    if (!$all) {
        $response['pagination'] = [
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
            'totalPages' => (int) ceil($total / $limit)
        ];
    }

    json_response($response);
} catch (Exception $e) {
    error_log('List categories error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch categories', 'details' => $e->getMessage()], 500);
}
