import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F0F0F), Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),

                // 🧿 App Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: const CircleAvatar(
                    radius: 60,
                    backgroundImage: AssetImage('assets/app_icon.png'),
                    backgroundColor: Colors.transparent,
                  ),
                ),

                const SizedBox(height: 40),

                const SizedBox(height: 24),

                const Text(
                  "Smart expense tracking",
                  style: TextStyle(
                    fontFamily: 'Qarume',
                    fontSize: 18,
                    color: Color.fromRGBO(255, 255, 255, 0.7),
                    fontWeight: FontWeight.w400,
                  ),
                ),

                const Spacer(),

                // 🔘 Google Sign-In Button
                Container(
                  margin: const EdgeInsets.only(bottom: 50),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: const Color.fromRGBO(255, 255, 255, 0.3),
                    ),
                    icon: const Icon(
                      Icons.g_mobiledata,
                      size: 24,
                      color: Colors.blue,
                    ),
                    label: const Text(
                      "Continue with Google",
                      style: TextStyle(
                        fontFamily: 'Qarume',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      final user = await auth.signInWithGoogle();
                      if (user != null && context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/home',
                          (route) => false,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
