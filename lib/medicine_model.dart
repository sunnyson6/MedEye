class Medicine {
  final int id;
  final String pillLabel;
  final String genericName;
  final String brandName;
  final String manufacturer;
  final String medicalUse;
  final String dosageGuidelines;
  final String warnings;
  final String additionalInfo;
  final int prescriptionRequired;
  final String legalStatus;

  Medicine({
    required this.id,
    required this.pillLabel,
    required this.genericName,
    required this.brandName,
    required this.manufacturer,
    required this.medicalUse,
    required this.dosageGuidelines,
    required this.warnings,
    required this.additionalInfo,
    required this.prescriptionRequired,
    required this.legalStatus,
  });

  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      id: map['ID'],
      pillLabel: map['Pill_Label'] ?? '',
      genericName: map['Generic_Name'] ?? '',
      brandName: map['Brand_Name'] ?? '',
      manufacturer: map['Manufacturer'] ?? '',
      medicalUse: map['Medical_Use'] ?? '',
      dosageGuidelines: map['Dosage_Guidelines'] ?? '',
      warnings: map['Warnings'] ?? '',
      additionalInfo: map['Additional_Info'] ?? '',
      prescriptionRequired: map['Prescription_Req'] ?? 0,
      legalStatus: map['Legal_Status'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ID': id,
      'Pill_Label': pillLabel,
      'Generic_Name': genericName,
      'Brand_Name': brandName,
      'Manufacturer': manufacturer,
      'Medical_Use': medicalUse,
      'Dosage_Guidelines': dosageGuidelines,
      'Warnings': warnings,
      'Additional_Info': additionalInfo,
      'Prescription_Req': prescriptionRequired,
      'Legal_Status': legalStatus,
    };
  }
}
