<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

if (isset($_SESSION['user_id'])) {
    unset($_SESSION['user_id']);
    unset($_SESSION['role']);
    session_destroy();
}

json_response(['success' => true, 'message' => 'Logged out successfully']);
?>
