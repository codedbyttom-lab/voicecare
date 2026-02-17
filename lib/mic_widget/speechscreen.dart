// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:highlight_text/highlight_text.dart';
// import 'package:voicecare/mic_widget/mic_button.dart';
// import 'package:voicecare/mic_widget/service_speech.dart';
// import 'package:voicecare/registration/user_registration.dart';

// class Speechscreen extends StatefulWidget {
//   const Speechscreen({super.key});

//   @override
//   State<Speechscreen> createState() => _SpeechscreenState();
// }

// class _SpeechscreenState extends State<Speechscreen> {
//   final SpeechService _speechService = Get.put(SpeechService());

//   final Map<String, HighlightedWord> _highlights = {
//     'Home screen': HighlightedWord(
//       onTap: () => Get.to(const UserReg()),
//       textStyle: const TextStyle(
//         color: Colors.blue,
//         fontWeight: FontWeight.bold,
//       ),
//     ),
//   };

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Obx(
//           () => Text("Confidence: "),
//         ),
//       ),
//       floatingActionButton: const MicButton(),
//       body: Column(
//         children: [
//           Expanded(
//             child: Container(
//               padding: const EdgeInsets.all(16.0),
//               child: Obx(() {
//                 final text = _speechService.speechText.value; // <-- works now
//                 return TextHighlight(
//                   text: text.isEmpty
//                       ? "Press the button and start speaking"
//                       : text,
//                   words: _highlights,
//                   textStyle: const TextStyle(
//                       fontSize: 24.0,
//                       color: Colors.black,
//                       fontWeight: FontWeight.w400),
//                 );
//               }),
//             ),
//           ),
//           ElevatedButton.icon(
//             onPressed: () => Get.to(const UserReg()),
//             icon: const Icon(Icons.home),
//             label: const Text("Go to Home"),
//           ),
//         ],
//       ),
//     );
//   }
// }
