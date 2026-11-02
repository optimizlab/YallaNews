<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

no_cache_headers();

try {
    $db = Database::getInstance();

    // Auto-create table with country & install tracking if not exists
    $db->query("CREATE TABLE IF NOT EXISTS `yn_active_sessions` (
      `session_id` VARCHAR(64) NOT NULL,
      `user_id` VARCHAR(64) DEFAULT NULL,
      `device_os` VARCHAR(32) DEFAULT 'unknown',
      `app_version` VARCHAR(16) DEFAULT '1.0.0',
      `ip_address` VARCHAR(45) DEFAULT NULL,
      `country` VARCHAR(64) DEFAULT 'مصر',
      `country_code` VARCHAR(8) DEFAULT 'EG',
      `is_new_install` TINYINT(1) DEFAULT 0,
      `last_ping` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`session_id`),
      KEY `idx_active_sessions_ping` (`last_ping`),
      KEY `idx_active_sessions_user` (`user_id`),
      KEY `idx_active_sessions_country` (`country_code`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Ensure columns exist on previously created tables
    try {
        $db->query("ALTER TABLE `yn_active_sessions` ADD COLUMN `country` VARCHAR(64) DEFAULT 'مصر'");
    } catch (Exception $e) {}
    try {
        $db->query("ALTER TABLE `yn_active_sessions` ADD COLUMN `country_code` VARCHAR(8) DEFAULT 'EG'");
    } catch (Exception $e) {}
    try {
        $db->query("ALTER TABLE `yn_active_sessions` ADD COLUMN `is_new_install` TINYINT(1) DEFAULT 0");
    } catch (Exception $e) {}

    $data = get_json_input();
    $sessionId = sanitize_string($data['sessionId'] ?? $data['deviceId'] ?? '', 64);
    if (empty($sessionId)) {
        $sessionId = md5(get_client_ip() . ($_SERVER['HTTP_USER_AGENT'] ?? 'device'));
    }

    $userId = sanitize_string($data['userId'] ?? get_authenticated_user_id() ?? '', 64);
    if (empty($userId)) $userId = null;

    $deviceOs = sanitize_string($data['deviceOs'] ?? $data['os'] ?? 'unknown', 32);
    $appVersion = sanitize_string($data['appVersion'] ?? '1.0.0', 16);
    $isNewInstall = intval($data['isNewInstall'] ?? 0);
    $ip = get_client_ip();

    $countryCode = strtoupper(sanitize_string($data['countryCode'] ?? 'EG', 8));
    if (empty($countryCode) || $countryCode === 'XX') $countryCode = 'EG';

    $countryNames = [
        'EG' => 'مصر',
        'SA' => 'السعودية',
        'AE' => 'الإمارات',
        'MA' => 'المغرب',
        'DZ' => 'الجزائر',
        'TN' => 'تونس',
        'IQ' => 'العراق',
        'JO' => 'الأردن',
        'KW' => 'الكويت',
        'QA' => 'قطر',
        'OM' => 'عُمان',
        'BH' => 'البحرين',
        'LY' => 'ليبيا',
        'SD' => 'السودان',
        'YE' => 'اليمن',
        'LB' => 'لبنان',
        'SY' => 'سوريا',
        'PS' => 'فلسطين',
        'TR' => 'تركيا',
        'FR' => 'فرنسا',
        'US' => 'الولايات المتحدة',
        'GB' => 'المملكة المتحدة',
        'DE' => 'ألمانيا',
    ];
    $countryName = $countryNames[$countryCode] ?? $countryCode;

    $stmt = $db->query(
        "INSERT INTO yn_active_sessions (session_id, user_id, device_os, app_version, ip_address, country, country_code, is_new_install, last_ping)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE 
            user_id = COALESCE(VALUES(user_id), user_id),
            device_os = VALUES(device_os),
            app_version = VALUES(app_version),
            ip_address = VALUES(ip_address),
            country = VALUES(country),
            country_code = VALUES(country_code),
            last_ping = NOW()",
        [$sessionId, $userId, $deviceOs, $appVersion, $ip, $countryName, $countryCode, $isNewInstall]
    );

    // Count live active sessions within the last 2 minutes
    $liveStmt = $db->query("SELECT COUNT(*) as live_count FROM yn_active_sessions WHERE last_ping >= NOW() - INTERVAL 120 SECOND");
    $liveCount = intval($liveStmt->fetch()['live_count'] ?? 1);

    json_response([
        'success' => true,
        'sessionId' => $sessionId,
        'liveCount' => max(1, $liveCount),
        'country' => $countryName,
        'timestamp' => time()
    ]);
} catch (Exception $e) {
    error_log('Ping error: ' . $e->getMessage());
    json_response(['error' => 'Ping failed', 'details' => $e->getMessage()], 500);
}
?>
