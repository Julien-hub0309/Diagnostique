import 'dart:io';

class FileAnalyzerModule {
  
  /// Extrait la description technique brute d'un fichier (Mime/Type, architecture binaire...)
  Future<String> getFileDescription(String filePath) async {
    try {
      final result = await Process.run('file', [filePath]);
      if (result.exitCode == 0 && result.stdout.toString().isNotEmpty) {
        final output = result.stdout.toString().trim();
        if (output.contains(':')) {
          return output.substring(output.indexOf(':') + 1).trim();
        }
        return output;
      }
      return "Type de fichier indéterminé.";
    } catch (_) {
      return "Erreur : L'utilitaire système 'file' est inaccessible.";
    }
  }

  /// Diagnostique la corruption d'un fichier binaire spécifique
  Future<Map<String, dynamic>> diagnosticFileCorruption(String filePath) async {
    try {
      final fileRef = File(filePath);
      if (!await fileRef.exists()) {
        return {"status": "CRITICAL", "message": "ERREUR : Le fichier $filePath n'existe pas."};
      }

      int size = await fileRef.length();
      if (size == 0) {
        return {"status": "CRITICAL", "message": "CORRUPTION : $filePath fait 0 octet."};
      }

      final description = await getFileDescription(filePath);
      // Vérification des binaires ELF (format exécutable standard sous Linux)
      if (description.toLowerCase().contains("elf") || description.toLowerCase().contains("shared object")) {
        final lddResult = await Process.run('ldd', [filePath]);
        
        if (lddResult.exitCode == 0) {
          String lddOutput = lddResult.stdout.toString();
          if (lddOutput.contains("not found")) {
            List<String> brokenLibs = lddOutput
                .split('\n')
                .where((line) => line.contains("not found"))
                .map((line) => line.trim())
                .toList();
            
            return {
              "status": "CRITICAL", 
              "message": "CORRUPTION : Dépendances manquantes pour $filePath :\n    -> ${brokenLibs.join('\n    -> ')}"
            };
          }
        }
      }

      return {
        "status": "OK",
        "message": "INTEGRITÉ VALIDÉE : $filePath (Taille : $size octets)."
      };

    } catch (e) {
      return {"status": "UNKNOWN", "message": "Échec accès $filePath : $e"};
    }
  }

  /// Scan automatique des répertoires systèmes critiques (/bin, /sbin, /usr/bin)
  Future<Map<String, dynamic>> autoScanSystemFiles() async {
    List<String> systemDirs = ['/bin', '/usr/bin', '/sbin'];
    List<String> filesToScan = [];

    // Récupération automatique de tous les fichiers dans ces dossiers
    for (String dirPath in systemDirs) {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        try {
          await for (FileSystemEntity entity in dir.list()) {
            if (entity is File) {
              filesToScan.add(entity.path);
            }
          }
        } catch (e) {
          // Ignore les erreurs d'accès aux dossiers
        }
      }
    }

    return await scanSystemFilesBatch(filesToScan);
  }

  /// Analyse une liste de fichiers pour détecter des corruptions (Batch Scan)
  Future<Map<String, dynamic>> scanSystemFilesBatch(List<String> filePaths) async {
    int total = filePaths.length;
    int corrupted = 0;
    List<String> criticalErrors = [];

    for (String path in filePaths) {
      var result = await diagnosticFileCorruption(path);
      if (result['status'] == 'CRITICAL') {
        corrupted++;
        criticalErrors.add(result['message']);
      }
    }

    return {
      "status": corrupted == 0 ? "OK" : "CRITICAL",
      "message": "Scan terminé : $total fichiers analysés, $corrupted corrompus.",
      "details": criticalErrors
    };
  }
}