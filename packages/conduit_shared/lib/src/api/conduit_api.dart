import 'package:dust_dart/http.dart';

import '../models/article.dart';
import '../models/comment.dart';
import '../models/profile.dart';
import '../models/tags.dart';
import '../models/user.dart';

part 'conduit_api.g.dart';

/// The whole RealWorld API, as a typed client.
///
/// Dust generates the implementation, so the browser and the server tests call
/// the same methods with the same models the server answers with. Paths are
/// appended to `Dio.options.baseUrl`, so point it at `https://host/api` or
/// pass `baseUrl`.
///
/// Authentication is a Dio interceptor rather than a parameter on every
/// method; see `ConduitClient`.
@HttpClient(generateTest: true)
abstract interface class ConduitApi {
  factory ConduitApi(Dio dio, {String? baseUrl}) = _$ConduitApi;

  // --- Users and authentication ---

  @POST('/users/login')
  Future<UserEnvelope> login(@Body() LoginRequest request);

  @POST('/users')
  Future<UserEnvelope> register(@Body() RegisterRequest request);

  @GET('/user')
  Future<UserEnvelope> currentUser();

  @PUT('/user')
  Future<UserEnvelope> updateUser(@Body() UpdateUserRequest request);

  // --- Profiles ---

  @GET('/profiles/{username}')
  Future<ProfileEnvelope> profile(@Path() String username);

  @POST('/profiles/{username}/follow')
  Future<ProfileEnvelope> follow(@Path() String username);

  @DELETE('/profiles/{username}/follow')
  Future<ProfileEnvelope> unfollow(@Path() String username);

  // --- Articles ---

  @GET('/articles')
  Future<ArticlesPage> articles({
    @Query('tag') String? tag,
    @Query('author') String? author,
    @Query('favorited') String? favorited,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/articles/feed')
  Future<ArticlesPage> feed({
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @GET('/articles/{slug}')
  Future<ArticleEnvelope> article(@Path() String slug);

  @POST('/articles')
  Future<ArticleEnvelope> createArticle(@Body() NewArticleRequest request);

  @PUT('/articles/{slug}')
  Future<ArticleEnvelope> updateArticle(
    @Path() String slug,
    @Body() UpdateArticleRequest request,
  );

  @DELETE('/articles/{slug}')
  Future<void> deleteArticle(@Path() String slug);

  // --- Favorites ---

  @POST('/articles/{slug}/favorite')
  Future<ArticleEnvelope> favorite(@Path() String slug);

  @DELETE('/articles/{slug}/favorite')
  Future<ArticleEnvelope> unfavorite(@Path() String slug);

  // --- Comments ---

  @GET('/articles/{slug}/comments')
  Future<CommentsList> comments(@Path() String slug);

  @POST('/articles/{slug}/comments')
  Future<CommentEnvelope> addComment(
    @Path() String slug,
    @Body() NewCommentRequest request,
  );

  @DELETE('/articles/{slug}/comments/{id}')
  Future<void> deleteComment(@Path() String slug, @Path() int id);

  // --- Tags ---

  @GET('/tags')
  Future<TagsList> tags();
}
