import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:isolated_http_client/isolated_http_client.dart';
import 'package:isolated_http_client/src/utils.dart';
import 'package:worker_manager/worker_manager.dart';

import 'exceptions.dart';
import 'http_method.dart';
import 'response.dart';
import 'requests.dart';

abstract class HttpClient {
  factory HttpClient(
          {Duration timeout = const Duration(seconds: 10), bool log = false}) =>
      IsolatedHttpClient(timeout, log);

  Cancelable<Response> get({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    bool fakeIsolate = false,
  });

  Cancelable<Response> head({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    bool fakeIsolate = false,
  });

  Cancelable<Response> post({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    Map<String, dynamic> body = const <String, Object>{},
    bool fakeIsolate = false,
  });

  Cancelable<Response> put({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    Map<String, dynamic> body = const <String, Object>{},
    bool fakeIsolate = false,
  });

  Cancelable<Response> delete({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    Map<String, dynamic> body = const <String, Object>{},
    bool fakeIsolate = false,
  });

  Cancelable<Response> patch({
    required String host,
    String path,
    Map<String, String> query,
    Map<String, String> headers,
    Map<String, dynamic> body = const <String, Object>{},
    bool fakeIsolate = false,
  });

  Cancelable<Response> request({
    required BaseRequestBundle bundle,
    bool fakeIsolate = false,
  });
}

class IsolatedHttpClient implements HttpClient {
  final Duration timeout;
  final bool log;

  IsolatedHttpClient(this.timeout, this.log);

  Response _checkedResponse(
      Response response, BaseRequestBundle requestBundle) {
    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) return response;
    if (statusCode == 401) {
      throw HttpUnauthorizedException(response.body, requestBundle);
    }
    if (statusCode >= 400 && statusCode < 500) {
      throw HttpClientException(response.body, requestBundle);
    }
    if (statusCode >= 500 && statusCode < 600) {
      throw HttpServerException(response.body, requestBundle);
    }
    throw HttpUnknownException(response.body, requestBundle);
  }

  @override
  Cancelable<Response> get({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.get,
      host: host,
      path: path,
      query: query,
      headers: headers,
      fakeIsolate: fakeIsolate,
    );
  }

  @override
  Cancelable<Response> head({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.head,
      host: host,
      path: path,
      query: query,
      headers: headers,
      fakeIsolate: fakeIsolate,
    );
  }

  @override
  Cancelable<Response> post({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.post,
      host: host,
      path: path,
      query: query,
      headers: headers,
      body: body,
      fakeIsolate: fakeIsolate,
    );
  }

  @override
  Cancelable<Response> put({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.put,
      host: host,
      path: path,
      query: query,
      headers: headers,
      body: body,
      fakeIsolate: fakeIsolate,
    );
  }

  @override
  Cancelable<Response> delete({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.delete,
      host: host,
      path: path,
      query: query,
      headers: headers,
      body: body,
      fakeIsolate: fakeIsolate,
    );
  }

  @override
  Cancelable<Response> patch({
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    bool fakeIsolate = false,
  }) {
    return _send(
      method: HttpMethod.patch,
      host: host,
      path: path,
      query: query,
      headers: headers,
      body: body,
      fakeIsolate: fakeIsolate,
    );
  }

  Cancelable<Response> _send({
    required String method,
    required String host,
    String path = '',
    Map<String, String> query = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    bool fakeIsolate = false,
  }) {
    final queryString = makeQuery(query);
    final fullPath = '$host$path$queryString';
    final bundle = RequestBundle(method, fullPath, query, headers, body: body);
    return request(bundle: bundle, fakeIsolate: fakeIsolate);
  }

  @override
  Cancelable<Response> request({
    required BaseRequestBundle bundle,
    bool fakeIsolate = false,
  }) {
    final execution = fakeIsolate
        ? Executor()
            .fakeExecute(arg1: bundle, arg2: timeout, arg3: log, fun3: _request)
        : Executor()
            .execute(arg1: bundle, arg2: timeout, arg3: log, fun3: _request);

    return execution.next(onValue: (value) {
      return _checkedResponse(value, bundle);
    });
  }

  static Future<Response> _request(
      BaseRequestBundle bundle, Duration timeout, bool log) async {
    try {
      final request = await bundle.toRequest();

      if (log) {
        if (request is http.Request) {
          final bodyLine =
              request.body.isEmpty ? '' : ',\nbody: ${request.body}';
          print(
              'url: [${request.method}] ${request.url},\nheaders: ${request.headers}$bodyLine');
        } else {
          print(
              'url: [${request.method}] ${request.url},\nheaders: ${request.headers},\nbody: <unknown>');
        }
      }

      final httpResponse = await request.send().timeout(timeout);
      final bodyString = await httpResponse.stream.bytesToString();
      final body = bodyString.isNotEmpty
          ? jsonDecode(bodyString) as Map<String, dynamic>
          : <String, dynamic>{};

      final isolatedResponse =
          Response(body, httpResponse.statusCode, httpResponse.headers);
      if (log) {
        print(isolatedResponse);
      }
      return isolatedResponse;
    } catch (e) {
      rethrow;
    }
  }
}
