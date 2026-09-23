<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();
$userId = require_auth();

$id = sanitize_string($_GET['id'] ?? '', 64);

if (!$id || $id !== $userId) {
    json_response(['error' => 'Invalid user id'], 403);
}

$rawInput = file_get_contents('php://input');
if (empty($rawInput)) {
    json_response(['error' => 'Empty request body'], 400);
}
$data = json_decode($rawInput, true);
if (json_last_error() !== JSON_ERROR_NONE) {
    json_response(['error' => 'Invalid JSON'], 400);
}

try {
    $db = Database::getInstance();

    $allowedFields = ['display_name', 'photo_url', 'phone_number'];
    $updates = [];
    $params = [];

    foreach ($allowedFields as $field) {
        $key = str_replace('_', '', $field);
        if (isset($data[$key])) {
            $updates[] = "$field = ?";
            $params[] = $data[$key];
        }
    }

    if (empty($updates)) {
        json_response(['error' => 'No valid fields to update'], 400);
    }

    $params[] = $userId;
    $sql = "UPDATE yn_users SET " . implode(', ', $updates) . ", updated_at = NOW() WHERE id = ?";
    $db->query($sql, $params);

    json_response([
        'success' => true,
        'message' => 'User updated successfully'
    ]);

} catch (Exception $e) {
    error_log('Update user error: ' . $e->getMessage());
    json_response(['error' => 'Failed to update user'], 500);
}
?>
