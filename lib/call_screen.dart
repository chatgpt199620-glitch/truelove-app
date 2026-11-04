	import 'package:flutter/material.dart';
	import 'package:agora_rtc_engine/agora_rtc_engine.dart';
	import 'package:permission_handler/permission_handler.dart';

	class CallScreen extends StatefulWidget {
	  final String channelName;
	  final bool isVideoCall;
	  final String otherName;
	  const CallScreen({super.key, required this.channelName, required this.isVideoCall, required this.otherName});

	  @override
	  State<CallScreen> createState() => _CallScreenState();
	}

	class _CallScreenState extends State<CallScreen> {
	  // ===== PASTE YOUR AGORA APP ID BELOW, BETWEEN THE QUOTES =====
	  static const String agoraAppId = "f2774569f860489cb62467b921f1f57b";
	  // ===== PASTE A TEMPORARY TOKEN FROM AGORA CONSOLE BELOW (or leave empty string "" if your project uses Testing mode) =====
	  static const String agoraTempToken = "";

	  late final RtcEngine engine;
	  bool joined = false;
	  int? remoteUid;
	  bool micMuted = false;
	  bool cameraOff = false;

	  @override
	  void initState() {
		super.initState();
		initAgora();
	  }

	  Future<void> initAgora() async {
		await [Permission.microphone, Permission.camera].request();

		engine = createAgoraRtcEngine();
		await engine.initialize(const RtcEngineContext(appId: agoraAppId));

		engine.registerEventHandler(RtcEngineEventHandler(
		  onJoinChannelSuccess: (connection, elapsed) {
			setState(() => joined = true);
		  },
		  onUserJoined: (connection, uid, elapsed) {
			setState(() => remoteUid = uid);
		  },
		  onUserOffline: (connection, uid, reason) {
			setState(() => remoteUid = null);
		  },
		));

		if (widget.isVideoCall) {
		  await engine.enableVideo();
		  await engine.startPreview();
		} else {
		  await engine.disableVideo();
		}

		await engine.joinChannel(
		  token: agoraTempToken,
		  channelId: widget.channelName,
		  uid: 0,
		  options: const ChannelMediaOptions(
			clientRoleType: ClientRoleType.clientRoleBroadcaster,
			channelProfile: ChannelProfileType.channelProfileCommunication,
		  ),
		);
	  }

	  @override
	  void dispose() {
		engine.leaveChannel();
		engine.release();
		super.dispose();
	  }

	  void toggleMic() {
		setState(() => micMuted = !micMuted);
		engine.muteLocalAudioStream(micMuted);
	  }

	  void toggleCamera() {
		setState(() => cameraOff = !cameraOff);
		engine.muteLocalVideoStream(cameraOff);
	  }

	  @override
	  Widget build(BuildContext context) {
		return Scaffold(
		  backgroundColor: Colors.black,
		  body: Stack(
			children: [
			  if (widget.isVideoCall && remoteUid != null)
				AgoraVideoView(
				  controller: VideoViewController.remote(
					rtcEngine: engine,
					canvas: VideoCanvas(uid: remoteUid),
					connection: RtcConnection(channelId: widget.channelName),
				  ),
				)
			  else
				Center(
				  child: Column(
					mainAxisAlignment: MainAxisAlignment.center,
					children: [
					  const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
					  const SizedBox(height: 16),
					  Text(widget.otherName, style: const TextStyle(color: Colors.white, fontSize: 22)),
					  const SizedBox(height: 8),
					  Text(joined ? (remoteUid == null ? "Calling..." : "Connected") : "Connecting...",
						  style: const TextStyle(color: Colors.white70)),
					],
				  ),
				),
			  if (widget.isVideoCall && joined)
				Positioned(
				  top: 40,
				  right: 16,
				  child: SizedBox(
					width: 100,
					height: 150,
					child: AgoraVideoView(
					  controller: VideoViewController(
						rtcEngine: engine,
						canvas: const VideoCanvas(uid: 0),
					  ),
					),
				  ),
				),
			  Positioned(
				bottom: 40,
				left: 0,
				right: 0,
				child: Row(
				  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
				  children: [
					FloatingActionButton(
					  heroTag: "mic",
					  backgroundColor: micMuted ? Colors.red : Colors.white24,
					  onPressed: toggleMic,
					  child: Icon(micMuted ? Icons.mic_off : Icons.mic, color: Colors.white),
					),
					FloatingActionButton(
					  heroTag: "end",
					  backgroundColor: Colors.red,
					  onPressed: () => Navigator.pop(context),
					  child: const Icon(Icons.call_end, color: Colors.white),
					),
					if (widget.isVideoCall)
					  FloatingActionButton(
						heroTag: "cam",
						backgroundColor: cameraOff ? Colors.red : Colors.white24,
						onPressed: toggleCamera,
						child: Icon(cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white),
					  ),
				  ],
				),
			  ),
			],
		  ),
		);
	  }
	}