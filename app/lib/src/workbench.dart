import 'dart:convert';
import 'dart:io';

import 'package:can_link/can_link.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ai_prompt.dart';
import 'recorder.dart';

/// Etwas zum Teilen: eine vorhandene Datei oder Text, der als Datei
/// verschickt wird.
class ShareItem {
  const ShareItem.file(this.name, String this.path) : text = null;
  const ShareItem.text(this.name, String this.text) : path = null;

  final String name;
  final String? path;
  final String? text;
}

typedef ShareFiles = Future<void> Function(List<ShareItem> items);

/// Lässt den Nutzer eine Textdatei wählen; null bei Abbruch.
typedef PickText = Future<String?> Function();

/// Arbeitsstand der Werkbank: das Profil, die angepinnten Signale und die
/// Mitschnitte. Mit [directory] wird alles im App-Ordner gesichert, ohne
/// (Tests) bleibt es im Speicher.
class Workbench extends ChangeNotifier {
  Workbench({
    this.directory,
    RecordingStore? recordings,
    ShareFiles? share,
    PickText? pickText,
  }) : recordings =
           recordings ??
           (directory == null
               ? MemoryRecordingStore()
               : FileRecordingStore(
                   Directory(
                     '${directory.path}${Platform.pathSeparator}mitschnitte',
                   ),
                 )),
       share = share ?? shareWithSystem,
       pickText = pickText ?? pickTextFile {
    recorder = Recorder(this.recordings);
  }

  final Directory? directory;
  final RecordingStore recordings;
  final ShareFiles share;
  final PickText pickText;
  late final Recorder recorder;

  CanProfile _profile = const CanProfile();
  CanProfile get profile => _profile;

  final Set<String> _pinned = {};

  /// Namen der angepinnten Signale, in der Reihenfolge des Anpinnens.
  List<String> get pinned => _pinned.toList();

  bool isPinned(String name) => _pinned.contains(name);

  /// Angepinnte Signale, die es im Profil gibt.
  List<SignalRef> get pinnedSignals => [
    for (final name in _pinned) ?_profile.signal(name),
  ];

  Future<void> _saving = Future.value();

  File _file(String name) =>
      File('${directory!.path}${Platform.pathSeparator}$name');

  /// Lädt den gesicherten Stand. Kaputte Dateien werden übergangen, damit
  /// die App trotzdem startet.
  static Future<Workbench> open(Directory directory) async {
    final w = Workbench(directory: directory);
    try {
      final profile = w._file('profil.json');
      if (await profile.exists()) {
        w._profile = CanProfile.parse(await profile.readAsString());
      }
      final state = w._file('werkbank.json');
      if (await state.exists()) {
        final json = jsonDecode(await state.readAsString());
        if (json is Map && json['pinned'] is List) {
          w._pinned.addAll((json['pinned'] as List).whereType<String>());
        }
      }
    } on Exception catch (e) {
      debugPrint('Werkbank-Stand nicht lesbar: $e');
    }
    return w;
  }

  /// Wartet, bis alles gesichert ist (Tests).
  Future<void> get saved => _saving;

  void _changed() {
    notifyListeners();
    if (directory == null) return;
    final profile = _profile.encode();
    final state = jsonEncode({'pinned': pinned});
    _saving = _saving.then((_) async {
      try {
        await _file('profil.json').writeAsString(profile, flush: true);
        await _file('werkbank.json').writeAsString(state, flush: true);
      } on FileSystemException catch (e) {
        debugPrint('Werkbank-Stand nicht gesichert: $e');
      }
    });
  }

  /// Profil ersetzen (Import, Beispiel, neu). Pins auf Signale, die es nicht
  /// mehr gibt, entfallen.
  void setProfile(CanProfile profile) {
    _profile = profile;
    _pinned.retainWhere((name) => profile.signal(name) != null);
    _changed();
  }

  /// Signal anlegen oder ändern, siehe [CanProfile.withSignal]. Wirft
  /// [ProfileFormatException].
  void saveSignal(int rawId, SignalDef signal, {String? replaces, int? dlc}) {
    _profile = _profile.withSignal(rawId, signal, replaces: replaces, dlc: dlc);
    if (replaces != null &&
        replaces != signal.name &&
        _pinned.remove(replaces)) {
      _pinned.add(signal.name);
    }
    _changed();
  }

  void deleteSignal(String name) {
    _profile = _profile.withoutSignal(name);
    _pinned.remove(name);
    _changed();
  }

  void togglePin(String name) {
    if (!_pinned.remove(name)) _pinned.add(name);
    _changed();
  }

  /// Name der Profildatei beim Teilen.
  String get profileFileName =>
      '${_profile.profileId.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}'
      '.profile.json';

  Future<void> shareProfile() =>
      share([ShareItem.text(profileFileName, _profile.encode())]);

  ShareItem _recordingItem(String name, String? text) {
    final path = recordings.pathOf(name);
    return path != null
        ? ShareItem.file(name, path)
        : ShareItem.text(name, text ?? '');
  }

  Future<void> shareRecording(String name) async => share([
    _recordingItem(
      name,
      recordings.pathOf(name) == null ? await recordings.read(name) : null,
    ),
  ]);

  /// Mitschnitt, aktuelles Profil und eine Anleitung für die KI: Sie soll
  /// daraus ein verbessertes Profil im selben Format liefern, das sich
  /// wieder importieren lässt.
  Future<void> shareForAi(String name) async => share([
    _recordingItem(
      name,
      recordings.pathOf(name) == null ? await recordings.read(name) : null,
    ),
    ShareItem.text(profileFileName, _profile.encode()),
    ShareItem.text(
      'KI-ANLEITUNG.md',
      aiInstructions(recording: name, profile: profileFileName),
    ),
  ]);
}

/// Teilen über den Dialog des Systems. Text wird dafür in eine Datei im
/// Zwischenspeicher der App geschrieben.
Future<void> shareWithSystem(List<ShareItem> items) async {
  final temp = await getTemporaryDirectory();
  final dir = Directory('${temp.path}${Platform.pathSeparator}teilen');
  await dir.create(recursive: true);
  final files = <XFile>[];
  for (final item in items) {
    var path = item.path;
    if (path == null) {
      path = '${dir.path}${Platform.pathSeparator}${item.name}';
      await File(path).writeAsString(item.text!, flush: true);
    }
    files.add(XFile(path, mimeType: 'text/plain'));
  }
  await SharePlus.instance.share(
    ShareParams(
      files: files,
      fileNameOverrides: [for (final item in items) item.name],
    ),
  );
}

Future<String?> pickTextFile() async {
  final files = await FilePicker.pickFiles();
  final path = files.firstOrNull?.path;
  return path == null ? null : File(path).readAsString();
}
