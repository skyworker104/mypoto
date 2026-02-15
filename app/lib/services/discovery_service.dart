import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import '../models/server_info.dart';

/// mDNS service discovery for finding PhotoNest servers on local network.
class DiscoveryService {
  static const String _serviceType = '_photonest._tcp';

  BonsoirDiscovery? _discovery;
  final _serversController = StreamController<List<ServerInfo>>.broadcast();
  final Map<String, ServerInfo> _found = {};

  Stream<List<ServerInfo>> get serversStream => _serversController.stream;
  List<ServerInfo> get servers => _found.values.toList();

  Future<void> startDiscovery() async {
    _found.clear();
    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.ready;

    _discovery!.eventStream!.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final service = event.service as ResolvedBonsoirService;
        final info = ServerInfo(
          name: service.name,
          host: service.host ?? '',
          port: service.port,
        );
        if (info.host.isNotEmpty) {
          _found[info.host] = info;
          _serversController.add(_found.values.toList());
        }
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        final service = event.service;
        if (service != null) {
          _found.removeWhere((_, v) => v.name == service.name);
        }
        _serversController.add(_found.values.toList());
      }
    });

    _discovery!.start();
  }

  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    _discovery = null;
  }

  void dispose() {
    stopDiscovery();
    _serversController.close();
  }
}
