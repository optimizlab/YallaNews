<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

// Resolve the user from the Bearer token (Flutter app) or session (web).
$userId = get_authenticated_user_id();
$role = $_SESSION['role'] ?? 'user';
$user = null;

if ($userId) {
    try {
        $db = Database::getInstance();
        $stmt = $db->query("SELECT id, email, display_name, role FROM yn_users WHERE id = ? LIMIT 1", [$userId]);
        $user = $stmt->fetch();
        if ($user) {
            $role = $user['role'];
            $_SESSION['role'] = $role;
        }
    } catch (Exception $e) {}
}

json_response([
    'success' => true,
    'authenticated' => !empty($userId),
    'user_id' => $userId,
    'role' => $role,
    'user' => $user
]);
?>
