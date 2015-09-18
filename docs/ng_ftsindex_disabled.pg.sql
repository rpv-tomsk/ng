ALTER TABLE "public"."ng_ftsindex" ADD COLUMN "disabled" SMALLINT;
ALTER TABLE "public"."ng_ftsindex"  ALTER COLUMN "disabled" SET DEFAULT 0;
UPDATE "public"."ng_ftsindex" SET disabled = 0;
ALTER TABLE "public"."ng_ftsindex"  ALTER COLUMN "disabled" SET NOT NULL;
COMMENT ON COLUMN public.ng_ftsindex.disabled IS 'Отключено в структуре сайта';

#By page_id
UPDATE public.ng_ftsindex SET disabled = 1 WHERE page_id IN
(SELECT id FROM ng_sitestruct WHERE disabled <> 0);

#By link_id
#By ling_id + lang_id

#TODO: this.

