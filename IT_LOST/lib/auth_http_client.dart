import 'package:http/http.dart' as http;

import 'auth_http_client_stub.dart'
    if (dart.library.html) 'auth_http_client_web.dart' as platform;

http.Client createAuthHttpClient() => platform.createAuthHttpClient();
