import 'dart:io';

class HardwareDiagnosticModule {
  
  // 1. CPU : Appel direct et robuste
  Future<String> getCpuModel() async {
    final result = await Process.run('sh', ['-c', "lscpu | grep -E 'Model name|Nom de modèle' | cut -d':' -f2 | sed 's/^[ \t]*//'"]);
    return result.exitCode == 0 && result.stdout.toString().isNotEmpty 
        ? result.stdout.toString().trim() 
        : "Processeur générique";
  }

  // 2. RAM : Lecture directe via /proc/meminfo pour éviter les dépendances
  Future<String> getRamTotal() async {
    final result = await Process.run('sh', ['-c', "grep MemTotal /proc/meminfo | awk '{print \$2/1024/1024 \" GB\"}'"]);
    return result.exitCode == 0 ? result.stdout.toString().trim() : "Indisponible";
  }

  // 3. GPU : Appel direct
  Future<String> getGpuModel() async {
    final result = await Process.run('sh', ['-c', "lspci | grep -E 'VGA|3D' | cut -d':' -f3 | sed 's/^[ \t]*//'"]);
    return result.exitCode == 0 && result.stdout.toString().isNotEmpty 
        ? result.stdout.toString().trim() 
        : "Contrôleur standard";
  }

  // 4. Disques : Liste simple et propre
  Future<List<String>> getStorageDevices() async {
    final result = await Process.run('lsblk', ['-d', '-n', '-o', 'NAME,SIZE']);
    if (result.exitCode == 0) {
      return result.stdout.toString().split('\n').where((s) => s.trim().isNotEmpty).toList();
    }
    return [];
  }

  // 5. THERMIQUE : Lecture multi-zone exhaustive sans erreur masquée
  // Si le dossier est vide, il retourne une valeur d'erreur explicite pour ton main.dart
  Future<Map<String, dynamic>> checkThermalStatus() async {
    Map<String, String> temperatures = {};
    
    try {
      final dir = Directory('/sys/class/thermal/');
      if (await dir.exists()) {
        for (var entity in dir.listSync()) {
          if (entity is Directory && entity.path.contains('thermal_zone')) {
            final type = await File('${entity.path}/type').readAsString();
            final temp = await File('${entity.path}/temp').readAsString();
            temperatures[type.trim()] = "${(double.parse(temp.trim()) / 1000).toStringAsFixed(1)}°C";
          }
        }
      }
    } catch (e) {
      return {"status": "ERROR", "message": "Accès capteurs impossible: $e"};
    }

    return {
      "status": temperatures.isEmpty ? "WARNING" : "OK",
      "message": temperatures.isEmpty ? "Aucune sonde détectée" : temperatures.toString()
    };
  }
}