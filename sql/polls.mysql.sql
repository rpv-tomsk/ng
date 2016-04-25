CREATE TABLE IF NOT EXISTS `polls` (
  `id` int(32) unsigned NOT NULL AUTO_INCREMENT,
  `question` varchar(255) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `visible` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `rotate` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `check_ip` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `multichoice` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `vote_cnt` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `page_id` int(11) DEFAULT NULL,
  `image` varchar(250) DEFAULT NULL COMMENT 'Изображение баннера в слайдер',
  PRIMARY KEY (`id`)
) ENGINE=MyISAM  DEFAULT CHARSET=cp1251;

CREATE TABLE IF NOT EXISTS `polls_answers` (
  `id` int(32) unsigned NOT NULL AUTO_INCREMENT,
  `polls_id` int(32) unsigned NOT NULL,
  `answer` varchar(255) NOT NULL,
  `def` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `vote_cnt` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `polls_id` (`polls_id`)
) ENGINE=MyISAM DEFAULT CHARSET=cp1251;


CREATE TABLE "polls_uid_votes" (
  `polls_id` int(11) unsigned NOT NULL COMMENT 'Код вопроса',
  `utime` int(11) unsigned NOT NULL COMMENT 'UUID - первая часть. Время создания UUID.',
  `uid` char(8) NOT NULL COMMENT 'UUID пользователя, вторая часть.',
  `ip` varchar(15) NOT NULL COMMENT 'IP голосования за вопрос',
  `atime` int(10) unsigned NOT NULL COMMENT 'Время голосования за вопрос',
  UNIQUE KEY `polls_id` (`polls_id`,`utime`,`uid`)
) ENGINE=MyISAM DEFAULT CHARSET=cp1251;

CREATE TABLE IF NOT EXISTS `polls_ip` (
  `polls_id` int(32) unsigned NOT NULL,
  `ip` char(16) NOT NULL,
  UNIQUE KEY `polls_id` (`polls_id`,`ip`)
) ENGINE=MyISAM;
