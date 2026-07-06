/// State union cho `authStateProvider` (spec-sprint-3 "State Management":
/// "anonymous / authenticated(user)").
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/auth_user.dart';

part 'auth_state.freezed.dart';

@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.anonymous() = AuthAnonymous;
  const factory AuthState.authenticated(AuthUser user) = AuthAuthenticated;
}
