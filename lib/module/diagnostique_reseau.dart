import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// Modèles de données
// ─────────────────────────────────────────────────────────────────────────────

enum Severity { ok, warning, critical, unknown }

class Issue {
  final String code;
  final String message;
  final Severity severity;
  final String? suggestion;

  const Issue({
    required this.code,
    required this.message,
    required this.severity,
    this.suggestion,
  });

  Map<String, dynamic> toMap() => {
        'code': code,
        'severity': severity.name.toUpperCase(),
        'message': message,
        if (suggestion != null) 'suggestion': suggestion,
      };
}

class InterfaceInfo {
  final String name;
  final String ipLocal;
  final String? ipv6;
  final String? mac;
  final bool isUp;
  final bool hasCarrier;
  final String? mtu;
  final List<Issue> issues;

  const InterfaceInfo({
    required this.name,
    required this.ipLocal,
    this.ipv6,
    this.mac,
    required this.isUp,
    required this.hasCarrier,
    this.mtu,
    required this.issues,
  });

  Map<String, dynamic> toMap() => {
        'interface': name,
        'ip_locale': ipLocal,
        if (ipv6 != null) 'ipv6': ipv6,
        if (mac != null) 'mac': mac,
        'etat': isUp ? 'UP' : 'DOWN',
        'carrier': hasCarrier ? 'présent' : 'absent',
        if (mtu != null) 'mtu': mtu,
        if (issues.isNotEmpty) 'problèmes': issues.map((i) => i.toMap()).toList(),
      };
}

class AuditResult {
  final DateTime timestamp;
  final List<InterfaceInfo> interfaces;
  final String? gateway;
  final String? ipPublique;
  final Map<String, dynamic> ping;
  final Map<String, dynamic> dns;
  final Map<String, dynamic> routage;
  final List<Issue> issuesGlobaux;
  final Severity statusGlobal;

  /// Accès rapide pour l'UI
  String get ipLocale =>
      interfaces.isNotEmpty ? interfaces.first.ipLocal : 'Non configurée';
  String get dnsStatus => dns['status'] as String? ?? 'UNKNOWN';

  const AuditResult({
    required this.timestamp,
    required this.interfaces,
    this.gateway,
    this.ipPublique,
    required this.ping,
    required this.dns,
    required this.routage,
    required this.issuesGlobaux,
    required this.statusGlobal,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'status_global': statusGlobal.name.toUpperCase(),
        'ip_publique': ipPublique ?? 'Indisponible',
        'gateway': gateway ?? 'Inconnue',
        'interfaces': interfaces.map((i) => i.toMap()).toList(),
        'ping': ping,
        'dns': dns,
        'routage': routage,
        if (issuesGlobaux.isNotEmpty)
          'problèmes_globaux': issuesGlobaux.map((i) => i.toMap()).toList(),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Module principal
// ─────────────────────────────────────────────────────────────────────────────

class NetworkDiagnosticModule {
  /// Audit complet de toutes les interfaces réseau détectées.
  Future<AuditResult> performFullNetworkDiagnostic() async {
    final allIssues = <Issue>[];

    // 1. Inventaire des interfaces
    final interfaces = await _auditAllInterfaces();

    // 2. Routage & gateway
    final routage = await _auditRoutage();
    final gateway = routage['gateway'] as String?;

    // 3. IP publique
    final ipPublique = await _getPublicIp();
    if (ipPublique == null) {
      allIssues.add(const Issue(
        code: 'NO_PUBLIC_IP',
        message: 'Impossible d\'obtenir l\'IP publique.',
        severity: Severity.critical,
        suggestion: 'Vérifiez la connexion Internet ou le pare-feu sortant.',
      ));
    }

    // 4. Ping (passerelle + external)
    final ping = await _auditPing(gateway);

    // 5. DNS
    final dns = await _auditDns();

    // 6. Agrégation des problèmes globaux
    if (ping['status'] == 'CRITICAL') {
      allIssues.add(Issue(
        code: 'PING_FAILURE',
        message: ping['message'] as String,
        severity: Severity.critical,
        suggestion: 'Vérifiez la connectivité vers ${ping['target']}.',
      ));
    } else if (ping['status'] == 'WARNING') {
      allIssues.add(Issue(
        code: 'HIGH_LATENCY',
        message: ping['message'] as String,
        severity: Severity.warning,
        suggestion: 'Latence élevée détectée — vérifiez la charge réseau.',
      ));
    }

    if (dns['status'] != 'OK') {
      allIssues.add(Issue(
        code: 'DNS_FAILURE',
        message: dns['message'] as String,
        severity: Severity.critical,
        suggestion: 'Vérifiez /etc/resolv.conf et la joignabilité du serveur DNS.',
      ));
    }

    if (routage['issues'] != null) {
      allIssues.addAll(routage['issues'] as List<Issue>);
    }

    // Interfaces sans IP ni carrier
    for (final iface in interfaces) {
      allIssues.addAll(iface.issues);
    }

    // Status global
    final severity = _computeGlobalSeverity(allIssues);

    return AuditResult(
      timestamp: DateTime.now(),
      interfaces: interfaces,
      gateway: gateway,
      ipPublique: ipPublique,
      ping: {
        'status': ping['status'],
        'message': ping['message'],
        'target': ping['target'],
        if (ping['latence_ms'] != null) 'latence_ms': ping['latence_ms'],
        if (ping['perte_paquets'] != null) 'perte_paquets': ping['perte_paquets'],
      },
      dns: {
        'status': dns['status'],
        'message': dns['message'],
        'serveurs': dns['serveurs'],
        if (dns['details'] != null) 'details': dns['details'],
      },
      routage: {
        'table': routage['table'],
        'gateway': gateway,
        'routes_count': routage['routes_count'],
      },
      issuesGlobaux: allIssues,
      statusGlobal: severity,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Audit des interfaces
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<InterfaceInfo>> _auditAllInterfaces() async {
    final result = await _run('ip -o link show');
    if (result == null) return [];

    final ifaceNames = <String>[];
    for (final line in result.trim().split('\n')) {
      final match = RegExp(r'^\d+:\s+(\S+):').firstMatch(line);
      if (match != null) {
        final name = match.group(1)!.replaceAll('@NONE', '');
        // Ignorer loopback
        if (name != 'lo') ifaceNames.add(name);
      }
    }

    final infos = <InterfaceInfo>[];
    for (final name in ifaceNames) {
      infos.add(await _auditInterface(name));
    }
    return infos;
  }

  Future<InterfaceInfo> _auditInterface(String name) async {
    final issues = <Issue>[];

    // Flags (UP / LOWER_UP / carrier)
    final linkLine = await _run('ip link show $name');
    final isUp = linkLine?.contains('UP') ?? false;
    final hasCarrier = linkLine?.contains('LOWER_UP') ?? false;

    if (!isUp) {
      issues.add(Issue(
        code: 'IFACE_DOWN',
        message: 'Interface $name est DOWN.',
        severity: Severity.critical,
        suggestion: 'Exécutez : ip link set $name up',
      ));
    } else if (!hasCarrier) {
      issues.add(Issue(
        code: 'NO_CARRIER',
        message: 'Interface $name est UP mais sans carrier (câble débranché ?).',
        severity: Severity.critical,
        suggestion: 'Vérifiez le câble ou le point d\'accès WiFi.',
      ));
    }

    // Adresse IPv4
    final ipResult = await _run(
        "ip addr show $name | grep 'inet ' | awk '{print \$2}' | head -n1");
    final ip = (ipResult?.trim().isNotEmpty == true) ? ipResult!.trim() : null;

    if (ip == null && isUp) {
      issues.add(Issue(
        code: 'NO_IP',
        message: 'Interface $name n\'a pas d\'adresse IPv4.',
        severity: Severity.critical,
        suggestion: 'Vérifiez DHCP (dhclient $name) ou configurez une IP statique.',
      ));
    }

    // Adresse IPv6
    final ipv6Result = await _run(
        "ip addr show $name | grep 'inet6 ' | awk '{print \$2}' | grep -v '^fe80' | head -n1");
    final ipv6 = ipv6Result?.trim().isNotEmpty == true ? ipv6Result!.trim() : null;

    // MAC
    final macResult = await _run(
        "ip link show $name | grep 'link/ether' | awk '{print \$2}'");
    final mac = macResult?.trim().isNotEmpty == true ? macResult!.trim() : null;

    // MTU
    final mtuMatch = RegExp(r'mtu (\d+)').firstMatch(linkLine ?? '');
    final mtu = mtuMatch?.group(1);
    if (mtu != null && int.tryParse(mtu) != null && int.parse(mtu) < 1280) {
      issues.add(Issue(
        code: 'MTU_TOO_LOW',
        message: 'MTU de $name est $mtu (< 1280 octets).',
        severity: Severity.warning,
        suggestion: 'ip link set $name mtu 1500',
      ));
    }

    // IP dupliquée (ARP check rapide)
    if (ip != null) {
      final cleanIp = ip.split('/').first;
      final arpResult = await _run('arping -c 1 -D -I $name $cleanIp 2>/dev/null; echo \$?');
      // arping -D retourne 1 si doublon détecté
      if (arpResult?.trim() == '1') {
        issues.add(Issue(
          code: 'DUPLICATE_IP',
          message: 'Conflit d\'adresse IP détecté sur $name ($cleanIp).',
          severity: Severity.critical,
          suggestion: 'Une autre machine utilise $cleanIp sur ce réseau.',
        ));
      }
    }

    return InterfaceInfo(
      name: name,
      ipLocal: ip ?? 'Non configurée',
      ipv6: ipv6,
      mac: mac,
      isUp: isUp,
      hasCarrier: hasCarrier,
      mtu: mtu,
      issues: issues,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Routage
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _auditRoutage() async {
    final issues = <Issue>[];
    final table = await _run('ip route show') ?? '';

    // Gateway par défaut
    final gwMatch = RegExp(r'default via (\S+)').firstMatch(table);
    final gateway = gwMatch?.group(1);

    if (gateway == null) {
      issues.add(const Issue(
        code: 'NO_DEFAULT_ROUTE',
        message: 'Aucune route par défaut configurée.',
        severity: Severity.critical,
        suggestion: 'ip route add default via <IP_GATEWAY>',
      ));
    }

    // Compter les routes
    final routes = table.trim().split('\n').where((l) => l.isNotEmpty).toList();

    return {
      'gateway': gateway,
      'table': table.trim(),
      'routes_count': routes.length,
      'issues': issues,
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // IP publique
  // ───────────────────────────────────────────────────────────────────────────

  Future<String?> _getPublicIp() async {
    // Essai sur plusieurs services en cas d'indisponibilité
    for (final url in ['https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com']) {
      try {
        final result = await Process.run(
            'curl', ['-s', '--connect-timeout', '3', '--max-time', '5', url]);
        if (result.exitCode == 0) {
          final ip = result.stdout.toString().trim();
          if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) return ip;
        }
      } catch (_) {}
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ping (gateway + 1.1.1.1 + 8.8.8.8)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _auditPing(String? gateway) async {
    final targets = <String>[
      if (gateway != null) gateway,
      '1.1.1.1',
      '8.8.8.8',
    ];

    for (final target in targets) {
      final res = await _pingTarget(target);
      if (res['status'] != 'CRITICAL') {
        return {...res, 'target': target};
      }
    }

    return {
      'status': 'CRITICAL',
      'message': 'Toutes les cibles ping sont injoignables (gateway, 1.1.1.1, 8.8.8.8).',
      'target': targets.join(', '),
    };
  }

  Future<Map<String, dynamic>> _pingTarget(String target) async {
    try {
      final result = await Process.run('ping', ['-c', '4', '-W', '2', target]);
      if (result.exitCode != 0) {
        // Extraire le % de perte
        final lossMatch = RegExp(r'(\d+)% packet loss').firstMatch(result.stdout.toString());
        final loss = lossMatch?.group(1) ?? '100';
        return {
          'status': 'CRITICAL',
          'message': 'Perte de paquets : $loss% vers $target.',
          'perte_paquets': '$loss%',
        };
      }

      final lines = result.stdout.toString().split('\n');
      final statsLine = lines.lastWhere((l) => l.contains('rtt'), orElse: () => '');
      final lossLine = lines.firstWhere((l) => l.contains('packet loss'), orElse: () => '');
      final lossMatch = RegExp(r'(\d+)% packet loss').firstMatch(lossLine);
      final loss = int.tryParse(lossMatch?.group(1) ?? '0') ?? 0;

      if (statsLine.isEmpty) {
        return {'status': 'UNKNOWN', 'message': 'Impossible de lire les statistiques ping.'};
      }

      // Format : rtt min/avg/max/mdev = 0.xxx/0.xxx/0.xxx/0.xxx ms
      final parts = statsLine.split('/');
      final avg = double.tryParse(parts.length >= 5 ? parts[4] : '0') ?? 0.0;

      String status = 'OK';
      String message = 'Latence moyenne : ${avg.toStringAsFixed(1)} ms vers $target.';

      if (loss > 0) {
        status = 'WARNING';
        message += ' Perte de paquets : $loss%.';
      }
      if (avg > 150) {
        status = status == 'WARNING' ? 'CRITICAL' : 'WARNING';
        message += ' Latence élevée (> 150 ms).';
      }

      return {
        'status': status,
        'message': message,
        'latence_ms': avg.toStringAsFixed(1),
        'perte_paquets': '$loss%',
      };
    } catch (_) {
      return {'status': 'UNKNOWN', 'message': 'Erreur lors du ping vers $target.'};
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DNS
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _auditDns() async {
    // Lire les serveurs DNS configurés
    final resolv = await _run("grep '^nameserver' /etc/resolv.conf | awk '{print \$2}'");
    final serveurs = resolv?.trim().split('\n').where((s) => s.isNotEmpty).toList() ?? [];

    final details = <Map<String, dynamic>>[];
    bool anySuccess = false;

    // Tester chaque serveur DNS individuellement
    final testDomains = ['google.com', 'cloudflare.com', 'example.com'];

    for (final dns in serveurs) {
      for (final domain in testDomains) {
        final res = await Process.run('dig', ['+short', '+time=2', '+tries=1', '@$dns', domain]);
        final resolved = res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty;
        details.add({'serveur': dns, 'domaine': domain, 'résolu': resolved});
        if (resolved) anySuccess = true;
      }
    }

    // Fallback : getent si dig absent
    if (serveurs.isEmpty) {
      final getent = await Process.run('sh', ['-c', 'getent hosts google.com > /dev/null 2>&1']);
      anySuccess = getent.exitCode == 0;
      return {
        'status': anySuccess ? 'OK' : 'CRITICAL',
        'message': anySuccess
            ? 'Résolution DNS fonctionnelle (via getent).'
            : 'Résolution DNS échouée. Aucun serveur DNS dans /etc/resolv.conf.',
        'serveurs': [],
        'details': [],
      };
    }

    // Vérifier les serveurs DNS standards si personnalisés non joignables
    final failedServers = details
        .where((d) => d['résolu'] == false)
        .map((d) => d['serveur'] as String)
        .toSet()
        .toList();

    String message;
    String status;

    if (anySuccess) {
      status = failedServers.isNotEmpty ? 'WARNING' : 'OK';
      message = failedServers.isNotEmpty
          ? 'Certains serveurs DNS ne répondent pas : ${failedServers.join(', ')}.'
          : 'Tous les serveurs DNS répondent correctement.';
    } else {
      status = 'CRITICAL';
      message = 'Aucun serveur DNS ne répond. Vérifiez /etc/resolv.conf et la connectivité.';
    }

    return {
      'status': status,
      'message': message,
      'serveurs': serveurs,
      'details': details,
    };
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  Future<String?> _run(String cmd) async {
    try {
      final result = await Process.run('sh', ['-c', cmd]);
      if (result.exitCode == 0) return result.stdout.toString();
      return null;
    } catch (_) {
      return null;
    }
  }

  Severity _computeGlobalSeverity(List<Issue> issues) {
    if (issues.any((i) => i.severity == Severity.critical)) return Severity.critical;
    if (issues.any((i) => i.severity == Severity.warning)) return Severity.warning;
    if (issues.any((i) => i.severity == Severity.unknown)) return Severity.unknown;
    return Severity.ok;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Point d'entrée pour test en ligne de commande
// ─────────────────────────────────────────────────────────────────────────────

void _printSection(String title) {
  print('\n${'─' * 60}');
  print('  $title');
  print('─' * 60);
}

void _printIssues(List<Issue> issues) {
  for (final issue in issues) {
    final icon = switch (issue.severity) {
      Severity.critical => '🔴',
      Severity.warning  => '🟡',
      Severity.unknown  => '⚪',
      Severity.ok       => '🟢',
    };
    print('  $icon [${issue.code}] ${issue.message}');
    if (issue.suggestion != null) print('     → ${issue.suggestion}');
  }
}

Future<void> main() async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║          Audit Réseau Complet — NetworkDiagnostic        ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('Démarrage de l\'audit...');

  final module = NetworkDiagnosticModule();
  final result = await module.performFullNetworkDiagnostic();

  _printSection('STATUT GLOBAL : ${result.statusGlobal.name.toUpperCase()}');
  print('  Horodatage  : ${result.timestamp}');
  print('  IP publique : ${result.ipPublique ?? "Indisponible"}');
  print('  Gateway     : ${result.gateway ?? "Inconnue"}');

  _printSection('INTERFACES (${result.interfaces.length} détectées)');
  for (final iface in result.interfaces) {
    print('\n  [${iface.name}]  ${iface.isUp ? "UP" : "DOWN"}  carrier=${iface.hasCarrier}');
    print('    IPv4 : ${iface.ipLocal}');
    if (iface.ipv6 != null) print('    IPv6 : ${iface.ipv6}');
    if (iface.mac != null)  print('    MAC  : ${iface.mac}');
    if (iface.mtu != null)  print('    MTU  : ${iface.mtu}');
    if (iface.issues.isNotEmpty) _printIssues(iface.issues);
  }

  _printSection('PING');
  print('  Statut  : ${result.ping['status']}');
  print('  Cible   : ${result.ping['target']}');
  print('  Message : ${result.ping['message']}');
  if (result.ping['latence_ms'] != null) print('  Latence : ${result.ping['latence_ms']} ms');
  if (result.ping['perte_paquets'] != null) print('  Perte   : ${result.ping['perte_paquets']}');

  _printSection('DNS');
  print('  Statut   : ${result.dns['status']}');
  print('  Message  : ${result.dns['message']}');
  final serveurs = result.dns['serveurs'] as List<dynamic>;
  if (serveurs.isNotEmpty) print('  Serveurs : ${serveurs.join(', ')}');

  _printSection('TABLE DE ROUTAGE');
  print('  Routes   : ${result.routage['routes_count']}');
  print('  Gateway  : ${result.routage['gateway'] ?? "Aucune"}');

  if (result.issuesGlobaux.isNotEmpty) {
    _printSection('PROBLÈMES DÉTECTÉS (${result.issuesGlobaux.length})');
    _printIssues(result.issuesGlobaux);
  } else {
    _printSection('AUCUN PROBLÈME DÉTECTÉ 🟢');
  }

  print('\n${'═' * 60}\n');
}