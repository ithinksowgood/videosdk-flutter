// ignore_for_file: prefer_typing_uninitialized_variables, deprecated_member_use, no_leading_underscores_for_local_identifiers, use_build_context_synchronously, avoid_print

import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:videosdk/videosdk.dart';
import 'package:videosdk_media_effects/videosdk_media_effects.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../widgets/screen_select_dialog.dart';
import '/screens/chat_screen.dart';
import '../../navigator_key.dart';
import '../utils/spacer.dart';
import '../utils/toast.dart';
import '../widgets/meeting_controls/meeting_action_bar.dart';
import '../widgets/participant_grid_view/participant_grid_view.dart';
import 'startup_screen.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';

// Meeting Screen

class MeetingScreen extends StatefulWidget {
  final String meetingId, token, displayName;
  final bool micEnabled, camEnabled, chatEnabled;
  const MeetingScreen({
    super.key,
    required this.meetingId,
    required this.token,
    required this.displayName,
    this.micEnabled = true,
    this.camEnabled = true,
    this.chatEnabled = true,
  });

  @override
  // ignore: library_private_types_in_public_api
  _MeetingScreenState createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen>
    with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.example/channel');
  // Recording Webhook
  final String recordingWebHookURL = "";
// RealTime Store Observing
  String? observerId;
  // Meeting
  late Room meeting;
  bool _joined = false;
  var relayMeetingId;
  var relayPeerId;
  // control states
  bool isRecordingOn = false;
  bool isLiveStreamOn = false;
  bool istranscriptionOn = false;
  bool isHlsOn = false;

  bool isWhiteboardOn = false;
  bool isFrontCam = true;
  late WebViewController controller;

  // List of controls
  List<VideoDeviceInfo>? cameras = [];
  List<AudioDeviceInfo>? mics = [];
  List<AudioDeviceInfo>? speakers = [];
  String? selectedMicId;
  Character? character;

  String? activePresenterId;

  String? url;
  String? base64Image;

  // Streams
  Stream? shareStream;
  Stream? videoStream;
  Stream? audioStream;
  Stream? remoteParticipantShareStream;
  int _cameraToggleCount = 0;
  final List<BitrateMode> _codecCycle = [
    BitrateMode.BALANCED,
    BitrateMode.HIGH_QUALITY,
  ];

  BaseKeyProvider customKeyProvider =
      BaseKeyProvider(); // Custom Key Provider for E2EE

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    // Create instance of Room (Meeting)
    initMeeting();
    WidgetsBinding.instance.addObserver(this);
  }

  initMeeting() async {
    VideoSDK.on(Events.error, (error) {
      log("VIDEOSDK ERROR :: ${error['code']}  :: ${error['name']} :: ${error['message']}");
    });

    //Creating Custom Video Track
    CustomTrack? videoTrack = await VideoSDK.createCameraVideoTrack(
      encoderConfig: CustomVideoTrackConfig.h720p_w1280p,
      multiStream: false,
      facingMode: FacingMode.user,
      maxLayer: 3,
      bitrateMode: BitrateMode.BANDWIDTH_OPTIMIZED,
      codec: VideoCodec.VP9,
    );

    //Creating Custom Audio Track
    CustomTrack? audioTrack = await VideoSDK.createMicrophoneAudioTrack(
      encoderConfig: CustomAudioTrackConfig.high_quality,
      noiseConfig: {
        "echoCancellation": true,
        "noiseSuppression": true,
        "autoGainControl": true,
      },
    );

    Room room = VideoSDK.createRoom(
      roomId: widget.meetingId,
      token: widget.token,
      displayName: "Flutter",
      micEnabled: true,
      camEnabled: true,
      maxResolution: 'hd',
      defaultCameraIndex: 0,
      multiStream: true,
      mode: Mode.SEND_AND_RECV,
      customCameraVideoTrack: videoTrack, // custom video track :: optional
      customMicrophoneAudioTrack: audioTrack, // custom audio track :: optional
      notification: const NotificationInfo(
        title: "Video SDK",
        message: "Video SDK is sharing screen in the meeting",
        icon: "notification_share", // drawable icon name
      ),
      translationLanguage: "en",
      speakingLanguage: "en",
    );

    // Register meeting events
    registerMeetingEvents(room);
    // Join meeting
    room.join();
    // keySetup(room);
    // Set up the encryption key
  }

  Future<void> keySetup(Room room) async {
    try {
      await customKeyProvider.setSharedKey("12345678");
      VideoSDK.setKeyProvider(customKeyProvider);
    } catch (e) {
      log("Error in setting the keys: ${e.toString()}");
    }
  }

  Future<void> _startMicrophoneService() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await platform.invokeMethod('startMicrophoneService');
      }
    } on PlatformException catch (e) {
      log("Failed to start service: '${e.message}'.");
    }
  }

  Future<void> _stopMicrophoneService() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await platform.invokeMethod('stopMicrophoneService');
      }
    } on PlatformException catch (e) {
      log("Failed to stop service: '${e.message}'.");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //Get statusbar height
    final statusbarHeight = MediaQuery.of(context).padding.top;

    // log("Meeting Data: ${widget.meetingId} ${widget.token}");
    return WillPopScope(
      onWillPop: _onWillPopScope,
      child: _joined
          ? Scaffold(
              backgroundColor:
                  Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
              floatingActionButton: MeetingActionBar(
                isMicEnabled: audioStream != null,
                isCamEnabled: videoStream != null,
                isScreenShareEnabled: shareStream != null,
                isScreenShareButtonDisabled:
                    remoteParticipantShareStream != null,
                // Called when Call End button is pressed
                onCallEndButtonPressed: () {
                  meeting.leave();
                },
                // Called when mic button is pressed
                onMicButtonPressed: () async {
                  if (meeting.micEnabled) {
                    meeting.muteMic();
                  } else {
                    //Create Custom Audio track
                    // CustomTrack? audioTrack =
                    //     await VideoSDK.createMicrophoneAudioTrack(
                    //         encoderConfig: CustomAudioTrackConfig.high_quality);
                    meeting.unmuteMic();
                  }
                },
                // Called when camera button is pressed
                onCameraButtonPressed: () async {
                  if (meeting.camEnabled) {
                    meeting.disableCam();
                  } else {
                    // Determine bitrate mode based on toggle count (cycles: BANDWIDTH_OPTIMIZED → BALANCED → HIGH_QUALITY → BANDWIDTH_OPTIMIZED → ...)
                    final bitrateMode =
                        _codecCycle[_cameraToggleCount % _codecCycle.length];

                    CustomTrack? track = await VideoSDK.createCameraVideoTrack(
                      encoderConfig: CustomVideoTrackConfig.h720p_w1280p,
                      multiStream: true,
                      bitrateMode: bitrateMode,
                      maxLayer: 5,
                      codec: VideoCodec.VP9,
                    );

                    await meeting.enableCam(track);

                    setState(() {
                      _cameraToggleCount++;
                    });
                  }
                },
                // Called when switch camera button is pressed
                onSwitchCameraButtonPressed: () async {
                  final selectedCamId = meeting.selectedCamId;

                  VideoDeviceInfo deviceToSwitch = cameras!.firstWhere(
                    (cam) => cam.deviceId != selectedCamId,
                  );

                  meeting.changeCam(deviceToSwitch);

                  setState(() {
                    isFrontCam =
                        deviceToSwitch.label.toLowerCase().contains("front") ||
                            deviceToSwitch.label.toLowerCase().contains("user");
                  });
                },

                // Called when ScreenShare button is pressed
                onScreenShareButtonPressed: () {
                  if (shareStream != null) {
                    meeting.disableScreenShare();
                  } else {
                    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
                      selectScreenSourceDialog(context).then((value) => {
                            if (value != null)
                              {
                                meeting.enableScreenShare(
                                    source: value, enableAudio: true)
                              }
                          });
                    } else if (!kIsWeb && Platform.isAndroid) {
                      meeting.enableScreenShare(enableAudio: true);
                    } else {
                      meeting.enableScreenShare();
                    }
                  }
                },

                // Called when more options button is pressed
                onMoreButtonPressed: () {
                  // Showing more options dialog box
                  showDialog<void>(
                    context: navigatorKey.currentContext!,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text("More options"),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ElevatedButton(
                              child: const Text('CHANGE INPUT AUDIO DEVICE'),
                              onPressed: () {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title:
                                        const Text("Select input Audio Device"),
                                    content: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        SingleChildScrollView(
                                          reverse: true,
                                          child: Column(
                                            children: mics!
                                                .map(
                                                  (e) => ElevatedButton(
                                                    child: Text(
                                                        "${e.label}  ${e.deviceId}"),
                                                    onPressed: () => {
                                                      meeting.changeMic(e),
                                                      Navigator.pop(context)
                                                    },
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            ElevatedButton(
                              child: const Text('CHANGE OUTPUT AUDIO DEVICE'),
                              onPressed: () {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                        "Select output Audio Device"),
                                    content: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        SingleChildScrollView(
                                          reverse: true,
                                          child: Column(
                                            children: speakers!
                                                .map(
                                                  (e) => ElevatedButton(
                                                    child: Text(
                                                        "${e.label} ${e.deviceId}"),
                                                    onPressed: () => {
                                                      meeting
                                                          .switchAudioDevice(e),
                                                      Navigator.pop(context)
                                                    },
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                            ElevatedButton(
                              child: const Text('CHANGE Video DEVICE'),
                              onPressed: () {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Select Video Device"),
                                    content: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        SingleChildScrollView(
                                          reverse: true,
                                          child: Column(
                                            children: cameras!
                                                .map(
                                                  (e) => ElevatedButton(
                                                    child: Text(e.label),
                                                    onPressed: () async => {
                                                      meeting.changeCam(e),
                                                      Navigator.pop(context)
                                                    },
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                base64Image = await meeting.localParticipant
                                    .captureImage();
                                log("Base64 Image captured $base64Image");
                              },
                              child: const Text("Capture Image"),
                            ),

                            ElevatedButton(
                              onPressed: () async {
                                url = await meeting.uploadBase64File(
                                  base64Data: base64Image!,
                                  token: widget.token,
                                  fileName: "image.png",
                                );
                                log("File Base Url : $url");
                              },
                              child: Text(
                                "Upload File",
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                String? file = await meeting.fetchBase64File(
                                  token: widget.token,
                                  url: url!,
                                );
                                log("Base64 File: $file");
                              },
                              child: Text("Fetch File"),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                await meeting.startTranslation();
                              },
                              child: Text("start Translation"),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                await meeting.changeTranslationLanguage('hi');
                              },
                              child: Text("Change Languages"),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                meeting.stopTranslation();
                              },
                              child: Text("Stop Translation"),
                            ),
                            ElevatedButton(
                              child: const Text('Add Character'),
                              onPressed: () {
                                CharacterConfig characterConfig =
                                    CharacterConfig.newInteraction(
                                  characterId: "shivani-v1",
                                  displayName: "MyCharacter",
                                  characterMode: CharacterMode.AUTO_PILOT,
                                  metaData: {"abcd": "xyz"},
                                  knowledgeBases: [
                                    "67c2c751-85c3-468e-9091-2c03e5ccc657"
                                  ],
                                  language: "hi",
                                );
                                character = meeting.createCharacter(
                                    characterConfig: characterConfig);
                                registerCharacterEvents(character!);
                                character?.join();

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Send Message to Character'),
                              onPressed: () {
                                character?.sendMessage(message: "Hey there");

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Leave Character'),
                              onPressed: () {
                                character?.leave();

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Interrupt Character'),
                              onPressed: () {
                                character?.interrupt();

                                Navigator.pop(context);
                              },
                            ),
                            //Change Mode
                            ElevatedButton(
                              child:
                                  const Text('Change Mode Send & recv -> recv'),
                              onPressed: () async {
                                if (meeting.localParticipant.mode ==
                                    Mode.SEND_AND_RECV) {
                                  meeting.changeMode(Mode.RECV_ONLY);
                                } else if (meeting.localParticipant.mode ==
                                    Mode.RECV_ONLY) {
                                  meeting.changeMode(Mode.SEND_AND_RECV);
                                }
                                Navigator.pop(context);
                              },
                            ),
                            //Change Mode
                            ElevatedButton(
                              child: const Text('Change Mode sig -> recv'),
                              onPressed: () async {
                                if (meeting.localParticipant.mode ==
                                    Mode.SIGNALLING_ONLY) {
                                  meeting.changeMode(Mode.RECV_ONLY);
                                } else if (meeting.localParticipant.mode ==
                                    Mode.RECV_ONLY) {
                                  meeting.changeMode(Mode.SIGNALLING_ONLY);
                                }
                                Navigator.pop(context);
                              },
                            ),
                            //Change Mode
                            ElevatedButton(
                              child: const Text('Change Mode'),
                              onPressed: () async {
                                if (meeting.localParticipant.mode ==
                                    Mode.SEND_AND_RECV) {
                                  meeting.changeMode(Mode.SIGNALLING_ONLY);
                                } else if (meeting.localParticipant.mode ==
                                    Mode.SIGNALLING_ONLY) {
                                  meeting.changeMode(Mode.SEND_AND_RECV);
                                }
                                Navigator.pop(context);
                              },
                            ),
                            // Chat
                            ElevatedButton(
                              child: const Text('Chat'),
                              onPressed: () {
                                Navigator.pop(context);
                                showModalBottomSheet(
                                  context: context,
                                  constraints: BoxConstraints(
                                      maxHeight:
                                          MediaQuery.of(context).size.height -
                                              statusbarHeight),
                                  isScrollControlled: true,
                                  builder: (context) =>
                                      ChatScreen(meeting: meeting),
                                );
                              },
                            ),

                            // Recording button
                            ElevatedButton(
                              child: Text(
                                isRecordingOn
                                    ? 'Stop Recording'
                                    : 'Start Recording',
                              ),
                              onPressed: () {
                                if (isRecordingOn) {
                                  meeting.stopRecording();
                                } else {
                                  meeting.startRecording();
                                }

                                Navigator.pop(context);
                              },
                            ),

                            ElevatedButton(
                              child: Text(
                                isWhiteboardOn
                                    ? 'Stop Whiteboard'
                                    : 'Start Whiteboard',
                              ),
                              onPressed: () {
                                if (isWhiteboardOn) {
                                  meeting.stopWhiteboard();
                                } else {
                                  meeting.startWhiteboard();
                                }

                                Navigator.pop(context);
                              },
                            ),

                            // Recording button
                            ElevatedButton(
                              child: Text(isHlsOn ? 'Stop HLS' : 'Start HLS'),
                              onPressed: () {
                                PostTranscriptionConfig
                                    postTranscriptionConfig =
                                    PostTranscriptionConfig(
                                  enabled: true,
                                  modelId: "raman_v1",
                                  summaryConfig: SummaryConfig(
                                      enabled: true,
                                      prompt:
                                          "Write summary in sections like Title, Agenda, Speakers, Action Items, Outlines, Notes and Summary"),
                                );
                                if (isHlsOn) {
                                  meeting.stopHls();
                                } else {
                                  meeting.startHls(
                                      config: {
                                        'layout': {
                                          'type': 'GRID',
                                          'priority': 'SPEAKER',
                                          'gridSize': 4,
                                        },
                                        'theme': "LIGHT",
                                        "mode": "video-and-audio"
                                      },
                                      postTranscriptionConfig:
                                          postTranscriptionConfig);
                                }

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Enable Noise Cancellation'),
                              onPressed: () {
                                VideosdkMediaEffects.startNoiseSuppression();
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Disable Noise Cancellation'),
                              onPressed: () {
                                VideosdkMediaEffects.stopNoiseSuppression();
                                Navigator.pop(context);
                              },
                            ),
                            //transcription Demo
                            ElevatedButton(
                              child: Text(
                                istranscriptionOn
                                    ? 'Stop Transcription'
                                    : 'Start Transcription',
                              ),
                              onPressed: () {
                                TranscriptionConfig transcriptionConfig =
                                    TranscriptionConfig(
                                        webhookUrl: "Web hook url here ",
                                        summaryConfig: SummaryConfig(
                                            enabled: true,
                                            prompt:
                                                "Write summary in sections like Title, Agenda, Speakers, Action Items, Outlines, Notes and Summary"));

                                if (!istranscriptionOn) {
                                  meeting.startTranscription(
                                      transcriptionConfig: transcriptionConfig);
                                } else {
                                  meeting.stopTranscription();
                                }

                                Navigator.pop(context);
                              },
                            ),
                            // LiveStream button
                            ElevatedButton(
                              child: Text(
                                isLiveStreamOn
                                    ? 'Stop Livestream'
                                    : 'Start Livestream',
                              ),
                              onPressed: () {
                                var outputs = [
                                  {
                                    'url': "Enter live stream url here",
                                    'streamKey': "Enter stream key here ",
                                  },
                                ];

                                PostTranscriptionConfig
                                    postTranscriptionConfig =
                                    PostTranscriptionConfig(
                                  enabled: true,
                                  modelId: "raman_v1",
                                  summaryConfig: SummaryConfig(
                                      enabled: true,
                                      prompt:
                                          "Write summary in sections like Title, Agenda, Speakers, Action Items, Outlines, Notes and Summary"),
                                );
                                var liveStreamConfig = {
                                  'layout': {
                                    'type': 'GRID',
                                    'priority': 'SPEAKER',
                                    'gridSize': 4,
                                  },
                                  'theme': "LIGHT",
                                };
                                if (isLiveStreamOn) {
                                  meeting.stopLivestream();
                                } else {
                                  if (outputs.isNotEmpty) {
                                    meeting.startLivestream(outputs,
                                        config: liveStreamConfig,
                                        postTranscriptionConfig:
                                            postTranscriptionConfig);
                                  } else {
                                    toastMsg(
                                      "Failed to start livestream. Please add live stream options.",
                                    );
                                  }
                                }

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Selected devices'),
                              onPressed: () async {
                                List<AudioDeviceInfo>? audioDevices =
                                    await VideoSDK.getAudioDevices();
                                // print("Videosdk Audio Devices: $audioDevices");
                                // print(
                                //     "Selected Mic: ${meeting.selectedMic?.label} ${meeting.selectedMic?.deviceId}");
                                // print(
                                //     "Selected Speaker: ${meeting.selectedSpeaker?.label} ${meeting.selectedSpeaker?.deviceId}");
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Apply Package Background'),
                              onPressed: () async {
                                Uri backgroundImageUri = Uri.parse(
                                    "https://st.depositphotos.com/2605379/52364/i/450/depositphotos_523648932-stock-photo-concrete-rooftop-night-city-view.jpg");
                                await VideosdkMediaEffects
                                    .applyVirtualBackground(
                                        backgroundSource: backgroundImageUri);
                                // VideoSDK.applyVideoProcessor(
                                //     videoProcessorName: "VirtualBGProcessor");
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Change Virtual Background'),
                              onPressed: () {
                                Uri backgroundImageUri = Uri.parse(
                                    "https://wallpapers.com/images/featured/abstract-background-6m6cjbifu3zpfv84.jpg");
                                VideosdkMediaEffects.changeVirtualBackground(
                                    backgroundSource: backgroundImageUri);

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Remove Virtual Background'),
                              onPressed: () {
                                VideoSDK.removeVideoProcessor();
                                VideosdkMediaEffects.removeVirtualBackground();
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              onPressed: () {
                                meeting.pauseAllStreams();
                              },
                              child: Text("Puse all Stream"),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                meeting.resumeAllStreams();
                              },
                              child: Text("Resume all Stream"),
                            ),
                            ElevatedButton(
                              child: const Text('Low Resolution'),
                              onPressed: () {
                                meeting.participants.forEach((key, value) {
                                  value.setQuality('low');
                                });

                                Navigator.pop(context);
                              },
                            ),

                            ElevatedButton(
                              child: const Text('Med Resolution'),
                              onPressed: () {
                                meeting.participants.forEach((key, value) {
                                  value.setQuality('med');
                                });

                                Navigator.pop(context);
                              },
                            ),

                            ElevatedButton(
                              child: const Text('High Resolution'),
                              onPressed: () {
                                meeting.participants.forEach((key, value) {
                                  value.setQuality('high');
                                });

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Switch Meeting'),
                              onPressed: () {
                                meeting.switchTo("754v-8c9f-jirr",
                                    token: widget.token);

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Request Relay'),
                              onPressed: () {
                                meeting.requestMediaRelay("99iy-uyji-9n1a",
                                    token: widget.token,
                                    kinds: [
                                      "video",
                                      "audio",
                                      "share",
                                      "share_audio"
                                    ]);
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Stop Relay'),
                              onPressed: () {
                                meeting
                                    .stopMediaRelay("Destination-meeting-id");
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Enable Relay'),
                              onPressed: () {
                                meeting.enableRelayMedia(
                                    "Destination-meeting-id",
                                    ["video", "audio"]);
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Disable Relay'),
                              onPressed: () {
                                meeting.disableRelayMedia(
                                    "Destination-meeting-id",
                                    ["video", "audio"]);

                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Set Value'),
                              onPressed: () async {
                                await meeting.realtimeStore
                                    .setValue("BLOCK_CHAT", "True");
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Get Value'),
                              onPressed: () async {
                                String? response = await meeting.realtimeStore
                                    .getValue("BLOCK_CHAT");
                                //   print("Response from the get Value:$response");
                                Navigator.pop(context);
                              },
                            ),
                            ElevatedButton(
                              child: const Text('Observe'),
                              onPressed: () async {
                                // Store the observer ID for later cleanup

                                observerId =
                                    await meeting.realtimeStore.observe(
                                  "BLOCK_CHAT",
                                  (value, updatedBy) {
                                    // print("Value: $value");
                                    // as participant can be null so kept in try catch
                                    try {
                                      print("Updated by: ${updatedBy!.id}");
                                    } catch (_) {
                                      log("Error is that particpant");
                                    }

                                    // Handle the change in your UI
                                    setState(() {
                                      // Update your state based on the new value
                                    });
                                  },
                                );
                                Navigator.pop(context);
                              },
                            ),

                            ElevatedButton(
                              child: const Text('Stop Observing'),
                              onPressed: () async {
                                if (observerId != null) {
                                  await meeting.realtimeStore
                                      .stopObserving(observerId!);
                                  log("Stopped observing with ID: $observerId");
                                  observerId = null; // Clear the observer ID
                                } else {
                                  log("No active observer to stop");
                                }
                                Navigator.pop(context);
                              },
                            ),
                            //check selected devices
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerFloat,
              appBar: AppBar(
                title: Text(widget.meetingId),
                actions: [
                  // Recording status
                  if (isRecordingOn)
                    SvgPicture.asset("assets/recording_on.svg"),

                  IconButton(
                    tooltip: 'Cycle all 4 codecs',
                    icon: const Icon(Icons.fast_forward),
                    onPressed: () => cycleAllCodecs(meeting),
                  ),

                  PopupMenuButton<VideoCodec>(
                    tooltip: 'Test codec',
                    icon: const Icon(Icons.video_settings),
                    onSelected: (VideoCodec codec) {
                      toastMsg('Switching webcam codec → ${codec.name}');
                      handleCodecSwitch(meeting, codec);
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<VideoCodec>>[
                      PopupMenuItem(
                          value: VideoCodec.VP8, child: Text('Codec: VP8')),
                      PopupMenuItem(
                          value: VideoCodec.VP9, child: Text('Codec: VP9')),
                      PopupMenuItem(
                          value: VideoCodec.AV1, child: Text('Codec: AV1')),
                      PopupMenuItem(
                          value: VideoCodec.H264, child: Text('Codec: H264')),
                    ],
                  ),

                  // Copy meeting id button
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.meetingId));
                      toastMsg("Meeting ID has been copied.");
                    },
                  ),
                ],
              ),
              body: Padding(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  child: Column(
                    children: [
                      if (remoteParticipantShareStream != null ||
                          shareStream != null)
                        SizedBox(
                          height: 200,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              height: 300,
                              color: Colors.black,
                              child: RTCVideoView(
                                remoteParticipantShareStream != null
                                    ? remoteParticipantShareStream!.renderer!
                                    : shareStream!.renderer!,
                              ),
                            ),
                          ),
                        ),
                      if (isWhiteboardOn)
                        SizedBox(
                          height: 300,
                          width: 350,
                          child: WebViewWidget(
                            controller: controller,
                          ),
                        ),
                      Expanded(
                        child: ParticipantGridView(
                          meeting: meeting,
                          isFrontCam: isFrontCam,
                        ),
                      ),
                    ],
                  )))
          : Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(),
                    VerticalSpacer(10),
                    Text("waiting to join meeting"),
                  ],
                ),
              ),
            ),
    );
  }

  void registerEventListener(Room meeting) async {
    PubSubMessages messages = await meeting.pubSub
        .subscribe("CHANGE_MODE_${meeting.localParticipant.id}",
            (PubSubMessage pubSubMessage) {
      String message = pubSubMessage.message;
      if (mounted) {
        showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                content: Text(
                    "${pubSubMessage.senderName} requested to join as a speaker"),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.black,
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  MaterialButton(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.black,
                      child:
                          const Text("Decline", style: TextStyle(fontSize: 16)),
                      onPressed: () {
                        Navigator.pop(context);
                      }),
                  MaterialButton(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: Colors.purple,
                      child:
                          const Text("Accept", style: TextStyle(fontSize: 16)),
                      onPressed: () {
                        meeting.camEnabled;
                        Navigator.pop(context);
                      }),
                ],
              );
            });
      }
    });
  }

  void registerCharacterEvents(Character character) {
    character.on(Events.characterJoined, (Character character) {
      log("Character Joined in character event with config $character ${character.runtimeType}");
    });

    character.on(Events.characterLeft, (Character character) {
      log("Character left in character event with config $character ${character.runtimeType}");
    });

    character.on(Events.characterMessage, (CharacterMessage message) {
      log("character Message ${message.text} ${message.characterId} ${message.characterName} ${message.runtimeType}");
    });

    character.on(Events.userMessage, (UserMessage message) {
      log("user Message ${message.text} ${message.participantId} ${message.participantName} ${message.runtimeType}");
    });

    character.on(Events.characterStateChanged, (CharacterState state) {
      log("character state changed $state ${state.runtimeType}");
    });

    character.on(Events.streamEnabled, (data) {
      log("stream come $data");
    });
  }

  void handleCodecSwitch(Room meeting, VideoCodec codec) async {
    await meeting.disableCam();

    await Future.delayed(Duration(seconds: 5));

    CustomTrack? videoTrack = await VideoSDK.createCameraVideoTrack(
      encoderConfig: CustomVideoTrackConfig.h720p_w1280p,
      multiStream: true,
      facingMode: FacingMode.user,
      bitrateMode: BitrateMode.BALANCED,
      codec: codec,
    );

    await meeting.enableCam(videoTrack);
  }

  bool _codecCycleRunning = false;

  Future<void> cycleAllCodecs(Room meeting) async {
    if (_codecCycleRunning) {
      toastMsg('Codec cycle already running');
      return;
    }

    _codecCycleRunning = true;

    const codecs = [
      VideoCodec.VP8,
      VideoCodec.VP9,
      VideoCodec.AV1,
      VideoCodec.H264,
    ];

    try {
      for (final codec in codecs) {
        toastMsg('Switching webcam codec → ${codec.name}');
        handleCodecSwitch(meeting, codec);
        await Future.delayed(const Duration(seconds: 12));
      }
      toastMsg('Codec cycle complete');
    } finally {
      _codecCycleRunning = false;
    }
  }

  void registerMeetingEvents(Room _meeting) {
    _meeting.on(Events.codecChanged, (CodecChangeInfo data) {
      final who = data.causedBy?.displayName ?? 'unknown peer';
      final msg =
          'codecChanged: ${data.previousCodec.name} → ${data.currentCodec.name} '
          '(rejected ${data.unsupportedRemoteCodec.name} by $who)';
      print(msg);
      toastMsg(msg);
    });

    VideoSDK.on(Events.deviceChanged, () async {
      cameras = await VideoSDK.getVideoDevices();
      List<AudioDeviceInfo>? audioDeviceInfo = await VideoSDK.getAudioDevices();

      mics = [];
      speakers = [];

      if (audioDeviceInfo != null) {
        for (var device in audioDeviceInfo) {
          if (device.kind == 'audioinput') {
            mics?.add(device);
          } else {
            speakers?.add(device);
          }
        }
      }
    });
    // Called when joined in meeting
    _meeting.on(
      Events.roomJoined,
      () async {
        // _meeting.enableAdaptiveSubscription();
        _meeting.localParticipant.pin();
        setState(() {
          meeting = _meeting;
          _joined = true;
        });
        if (!kIsWeb && Platform.isAndroid && meeting.micEnabled) {
          _startMicrophoneService();
        }
        // Holds available cameras info
        cameras = await VideoSDK.getVideoDevices();
        List<AudioDeviceInfo>? audioDeviceInfo =
            await VideoSDK.getAudioDevices();

        if (audioDeviceInfo != null) {
          for (var device in audioDeviceInfo) {
            if (device.kind == 'audioinput') {
              mics?.add(device);
            } else {
              speakers?.add(device);
            }
          }
        }

        _meeting.pubSub.subscribe(
          _meeting.localParticipant.id,
          (message) {
            try {
              final codecString = message.message.toUpperCase();

              var codec;

              if (codecString == "AV1") {
                codec = VideoCodec.AV1;
              } else if (codecString == "VP9") {
                codec = VideoCodec.VP9;
              } else if (codecString == "H264") {
                codec = VideoCodec.H264;
              } else {
                codec = VideoCodec.VP8;
              }

              handleCodecSwitch(_meeting, codec);
            } catch (e) {
              print("error ${e.toString()}");
            }
          },
        );
      },
    );
    _meeting.on(Events.mediaRelayRequestReceived,
        (meetingId, peerId, displayName, accept, reject) {
      relayMeetingId = meetingId;
      relayPeerId = peerId;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Media Relay Request'),
            content: Text(
                'User $relayPeerId wants to relay media in meeting $relayMeetingId.'),
            actions: [
              TextButton(
                child: Text('Allow'),
                onPressed: () {
                  accept();
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: Text('Deny'),
                onPressed: () {
                  reject();
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    });
    _meeting.on(Events.mediaRelayRequestResponse, (decidedBy, decision) {
      log("Media Realy response by: $decidedBy, decision: $decision");
    });
    // Called when meeting is ended
    _meeting.on(Events.roomLeft, (LeaveReason? reason) {
      if (reason != null) {
        toastMsg("Meeting left due to ${reason.message}  ${reason.code}!!");
      }

      if (!kIsWeb && Platform.isAndroid) {
        _stopMicrophoneService();
      }

      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const StartupScreen()),
          (route) => false);
    });

    _meeting.on(Events.roomStateChanged, (RoomState state) {
      toastMsg(
        "Current state of room: $state",
      );
      switch (state) {
        case RoomState.connecting:
          log('Meeting is Connecting');
          break;
        case RoomState.connected:
          log('Meeting is Connected');
          break;
        case RoomState.disconnected:
          log('Meeting connection disconnected abruptly');
          break;
        case RoomState.reconnecting:
          log("Meeting is in reconnecting state");
          break;
        case RoomState.failed:
          log("Meeting could not be joined — see the error event for why");
          break;
      }
    });

    // Called when recording is started
    _meeting.on(Events.recordingStarted, () {
      toastMsg("Meeting recording started.");

      setState(() {
        isRecordingOn = true;
      });
    });

    _meeting.on(Events.recordingStateChanged, (String status) {
      toastMsg("Meeting recording status : $status");
    });

    _meeting.on(Events.mediaRelayStarted, (meetingId) {
      log("Media relay started: $meetingId");
    });

    // Called when recording is started
    _meeting.on(Events.recordingStateChanged, (String status) {
      toastMsg("Meeting recording status : $status");
    });
    // Called when recording is stopped
    _meeting.on(Events.recordingStopped, () {
      toastMsg("Meeting recording stopped.");

      setState(() {
        isRecordingOn = false;
      });
    });

    _meeting.on(Events.whiteboardStarted, (url) {
      toastMsg("Whiteboard started $url .");
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(
          Uri.parse(url),
        );

      setState(() {
        isWhiteboardOn = true;
      });
    });

    // Called when recording is stopped
    _meeting.on(Events.whiteboardStopped, () {
      toastMsg("Whiteboard stopped.");

      setState(() {
        isWhiteboardOn = false;
      });
    });

    // Called when LiveStreaming is started
    _meeting.on(Events.liveStreamStarted, () {
      toastMsg("Meeting live streaming started.");

      setState(() {
        isLiveStreamOn = true;
      });
    });

    _meeting.on(Events.error, (error) {
      log("VIDEOSDK ERROR :: ${error['code']}  :: ${error['name']} :: ${error['message']}");
    });

    // Called when LiveStreaming is stopped
    _meeting.on(Events.liveStreamStopped, () {
      toastMsg("Meeting live streaming stopped.");

      setState(() {
        isLiveStreamOn = false;
      });
    });

    // Called when LiveStreaming is stopped

    _meeting.on(Events.liveStreamStateChanged, (String status) {
      toastMsg("Meeting live streaming status : $status");
    });
    _meeting.on(Events.transcriptionStateChanged, (Map<String, dynamic> data) {
      if (data['status'] == 'TRANSCRIPTION_STARTING') {
        toastMsg("Transcription Starting");
      } else if (data['status'] == 'TRANSCRIPTION_STARTED') {
        toastMsg("Transcription started");
        setState(() {
          istranscriptionOn = true;
        });
      } else if (data['status'] == 'TRANSCRIPTION_STOPPING') {
        toastMsg("Transcription Stopping");
      } else if (data['status'] == 'TRANSCRIPTION_STOPPED') {
        toastMsg("Transcription Stopped");
        setState(() {
          istranscriptionOn = false;
        });
      }
    });

    _meeting.on(Events.transcriptionText, (TranscriptionText data) {
      var participantId = data.participantId;
      var participantName = data.participantName;
      var text = data.text;
      var timestamp = data.timestamp;
      var type = data.type;
    });

    _meeting.on(Events.translationStateChanged, (TranslationState state) {
      log("translationStateChanged $state");
    });

    _meeting.on(Events.translationText, (TranslationText data) {
      log("${data.participantName} : ${data.text}");
    });

    _meeting.on(Events.translationLanguageChanged, (String language) {
      log('translation langugaues $language');
    });

    // Called when HLS is started
    _meeting.on(Events.hlsStarted, (downstreamUrl) {
      toastMsg("Meeting HLS started.");
      log("DOWNSTREAM URL -- $downstreamUrl");
      setState(() {
        isHlsOn = true;
      });
    });

    // Called when LiveStreaming is stopped
    _meeting.on(Events.hlsStopped, () {
      toastMsg("Meeting HLS stopped.");
      setState(() {
        isHlsOn = false;
      });
    });

    _meeting.on(Events.hlsStateChanged, (Map<String, dynamic> data) {
      toastMsg("Meeting HLS status : ${data['status']}");
      if (data['status'] == "HLS_STARTED") {
        print("DOWNSTREAM URL -- ${data['downstreamUrl']}");
      }
    });

    // Called when mic is requested
    _meeting.on(Events.micRequested, (_data) {
      log("_data => $_data");
      dynamic accept = _data['accept'];
      dynamic reject = _data['reject'];

      log("accept => $accept reject => $reject");

      // Mic Request Dialog
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text("Mic requested?"),
          content: const Text("Do you want to turn on your mic? "),
          actions: [
            TextButton(
              onPressed: () {
                reject();

                Navigator.of(context).pop();
              },
              child: const Text("Reject"),
            ),
            TextButton(
              onPressed: () {
                accept();

                Navigator.of(context).pop();
              },
              child: const Text("Accept"),
            ),
          ],
        ),
      );
    });
    _meeting.on(Events.mediaRelayStopped, (meetingId, reason) {
      String _reason = reason;
      switch (_reason) {
        case "user_stopped":
          toastMsg("Media relay stopped");
          break;
        case "connection_lost":
          toastMsg("Media relay ended");
          break;
        default:
          toastMsg("Media relay stopped");
      }
    });
    _meeting.on(Events.mediaRelayError, (meetingId, reason) {
      log("Media Relay error: $reason");
    });

    // Called when camera is requested
    _meeting.on(Events.cameraRequested, (_data) {
      log("_data => $_data");
      dynamic accept = _data['accept'];
      dynamic reject = _data['reject'];

      log("accept => $accept reject => $reject");

      // camera Request Dialog
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text("Camera requested?"),
          content: const Text("Do you want to turn on your Camera? "),
          actions: [
            TextButton(
              onPressed: () {
                reject();

                Navigator.of(context).pop();
              },
              child: const Text("Reject"),
            ),
            TextButton(
              onPressed: () {
                accept();

                Navigator.of(context).pop();
              },
              child: const Text("Accept"),
            ),
          ],
        ),
      );
    });

    // Called when stream is enabled
    _meeting.localParticipant.on(Events.streamEnabled, (Stream _stream) {
      if (_stream.kind == 'video') {
        setState(() {
          videoStream = _stream;
        });
      } else if (_stream.kind == 'audio') {
        setState(() {
          audioStream = _stream;
        });
      } else if (_stream.kind == 'share') {
        setState(() {
          shareStream = _stream;
        });
      }
    });

    _meeting.on(Events.participantJoined, (Participant participant) {
      toastMsg("participant joined , $participant");
      // try {
      //   customKeyProvider.setKey(participant.id, participant.displayName);
      // } catch (e) {
      //   log("E2EE Error in setting the keys: ${e.toString()}");
      // }
    });

    _meeting.on(Events.participantLeft, (
      String participantId,
      LeaveReason reason,
    ) {
      toastMsg(
          "Participant left: $participantId, reason: ${reason.message}, code: ${reason.code}");
    });

    _meeting.on(Events.pinStateChanged, (Map<String, dynamic> data) {
      final participantId = data['participantId'];
      final pinnedBy = data['pinnedBy'];
      final state = data['state'];
    });
    _meeting.localParticipant.on(Events.streamDisabled, (Stream _stream) {
      if (_stream.kind == 'video' && videoStream?.id == _stream.id) {
        setState(() {
          videoStream = null;
        });
      } else if (_stream.kind == 'audio' && audioStream?.id == _stream.id) {
        setState(() {
          audioStream = null;
        });
      } else if (_stream.kind == 'share' && shareStream?.id == _stream.id) {
        setState(() {
          shareStream = null;
        });
      }
    });

    // Called when presenter is changed
    _meeting.on(Events.presenterChanged, (_activePresenterId) {
      Participant? activePresenterParticipant =
          _meeting.participants[_activePresenterId];

      // Get Share Stream
      Stream? _stream = activePresenterParticipant?.streams.values
          .singleWhere((e) => e.kind == "share");

      setState(() => remoteParticipantShareStream = _stream);
    });

    //Entry Event
    _meeting.on(Events.entryRequested, (data) {
      var name = data["name"];
      var allow = data["allow"];
      var deny = data["deny"];

      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text("Join Request"),
          content: Text("Do you want to allow $name to join meeting?"),
          actions: [
            TextButton(
              onPressed: () {
                deny();
                Navigator.of(context).pop();
              },
              child: const Text("Deny"),
            ),
            TextButton(
              onPressed: () {
                allow();

                Navigator.of(context).pop();
              },
              child: const Text("Allow"),
            ),
          ],
        ),
      );
    });

    _meeting.on(Events.entryResponded, (data) {
      var id = data['id'];
      var decision = data['decision'];
      if (id == _meeting.localParticipant.id) {
        if (decision == 'allowed') {
          toastMsg("Allowed to join the meeting.");
        } else {
          toastMsg("Denied to join the meeting.");
          Navigator.of(context).pop();
        }
      }
    });

    _meeting.on(Events.pausedAllStreams, (kind) {
      log("Pause $kind Consumer");
    });

    _meeting.on(Events.resumedAllStreams, (kind) {
      log("resumed $kind Consumer");
    });

    _meeting.on(Events.error, (error) {
      log("VIDEOSDK ERROR :: ${error['code']}  :: ${error['name']} :: ${error['message']}");
      toastMsg("VIDEOSDK ERROR :: ${error['message']}");
    });

    _meeting.on(Events.qualityLimitation, (time, state, timestamp) {
      log("Quality Limitation for type:$time in $state at $timestamp");
    });
  }

  Future<bool> _onWillPopScope() async {
    meeting.leave();
    return true;
  }

  Future<DesktopCapturerSource?> selectScreenSourceDialog(
      BuildContext context) async {
    final source = await showDialog<DesktopCapturerSource>(
      context: context,
      builder: (context) => ScreenSelectDialog(
        meeting: meeting,
      ),
    );
    return source;
  }
}
