import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/features/auth/presentation/password_change_screen.dart';
import 'package:attendance_app/features/home/presentation/home_screen.dart';

/// One entry per predefined system role, mirrored from
/// `MigrationHelpers._kRoles` / `Role._kPredefined` so every role in the
/// system gets its own quick-login button in debug builds.
class _DevRole {
  const _DevRole({required this.code, required this.label});
  final String code;
  final String label;
}

const List<_DevRole> _kDevQuickLoginRoles = [
  _DevRole(code: 'admin', label: 'Admin'),
  _DevRole(code: 'principal', label: 'Principal'),
  _DevRole(code: 'vice_principal', label: 'Vice Principal'),
  _DevRole(code: 'hod', label: 'HOD'),
  _DevRole(code: 'teacher', label: 'Teacher'),
  _DevRole(code: 'student', label: 'Student'),
  _DevRole(code: 'parent', label: 'Parent'),
  _DevRole(code: 'accountant', label: 'Accountant'),
  _DevRole(code: 'lab_in_charge', label: 'Lab In-Charge'),
  _DevRole(code: 'assistant', label: 'Assistant'),
];

/// Professional Login Screen backed by database authentication.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _identifierController;
  late final TextEditingController _passwordController;

  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Forgot-password (OTP recovery) flow state
  int _resetStage = 0; // 0: ask email, 1: enter OTP + new password
  String? _resetError;
  bool _resetSending = false;
  bool _resetSubmitting = false;
  late final TextEditingController _resetEmailController;
  late final TextEditingController _resetOtpController;
  late final TextEditingController _resetPasswordController;
  late final TextEditingController _resetConfirmController;

  @override
  void initState() {
    super.initState();
    _identifierController = TextEditingController();
    _passwordController = TextEditingController();
    _resetEmailController = TextEditingController();
    _resetOtpController = TextEditingController();
    _resetPasswordController = TextEditingController();
    _resetConfirmController = TextEditingController();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _resetEmailController.dispose();
    _resetOtpController.dispose();
    _resetPasswordController.dispose();
    _resetConfirmController.dispose();
    super.dispose();
  }

  /// Quick sign-in as [roleCode] via the shared dev bypass path. Uses the
  /// exact same state initialization as production login (AuthStore.login),
  /// so PermissionService / PermissionGuard resolve the role's real grants.
  ///
  /// Wrapped in try/catch/finally so [_isLoading] is always reset Ã¢â‚¬â€ even when
  /// [devBypassLoginForRole] throws Ã¢â‚¬â€ preventing the login spinner from
  /// spinning forever. No Supabase network calls are awaited here; everything
  /// is local SQLite / secure storage.
  Future<void> _handleDevLogin(String roleCode) async {
    debugPrint('[DEV_LOGIN] 1. Starting quick sign-in for role: $roleCode');

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authStore = context.read<AuthStore>();

    setState(() => _isLoading = true);

    try {
      debugPrint('[DEV_LOGIN] 2. Calling authStore.devBypassLoginForRole($roleCode)');
      final user = await authStore.devBypassLoginForRole(roleCode);
      debugPrint(
        '[DEV_LOGIN] 3. User resolved: ${user.displayName} (${user.role.value}) id=${user.id}',
      );

      if (!mounted) return;

      debugPrint('[DEV_LOGIN] 4. Showing sign-in snackbar');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ã¢Å¡Â¡ Signed in as ${user.displayName} (${user.role.value})'),
          backgroundColor: Colors.teal.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (!mounted) return;

      debugPrint('[DEV_LOGIN] 5. Navigating to HomeScreen');
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const HomeScreen(),
        ),
      );
      debugPrint('[DEV_LOGIN] 6. Navigation to HomeScreen triggered');
    } catch (e, stackTrace) {
      debugPrint('[DEV_LOGIN] ERROR during dev sign-in: $e');
      debugPrint('[DEV_LOGIN] StackTrace: $stackTrace');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Dev sign-in failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      debugPrint('[DEV_LOGIN] finally: resetting _isLoading = false');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text;

    setState(() => _isLoading = true);

    final identifier = _identifierController.text.trim();
    final authStore = context.read<AuthStore>();
    final user = await authStore.login(identifier, password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (user != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome back, ${user.displayName}!'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (!mounted) return;

      // Default-password accounts must change their password before the
      // dashboard becomes accessible.
      if (authStore.requirePasswordChange) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const PasswordChangeScreen(),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const HomeScreen(),
          ),
        );
      }
    } else {
      if (kDebugMode && identifier.toLowerCase() == 'admin') {
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        final devUser = await authStore.devBypassLogin();
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Ã¢Å¡Â¡ Signed in as ${devUser.displayName} (Dev Bypass)'),
            backgroundColor: Colors.teal.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
        return;
      }
      setState(() {
        _errorMessage = authStore.lastAuthError;
      });
    }
  }

  /// Opens the email-based OTP password-recovery dialog.
  Future<void> _showForgotPasswordDialog() async {
    _resetStage = 0;
    _resetError = null;
    _resetEmailController.clear();
    _resetOtpController.clear();
    _resetPasswordController.clear();
    _resetConfirmController.clear();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot password?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_resetStage == 0) ..._resetEmailStep(),
              if (_resetStage == 1) ..._resetOtpStep(),
              if (_resetError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resetError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_resetStage == 0) ...[
            TextButton(
              onPressed:
                  _resetSending ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _resetSending ? null : _handleSendCode,
              child: _resetSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send code'),
            ),
          ] else ...[
            TextButton(
              onPressed:
                  _resetSubmitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _resetSubmitting ? null : _handleReset,
              child: _resetSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reset password'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleSendCode() async {
    final email = _resetEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _resetError = 'Enter your email address.');
      return;
    }
    setState(() {
      _resetSending = true;
      _resetError = null;
    });
    final authStore = context.read<AuthStore>();
    final sent = await authStore.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _resetSending = false);
    if (kDebugMode) {
      debugPrint(
        'Password-reset OTP for $email: ${authStore.lastSentOtp}',
      );
    }
    if (sent) {
      setState(() => _resetStage = 1);
    } else {
      // Generic message either way: avoids enumerating accounts via recovery.
      setState(() {
        _resetError =
            'If an account exists with this email, a one-time code was sent.';
      });
    }
  }

  Future<void> _handleReset() async {
    final otp = _resetOtpController.text.trim();
    final password = _resetPasswordController.text;
    final confirm = _resetConfirmController.text;
    if (otp.length != 6 || otp.contains(RegExp(r'[^0-9]'))) {
      setState(() => _resetError = 'Enter the 6-digit code.');
      return;
    }
    if (password.isEmpty || password != confirm) {
      setState(() => _resetError = 'Passwords must match and not be empty.');
      return;
    }
    setState(() {
      _resetSubmitting = true;
      _resetError = null;
    });
    final ok = await context.read<AuthStore>().resetPasswordWithOtp(
          _resetEmailController.text.trim(),
          otp,
          password,
        );
    if (!mounted) return;
    setState(() => _resetSubmitting = false);
    if (ok) {
      Navigator.of(context).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset successfully. Please sign in.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _resetError = 'Invalid or expired code. Request a new one.');
    }
  }

  List<Widget> _resetEmailStep() => [
        const Text('Enter the email address of your account.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _resetEmailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleSendCode(),
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            hintText: 'email@institute.edu',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
      ];

  List<Widget> _resetOtpStep() => [
        const Text('Enter the 6-digit code sent to your email.'),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('otpField'),
          controller: _resetOtpController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: '123456',
            prefixIcon: Icon(Icons.lock_outline_rounded),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('resetPasswordField'),
          controller: _resetPasswordController,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'New password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('resetConfirmField'),
          controller: _resetConfirmController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleReset(),
          decoration: const InputDecoration(
            hintText: 'Confirm new password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand / Logo Section
                    Center(
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colorScheme.primary,
                              colorScheme.primaryContainer,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: 36,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // App Title & Subtitle
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to manage institute attendance',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),


                    // Error Message banner if any
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Identifier field Ã¢â‚¬â€ accepts username, roll number, or
                    // employee ID interchangeably.
                    Text(
                      'Username / Roll No / Employee ID',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('identifierField'),
                      controller: _identifierController,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText:
                            'Enter your username, roll number, or employee ID',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Identifier is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    Text(
                      'Password',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: const Key('passwordField'),
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          key: const Key('togglePasswordVisibility'),
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Remember Me & Forgot Password row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _rememberMe = !_rememberMe;
                                });
                              },
                              child: Text(
                                'Remember me',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          key: const Key('forgotPasswordButton'),
                          onPressed: _isLoading ? null : _showForgotPasswordDialog,
                          child: const Text('Forgot password?'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Sign In Button
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        key: const Key('signInButton'),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      Text(
                        'QUICK DEV SIGN-IN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _kDevQuickLoginRoles.map((devRole) {
                          return OutlinedButton(
                            key: Key('devBypassButton_${devRole.code}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.tertiary,
                              side: BorderSide(
                                color: colorScheme.tertiary.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _isLoading
                                ? null
                                : () => _handleDevLogin(devRole.code),
                            child: Text(
                              devRole.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Footer / Help info
                    Center(
                      child: Text(
                        'School & Institute Attendance',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}