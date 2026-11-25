import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Picks a photo and returns its bytes, or null when nothing was picked.
/// Tests pass their own instead of opening the photo picker.
typedef PickPicture = Future<Uint8List?> Function({required bool wallpaper});

/// The biggest picture the PC keeps, like ImageStore.MaxBytes there.
const maxPictureBytes = 700 * 1024;

/// Picks a photo from the phone. The phone's own picker shrinks and
/// compresses it: a button picture to 512 pixels, a wallpaper to 1600.
Future<Uint8List?> pickFromGallery({required bool wallpaper}) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: wallpaper ? 1600 : 512,
    maxHeight: wallpaper ? 1600 : 512,
    imageQuality: wallpaper ? 75 : 85,
  );
  return file?.readAsBytes();
}
