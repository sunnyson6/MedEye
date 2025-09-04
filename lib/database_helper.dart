import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      // Get the directory for storing the database file
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, "medeye.db");
      debugPrint('Database path: $path');

      // Check if the database file already exists
      bool fileExists = await File(path).exists();
      debugPrint('Database file exists: $fileExists');

      // If the database doesn't exist, copy it from assets
      if (!fileExists) {
        debugPrint('Copying database from assets...');
        ByteData data = await rootBundle.load("assets/medeye.db");
        debugPrint('Asset size: ${data.lengthInBytes} bytes');
        List<int> bytes = data.buffer.asUint8List();
        await File(path).writeAsBytes(bytes);
        debugPrint('Database copied successfully');
      }

      // Open the database
      final db = await openDatabase(
        path,
        readOnly: false,
        version: 2,
        onCreate: _createDb,
        onUpgrade: _upgradeDb,
      );
      debugPrint('Database opened successfully');

      // Verify the database has the expected tables
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      debugPrint(
        'Tables in database: ${tables.map((t) => t['name']).join(', ')}',
      );

      return db;
    } catch (e) {
      debugPrint('Error initializing database: $e');
      rethrow;
    }
  }

  // Create database tables
  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medicine_id INTEGER,
        scan_date TEXT,
        brand_name TEXT,
        generic_name TEXT,
        FOREIGN KEY (medicine_id) REFERENCES pills (ID)
      )
    ''');
  }

  // Handle database upgrades
  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS scan_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          medicine_id INTEGER,
          scan_date TEXT,
          brand_name TEXT,
          generic_name TEXT,
          FOREIGN KEY (medicine_id) REFERENCES pills (ID)
        )
      ''');
    }
  }

  // Get medicine information by ID
  Future<Map<String, dynamic>?> getMedicineById(int id) async {
    try {
      debugPrint('Getting medicine with ID: $id');
      final db = await database;

      // Check if 'pills' table exists
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='pills'",
      );
      if (tableCheck.isEmpty) {
        debugPrint('Error: pills table does not exist in the database');
        return null;
      }

      final List<Map<String, dynamic>> results = await db.query(
        'pills',
        where: 'ID = ?',
        whereArgs: [id],
      );

      debugPrint('Query results: ${results.length} rows found');

      if (results.isNotEmpty) {
        debugPrint('Medicine found: ${results.first}');
        return results.first;
      }
      debugPrint('No medicine found with ID: $id');
      return null;
    } catch (e) {
      debugPrint('Error getting medicine by ID: $e');
      return null;
    }
  }

  // Get medicine information by name
  Future<Map<String, dynamic>?> getMedicineByName(String name) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'pills',
      where: 'Brand_Name LIKE ? OR Generic_Name LIKE ?',
      whereArgs: ['%$name%', '%$name%'],
    );

    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }

  // Save scan to history
  Future<int> saveScanToHistory(
    int medicineId,
    String brandName,
    String genericName,
  ) async {
    final db = await database;

    final scanData = {
      'medicine_id': medicineId,
      'scan_date': DateTime.now().toIso8601String(),
      'brand_name': brandName,
      'generic_name': genericName,
    };

    return await db.insert('scan_history', scanData);
  }

  // Get all scan history, ordered by most recent
  Future<List<Map<String, dynamic>>> getAllScanHistory() async {
    final db = await database;

    return await db.query('scan_history', orderBy: 'scan_date DESC');
  }

  // Delete scan history item
  Future<int> deleteScanHistoryItem(int id) async {
    final db = await database;

    return await db.delete('scan_history', where: 'id = ?', whereArgs: [id]);
  }

  // Clear all scan history
  Future<int> clearScanHistory() async {
    final db = await database;

    return await db.delete('scan_history');
  }
}
