import 'package:chopper/chopper.dart';
import 'package:kover/api/openapi.swagger.dart';
import 'package:kover/riverpod/providers/settings/credentials.dart';
import 'package:kover/utils/http_client/http_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'client.g.dart';

/// Skips JSON decoding for non-JSON bodies (images, PDFs, fonts), which the
/// generated converter would otherwise needlessly turn into strings.
class _ContentAwareConverter extends $JsonSerializableConverter {
  @override
  FutureOr<Response<ResultType>> convertResponse<ResultType, Item>(
    Response response,
  ) {
    final contentType = response.headers['content-type'];
    if (contentType != null &&
        !contentType.contains('json') &&
        !contentType.startsWith('text/')) {
      return response.copyWith<ResultType>();
    }
    return super.convertResponse<ResultType, Item>(response);
  }
}

ChopperClient getChopperClient(
  Uri uri,
  String apiKey, {
  Map<String, String> customHeaders = const {},
  bool ignoreCertificateValidation = false,
}) {
  return ChopperClient(
    baseUrl: uri,
    client: createHttpClient(
      ignoreCertificateValidation: ignoreCertificateValidation,
    ),
    interceptors: [
      HeadersInterceptor({
        'x-api-key': apiKey,
        "Content-Type": "application/json",
        ...customHeaders,
      }),
    ],
    converter: _ContentAwareConverter(),
  );
}

@Riverpod(keepAlive: true)
ChopperClient authenticatedClient(Ref ref) {
  final settings = ref.watch(credentialsProvider).value;
  final key = ref.watch(apiKeyProvider);

  if (settings?.url == null || settings?.apiKey == null) {
    throw Exception('Credentials not set in settings');
  }

  final uri = Uri.tryParse(settings!.url!);
  if (uri == null) {
    throw Exception('Invalid URL in settings');
  }

  final httpClient = createHttpClient(
    ignoreCertificateValidation: settings.ignoreCertificateValidation,
  );
  if (httpClient != null) ref.onDispose(httpClient.close);

  final client = ChopperClient(
    baseUrl: uri,
    client: httpClient,
    interceptors: [
      HeadersInterceptor({
        'x-api-key': key!,
        "Content-Type": "application/json",
        ...settings.customHeaders,
      }),
    ],
    converter: _ContentAwareConverter(),
  );

  return client;
}

@Riverpod(keepAlive: true)
Openapi restClient(Ref ref) {
  final client = ref.watch(authenticatedClientProvider);
  return Openapi.create(client: client);
}
