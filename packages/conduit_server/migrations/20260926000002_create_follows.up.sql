-- Who follows whom.
CREATE TABLE follows (
  follower_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  followee_id BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

-- The feed asks "who does this user follow"; the primary key answers that.
-- A profile page asks the reverse, which needs its own index.
CREATE INDEX follows_followee ON follows (followee_id);
