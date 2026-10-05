import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/network/api_exception.dart';
import 'package:nomowear/core/services/auth_storage.dart';
import 'package:nomowear/core/services/firebase_messaging_service.dart';
import 'package:nomowear/features/auth/data/auth_repository.dart';
import 'package:nomowear/features/auth/presentation/bloc/otp_event.dart';
import 'package:nomowear/features/auth/presentation/bloc/otp_state.dart';
import 'package:nomowear/features/profile/data/profile_completion_helper.dart';

class OtpBloc extends Bloc<OtpEvent, OtpState> {
  final AuthRepository _authRepository;
  final AuthStorage _authStorage;
  final String mobileNumber;
  String customerId;
  String userToken;

  Timer? _timer;

  OtpBloc({
    required this.mobileNumber,
    required this.customerId,
    required this.userToken,
    String? initialOtp,
    AuthRepository? authRepository,
    AuthStorage? authStorage,
  })  : _authRepository = authRepository ?? AuthRepository(),
        _authStorage = authStorage ?? AuthStorage(),
        super(OtpState(secondsRemaining: 30, devOtp: initialOtp)) {
    on<OtpChangedEvent>(_onOtpChanged);
    on<VerifyOtpEvent>(_onVerifyOtp);
    on<ResendOtpEvent>(_onResendOtp);
    on<TimerTickEvent>(_onTimerTick);

    _startTimer(30);
  }

  void _startTimer(int seconds) {
    _timer?.cancel();

    var remaining = seconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remaining > 0) {
        remaining--;
        add(TimerTickEvent(remaining));
      } else {
        timer.cancel();
      }
    });
  }

  void _onTimerTick(TimerTickEvent event, Emitter<OtpState> emit) {
    emit(state.copyWith(secondsRemaining: event.secondsRemaining));
  }

  void _onOtpChanged(OtpChangedEvent event, Emitter<OtpState> emit) {
    emit(state.copyWith(
      otp: event.otp,
      isButtonEnabled: event.otp.length == 6,
      hasError: false,
      clearError: true,
    ));
  }

  Future<void> _onVerifyOtp(VerifyOtpEvent event, Emitter<OtpState> emit) async {
    if (!state.isButtonEnabled || state.isLoading) return;

    emit(state.copyWith(isLoading: true, hasError: false, clearError: true));

    try {
      final result = await _authRepository.verifyOtp(
        customerId: customerId,
        otp: state.otp,
        userToken: userToken,
      );

      await _authStorage.saveAuthenticatedSession(
        authToken: result.authToken,
        customerId: result.customer.id,
        mobileNumber: result.customer.mobile,
        profileComplete:
            ProfileCompletionHelper.isProfileComplete(result.customer),
      );

      // Register FCM token with backend
      unawaited(FirebaseMessagingService.instance.sendTokenToServer(
        authToken: result.authToken,
      ));

      debugPrint('════════ LOGIN AUTH TOKEN ════════');
      debugPrint('Token: ${result.authToken}');
      debugPrint('══════════════════════════════════');

      emit(state.copyWith(isSuccess: true, isLoading: false));
    } on ApiException catch (e) {
      emit(state.copyWith(
        hasError: true,
        isLoading: false,
        errorMessage: e.message,
      ));
    } catch (_) {
      emit(state.copyWith(
        hasError: true,
        isLoading: false,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  Future<void> _onResendOtp(ResendOtpEvent event, Emitter<OtpState> emit) async {
    if (state.isResending || state.isLoading) return;

    emit(state.copyWith(isResending: true, clearError: true));

    try {
      final result = await _authRepository.resendOtp(mobileNumber);

      if (result.customerId != null && result.customerId!.isNotEmpty) {
        customerId = result.customerId!;
      }
      if (result.userToken != null && result.userToken!.isNotEmpty) {
        userToken = result.userToken!;
      }

      await _authStorage.savePendingOtpSession(
        customerId: customerId,
        userToken: userToken,
        mobileNumber: mobileNumber,
      );

      emit(OtpState(
        otp: '',
        isButtonEnabled: false,
        secondsRemaining: 30,
        isResending: false,
        devOtp: result.otp,
      ));
      _startTimer(30);
    } on ApiException catch (e) {
      emit(state.copyWith(isResending: false, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        isResending: false,
        errorMessage: 'Failed to resend OTP. Please try again.',
      ));
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
