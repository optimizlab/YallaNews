<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

try {
    $db = Database::getInstance();

    $page = max(1, intval($_GET['page'] ?? 1));
    $limit = min(100, max(1, intval($_GET['limit'] ?? 20)));
    $offset = ($page - 1) * $limit;
    $search = sanitize_string($_GET['search'] ?? '', 100);
    $role = sanitize_string($_GET['role'] ?? '', 32);

    $where = [];
    $params = [];

    if (!empty($search)) {
        $where[] = "(email LIKE ? OR display_name LIKE ?)";
        $params[] = "%$search%";
        $params[] = "%$search%";
    }
    if (!empty($role)) {
        $where[] = "role = ?";
        $params[] = $role;
    }

    $whereClause = !empty($where) ? "WHERE " . implode(' AND ', $where) : "";

    $countStmt = $db->query("SELECT COUNT(*) as total FROM yn_users $whereClause", $params);
    $total = intval($countStmt->fetch()['total'] ?? 0);

    $sql = "SELECT id, email, display_name, photo_url, phone_number, role, created_at, updated_at 
            FROM yn_users 
            $whereClause 
            ORDER BY created_at DESC 
            LIMIT $limit OFFSET $offset";
    $stmt = $db->query($sql, $params);
    $users = $stmt->fetchAll();

    $formatted = array_map(function($u) {
        return [
            'id' => $u['id'],
            'email' => $u['email'],
            'displayName' => $u['display_name'],
            'photoUrl' => $u['photo_url'],
            'phoneNumber' => $u['phone_number'],
            'role' => $u['role'] ?? 'user',
            'createdAt' => $u['created_at'],
            'updatedAt' => $u['updated_at']
        ];
    }, $users);

    json_response([
        'success' => true,
        'users' => $formatted,
        'total' => $total,
        'page' => $page,
        'limit' => $limit,
        'pages' => ceil($total / $limit)
    ]);
} catch (Exception $e) {
    error_log('List users error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch users', 'details' => $e->getMessage()], 500);
}
?>
