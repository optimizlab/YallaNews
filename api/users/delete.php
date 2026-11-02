<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? $_POST['id'] ?? '', 64);
if (empty($id)) {
    $data = get_json_input();
    $id = sanitize_string($data['id'] ?? '', 64);
}

if (empty($id)) {
    json_response(['error' => 'Missing user id'], 400);
}

try {
    $db = Database::getInstance();

    // Prevent deleting the main admin account if it's the only one
    $adminCount = $db->query("SELECT COUNT(*) as count FROM yn_users WHERE role = 'admin'")->fetch();
    $targetUser = $db->query("SELECT role FROM yn_users WHERE id = ?", [$id])->fetch();

    if ($targetUser && $targetUser['role'] === 'admin' && intval($adminCount['count'] ?? 0) <= 1) {
        json_response(['error' => 'Cannot delete the only admin account'], 403);
    }

    $db->query("DELETE FROM yn_users WHERE id = ?", [$id]);

    json_response([
        'success' => true,
        'message' => 'User deleted successfully'
    ]);
} catch (Exception $e) {
    error_log('Delete user error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete user', 'details' => $e->getMessage()], 500);
}
?>
