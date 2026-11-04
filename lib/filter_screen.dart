import 'package:flutter/material.dart';

class ProfileFilters {
  String? nameQuery;
  int minAge;
  int maxAge;
  String? interest;
  String? location;

  ProfileFilters({this.nameQuery, this.minAge = 18, this.maxAge = 60, this.interest, this.location});
}

class FilterScreen extends StatefulWidget {
  final ProfileFilters currentFilters;
  const FilterScreen({super.key, required this.currentFilters});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController interestCtrl;
  late TextEditingController locationCtrl;
  late RangeValues ageRange;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.currentFilters.nameQuery ?? '');
    interestCtrl = TextEditingController(text: widget.currentFilters.interest ?? '');
    locationCtrl = TextEditingController(text: widget.currentFilters.location ?? '');
    ageRange = RangeValues(widget.currentFilters.minAge.toDouble(), widget.currentFilters.maxAge.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Filters")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name contains", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Text("Age range: ${ageRange.start.round()} - ${ageRange.end.round()}"),
            RangeSlider(
              values: ageRange,
              min: 18,
              max: 70,
              divisions: 52,
              labels: RangeLabels("${ageRange.start.round()}", "${ageRange.end.round()}"),
              onChanged: (values) => setState(() => ageRange = values),
            ),
            const SizedBox(height: 10),
            TextField(controller: interestCtrl, decoration: const InputDecoration(labelText: "Interest (e.g. travel)", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: "Location / city", border: OutlineInputBorder())),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                final filters = ProfileFilters(
                  nameQuery: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                  minAge: ageRange.start.round(),
                  maxAge: ageRange.end.round(),
                  interest: interestCtrl.text.trim().isEmpty ? null : interestCtrl.text.trim(),
                  location: locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim(),
                );
                Navigator.pop(context, filters);
              },
              child: const Text("Apply Filters"),
            ),
          ],
        ),
      ),
    );
  }
}