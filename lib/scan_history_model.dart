class ScanHistory {
  final int id;
  final int medicineId;
  final String scanDate;
  final String brandName;
  final String genericName;

  ScanHistory({
    required this.id,
    required this.medicineId,
    required this.scanDate,
    required this.brandName,
    required this.genericName,
  });

  factory ScanHistory.fromMap(Map<String, dynamic> map) {
    return ScanHistory(
      id: map['id'],
      medicineId: map['medicine_id'],
      scanDate: map['scan_date'],
      brandName: map['brand_name'],
      genericName: map['generic_name'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicine_id': medicineId,
      'scan_date': scanDate,
      'brand_name': brandName,
      'generic_name': genericName,
    };
  }
}
