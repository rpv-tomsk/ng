CREATE TABLE "public"."ng_mailing_types" (
  "type_id" SERIAL,
  "type_name" VARCHAR(50) NOT NULL,
  "subject_prefix" VARCHAR(15) DEFAULT ''::character varying NOT NULL,
  "subscribers_module" VARCHAR(25) DEFAULT ''::character varying NOT NULL,
  "subscribers_id" VARCHAR(25) DEFAULT ''::character varying NOT NULL,
  "segment_size" SMALLINT DEFAULT 100 NOT NULL,
  "layout" TEXT DEFAULT ''::text NOT NULL,
  "plain_layout" TEXT DEFAULT ''::text NOT NULL,
  "mailer_group_code" VARCHAR(15) DEFAULT ''::character varying NOT NULL,
  "mail_from" VARCHAR(50) DEFAULT ''::character varying NOT NULL,
  "test_rcpt_data" VARCHAR(1000) DEFAULT ''::character varying NOT NULL,
  "lettersize_limit" INTEGER DEFAULT 0 NOT NULL,
  CONSTRAINT "mailing_types_pkey" PRIMARY KEY("type_id")
) WITH OIDS;

COMMENT ON COLUMN "public"."ng_mailing_types"."type_id" IS 'Код типа рассылки';
COMMENT ON COLUMN "public"."ng_mailing_types"."type_name" IS 'Наименование типа рассылки';
COMMENT ON COLUMN "public"."ng_mailing_types"."subject_prefix" IS 'Префикс Subj-а рассылок';
COMMENT ON COLUMN "public"."ng_mailing_types"."subscribers_module" IS 'Код модуля списка подписчиков';
COMMENT ON COLUMN "public"."ng_mailing_types"."subscribers_id" IS 'Идентификатор группы в модуле списка подписчиков';
COMMENT ON COLUMN "public"."ng_mailing_types"."segment_size" IS 'Количество отправляемых писем за итерацию';
COMMENT ON COLUMN "public"."ng_mailing_types"."layout" IS 'Шаблон обрамления отправляемых писем';
COMMENT ON COLUMN "public"."ng_mailing_types"."plain_layout" IS 'Шаблон обрамления отправляемого Plain-текста';
COMMENT ON COLUMN "public"."ng_mailing_types"."mailer_group_code" IS 'Код groupCode для NG::Mailer';
COMMENT ON COLUMN "public"."ng_mailing_types"."mail_from" IS 'Заголовок From:';
COMMENT ON COLUMN "public"."ng_mailing_types"."test_rcpt_data" IS 'Тестовый набор данных для layout';
COMMENT ON COLUMN "public"."ng_mailing_types"."lettersize_limit" IS 'Максимальный размер рассылаемого письма';

CREATE TABLE "public"."ng_mailing" (
  "id" SERIAL,
  "subject" VARCHAR(512) NOT NULL,
  "html_content" TEXT,
  "plain_content" TEXT DEFAULT ''::text NOT NULL,
  "date_add" TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT now() NOT NULL,
  "status" SMALLINT DEFAULT 1 NOT NULL,
  "total" INTEGER DEFAULT 0 NOT NULL,
  "progress" INTEGER DEFAULT 0 NOT NULL,
  "date_end" TIMESTAMP WITHOUT TIME ZONE,
  "date_begin" TIMESTAMP WITHOUT TIME ZONE,
  "module" VARCHAR(25) NOT NULL,
  "contentid" VARCHAR(50) NOT NULL,
  "type" SMALLINT DEFAULT 1 NOT NULL,
  "send_after" TIMESTAMP(0) WITHOUT TIME ZONE DEFAULT now() NOT NULL,
  "lettersize" INTEGER DEFAULT 0 NOT NULL,
  CONSTRAINT "mailer_pkey" PRIMARY KEY("id"),
  CONSTRAINT "ng_mailing_fk" FOREIGN KEY ("type")
    REFERENCES "public"."ng_mailing_types"("type_id")
    ON DELETE RESTRICT
    ON UPDATE RESTRICT
    NOT DEFERRABLE
) WITHOUT OIDS;

COMMENT ON COLUMN "public"."ng_mailing"."subject" IS 'Наименование контента/Subject рассылки';
COMMENT ON COLUMN "public"."ng_mailing"."html_content" IS 'Рассылаемый HTML';
COMMENT ON COLUMN "public"."ng_mailing"."plain_content" IS 'Рассылаемый Plain-контент';
COMMENT ON COLUMN "public"."ng_mailing"."total" IS 'Количество получателей';
COMMENT ON COLUMN "public"."ng_mailing"."date_begin" IS 'Дата-время отправки первой пачки, т.е. перехода в статус 3';
COMMENT ON COLUMN "public"."ng_mailing"."module" IS 'Код модуля генератора контента';
COMMENT ON COLUMN "public"."ng_mailing"."contentid" IS 'Идентификатор контента в генераторе';
COMMENT ON COLUMN "public"."ng_mailing"."type" IS 'Код типа рассылки';
COMMENT ON COLUMN "public"."ng_mailing"."send_after" IS 'Поле даты отложенной отправки';
COMMENT ON COLUMN "public"."ng_mailing"."lettersize" IS 'Размер рассылаемого писма, байт';
CREATE INDEX "mailing_idx" ON "public"."ng_mailing"   USING btree ("module", "contentid");
COMMENT ON INDEX "public"."mailing_idx" IS 'Должен быть уникальным, но данные не позволяют';


CREATE TABLE "public"."ng_mailing_recipients" (
  "mailing_id" INTEGER NOT NULL, 
  "segment" INTEGER NOT NULL, 
  "email" VARCHAR(150) NOT NULL, 
  "fio" VARCHAR(150), 
  "data" VARCHAR(1000)
) WITH OIDS;

ALTER TABLE "public"."ng_mailing_recipients"
  ALTER COLUMN "segment" SET STATISTICS 0;

CREATE INDEX "mailing_recipients_idx" ON "public"."ng_mailing_recipients"
  USING btree ("mailing_id", "segment");

CREATE UNIQUE INDEX "mailing_recipients_idx1" ON "public"."ng_mailing_recipients"
  USING btree ("mailing_id", "email");
  
  
CREATE TABLE "public"."ng_mailing_rtf_images" (
  "id" SERIAL,
  "parent_id" INTEGER,
  "subpage" INTEGER,
  "filename" VARCHAR(512),
  CONSTRAINT "mailer_rtf_images_pkey" PRIMARY KEY("id")
) WITHOUT OIDS;
