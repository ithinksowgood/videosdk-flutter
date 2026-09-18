// ignore_for_file: no_leading_underscores_for_local_identifiers, constant_identifier_names, strict_top_level_inference

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:videosdk/src/core/room/codec.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/component_category.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/event_category.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/output_target.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/sdk_tracer.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/span_scope.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';
import 'package:random_string/random_string.dart';
import 'package:videosdk/src/core/room/custom_track_configs.dart';
import 'package:videosdk/src/core/room/events.dart';
import 'package:videosdk/src/core/webrtc/src/handlers/unified_plan.dart';
import 'package:videosdk/videosdk_platform_interface.dart';
import 'package:videosdk/src/core/utils/event_emitter.dart';

import '../../videosdk.dart';
import '../utils/constants.dart';

/// VideoSDK Class is a core class of SDK that provides methods to create and configure VideoSDK Room.
class VideoSDK {
  /// @nodoc
  VideoSDK();

  // Method channel to  communicate with platform
  static const MethodChannel _channel = MethodChannel('videosdk');
  static const EventChannel _eventChannel = EventChannel('videosdk-event');
  static LogLevel get logLevel => SdkTracer.shared.getLogLevel();

  /// Stores the available media devices grouped by their type.
  ///
  /// This map maintains a list of media devices categorized by
  /// [MediaDeviceType], such as audio input, audio output, and video input.
  ///
  /// ### Type
  ///
  /// - `Map<MediaDeviceType, List<MediaDeviceInfo>>`
  static final Map<MediaDeviceType, List<MediaDeviceInfo>> mediaDevices = {};

  static final EventEmitter _eventEmitter = EventEmitter();

  /// The active key provider used for end-to-end encryption (E2EE).
  ///
  /// This holds the configured [BaseKeyProvider] instance responsible
  /// for managing encryption keys.
  ///
  /// ### Type
  ///
  /// - `BaseKeyProvider?`
  static BaseKeyProvider? keyProvider;

  /// Indicates the type of end-to-end encryption currently in use.
  ///
  /// Possible values represent whether encryption is applied at the
  /// meeting level or the participant level.
  ///
  /// ### Type
  ///
  /// - `String?`
  static String? e2eeType;

  /// @nodoc
  @override
  String toString() {
    return super.toString();
  }

  /// @nodoc
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// @nodoc
  @override
  bool operator ==(Object other) {
    return super == other;
  }

  /// @nodoc
  @override
  int get hashCode => super.hashCode;

  /// Creates and initializes a new room instance.
  ///
  /// This method prepares a [Room] object with the provided configuration
  /// and returns it without immediately joining the room. You can use the
  /// returned room instance to register event listeners and then join the room.
  ///
  /// ### **Parameters**
  ///
  /// - [roomId]:
  ///   The unique identifier of the room to join.
  ///
  /// - [displayName]:
  ///   The display name of the local participant.
  ///
  /// - [token]:
  ///   A valid VideoSDK authentication token.
  ///
  /// - [micEnabled] *(optional)*:
  ///   Determines whether the microphone is enabled when joining the room.
  ///   Defaults to `true`.
  ///
  /// - [camEnabled] *(optional)*:
  ///   Determines whether the camera is enabled when joining the room.
  ///   Defaults to `true`.
  ///
  /// - [participantId] *(optional)*:
  ///   A unique identifier for the local participant.
  ///   If not provided, a random ID is generated.
  ///
  /// - [maxResolution] *(optional)*:
  ///   Specifies the maximum video resolution.
  ///   Defaults to `'sd'`.
  ///
  /// - [defaultCameraIndex] *(optional)*:
  ///   The index of the camera device to use by default.
  ///   Defaults to `0`.
  ///
  /// - [multiStream] *(optional)*:
  ///   Enables or disables multi-stream (simulcast) video publishing.
  ///   Defaults to `true`.
  ///
  /// - [customCameraVideoTrack] *(optional)*:
  ///   A custom camera video track created using
  ///   `createCameraVideoTrack()`.
  ///
  /// - [customMicrophoneAudioTrack] *(optional)*:
  ///   A custom microphone audio track created using
  ///   `createMicrophoneAudioTrack()`.
  ///
  /// - [notification] *(optional)*:
  ///   Notification configuration used during screen sharing.
  ///   Defaults to a predefined [NotificationInfo].
  ///
  /// - [mode] *(optional)*:
  ///   The participant mode that defines media behavior.
  ///   Defaults to [Mode.SEND_AND_RECV].
  ///
  /// - [metaData] *(optional)*:
  ///   Custom metadata associated with the participant.
  ///   Defaults to an empty map.
  ///
  /// - [signalingBaseUrl] *(optional)*:
  ///   The base URL for the signaling server.
  ///   Defaults to `api.videosdk.live`.
  ///
  /// - [preferredProtocol] *(optional)*:
  ///   Specifies the preferred transport protocol for signaling.
  ///   Defaults to [PreferredProtocol.UDP_OVER_TCP].
  ///
  /// - [debugMode] *(optional)*:
  ///   Enables or disables debug logging.
  ///   Defaults to `true`.
  ///
  /// - [translationLanguage] *(optional)*:
  ///   The language code used for real-time translation.
  ///
  /// - [speakingLanguage] *(optional)*:
  ///   The language code representing the participant’s spoken language.
  ///
  /// - [autoConsume] *(optional)*:
  ///   Enables or disables automatic consumption of streams.
  ///
  /// - [codecSwitchEnabled] *(optional)*:
  ///   Automatically falls back to VP8 when the receiving device cannot consume the selected video codec.
  ///   Defaults to `true`.
  ///
  /// ### Returns
  ///
  /// - A [Room] instance configured with the provided options.
  ///
  /// ### Throws
  ///
  /// - Throws an error if the provided [token] is empty or invalid.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// final room = VideoSDK.createRoom(
  ///   roomId: 'my-room-id',
  ///   displayName: 'John Doe',
  ///   token: '<VIDEOSDK_TOKEN>',
  ///   micEnabled: true,
  ///   camEnabled: true,
  ///   mode: Mode.SEND_AND_RECV,
  ///   metaData: {
  ///     'role': 'host',
  ///   },
  /// );
  ///
  /// // Register event listeners
  /// room.on(Events.roomJoined, () {
  ///   print('Joined room successfully');
  /// });
  ///
  /// // Join the room
  /// await room.join();
  /// ```
  static Room createRoom({
    required String roomId,
    required String displayName,
    required String token,
    bool micEnabled = true,
    bool camEnabled = true,
    String participantId = '',
    String maxResolution = 'sd',
    int defaultCameraIndex = 0,
    bool multiStream = true,
    CustomTrack? customCameraVideoTrack,
    CustomTrack? customMicrophoneAudioTrack,
    NotificationInfo notification = const NotificationInfo(
      title: "Video SDK",
      message: "Video SDK is sharing screen in the meeting",
      icon: "notification_share",
    ),
    Mode mode = Mode.SEND_AND_RECV,
    Map<String, dynamic> metaData = const {},
    String signalingBaseUrl = '',
    PreferredProtocol preferredProtocol = PreferredProtocol.UDP_OVER_TCP,
    bool debugMode = true,
    String? translationLanguage,
    String? speakingLanguage,
    bool autoConsume = true,
    bool codecSwitchEnabled = true,
    bool enableBatching = true,
  }) =>
      _createRoom(
        roomId: roomId,
        displayName: displayName,
        token: token,
        micEnabled: micEnabled,
        camEnabled: camEnabled,
        participantId: participantId,
        maxResolution: maxResolution,
        defaultCameraIndex: defaultCameraIndex,
        multiStream: multiStream,
        customCameraVideoTrack: customCameraVideoTrack,
        customMicrophoneAudioTrack: customMicrophoneAudioTrack,
        notification: notification,
        mode: mode,
        metaData: metaData,
        signalingBaseUrl: signalingBaseUrl,
        preferredProtocol: preferredProtocol,
        debugMode: debugMode,
        translationLanguage: translationLanguage,
        speakingLanguage: speakingLanguage,
        autoConsume: autoConsume,
        codecSwitchEnabled: codecSwitchEnabled,
        enableBatching: enableBatching,
      );

  static Room _createRoom(
      {required String roomId,
      required String displayName,
      required String token,
      bool micEnabled = true,
      bool camEnabled = true,
      String participantId = '',
      String maxResolution = 'sd',
      int defaultCameraIndex = 0,
      bool multiStream = true,
      CustomTrack? customCameraVideoTrack,
      CustomTrack? customMicrophoneAudioTrack,
      NotificationInfo notification = const NotificationInfo(
        title: "Video SDK",
        message: "Video SDK is sharing screen in the meeting",
        icon: "notification_share",
      ),
      // Mode mode = Mode.CONFERENCE,
      Mode mode = Mode.SEND_AND_RECV,
      Map<String, dynamic> metaData = const {},
      String signalingBaseUrl = '',
      PreferredProtocol preferredProtocol = PreferredProtocol.UDP_OVER_TCP,
      bool debugMode = true,
      String? translationLanguage,
      String? speakingLanguage,
      bool autoConsume = true,
      bool codecSwitchEnabled = true,
      bool enableBatching = true}) {
    SpanScope initMeetingSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Initializing the meeting',
              attributes: {
                'roomId': roomId,
                'displayName': displayName,
                'participantId': participantId,
                'maxResolution': maxResolution,
                'defaultCameraIndex': defaultCameraIndex,
                'multiStream': multiStream,
                'customCameraVideoTrack': customCameraVideoTrack != null
                    ? customCameraVideoTrack.toMap()
                    : "null",
                'customMicrophoneAudioTrack': customMicrophoneAudioTrack != null
                    ? customMicrophoneAudioTrack.toMap()
                    : "null",
                'notification': notification.toJson(),
                'mode': mode,
                'metaData': metaData,
                'signalingBaseUrl': signalingBaseUrl,
                'preferredProtocol': preferredProtocol,
                'debugMode': debugMode,
                'translationLanguage': translationLanguage,
                'speakingLanguage': speakingLanguage,
                'autoConsume': autoConsume,
              },
              component: ComponentCategory.meeting,
              category: EventCategory.telemetry,
            );
    //
    participantId = participantId.isNotEmpty ? participantId : randomAlpha(8);

    signalingBaseUrl =
        signalingBaseUrl.isNotEmpty ? signalingBaseUrl : "api.videosdk.live";

    //
    if (token.isEmpty) {
      SdkTracer.shared.endSpan(
        initMeetingSpan,
        attributes: {
          'error': 'Please provide token to proceed!',
        },
        message: "Error while initialising the meeting",
      );
      throw "Please provide a valid Token or non-empty Token.";
    }
    if (roomId.isEmpty || roomId.trim().isEmpty) {
      SdkTracer.shared.endSpan(
        initMeetingSpan,
        attributes: {
          'error': 'Please provide meetingId to proceed!',
        },
        message: "Error while initialising the meeting",
      );
      throw "Please provide a non-empty meetingId.";
    }
    // Propagate selected bitrate mode into capabilities

    Room room = Room(
      participantId: participantId,
      displayName: displayName,
      maxResolution: maxResolution,
      camEnabled: camEnabled,
      micEnabled: micEnabled,
      meetingId: roomId,
      multiStream: multiStream,
      token: token,
      notification: notification,
      defaultCameraIndex: defaultCameraIndex,
      customCameraVideoTrack: customCameraVideoTrack,
      customMicrophoneAudioTrack: customMicrophoneAudioTrack,
      mode: mode,
      metaData: metaData,
      signalingBaseUrl: signalingBaseUrl,
      preferredProtocol: preferredProtocol,
      debugMode: debugMode,
      translationLanguage: translationLanguage,
      speakingLanguage: speakingLanguage,
      autoConsume: autoConsume,
      codecSwitchEnabled: codecSwitchEnabled,
      enableBatching: enableBatching,
    );

    if (!kIsWeb) {
      if (!Platform.isMacOS && !Platform.isWindows) {
        _eventChannel.receiveBroadcastStream().listen((event) {
          if (event == "STOP_SCREENSHARE") {
            //The ungated internal entry point: this is the SDK reacting to the
            //platform, not the app calling in.
            room.disableShare();
          } else if (event == "START_SCREENSHARE") {
            room.enableShare(null, iosPermissionGiven: true);
          }
        });
      }
    }

    SdkTracer.shared.endSpan(initMeetingSpan,
        message: "Meeting initialised successfully and ready to join!");
    //
    return room;
  }

  /// Configures the logging level for SDK.
  ///
  /// Log levels control how much diagnostic information the SDK emits. They allow you to adjust logging verbosity based on your debugging needs without affecting SDK behavior.
  ///
  /// Log levels (from least to most verbose):
  /// - [LogLevel.none] : Disables all logging output. No logs will be printed.
  /// - [LogLevel.error] : Displays only critical failures and unrecoverable issues.
  /// - [LogLevel.warn] : Displays warnings and errors. Warnings indicate recoverable anomalies.
  /// - [LogLevel.info] : Displays standard SDK activity logs including lifecycle events and state transitions. (default)
  /// - [LogLevel.debug]: Displays detailed diagnostic logs for debugging SDK behavior and internal operations.
  /// - [LogLevel.all] : Enables extremely verbose logging including high-frequency real-time events.
  ///
  /// ### **Parameters**
  ///
  /// - [level]:
  ///   The desired logging level. See [LogLevel] for the available options.
  ///   Defaults to [LogLevel.info].
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// VideoSDK.setLogLevel(LogLevel.debug);
  /// ```
  static void setLogLevel([LogLevel? level = LogLevel.info]) =>
      _setLogLevel(level ?? LogLevel.info);
  static void _setLogLevel(LogLevel level) {
    SdkTracer.shared.setLogLevel(level);

    SdkTracer.shared
        .to(OutputTarget.toConsole, OutputTarget.toTelemetry)
        .traceEvent(
            name: "VideoSDK Log Level set to: ${level.name}",
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry);
  }

  static void _registerForDeviceChange() async {
    SpanScope registerDeviceChangeSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Registering Device Change Listener',
              component: ComponentCategory.media,
            );
    try {
      navigator.mediaDevices.ondevicechange = (event) => {
            navigator.mediaDevices.enumerateDevices().then((devices) {
              try {
                updateDeviceList(devices);
                SdkTracer.shared.traceEvent(
                    spanName: "Emitting DEVICE_CHANGED Event",
                    attributes: {
                      "deviceCount": devices.length.toString(),
                    },
                    component: ComponentCategory.media,
                    category: EventCategory.telemetry);
                _eventEmitter.emit(
                    Events.deviceChanged.parseToString(), devices);
                if (!kIsWeb) {
                  if (Platform.isIOS) {
                    // set videoChat mode whenever new device connected
                    setAppleAudioConfiguration();
                  }
                }
              } catch (e) {
                SdkTracer.shared.traceEvent(
                    spanName: "Error in Device Change Handler",
                    attributes: {
                      "error": e.toString(),
                    },
                    component: ComponentCategory.media,
                    category: EventCategory.telemetry);
              }
            })
          };
      SdkTracer.shared.endSpan(registerDeviceChangeSpan,
          message: "Device change listener registered successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(registerDeviceChangeSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while registering device change listener");
    }
  }

  /// It is used to listen to `VideoSDK` related events and perform actions based on those events.
  ///
  /// #### Parameters
  ///
  /// - [event]
  ///   - type: [Events]
  ///   - This will specify the event to be listened. It defines which particular event from the VideoSDK class you are subscribing to.
  ///
  /// - eventHandler
  ///   - type: [Function]
  ///   - This will be invoked whenever the specified event occurs. The function is executed with relevant data whenever the event is triggered.
  ///
  /// #### Returns
  ///
  /// - `void`
  ///
  /// #### Example
  ///
  /// ```dart
  /// VideoSDK.on(Events.deviceChanged, () {
  ///   // do something
  /// });
  /// ```
  static on(Events event, Function handler) => _on(event, handler);
  static _on(Events event, Function handler) {
    SpanScope onEventSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Registering ${event.name} Event Handler',
              attributes: {
                "event": event.parseToString(),
              },
              component: ComponentCategory.meeting,
            );
    try {
      if (event == Events.deviceChanged) {
        _eventEmitter.on(event.parseToString(), handler);
        _registerForDeviceChange();
      } else if (event == Events.error) {
        _eventEmitter.on(event.parseToString(), handler);
      } else {
        throw Error();
      }
      SdkTracer.shared.endSpan(onEventSpan,
          message: "Event handler registered successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(onEventSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while registering event handler");
      rethrow;
    }
  }

  /// It is used to stop listening to `VideoSDK` related events.
  ///
  /// #### Parameters
  ///
  /// - [event]
  ///   - type: [Events]
  ///   - This will specify the event to be un-listened.
  ///
  /// - eventHandler
  ///   - type: [Function]
  ///   - The handler that was previously registered.
  ///
  /// #### Returns
  ///
  /// - `void`
  static off(Events event, Function handler) => _off(event, handler);
  static _off(Events event, Function handler) {
    SpanScope offEventSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Unregistering ${event.name} Event Handler',
              attributes: {
                "event": event.parseToString(),
              },
              component: ComponentCategory.meeting,
            );
    try {
      if (event == Events.deviceChanged) {
        _eventEmitter.remove(event.parseToString(), handler);
      } else if (event == Events.error) {
        _eventEmitter.remove(event.parseToString(), handler);
      } else {
        throw Error();
      }
      SdkTracer.shared.endSpan(offEventSpan,
          message: "Event handler unregistered successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(offEventSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while unregistering event handler");
      rethrow;
    }
  }

  /// @nodoc
  static void requestIOSScreenSharePermission() {
    SpanScope requestScreenSharePermissionSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Requesting iOS Screen Share Permission',
              component: ComponentCategory.media,
            );
    try {
      _channel.invokeMethod('requestScreenSharePermission');
      SdkTracer.shared.endSpan(requestScreenSharePermissionSpan,
          message: "iOS Screen Share Permission requested successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(requestScreenSharePermissionSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while requesting iOS Screen Share Permission");
    }
  }

  /// @nodoc
  static Future<Map<String, dynamic>> getDeviceInfo() async {
    String platform;

    if (kIsWeb) {
      platform = "web";
    } else if (Platform.isAndroid) {
      platform = "android";
    } else if (Platform.isIOS) {
      platform = "ios";
    } else if (Platform.isMacOS) {
      platform = "macos";
    } else if (Platform.isWindows) {
      platform = "windows";
    } else {
      platform = "web";
    }

    final deviceInfo = <String, dynamic>{};

    deviceInfo.addAll(<String, dynamic>{
      "sdkType": 'flutter',
      "sdkVersion": sdkVersion,
      "platform": platform
    });
    if (!kIsWeb) {
      var deviceUserAgent = await _channel.invokeMethod('getDeviceInfo');

      if (deviceUserAgent != null) {
        deviceInfo
            .addAll(<String, dynamic>{"deviceUserAgent": deviceUserAgent});
      }
    } else {
      var browserUserAgent = await VideosdkPlatform.instance.getDeviceInfo();
      if (browserUserAgent != null) {
        deviceInfo
            .addAll(<String, dynamic>{"browserUserAgent": browserUserAgent});
      }
    }
    return deviceInfo;
  }

  /// @nodoc
  static Future<Map<MediaDeviceType, List<MediaDeviceInfo>>>
      loadMediaDevices() async {
    /// Load MediaDevices
    final List<MediaDeviceInfo> devices =
        await navigator.mediaDevices.enumerateDevices();

    updateDeviceList(devices);

    /// Device Change Event, commonly made for inside meeting as well as for VideoSDK.ondeviceChange
    _registerForDeviceChange();

    return mediaDevices;
  }

  /// @nodoc
  static updateDeviceList(List<MediaDeviceInfo> devices) {
    SpanScope updateDeviceListSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Updating Device List',
              attributes: {
                "totalDevices": devices.length.toString(),
                "availableDevices": devices.map((e) => e.toString()),
              },
              component: ComponentCategory.media,
            );
    try {
      // Clear Devices
      mediaDevices[MediaDeviceType.audioInput] = <MediaDeviceInfo>[];
      mediaDevices[MediaDeviceType.audioOutput] = <MediaDeviceInfo>[];
      mediaDevices[MediaDeviceType.videoInput] = <MediaDeviceInfo>[];

      // log("Device List: ${devices.length} ${devices.map((e) => e.kind).join(" ")}");

      // Iterate MediaDevice
      for (MediaDeviceInfo device in devices) {
        // Conditional Checking
        switch (device.kind) {
          case 'audioinput':
            mediaDevices[MediaDeviceType.audioInput]!.add(device);
            break;
          case 'audiooutput':
            mediaDevices[MediaDeviceType.audioOutput]!.add(device);
            break;
          case 'videoinput':
            mediaDevices[MediaDeviceType.videoInput]!.add(device);
            break;
          default:
            break;
        }
      }
      SdkTracer.shared.endSpan(updateDeviceListSpan,
          attributes: {
            "audioInputCount":
                mediaDevices[MediaDeviceType.audioInput]?.length.toString() ??
                    "0",
            "audioOutputCount":
                mediaDevices[MediaDeviceType.audioOutput]?.length.toString() ??
                    "0",
            "videoInputCount":
                mediaDevices[MediaDeviceType.videoInput]?.length.toString() ??
                    "0",
          },
          message: "Device list updated successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(updateDeviceListSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while updating device list");
    }
  }

  // @Deprecated("Use getAudioDevices() method instead")
  // static Future<List<MediaDeviceInfo>?> getAudioOutputDevices() async {
  //   await loadMediaDevices();
  //   return mediaDevices[MediaDeviceType.audioOutput];
  // }
  /// Retrieves the list of available video input devices.
  ///
  /// This method returns a list of [VideoDeviceInfo] objects representing
  /// the currently available video input devices (cameras) on the system.
  ///
  /// Each [VideoDeviceInfo] object contains the following properties:
  ///
  /// - `deviceId`:
  ///   A unique identifier for the video device, persisted across sessions.
  ///
  /// - `kind`:
  ///   An enumerated value indicating the device type.
  ///   For video devices, this value is always `videoinput`.
  ///
  /// - `label`:
  ///   A human-readable description of the device
  ///   (for example, a camera name or manufacturer).
  ///
  /// - `groupId`:
  ///   Identifies the physical device group. Devices that belong to the
  ///   same physical hardware (for example, a monitor with a built-in
  ///   camera and microphone) share the same `groupId`.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a `List<VideoDeviceInfo>?` containing
  ///   the available video input devices.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// Future<void> getVideoDeviceList() async {
  ///   try {
  ///     final List<VideoDeviceInfo>? videoDevices =
  ///         await VideoSDK.getVideoDevices();
  ///
  ///     if (videoDevices != null) {
  ///       for (final device in videoDevices) {
  ///         print('Camera: ${device.label}');
  ///       }
  ///     }
  ///   } catch (e) {
  ///     print('Error while fetching video devices');
  ///   }
  /// }
  /// ```
  static Future<List<VideoDeviceInfo>?> getVideoDevices() => _getVideoDevices();
  static Future<List<VideoDeviceInfo>?> _getVideoDevices() async {
    SpanScope getVideoDevicesSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Getting Video Devices',
              component: ComponentCategory.media,
              category: EventCategory.telemetry,
            );
    MediaStream? mediaStream;
    bool _isFirefox = await isFirefox();
    if (_isFirefox) {
      try {
        mediaStream = await navigator.mediaDevices
            .getUserMedia({'audio': false, 'video': true});
      } catch (e) {
        SdkTracer.shared.to(OutputTarget.toConsole).endSpan(getVideoDevicesSpan,
            attributes: {"error": e.toString()},
            success: false,
            message:
                "Error while getting audio devices: microphone permission not granted");
        if (e ==
            "Unable to getUserMedia: NotAllowedError: The request is not allowed by the user agent or the platform in the current context.") {
          log("Error in getVideoDevices(): The request is not allowed by the user agent or the platform in the current context.");
          return null;
        }
      }
    }
    if (!_isFirefox && kIsWeb) {
      // The deviceId,label of the VideoDevice will be empty if the camera permission is not granted on the web.
      // checkPermission is not supported by Firefox
      final permissions = await checkPermissions(
          permissions: Permissions.video, parentSpan: getVideoDevicesSpan);
      if (!permissions['video']!) {
        SdkTracer.shared.to(OutputTarget.toConsole).endSpan(getVideoDevicesSpan,
            attributes: {"error": "Camera permission not granted"},
            success: false,
            message:
                "Error while getting audio devices: microphone permission not granted");
        //    log("You need camera permission to access list of Video devices.");
        return null;
      }
    }
    final List<MediaDeviceInfo> devices =
        await navigator.mediaDevices.enumerateDevices();
    final List<VideoDeviceInfo> videoDevices = [];
    for (MediaDeviceInfo device in devices) {
      if (device.kind == 'videoinput') {
        videoDevices.add(VideoDeviceInfo(
          deviceId: device.deviceId,
          label: device.label,
          groupId: device.groupId,
          kind: device.kind,
        ));
      }
    }

    if (mediaStream != null) {
      for (var track in mediaStream.getTracks()) {
        track.stop();
        mediaStream!.dispose();
        mediaStream = null;
      }
    }

    SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
          getVideoDevicesSpan,
          attributes: {
            "videoDeviceCount": jsonEncode(videoDevices
                .map((e) => {
                      "deviceId": e.deviceId,
                      "label": e.label,
                      "kind": e.kind,
                    })
                .toList()),
          },
          message: "Video devices retrieved successfully",
        );
    return videoDevices;
  }

  /// Retrieves the list of available audio devices on the system.
  ///
  /// This method returns a list of [AudioDeviceInfo] objects representing
  /// the currently available audio input and/or output devices, depending
  /// on the platform.
  ///
  /// Each [AudioDeviceInfo] object contains the following properties:
  ///
  /// - `deviceId`:
  ///   A unique identifier for the audio device, persisted across sessions.
  ///
  /// - `kind`:
  ///   Indicates whether the device is an audio input (`audioinput`)
  ///   or audio output (`audiooutput`).
  ///
  /// - `label`:
  ///   A human-readable description of the device
  ///   (for example, `BLUETOOTH`, `WIRED_HEADSET`).
  ///
  /// - `groupId`:
  ///   Identifies the physical device group. Devices that belong to the
  ///   same physical hardware (for example, a monitor with a built-in
  ///   microphone and speaker) share the same `groupId`.
  ///
  /// > **Note (iOS-specific behavior):**
  /// > - `EARPIECE` is not available when a `WIRED_HEADSET` or `BLUETOOTH`
  /// >   device is connected.
  /// > - `WIRED_HEADSET` and `BLUETOOTH` devices cannot be used
  /// >   simultaneously. Priority is given to the most recently
  /// >   connected device.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a `List<AudioDeviceInfo>?` containing
  ///   the available audio devices.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  /// import 'dart:io';
  ///
  /// final List<AudioDeviceInfo> audioInputDevices = [];
  /// final List<AudioDeviceInfo> audioOutputDevices = [];
  ///
  /// Future<void> getAudioDeviceList() async {
  ///   try {
  ///     // On mobile platforms, this returns only audio output devices.
  ///     final List<AudioDeviceInfo>? audioDevices =
  ///         await VideoSDK.getAudioDevices();
  ///
  ///     if (audioDevices == null) return;
  ///
  ///     for (final AudioDeviceInfo device in audioDevices) {
  ///       // Mobile platforms (Android / iOS)
  ///       // Note: Switching audio devices affects both microphone and speaker.
  ///       if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
  ///         audioOutputDevices.add(device);
  ///       } else {
  ///         // Web and Desktop platforms
  ///         if (device.kind == 'audioinput') {
  ///           audioInputDevices.add(device);
  ///         } else {
  ///           audioOutputDevices.add(device);
  ///         }
  ///       }
  ///     }
  ///   } catch (e) {
  ///     print('Error while fetching audio devices');
  ///   }
  /// }
  /// ```
  ///
  static Future<List<AudioDeviceInfo>?> getAudioDevices() => _getAudioDevices();
  static Future<List<AudioDeviceInfo>?> _getAudioDevices() async {
    SpanScope getAudioDevicesSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Getting Audio Devices',
              component: ComponentCategory.media,
              category: EventCategory.telemetry,
            );
    MediaStream? mediaStream;
    try {
      bool _isFirefox = await isFirefox();
      if (_isFirefox) {
        try {
          mediaStream = await navigator.mediaDevices
              .getUserMedia({'audio': true, 'video': false});
        } catch (e) {
          if (e ==
              "Unable to getUserMedia: NotAllowedError: The request is not allowed by the user agent or the platform in the current context.") {
            log("Error in getAudioDevices(): The request is not allowed by the user agent or the platform in the current context.");
            SdkTracer.shared.endSpan(getAudioDevicesSpan,
                attributes: {"error": e.toString()},
                success: false,
                message:
                    "Error while getting audio devices: permission denied");
            return null;
          }
        }
      }

      if (!kIsWeb) {
        if (Platform.isIOS) {
          // setting AppleAudioConfiguration to get bluetooth device in the list
          setAppleAudioConfiguration();
        }
      }
      if (!_isFirefox && kIsWeb) {
        // The deviceId,label of the AudioDevice will be empty if the audio permission is not granted on the web.
        // checkPermission is not supported by Firefox
        final permissions = await checkPermissions(
            permissions: Permissions.audio, parentSpan: getAudioDevicesSpan);
        if (!permissions['audio']!) {
          log("You need microphone permission to access list of Audio Input devices.");
          SdkTracer.shared.endSpan(getAudioDevicesSpan,
              attributes: {"error": "Microphone permission not granted"},
              success: false,
              message:
                  "Error while getting audio devices: microphone permission not granted");
          return null;
        }
      }
      final List<MediaDeviceInfo> devices =
          await navigator.mediaDevices.enumerateDevices();
      final List<AudioDeviceInfo> audioDevices = [];

      for (MediaDeviceInfo device in devices) {
        if (kIsWeb || Platform.isMacOS || Platform.isWindows) {
          if (device.kind != 'videoinput') {
            audioDevices.add(AudioDeviceInfo(
              deviceId: device.deviceId,
              label: device.label,
              groupId: device.groupId,
              kind: device.kind,
            ));
          }
        } else {
          if (device.kind == 'audiooutput') {
            audioDevices.add(AudioDeviceInfo(
              deviceId: device.deviceId,
              label: device.label,
              groupId: device.groupId,
              kind: device.kind,
            ));
          }
        }
      }
      if (!kIsWeb) {
        if (Platform.isIOS) {
          if (audioDevices.length == 1) {
            AudioDeviceInfo mediaDeviceInfo = AudioDeviceInfo(
                label: "Receiver",
                deviceId: "Built-In Receiver",
                kind: "audiooutput");
            audioDevices.insert(0, mediaDeviceInfo);
          }
        }
      }

      if (mediaStream != null) {
        for (var track in mediaStream.getTracks()) {
          track.stop();
          mediaStream!.dispose();
          mediaStream = null;
        }
      }
      SdkTracer.shared.endSpan(
        getAudioDevicesSpan,
        attributes: {
          "audioDeviceCount": audioDevices.length.toString(),
          "audioDevices": jsonEncode(
            audioDevices
                .map((e) => {
                      "deviceId": e.deviceId,
                      "label": e.label,
                      "kind": e.kind,
                    })
                .toList(),
          ),
        },
        message: "Audio devices retrieved successfully",
      );
      return audioDevices;
    } catch (e) {
      SdkTracer.shared.endSpan(getAudioDevicesSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while getting audio devices");
      rethrow;
    }
  }

  /// @nodoc
  static void setAppleAudioConfiguration() async {
    SpanScope setAppleAudioConfigSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Setting Apple Audio Configuration',
              attributes: {
                "category": "playAndRecord",
                "categoryOptions": "allowBluetooth, allowBluetoothA2DP",
                "mode": "videoChat",
              },
              component: ComponentCategory.media,
            );
    try {
      await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
          appleAudioCategory: AppleAudioCategory.playAndRecord,
          appleAudioCategoryOptions: {
            AppleAudioCategoryOption.allowBluetooth,
            AppleAudioCategoryOption.allowBluetoothA2DP
          },
          appleAudioMode: AppleAudioMode.videoChat));
      SdkTracer.shared.endSpan(setAppleAudioConfigSpan,
          message: "Apple Audio Configuration set successfully");
    } catch (e) {
      SdkTracer.shared.endSpan(setAppleAudioConfigSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while setting Apple Audio Configuration");
    }
  }

  /// Retrieves all available media input and output devices.
  ///
  /// This method returns a list of [DeviceInfo] objects representing
  /// the currently available media devices on the system, such as
  /// cameras, microphones, speakers, and headsets.
  ///
  /// Each [DeviceInfo] object contains the following properties:
  ///
  /// - `deviceId`:
  ///   A unique identifier for the device, persisted across sessions.
  ///
  /// - `kind`:
  ///   Indicates the type of device. Possible values include:
  ///   `videoinput`, `audioinput`, and `audiooutput`.
  ///
  /// - `label`:
  ///   A human-readable description of the device
  ///   (for example, `BLUETOOTH` or a device name).
  ///
  /// - `groupId`:
  ///   Identifies the physical device group. Devices that belong to
  ///   the same physical hardware (for example, a monitor with both
  ///   a built-in camera and microphone) share the same `groupId`.
  ///
  /// > **Note (iOS-specific behavior):**
  /// > - `EARPIECE` is not available when a `WIRED_HEADSET` or `BLUETOOTH`
  /// >   device is connected.
  /// > - `WIRED_HEADSET` and `BLUETOOTH` devices cannot be used
  /// >   simultaneously. Priority is given to the most recently
  /// >   connected device.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a `List<DeviceInfo>?` containing
  ///   the available media devices.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// Future<void> getDeviceList() async {
  ///   try {
  ///     final List<DeviceInfo>? devices = await VideoSDK.getDevices();
  ///
  ///     if (devices != null) {
  ///       for (final device in devices) {
  ///         print('${device.kind}: ${device.label}');
  ///       }
  ///     }
  ///   } catch (e) {
  ///     print('Error while fetching media devices');
  ///   }
  /// }
  /// ```
  static Future<List<DeviceInfo>?> getDevices() => _getDevices();
  static Future<List<DeviceInfo>?> _getDevices() async {
    final span = SdkTracer.shared.startSpan(
      spanName: "Get Media Devices",
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
    );

    try {
      final bool isFirefoxBrowser = await isFirefox();

      SdkTracer.shared.traceEvent(
        spanName: "Browser Detection",
        parentScope: span,
        attributes: {
          "isFirefox": isFirefoxBrowser.toString(),
          "isWeb": kIsWeb.toString(),
        },
        component: ComponentCategory.media,
      );

      final List<DeviceInfo> mediaDevices = [];

      if (!isFirefoxBrowser && kIsWeb) {
        final permissions = await checkPermissions(parentSpan: span);

        SdkTracer.shared.traceEvent(
          spanName: "Permissions Checked",
          parentScope: span,
          attributes: {
            "audioPermission": permissions['audio'].toString(),
            "videoPermission": permissions['video'].toString(),
          },
          component: ComponentCategory.media,
        );

        if (permissions['audio']! && !permissions['video']!) {
          SdkTracer.shared.traceEvent(
            spanName: "Camera Permission Missing",
            parentScope: span,
            component: ComponentCategory.media,
          );

          final audioDevices = await _getAudioDevicesList();

          SdkTracer.shared.endSpan(
            span,
            attributes: {
              "audioDeviceCount": audioDevices.length.toString(),
              "videoDeviceCount": "0",
            },
            message: "Retrieved audio devices only",
          );

          return audioDevices;
        } else if (!permissions['audio']! && permissions['video']!) {
          SdkTracer.shared.traceEvent(
            spanName: "Microphone Permission Missing",
            parentScope: span,
            component: ComponentCategory.media,
          );

          final videoDevices = await _getVideoDevicesList();

          SdkTracer.shared.endSpan(
            span,
            attributes: {
              "videoDeviceCount": jsonEncode(
                videoDevices
                    .map((e) => {
                          "deviceId": e.deviceId,
                          "label": e.label,
                          "kind": e.kind,
                        })
                    .toList(),
              ),
            },
            message: "Retrieved video devices only",
          );

          return videoDevices;
        } else if (!permissions['audio']! && !permissions['video']!) {
          SdkTracer.shared.endSpan(
            span,
            attributes: {
              "audioDeviceCount": "0",
              "videoDeviceCount": "0",
            },
            success: false,
            message: "No permissions granted",
          );

          return null;
        }
      }

      // Get audio devices
      final audioDevices = await _getAudioDevicesList();

      SdkTracer.shared.traceEvent(
        spanName: "Audio Devices Retrieved",
        parentScope: span,
        attributes: {
          "count": audioDevices.length.toString(),
        },
        component: ComponentCategory.media,
      );

      // Get video devices
      final videoDevices = await _getVideoDevicesList();

      SdkTracer.shared.traceEvent(
        spanName: "Video Devices Retrieved",
        parentScope: span,
        attributes: {
          "count": videoDevices.length.toString(),
        },
        component: ComponentCategory.media,
      );

      mediaDevices.addAll(audioDevices);
      mediaDevices.addAll(videoDevices);

      SdkTracer.shared.endSpan(
        span,
        attributes: {
          "audioDeviceCount": audioDevices.length.toString(),
          "videoDeviceCount": videoDevices.length.toString(),
          "totalDeviceCount": mediaDevices.length.toString(),
        },
        message: "Media devices retrieved successfully",
      );

      return mediaDevices;
    } catch (error) {
      SdkTracer.shared.endSpan(
        span,
        success: false,
        message: "Failed to retrieve media devices",
        attributes: {
          "error": error.toString(),
        },
      );

      rethrow;
    }
  }

  static Future<List<DeviceInfo>> _getAudioDevicesList() async {
    final List<DeviceInfo> audioDevices = [];
    final audioDeviceList = await getAudioDevices();
    if (audioDeviceList != null) {
      for (var audioDevice in audioDeviceList) {
        audioDevices.add(DeviceInfo(
          deviceId: audioDevice.deviceId,
          label: audioDevice.label,
          groupId: audioDevice.groupId,
          kind: audioDevice.kind,
        ));
      }
    }
    return audioDevices;
  }

  static Future<List<DeviceInfo>> _getVideoDevicesList() async {
    final List<DeviceInfo> videoDevices = [];
    final videoDeviceList = await getVideoDevices();
    if (videoDeviceList != null) {
      for (var videoDevice in videoDeviceList) {
        videoDevices.add(DeviceInfo(
          deviceId: videoDevice.deviceId,
          label: videoDevice.label,
          groupId: videoDevice.groupId,
          kind: videoDevice.kind,
        ));
      }
    }
    return videoDevices;
  }

  /// @nodoc
  static Future<bool> isFirefox() async {
    final deviceInfo = await VideoSDK.getDeviceInfo();
    return deviceInfo['browserUserAgent']?['browser']?['name'] == "Firefox";
  }

  /// Checks the permission status for camera and microphone access.
  ///
  /// This method verifies whether the application has permission to access
  /// audio (microphone) and/or video (camera) devices. The result is returned
  /// as a map where:
  /// - `'audio'` represents microphone permission
  /// - `'video'` represents camera permission
  ///
  /// ### iOS Configuration
  ///
  /// To enable permission checks on iOS, add the following configuration
  /// to your `Podfile`:
  ///
  /// ```ruby
  /// post_install do |installer|
  ///   installer.pods_project.targets.each do |target|
  ///     flutter_additional_ios_build_settings(target)
  ///     target.build_configurations.each do |config|
  ///       config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
  ///         'PERMISSION_CAMERA=1',
  ///         'PERMISSION_MICROPHONE=1',
  ///       ]
  ///     end
  ///   end
  /// end
  /// ```
  ///
  /// ### **Parameters**
  ///
  /// - [permissions] *(optional)*:
  ///   Specifies which media permissions should be checked.
  ///
  ///   Allowed values:
  ///   - [Permissions.audio]
  ///   - [Permissions.video]
  ///   - [Permissions.audio_video]
  ///
  ///   Defaults to [Permissions.audio_video].
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a `Map<String, bool>` indicating
  ///   the permission status for each requested media type.
  ///
  /// > **Info:**
  /// > The `checkPermissions()` method is not supported on desktop
  /// > platforms or Firefox browser.
  ///
  /// > **Tip:**
  /// > This method throws an [UnsupportedError] when the platform
  /// > does not support permission checks.
  ///
  /// ### **Example**
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// Future<void> checkMediaPermissions() async {
  ///   try {
  ///     // Check both audio and video permissions (default)
  ///     final permissions = await VideoSDK.checkPermissions();
  ///
  ///     // Check only audio permission
  ///     final audioPermission =
  ///         await VideoSDK.checkPermissions(Permissions.audio);
  ///
  ///     // Check only video permission
  ///     final videoPermission =
  ///         await VideoSDK.checkPermissions(Permissions.video);
  ///
  ///     // Check both audio and video permissions explicitly
  ///     final audioVideoPermission =
  ///         await VideoSDK.checkPermissions(Permissions.audio_video);
  ///
  ///     print(
  ///       'Audio: ${audioVideoPermission['audio']}, '
  ///       'Video: ${audioVideoPermission['video']}',
  ///     );
  ///   } catch (e) {
  ///     print('Error while checking media permissions');
  ///   }
  /// }
  /// ```
  static Future<Map<String, bool>> checkPermissions(
          {Permissions? permissions, SpanScope? parentSpan}) =>
      _checkPermissions(permissions: permissions, parentSpan: parentSpan);
  static Future<Map<String, bool>> _checkPermissions(
      {Permissions? permissions, SpanScope? parentSpan}) async {
    permissions ??= Permissions.audio_video;
    SpanScope checkPermissionsSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Checking Permissions',
              attributes: {
                "permissions": permissions.name,
              },
              component: ComponentCategory.media,
              parentSpan: parentSpan,
              category: parentSpan != null
                  ? EventCategory.debug
                  : EventCategory.telemetry,
            );
    try {
      Map<String, bool> permissionMap = {};
      final _isFirefox = await isFirefox();
      if (_isFirefox) {
        SdkTracer.shared.endSpan(checkPermissionsSpan,
            attributes: {
              "error": "Checking permission is not supported on Firefox"
            },
            success: false,
            message:
                "Error while checking permissions: not supported on Firefox");
        throw UnsupportedError('Checking permission is not supported.');
      }
      if (!kIsWeb) {
        if (Platform.isMacOS || Platform.isWindows) {
          SdkTracer.shared.endSpan(checkPermissionsSpan,
              attributes: {
                "error": "Checking permission is not supported on this platform"
              },
              success: false,
              message:
                  "Error while checking permissions: not supported on desktop");
          throw UnsupportedError('Checking permission is not supported.');
        }
      }

      if (permissions == Permissions.audio ||
          permissions == Permissions.audio_video) {
        bool allowed = false;
        try {
          var status = await Permission.microphone.status;
          if (status.isGranted) {
            allowed = true;
          }
        } catch (error) {
          allowed = false;
        }
        permissionMap["audio"] = allowed;
      }
      if (permissions == Permissions.video ||
          permissions == Permissions.audio_video) {
        bool allowed = false;
        try {
          var status = await Permission.camera.status;
          if (status.isGranted) {
            allowed = true;
          }
        } catch (error) {
          allowed = false;
        }
        permissionMap["video"] = allowed;
      }
      SdkTracer.shared.endSpan(checkPermissionsSpan,
          attributes: {
            if (permissionMap.containsKey("audio"))
              "audio": permissionMap["audio"].toString(),
            if (permissionMap.containsKey("video"))
              "video": permissionMap["video"].toString(),
          },
          message: "Permissions checked successfully");
      return permissionMap;
    } catch (e) {
      if (e is! UnsupportedError) {
        SdkTracer.shared.endSpan(checkPermissionsSpan,
            attributes: {"error": e.toString()},
            success: false,
            message: "Error while checking permissions");
      }
      rethrow;
    }
  }

  /// Prompts the user for permission to access camera and microphone devices.
  ///
  /// Returns a `Map<String, bool>` where:
  /// - `'audio'` indicates microphone permission status.
  /// - `'video'` indicates camera permission status.
  ///
  /// ### iOS Configuration
  ///
  /// To enable requesting microphone and camera permissions on iOS devices,
  /// add the following to your **Podfile**:
  ///
  /// ```ruby
  /// post_install do |installer|
  ///   installer.pods_project.targets.each do |target|
  ///     flutter_additional_ios_build_settings(target)
  ///     target.build_configurations.each do |config|
  ///       config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
  ///         'PERMISSION_CAMERA=1',
  ///         'PERMISSION_MICROPHONE=1',
  ///       ]
  ///     end
  ///   end
  /// end
  /// ```
  ///
  /// ### Parameters
  ///
  /// - `permissions` ([Permissions], optional)
  ///   Specifies which media permissions to request.
  ///
  ///   Allowed values:
  ///   - `Permissions.audio`
  ///   - `Permissions.video`
  ///   - `Permissions.audio_video`
  ///
  ///   Default: `Permissions.audio_video`
  ///
  /// ### Returns
  ///
  /// A `Future<Map<String, bool>>` containing the permission results.
  ///
  /// ### Notes
  ///
  /// - This method is **not supported** on:
  ///   - Desktop platforms
  ///   - Firefox browser
  ///
  /// ### Example
  ///
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// void requestMediaPermissions() async {
  ///   try {
  ///     // By default both audio and video permissions will be requested.
  ///     Map<String, bool> reqPermissions =
  ///         await VideoSDK.requestPermissions();
  ///
  ///     // Request only audio permission.
  ///     Map<String, bool> reqAudioPermissions =
  ///         await VideoSDK.requestPermissions(Permissions.audio);
  ///
  ///     // Request only video permission.
  ///     Map<String, bool> reqVideoPermissions =
  ///         await VideoSDK.requestPermissions(Permissions.video);
  ///
  ///     // Request both audio and video permissions.
  ///     Map<String, bool> reqAudioVideoPermissions =
  ///         await VideoSDK.requestPermissions(Permissions.audio_video);
  ///
  ///     print(
  ///       "Request Permissions ${reqAudioVideoPermissions['audio']} "
  ///       "${reqAudioVideoPermissions['video']}",
  ///     );
  ///   } catch (ex) {
  ///     print("Error in requestPermission");
  ///   }
  /// }
  /// ```
  ///
  /// ### Throws
  ///
  /// Throws an [UnsupportedError] when the platform does not support
  /// permission request functionality.
  static Future<Map<String, bool>> requestPermissions(
          [Permissions? permissions]) =>
      _requestPermissions(permissions);
  static Future<Map<String, bool>> _requestPermissions(
      [Permissions? permissions]) async {
    permissions ??= Permissions.audio_video;
    SpanScope requestPermissionsSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Requesting Permissions',
              attributes: {
                "permissions": permissions.name,
              },
              component: ComponentCategory.media,
              category: EventCategory.telemetry,
            );
    try {
      Map<String, bool> permissionMap = {};
      bool _isFirefox = await isFirefox();
      if (_isFirefox) {
        SdkTracer.shared.endSpan(requestPermissionsSpan,
            attributes: {
              "error": "Requesting permission is not supported on Firefox"
            },
            success: false,
            message:
                "Error while requesting permissions: not supported on Firefox");
        throw UnsupportedError('Requesting permission is not supported');
      }
      if (!kIsWeb) {
        if (Platform.isMacOS || Platform.isWindows) {
          SdkTracer.shared.endSpan(requestPermissionsSpan,
              attributes: {
                "error":
                    "Requesting permission is not supported on this platform"
              },
              success: false,
              message:
                  "Error while requesting permissions: not supported on desktop");
          throw UnsupportedError('Requesting permission is not supported');
        }
      }
      if (permissions == Permissions.audio ||
          permissions == Permissions.audio_video) {
        bool allowed = false;
        try {
          var status = await Permission.microphone.request();
          if (status.isGranted) {
            allowed = true;
          }
        } catch (error) {
          allowed = false;
        }
        permissionMap["audio"] = allowed;
      }
      if (permissions == Permissions.video ||
          permissions == Permissions.audio_video) {
        bool allowed = false;
        try {
          var status = await Permission.camera.request();
          if (status.isGranted) {
            allowed = true;
          }
        } catch (error) {
          allowed = false;
        }
        permissionMap["video"] = allowed;
      }

      SdkTracer.shared.endSpan(requestPermissionsSpan,
          attributes: {
            if (permissionMap.containsKey("audio"))
              "audio": permissionMap["audio"].toString(),
            if (permissionMap.containsKey("video"))
              "video": permissionMap["video"].toString(),
          },
          message: "Permissions requested successfully");
      return permissionMap;
    } catch (e) {
      if (e is! UnsupportedError) {
        SdkTracer.shared.endSpan(requestPermissionsSpan,
            attributes: {"error": e.toString()},
            success: false,
            message: "Error while requesting permissions");
      }
      rethrow;
    }
  }

  /// Checks whether the application has Bluetooth permission.
  ///
  /// This method verifies if the application is allowed to access
  /// Bluetooth functionality on the device.
  ///
  /// > **Info:**
  /// > The `checkBluetoothPermission()` method is supported only on
  /// > Android devices running Android 12 or later.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to `true` if Bluetooth permission
  ///   is granted, or `false` otherwise.
  ///
  /// > **Tip:**
  /// > This method throws an [UnsupportedError] when called on
  /// > platforms that do not support Bluetooth permission checks.
  ///
  /// ### **Example**
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// Future<void> checkBluetooth() async {
  ///   try {
  ///     final bool bluetoothPerm =
  ///         await VideoSDK.checkBluetoothPermission();
  ///
  ///     print('Bluetooth permission granted: $bluetoothPerm');
  ///   } catch (e) {
  ///     print('Bluetooth permission check not supported');
  ///   }
  /// }
  /// ```
  static Future<bool> checkBluetoothPermission() => _checkBluetoothPermission();
  static Future<bool> _checkBluetoothPermission() async {
    SpanScope checkBluetoothPermissionSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Checking Bluetooth Permission',
              component: ComponentCategory.media,
              category: EventCategory.telemetry,
            );
    try {
      bool permAvailable = false;

      if (!kIsWeb) {
        // Providing the checkBluetoothPermission() method for Android version 12 and higher.
        if (Platform.isAndroid) {
          final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
          final AndroidDeviceInfo info = await deviceInfoPlugin.androidInfo;
          if (int.parse(info.version.release) > 11) {
            permAvailable = true;
          }
        }
      }
      if (permAvailable == false) {
        SdkTracer.shared.endSpan(checkBluetoothPermissionSpan,
            attributes: {
              "error":
                  "Checking Bluetooth permission is not applicable on this platform"
            },
            success: false,
            message:
                "Error while checking Bluetooth permission: not supported");
        throw UnsupportedError(
            'Checking Bluetooth permission is not applicable');
      }

      bool allowed = false;

      try {
        var status = await Permission.bluetoothConnect.status;
        if (status.isGranted) {
          allowed = true;
        }
      } catch (error) {
        allowed = false;
      }

      SdkTracer.shared.endSpan(checkBluetoothPermissionSpan,
          attributes: {"bluetoothPermission": allowed.toString()},
          message: "Bluetooth permission checked successfully");
      return allowed;
    } catch (e) {
      if (e is! UnsupportedError) {
        SdkTracer.shared.endSpan(checkBluetoothPermissionSpan,
            attributes: {"error": e.toString()},
            success: false,
            message: "Error while checking Bluetooth permission");
      }
      rethrow;
    }
  }

  /// Requests Bluetooth permission from the device.
  ///
  /// This method prompts the user to grant permission for Bluetooth access
  /// and returns whether the permission request was successful.
  ///
  /// > **Info:**
  /// > The `requestBluetoothPermission()` method is supported only on
  /// > Android devices running Android 12 or later.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to `true` if Bluetooth permission is granted,
  ///   or `false` otherwise.
  ///
  /// > **Tip:**
  /// > This method throws an [UnsupportedError] when called on platforms
  /// > that do not support Bluetooth permission requests.
  ///
  /// ### **Example**
  /// ```dart
  /// import 'package:videosdk/videosdk.dart';
  ///
  /// Future<void> requestBluetooth() async {
  ///   try {
  ///     final bool bluetoothPerm =
  ///         await VideoSDK.requestBluetoothPermission();
  ///
  ///     print('Bluetooth permission granted: $bluetoothPerm');
  ///   } catch (e) {
  ///     print('Bluetooth permission request not supported');
  ///   }
  /// }
  /// ```
  static Future<bool> requestBluetoothPermission() =>
      _requestBluetoothPermission();
  static Future<bool> _requestBluetoothPermission() async {
    SpanScope requestBluetoothPermissionSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Requesting Bluetooth Permission',
              component: ComponentCategory.media,
              category: EventCategory.telemetry,
            );
    try {
      bool permAvailable = false;

      if (!kIsWeb) {
        // checking android version
        // Providing the requestBluetoothPermission() method for Android version 12 and higher.
        if (Platform.isAndroid) {
          final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
          final AndroidDeviceInfo info = await deviceInfoPlugin.androidInfo;
          if (int.parse(info.version.release) > 11) {
            permAvailable = true;
          }
        }
      }
      if (permAvailable == false) {
        SdkTracer.shared.endSpan(requestBluetoothPermissionSpan,
            attributes: {
              "error":
                  "Requesting Bluetooth permission is not applicable on this platform"
            },
            success: false,
            message:
                "Error while requesting Bluetooth permission: not supported");
        throw UnsupportedError(
            'Requesting Bluetooth permission is not applicable');
      }

      bool allowed = false;

      try {
        var status = await Permission.bluetoothConnect.request();

        if (status.isGranted) {
          allowed = true;
        }
      } catch (error) {
        allowed = false;
      }

      SdkTracer.shared.endSpan(requestBluetoothPermissionSpan,
          attributes: {"bluetoothPermission": allowed.toString()},
          message: "Bluetooth permission requested successfully");
      return allowed;
    } catch (e) {
      if (e is! UnsupportedError) {
        SdkTracer.shared.endSpan(requestBluetoothPermissionSpan,
            attributes: {"error": e.toString()},
            success: false,
            message: "Error while requesting Bluetooth permission");
      }
      rethrow;
    }
  }

  /// Creates a microphone-based audio track with customizable
  /// encoding and noise-cancellation settings.
  ///
  /// This method allows you to create a custom audio track using a
  /// microphone device, with support for different audio quality
  /// profiles and optional noise control configurations.
  ///
  /// ### **Parameters**
  ///
  /// - [microphoneId] *(optional)*:
  ///   The device ID of the microphone from which audio should be captured.
  ///   If not provided, the default microphone will be used.
  ///
  /// - [encoderConfig] *(optional)*:
  ///   The audio encoder configuration to be used for the audio track.
  ///   Defaults to [CustomAudioTrackConfig.speech_standard].
  ///
  ///   Allowed values:
  ///   - [CustomAudioTrackConfig.speech_low_quality]
  ///   - [CustomAudioTrackConfig.speech_standard]
  ///   - [CustomAudioTrackConfig.music_standard]
  ///   - [CustomAudioTrackConfig.standard_stereo]
  ///   - [CustomAudioTrackConfig.high_quality]
  ///   - [CustomAudioTrackConfig.high_quality_stereo]
  ///
  /// - [noiseConfig] *(optional)*:
  ///   Configuration options for controlling audio noise processing.
  ///
  ///   Supported properties:
  ///   - `echoCancellation`:
  ///     Enables or disables echo cancellation.
  ///   - `autoGainControl`:
  ///     Enables or disables automatic gain control.
  ///   - `noiseSuppression`:
  ///     Enables or disables noise suppression.
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a [CustomTrack] representing the
  ///   created audio track, or `null` if audio track creation fails.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// final CustomTrack? audioTrack =
  ///     await VideoSDK.createMicrophoneAudioTrack(
  ///       encoderConfig: CustomAudioTrackConfig.high_quality,
  ///     );
  ///
  /// if (audioTrack != null) {
  ///   print('Audio track created successfully');
  /// }
  /// ```
  static createMicrophoneAudioTrack(
          {String? microphoneId,
          CustomAudioTrackConfig encoderConfig =
              CustomAudioTrackConfig.speech_standard,
          Map<String, bool> noiseConfig = const {}}) =>
      _createMicrophoneAudioTrack(
          microphoneId: microphoneId,
          encoderConfig: encoderConfig,
          noiseConfig: noiseConfig);
  static _createMicrophoneAudioTrack(
      {String? microphoneId,
      CustomAudioTrackConfig encoderConfig =
          CustomAudioTrackConfig.speech_standard,
      Map<String, bool> noiseConfig = const {}}) async {
    Map<String, dynamic>? config = customAudioTrackConfigMap[encoderConfig];
    late Map<String, dynamic> mediaConstraints;
    String? selectedMicrophoneId;

    SpanScope createMicrophoneAudioTrackSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Creating Custom Audio Track',
              attributes: {
                'encoderConfig': encoderConfig.name,
                'microphoneId': microphoneId,
                "noiseConfig": noiseConfig.toString(),
              },
              component: ComponentCategory.media,
            );
    bool _isFirefox = await isFirefox();

    if (!_isFirefox && kIsWeb) {
      // ignore: unused_local_variable
      Map<String, bool>? audioPermissions =
          await VideoSDK.requestPermissions(Permissions.audio);
    } else {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        Map<String, bool>? audioPermissions =
            await VideoSDK.requestPermissions(Permissions.audio);
        if (audioPermissions['audio'] == false) {
          //Throwing error for Android and iOS directly
          SdkTracer.shared.endSpan(createMicrophoneAudioTrackSpan,
              attributes: {
                "error":
                    "Error while creating Audio Track: Browser/Device Permissions denied."
              },
              success: false,
              message: "Error while creating custom audio track");
          _eventEmitter.emit("error", VideoSDKErrors[3008]);

          log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3008]?['code']}  :: ${VideoSDKErrors[3008]?['name']} :: ${VideoSDKErrors[3008]?['message']}");
          return null;
        }
      }
    }

    try {
      if (microphoneId != null) {
        List<AudioDeviceInfo>? audioDevices = await VideoSDK.getAudioDevices();
        if (audioDevices != null) {
          bool isMicrophone = kIsWeb || Platform.isMacOS || Platform.isWindows
              ? audioDevices.any((mic) =>
                  mic.deviceId == microphoneId && mic.kind == "audioinput")
              : audioDevices.any((mic) => mic.deviceId == microphoneId);
          if (isMicrophone) {
            selectedMicrophoneId =
                kIsWeb || Platform.isMacOS || Platform.isWindows
                    ? audioDevices
                        .firstWhere((mic) =>
                            mic.deviceId == microphoneId &&
                            mic.kind == "audioinput")
                        .deviceId
                    : audioDevices
                        .firstWhere((mic) => mic.deviceId == microphoneId)
                        .deviceId;
          } else {
            selectedMicrophoneId = audioDevices.first.deviceId;
            log("No microphone device found for the specified microphoneId. Please verify the provided microphoneId. The default microphone will be used instead.");
          }
        } else {
          //For web if permission not available.
          selectedMicrophoneId = microphoneId;
        }
      }

      if (!kIsWeb) {
        mediaConstraints = <String, dynamic>{
          "audio": {
            "mandatory": {
              "googEchoCancellation": noiseConfig["echoCancellation"] ??
                  config?["echoCancellation"] as bool,
              "googNoiseSuppression": noiseConfig["noiseSuppression"] ??
                  config?["noiseSuppression"] as bool,
              "echoCancellation": noiseConfig["echoCancellation"] ??
                  config?["echoCancellation"] as bool,
              "googEchoCancellation2": noiseConfig["echoCancellation"] ??
                  config?["echoCancellation"] as bool,
              "googDAEchoCancellation": noiseConfig["echoCancellation"] ??
                  config?["echoCancellation"] as bool,
              "googAutoGainControl": noiseConfig["autoGainControl"] ??
                  config?["autoGainControl"] as bool,
            },
            'optional': selectedMicrophoneId != null
                ? [
                    {
                      'sourceId': selectedMicrophoneId,
                    }
                  ]
                : [],
          },
          "video": false
        };
      } else {
        mediaConstraints = <String, dynamic>{
          "audio": {
            "googEchoCancellation": noiseConfig["echoCancellation"] ??
                config?["echoCancellation"] as bool,
            "googNoiseSuppression": noiseConfig["noiseSuppression"] ??
                config?["noiseSuppression"] as bool,
            "echoCancellation": noiseConfig["echoCancellation"] ??
                config?["echoCancellation"] as bool,
            "googEchoCancellation2": noiseConfig["echoCancellation"] ??
                config?["echoCancellation"] as bool,
            "googDAEchoCancellation": noiseConfig["echoCancellation"] ??
                config?["echoCancellation"] as bool,
            "googAutoGainControl": noiseConfig["autoGainControl"] ??
                config?["autoGainControl"] as bool,
            "deviceId": selectedMicrophoneId != null
                ? {"exact": selectedMicrophoneId}
                : null,
          },
          "video": false
        };
      }

      MediaStream mediaStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);

      CustomTrack customAudioTrack = CustomTrack.audioTrack(
          mediaStream: mediaStream,
          audioEncoderConfig: encoderConfig,
          noiseConfig: noiseConfig,
          microphoneId: selectedMicrophoneId);

      SdkTracer.shared.endSpan(createMicrophoneAudioTrackSpan,
          attributes: {"config": customAudioTrack.toMap().toString()},
          message: "Custom Audio Track created successfully");

      return customAudioTrack;
    } catch (e) {
      SdkTracer.shared.endSpan(createMicrophoneAudioTrackSpan,
          attributes: {"error": "Device could not create audio track!"},
          success: false,
          message: "Error while creating custom audio track");

      if (e == "Unable to getUserMedia: NotAllowedError: Permission denied" ||
          e ==
              "Unable to getUserMedia: NotAllowedError: The request is not allowed by the user agent or the platform in the current context." ||
          e ==
              "Unable to getUserMedia: getUserMedia(): DOMException, NotAllowedError" ||
          e == "Unable to getUserMedia: NotAllowedError") {
        _eventEmitter.emit("error", VideoSDKErrors[3008]);

        log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3008]?['code']}  :: ${VideoSDKErrors[3008]?['name']} :: ${VideoSDKErrors[3008]?['message']}");
      } else if (e ==
              "Unable to getUserMedia: NotAllowedError: Permission denied by system" ||
          e ==
              "Unable to getUserMedia: NotFoundError: The object can not be found here.") {
        _eventEmitter.emit("error", VideoSDKErrors[3010]);

        log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3010]?['code']}  :: ${VideoSDKErrors[3010]?['name']} :: ${VideoSDKErrors[3010]?['message']}");
      } else if (e ==
              "Unable to getUserMedia: NotReadableError: Device in use" ||
          e.toString().contains("Unable to getUserMedia: AbortError")) {
        _eventEmitter.emit("error", VideoSDKErrors[3004]);

        log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3004]?['code']}  :: ${VideoSDKErrors[3004]?['name']} :: ${VideoSDKErrors[3004]?['message']}");
      } else if (e.toString().contains(
          "TypeError: null: type 'Null' is not a subtype of type 'JSObject'")) {
        _eventEmitter.emit("error", VideoSDKErrors[3006]);

        log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3006]?['code']}  :: ${VideoSDKErrors[3006]?['name']} :: ${VideoSDKErrors[3006]?['message']}");
      } else {
        _eventEmitter.emit("error", VideoSDKErrors[3018]);

        log("An error occurred while creating Audio Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3018]?['code']}  :: ${VideoSDKErrors[3018]?['name']} :: ${VideoSDKErrors[3018]?['message']}");
      }
      return null;
    }
  }

  /// Creates a camera-based video track with customizable capture
  /// and encoding configurations.
  ///
  /// This method allows you to create a custom video track using a camera
  /// device with configurable resolution, frame rate, camera facing mode,
  /// and multi-stream support.
  ///
  /// ### **Parameters**
  ///
  /// - [cameraId] *(optional)*:
  ///   The device ID of the camera from which the video should be captured.
  ///   If not provided, the default camera will be used.
  ///
  /// - [encoderConfig] *(optional)*:
  ///   The video encoder configuration to be used for the video track.
  ///   Defaults to [CustomVideoTrackConfig.h720p_w1280p].
  ///
  ///   > **Note:**
  ///   > These encoder configurations are valid for both landscape
  ///   > and portrait orientations.
  ///
  /// - [facingMode] *(optional)*:
  ///   Specifies which camera to use for video capture.
  ///   Defaults to [FacingMode.user].
  ///
  ///   Allowed values:
  ///   - [FacingMode.user]
  ///   - [FacingMode.environment]
  ///
  /// - [multiStream] *(optional)*:
  ///   Determines whether multiple resolution layers should be sent
  ///   for the video stream.
  ///   Defaults to `true`.
  ///
  ///   > **Info:**
  ///   > - For meetings with **four or fewer participants**, setting
  ///   >   `multiStream: false` is recommended for better performance.
  ///   > - Available from SDK version `v1.0.9`.
  ///
  /// - [bitrateMode] *(optional)*:
  ///   Controls how the bitrate is managed for the video stream.
  ///   Defaults to [BitrateMode.BALANCED].
  ///
  /// - [maxLayer] *(optional)*:
  ///   Specifies the maximum number of simulcast layers to publish.
  ///   Valid values are between `1` and `3`.
  ///   Defaults to `3`.
  ///
  /// - [codec] *(optional)*:
  ///   The video codec used to encode the video stream.
  ///   Defaults to [VideoCodec.VP8].
  ///
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a [CustomTrack] representing the
  ///   created video track, or `null` if video track creation fails.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// final CustomTrack? videoTrack =
  ///     await VideoSDK.createCameraVideoTrack(
  ///       encoderConfig: CustomVideoTrackConfig.h1440p_w1920p,
  ///       facingMode: FacingMode.user,
  ///       multiStream: false,
  ///       bitrateMode: BitrateMode.BALANCED,
  ///       maxLayer: 2,
  ///       codec: VideoCodec.VP8,
  ///     );
  ///
  /// if (videoTrack != null) {
  ///   print('Video track created successfully');
  /// }
  /// ```
  static createCameraVideoTrack({
    String? cameraId,
    CustomVideoTrackConfig encoderConfig = CustomVideoTrackConfig.h720p_w1280p,
    FacingMode facingMode = FacingMode.user,
    bool multiStream = true,
    BitrateMode bitrateMode = BitrateMode.BALANCED,
    int maxLayer = 3,
    VideoCodec codec = VideoCodec.VP8,
  }) =>
      _createCameraVideoTrack(
          cameraId: cameraId,
          encoderConfig: encoderConfig,
          facingMode: facingMode,
          multiStream: multiStream,
          bitrateMode: bitrateMode,
          maxLayer: maxLayer,
          codec: codec);

  static _createCameraVideoTrack({
    String? cameraId,
    CustomVideoTrackConfig encoderConfig = CustomVideoTrackConfig.h720p_w1280p,
    FacingMode facingMode = FacingMode.user,
    // String optimizationMode = "motion",
    bool multiStream = true,
    BitrateMode bitrateMode = BitrateMode.BALANCED,
    int maxLayer = 3,
    VideoCodec codec = VideoCodec.VP8,
  }) async {
    late Map<String, dynamic> mediaConstraints;
    String? selectedCameraId;

    SpanScope createCameraVideoTrackSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Creating Custom Video Track',
              attributes: {
                "config": jsonEncode({
                  "height": customVideotrackConfigMap[encoderConfig]?["height"],
                  "width": customVideotrackConfigMap[encoderConfig]?["width"],
                  "frameRate": customVideotrackConfigMap[encoderConfig]
                      ?["frameRate"]
                }),
                "facingMode": facingMode.name,
                "multiStream": multiStream.toString(),
                "bitrateMode": bitrateMode.name,
                "maxLayer": maxLayer.toString(),
                "cameraId": cameraId
              },
              component: ComponentCategory.media,
            );

    bool _isFirefox = await isFirefox();

    if (!_isFirefox && kIsWeb) {
      // ignore: unused_local_variable
      Map<String, bool>? videoPermissions =
          await VideoSDK.requestPermissions(Permissions.video);
    } else {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        Map<String, bool>? videoPermissions =
            await VideoSDK.requestPermissions(Permissions.video);
        if (videoPermissions['video'] == false) {
          //Throwing error for Android and iOS directly
          SdkTracer.shared.endSpan(createCameraVideoTrackSpan,
              attributes: {
                "error":
                    "Error while creating Video Track: Browser/Device Permissions denied."
              },
              success: false,
              message: "Error while creating custom video track");
          _eventEmitter.emit("error", VideoSDKErrors[3007]);

          log("An error occurred while creating Video Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3007]?['code']}  :: ${VideoSDKErrors[3007]?['name']} :: ${VideoSDKErrors[3007]?['message']}");
          return null;
        }
      }
    }
    try {
      if (cameraId != null) {
        List<VideoDeviceInfo>? videoDevices = await VideoSDK.getVideoDevices();
        if (videoDevices != null) {
          bool isCamera =
              videoDevices.any((camera) => camera.deviceId == cameraId);
          if (isCamera) {
            for (var videoDevice in videoDevices) {
              if (videoDevice.deviceId == cameraId) {
                selectedCameraId = videoDevice.deviceId;
              }
            }
          } else {
            selectedCameraId = videoDevices.first.deviceId;
            log("No camera device found for the specified cameraId. Please verify the provided cameraId. The default camera will be used instead.");
          }
        } else {
          //For web if permission not available.
          selectedCameraId = cameraId;
        }
      }

      if (!kIsWeb) {
        var optional = selectedCameraId != null
            ? [
                {
                  // 'sourceId': cameraId,
                  'sourceId': selectedCameraId,
                }
              ]
            : [];

        if (selectedCameraId != null && Platform.isAndroid) {
          final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
          final AndroidDeviceInfo info = await deviceInfoPlugin.androidInfo;
          var osVersion = info.version.sdkInt;
          if (mediaDevices.isEmpty) {
            await loadMediaDevices();
          }
          MediaDeviceInfo? device = mediaDevices[MediaDeviceType.videoInput]!
              .firstWhereOrNull(
                  (element) => element.deviceId == selectedCameraId);
          if (device != null && Platform.isAndroid && osVersion <= 28) {
            if (info.supportedAbis.first != "arm64-v8a" &&
                info.supportedAbis.first != "x86_64") {
              optional = [
                {
                  'sourceId': device.label,
                }
              ];
            }
          }
        }

        if (Platform.isAndroid || Platform.isIOS) {
          mediaConstraints = <String, dynamic>{
            'audio': false,
            'video': {
              'facingMode': facingMode.name,
              'width': customVideotrackConfigMap[encoderConfig]!["width"],
              'height': customVideotrackConfigMap[encoderConfig]!["height"],
              'frameRate':
                  customVideotrackConfigMap[encoderConfig]!["frameRate"],
              'optional': optional,
            },
          };
        } //In Desktop based applications, facingMode is not working and creates issues if passed as null
        else {
          mediaConstraints = <String, dynamic>{
            'audio': false,
            'video': {
              'width': customVideotrackConfigMap[encoderConfig]!["width"],
              'height': customVideotrackConfigMap[encoderConfig]!["height"],
              'frameRate':
                  customVideotrackConfigMap[encoderConfig]!["frameRate"],
              'optional': optional,
            },
          };
        }
      } else {
        mediaConstraints = <String, dynamic>{
          'audio': false,
          'video': {
            'facingMode': selectedCameraId != null ? null : facingMode,
            'width': customVideotrackConfigMap[encoderConfig]!["width"],
            'height': customVideotrackConfigMap[encoderConfig]!["height"],
            'frameRate': customVideotrackConfigMap[encoderConfig]!["frameRate"],
            'deviceId':
                selectedCameraId != null ? {"exact": selectedCameraId} : null,
          },
        };
      }

      MediaStream mediaStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (!kIsWeb) {
        if (Platform.isWindows) {
          // ignore: unused_local_variable
          var track = mediaStream.getVideoTracks().first;
        }
      }
      final int resolvedmaxLayer =
          (maxLayer > 0 && maxLayer <= 3) ? maxLayer : 3;

      CustomTrack customVideoTrack = CustomTrack.videoTrack(
        mediaStream: mediaStream,
        multiStream: multiStream,
        videoEncoderConfig: encoderConfig,
        maxLayer: resolvedmaxLayer,
        bitrateMode: bitrateMode,
        codec: codec,
        facingMode: facingMode,
        cameraId: selectedCameraId,
        // optimizationMode: optimizationMode
      );

      SdkTracer.shared.endSpan(createCameraVideoTrackSpan,
          attributes: {"config": customVideoTrack.toMap().toString()},
          message: "Custom Video Track created successfully");

      return customVideoTrack;
    } catch (e) {
      SdkTracer.shared.endSpan(createCameraVideoTrackSpan,
          attributes: {"error": "Device could not create video track!"},
          success: false,
          message: "Error while creating custom video track");

      if (e == "Unable to getUserMedia: NotAllowedError: Permission denied" ||
          e ==
              "Unable to getUserMedia: NotAllowedError: The request is not allowed by the user agent or the platform in the current context." ||
          e ==
              "Unable to getUserMedia: getUserMedia(): DOMException, NotAllowedError" ||
          e == "Unable to getUserMedia: NotAllowedError") {
        _eventEmitter.emit("error", VideoSDKErrors[3007]);

        log("An error occurred while creating Video Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3007]?['code']}  :: ${VideoSDKErrors[3007]?['name']} :: ${VideoSDKErrors[3007]?['message']}");
      } else if (e ==
              "Unable to getUserMedia: NotAllowedError: Permission denied by system" ||
          e ==
              "Unable to getUserMedia: NotFoundError: The object can not be found here.") {
        _eventEmitter.emit("error", VideoSDKErrors[3009]);

        log("An error occurred while creating Video track: VIDEOSDK ERROR :: ${VideoSDKErrors[3009]?['code']}  :: ${VideoSDKErrors[3009]?['name']} :: ${VideoSDKErrors[3009]?['message']}");
      } else if (e ==
              "Unable to getUserMedia: NotReadableError: Device in use" ||
          e ==
              "Unable to getUserMedia: AbortError: Starting videoinput failed") {
        _eventEmitter.emit("error", VideoSDKErrors[3003]);

        log("An error occurred while creating Video Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3003]?['code']}  :: ${VideoSDKErrors[3003]?['name']} :: ${VideoSDKErrors[3003]?['message']}");
      } else if (e.toString().contains(
          "TypeError: null: type 'Null' is not a subtype of type 'JSObject'")) {
        _eventEmitter.emit("error", VideoSDKErrors[3005]);

        log("An error occurred while creating Video Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3005]?['code']}  :: ${VideoSDKErrors[3005]?['name']} :: ${VideoSDKErrors[3005]?['message']}");
      } else {
        _eventEmitter.emit("error", VideoSDKErrors[3019]);

        log("An error occurred while creating Video Track: VIDEOSDK ERROR :: ${VideoSDKErrors[3019]?['code']}  :: ${VideoSDKErrors[3019]?['name']} :: ${VideoSDKErrors[3019]?['message']}");
      }
      return null;
    }
  }

  /// Applies a registered video processor to the video stream.
  ///
  /// This method enables the application of a video processor to add
  /// visual effects to the video stream. The processor must be registered
  /// during application initialization.
  ///
  /// > **Info:**
  /// > Only video processors that were registered during app initialization
  /// > are available for use during a meeting.
  /// >
  /// > To learn how to register a custom video processor, refer to the setup
  /// > guides for:
  /// > - Android: https://docs.videosdk.live/flutter/guide/video-and-audio-calling-api-sdk/video-processor/android-setup
  /// > - iOS: https://docs.videosdk.live/flutter/guide/video-and-audio-calling-api-sdk/video-processor/ios-setup
  ///
  /// ### **Parameters**
  ///
  /// - [videoProcessorName]:
  ///   The name of the registered video processor whose effect
  ///   should be applied.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Apply a registered video processor
  /// VideoSDK.applyVideoProcessor(
  ///   videoProcessorName: 'VirtualBGProcessor',
  /// );
  /// ```
  static void applyVideoProcessor({required String videoProcessorName}) =>
      _applyVideoProcessor(videoProcessorName: videoProcessorName);
  static void _applyVideoProcessor({required String videoProcessorName}) async {
    SpanScope applyVideoProcessorSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Applying Video Processor',
              attributes: {
                "processorName": videoProcessorName,
                "platform":
                    kIsWeb ? "web" : (Platform.isAndroid ? "android" : "ios"),
              },
              component: ComponentCategory.media,
            );
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _channel.invokeMethod(
            'processorMethod', {"videoProcessorName": videoProcessorName});
        SdkTracer.shared.endSpan(applyVideoProcessorSpan,
            message:
                "Video Processor '$videoProcessorName' applied successfully");
      } else {
        throw UnsupportedError('Applying a video processor is not supported.');
      }
    } catch (e) {
      SdkTracer.shared.endSpan(applyVideoProcessorSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while applying video processor");
      rethrow;
    }
  }

  /// This method removes a previously applied video processor from the video stream. This allows users to disable specific effects or revert to the original video state.
  /// The `removeVideoProcessor` method will remove the effect of the currently active video processor.
  ///
  /// #### Returns
  ///
  /// - `void`
  ///
  /// #### Example
  ///
  /// ```dart
  /// VideoSDK.removeVideoProcessor();
  /// ```

  static void removeVideoProcessor() => _removeVideoProcessor();
  static void _removeVideoProcessor() async {
    SpanScope removeVideoProcessorSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: 'Removing Video Processor',
              attributes: {
                "platform":
                    kIsWeb ? "web" : (Platform.isAndroid ? "android" : "ios"),
              },
              component: ComponentCategory.media,
            );
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _channel
            .invokeMethod('processorMethod', {"videoProcessorName": null});
        SdkTracer.shared.endSpan(removeVideoProcessorSpan,
            message: "Video Processor removed successfully");
      } else {
        throw UnsupportedError('Removing a video processor is not supported.');
      }
    } catch (e) {
      SdkTracer.shared.endSpan(removeVideoProcessorSpan,
          attributes: {"error": e.toString()},
          success: false,
          message: "Error while removing video processor");
      rethrow;
    }
  }

  /// Sets the encryption key provider for end-to-end encryption (E2EE).
  ///
  /// This method configures the [BaseKeyProvider] that will be used
  /// for encrypting and decrypting media streams. The provided key
  /// provider must have either a shared meeting-level key or a
  /// participant-specific key configured before being set.
  ///
  /// ### **Parameters**
  ///
  /// - [provider]:
  ///   A [BaseKeyProvider] instance containing the encryption key
  ///   configuration.
  ///
  /// ### Throws
  ///
  /// - Throws an [Exception] if neither a shared key nor a participant-specific
  ///   key has been set on the provided [BaseKeyProvider]. You must call
  ///   `setSharedKey()` or `setKey()` on the provider before passing it here.
  ///
  /// ### Behavior
  ///
  /// - If a shared key is provided, encryption is applied at the
  ///   **meeting level**.
  /// - If a participant-specific key is provided, encryption is applied
  ///   at the **participant level**.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// final BaseKeyProvider keyProvider = BaseKeyProvider();
  ///
  /// // Set a shared key for meeting-level encryption
  /// await keyProvider.setSharedKey('secure-meeting-key');
  ///
  /// // Configure the SDK with the key provider
  /// VideoSDK.setKeyProvider(keyProvider);
  /// ```
  static void setKeyProvider(BaseKeyProvider provider) =>
      _setKeyProvider(provider);
  static void _setKeyProvider(BaseKeyProvider provider) {
    SpanScope setKeyProviderSpan =
        SdkTracer.shared.to(OutputTarget.toConsole).startSpan(
              spanName: "Setting up key provider for E2EE",
            );
    // Check if both sharedKey and key are either null or empty
    if ((provider.sharedKey == null || provider.sharedKey!.isEmpty) &&
        (provider.key == null || provider.key!.isEmpty)) {
      SdkTracer.shared.endSpan(
        setKeyProviderSpan,
        attributes: {
          "error": "Shared Key not provided in key provider!",
        },
        message: "Error while setting up key provider",
      );
      throw Exception(
          "KeyProvider must have a sharedKey or Key to be set. Please call setSharedKey() or setKey() before passing the provider.");
    }

    if (provider.sharedKey == null || provider.sharedKey!.isEmpty) {
      e2eeType = "participant";
    } else {
      e2eeType = "meeting";
    }
    keyProvider = provider;
    SdkTracer.shared.endSpan(
      setKeyProviderSpan,
      message: "Key Provider set successfully",
    );
  }
}

/// @nodoc
enum MediaDeviceType {
  /// OPTIONS 1
  audioInput,

  /// OPTIONS 2
  audioOutput,

  /// OPTIONS 3
  videoInput,
}

/// @nodoc
enum PreferredProtocol {
  /// OPTIONS 1
  UDP_ONLY,

  /// OPTIONS 2
  UDP_OVER_TCP,

  /// OPTIONS 3
  TCP_ONLY,
}

/// Defines the camera facing mode for video capture.
///
/// - This enum specifies which camera should be used when creating
/// a camera video track.
///
/// ### **Example**
/// ```dart
/// final videoTrack = await VideoSDK.createCameraVideoTrack(
///   facingMode: FacingMode.user,
/// );
/// ```
enum FacingMode {
  /// Uses the rear-facing (environment) camera.
  ///
  /// - Typically used for capturing surroundings or external views.
  ///
  /// ### **Example**
  /// ```dart
  /// FacingMode.environment
  /// ```
  environment,

  /// Uses the front-facing (user) camera.
  ///
  /// -Commonly used for video calls and meetings.
  ///
  /// ### **Example**
  /// ```dart
  /// FacingMode.user
  /// ```
  user,
}
