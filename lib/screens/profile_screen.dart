import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../widgets/crixy_floating.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;

  String name = "";
  String phone = "";
  String dob = "";

  @override
  void initState() {
    super.initState();
    loadData();
  }

  late Box profileBox;

  Future<void> loadData() async {
    // 1. FAST LOCAL LOAD (Zero Buffering)
    profileBox = await Hive.openBox('profile_${(user!.email ?? user!.uid)}');
    setState(() {
      name = profileBox.get('name', defaultValue: "");
      phone = profileBox.get('phone', defaultValue: "");
      dob = profileBox.get('dob', defaultValue: "");
    });

    // 2. BACKGROUND FIREBASE SYNC
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc((user!.email ?? user!.uid))
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          name = data['name'] ?? "";
          phone = data['phone'] ?? "";
          dob = data['dob'] ?? "";
        });
        
        // Cache fetched remote data to local Hive Box
        await profileBox.put('name', name);
        await profileBox.put('phone', phone);
        await profileBox.put('dob', dob);
        await profileBox.put('photoURL', user?.photoURL ?? "");
      }
    } catch (_) {
      // Continue serving local cache on fetch failure
    }
  }

  // 🔥 FAST SAVE (instant UI update & auto-sync)
  Future<void> saveField(String key, String value) async {
    setState(() {
      if (key == "name") name = value;
      if (key == "phone") phone = value;
      if (key == "dob") dob = value;
    });

    // Quick save locally first
    try {
      await profileBox.put(key, value);
    } catch (_) {}

    // Flush to Firestore softly
    try {
      await FirebaseFirestore.instance.collection('users').doc((user!.email ?? user!.uid)).set({
        key: value,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ✏️ EDIT TEXT FIELD (FIXED UI)
  void editTextField(String title, String currentValue, String key) {
    final controller = TextEditingController(text: currentValue);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF09090B),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF27272A)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Edit $title",
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: key == "phone" ? TextInputType.phone : TextInputType.text,
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: "Enter $title",
                    hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Qarume'),
                    filled: true,
                    fillColor: const Color(0xFF18181B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF10B981)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF27272A)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(fontFamily: 'Qarume', color: Colors.white54, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        saveField(key, controller.text);
                        Navigator.pop(context);
                      },
                      child: const Text('Save', style: TextStyle(fontFamily: 'Qarume', fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 📅 DOB PICKER (instant update)
  void pickDOB() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF09090B),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF09090B)),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      String formatted = DateFormat('dd-MM-yyyy').format(picked);
      saveField("dob", formatted);
    }
  }

  // 🔓 LOGOUT
  Future<void> logout() async {
    await Hive.close();
    await AuthService().signOut();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Widget buildRow(String title, String value, IconData leadingIcon, Color iconColor, VoidCallback onEdit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF27272A).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(leadingIcon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? "Not set" : value,
                  style: const TextStyle(
                    fontFamily: 'Qarume',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 20),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      floatingActionButton: const CrixyFloatingButton(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Profile",
          style: TextStyle(
            fontFamily: 'Qarume',
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: 1,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            // Profile Image
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF6366F1), width: 3),
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: const Color(0xFF18181B),
                backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null ? const Icon(Icons.person, size: 40, color: Colors.white54) : null,
              ),
            ),

            const SizedBox(height: 16),
            
            Text(
              user?.email ?? "", 
              style: const TextStyle(fontFamily: 'Qarume', color: Colors.white70, fontSize: 16),
            ),

            const SizedBox(height: 40),

            buildRow("Name", name, Icons.person_rounded, const Color(0xFF6366F1), () {
              editTextField("Name", name, "name");
            }),

            buildRow("Phone", phone, Icons.phone_rounded, const Color(0xFF10B981), () {
              editTextField("Phone", phone, "phone");
            }),

            buildRow("Date of Birth", dob, Icons.cake_rounded, const Color(0xFFF59E0B), () {
              pickDOB();
            }),

            const SizedBox(height: 40),

            // 🔓 LOGOUT BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF43F5E).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFFF43F5E),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: const Color(0xFFF43F5E).withValues(alpha: 0.3)),
                  ),
                  elevation: 0,
                ),
                onPressed: logout,
                label: const Text(
                  "Logout",
                  style: TextStyle(
                    fontFamily: 'Qarume',
                    color: Color(0xFFF43F5E),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
