import 'package:conduit_shared/conduit_shared.dart';

import '../db/rows.dart';

// Database rows to wire models. The wire models come from `conduit_shared`,
// so these are the only place the server decides what a client sees.

User userOf(UserRow row, String token) => User(
      email: row.email,
      token: token,
      username: row.username,
      bio: row.bio,
      image: row.image,
    );

Profile profileOf(ProfileRow row) => Profile(
      username: row.username,
      bio: row.bio,
      image: row.image,
      following: row.following,
    );

/// A user seen by themselves: nobody follows themselves.
Profile ownProfileOf(UserRow row) => Profile(
      username: row.username,
      bio: row.bio,
      image: row.image,
      following: false,
    );

Profile _authorOf(ArticleRow row) => Profile(
      username: row.authorUsername,
      bio: row.authorBio,
      image: row.authorImage,
      following: row.authorFollowing,
    );

Article articleOf(ArticleRow row) => Article(
      slug: row.slug,
      title: row.title,
      description: row.description,
      body: row.body ?? '',
      tagList: row.tagList,
      createdAt: row.createdAt.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
      favorited: row.favorited,
      favoritesCount: row.favoritesCount,
      author: _authorOf(row),
    );

ArticlePreview previewOf(ArticleRow row) => ArticlePreview(
      slug: row.slug,
      title: row.title,
      description: row.description,
      tagList: row.tagList,
      createdAt: row.createdAt.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
      favorited: row.favorited,
      favoritesCount: row.favoritesCount,
      author: _authorOf(row),
    );

Comment commentOf(CommentRow row) => Comment(
      id: row.id,
      createdAt: row.createdAt.toUtc(),
      updatedAt: row.updatedAt.toUtc(),
      body: row.body,
      author: Profile(
        username: row.authorUsername,
        bio: row.authorBio,
        image: row.authorImage,
        following: row.authorFollowing,
      ),
    );
