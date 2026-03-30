import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/media/image_pick_and_crop.dart';
import '../../../core/input_formatters/us_phone_input_formatter.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/onboarding_service.dart';
import '../../../services/user_service.dart';

class OnboardingFlowPage extends StatefulWidget {
  const OnboardingFlowPage({super.key});

  @override
  State<OnboardingFlowPage> createState() => _OnboardingFlowPageState();
}

class _OnboardingFlowPageState extends State<OnboardingFlowPage> {
  static const _interestOptions = <String>[
    'Dorm Essentials',
    'Outdoors',
    'Sports',
    'Kitchen',
    'Clothing',
    'Electronics',
    'School Supplies',
    'Other',
  ];

  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _imagePicker = ImagePicker();

  int _stepIndex = 0;
  bool _submitting = false;
  XFile? _selectedProfileImage;
  final Set<String> _selectedInterests = <String>{};
  bool _notificationsEnabled = true;
  bool _urgentAlertsEnabled = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _validatePhone() {
    final valid = UsPhoneInputFormatter.isValid(_phoneController.text);
    if (!valid) {
      _showMessage('Enter a valid 10-digit phone number.');
      return false;
    }
    return true;
  }

  Future<void> _pickImage() async {
    try {
      final image = await pickAndCropImage(
        context: context,
        imagePicker: _imagePicker,
        cropTitle: 'Crop profile photo',
        circleUi: true,
        aspectRatio: 1,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (!mounted || image == null) {
        return;
      }

      setState(() {
        _selectedProfileImage = image;
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      _showMessage(
        'Photo picker is unavailable right now. Please restart the app build.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not open photo picker: $error');
    }
  }

  void _goBack() {
    if (_submitting || _stepIndex == 0) {
      return;
    }
    setState(() {
      _stepIndex -= 1;
    });
  }

  Future<void> _next() async {
    if (_submitting) {
      return;
    }

    if (_stepIndex == 0 && !_validatePhone()) {
      return;
    }

    if (_stepIndex < 3) {
      setState(() {
        _stepIndex += 1;
      });
      return;
    }

    await _completeOnboarding();
  }

  void _skipOptionalStep() {
    if (_submitting || _stepIndex == 0 || _stepIndex == 3) {
      return;
    }
    setState(() {
      _stepIndex += 1;
    });
  }

  Future<void> _completeOnboarding() async {
    final auth = context.read<AuthController>();
    final user = auth.firebaseUser;

    if (user == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      String? photoUrl;
      if (_selectedProfileImage != null) {
        photoUrl = await context.read<OnboardingService>().uploadProfilePhoto(
              uid: user.uid,
              image: _selectedProfileImage!,
            );
        await user.updatePhotoURL(photoUrl);
        await user.reload();
      }

      final normalizedPhone =
          UsPhoneInputFormatter.normalizeForStorage(_phoneController.text);

      await context.read<UserService>().completeOnboarding(
            uid: user.uid,
            phoneNumber: normalizedPhone,
            interests: _selectedInterests.toList()..sort(),
            notificationsEnabled: _notificationsEnabled,
            urgentAlertsEnabled: _urgentAlertsEnabled,
            photoUrl: photoUrl,
          );

      if (!mounted) {
        return;
      }

      _showMessage('Onboarding complete. Welcome to Knocknock.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not complete onboarding: $error');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Your Account'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: (_stepIndex + 1) / 4),
              const SizedBox(height: 12),
              Text(
                'Step ${_stepIndex + 1} of 4',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _buildStep(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_stepIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _goBack,
                        child: const Text('Back'),
                      ),
                    ),
                  if (_stepIndex > 0) const SizedBox(width: 12),
                  if (_stepIndex == 1 || _stepIndex == 2)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : _skipOptionalStep,
                        child: const Text('Skip'),
                      ),
                    ),
                  if (_stepIndex == 1 || _stepIndex == 2)
                    const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _next,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_stepIndex == 3 ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_stepIndex) {
      case 0:
        return _buildPhoneStep(context);
      case 1:
        return _buildProfilePhotoStep(context);
      case 2:
        return _buildInterestsStep(context);
      case 3:
        return _buildNotificationStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPhoneStep(BuildContext context) {
    return Column(
      key: const ValueKey('phone-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Contact Number',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Required. We need this because this is how you will contact other users when matched.',
        ),
        const SizedBox(height: 16),
        AutofillGroup(
          child: TextFormField(
            controller: _phoneController,
            focusNode: _phoneFocusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: const [UsPhoneInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '(917) 555-1234',
              helperText: 'Tip: tap the number suggestion above your keyboard.',
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _phoneFocusNode.requestFocus(),
            icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
            label: const Text('Use iPhone autofill'),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePhotoStep(BuildContext context) {
    return Column(
      key: const ValueKey('photo-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Profile Picture',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Optional. Add now or skip and set it later.'),
        const SizedBox(height: 20),
        Center(
          child: CircleAvatar(
            radius: 52,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            backgroundImage: _selectedProfileImage != null
                ? FileImage(File(_selectedProfileImage!.path))
                : null,
            child: _selectedProfileImage == null
                ? const Icon(Icons.person_outline, size: 42)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _submitting ? null : _pickImage,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(_selectedProfileImage == null ? 'Choose photo' : 'Replace photo'),
        ),
      ],
    );
  }

  Widget _buildInterestsStep(BuildContext context) {
    return Column(
      key: const ValueKey('interests-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Categories You Like',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Optional. We will use this to improve your feed.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _interestOptions.map((interest) {
            final isSelected = _selectedInterests.contains(interest);
            return FilterChip(
              label: Text(interest),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedInterests.add(interest);
                  } else {
                    _selectedInterests.remove(interest);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNotificationStep(BuildContext context) {
    return Column(
      key: const ValueKey('notifications-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Alert Preferences',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Choose your default notifications. You can change later.'),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Enable notifications'),
          value: _notificationsEnabled,
          onChanged: (value) {
            setState(() {
              _notificationsEnabled = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text('Enable urgent alerts'),
          value: _urgentAlertsEnabled,
          onChanged: (value) {
            setState(() {
              _urgentAlertsEnabled = value;
            });
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Turn this on if you want to post urgent alerts when you need something urgently. '
            'If enabled, you will also receive notifications when other people post urgent alerts.',
          ),
        ),
      ],
    );
  }
}
