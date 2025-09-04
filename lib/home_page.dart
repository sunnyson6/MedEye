import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'image_utils.dart';
import 'model_config.dart';
import 'custom_model_helper.dart';
import 'database_helper.dart';
import 'medicine_model.dart';
import 'medicine_details_page.dart';
import 'scan_page.dart';
import 'scan_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    if (index == 1) {
      // Navigate to History page
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ScanHistoryPage()),
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _navigateToScan() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScanPage()),
    );
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScanHistoryPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo and App Name
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF45BFB8),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.visibility,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'MedEye',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0B3954),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Tagline
              const Text(
                'Smart Medical Scanning\nat Your Fingertips',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF333333),
                ),
              ),

              const SizedBox(height: 32),

              // Welcome Text
              const Text(
                'Welcome to MedEye! Quickly scan medicine packages with our AI-powered scanner and get the details of the medicine.',
                style: TextStyle(fontSize: 18, color: Color(0xFF555555)),
              ),

              const SizedBox(height: 40),

              // Scan Now Button
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: _navigateToScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0277BD),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Scan Now',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Features section
              FeatureItem(
                icon: Icons.speed,
                title: 'Fast & Accurate',
                description: 'AI-powered real-time scanning',
              ),

              const SizedBox(height: 24),

              FeatureItem(
                icon: Icons.folder,
                title: 'Saved Scans',
                description: 'View your scan history',
                onTap: _navigateToHistory,
              ),

              const SizedBox(height: 24),

              FeatureItem(
                icon: Icons.access_time,
                title: 'Offline Support',
                description: 'Works without an internet connection',
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  const FeatureItem({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0277BD),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
