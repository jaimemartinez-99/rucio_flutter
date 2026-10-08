class AndroidInstallation {
  const AndroidInstallation({
    required this.packageId,
    required this.version,
    required this.buildNumber,
    required this.abis,
    required this.certificates,
  });

  factory AndroidInstallation.fromJson(Map<String, dynamic> json) =>
      AndroidInstallation(
        packageId: json['packageId'] as String,
        version: json['version'] as String,
        buildNumber: (json['buildNumber'] as num).toInt(),
        abis: List<String>.from(json['abis'] as List),
        certificates: List<String>.from(json['certificates'] as List),
      );

  final String packageId;
  final String version;
  final int buildNumber;
  final List<String> abis;
  final List<String> certificates;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  factory AppRelease.fromJson(
    Map<String, dynamic> json,
    AndroidInstallation installation,
  ) {
    final build = json['buildNumber'];
    final version = json['version'];
    final notes = json['notes'];
    final certificate = json['certificateSha256'];
    if (json['schema'] != 1 ||
        json['packageId'] != installation.packageId ||
        build is! int ||
        build <= 0 ||
        build > 2147483647 ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        notes is! String ||
        notes.length > 10000 ||
        certificate is! String ||
        !installation.certificates.contains(certificate.toLowerCase()) ||
        json['artifacts'] is! Map) {
      throw const FormatException(
        'La actualización no es compatible con esta instalación.',
      );
    }
    final artifacts = json['artifacts'] as Map;
    Map? artifact;
    String? selectedAbi;
    for (final abi in installation.abis) {
      if (artifacts[abi] is Map) {
        artifact = artifacts[abi] as Map;
        selectedAbi = abi;
        break;
      }
    }
    if (artifact == null) {
      throw const FormatException(
        'No hay una actualización compatible con este dispositivo.',
      );
    }
    final path = artifact['path'];
    final bytes = artifact['bytes'];
    final digest = artifact['sha256'];
    if (path != 'android/$build/rucio-$selectedAbi.apk' ||
        bytes is! int ||
        bytes <= 0 ||
        bytes > 50 * 1024 * 1024 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'La información de la actualización no es válida.',
      );
    }
    return AppRelease(
      version: version,
      buildNumber: build,
      notes: notes,
      path: path as String,
      bytes: bytes,
      sha256: digest,
    );
  }

  final String version;
  final int buildNumber;
  final String notes;
  final String path;
  final int bytes;
  final String sha256;
}
