<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

check_rate_limit('signup:' . get_client_ip(), 5, 600);

$data = get_json_input();

$email = filter_var(sanitize_string($data['email'] ?? '', 255), FILTER_SANITIZE_EMAIL);
$password = $data['password'] ?? null;
$displayName = sanitize_string($data['displayName'] ?? $data['username'] ?? '', 255);
$photoUrl = filter_var(sanitize_string($data['photoUrl'] ?? '', 512), FILTER_SANITIZE_URL);
$phoneNumber = sanitize_string($data['phoneNumber'] ?? '', 32);

validate_required(['email' => $email, 'password' => $password, 'displayName' => $displayName]);

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    json_response(['error' => 'Invalid email format'], 400);
}

if (strlen($password) < 8) {
    json_response(['error' => 'Password must be at least 8 characters'], 400);
}

try {
    $db = Database::getInstance();

    $sql = "SELECT id FROM yn_users WHERE email = ?";
    $stmt = $db->query($sql, [$email]);
    if ($stmt->fetch()) {
        json_response(['error' => 'Email already exists'], 409);
    }

    $passwordHash = password_hash($password, PASSWORD_DEFAULT);
    $userId = generate_secure_id('user_');

    $sql = "INSERT INTO yn_users (id, email, display_name, photo_url, phone_number, password_hash, role, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, 'user', NOW())";
    $db->query($sql, [$userId, $email, $displayName, $photoUrl, $phoneNumber, $passwordHash]);

    session_regenerate_id(true);
    $_SESSION['user_id'] = $userId;
    $_SESSION['role'] = 'user';

    json_response([
        'success' => true,
        'user' => [
            'id' => $userId,
            'email' => $email,
            'displayName' => $displayName,
            'photoUrl' => $photoUrl,
            'phoneNumber' => $phoneNumber,
            'role' => 'user'
        ]
    ]);

} catch (Exception $e) {
    error_log('Signup error: ' . $e->getMessage());
    json_response(['error' => 'Signup failed'], 500);
}
?>
