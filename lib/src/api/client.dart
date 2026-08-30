import 'models.dart';

class ApiClient {
  const ApiClient({required this.baseUrl});
  final String baseUrl;

  ConnectionStatus snapshot() =>
      ConnectionStatus(connected: false, endpoint: baseUrl);
}
