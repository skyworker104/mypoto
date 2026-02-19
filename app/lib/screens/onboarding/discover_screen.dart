import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_config.dart';
import '../../services/discovery_service.dart';
import '../../models/server_info.dart';

/// Server discovery screen - finds PhotoNest servers via mDNS.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _discovery = DiscoveryService();
  final _ipController = TextEditingController();
  List<ServerInfo> _servers = [];
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  Future<void> _startSearch() async {
    _discovery.serversStream.listen((servers) {
      if (mounted) setState(() => _servers = servers);
    });
    await _discovery.startDiscovery();

    // Stop searching after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _searching = false);
    });
  }

  void _connectTo(ServerInfo server) {
    context.push('/pin', extra: server.baseUrl);
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    // Always use default port - user only enters IP address
    final cleanIp = ip.replaceAll(RegExp(r':\d+$'), '');
    context.push('/pin', extra: 'http://$cleanIp:${AppConfig.defaultPort}');
  }

  @override
  void dispose() {
    _discovery.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Text('PhotoNest',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              Text('가족 사진을 안전하게 백업하세요',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey,
                      )),
              const SizedBox(height: 48),
              // Server search
              Row(
                children: [
                  Text('서버 찾는 중...',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_searching) ...[
                    const SizedBox(width: 12),
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Found servers
              Expanded(
                child: _servers.isEmpty
                    ? Center(
                        child: _searching
                            ? const Text('Wi-Fi 네트워크에서 서버를 찾고 있습니다...')
                            : const Text('서버를 찾지 못했습니다.\n아래에서 IP를 직접 입력해주세요.',
                                textAlign: TextAlign.center),
                      )
                    : ListView.builder(
                        itemCount: _servers.length,
                        itemBuilder: (_, i) {
                          final s = _servers[i];
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.dns, size: 36),
                              title: Text(s.name),
                              subtitle: Text('${s.host}:${s.port}'),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () => _connectTo(s),
                            ),
                          );
                        },
                      ),
              ),
              // Manual IP entry
              const Divider(),
              const SizedBox(height: 8),
              Text('서버 IP 직접 입력', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('포트는 자동으로 ${AppConfig.defaultPort}이 사용됩니다',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.wifi, size: 20),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onSubmitted: (_) => _connectManual(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _connectManual,
                    child: const Text('연결'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
