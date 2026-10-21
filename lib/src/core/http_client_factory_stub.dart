import 'package:http/http.dart' as http;

/// Platform default client (the browser's fetch on the web).
http.Client createAppHttpClient() => http.Client();
