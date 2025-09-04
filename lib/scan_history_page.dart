import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import 'scan_history_model.dart';
import 'medicine_details_page.dart';
import 'medicine_model.dart';

class ScanHistoryPage extends StatefulWidget {
  const ScanHistoryPage({super.key});

  @override
  State<ScanHistoryPage> createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<ScanHistory> _scanHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScanHistory();
  }

  Future<void> _loadScanHistory() async {
    setState(() {
      _isLoading = true;
    });

    final historyData = await _databaseHelper.getAllScanHistory();

    setState(() {
      _scanHistory =
          historyData.map((item) => ScanHistory.fromMap(item)).toList();
      _isLoading = false;
    });
  }

  Future<void> _deleteScanHistoryItem(int id) async {
    await _databaseHelper.deleteScanHistoryItem(id);
    _loadScanHistory();
  }

  Future<void> _clearScanHistory() async {
    final shouldClear =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Clear All History'),
                content: const Text(
                  'Are you sure you want to clear all scan history?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Clear'),
                  ),
                ],
              ),
        ) ??
        false;

    if (shouldClear) {
      await _databaseHelper.clearScanHistory();
      _loadScanHistory();
    }
  }

  Future<void> _viewMedicineDetails(int medicineId) async {
    final medicineData = await _databaseHelper.getMedicineById(medicineId);

    if (medicineData != null && context.mounted) {
      final medicine = Medicine.fromMap(medicineData);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MedicineDetailsPage(medicine: medicine),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medicine details not found'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(String isoDate) {
    final dateTime = DateTime.parse(isoDate);
    return DateFormat('MMM d, yyyy - h:mm a').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        actions: [
          if (_scanHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
              onPressed: _clearScanHistory,
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _scanHistory.isEmpty
              ? const Center(
                child: Text(
                  'No scan history found',
                  style: TextStyle(fontSize: 18),
                ),
              )
              : ListView.builder(
                itemCount: _scanHistory.length,
                itemBuilder: (context, index) {
                  final historyItem = _scanHistory[index];
                  return Dismissible(
                    key: Key(historyItem.id.toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Delete Item'),
                                  content: const Text(
                                    'Are you sure you want to delete this item?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () =>
                                              Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.of(context).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                          ) ??
                          false;
                    },
                    onDismissed: (direction) {
                      _deleteScanHistoryItem(historyItem.id);
                    },
                    child: ListTile(
                      title: Text(
                        historyItem.brandName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(historyItem.genericName),
                          Text(
                            _formatDate(historyItem.scanDate),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 16),
                        onPressed:
                            () => _viewMedicineDetails(historyItem.medicineId),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      onTap: () => _viewMedicineDetails(historyItem.medicineId),
                    ),
                  );
                },
              ),
    );
  }
}
