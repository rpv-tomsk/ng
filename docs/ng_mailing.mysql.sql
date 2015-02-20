CREATE TABLE `ng_mailing_types` (
`type_id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY COMMENT 'Код типа рассылки',
`type_name` VARCHAR(50) NOT NULL COMMENT 'Наименование типа рассылки',
`subject_prefix` VARCHAR(15) NOT NULL DEFAULT '' COMMENT 'Префикс Subj-а рассылок',
`subscribers_module` VARCHAR(25) NOT NULL DEFAULT '' COMMENT 'Код модуля списка подписчиков',
`subscribers_id` VARCHAR(25) NOT NULL DEFAULT '' COMMENT 'Идентификатор группы в модуле списка подписчиков',
`segment_size` SMALLINT UNSIGNED NOT NULL DEFAULT '100' COMMENT 'Количество отправляемых писем за итерацию',
`layout` TEXT NOT NULL COMMENT 'Шаблон обрамления отправляемых писем',
`plain_layout` TEXT NOT NULL COMMENT 'Шаблон обрамления отправляемого Plain-текста',
`mailer_group_code` VARCHAR(25) NOT NULL DEFAULT '' COMMENT 'Код groupCode для NG::Mailer',
`mail_from` VARCHAR(50) NOT NULL DEFAULT '' COMMENT 'Заголовок From:',
`test_rcpt_data` VARCHAR(1000) NOT NULL COMMENT 'Тестовый набор данных для layout',
`lettersize_limit` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Максимальный размер рассылаемого письма'
);

CREATE TABLE `ng_mailing` (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`subject` VARCHAR(512) NOT NULL COMMENT 'Наименование контента/Subject рассылки',
`html_content` TEXT NOT NULL COMMENT 'Рассылаемый HTML',
`plain_content` TEXT NOT NULL COMMENT 'Рассылаемый Plain-контент',
`date_add` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
`status` TINYINT UNSIGNED NOT NULL DEFAULT '1',
`total` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Количество получателей',
`progress` INT UNSIGNED NOT NULL DEFAULT '0',
`date_end` DATETIME NOT NULL,
`date_begin` DATETIME NOT NULL COMMENT 'Дата-время отправки первой пачки, т.е. перехода в статус 3',
`module` VARCHAR(25) NOT NULL COMMENT 'Код модуля генератора контента',
`contentid` VARCHAR(50) NOT NULL COMMENT 'Идентификатор контента в генераторе',
`type` MEDIUMINT UNSIGNED NOT NULL COMMENT 'Код типа рассылки',
`send_after` DATETIME NOT NULL COMMENT 'Поле даты отложенной отправки',
`lettersize` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Размер рассылаемого писма, байт'
);

ALTER TABLE `ng_mailing` ADD UNIQUE  (`module`, `contentid`);


CREATE TABLE `ng_mailing_recipients` (
`mailing_id` INT UNSIGNED NOT NULL,
`segment` INT UNSIGNED NOT NULL,
`email` VARCHAR(150) NOT NULL,
`fio` VARCHAR(150) NOT NULL,
`data` VARCHAR(1000) NOT NULL
);

ALTER TABLE `ng_mailing_recipients` ADD INDEX  (`mailing_id`, `segment`);
ALTER TABLE `ng_mailing_recipients` ADD UNIQUE  (`mailing_id`, `email`);


CREATE TABLE `ng_mailing_rtf_images` (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`parent_id` INT UNSIGNED NOT NULL,
`subpage` SMALLINT UNSIGNED NOT NULL,
`filename` VARCHAR( 512 ) NOT NULL
);
