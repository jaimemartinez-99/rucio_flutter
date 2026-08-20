import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/vocablingo_service.dart';

class AppAuthState {
  final User? user;
  final bool isLoading;

  const AppAuthState({this.user, this.isLoading = false});

  AppAuthState copyWith({User? user, bool? isLoading}) {
    return AppAuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AppAuthState> {
  StreamSubscription? _authSubscription;
  final VocablingoService _vocablingo = VocablingoService();

  AuthNotifier() : super(const AppAuthState(isLoading: true)) {
    _init();
  }

  Future<void> _init() async {
    final client = Supabase.instance.client;
    try {
      final response = await client.auth.refreshSession();
      state = AppAuthState(user: response.session?.user);
    } catch (_) {
      state = const AppAuthState();
    }

    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      state = AppAuthState(user: session?.user);
    });
  }

  Future<void> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      _vocablingo.signIn(email, password).catchError((_) {});
    } catch (_) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> signUp(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      await Supabase.instance.client.auth
          .signUp(email: email, password: password);
      _vocablingo.signIn(email, password).catchError((_) {});
    } catch (_) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _vocablingo.signOut().catchError((_) {});
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final authProvider =
    StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  return AuthNotifier();
});
