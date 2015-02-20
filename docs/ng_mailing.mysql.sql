CREATE TABLE `ng_mailing_types` (
`type_id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY COMMENT '��� ���� ��������',
`type_name` VARCHAR(50) NOT NULL COMMENT '������������ ���� ��������',
`subject_prefix` VARCHAR(15) NOT NULL DEFAULT '' COMMENT '������� Subj-� ��������',
`subscribers_module` VARCHAR(25) NOT NULL DEFAULT '' COMMENT '��� ������ ������ �����������',
`subscribers_id` VARCHAR(25) NOT NULL DEFAULT '' COMMENT '������������� ������ � ������ ������ �����������',
`segment_size` SMALLINT UNSIGNED NOT NULL DEFAULT '100' COMMENT '���������� ������������ ����� �� ��������',
`layout` TEXT NOT NULL COMMENT '������ ���������� ������������ �����',
`plain_layout` TEXT NOT NULL COMMENT '������ ���������� ������������� Plain-������',
`mailer_group_code` VARCHAR(25) NOT NULL DEFAULT '' COMMENT '��� groupCode ��� NG::Mailer',
`mail_from` VARCHAR(50) NOT NULL DEFAULT '' COMMENT '��������� From:',
`test_rcpt_data` VARCHAR(1000) NOT NULL COMMENT '�������� ����� ������ ��� layout',
`lettersize_limit` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT '������������ ������ ������������ ������'
);

CREATE TABLE `ng_mailing` (
`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
`subject` VARCHAR(512) NOT NULL COMMENT '������������ ��������/Subject ��������',
`html_content` TEXT NOT NULL COMMENT '����������� HTML',
`plain_content` TEXT NOT NULL COMMENT '����������� Plain-�������',
`date_add` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
`status` TINYINT UNSIGNED NOT NULL DEFAULT '1',
`total` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT '���������� �����������',
`progress` INT UNSIGNED NOT NULL DEFAULT '0',
`date_end` DATETIME NOT NULL,
`date_begin` DATETIME NOT NULL COMMENT '����-����� �������� ������ �����, �.�. �������� � ������ 3',
`module` VARCHAR(25) NOT NULL COMMENT '��� ������ ���������� ��������',
`contentid` VARCHAR(50) NOT NULL COMMENT '������������� �������� � ����������',
`type` MEDIUMINT UNSIGNED NOT NULL COMMENT '��� ���� ��������',
`send_after` DATETIME NOT NULL COMMENT '���� ���� ���������� ��������',
`lettersize` INT UNSIGNED NOT NULL DEFAULT '0' COMMENT '������ ������������ �����, ����'
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
