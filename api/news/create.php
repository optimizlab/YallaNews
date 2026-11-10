<?php
require_once __DIR__ . '/../helpers.php';
require_once __DIR__ . '/../db.php';
require_once __DIR__ . '/news_schema.php';

require_post();
check_rate_limit('news_create:' . get_client_ip(), 100, 300);

$data = get_json_input();

$title = sanitize_string($data['title'] ?? '', 500);
$summary = sanitize_string($data['summary'] ?? '', 1000);
$content = $data['content'] ?? null;
$language = sanitize_string($data['language'] ?? 'ar', 8);
$category = sanitize_string($data['category'] ?? '', 64);
$sourceName = sanitize_string($data['source']['name'] ?? $data['sourceName'] ?? $data['sourceId'] ?? $data['source']['id'] ?? '', 255);
$sourceUrl = filter_var(
    sanitize_string($data['source']['url'] ?? $data['source_url'] ?? '', 512),
    FILTER_SANITIZE_URL
);
$sourceUrlArticle = filter_var(
    sanitize_string($data['sourceUrlArticle'] ?? $data['articleUrl'] ?? $data['sourceUrl'] ?? '', 512),
    FILTER_SANITIZE_URL
);
$imageUrl = filter_var(sanitize_string($data['imageUrl'] ?? '', 512), FILTER_SANITIZE_URL);
if (empty($sourceName)) {
    $sourceName = 'يلا نيوز';
}

$isYallaNews = ($sourceName === 'يلا نيوز' || strtolower($sourceName) === 'yalla news' || strtolower($sourceName) === 'yallanews');
if ($isYallaNews && (empty($sourceUrlArticle) || $sourceUrlArticle === 'https://yallanews.app' || $sourceUrlArticle === 'https://yallanews.app/')) {
    $sourceUrlArticle = 'https://yallanews.app/news/exclusive_' . time() . '_' . substr(bin2hex(random_bytes(4)), 0, 6);
}

if (empty($imageUrl) || str_contains($imageUrl, 'bing.com/images/search')) {
    $seed = crc32($sourceUrlArticle . $title);
    $imageUrl = "https://placehold.co/600x400/EEE/31343C?text=" . urlencode($category) . "+$seed";
}
$publishedAt = intval($data['publishedAt'] ?? time() * 1000);
$status = in_array($data['status'] ?? 'published', ['published', 'draft', 'archived']) ? $data['status'] : 'published';

validate_required(['title' => $title, 'category' => $category, 'source_id' => $sourceName, 'source_url_article' => $sourceUrlArticle]);

try {
    $db = Database::getInstance();
    $columns = news_table_columns($db);
    foreach (['id', 'title', 'category', 'language', 'source_url_article'] as $requiredColumn) {
        if (!news_has_column($columns, $requiredColumn)) {
            throw new RuntimeException("yn_news is missing required column: $requiredColumn");
        }
    }

    [$sourceColumn, $sourceValue] = news_source_write_value(
        $db,
        $columns,
        $sourceName,
        $sourceUrl
    );
    if ($sourceColumn === null) {
        throw new RuntimeException('yn_news must contain source_name or source_id');
    }

    $categoryColumns = $db->query('SHOW COLUMNS FROM yn_categories')->fetchAll(PDO::FETCH_COLUMN, 0);
    $categoryQuery = in_array('active', $categoryColumns, true)
        ? 'SELECT id FROM yn_categories WHERE id = ? AND active = 1 LIMIT 1'
        : 'SELECT id FROM yn_categories WHERE id = ? LIMIT 1';
    $categoryExists = $db->query($categoryQuery, [$category])->fetch();
    if (!$categoryExists) {
        json_response(['error' => 'Category does not exist or is inactive'], 400);
    }

    $existing = $db->query(
        'SELECT id FROM yn_news WHERE source_url_article = ? AND language = ? LIMIT 1',
        [$sourceUrlArticle, $language]
    )->fetch();

    if ($existing) {
        $updates = [
            'title' => $title,
            'language' => $language,
            'category' => $category,
            $sourceColumn => $sourceValue,
            'source_url_article' => $sourceUrlArticle,
        ];
        foreach ([
            'summary' => $summary,
            'content' => $content,
            'source_url' => $sourceUrl,
            'image_url' => $imageUrl,
            'published_at' => $publishedAt,
            'status' => $status,
        ] as $column => $value) {
            if (news_has_column($columns, $column)) {
                $updates[$column] = $value;
            }
        }
        $assignments = array_map(fn($column) => "$column = ?", array_keys($updates));
        if (news_has_column($columns, 'updated_at')) {
            $assignments[] = 'updated_at = NOW()';
        }
        $db->query(
            'UPDATE yn_news SET ' . implode(', ', $assignments) . ' WHERE id = ?',
            array_merge(array_values($updates), [$existing['id']])
        );

        json_response([
            'success' => true,
            'id' => $existing['id'],
            'message' => 'Article updated successfully',
            'updated' => true,
        ], 200);
        return;
    }

    $id = generate_secure_id('article_');
    $insert = [
        'id' => $id,
        'title' => $title,
        'language' => $language,
        'category' => $category,
        $sourceColumn => $sourceValue,
        'source_url_article' => $sourceUrlArticle,
    ];
    foreach ([
        'summary' => $summary,
        'content' => $content,
        'source_url' => $sourceUrl,
        'image_url' => $imageUrl,
        'published_at' => $publishedAt,
        'status' => $status,
    ] as $column => $value) {
        if (news_has_column($columns, $column)) {
            $insert[$column] = $value;
        }
    }
    $insertColumns = array_keys($insert);
    $insertValues = array_fill(0, count($insertColumns), '?');
    if (news_has_column($columns, 'created_at')) {
        $insertColumns[] = 'created_at';
        $insertValues[] = 'NOW()';
    }
    if (news_has_column($columns, 'updated_at')) {
        $insertColumns[] = 'updated_at';
        $insertValues[] = 'NOW()';
    }
    $sql = 'INSERT INTO yn_news (' . implode(', ', $insertColumns) . ') VALUES (' . implode(', ', $insertValues) . ')';
    $db->query($sql, array_values($insert));

    json_response([
        'success' => true,
        'id' => $id,
        'message' => 'Article created successfully'
    ], 201);

} catch (Exception $e) {
    $serverMessage = 'Server error: ' . $e->getMessage();
    error_log('Create article error: ' . $e->getMessage());
    json_response([
        'error' => 'Failed to create article',
        'details' => $serverMessage,
    ], 500);
}
