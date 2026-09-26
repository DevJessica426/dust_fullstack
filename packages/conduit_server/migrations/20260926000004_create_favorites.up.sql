-- Which users favorited which articles.
CREATE TABLE favorites (
  user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  article_id BIGINT NOT NULL REFERENCES articles (id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, article_id)
);

CREATE INDEX favorites_article ON favorites (article_id);
