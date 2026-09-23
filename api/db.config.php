<?php
// Detect environment
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$is_localhost = ($host === 'localhost' || $host === '127.0.0.1' || strpos($host, '192.168.') === 0);

if ($is_localhost) {
    if (file_exists(__DIR__ . '/db.config.local.php')) {
        require_once __DIR__ . '/db.config.local.php';
    } else {
        die('Local database configuration (db.config.local.php) is missing.');
    }
} else {
    if (file_exists(__DIR__ . '/db.config.prod.php')) {
        require_once __DIR__ . '/db.config.prod.php';
    } else {
        die('Production database configuration (db.config.prod.php) is missing.');
    }
}

define('DB_CHARSET', 'utf8mb4');
define('JWT_SECRET', 'your_jwt_secret_key_here_change_in_production');
?>
