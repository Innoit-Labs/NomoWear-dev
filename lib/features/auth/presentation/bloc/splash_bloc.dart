import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/app_version_gate.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/core/services/firebase_messaging_service.dart';
import 'package:nomowear/core/services/session_cleanup.dart';
import 'package:nomowear/features/auth/presentation/bloc/splash_event.dart';
import 'package:nomowear/features/auth/presentation/bloc/splash_state.dart';
import 'package:nomowear/features/profile/data/profile_repository.dart';

class SplashBloc extends Bloc<SplashEvent, SplashState> {
  static const Duration minSplashDuration = Duration(seconds: 3);

  final AuthStorage _authStorage;
  final ProfileRepository _profileRepository;

  SplashBloc({
    AuthStorage? authStorage,
    ProfileRepository? profileRepository,
  })  : _authStorage = authStorage ?? AuthStorage(),
        _profileRepository = profileRepository ?? ProfileRepository(),
        super(SplashInitial()) {
    on<LoadSplashEvent>(_onLoadSplash);
  }

  Future<void> _onLoadSplash(
    LoadSplashEvent event,
    Emitter<SplashState> emit,
  ) async {
    final startedAt = DateTime.now();

    // New APK / build number change → wipe previous user's local data.
    final versionForcedLogout =
        await AppVersionGate.ensureFreshInstallSession();

    await _authStorage.logStoredToken(source: 'splash');

    var destination = SplashDestination.login;

    // After a version wipe (or if never logged in), always go to Login.
    if (!versionForcedLogout) {
      final isLoggedIn = await _authStorage.isLoggedIn();
      if (isLoggedIn) {
        destination = SplashDestination.home;
        unawaited(FirebaseMessagingService.instance.sendTokenToServer());
        try {
          await _profileRepository.getProfile(forceRefresh: true);
        } on ApiException catch (e) {
          if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
            // Invalid token or session (e.g. account deleted) — full local wipe, then Login.
            await SessionCleanup.clearUserSession();
            destination = SplashDestination.login;
          }
        } catch (_) {
          // Continue to home even if profile prefetch fails (network blip).
        }
      }
    }

    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minSplashDuration) {
      await Future.delayed(minSplashDuration - elapsed);
    }

    emit(SplashLoaded(destination));
  }
}
