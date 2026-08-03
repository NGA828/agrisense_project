import '../services/api/api_service.dart';

class Diagnosis {
  final String id;
  final String userEmail;
  final String cropType;
  final String imageUrl;
  final String symptoms;
  final double confidence;
  final String diseaseName;
  final String severity;
  final String causes;
  final String prevention;
  final bool isHealthy;
  final bool isInconclusive;
  final String engine;
  final bool trainedModel;
  final String modelVersion;
  final String modelLabel;
  final List<Map<String, dynamic>> alternatives;
  final DateTime createdAt;
  final Location? location;
  final TreatmentPlan? treatmentPlan;

  Diagnosis({
    required this.id,
    required this.userEmail,
    required this.cropType,
    required this.imageUrl,
    required this.symptoms,
    required this.confidence,
    required this.diseaseName,
    required this.severity,
    required this.causes,
    required this.prevention,
    this.isHealthy = false,
    this.isInconclusive = false,
    this.engine = 'unknown',
    this.trainedModel = false,
    this.modelVersion = '',
    this.modelLabel = '',
    this.alternatives = const [],
    required this.createdAt,
    this.location,
    this.treatmentPlan,
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) {
    return Diagnosis(
      id: json['id'],
      userEmail: json['user_email'],
      cropType: json['crop_type'],
      imageUrl: ApiService.resolveMedia(json['image'] as String?),
      symptoms: json['symptoms'],
      confidence: double.parse(json['confidence'].toString()),
      diseaseName: json['disease_name'],
      severity: json['severity'],
      causes: json['causes'],
      prevention: json['prevention'],
      isHealthy: json['is_healthy'] ?? false,
      isInconclusive: json['is_inconclusive'] ?? false,
      engine: json['engine']?.toString() ?? 'unknown',
      trainedModel: json['trained_model'] == true,
      modelVersion: json['model_version']?.toString() ?? '',
      modelLabel: json['model_label']?.toString() ?? '',
      alternatives: (json['alternatives'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      createdAt: DateTime.parse(json['created_at']),
      location: json['location_data'] != null 
          ? Location.fromJson(json['location_data']) 
          : null,
      treatmentPlan: json['treatment_plan'] != null
          ? TreatmentPlan.fromJson(json['treatment_plan'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_email': userEmail,
        'crop_type': cropType,
        'image': imageUrl, // already resolved absolute URL; fromJson keeps it
        'symptoms': symptoms,
        'confidence': confidence,
        'disease_name': diseaseName,
        'severity': severity,
        'causes': causes,
        'prevention': prevention,
        'is_healthy': isHealthy,
        'is_inconclusive': isInconclusive,
        'engine': engine,
        'trained_model': trainedModel,
        'model_version': modelVersion,
        'model_label': modelLabel,
        'alternatives': alternatives,
        'created_at': createdAt.toIso8601String(),
        'location_data': location?.toJson(),
        'treatment_plan': treatmentPlan?.toJson(),
      };

  bool get usesTrainedModel => trainedModel;
  bool get lacksTrainedModelProvenance => !usesTrainedModel;
  bool get usesRuleFallback => engine == 'rule-based';
}

class Location {
  final int id;
  final double longitude;
  final double latitude;
  final String address;
  final String climateZone;

  Location({
    required this.id,
    required this.longitude,
    required this.latitude,
    required this.address,
    required this.climateZone,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'],
      longitude: json['longitude'],
      latitude: json['latitude'],
      address: json['address'],
      climateZone: json['climate_zone'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'longitude': longitude,
        'latitude': latitude,
        'address': address,
        'climate_zone': climateZone,
      };
}

class TreatmentPlan {
  final int id;
  final String treatmentType;
  final String medication;
  final String instructions;
  final int duration;
  final DateTime followUpDate;
  final String status;

  TreatmentPlan({
    required this.id,
    required this.treatmentType,
    required this.medication,
    required this.instructions,
    required this.duration,
    required this.followUpDate,
    required this.status,
  });

  factory TreatmentPlan.fromJson(Map<String, dynamic> json) {
    return TreatmentPlan(
      id: json['id'],
      treatmentType: json['treatment_type'],
      medication: json['medication'],
      instructions: json['instructions'],
      duration: json['duration'],
      followUpDate: DateTime.parse(json['follow_up_date']),
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'treatment_type': treatmentType,
        'medication': medication,
        'instructions': instructions,
        'duration': duration,
        'follow_up_date': followUpDate.toIso8601String(),
        'status': status,
      };
}