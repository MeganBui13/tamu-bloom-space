import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  // Stream of auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );

      final userId = response.user?.id;
      if (userId != null && response.session != null) {
        await _createProfileIfMissing(
          userId: userId,
          displayName: displayName,
          email: email,
        );
      }

      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      await _createProfileForAuthenticatedUser();
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  // Send password reset email
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://tamu-bloom-space.vercel.app/reset-password',
      );
    } catch (e) {
      rethrow;
    }
  }

  // Update password
  Future<UserResponse> updatePassword(String newPassword) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Get user profile
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createProfileIfMissing({
    required String userId,
    required String displayName,
    required String email,
  }) async {
    final existingProfile = await getUserProfile(userId);
    if (existingProfile != null) return;

    try {
      await _supabase.from('profiles').insert({
        'id': userId,
        'display_name': displayName,
        'email': email,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      if (error is PostgrestException &&
          error.message.toLowerCase().contains('row-level security')) {
        throw Exception(
          'Signup/login succeeded but profile creation failed because Supabase row-level security blocked the insert. '
          'Enable a profile INSERT policy that allows authenticated users to insert their own row with auth.uid() = id.',
        );
      }
      rethrow;
    }
  }

  Future<void> _createProfileForAuthenticatedUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final displayName = user.userMetadata?['display_name']?.toString() ?? user.email ?? '';
    final email = user.email ?? '';

    await _createProfileIfMissing(
      userId: user.id,
      displayName: displayName,
      email: email,
    );
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? bio,
    bool? hideActivity,
    bool? showOnlineStatus,
  }) async {
    try {
      final Map<String, dynamic> updates = {
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (displayName != null) updates['display_name'] = displayName;
      if (bio != null) updates['bio'] = bio;
      if (hideActivity != null) updates['hide_activity'] = hideActivity;
      if (showOnlineStatus != null) {
        updates['show_online_status'] = showOnlineStatus;
      }

      await _supabase.from('profiles').update(updates).eq('id', userId);
    } catch (e) {
      rethrow;
    }
  }

  // Save a post
  Future<void> savePost({
    required String userId,
    required String postId,
    required String postTitle,
    required String postContent,
  }) async {
    try {
      await _supabase.from('saved_posts').insert({
        'user_id': userId,
        'post_id': postId,
        'post_title': postTitle,
        'post_content': postContent,
        'saved_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      rethrow;
    }
  }

  // Get saved posts
  Future<List<Map<String, dynamic>>> getSavedPosts(String userId) async {
    try {
      final response = await _supabase
          .from('saved_posts')
          .select()
          .eq('user_id', userId)
          .order('saved_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      rethrow;
    }
  }

  // Remove saved post
  Future<void> removeSavedPost(String savedPostId) async {
    try {
      await _supabase.from('saved_posts').delete().eq('id', savedPostId);
    } catch (e) {
      rethrow;
    }
  }

  // Check if email exists
  Future<bool> checkEmailExists(String email) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id')
          .eq('email', email);
      return response.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
