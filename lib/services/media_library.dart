import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Folders inside the app's own media directory.
enum MediaAlbum {
  snaps('Snaps', 'IMG'),
  videos('Videos', 'VID'),
  boomerang('Boomerang', 'BOOM'),
  wallpapers('Wallpapers', 'WALL'),
  auraResults('Aura Results', 'AURA');

  const MediaAlbum(this.folder, this.filePrefix);

  final String folder;
  final String filePrefix;

  /// Album path relative to the standard Pictures folder.
  String get album => '${MediaLibrary.rootFolder}/$folder';
}

/// Saves everything the app captures into one AURA directory on the device,
/// split by category:
///
///   Pictures/AURA/Snaps        photos
///   Pictures/AURA/Videos       videos
///   Pictures/AURA/Boomerang    boomerangs
///   Pictures/AURA/Wallpapers   photos framed for laptop/desktop screens
///   Pictures/AURA/Aura Results Aura Calc photos and result cards
///
/// Files go through Android's MediaStore, so they also appear in the Gallery
/// (as albums), and are named like native camera files, e.g.
/// AURA_IMG_20260924_194812_123.jpg. (Android only lets apps create media
/// folders inside a standard folder such as Pictures; a folder at the very
/// top of storage would need the restricted "All files access" permission.)
class MediaLibrary {
  static const String rootFolder = 'AURA';

  static bool _accessChecked = false;

  /// Returns the (renamed) local file that was saved.
  static Future<String> saveImage(String path, MediaAlbum album, {bool keepSource = false}) async {
    await _ensureAccess();
    final named = await _named(path, album, keepSource: keepSource);
    await Gal.putImage(named, album: album.album);
    return named;
  }

  static Future<void> saveImageBytes(Uint8List bytes, MediaAlbum album) async {
    await _ensureAccess();
    await Gal.putImageBytes(bytes, album: album.album, name: _fileStem(album));
  }

  static Future<void> saveVideo(String path, MediaAlbum album, {bool keepSource = false}) async {
    await _ensureAccess();
    final named = await _named(path, album, keepSource: keepSource);
    await Gal.putVideo(named, album: album.album);
  }

  /// Saving into an album needs storage permission on Android 9/10 only.
  static Future<void> _ensureAccess() async {
    if (_accessChecked) return;
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
    } catch (e) {
      debugPrint('MediaLibrary: access check failed: $e');
    }
    _accessChecked = true;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _fileStem(MediaAlbum album) {
    final now = DateTime.now();
    final date = '${now.year}${_two(now.month)}${_two(now.day)}';
    final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final ms = now.millisecond.toString().padLeft(3, '0');
    return 'AURA_${album.filePrefix}_${date}_${time}_$ms';
  }

  /// The gallery keeps the source file's name, so give it a proper one first.
  /// Moves the temp file, or copies it when the app still shows the source.
  static Future<String> _named(String path, MediaAlbum album, {bool keepSource = false}) async {
    final int dot = path.lastIndexOf('.');
    final String extension = dot > path.lastIndexOf('/') ? path.substring(dot) : '';
    final String target = '${(await getTemporaryDirectory()).path}/${_fileStem(album)}$extension';
    try {
      if (!keepSource) return (await File(path).rename(target)).path;
    } catch (_) {
      // Different volume or file in use: fall back to copying
    }
    try {
      return (await File(path).copy(target)).path;
    } catch (e) {
      debugPrint('MediaLibrary: could not name $path: $e');
      return path;
    }
  }
}
