CREATE TABLE "polls" (
  "id" SERIAL,
  "question" VARCHAR(255) NOT NULL,
  "start_date" DATE NOT NULL,
  "end_date" DATE,
  "visible" SMALLINT DEFAULT 0 NOT NULL,
  "rotate" SMALLINT DEFAULT 0 NOT NULL,
  "check_ip" SMALLINT DEFAULT 0 NOT NULL,
  "multichoice" SMALLINT DEFAULT 0 NOT NULL,
  "vote_cnt" INTEGER DEFAULT 0 NOT NULL,
  CONSTRAINT "polls_pkey" PRIMARY KEY("id")
) WITHOUT OIDS;

CREATE TABLE "polls_answers" (
  "id" SERIAL,
  "polls_id" INTEGER NOT NULL,
  "answer" VARCHAR(512) NOT NULL,
  "def" SMALLINT DEFAULT 0 NOT NULL,
  "vote_cnt" INTEGER DEFAULT 0 NOT NULL,
  CONSTRAINT "poll_variants_pkey" PRIMARY KEY("id"),
  CONSTRAINT "polls_answers_fk" FOREIGN KEY ("polls_id")
    REFERENCES "polls"("id")
    ON DELETE CASCADE
    ON UPDATE CASCADE
    NOT DEFERRABLE
) WITHOUT OIDS;

CREATE INDEX "polls_answers_idx" ON "polls_answers"
  USING btree ("polls_id");

CREATE TABLE "polls_ip" (
  "polls_id" INTEGER NOT NULL,
  "ip" VARCHAR(16) NOT NULL,
  CONSTRAINT "polls_ip_fk" FOREIGN KEY ("polls_id")
    REFERENCES "polls"("id")
    ON DELETE CASCADE
    ON UPDATE CASCADE
    NOT DEFERRABLE
) WITHOUT OIDS;

CREATE UNIQUE INDEX "polls_ip_idx" ON "polls_ip"
  USING btree ("polls_id", "ip");

CREATE TABLE "polls_uid_votes" (
  "polls_id" INTEGER NOT NULL,
  "utime" INTEGER NOT NULL,
  "uid" CHAR(8) NOT NULL,
  "ip" INET NOT NULL,
  "atime" INTEGER NOT NULL,
  CONSTRAINT "polls_uid_votes_fk" FOREIGN KEY ("polls_id")
    REFERENCES "polls"("id")
    ON DELETE CASCADE
    ON UPDATE CASCADE
    NOT DEFERRABLE
) WITH OIDS;

COMMENT ON COLUMN "polls_uid_votes"."polls_id"
IS ' од вопроса';

COMMENT ON COLUMN "polls_uid_votes"."utime"
IS 'UUID - перва€ часть. ¬рем€ создани€ UUID.';

COMMENT ON COLUMN "polls_uid_votes"."uid"
IS 'UUID пользовател€, втора€ часть.';

COMMENT ON COLUMN "polls_uid_votes"."ip"
IS 'IP голосовани€ за вопрос';

COMMENT ON COLUMN "polls_uid_votes"."atime"
IS '¬рем€ голосовани€ за вопрос';

CREATE UNIQUE INDEX "polls_uid_votes_idx" ON "polls_uid_votes"
  USING btree ("polls_id", "utime", "uid");
