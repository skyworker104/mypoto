/// Discovered server info from mDNS or manual entry.
class ServerInfo {
  final String name;
  final String host;
  final int port;
  final String? serverId;

  const ServerInfo({
    required this.name,
    required this.host,
    required this.port,
    this.serverId,
  });

  String get baseUrl => 'http://$host:$port';
  String get apiUrl => '$baseUrl/api/v1';

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      name: json['name'] as String? ?? 'PhotoNest Server',
      host: json['host'] as String,
      port: json['port'] as int? ?? 8080,
      serverId: json['server_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'server_id': serverId,
      };
}
