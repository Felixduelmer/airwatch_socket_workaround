import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

import '../air_watch_socket_workaround.dart';

@visibleForTesting
class ContentTypeBasedHttpRequestBodyProviderFactory implements HttpRequestBodyProviderFactory {
  HttpRequestBodyProvider build(ContentType contentType) {
    final primaryType = contentType.primaryType;
    final subType = contentType.subType;

    switch (primaryType) {
      case "audio":
      case "video":
      case "image":
        return RawBodyProvider();
      case "multipart":
        return MultipartBodyProvider();
      case "application":
        if (subType == 'json') return StringBodyProvider();

        return RawBodyProvider();
      case "text":
        return StringBodyProvider();
      default:
        throw ArgumentError('Content types allowed are:'
            ' multipart/form-data, application/json, text/plain,'
            ' application/octet-stream or any audio, video or image one.');
    }
  }
}

@visibleForTesting
class MultipartBodyProvider implements HttpRequestBodyProvider {
  @override
  Future<String> getBody(BaseRequest request) async {
    if (request is MultipartRequest) {
      List<MultipartMessage> messages = [];

      await Future.forEach(request.files, (file) async {
        final bytes = await (file as MultipartFile).finalize().toBytes();
        final contentType = ContentType.parse(file.contentType.mimeType);

        messages.add(MultipartMessage.fromBytes(file.field, bytes, contentType: contentType));
      });

      return jsonEncode(messages.map((e) => e.toJson()).toList(growable: false));
    } else {
      throw ArgumentError('Provided request is not a valid Multipart one');
    }
  }

  @override
  Encoding getEncoding(BaseRequest request) {
    return utf8;
  }
}

@visibleForTesting
class StringBodyProvider implements HttpRequestBodyProvider {
  @override
  Future<String> getBody(BaseRequest request) async {
    if (request is Request) {
      return request.body;
    } else {
      throw ArgumentError('Provided request is not a valid one with a String body');
    }
  }

  @override
  Encoding getEncoding(BaseRequest request) {
    if (request is Request) {
      return request.encoding;
    } else {
      throw ArgumentError('Provided request is not a valid one with a String body');
    }
  }
}

@visibleForTesting
class RawBodyProvider implements HttpRequestBodyProvider {
  @override
  Future<Uint8List> getBody(BaseRequest request) async {
    if (request is Request) {
      return request.bodyBytes;
    } else {
      throw ArgumentError('Provided request is not a valid one with a Raw bytes body');
    }
  }

  @override
  Encoding getEncoding(BaseRequest request) {
    if (request is Request) {
      return request.encoding;
    } else {
      throw ArgumentError('Provided request is not a valid one with a String body');
    }
  }
}

class MultipartMessage {
  /// The name of the form field.
  final String name;

  /// The size of the file/field in bytes.
  final int length;

  /// The content-type of the file.
  ///
  /// Defaults to `application/octet-stream`.
  final ContentType contentType;

  Uint8List data;

  /// Creates a new [MultipartFile] from an array of bytes, with a default
  /// content-type of `application/octet-stream`.
  MultipartMessage(this.name, this.data, this.length, {ContentType? contentType})
      : contentType = contentType ?? ContentType.binary;

  /// Creates a new [MultipartFile] from a byte array, with a default
  /// content-type of `application/octet-stream`.
  factory MultipartMessage.fromBytes(String field, Uint8List rawBytes, {ContentType? contentType}) {
    return MultipartMessage(field, rawBytes, rawBytes.length,
        contentType: contentType ?? ContentType.binary);
  }

  /// Creates a new [MultipartFile] from a string, with a default content type
  /// of `text/plain` and UTF-8 encoding.
  factory MultipartMessage.fromString(String field, String value, {ContentType? contentType}) {
    contentType ??= ContentType.text;
    final encoder = Encoding.getByName(contentType.charset);

    return MultipartMessage.fromBytes(field, encoder!.encode(value) as Uint8List,
        contentType: contentType);
  }

  /// Creates a new [MultipartFile] from a Json map, with a default content type
  /// of `application/json` and UTF-8 encoding.
  factory MultipartMessage.fromJson(String field, Map<String, dynamic> value,
      {ContentType? contentType}) {
    final jsonEncoded = json.encode(value);

    return MultipartMessage.fromString(field, jsonEncoded,
        contentType: contentType ?? ContentType.json);
  }

  Map<String, dynamic> toJson() =>
      {'name': name, 'length': length, 'contentType': contentType.value, 'data': data};

  static MultipartMessage fromCodec<T>(String field, T value, Codec<T, List<int>> codec,
      {ContentType? contentType}) {
    return MultipartMessage.fromBytes(field, Uint8List.fromList(codec.encode(value)),
        contentType: contentType);
  }
}
