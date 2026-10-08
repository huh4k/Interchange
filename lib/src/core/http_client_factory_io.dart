import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// A client that keeps idle connections open for 40 s.
///
/// The default 15 s idle timeout closes the keep-alive connection before the
/// next 30 s refresh, so every refresh would otherwise pay a fresh TCP+TLS
/// handshake.
http.Client createAppHttpClient() => IOClient(
      HttpClient()
        ..idleTimeout = const Duration(seconds: 40)
        ..connectionTimeout = const Duration(seconds: 10),
    );
