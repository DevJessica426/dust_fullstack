-- Users.
--
-- Uniqueness lives in the database, not in a SELECT before an INSERT: two
-- sign-ups racing for one username both pass a check-then-write, and only a
-- unique index stops the second. The handlers turn the resulting SQLSTATE 23505
-- into a 409 by constraint name, so the index names are part of the contract.
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
