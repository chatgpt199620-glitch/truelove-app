import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Shows everything collected at registration (Jeevansathi-style details).
/// Pass the user's Firestore document map:
///
///   ProfileDetailsCard(data: userData)
///
/// Empty values are hidden automatically.
class ProfileDetailsCard extends StatelessWidget {
  final Map<String, dynamic> data;

  /// Set false where bio & interests are already shown (e.g. an edit form).
  final bool showAbout;
  const ProfileDetailsCard({super.key, required this.data, this.showAbout = true});

  String _s(String key) => (data[key] ?? '').toString().trim();

  String _age() {
    final dob = data['dob'];
    if (dob is! Timestamp) return '';
    final d = dob.toDate();
    final now = DateTime.now();
    int age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return '$age yrs';
  }

  String _place() {
    final parts = [_s('city'), _s('state'), _s('country')].where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? _s('location') : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final interests = (data['interests'] is List) ? List<String>.from(data['interests']) : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAbout && _s('bio').isNotEmpty) _section('About', [_row(Icons.info_outline, 'About', _s('bio'))]),
        _section('Basic details', [
          _row(Icons.wc, 'Gender', _s('gender')),
          _row(Icons.cake_outlined, 'Age', _age()),
          _row(Icons.favorite_border, 'Relationship status', _s('relationshipStatus')),
          _row(Icons.favorite, 'Looking for', _s('lookingFor')),
          _row(Icons.height, 'Height', _s('height')),
          _row(Icons.restaurant_outlined, 'Diet', _s('diet')),
        ]),
        _section('Background', [
          _row(Icons.temple_hindu_outlined, 'Religion', _s('religion')),
          _row(Icons.translate, 'Mother tongue', _s('motherTongue')),
        ]),
        _section('Education & career', [
          _row(Icons.school_outlined, 'Education', _s('education')),
          _row(Icons.business_center_outlined, 'Working in', _s('employedIn')),
          _row(Icons.work_outline, 'Occupation', _s('occupation')),
        ]),
        _section('Location', [
          _row(Icons.location_on_outlined, 'Lives in', _place()),
        ]),
        if (showAbout && interests.isNotEmpty)
          _section('Interests', [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: interests.map((i) => Chip(label: Text(i))).toList(),
            ),
          ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> rows) {
    // Hide the section if every row is empty.
    final visible = rows.where((w) => w is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 10),
            ...visible,
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.grey[600]))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
