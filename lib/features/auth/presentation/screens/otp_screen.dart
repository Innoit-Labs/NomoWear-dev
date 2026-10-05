import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/auth/presentation/bloc/otp_bloc.dart';
import 'package:nomowear/features/auth/presentation/bloc/otp_event.dart';
import 'package:nomowear/features/auth/presentation/bloc/otp_state.dart';
import 'package:nomowear/features/auth/presentation/models/otp_screen_args.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({Key? key}) : super(key: key);

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  @override
  void initState() {
    super.initState();
    // Request focus for the first field after the screen is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _clearControllers() {
    for (var controller in _controllers) {
      controller.clear();
    }
    // Set focus back to the first text field
    if (_focusNodes.isNotEmpty) {
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _navigateAfterVerifySuccess(BuildContext context) async {
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.homeScreen,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! OtpScreenArgs) {
      return Scaffold(
        backgroundColor: AppColours.black,
        body: Center(
          child: Text(
            'Invalid session. Please login again.',
            style: CustomTextStyles.openSansRegular.copyWith(color: Colors.white70),
          ),
        ),
      );
    }

    return BlocProvider(
      create: (context) => OtpBloc(
        mobileNumber: args.mobileNumber,
        customerId: args.customerId,
        userToken: args.userToken,
        initialOtp: args.otp,
      ),
      child: BlocListener<OtpBloc, OtpState>(
        listenWhen: (previous, current) =>
            !previous.isSuccess && current.isSuccess,
        listener: (context, state) {
          _navigateAfterVerifySuccess(context);
        },
        child: BlocListener<OtpBloc, OtpState>(
          listenWhen: (previous, current) =>
              previous.isResending && !current.isResending,
          listener: (context, state) {
            if (state.errorMessage != null &&
                !state.hasError &&
                !state.isResending) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage!)),
              );
              return;
            }
            if (!state.isResending && state.errorMessage == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('OTP resent successfully')),
              );
            }
          },
          child: BlocBuilder<OtpBloc, OtpState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColours.black,
            body: SafeArea(
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  width: double.maxFinite,
                  child: Column(
                    children: [
                      SizedBox(height: 100.h),
                      AppLogo(
                        height: 180.h,
                        width: 180.w,
                        showTagline: false,
                      ),

                      SizedBox(height: 10.h),
                      Text(
                        "Enter the 6-digit code sent to\n+91 ${args.mobileNumber}",
                        textAlign: TextAlign.center,
                        style: CustomTextStyles.openSansBold.copyWith(fontSize: 14),
                      ),
                      if (state.devOtp != null && state.devOtp!.isNotEmpty) ...[
                        SizedBox(height: 12.h),
                        Text(
                          'OTP: ${state.devOtp}',
                          textAlign: TextAlign.center,
                          style: CustomTextStyles.openSansSemiBold.copyWith(
                            fontSize: 16,
                            color: AppColours.primary,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                      SizedBox(height: 40.h),
                      // OTP Boxes Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          6,
                          (index) => _buildOtpBox(context, index, state),
                        ),
                      ),
                      SizedBox(height: 15.h),
                      
                      // DYNAMIC LAYOUT AREA
                      if (!state.hasError) ...[
                        // NORMAL STATE
                        Align(
                          alignment: Alignment.centerLeft,
                          child: state.secondsRemaining > 0
                              ? Text(
                                  "OTP expires in ${state.secondsRemaining} seconds",
                                  style: CustomTextStyles.openSansSemiBold.copyWith(fontSize: 14,color: AppColours.primary),
                                )
                              : Row(
                                  children: [
                                    Text(
                                      "Didn’t receive the code? ",
                                      style: CustomTextStyles.openSansRegular.copyWith(color: AppColours.hintcolor,fontSize: 14),
                                    ),
                                    _buildResendText(context, state),
                                  ],
                                ),
                        ),
                        SizedBox(height: 24.h),
                        _buildVerifyButton(context, state),
                      ] else ...[
                        // ERROR STATE
                        SizedBox(height: 40.h),
                        _buildVerifyButton(context, state),
                        SizedBox(height: 20.h),
                        _buildResendText(context, state),
                        SizedBox(height: 40.h),
                        _buildErrorBox(context, state),
                      ],
                      SizedBox(height: 40.h),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
          ),
        ),
      ),
    );
  }

  Widget _buildResendText(BuildContext context, OtpState state) {
    if (state.isResending) {
      return Text(
        "Sending...",
        style: CustomTextStyles.openSansSemiBold.copyWith(
          fontSize: 14,
          color: AppColours.primary,
        ),
      );
    }

    return GestureDetector(
      onTap: state.secondsRemaining == 0
          ? () {
              _clearControllers();
              context.read<OtpBloc>().add(ResendOtpEvent());
            }
          : null,
      child: Text(
        "Resend OTP",
        style: CustomTextStyles.openSansSemiBold.copyWith(
          fontSize: 14,
          color: state.secondsRemaining == 0
              ? AppColours.primary
              : AppColours.primary.withOpacity(0.4),
        ),
      ),
    );
  }

  Widget _buildVerifyButton(BuildContext context, OtpState state) {
    return SizedBox(
      width: double.maxFinite,
      height: 44.h,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColours.primary,
          disabledBackgroundColor: Color(0x99F5E6C8).withOpacity(0.4),

            shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: (state.isButtonEnabled && !state.isLoading)
            ? () {
                context.read<OtpBloc>().add(VerifyOtpEvent());
              }
            : null,
        child: state.isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            : Text(
                "VERIFY",
                style: CustomTextStyles.montserratBold.copyWith(
                  color: state.isButtonEnabled ? Colors.black : Colors.black,

                  fontSize: 16.fSize,
                  letterSpacing: 1.6,

                ),
              ),
      ),
    );
  }

  Widget _buildErrorBox(BuildContext context, OtpState state) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: AppColours.primary),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColours.primary, size: 28),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              state.errorMessage ??
                  "You have entered the wrong otp\nPlease try again.",
              style: CustomTextStyles.montserratBold.copyWith(
                color: AppColours.primary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpBox(BuildContext context, int index, OtpState state) {
    return Container(
      width: 48.w,
      height: 60.h,
      alignment: Alignment.center, // 🔥 important

      decoration: BoxDecoration(
        color: const Color(0xFF1A1D21),
        border: Border.all(color: AppColours.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        onChanged: (value) {
          String currentOtp = "";
          for (var controller in _controllers) {
            currentOtp += controller.text;
          }
          context.read<OtpBloc>().add(OtpChangedEvent(currentOtp));
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: TextStyle(
          color: state.hasError ? Colors.red : AppColours.primary,
          fontSize: 22.fSize,
        ),
        decoration: InputDecoration(
          hintText: "-",
          hintStyle: TextStyle(color: AppColours.primary.withOpacity(0.5)),
          counterText: "",
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
