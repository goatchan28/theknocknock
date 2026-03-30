import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<XFile?> pickAndCropImage({
  required BuildContext context,
  required ImagePicker imagePicker,
  required String cropTitle,
  bool circleUi = false,
  double? aspectRatio,
  int maxWidth = 1400,
  int imageQuality = 88,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
        ],
      ),
    ),
  );

  if (source == null) {
    return null;
  }

  final pickedImage = await imagePicker.pickImage(
    source: source,
    maxWidth: maxWidth.toDouble(),
    imageQuality: imageQuality,
  );
  if (pickedImage == null) {
    return null;
  }

  final bytes = await pickedImage.readAsBytes();
  if (!context.mounted) {
    return null;
  }

  final croppedBytes = await Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => _ImageCropPage(
        title: cropTitle,
        imageBytes: bytes,
        circleUi: circleUi,
        aspectRatio: aspectRatio,
      ),
      fullscreenDialog: true,
    ),
  );

  if (croppedBytes == null || croppedBytes.isEmpty) {
    return null;
  }

  final tempFile = File(
    '${Directory.systemTemp.path}/knocknock_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await tempFile.writeAsBytes(croppedBytes, flush: true);
  return XFile(tempFile.path);
}

class _ImageCropPage extends StatefulWidget {
  const _ImageCropPage({
    required this.title,
    required this.imageBytes,
    required this.circleUi,
    required this.aspectRatio,
  });

  final String title;
  final Uint8List imageBytes;
  final bool circleUi;
  final double? aspectRatio;

  @override
  State<_ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<_ImageCropPage> {
  final CropController _cropController = CropController();
  bool _cropping = false;

  void _onCropPressed() {
    if (_cropping) {
      return;
    }
    setState(() {
      _cropping = true;
    });
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _cropping ? null : _onCropPressed,
            child: Text(_cropping ? 'Cropping...' : 'Use photo'),
          ),
        ],
      ),
      body: Crop(
        image: widget.imageBytes,
        controller: _cropController,
        withCircleUi: widget.circleUi,
        aspectRatio: widget.aspectRatio,
        interactive: true,
        onCropped: (result) {
          if (!mounted) {
            return;
          }
          if (result is CropSuccess) {
            Navigator.of(context).pop(result.croppedImage);
            return;
          }

          if (result is CropFailure) {
            setState(() {
              _cropping = false;
            });
            final messenger = ScaffoldMessenger.of(context);
            messenger.clearSnackBars();
            messenger.showSnackBar(
              SnackBar(content: Text('Could not crop image: ${result.cause}')),
            );
            return;
          }
        },
      ),
    );
  }
}
