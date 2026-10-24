import 'package:flutter/material.dart';

import '../../config/supabase_config.dart';
import '../../constants/colors.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/customtextfield.dart';
import '../../widgets/detailstext1.dart';
import '../../state/session_scope.dart';

import '../home/homescreen.dart';
import 'authwidgets/auth_tab.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  bool _rememberMe = false;
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  /// This public application creates client accounts only. Lawyer onboarding
  /// belongs to the lawyer dashboard; owner provisioning is never public.
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;

  /// Shown inline under the fields; a SnackBar can be missed on a tall form.
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Starts from bottom
      end: Offset.zero, // Ends at its original position
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    _controller.forward(); // Start the animation
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Creates the Auth account and waits for its server-provisioned profile.
  /// An unconfirmed account stays on this screen with a confirmation message.
  Future<void> _handleSignup() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in your name, email and password.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _showMessage('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showMessage('Choose a password with at least 6 characters.');
      return;
    }
    if (password != confirm) {
      _showMessage('The passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final session = SessionScope.read(context);
    final ok = await session.register(
      name: name,
      email: email,
      password: password,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!ok) {
      final message = session.error ?? 'Registration failed. Please try again.';
      setState(() => _error = message);
      _showMessage(message);
      return;
    }

    // The account and its profile both exist. Replace the auth stack so the
    // back gesture cannot return to the sign-up form.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => HomePage()),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background color with News Wave text and image
          Container(
            width: double.infinity,
            color: AppColors.buttonColor,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 100), // Add some spacing from the top
                  Text1(
                    text1: 'Legal Services App',
                    color: Colors.white,
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
          // Main content
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          const Text1(
                            text1: 'SignUp',
                            size: 24,
                            color: AppColors.buttonColor,
                          ),
                          const SizedBox(height: 20),
                          if (!SupabaseConfig.enableClientSignup)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Client registration is temporarily unavailable until secure Supabase profile provisioning is deployed.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.deepOrange),
                              ),
                            ),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Create a client account',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _nameController,
                            label: 'Full name',
                            icon: Icons.person,
                          ),
                          CustomTextField(
                            controller: _emailController,
                            label: 'Email',
                            icon: Icons.email_outlined,
                          ),
                          // `obscureText` was never set here, so the password
                          // fields rendered in clear text. Both are obscured now.
                          CustomTextField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock,
                            icon2: Icons.visibility,
                            obscureText: true,
                          ),
                          CustomTextField(
                            controller: _confirmController,
                            label: 'Confirm Password',
                            icon: Icons.lock,
                            icon2: Icons.visibility,
                            obscureText: true,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (value) {
                                      setState(() {
                                        _rememberMe = value!;
                                      });
                                    },
                                    activeColor: const Color(0xFF008FD5),
                                  ),
                                  const Text('Remember me'),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          CustomButton(
                            text: _isLoading
                                ? 'Creating account...'
                                : SupabaseConfig.enableClientSignup
                                    ? 'Signup'
                                    : 'Registration unavailable',
                            onTap: _isLoading || !SupabaseConfig.enableClientSignup
                                ? null
                                : _handleSignup,
                          ),
                          const SizedBox(height: 20),
                          const Text('or continue with'),
                          const SizedBox(height: 20),
                          const Row(
                            children: [
                              AuthTab(
                                image: 'images/icons8-facebook-48.png',
                                text: 'Facebook',
                              ),
                              SizedBox(
                                width: 12,
                              ),
                              AuthTab(
                                image: 'images/icons8-google-48.png',
                                text: 'Google',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Don't have an account? "),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                        const LoginScreen()),
                                  );
                                },
                                child: const Text(
                                  'Login',
                                  style: TextStyle(
                                    color: Color(
                                        0xFF1A73E8), // Replace with your specific color
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
