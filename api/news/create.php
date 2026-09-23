<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';

require_post();
check_rate_limit('news_create:' . get_client_ip(), 100, 300);

$data = get_json_input();

$title = sanitize_string($data['title'] ?? '', 500);
$summary = sanitize_string($data['summary'] ?? '', 1000);
$content = $data['content'] ?? null;
$language = sanitize_string($data['language'] ?? 'ar', 8);
$category = sanitize_string($data['category'] ?? '', 64);
$sourceId = sanitize_string($data['source']['id'] ?? $data['sourceId'] ?? $data['source']['name'] ?? '', 64);
$sourceUrlArticle = filter_var(sanitize_string($data['sourceUrl'] ?? $data['sourceUrlArticle'] ?? '', 512), FILTER_SANITIZE_URL);
$imageUrl = filter_var(sanitize_string($data['imageUrl'] ?? '', 512), FILTER_SANITIZE_URL);
if (empty($imageUrl) || str_contains($imageUrl, 'bing.com/images/search')) {
    $seed = crc32($sourceUrlArticle . $title);
    $imageUrl = "https://placehold.co/600x400/EEE/31343C?text=" . urlencode($category) . "+$seed";
}
$publishedAt = intval($data['publishedAt'] ?? time() * 1000);
$status = in_array($data['status'] ?? 'published', ['published', 'draft', 'archived']) ? $data['status'] : 'published';

validate_required(['title' => $title, 'category' => $category, 'sourceId' => $sourceId, 'sourceUrlArticle' => $sourceUrlArticle]);

try {
    $db = Database::getInstance();

    $existing = $db->query(
        'SELECT id FROM yn_news WHERE source_url_article = ? LIMIT 1',
        [$sourceUrlArticle]
    )->fetch();

    if ($existing) {
        $sql = "UPDATE yn_news SET title = ?, summary = ?, content = ?, language = ?, category = ?, source_id = ?, source_url_article = ?, image_url = ?, published_at = ?, status = ?, updated_at = NOW() WHERE id = ?";
        $db->query($sql, [$title, $summary, $content, $language, $category, $sourceId, $sourceUrlArticle, $imageUrl, $publishedAt, $status, $existing['id']]);

        json_response([
            'success' => true,
            'id' => $existing['id'],
            'message' => 'Article updated successfully',
            'updated' => true,
        ], 200);
        return;
    }

    $id = generate_secure_id('article_');

    $sql = "INSERT INTO yn_news (id, title, summary, content, language, category, source_id, source_url_article, image_url, published_at, status, created_at, updated_at) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())";
    $db->query($sql, [$id, $title, $summary, $content, $language, $category, $sourceId, $sourceUrlArticle, $imageUrl, $publishedAt, $status]);

    json_response([
        'success' => true,
        'id' => $id,
        'message' => 'Article created successfully'
    ], 201);

} catch (Exception $e) {
    error_log('Create article error: ' . $e->getMessage());
    json_response(['error' => 'Failed to create article'], 500);
}
?>
