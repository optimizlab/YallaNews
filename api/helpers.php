<?php
session_set_cookie_params([
    'lifetime' => 86400,
    'path' => '/',
    'domain' => '',
    'secure' => isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on',
    'httponly' => true,
    'samesite' => 'Lax'
]);
session_start();

header('Content-Type: application/json');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: ' . ($_SERVER['REQUEST_METHOD'] === 'OPTIONS' ? 'OPTIONS' : 'GET, POST, PUT, DELETE, OPTIONS'));
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Max-Age: 86400');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function json_response($data, $status = 200) {
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function get_json_input() {
    $raw = file_get_contents('php://input');
    if (empty($raw)) {
        json_response(['error' => 'Empty request body'], 400);
    }
    $data = json_decode($raw, true);
    if (json_last_error() !== JSON_ERROR_NONE) {
        json_response(['error' => 'Invalid JSON'], 400);
    }
    return $data;
}

function require_post() {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function require_get() {
    if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function require_put() {
    if ($_SERVER['REQUEST_METHOD'] !== 'PUT') {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function require_delete() {
    if ($_SERVER['REQUEST_METHOD'] !== 'DELETE') {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function validate_required($data) {
    foreach ($data as $field => $value) {
        if (empty($value)) {
            json_response(['error' => "Missing required field: $field"], 400);
        }
    }
}

function sanitize_string($value, $maxLength = 255) {
    return is_string($value) ? substr(trim($value), 0, $maxLength) : null;
}

function get_client_ip() {
    return $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

function check_rate_limit($key, $maxRequests = 60, $windowSeconds = 60) {
    $cacheFile = sys_get_temp_dir() . '/rate_limit_' . md5($key) . '.json';
    $now = time();
    
    $hits = [];
    if (file_exists($cacheFile)) {
        $hits = json_decode(file_get_contents($cacheFile), true) ?: [];
        $hits = array_filter($hits, fn($t) => $t > $now - $windowSeconds);
    }
    
    if (count($hits) >= $maxRequests) {
        json_response(['error' => 'Rate limit exceeded'], 429);
    }
    
    $hits[] = $now;
    file_put_contents($cacheFile, json_encode($hits));
}

function generate_secure_id($prefix = '') {
    return $prefix . bin2hex(random_bytes(16));
}

function require_auth() {
    if (empty($_SESSION['user_id'])) {
        json_response(['error' => 'Unauthorized'], 401);
    }
    return $_SESSION['user_id'];
}

function get_authenticated_user_id() {
    return $_SESSION['user_id'] ?? null;
}

function require_admin() {
    $userId = require_auth();
    if (($_SESSION['role'] ?? 'user') !== 'admin') {
        json_response(['error' => 'Forbidden'], 403);
    }
    return $userId;
}

function get_pagination_params() {
    $page = max(1, intval($_GET['page'] ?? 1));
    $limit = min(100, max(1, intval($_GET['limit'] ?? 20)));
    $offset = ($page - 1) * $limit;
    return [$page, $limit, $offset];
}

function cache_headers($maxAge = 300) {
    header('Cache-Control: public, max-age=' . $maxAge);
    header('Expires: ' . gmdate('D, d M Y H:i:s', time() + $maxAge) . ' GMT');
}

function no_cache_headers() {
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
}

?>
