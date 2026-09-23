<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

json_response([
    'success' => true,
    'authenticated' => isset($_SESSION['user_id']) && !empty($_SESSION['user_id']),
    'user_id' => $_SESSION['user_id'] ?? null
]);
?>
