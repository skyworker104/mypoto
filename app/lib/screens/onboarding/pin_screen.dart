import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/server_info.dart';
import '../../providers/auth_provider.dart';

/// PIN input screen for server pairing.
class PinScreen extends ConsumerStatefulWidget {
  final String serverHost;

  const PinScreen({super.key, required this.serverHost});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPairing();
  }

  Future<void> _initPairing() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(widget.serverHost);
      final auth = ref.read(authProvider.notifier);
      final server = ServerInfo(
        name: 'PhotoNest',
        host: uri.host,
        port: uri.port,
      );
      await auth.initPairing(server);
    } catch (e) {
      setState(() => _error = '서버에 연결할 수 없습니다: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _error = '6자리 PIN을 입력하세요');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider.notifier);
      await auth.submitPin(
        pin: pin,
        deviceName: 'My Phone',
        deviceType: Platform.isIOS ? 'ios' : 'android',
      );

      if (mounted) {
        // New user needs setup, existing user goes to home
        context.go('/setup');
      }
    } catch (e) {
      setState(() => _error = 'PIN이 올바르지 않습니다');
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('서버 페어링')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phonelink_lock, size: 64, color: Colors.green),
            const SizedBox(height: 24),
            Text('서버 화면에 표시된\nPIN 번호를 입력하세요',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _pinController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitPin(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 14)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submitPin,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('연결하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
