// import 'package:flutter/material.dart';
// import 'package:voicecare/mic_widget/mic_button.dart';

// class EmergencyContactReg extends StatefulWidget {
//   const EmergencyContactReg({super.key});

//   @override
//   State<EmergencyContactReg> createState() => _EmergencyContactRegState();
// }

// class _EmergencyContactRegState extends State<EmergencyContactReg> {
//   @override
//   Widget build(BuildContext context) {
//     final position = MediaQuery.of(context);
//     return Scaffold(
//       appBar: AppBar(
//         title: const Center(
//           child: Text(
//             'Emergency Contact',
//             style: TextStyle(
//               fontSize: 25,
//             ),
//           ),
//         ),
//       ),
//       body: Container(
//         decoration: const BoxDecoration(
//           image: DecorationImage(
//               image: AssetImage(
//                   'lib/assets/registration_assets/user_reg_wallpaper.png'),
//               alignment: Alignment.center,
//               scale: 1.9,
//               opacity: 0.9),
              
//         ),
//         child: Stack(
//           children: [
//             Padding(
//               padding: EdgeInsets.only(
//                   left: position.size.width * 0.02,
//                   right: position.size.width * 0.02),
//               child: Column(
//                 children: [
//                   const Divider(
//                     height: 0.5,
//                     thickness: 5,
//                     color: Colors.black,
//                     indent: 20,
//                     endIndent: 20,
//                   ),
//                   const SizedBox(height: 30), // This now works!

//                   const Row(
//                     children: [
//                       Expanded(
//                         child: TextField(
//                           decoration: InputDecoration(
//                             labelText: 'name',
//                             prefixIcon: Icon(
//                               Icons.person,
//                               color: Color.fromARGB(255, 156, 33, 37),
//                             ),
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.all(
//                                 Radius.circular(30),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                       SizedBox(width: 10),
//                       Expanded(
//                         child: TextField(
//                           decoration: InputDecoration(
//                             labelText: 'Surname',
//                             prefixIcon: Icon(
//                               Icons.person_outline,
//                               color: Color.fromARGB(255, 156, 33, 37),
//                             ),
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.all(
//                                 Radius.circular(30),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: position.size.height * 0.03),
//                   const TextField(
//                     decoration: InputDecoration(
//                       labelText: 'Email',
//                       prefixIcon: Icon(
//                         Icons.email,
//                         color: Color.fromARGB(255, 156, 33, 37),
//                       ),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.all(Radius.circular(30)),
//                       ),
//                     ),
//                   ),
//                   SizedBox(height: position.size.height * 0.03),
//                   const TextField(
//                     decoration: InputDecoration(
//                       labelText: '+27',
//                       prefixIcon: Icon(
//                         Icons.phone_android,
//                         color: Color.fromARGB(255, 156, 33, 37),
//                       ),
//                       border: OutlineInputBorder(
//                         borderRadius: BorderRadius.all(Radius.circular(30)),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             Positioned(
//               bottom: position.padding.bottom + 10,
//               left: 0,
//               right: 0,
//               child: const Center(child: MicButton()),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
