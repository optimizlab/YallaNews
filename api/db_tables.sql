-- ============================================================
-- YallaNews Database Schema (MySQL / MariaDB)
-- Replaces Firebase Realtime Database
-- ============================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ------------------------------------------------------------
-- 1. Categories
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_categories`;
CREATE TABLE `yn_categories` (
  `id` VARCHAR(64) NOT NULL,
  `name` VARCHAR(128) NOT NULL,
  `name_en` VARCHAR(128) NOT NULL,
  `sort_order` INT DEFAULT 0,
  `active` TINYINT(1) DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_categories_active` (`active`, `sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 2. Sources
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_sources`;
CREATE TABLE `yn_sources` (
  `id` VARCHAR(64) NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `url` VARCHAR(512) NOT NULL,
  `category` VARCHAR(64) DEFAULT 'general',
  `country` CHAR(2) DEFAULT NULL,
  `language` VARCHAR(8) DEFAULT 'ar',
  `status` VARCHAR(32) DEFAULT 'published',
  `score` DECIMAL(3,2) DEFAULT 0.00,
  `last_crawled` BIGINT DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_sources_status` (`status`),
  KEY `idx_sources_category` (`category`),
  CONSTRAINT `fk_sources_category` FOREIGN KEY (`category`) REFERENCES `yn_categories`(`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 3. News (Articles)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_news`;
CREATE TABLE `yn_news` (
  `id` VARCHAR(64) NOT NULL,
  `title` TEXT NOT NULL,
  `summary` TEXT,
  `content` LONGTEXT,
  `language` VARCHAR(8) DEFAULT 'ar',
  `category` VARCHAR(64) NOT NULL,
  `source_name` VARCHAR(255) NOT NULL,
  `source_url` VARCHAR(512) NOT NULL,
  `source_score` DECIMAL(3,2) DEFAULT 0.00,
  `source_url_article` VARCHAR(512) NOT NULL,
  `image_url` VARCHAR(512) DEFAULT NULL,
  `published_at` BIGINT NOT NULL,
  `status` VARCHAR(32) DEFAULT 'published',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_news_published_at` (`published_at`),
  KEY `idx_news_status` (`status`),
  KEY `idx_news_category` (`category`),
  FULLTEXT KEY `idx_news_fulltext` (`title`, `summary`, `content`) WITH PARSER ngram,
  CONSTRAINT `fk_news_category` FOREIGN KEY (`category`) REFERENCES `yn_categories`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 4. Comments
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_comments`;
CREATE TABLE `yn_comments` (
  `id` VARCHAR(64) NOT NULL,
  `article_id` VARCHAR(64) NOT NULL,
  `user_id` VARCHAR(64) NOT NULL,
  `user_name` VARCHAR(255) NOT NULL,
  `text` TEXT NOT NULL,
  `parent_id` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_comments_article` (`article_id`),
  KEY `idx_comments_user` (`user_id`),
  KEY `idx_comments_parent` (`parent_id`),
  CONSTRAINT `fk_comments_article` FOREIGN KEY (`article_id`) REFERENCES `yn_news`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 5. Users
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_users`;
CREATE TABLE `yn_users` (
  `id` VARCHAR(64) NOT NULL,
  `email` VARCHAR(255) NOT NULL,
  `display_name` VARCHAR(255) NOT NULL,
  `photo_url` VARCHAR(512) DEFAULT NULL,
  `phone_number` VARCHAR(32) DEFAULT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `role` VARCHAR(32) DEFAULT 'user',
  `created_at` DATETIME NOT NULL,
  `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_users_email` (`email`),
  KEY `idx_users_created_at` (`created_at`),
  KEY `idx_users_role` (`role`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 6. User Following (many-to-many)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_user_following`;
CREATE TABLE `yn_user_following` (
  `follower_id` VARCHAR(64) NOT NULL,
  `following_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`follower_id`, `following_id`),
  KEY `idx_user_following_following` (`following_id`),
  CONSTRAINT `fk_user_following_follower` FOREIGN KEY (`follower_id`) REFERENCES `yn_users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_user_following_following` FOREIGN KEY (`following_id`) REFERENCES `yn_users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 7. User Liked Articles (many-to-many)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_user_liked_articles`;
CREATE TABLE `yn_user_liked_articles` (
  `user_id` VARCHAR(64) NOT NULL,
  `article_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `article_id`),
  KEY `idx_user_liked_articles_article` (`article_id`),
  CONSTRAINT `fk_user_liked_articles_user` FOREIGN KEY (`user_id`) REFERENCES `yn_users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_user_liked_articles_article` FOREIGN KEY (`article_id`) REFERENCES `yn_news`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 8. User Saved Articles (many-to-many)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_user_saved_articles`;
CREATE TABLE `yn_user_saved_articles` (
  `user_id` VARCHAR(64) NOT NULL,
  `article_id` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`, `article_id`),
  KEY `idx_user_saved_articles_article` (`article_id`),
  CONSTRAINT `fk_user_saved_articles_user` FOREIGN KEY (`user_id`) REFERENCES `yn_users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_user_saved_articles_article` FOREIGN KEY (`article_id`) REFERENCES `yn_news`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 9. User Reading History
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_user_reading_history`;
CREATE TABLE `yn_user_reading_history` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `user_id` VARCHAR(64) NOT NULL,
  `article_id` VARCHAR(64) NOT NULL,
  `read_at` BIGINT NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_reading_history` (`user_id`, `article_id`),
  KEY `idx_reading_history_user` (`user_id`),
  KEY `idx_reading_history_article` (`article_id`),
  CONSTRAINT `fk_reading_history_user` FOREIGN KEY (`user_id`) REFERENCES `yn_users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_reading_history_article` FOREIGN KEY (`article_id`) REFERENCES `yn_news`(`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- 10. Trending Searches
-- ------------------------------------------------------------
DROP TABLE IF EXISTS `yn_trending_searches`;
CREATE TABLE `yn_trending_searches` (
  `id` VARCHAR(64) NOT NULL,
  `query` VARCHAR(255) NOT NULL,
  `count` INT DEFAULT 0,
  `language` VARCHAR(8) DEFAULT 'ar',
  `created_at` BIGINT NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_trending_searches_count` (`count`),
  KEY `idx_trending_searches_language` (`language`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
