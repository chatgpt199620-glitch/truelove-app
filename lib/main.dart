import 'update_notifier.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'profile_screen.dart';
import 'main_shell.dart';
import 'guidelines_screen.dart';
import 'user_utils.dart';
import 'animated_heart.dart';
import 'profile_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await UpdateNotifier.init();  // ← ADD THIS ONE LINE

  runApp(const MyApp());
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
	navigatorKey: navigatorKey, 
      title: 'TrueLove',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatelessWidget {
  const StartupGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!authSnapshot.hasData) return const WelcomeScreen();

        final uid = authSnapshot.data!.uid;
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final data = profileSnapshot.data?.data() as Map<String, dynamic>?;

            if (data?['isBanned'] == true) {
              FirebaseAuth.instance.signOut();
              return const WelcomeScreen();
            }

            final isComplete = data?['profileComplete'] == true;
            return isComplete ? const MainShell() : const ProfileSetupScreen();
          },
        );
      },
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AnimatedHeart(size: 85, animation: HeartAnimation.dropIn),
              const SizedBox(height: 20),
              const Text('TrueLove', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 10),
              const Text('Find your perfect connection', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 50),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const GuidelinesScreen()));
                  },
                  child: const Text('Register Free', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen(register: false)));
                  },
                  child: const Text('Login', style: TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final bool register;
  const AuthScreen({super.key, required this.register});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Register flow has 5 pages (index 0..4). Last page index = lastStep.
  static const int lastStep = 4;

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final PageController pageCtrl = PageController();
  int currentStep = 0;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController occupationController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController stateController = TextEditingController();
  final TextEditingController countryController = TextEditingController(text: 'India');
  final TextEditingController aboutController = TextEditingController();
  final TextEditingController interestsController = TextEditingController();

  bool isEmail = true;
  bool loading = false;
  bool otpSent = false;
  bool showPassword = false; // toggles the eye icon on password fields

  String? lookingFor;
  String? gender;
  String relationshipStatus = 'Single';
  String? religion;
  String? motherTongue;
  String? education;
  String? employedIn;
  String? diet;
  int? heightCm;

  DateTime? selectedDob;
  String verificationId = '';

  @override
  void dispose() {
    pageCtrl.dispose();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    nameController.dispose();
    occupationController.dispose();
    cityController.dispose();
    stateController.dispose();
    countryController.dispose();
    aboutController.dispose();
    interestsController.dispose();
    super.dispose();
  }

  Widget passwordField() {
    return TextField(
      controller: passwordController,
      obscureText: !showPassword,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Password',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          tooltip: showPassword ? 'Hide password' : 'Show password',
          icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => showPassword = !showPassword),
        ),
      ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> selectDob() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => selectedDob = picked);
  }

  bool isAdult() {
    if (selectedDob == null) return false;
    final now = DateTime.now();
    int age = now.year - selectedDob!.year;
    if (now.month < selectedDob!.month || (now.month == selectedDob!.month && now.day < selectedDob!.day)) {
      age--;
    }
    return age >= 18;
  }

  // ---------- Validation (one per step) ----------
  bool validateStep1() {
    if (isEmail) {
      final email = emailController.text.trim();
      if (email.isEmpty || passwordController.text.trim().isEmpty) {
        showMessage('Please enter email and password.');
        return false;
      }
      if (!email.contains('@') || !email.contains('.')) {
        showMessage('Please enter a valid email address.');
        return false;
      }
      if (passwordController.text.trim().length < 6) {
        showMessage('Password must contain at least 6 characters.');
        return false;
      }
    } else {
      if (phoneController.text.trim().length != 10) {
        showMessage('Enter a valid 10-digit mobile number.');
        return false;
      }
    }
    return true;
  }

  bool validateStep2() {
    if (nameController.text.trim().isEmpty) {
      showMessage('Please enter your name.');
      return false;
    }
    if (selectedDob == null) {
      showMessage('Please select your date of birth.');
      return false;
    }
    if (!isAdult()) {
      showMessage('You must be at least 18 years old to register.');
      return false;
    }
    if (gender == null) {
      showMessage('Please select your gender.');
      return false;
    }
    if (lookingFor == null) {
      showMessage('Please select what you are looking for.');
      return false;
    }
    return true;
  }

  bool validateStep3() {
    if (religion == null) {
      showMessage('Please select religion.');
      return false;
    }
    if (motherTongue == null) {
      showMessage('Please select mother tongue.');
      return false;
    }
    return true;
  }

  bool validateStep4() {
    if (education == null) {
      showMessage('Please select highest education.');
      return false;
    }
    if (employedIn == null) {
      showMessage('Please select what you are working in.');
      return false;
    }
    return true;
  }

  bool validateStep5() {
    if (heightCm == null) {
      showMessage('Please select height.');
      return false;
    }
    if (cityController.text.trim().isEmpty) {
      showMessage('Please enter your city.');
      return false;
    }
    return true;
  }

  void nextStep() {
    final validators = [validateStep1, validateStep2, validateStep3, validateStep4, validateStep5];
    if (!validators[currentStep]()) return;
    if (currentStep < lastStep) {
      setState(() => currentStep++);
      pageCtrl.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      submitRegistration();
    }
  }

  void prevStep() {
    if (currentStep > 0) {
      setState(() => currentStep--);
      pageCtrl.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Everything the user typed during registration.
  /// These exact keys are what the profile screen should read.
  Map<String, dynamic> buildProfileData() {
    final city = cityController.text.trim();
    return {
      'name': nameController.text.trim(),
      'dob': Timestamp.fromDate(selectedDob!),
      'gender': gender,
      'relationshipStatus': relationshipStatus,
      'lookingFor': lookingFor,
      'religion': religion,
      'motherTongue': motherTongue,
      'education': education,
      'employedIn': employedIn,
      'occupation': occupationController.text.trim(),
      'heightCm': heightCm,
      'height': heightCm == null ? '' : heightLabel(heightCm!),
      'diet': diet ?? '',
      'location': city, // kept for existing screens
      'city': city,
      'state': stateController.text.trim(),
      'country': countryController.text.trim(),
      'bio': aboutController.text.trim(),
      'interests': interestsController.text.trim().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'registrationDetailsDone': true,
    };
  }

  Future<void> openNextScreen(User user) async {
    final userRef = firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    final existing = userDoc.data();

    final base = {
      'email': user.email ?? '',
      'phoneNumber': user.phoneNumber ?? '',
    };

    if (!userDoc.exists) {
      await userRef.set({
        ...base,
        // Only save registration details when coming from the Register flow
        // (login has no form data - this used to crash on selectedDob!).
        if (widget.register) ...buildProfileData(),
        'createdAt': FieldValue.serverTimestamp(),
        'isBanned': false,
        'profileComplete': false,
      });
    } else if (widget.register && existing?['profileComplete'] != true) {
      // Doc already existed (e.g. created before details were saved):
      // merge the registration details instead of silently dropping them.
      await userRef.set({...base, ...buildProfileData()}, SetOptions(merge: true));
    } else {
      await userRef.set(base, SetOptions(merge: true));
    }

    final updatedDoc = await userRef.get();
    final data = updatedDoc.data();
    if (!mounted) return;

    if (data?['isBanned'] == true) {
      await auth.signOut();
      showMessage('Your account has been disabled.');
      return;
    }

    final bool profileComplete = data?['profileComplete'] == true;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => profileComplete ? const MainShell() : const ProfileSetupScreen()),
      (route) => false,
    );
  }

  Future<void> submitRegistration() async {
    if (!validateStep5()) return;

    // Phone: OTP flow manages its own loading state.
    if (!isEmail) {
      await sendPhoneOtp();
      return;
    }

    setState(() => loading = true);
    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      await openNextScreen(credential.user!);
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Registration failed.');
    } catch (e) {
      showMessage('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// "Forgot password?" - asks for the email and sends Firebase's password-reset link.
  Future<void> forgotPassword() async {
    final ctrl = TextEditingController(text: emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter your registered email. We'll send you a link to set a new password."),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, ctrl.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );

    if (email == null) return; // cancelled
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      showMessage('Please enter a valid email address.');
      return;
    }

    setState(() => loading = true);
    try {
      await auth.sendPasswordResetEmail(email: email);
      showMessage('Password reset link sent to $email. Check your inbox (and spam folder).');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        showMessage('No account found with this email.');
      } else if (e.code == 'invalid-email') {
        showMessage('Please enter a valid email address.');
      } else if (e.code == 'too-many-requests') {
        showMessage('Too many attempts. Please try again after some time.');
      } else {
        showMessage(e.message ?? 'Could not send reset email.');
      }
    } catch (e) {
      showMessage('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loginWithEmail() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      showMessage('Please enter email and password.');
      return;
    }
    setState(() => loading = true);
    try {
      final credential = await auth.signInWithEmailAndPassword(email: email, password: password);
      await openNextScreen(credential.user!);
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Login failed.');
    } catch (e) {
      showMessage('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendPhoneOtp() async {
    final phone = phoneController.text.trim();
    setState(() => loading = true);
    try {
      await auth.verifyPhoneNumber(
        phoneNumber: '+91$phone',
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final result = await auth.signInWithCredential(credential);
            if (result.user != null) await openNextScreen(result.user!);
          } catch (e) {
            showMessage('Phone verification failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          showMessage(e.message ?? 'OTP verification failed.');
          if (mounted) setState(() => loading = false);
        },
        codeSent: (String id, int? resendToken) {
          if (!mounted) return;
          setState(() {
            verificationId = id;
            otpSent = true;
            loading = false;
            currentStep = lastStep; // reuse last page as OTP entry
          });
          pageCtrl.jumpToPage(lastStep);
          showMessage('OTP sent successfully.');
        },
        codeAutoRetrievalTimeout: (String id) {
          verificationId = id;
        },
      );
    } catch (e) {
      showMessage('Unable to send OTP: $e');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifyPhoneOtp() async {
    final otp = otpController.text.trim();
    if (otp.isEmpty || verificationId.isEmpty) {
      showMessage('Please enter the OTP.');
      return;
    }
    setState(() => loading = true);
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otp);
      final result = await auth.signInWithCredential(credential);
      if (result.user != null) await openNextScreen(result.user!);
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Invalid OTP.');
    } catch (e) {
      showMessage('Verification failed: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ---------- Non-register (login) layout — unchanged, single form ----------
  Widget loginLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 15),
          const AnimatedHeart(size: 55, animation: HeartAnimation.jump),
          const SizedBox(height: 20),
          const Text('Welcome back', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 25),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Email'), icon: Icon(Icons.email)),
              ButtonSegment(value: false, label: Text('Mobile'), icon: Icon(Icons.phone_android)),
            ],
            selected: {isEmail},
            onSelectionChanged: (value) {
              setState(() {
                isEmail = value.first;
                otpSent = false;
              });
            },
          ),
          const SizedBox(height: 25),
          if (isEmail) ...[
            TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 15),
            passwordField(),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: loading ? null : forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: loading ? null : loginWithEmail,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
              child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Login'),
            ),
          ] else ...[
            TextField(controller: phoneController, keyboardType: TextInputType.phone, maxLength: 10,
                decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
            if (otpSent) ...[
              const SizedBox(height: 15),
              TextField(controller: otpController, keyboardType: TextInputType.number, maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Enter OTP', border: OutlineInputBorder(), prefixIcon: Icon(Icons.password))),
            ],
            const SizedBox(height: 25),
            ElevatedButton(
              onPressed: loading ? null : otpSent ? verifyPhoneOtp : sendPhoneOtp,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
              child: loading ? const CircularProgressIndicator(color: Colors.white) : Text(otpSent ? 'Verify OTP' : 'Send OTP'),
            ),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GuidelinesScreen()));
            },
            child: const Text('New user? Register Free'),
          ),
        ],
      ),
    );
  }

  // ---------- Register layout — 5-step design ----------
  Widget stepDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(lastStep + 1, (i) {
        final active = i <= currentStep;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Colors.red : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget stepCard({required String title, required String subtitle, required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    );
  }

  // Small helpers so each step stays short.
  Widget dropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), prefixIcon: Icon(icon)),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget textField(TextEditingController c, String label, IconData icon, {int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), prefixIcon: Icon(icon)),
      ),
    );
  }

  // Step 1 – account
  Widget step1() {
    return stepCard(
      title: "Create your account",
      subtitle: "Step 1 of 5 — how you'll sign in",
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Email'), icon: Icon(Icons.email)),
            ButtonSegment(value: false, label: Text('Mobile'), icon: Icon(Icons.phone_android)),
          ],
          selected: {isEmail},
          onSelectionChanged: (value) => setState(() => isEmail = value.first),
        ),
        const SizedBox(height: 20),
        if (isEmail) ...[
          TextField(controller: emailController, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
          const SizedBox(height: 15),
          passwordField(),
        ] else
          TextField(controller: phoneController, keyboardType: TextInputType.phone, maxLength: 10,
              decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 ', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
      ],
    );
  }

  // Step 2 – basic details
  Widget step2() {
    return stepCard(
      title: "Basic details",
      subtitle: "Step 2 of 5 — tell us about yourself",
      children: [
        textField(nameController, 'Full name', Icons.person),
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: OutlinedButton.icon(
            onPressed: selectDob,
            icon: const Icon(Icons.calendar_month),
            label: Text(selectedDob == null ? 'Select date of birth' : '${selectedDob!.day}/${selectedDob!.month}/${selectedDob!.year}'),
          ),
        ),
        dropdown(label: 'Gender', icon: Icons.wc, value: gender, items: List<String>.from(kGenders),
            onChanged: (v) => setState(() => gender = v)),
        dropdown(label: 'Relationship status', icon: Icons.favorite_border, value: relationshipStatus, items: kRelationshipOptions,
            onChanged: (v) => setState(() => relationshipStatus = v ?? 'Single')),
        dropdown(label: "I'm looking for", icon: Icons.favorite, value: lookingFor, items: kLookingForOptions,
            onChanged: (v) => setState(() => lookingFor = v)),
      ],
    );
  }

  // Step 3 – religion & mother tongue
  Widget step3() {
    return stepCard(
      title: "Background",
      subtitle: "Step 3 of 5 — helps find people you click with",
      children: [
        dropdown(label: 'Religion', icon: Icons.temple_hindu_outlined, value: religion, items: kReligionOptions,
            onChanged: (v) => setState(() => religion = v)),
        dropdown(label: 'Mother tongue', icon: Icons.translate, value: motherTongue, items: kMotherTongueOptions,
            onChanged: (v) => setState(() => motherTongue = v)),
      ],
    );
  }

  // Step 4 – education & career
  Widget step4() {
    return stepCard(
      title: "Education & career",
      subtitle: "Step 4 of 5 — what you do",
      children: [
        dropdown(label: 'Highest education', icon: Icons.school_outlined, value: education, items: kEducationOptions,
            onChanged: (v) => setState(() => education = v)),
        dropdown(label: 'Working in', icon: Icons.business_center_outlined, value: employedIn, items: kEmployedInOptions,
            onChanged: (v) => setState(() => employedIn = v)),
        textField(occupationController, 'Occupation / Profession', Icons.work_outline, hint: 'e.g. Software engineer, Doctor'),
      ],
    );
  }

  // Step 5 – personal details & location (or OTP page for phone sign-up)
  Widget step5() {
    if (!isEmail && otpSent) {
      return stepCard(
        title: "Verify your number",
        subtitle: "Enter the OTP sent to +91 ${phoneController.text}",
        children: [
          TextField(controller: otpController, keyboardType: TextInputType.number, maxLength: 6,
              decoration: const InputDecoration(labelText: 'Enter OTP', border: OutlineInputBorder(), prefixIcon: Icon(Icons.password))),
        ],
      );
    }
    return stepCard(
      title: "Personal details & location",
      subtitle: "Step 5 of 5 — almost done",
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 15),
          child: DropdownButtonFormField<int>(
            value: heightCm,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Height', border: OutlineInputBorder(), prefixIcon: Icon(Icons.height)),
            items: kHeightsCm.map((cm) => DropdownMenuItem(value: cm, child: Text(heightLabel(cm)))).toList(),
            onChanged: (v) => setState(() => heightCm = v),
          ),
        ),
        dropdown(label: 'Diet (optional)', icon: Icons.restaurant_outlined, value: diet, items: kDietOptions,
            onChanged: (v) => setState(() => diet = v)),
        textField(cityController, 'City', Icons.location_city_outlined),
        textField(stateController, 'State', Icons.map_outlined),
        textField(countryController, 'Country', Icons.public),
        textField(aboutController, 'About yourself', Icons.info_outline, maxLines: 3),
        textField(interestsController, 'Interests (comma separated)', Icons.interests_outlined, hint: 'e.g. travel, books, music'),
      ],
    );
  }

  Widget registerLayout() {
    return Column(
      children: [
        const SizedBox(height: 10),
        stepDots(),
        const SizedBox(height: 6),
        Expanded(
          child: PageView(
            controller: pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [step1(), step2(), step3(), step4(), step5()],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              if (currentStep > 0 && !(!isEmail && otpSent))
                Expanded(
                  child: OutlinedButton(onPressed: loading ? null : prevStep, child: const Text("Back")),
                ),
              if (currentStep > 0 && !(!isEmail && otpSent)) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
                  onPressed: loading
                      ? null
                      : (!isEmail && otpSent)
                          ? verifyPhoneOtp
                          : currentStep < lastStep
                              ? nextStep
                              : submitRegistration,
                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text((!isEmail && otpSent) ? "Verify OTP" : currentStep < lastStep ? "Continue" : "Finish"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.register ? 'Register' : 'Login')),
      body: SafeArea(child: widget.register ? registerLayout() : loginLayout()),
    );
  }
}