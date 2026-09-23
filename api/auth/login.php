<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

check_rate_limit('login:' . get_client_ip(), 10, 300);

$data = get_json_input();

$email = filter_var(sanitize_string($data['email'] ?? '', 255), FILTER_SANITIZE_EMAIL);
$password = $data['password'] ?? null;

if (!$email || !$password) {
    json_response(['error' => 'Missing email or password'], 400);
}

try {
    $db = Database::getInstance();
    
    $sql = "SELECT id, email, display_name, photo_url, phone_number, password_hash, role 
            FROM yn_users 
            WHERE email = ? 
            LIMIT 1";
    $stmt = $db->query($sql, [$email]);
    $user = $stmt->fetch();

    if (!$user || !password_verify($password, $user['password_hash'] ?? '')) {
        json_response(['error' => 'Invalid credentials'], 401);
    }

    session_regenerate_id(true);
    $_SESSION['user_id'] = $user['id'];
    $_SESSION['role'] = $user['role'];

    json_response([
        'success' => true,
        'user' => [
            'id' => $user['id'],
            'email' => $user['email'],
            'displayName' => $user['display_name'],
            'photoUrl' => $user['photo_url'],
            'phoneNumber' => $user['phone_number'],
            'role' => $user['role']
        ]
    ]);

} catch (Exception $e) {
    error_log('Login error: ' . $e->getMessage());
    json_response(['error' => 'Login failed'], 500);
}
?>
