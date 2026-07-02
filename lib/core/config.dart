class AppConfig {
  // Ports standard utilisés pour la détection des terminaux d'impression
  static const int portIPP = 631;       // Internet Printing Protocol
  static const int portJetDirect = 9100; // HP JetDirect / RAW printing
  static const int portLPD = 515;       // Line Printer Daemon (Optionnel)

  // Configuration des Timeouts réseaux pour maintenir la réactivité de l'UI
  static const Duration connectionTimeout = Duration(seconds: 2);
  static const Duration connectionTestTimeout = Duration(seconds: 5);

  // Communautés SNMP de base utilisées lors de la phase de reconnaissance
  static const List<String> snmpCommunities = [
    "public",
    "private",
    "internal"
  ];

  /// Retourne la liste des ports d'impression critiques à auditer
  static List<int> getAuditPorts() {
    return [portIPP, portJetDirect, portLPD];
  }
}