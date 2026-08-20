import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isSignUp) {
        await ref.read(authProvider.notifier).signUp(email, password);
      } else {
        await ref.read(authProvider.notifier).signIn(email, password);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _toggleMode() {
    setState(() => _isSignUp = !_isSignUp);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0E17), Color(0xFF171421), Color(0xFF0F0E17)],
          ),
        ),
        child: Stack(
          children: [
            const _BackgroundGlow(
              alignment: Alignment(-1.15, -0.95),
              size: 270,
              color: Color(0x1FF2A65A),
            ),
            const _BackgroundGlow(
              alignment: Alignment(1.1, 0.95),
              size: 320,
              color: Color(0x12252336),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _LoginCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      isSignUp: _isSignUp,
                      isLoading: authState.isLoading,
                      obscurePassword: _obscurePassword,
                      isWide: screenWidth >= 600,
                      onSubmit: _submit,
                      onToggleMode: _toggleMode,
                      onTogglePasswordVisibility: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isSignUp,
    required this.isLoading,
    required this.obscurePassword,
    required this.isWide,
    required this.onSubmit,
    required this.onToggleMode,
    required this.onTogglePasswordVisibility,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isSignUp;
  final bool isLoading;
  final bool obscurePassword;
  final bool isWide;
  final VoidCallback onSubmit;
  final VoidCallback onToggleMode;
  final VoidCallback onTogglePasswordVisibility;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(isWide ? 40 : 28),
      decoration: BoxDecoration(
        color: const Color(0xF21A1827),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF252336)),
        boxShadow: const [
          BoxShadow(color: Color(0x70000000), blurRadius: 32, offset: Offset(0, 18)),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandMark(),
            const SizedBox(height: 28),
            Text(
              isSignUp ? 'Start your reading space' : 'Welcome back',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFE8E4F0),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isSignUp
                  ? 'Create an account to keep your library in sync.'
                  : 'Sign in to return to your library and reading progress.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF7C748E),
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Email is required';
                if (!value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: passwordController,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => onSubmit(),
              autofillHints: [
                if (isSignUp) AutofillHints.newPassword else AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: onTogglePasswordVisibility,
                  icon: Icon(
                    obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Password is required';
                if (value.length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: const Color(0xFF0F0E17),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                onPressed: isLoading ? null : onSubmit,
                child: isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Color(0xFF0F0E17),
                        ),
                      )
                    : Text(isSignUp ? 'Create account' : 'Sign in'),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: const [
                Expanded(child: Divider(color: Color(0xFF252336))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Color(0xFF7C748E))),
                ),
                Expanded(child: Divider(color: Color(0xFF252336))),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: isLoading ? null : onToggleMode,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE8E4F0),
                minimumSize: const Size.fromHeight(48),
              ),
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF7C748E)),
                  children: [
                    TextSpan(text: isSignUp ? 'Already have an account? ' : 'New to Rucio? '),
                    TextSpan(
                      text: isSignUp ? 'Sign in' : 'Create an account',
                      style: TextStyle(color: Color(0xFFF2A65A), fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFF252336),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF3B374E)),
        ),
        child: const Icon(Icons.auto_stories_rounded, color: Color(0xFFF2A65A), size: 36),
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.alignment, required this.size, required this.color});

  final Alignment alignment;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
