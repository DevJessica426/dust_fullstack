-- The whole Conduit schema.
--
-- Uniqueness lives in the database, not in a SELECT before an INSERT: two
-- sign-ups racing for one username both pass a check-then-write, and only a
-- unique index stops the second. The handlers turn the resulting SQLSTATE 23505
-- into a 409 by constraint name, so the names below are part of the contract.
--
-- Timestamps default to now(), which is fixed for the whole statement, so a new
-- row's created_at and updated_at are equal. clock_timestamp() is read once
-- per column and can differ by a microsecond between the two.

CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL,
  email         TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  bio           TEXT,
  image         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Case-insensitive, so `Ada` cannot register next to `ada` and impersonate her.
CREATE UNIQUE INDEX users_username_key ON users (lower(username));
CREATE UNIQUE INDEX users_email_key ON users (lower(email));

CREATE TABLE follows (
  follower_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  followee_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

-- The feed asks "who does this user follow"; the primary key answers that.
-- A profile page asks the reverse, which needs its own index.
CREATE INDEX follows_followee ON follows (followee_id);

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

CREATE TABLE favorites (
  user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  article_id BIGINT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX favorites_article ON favorites (article_id);

CREATE TABLE comments (
  id         BIGSERIAL PRIMARY KEY,
  article_id BIGINT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  author_id  BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  body       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX comments_article ON comments (article_id, id DESC);
