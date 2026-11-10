<?php

function category_table_columns($db)
{
    $columns = $db->query('SHOW COLUMNS FROM yn_categories')->fetchAll(PDO::FETCH_COLUMN, 0);
    return array_fill_keys($columns, true);
}

function category_select_columns(array $columns)
{
    $select = [];
    foreach (['id', 'name', 'name_translation', 'name_en', 'name_fr', 'name_tr', 'sort_order', 'active'] as $column) {
        if (isset($columns[$column])) {
            $select[] = $column;
        }
    }
    return $select;
}

function category_translation_expression(array $columns, string $language, string $alias = 'c')
{
    $columnByLanguage = [
        'ar' => 'name',
        'en' => 'name_en',
        'fr' => 'name_fr',
        'tr' => 'name_tr',
    ];
    $column = $columnByLanguage[$language] ?? 'name';
    $expressions = [];
    if (isset($columns[$column])) {
        $expressions[] = "NULLIF($alias.$column, '')";
    }
    if (isset($columns['name_translation'])) {
        $expressions[] = "JSON_UNQUOTE(JSON_EXTRACT($alias.name_translation, '$.$language'))";
    }
    if (!$expressions) {
        return "''";
    }
    return 'COALESCE(' . implode(', ', $expressions) . ", '')";
}

function category_join_translation_select(array $columns, string $alias = 'c', string $prefix = 'category_')
{
    $select = [];
    foreach (['ar', 'en', 'fr', 'tr'] as $language) {
        $select[] = category_translation_expression($columns, $language, $alias)
            . ' AS ' . $prefix . ($language === 'ar' ? 'name' : 'name_' . $language);
    }
    return $select;
}

function category_names_from_input(array $data)
{
    $translations = $data['translations'] ?? $data['name_translation'] ?? [];
    if (!is_array($translations)) {
        $translations = [];
    }

    return [
        'name' => sanitize_string(
            $translations['ar'] ?? $data['nameAr'] ?? $data['name_ar'] ?? $data['name'] ?? '',
            128
        ),
        'name_en' => sanitize_string(
            $translations['en'] ?? $data['nameEn'] ?? $data['name_en'] ?? '',
            128
        ),
        'name_fr' => sanitize_string(
            $translations['fr'] ?? $data['nameFr'] ?? $data['name_fr'] ?? '',
            128
        ),
        'name_tr' => sanitize_string(
            $translations['tr'] ?? $data['nameTr'] ?? $data['name_tr'] ?? '',
            128
        ),
    ];
}

function format_category(array $category)
{
    $jsonTranslations = [];
    $raw = $category['name_translation'] ?? null;
    if (is_string($raw) && $raw !== '') {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) {
            // name_translation is stored as a JSON array like [{"en":..., "fr":..., "tr":..., "es":...}]
            if (isset($decoded[0]) && is_array($decoded[0])) {
                $jsonTranslations = $decoded[0];
            } elseif (isset($decoded['en']) || isset($decoded['ar']) || isset($decoded['fr']) || isset($decoded['tr'])) {
                $jsonTranslations = $decoded;
            }
        }
    }

    $translations = [
        'ar' => (string)($jsonTranslations['ar'] ?? $category['name'] ?? ''),
        'en' => (string)($jsonTranslations['en'] ?? $category['name_en'] ?? ''),
        'fr' => (string)($jsonTranslations['fr'] ?? $category['name_fr'] ?? ''),
        'tr' => (string)($jsonTranslations['tr'] ?? $category['name_tr'] ?? ''),
    ];

    return [
        'id' => (string)$category['id'],
        'name' => $translations['ar'],
        'nameAr' => $translations['ar'],
        'nameEn' => $translations['en'],
        'nameFr' => $translations['fr'],
        'nameTr' => $translations['tr'],
        'translations' => $translations,
        'name_translation' => $translations,
        'sortOrder' => intval($category['sort_order'] ?? 0),
        'active' => (bool)($category['active'] ?? false),
    ];
}

function require_category_names(array $names)
{
    foreach (['name', 'name_en', 'name_fr', 'name_tr'] as $field) {
        if (empty($names[$field])) {
            json_response([
                'error' => 'Missing category translation',
                'field' => $field,
            ], 400);
        }
    }
}
