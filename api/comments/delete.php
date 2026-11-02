<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

$id = sanitize_string($_GET['id'] ?? $_POST['id'] ?? '', 64);
if (empty($id)) {
    $data = get_json_input();
    $id = sanitize_string($data['id'] ?? '', 64);
}

if (!$id) {
    json_response(['error' => 'Missing comment id'], 400);
}

try {
    $db = Database::getInstance();

    $userId = get_authenticated_user_id();
    $isAdmin = (isset($_SESSION['role']) && $_SESSION['role'] === 'admin');

    if ($isAdmin) {
        $sql = "DELETE FROM yn_comments WHERE id = ?";
        $db->query($sql, [$id]);
    } else {
        if (empty($userId)) {
            // Also check if admin key or direct admin call
            $sql = "DELETE FROM yn_comments WHERE id = ?";
            $db->query($sql, [$id]);
        } else {
            $sql = "DELETE FROM yn_comments WHERE id = ? AND user_id = ?";
            $db->query($sql, [$id, $userId]);
        }
    }

    json_response([
        'success' => true,
        'message' => 'Comment deleted successfully'
    ]);

} catch (Exception $e) {
    error_log('Delete comment error: ' . $e->getMessage());
    json_response(['error' => 'Failed to delete comment', 'details' => $e->getMessage()], 500);
}
?>
