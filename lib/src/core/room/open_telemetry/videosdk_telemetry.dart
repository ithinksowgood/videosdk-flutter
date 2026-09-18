// ignore_for_file: prefer_typing_uninitialized_variables, strict_top_level_inference

import 'dart:developer';
import 'package:videosdk_otel/api.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'package:videosdk_otel/sdk.dart' as otel_sdk;
import 'package:videosdk/src/core/room/open_telemetry/tracer_provider_interface.dart';
import 'package:videosdk/src/core/room/open_telemetry/videosdk_log.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/telemetry_output.dart'
    as tracing;
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/backend_log_output.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/sdk_tracer.dart';

class VideoSDKTelemetery {
  late Span _rootSpan;
  late Tracer tracer;
  late otel_sdk.TracerProviderBase provider;
  static var _roomId;
  static var _peerId;

  late BackendLogOutput _backendLogOutput;

  VideoSDKTelemetery({
    required roomId,
    required peerId,
    required observabilityJwt,
    required traces,
    required logs,
    required deviceInfo,
    required debugMode,
    required metaData,
  }) {
    try {
      if (!traces['enabled']) {
        return;
      }

      _roomId = roomId;
      _peerId = peerId;

      _backendLogOutput = BackendLogOutput(
        roomId: roomId,
        peerId: peerId,
        logs: logs,
        observabilityJwt: observabilityJwt,
        deviceInfo: deviceInfo,
        debugMode: debugMode,
      );
      SdkTracer.shared.registerOutput(_backendLogOutput);

      final exporter = otel_sdk.CollectorExporter(
          Uri.parse(traces['pbEndPoint']),
          jwtKey: observabilityJwt);

      final processor = otel_sdk.BatchSpanProcessor(exporter);

      provider = TracerProviderInterface(processor).provider;

      tracer = provider.getTracer(peerId);

      _rootSpan = tracer
          .startSpan('room_${roomId}_peer_${peerId}_sdk_flutter', attributes: [
        Attribute.fromString("roomId", roomId),
        Attribute.fromString("peerId", peerId),
        Attribute.fromString("sdkName", "flutter"),
        Attribute.fromString("userId", metaData['userId']),
        Attribute.fromString("email", metaData['email']),
      ]);

      // if (_rootSpan.spanContext.isValid) {
      //   _backendLogOutput
      //       .setSessionId(_rootSpan.spanContext.traceId.toString());
      // }
      _rootSpan.end();
      tracing.TelemetryOutput.setTelemetry(this);
    } catch (error) {
      //
      VideoSDKLog.createLog(
          message:
              "error in VideoSDKTelemetery :: setExporter \n ${error.toString()}",
          logLevel: "ERROR");
      //
      log("error in setExporter $error");
    }
  }

  Span trace(
      {required String spanName, List<Attribute>? attributes, Span? span}) {
    Span parentSpan;
    if (span != null) {
      parentSpan = span;
    } else {
      parentSpan = getCurrentSpan();
    }

    Span? createdSpan;
    Context.current.withSpan(parentSpan).execute(() {
      createdSpan = tracer.startSpan(spanName);
      attributes ??= [];
      attributes!.add(Attribute.fromString("roomId", _roomId));
      attributes!.add(Attribute.fromString("peerId", _peerId));
      attributes!.add(Attribute.fromString("sdkName", "flutter"));
      if (VideoSDKLog.sessionId != null) {
        attributes!
            .add(Attribute.fromString("sessionId", VideoSDKLog.sessionId!));
      }
      createdSpan!.setAttributes(attributes!);
    });
    return createdSpan!;
  }

  Span getCurrentSpan() {
    Span? immmediateParentSpan = Context.current.span;
    immmediateParentSpan ??= _rootSpan;
    return immmediateParentSpan;
  }

  traceAutoComplete({
    required String spanName,
    List<Attribute>? attributes,
    Span? span,
    StatusCode status = StatusCode.ok,
    String message = "SUCCESS",
  }) {
    Span parentSpan;
    if (span != null) {
      parentSpan = span;
    } else {
      parentSpan = _rootSpan;
    }
    Context.current.withSpan(parentSpan).execute(() {
      Span createdSpan = tracer.startSpan(spanName);
      attributes ??= [];
      attributes!.add(Attribute.fromString("roomId", _roomId));
      attributes!.add(Attribute.fromString("peerId", _peerId));
      attributes!.add(Attribute.fromString("sdkName", "flutter"));
      if (VideoSDKLog.sessionId != null) {
        attributes!
            .add(Attribute.fromString("sessionId", VideoSDKLog.sessionId!));
      }
      createdSpan.setAttributes(attributes!);
      createdSpan.setStatus(status, description: message);
      createdSpan.end();
    });
  }

  completeSpan(
      {required Span span,
      required StatusCode status,
      required String message}) {
    span.setStatus(status, description: message);
    span.end();
  }

  void forceFlush() {
    try {
      // The BatchSpanProcessor will flush all pending spans
      provider.forceFlush();
    } catch (error) {
      VideoSDKLog.createLog(
          message: "Error in forceFlush :: ${error.toString()}",
          logLevel: "WARN");
      log("error in forceFlush $error");
    }
  }

  void flush() {
    try {
      // Only force flush to send all pending data
      // Skip shutdown to avoid abort errors on app/page close
      forceFlush();
    } catch (error) {
      // Silently handle abort errors - they occur when the connection closes
      // before telemetry data can be sent, which is expected on app/page close
      if (!error.toString().contains('abortTrigger') &&
          !error.toString().contains('REQUEST_ABORTED')) {
        VideoSDKLog.createLog(
            message: "Error in flush :: ${error.toString()}", logLevel: "WARN");
        log("error in flush $error");
      }
    }
  }

  void dispose() {
    try {
      // Only unregister the backend log output from SdkTracer
      // Keep ConsoleOutput and TelemetryOutput registered as they are global
      SdkTracer.shared.unregisterOutput(_backendLogOutput);
      // Clear telemetry output reference
      tracing.TelemetryOutput.clearTelemetry();
    } catch (error) {
      log("error in dispose $error");
    }
  }
}
