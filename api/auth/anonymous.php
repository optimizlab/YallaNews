<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
check_rate_limit('anonymous:' . get_client_ip(), 20, 300);

try {
    $db = Database::getInstance();

    $guestId = generate_secure_id('guest_');
    $authToken = bin2hex(random_bytes(32)); // 64-char hex token
    $guestEmail = 'guest_' . substr($guestId, 6) . '@yallanews.guest';
    $displayName = 'Guest User';

    // Ensure auth_token column exists (safe migration, mirrors login.php/signup.php)
    try {
        $db->query("ALTER TABLE yn_users ADD COLUMN auth_token VARCHAR(128) DEFAULT NULL, ADD INDEX idx_auth_token (auth_token)", []);
    } catch (Exception $ignoreMigration) {}

    $db->query(
        "INSERT INTO yn_users (id, email, display_name, photo_url, phone_number, password_hash, role, auth_token, created_at) 
         VALUES (?, ?, ?, NULL, NULL, NULL, 'guest', ?, NOW())",
        [$guestId, $guestEmail, $displayName, $authToken]
    );

    // Verify the token was persisted
    $verify = $db->query("SELECT auth_token FROM yn_users WHERE id = ? LIMIT 1", [$guestId]);
    $saved = $verify->fetch();
    if (!$saved || $saved['auth_token'] !== $authToken) {
        throw new Exception('Failed to persist guest auth token');
    }

    session_regenerate_id(true);
    $_SESSION['user_id'] = $guestId;
    $_SESSION['role'] = 'guest';

    json_response([
        'success' => true,
        'token'   => $authToken,
        'user' => [
            'id'        => $guestId,
            'email'     => $guestEmail,
            'displayName' => $displayName,
            'photoUrl'  => null,
            'phoneNumber' => null,
            'role'      => 'guest'
        ]
    ]);

} catch (Exception $e) {
    error_log('Anonymous login error: ' . $e->getMessage());
    json_response(['success' => false, 'error' => 'Guest login failed'], 500);
}

?>
