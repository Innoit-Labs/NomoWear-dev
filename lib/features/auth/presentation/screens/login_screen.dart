import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nomowear/core/app_export.dart';
import 'package:nomowear/features/auth/presentation/bloc/login_bloc.dart';
import 'package:nomowear/features/auth/presentation/bloc/login_event.dart';
import 'package:nomowear/features/auth/presentation/bloc/login_state.dart';
import 'package:nomowear/features/auth/presentation/models/otp_screen_args.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginBloc(),
      child: BlocConsumer<LoginBloc, LoginState>(
        listenWhen: (previous, current) =>
            current.otpSession != null && previous.otpSession != current.otpSession,
        listener: (context, state) {
          final session = state.otpSession;
          if (session == null) return;
          Navigator.pushNamed(
            context,
            AppRoutes.otpScreen,
            arguments: OtpScreenArgs(
              mobileNumber: session.mobileNumber,
              customerId: session.customerId,
              userToken: session.userToken,
            ),
          );
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColours.black,
            body: SafeArea(
              child: SingleChildScrollView(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
                  width: double.maxFinite,
                  child: Column(
                    children: [
                      SizedBox(height: 100.h),
                      // Logo
                      Center(
                        child: AppLogo(
                          height: 180.h,
                          width: 180.w,
                          showTagline: false,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      SizedBox(height: 30.h),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Login with Mobile Number",
                          style: CustomTextStyles.openSansBold.copyWith(fontSize: 14),
                        ),
                      ),


                      SizedBox(height: 12.h),
                      TextField(
                        onChanged: (value) {
                          context.read<LoginBloc>().add(MobileNumberChangedEvent(value));
                        },
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: InputDecoration(
                          hintText: "Mobile Number",
                          hintStyle: CustomTextStyles.openSansRegular.copyWith(fontSize: 16,color: AppColours.hintcolor),

                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColours.primary),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColours.primary, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "We will send an OTP to this mobile number.",
                          style: CustomTextStyles.openSansSemiBold.copyWith(color: AppColours.hintcolor,fontSize: 12),

                        ),
                      ),
                      if (state.errorMessage != null) ...[
                        SizedBox(height: 8.h),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            state.errorMessage!,
                            style: CustomTextStyles.openSansSemiBold.copyWith(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 12.h),
                      SizedBox(
                        width: double.maxFinite,
                        height: 44.h,
                        child: ElevatedButton(
                          onPressed: state.isButtonEnabled && !state.isLoading
                              ? () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  context.read<LoginBloc>().add(LoginSubmitEvent());
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColours.primary,
                            disabledBackgroundColor: const Color(0xFF8E836F),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
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
                                  "LOGIN",
                                  style: CustomTextStyles.montserratBold.copyWith(
                                    color: state.isButtonEnabled
                                        ? Colors.black
                                        : Colors.black.withOpacity(0.5),
                                    fontSize: 18.fSize,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: 132.h),

                      const _LoginTermsFooter(),
                      SizedBox(height: 24.h),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoginTermsFooter extends StatefulWidget {
  const _LoginTermsFooter();

  @override
  State<_LoginTermsFooter> createState() => _LoginTermsFooterState();
}

class _LoginTermsFooterState extends State<_LoginTermsFooter> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer();
    _privacyTap = TapGestureRecognizer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _termsTap.onTap = () => Navigator.pushNamed(context, AppRoutes.termsConditionsScreen);
    _privacyTap.onTap = () => Navigator.pushNamed(context, AppRoutes.privacyPolicyScreen);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = CustomTextStyles.openSansRegular.copyWith(
      fontSize: 12.fSize,
      color: AppColours.secondary.withValues(alpha: 0.75),
      height: 1.45,
    );
    final linkStyle = CustomTextStyles.openSansRegular.copyWith(
      fontSize: 12.fSize,
      color: AppColours.primary,
      height: 1.45,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'By continuing, you agree to our '),
                TextSpan(
                  text: 'Terms & conditions',
                  style: linkStyle,
                  recognizer: _termsTap,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: linkStyle,
                  recognizer: _privacyTap,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
