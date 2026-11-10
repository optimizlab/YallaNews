<?php

function news_table_columns($db)
{
    $columns = $db->query('SHOW COLUMNS FROM yn_news')->fetchAll(PDO::FETCH_COLUMN, 0);
    return array_fill_keys($columns, true);
}

function news_has_column(array $columns, string $column)
{
    return isset($columns[$column]);
}

function news_source_name_expression(array $columns)
{
    if (news_has_column($columns, 'source_name')) {
        return 'n.source_name';
    }
    if (news_has_column($columns, 'source_id')) {
        return 'COALESCE(s.name, n.source_id)';
    }
    return "''";
}

function news_source_url_expression(array $columns)
{
    if (news_has_column($columns, 'source_url') && news_has_column($columns, 'source_id')) {
        return "COALESCE(NULLIF(n.source_url, ''), s.url, '')";
    }
    if (news_has_column($columns, 'source_url')) {
        return "COALESCE(n.source_url, '')";
    }
    if (news_has_column($columns, 'source_id')) {
        return "COALESCE(s.url, '')";
    }
    return "''";
}

function news_source_join(array $columns)
{
    return news_has_column($columns, 'source_id')
        ? ' LEFT JOIN yn_sources s ON s.id = n.source_id '
        : ' ';
}

function news_source_write_value($db, array $columns, string $sourceName, string $sourceUrl)
{
    if (news_has_column($columns, 'source_name')) {
        return ['source_name', $sourceName];
    }
    if (!news_has_column($columns, 'source_id')) {
        return [null, null];
    }

    $source = null;
    if ($sourceUrl !== '') {
        $source = $db->query(
            'SELECT id FROM yn_sources WHERE url = ? LIMIT 1',
            [$sourceUrl]
        )->fetch();
    }
    if (!$source && $sourceName !== '') {
        $source = $db->query(
            'SELECT id FROM yn_sources WHERE name = ? LIMIT 1',
            [$sourceName]
        )->fetch();
    }

    return ['source_id', $source['id'] ?? $sourceName];
}
