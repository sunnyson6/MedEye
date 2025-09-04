import 'package:flutter/material.dart';
import 'medicine_model.dart';
import 'package:flutter_tts/flutter_tts.dart';

class MedicineDetailsPage extends StatefulWidget {
  final Medicine medicine;
  final String? expiryDate; // Add expiry date parameter

  const MedicineDetailsPage({
    super.key,
    required this.medicine,
    this.expiryDate, // Make it optional
  });

  @override
  State<MedicineDetailsPage> createState() => _MedicineDetailsPageState();
}

class _MedicineDetailsPageState extends State<MedicineDetailsPage> {
  final FlutterTts flutterTts = FlutterTts();
  bool isSpeaking = false;
  String selectedLanguage = "en-US"; // Default language is English

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    flutterTts.setCompletionHandler(() {
      setState(() {
        isSpeaking = false;
      });
    });
  }

  Future<void> _speak(String language) async {
    if (isSpeaking) {
      await flutterTts.stop();
      setState(() {
        isSpeaking = false;
      });
      return;
    }

    // Set language
    if (language == "tl-PH") {
      await flutterTts.setLanguage("fil-PH"); // Filipino/Tagalog
    } else {
      await flutterTts.setLanguage("en-US"); // English (US)
    }

    String textToRead = """
      Medicine Information:
      Pill Label: ${widget.medicine.pillLabel}
      Generic Name: ${widget.medicine.genericName}
      Brand Name: ${widget.medicine.brandName}
      Manufacturer: ${widget.medicine.manufacturer}
      Medical Use: ${widget.medicine.medicalUse}
      Dosage Guidelines: ${widget.medicine.dosageGuidelines}
      Warnings: ${widget.medicine.warnings}
      Additional Information: ${widget.medicine.additionalInfo}
      Prescription Required: ${widget.medicine.prescriptionRequired == 1 ? 'Yes' : 'No'}
      Legal Status: ${widget.medicine.legalStatus}
    """;

    setState(() {
      isSpeaking = true;
      selectedLanguage = language;
    });

    await flutterTts.speak(textToRead);
  }

  void _showLanguageSelection() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Image.asset(
                  'assets/icons/usa_flag.webp',
                  width: 40,
                  height: 40,
                ),
                title: const Text('English'),
                onTap: () {
                  Navigator.of(context).pop();
                  _speak("en-US");
                },
              ),
              ListTile(
                leading: Image.asset(
                  'assets/icons/ph_flag.webp',
                  width: 40,
                  height: 40,
                ),
                title: const Text('Tagalog'),
                onTap: () {
                  Navigator.of(context).pop();
                  _speak("tl-PH");
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.medicine.brandName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoSection('Pill Label', widget.medicine.pillLabel),
            _buildInfoSection('Generic Name', widget.medicine.genericName),
            _buildInfoSection('Brand Name', widget.medicine.brandName),
            _buildInfoSection('Manufacturer', widget.medicine.manufacturer),
            _buildInfoSection('Medical Use', widget.medicine.medicalUse),
            _buildInfoSection(
              'Dosage Guidelines',
              widget.medicine.dosageGuidelines,
            ),
            _buildInfoSection('Warnings', widget.medicine.warnings),
            _buildInfoSection(
              'Additional Information',
              widget.medicine.additionalInfo,
            ),
            _buildInfoSection(
              'Prescription Required',
              widget.medicine.prescriptionRequired == 1 ? 'Yes' : 'No',
            ),
            _buildInfoSection('Legal Status', widget.medicine.legalStatus),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            isSpeaking
                ? () => _speak(selectedLanguage)
                : _showLanguageSelection,
        tooltip: isSpeaking ? 'Stop Reading' : 'Read Aloud',
        child: Icon(isSpeaking ? Icons.stop : Icons.volume_up),
      ),
    );
  }

  Widget _buildInfoSection(String title, String content) {
    if (content.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8.0),
          Text(content, style: const TextStyle(fontSize: 16.0)),
        ],
      ),
    );
  }

  // Special section for expiration date with a more prominent display
  Widget _buildExpiryDateSection(String expiryDate) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.red, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.red, size: 20.0),
              const SizedBox(width: 8.0),
              Text(
                'Expiration Date',
                style: TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Text(
            expiryDate,
            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4.0),
          Text(
            'Detected from package via text recognition',
            style: TextStyle(
              fontSize: 14.0,
              fontStyle: FontStyle.italic,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
