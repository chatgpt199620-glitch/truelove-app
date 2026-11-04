// Shared option lists for profile details.
// Used by registration (main.dart) AND the edit screen (settings_screen.dart) so they never drift apart.

const List<String> kLookingForOptions = [
  'Long-term relationship',
  'Short-term relationship',
  'Casual / Timepass',
  'Friendship first',
  'Still figuring it out',
];
const List<String> kRelationshipOptions = ['Single', 'In a relationship', "It's complicated", 'Divorced', 'Widowed'];
const List<String> kReligionOptions = ['Hindu', 'Muslim', 'Christian', 'Sikh', 'Jain', 'Buddhist', 'Parsi', 'Jewish', 'Spiritual', 'No religion', 'Other'];
const List<String> kMotherTongueOptions = [
  'Hindi', 'Marathi', 'Gujarati', 'Bengali', 'Tamil', 'Telugu', 'Kannada', 'Malayalam',
  'Punjabi', 'Urdu', 'Odia', 'Assamese', 'Konkani', 'English', 'Other',
];
const List<String> kEducationOptions = [
  'High school', 'Diploma', "Bachelor's degree", "Master's degree", 'Doctorate (PhD)',
  'Professional (CA / CS / MBBS / LLB etc.)', 'Other',
];
const List<String> kEmployedInOptions = ['Private sector', 'Government / PSU', 'Business / Self-employed', 'Defence', 'Student', 'Not working'];
const List<String> kDietOptions = ['Vegetarian', 'Non-vegetarian', 'Eggetarian', 'Vegan', 'Jain'];

/// Heights from 137 cm (4'6") to 213 cm (7'0").
final List<int> kHeightsCm = List<int>.generate(77, (i) => 137 + i);

String heightLabel(int cm) {
  final totalInches = (cm / 2.54).round();
  return '${totalInches ~/ 12}\' ${totalInches % 12}" ($cm cm)';
}
