import 'package:flutter/material.dart';
import 'module/diagnostique_hardware.dart';
import 'module/diagnostique_reseau.dart';
import 'module/diagnostique_software.dart';

void main() => runApp(const FO_diagnostique());

class FO_diagnostique extends StatelessWidget {
  const FO_diagnostique({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121214),
        cardColor: const Color(0xFF1A1A1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE2121E),
          surface: Color(0xFF1A1A1E),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final Map<String, List<Map<String, String>>> _logs = {
    "HARDWARE": [],
    "RÉSEAU": [],
    "SOFTWARE": [],
  };
  bool _isAnalyzing = false;

  void _log(String tab, String msg, String type) {
    setState(() => _logs[tab]!.add({'msg': msg, 'type': type}));
  }

  Future<void> _runDiagnostic(String tab) async {
    setState(() {
      _isAnalyzing = true;
      _logs[tab]!.clear(); // Réinitialise les logs à chaque nouvel audit
    });
    _log(tab, ">>> INITIALISATION DE L'AUDIT LOCAL", 'sys');

    try {
      if (tab == "HARDWARE") {
        final mod = HardwareDiagnosticModule();
        _log(tab, "CPU: ${await mod.getCpuModel()}", 'info');
        _log(tab, "RAM: ${await mod.getRamTotal()}", 'info');
        final temp = await mod.checkThermalStatus();
        _log(
          tab,
          "THERMIQUE: ${temp['message']}",
          temp['status'] == 'OK' ? 'info' : 'error',
        );

      } else if (tab == "RÉSEAU") {
        final mod = NetworkDiagnosticModule();
        final net = await mod.performFullNetworkDiagnostic();

        // ── Informations générales ──────────────────────────────────────
        _log(tab, "IP PUBLIQUE : ${net.ipPublique ?? 'Indisponible'}", 'info');
        _log(tab, "GATEWAY     : ${net.gateway ?? 'Inconnue'}", 'info');

        // ── Interfaces ─────────────────────────────────────────────────
        _log(tab, "─── INTERFACES (${net.interfaces.length}) ───", 'sys');
        for (final iface in net.interfaces) {
          final state = iface.isUp ? 'UP' : 'DOWN';
          final carrier = iface.hasCarrier ? '' : ' | NO CARRIER';
          _log(tab, "[${iface.name}] $state$carrier | IP: ${iface.ipLocal}", 'info');
          if (iface.ipv6 != null) _log(tab, "  IPv6: ${iface.ipv6}", 'info');
          for (final issue in iface.issues) {
            _log(tab, "  ⚠ [${issue.code}] ${issue.message}", 'error');
            if (issue.suggestion != null) {
              _log(tab, "    → ${issue.suggestion}", 'warn');
            }
          }
        }

        // ── Ping ───────────────────────────────────────────────────────
        _log(tab, "─── PING ───", 'sys');
        final pingStatus = net.ping['status'] as String;
        final pingMsg    = net.ping['message'] as String;
        _log(tab, "[$pingStatus] $pingMsg", pingStatus == 'OK' ? 'info' : 'error');

        // ── DNS ────────────────────────────────────────────────────────
        _log(tab, "─── DNS ───", 'sys');
        final dnsStatus = net.dns['status'] as String;
        final dnsMsg    = net.dns['message'] as String;
        _log(tab, "[$dnsStatus] $dnsMsg", dnsStatus == 'OK' ? 'info' : 'error');
        final serveurs = net.dns['serveurs'] as List<dynamic>;
        if (serveurs.isNotEmpty) {
          _log(tab, "  Serveurs : ${serveurs.join(', ')}", 'info');
        }

        // ── Problèmes globaux ──────────────────────────────────────────
        if (net.issuesGlobaux.isNotEmpty) {
          _log(tab, "─── PROBLÈMES DÉTECTÉS ───", 'sys');
          for (final issue in net.issuesGlobaux) {
            _log(tab, "[${issue.severity.name.toUpperCase()}] ${issue.message}", 'error');
            if (issue.suggestion != null) {
              _log(tab, "  → ${issue.suggestion}", 'warn');
            }
          }
        }

        // ── Statut final ───────────────────────────────────────────────
        final globalOk = net.statusGlobal == Severity.ok;
        _log(
          tab,
          ">>> STATUT GLOBAL : ${net.statusGlobal.name.toUpperCase()}",
          globalOk ? 'success' : 'error',
        );
        return; // On gère le message de fin ci-dessous séparément

      } else {
        final mod = FileAnalyzerModule();
        final report = await mod.autoScanSystemFiles();
        _log(
          tab,
          report['message'] as String,
          report['status'] == 'OK' ? 'success' : 'error',
        );
      }

      _log(tab, ">>> AUDIT TERMINÉ — STATUS OK", 'success');
    } catch (e) {
      _log(tab, "CRITICAL: $e", 'error');
    }

    setState(() => _isAnalyzing = false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Image.asset('assets/background.png', fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.85)),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildTabBar(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: TabBarView(
                      children: _logs.keys
                          .map((tab) => _buildModuleView(tab))
                          .toList(),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "FO_DIAGNOSTIQUE",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _isAnalyzing
                ? const Color(0xFF3B1214)
                : const Color(0xFF1C241E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isAnalyzing
                    ? const Color(0xFFFA4D56)
                    : const Color(0xFF24A148),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isAnalyzing ? "ANALYZING" : "STANDBY",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _isAnalyzing
                    ? const Color(0xFFFA4D56)
                    : const Color(0xFF24A148),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 45,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: const Color(0xFFE2121E).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2121E).withOpacity(0.5)),
        ),
        labelColor: Colors.white,
        tabs: const [
          Tab(text: "HARDWARE"),
          Tab(text: "RÉSEAU"),
          Tab(text: "SOFTWARE"),
        ],
      ),
    );
  }

  Widget _buildModuleView(String tab) {
    return Column(children: [
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE2121E),
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: _isAnalyzing ? null : () => _runDiagnostic(tab),
        child: const Text("LANCER LE DIAGNOSTIC"),
      ),
      const SizedBox(height: 20),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1E).withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _logs[tab]!.length,
            itemBuilder: (context, i) {
              final entry = _logs[tab]![i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  entry['msg']!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _logColor(entry['type']!),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }

  Color _logColor(String type) => switch (type) {
        'error'   => const Color(0xFFFA4D56),
        'success' => const Color(0xFF24A148),
        'warn'    => const Color(0xFFFFB800),
        'sys'     => const Color(0xFF878D96),
        _         => Colors.white70,
      };
}