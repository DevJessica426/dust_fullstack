-- Articles.
--
-- Tags are a TEXT[] on the article rather than a join table: an article owns a
-- short, ordered list, and PostgreSQL arrays keep the order the author gave.
-- The GIN index serves `tag_list @> ARRAY[$1]`, the "filter by tag" query.
CREATE TABLE articles (
  id          BIGSERIAL PRIMARY KEY,
  slug        TEXT NOT NULL CONSTRAINT articles_slug_key UNIQUE,
  title       TEXT NOT NULL,
  description TEXT NOT NULL,
  body        TEXT NOT NULL,
  tag_list    TEXT[] NOT NULL DEFAULT '{}',
  author_id   BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX articles_recent ON articles (created_at DESC, id DESC);
CREATE INDEX articles_author_recent ON articles (author_id, created_at DESC);
CREATE INDEX articles_tag_list ON articles USING GIN (tag_list);
