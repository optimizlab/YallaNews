-- Apply once to an existing database before deploying category translation APIs.
ALTER TABLE `yn_categories`
  ADD COLUMN `name_fr` VARCHAR(128) NOT NULL DEFAULT '' AFTER `name_en`,
  ADD COLUMN `name_tr` VARCHAR(128) NOT NULL DEFAULT '' AFTER `name_fr`;
