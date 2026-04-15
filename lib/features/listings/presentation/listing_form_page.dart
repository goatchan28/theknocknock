import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/media/image_pick_and_crop.dart';
import '../../../models/listing.dart';
import '../../../providers/auth_controller.dart';
import '../../../services/listing_service.dart';
import 'create_listing_flow_result.dart';
import 'listing_detail_page.dart';

class ListingFormPage extends StatefulWidget {
  const ListingFormPage.create({
    super.key,
    this.embedded = false,
    this.showEmbeddedHeader = true,
    this.prefillListing,
    this.closeOnDoneAfterPost = false,
  }) : listing = null;

  const ListingFormPage.edit({
    super.key,
    required this.listing,
  })  : embedded = false,
        showEmbeddedHeader = false,
        prefillListing = null,
        closeOnDoneAfterPost = false;

  final Listing? listing;
  final bool embedded;
  final bool showEmbeddedHeader;
  final Listing? prefillListing;
  final bool closeOnDoneAfterPost;

  bool get isEdit => listing != null;

  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  static const _categories = <String>[
    'Dorm Essentials',
    'Outdoors',
    'Sports',
    'Kitchen',
    'Clothing',
    'Electronics',
    'School Supplies',
    'Other',
  ];

  static const _urgentOptions = <_UrgentOption>[
    _UrgentOption(label: '15 min', duration: Duration(minutes: 15)),
    _UrgentOption(label: '30 min', duration: Duration(minutes: 30)),
    _UrgentOption(label: '1 hour', duration: Duration(hours: 1)),
    _UrgentOption(label: '6 hours', duration: Duration(hours: 6)),
    _UrgentOption(label: '24 hours', duration: Duration(hours: 24)),
  ];

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();

  String _category = _categories.first;
  ListingType _type = ListingType.lend;
  bool _isUrgent = false;
  Duration _urgentDuration = const Duration(hours: 1);
  XFile? _newImage;
  String? _existingImageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final listing = widget.listing ?? widget.prefillListing;
    if (listing == null) {
      return;
    }

    _titleController.text = listing.title;
    _descriptionController.text = listing.description;
    _category = listing.category.trim().isEmpty ? _categories.first : listing.category;
    if (!_categories.contains(_category)) {
      _category = 'Other';
    }

    _type = listing.type;
    _existingImageUrl = listing.imageUrl;
    if (listing.isUrgent) {
      _isUrgent = true;
      if (listing.urgentUntil != null) {
        _urgentDuration = _closestDurationTo(
          listing.urgentUntil!.difference(DateTime.now()),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final image = await pickAndCropImage(
        context: context,
        imagePicker: _imagePicker,
        cropTitle: 'Crop listing photo',
        circleUi: false,
        aspectRatio: 1,
        maxWidth: 1400,
        imageQuality: 85,
      );

      if (!mounted || image == null) {
        return;
      }

      setState(() {
        _newImage = image;
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }
      _showMessage('Photo picker is unavailable right now. Please rebuild and retry.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not open photo picker: $error');
    }
  }

  Duration _closestDurationTo(Duration value) {
    if (value <= Duration.zero) {
      return _urgentOptions.first.duration;
    }

    var closest = _urgentOptions.first.duration;
    for (final option in _urgentOptions) {
      if (option.duration >= value) {
        return option.duration;
      }
      closest = option.duration;
    }
    return closest;
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }

    FocusScope.of(context).unfocus();

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Item name is required.');
      return;
    }

    final auth = context.read<AuthController>();
    final user = auth.firebaseUser;
    if (user == null) {
      _showMessage('Session expired. Please sign in again.');
      return;
    }
    final urgentAlertsEnabled = auth.profile?.urgentAlertsEnabled ?? false;

    final ownerDisplayName =
        auth.profile?.displayName?.trim().isNotEmpty == true
            ? auth.profile!.displayName!.trim()
            : (user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'Columbia Student');

    setState(() {
      _saving = true;
    });

    final listingService = context.read<ListingService>();

    try {
      if (widget.isEdit) {
        await listingService.updateListing(
          listingId: widget.listing!.id,
          ownerId: user.uid,
          ownerDisplayName: ownerDisplayName,
          ownerPhotoUrl: auth.profile?.photoUrl ?? user.photoURL,
          title: title,
          description: _descriptionController.text.trim(),
          category: _category,
          type: _type,
          urgentDuration: _type == ListingType.borrow &&
                  _isUrgent &&
                  urgentAlertsEnabled
              ? _urgentDuration
              : null,
          image: _newImage,
        );

        if (!mounted) {
          return;
        }

        Navigator.of(context).pop(true);
        _showMessage('Listing updated.');
        return;
      }

      final listingId = await listingService.createListing(
        ownerId: user.uid,
        ownerDisplayName: ownerDisplayName,
        ownerPhotoUrl: auth.profile?.photoUrl ?? user.photoURL,
        title: title,
        description: _descriptionController.text.trim(),
        category: _category,
        type: _type,
        existingImageUrl: _existingImageUrl,
        urgentDuration: _type == ListingType.borrow &&
                _isUrgent &&
                urgentAlertsEnabled
            ? _urgentDuration
            : null,
        image: _newImage,
      );

      if (!mounted) {
        return;
      }

      final shouldViewListing =
          await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ListingPostedPage(
            listingId: listingId,
            listingTitle: title,
          ),
        ),
      ) ??
          false;

      if (!mounted) {
        return;
      }

      if (widget.embedded) {
        Navigator.of(context).pop(
          shouldViewListing
              ? CreateListingFlowResult.viewListing(listingId)
              : const CreateListingFlowResult.done(),
        );
        return;
      }

      if (shouldViewListing) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ListingDetailPage(listingId: listingId),
          ),
        );
        return;
      }

      if (widget.closeOnDoneAfterPost) {
        Navigator.of(context).pop(true);
        return;
      }

      _resetForm();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Could not save listing: $error');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _resetForm() {
    _titleController.clear();
    _descriptionController.clear();

    setState(() {
      _newImage = null;
      _existingImageUrl = null;
      _category = _categories.first;
      _type = ListingType.lend;
      _isUrgent = false;
      _urgentDuration = const Duration(hours: 1);
    });
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final prefill = widget.prefillListing;
    final urgentAlertsEnabled =
        context.watch<AuthController>().profile?.urgentAlertsEnabled ?? false;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final content = ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
          if (widget.embedded && !widget.isEdit && widget.showEmbeddedHeader) ...[
            Text(
              'Create Listing',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const Text('Post something to lend or request to borrow.'),
            const SizedBox(height: 16),
          ],
          _ListingPhotoPicker(
            imageUrl: _existingImageUrl ?? listing?.imageUrl ?? prefill?.imageUrl,
            selectedFile: _newImage,
            onPick: _saving ? null : _pickImage,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleController,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Item name *',
              hintText: 'What are you lending or borrowing?',
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descriptionController,
            enabled: !_saving,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'Add useful details for other students.',
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: _categories
                .map((category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ))
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _category = value;
                    });
                  },
          ),
          const SizedBox(height: 14),
          Text('Listing type', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ListingType>(
            segments: const [
              ButtonSegment(
                value: ListingType.lend,
                icon: Icon(Icons.volunteer_activism_outlined),
                label: Text('Lend'),
              ),
              ButtonSegment(
                value: ListingType.borrow,
                icon: Icon(Icons.shopping_bag_outlined),
                label: Text('Borrow'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: _saving
                ? null
                : (selection) {
                    final selectedType = selection.first;
                    setState(() {
                      _type = selectedType;
                      if (_type == ListingType.lend) {
                        _isUrgent = false;
                      }
                    });
                  },
          ),
          if (_type == ListingType.borrow) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              value: urgentAlertsEnabled ? _isUrgent : false,
              onChanged: _saving || !urgentAlertsEnabled
                  ? null
                  : (value) {
                      setState(() {
                        _isUrgent = value;
                      });
                    },
              title: const Text('Mark as urgent'),
              subtitle: Text(
                urgentAlertsEnabled
                    ? 'Show this request as urgent for a limited time.'
                    : 'Enable urgent alerts in Settings to post urgent requests.',
              ),
            ),
            if (_isUrgent && urgentAlertsEnabled) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _urgentOptions.map((option) {
                  return ChoiceChip(
                    label: Text(option.label),
                    selected: _urgentDuration == option.duration,
                    onSelected: _saving
                        ? null
                        : (selected) {
                            if (!selected) {
                              return;
                            }
                            setState(() {
                              _urgentDuration = option.duration;
                            });
                          },
                  );
                }).toList(),
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(widget.isEdit ? Icons.save_outlined : Icons.check_circle_outline),
            label: Text(widget.isEdit ? 'Save changes' : 'Post listing'),
          ),
        ],
      );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEdit
              ? 'Edit Listing'
              : (widget.prefillListing != null ? 'Relist Item' : 'Create Listing'),
        ),
      ),
      body: content,
    );
  }
}

class ListingPostedPage extends StatelessWidget {
  const ListingPostedPage({
    super.key,
    required this.listingId,
    required this.listingTitle,
  });

  final String listingId;
  final String listingTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listing Posted')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.check_circle,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Your listing is live',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                listingTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View listing'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingPhotoPicker extends StatelessWidget {
  const _ListingPhotoPicker({
    required this.imageUrl,
    required this.selectedFile,
    required this.onPick,
  });

  final String? imageUrl;
  final XFile? selectedFile;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    Widget imageChild;
    if (selectedFile != null) {
      imageChild = Image.file(
        File(selectedFile!.path),
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      imageChild = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else {
      imageChild = Container(
        color: Theme.of(context).colorScheme.surfaceVariant,
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, size: 40),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: imageChild,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onPick,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(selectedFile == null && (imageUrl == null || imageUrl!.isEmpty)
              ? 'Add photo'
              : 'Replace photo'),
        ),
      ],
    );
  }
}

class _UrgentOption {
  const _UrgentOption({required this.label, required this.duration});

  final String label;
  final Duration duration;
}
