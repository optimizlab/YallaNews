<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

cache_headers(300);

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id) {
    json_response(['error' => 'Missing user id'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT id, email, display_name, photo_url, phone_number, created_at FROM yn_users WHERE id = ? LIMIT 1";
    $stmt = $db->query($sql, [$id]);
    $user = $stmt->fetch();

    if (!$user) {
        json_response(['error' => 'User not found'], 404);
    }

    json_response([
        'success' => true,
        'user' => [
            'id' => $user['id'],
            'email' => $user['email'],
            'displayName' => $user['display_name'],
            'photoUrl' => $user['photo_url'],
            'phoneNumber' => $user['phone_number'],
            'createdAt' => $user['created_at']
        ]
    ]);

} catch (Exception $e) {
    error_log('Get user error: ' . $e->getMessage());
    json_response(['error' => 'Failed to fetch user'], 500);
}
?>
