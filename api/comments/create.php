<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
$userId = require_auth();
check_rate_limit('comment_create:' . get_client_ip(), 30, 300);

$data = get_json_input();

$articleId = sanitize_string($data['articleId'] ?? $data['article_id'] ?? '', 512);
$userName = sanitize_string($data['userName'] ?? $data['user_name'] ?? '', 255);
$text = sanitize_string($data['text'] ?? '', 2000);
$parentId = sanitize_string($data['parentId'] ?? $data['parent_id'] ?? null, 64);

validate_required(['articleId' => $articleId, 'userName' => $userName, 'text' => $text]);

try {
    $db = Database::getInstance();

    // If articleId is a URL, resolve to yn_news.id or ensure a stub exists
    if (str_starts_with($articleId, 'http://') || str_starts_with($articleId, 'https://')) {
        $found = $db->query("SELECT id FROM yn_news WHERE source_url_article = ? LIMIT 1", [$articleId])->fetch();
        if ($found) {
            $articleId = $found['id'];
        } else {
            $stubId = generate_secure_id('article_');
            try {
                $db->query(
                    "INSERT INTO yn_news (id, title, summary, category, source_name, source_url, source_url_article, published_at, status)
                     VALUES (?, 'خبر', '', 'general', 'يلا نيوز', ?, ?, ?, 'published')",
                    [$stubId, $articleId, $articleId, time() * 1000]
                );
                $articleId = $stubId;
            } catch (Exception $eStub) {
                // If table columns differ, fallback to existing or keep original
            }
        }
    }

    $id = generate_secure_id('comment_');
    $createdAt = date('Y-m-d H:i:s');

    $sql = "INSERT INTO yn_comments (id, article_id, user_id, user_name, text, parent_id, created_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?)";
    $db->query($sql, [$id, $articleId, $userId, $userName, $text, $parentId, $createdAt]);

    json_response([
        'success' => true,
        'id' => $id,
        'message' => 'Comment created successfully'
    ], 201);

} catch (Exception $e) {
    error_log('Create comment error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create comment'], 500);
}
?>
