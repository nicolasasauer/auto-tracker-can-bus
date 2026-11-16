import 'dart:convert';
import 'dart:typed_data';

import 'messages.dart';

/// Arbeitsprofil der Werkbank: welche Bits einer CAN-Botschaft welches Signal
/// sind und wie der Rohwert umgerechnet wird. Format und Bitzählung:
/// docs/CAN-KONZEPT.md, Kapitel 9.1.
///
/// Unbekannte Felder bleiben beim Laden und Speichern erhalten (z. B. `store`
/// oder `cycle_ms`), damit ein Profil den Weg App → KI → App unbeschadet
/// übersteht.

enum SignalByteOrder { big, little }

/// Wie sicher die Zuordnung ist.
enum SignalConfidence {
  verified('verified', 'geprüft'),
  probable('probable', 'wahrscheinlich'),
  guess('guess', 'Vermutung');

  const SignalConfidence(this.key, this.label);
  final String key;
  final String label;
}

/// Speicherregeln, die ein Profil nennen darf (die Werkbank prüft sie nur;
/// ausgewertet werden sie von `SignalSampler`).
const knownStoreModes = {'sample', 'on_change', 'deadband', 'counter'};

/// Längstes Bitfeld. 64 Bit ohne Vorzeichen passen nicht in Darts Ganzzahl.
const maxSignalLength = 63;

class ProfileFormatException implements Exception {
  ProfileFormatException(this.problems);
  ProfileFormatException.single(String problem) : problems = [problem];

  final List<String> problems;

  @override
  String toString() => problems.join('\n');
}

class SignalDef {
  const SignalDef({
    required this.name,
    required this.start,
    required this.length,
    this.signed = false,
    this.byteOrder = SignalByteOrder.big,
    this.factor = 1,
    this.offset = 0,
    this.unit = '',
    this.confidence = SignalConfidence.guess,
    this.note = '',
    this.extra = const {},
  });

  final String name;

  /// Big Endian: Bit-Abstand vom höchstwertigen Bit von Byte 0 bis zum
  /// höchstwertigen Bit des Signals (0 = Byte 0 Bit 7, 8 = Byte 1 Bit 7).
  /// Little Endian: Position des niederwertigsten Bits wie bei DBC/Intel
  /// (Byte × 8 + Bit, Bit 0 = niederwertigstes Bit des Bytes).
  final int start;
  final int length;
  final bool signed;
  final SignalByteOrder byteOrder;
  final double factor;
  final double offset;
  final String unit;
  final SignalConfidence confidence;
  final String note;

  /// Felder, die die Werkbank nicht kennt (z. B. `store`).
  final Map<String, Object?> extra;

  SignalDef copyWith({
    String? name,
    int? start,
    int? length,
    bool? signed,
    SignalByteOrder? byteOrder,
    double? factor,
    double? offset,
    String? unit,
    SignalConfidence? confidence,
    String? note,
  }) => SignalDef(
    name: name ?? this.name,
    start: start ?? this.start,
    length: length ?? this.length,
    signed: signed ?? this.signed,
    byteOrder: byteOrder ?? this.byteOrder,
    factor: factor ?? this.factor,
    offset: offset ?? this.offset,
    unit: unit ?? this.unit,
    confidence: confidence ?? this.confidence,
    note: note ?? this.note,
    extra: extra,
  );

  /// Die belegten Bits als Abstand vom höchstwertigen Bit von Byte 0
  /// (Byte × 8 + (7 − Bit)), vom höchst- zum niederwertigsten Bit des
  /// Signals. So lassen sich beide Byte-Reihenfolgen im Bitraster zeigen.
  List<int> get bitPositions => [
    if (byteOrder == SignalByteOrder.big)
      for (var i = 0; i < length; i++) start + i
    else
      for (var p = start + length - 1; p >= start; p--)
        (p >> 3) * 8 + 7 - p % 8,
  ];

  /// Zahl der Bytes, die eine Botschaft für dieses Signal haben muss.
  int get bytesNeeded => (start + length + 7) >> 3;

  /// Rohwert aus den Nutzdaten, null wenn die Botschaft zu kurz ist.
  int? rawFrom(Uint8List data) {
    if (start < 0 || length < 1 || bytesNeeded > data.length) return null;
    var raw = 0;
    for (final p in bitPositions) {
      raw = raw << 1 | (data[p >> 3] >> (7 - p % 8) & 1);
    }
    if (signed && raw >= 1 << (length - 1)) raw -= 1 << length;
    return raw;
  }

  double scale(int raw) => raw * factor + offset;

  /// Umgerechneter Wert, null wenn die Botschaft zu kurz ist.
  double? valueFrom(Uint8List data) {
    final raw = rawFrom(data);
    return raw == null ? null : scale(raw);
  }

  /// Nachkommastellen, die der Faktor hergibt (0,125 → 3), höchstens 4.
  int get decimals {
    var digits = 0;
    for (final v in [factor, offset]) {
      var d = 0;
      while (d < 4 &&
          (v * _pow10[d] - (v * _pow10[d]).roundToDouble()).abs() > 1e-9) {
        d++;
      }
      if (d > digits) digits = d;
    }
    return digits;
  }

  /// Wert mit Komma und Einheit, z. B. „1234,5 rpm“.
  String format(double value) {
    final number = value.toStringAsFixed(decimals).replaceAll('.', ',');
    return unit.isEmpty ? number : '$number $unit';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'start': start,
    'length': length,
    'signed': signed,
    if (byteOrder == SignalByteOrder.little) 'byte_order': 'little',
    'factor': _compact(factor),
    'offset': _compact(offset),
    if (unit.isNotEmpty) 'unit': unit,
    'confidence': confidence.key,
    if (note.isNotEmpty) 'note': note,
    ...extra,
  };
}

const _pow10 = [1.0, 10.0, 100.0, 1000.0, 10000.0];

/// 1.0 als 1 schreiben, damit die Datei so aussieht wie von Hand geschrieben.
num _compact(double v) =>
    v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v;

class MessageDef {
  const MessageDef({
    required this.rawId,
    this.name = '',
    this.dlc,
    this.signals = const [],
    this.extra = const {},
  });

  /// CAN-ID wie in [IdRecord.rawId] (mit Erweitert-Bit, ohne RTR).
  final int rawId;
  final String name;

  /// Datenlänge in Byte, null = unbekannt.
  final int? dlc;
  final List<SignalDef> signals;
  final Map<String, Object?> extra;

  int get id => rawId & CanLinkProtocol.idMask;
  bool get extended => rawId & CanLinkProtocol.extendedFlag != 0;
  String get label => formatCanId(id, extended: extended);

  MessageDef copyWith({String? name, int? dlc, List<SignalDef>? signals}) =>
      MessageDef(
        rawId: rawId,
        name: name ?? this.name,
        dlc: dlc ?? this.dlc,
        signals: signals ?? this.signals,
        extra: extra,
      );

  Map<String, Object?> toJson() => {
    'id': '0x$label',
    if (extended) 'extended': true,
    if (name.isNotEmpty) 'name': name,
    'dlc': ?dlc,
    ...extra,
    'signals': [for (final s in signals) s.toJson()],
  };
}

/// Ein Signal samt der Botschaft, in der es liegt.
typedef SignalRef = ({MessageDef message, SignalDef signal});

class CanProfile {
  const CanProfile({
    this.profileId = 'neu',
    this.messages = const [],
    this.extra = const {},
  });

  static const schemaVersion = 1;

  final String profileId;
  final List<MessageDef> messages;

  /// Übrige Felder der Datei (`vehicle`, `bus`, `ignored`, …).
  final Map<String, Object?> extra;

  bool get isEmpty => messages.every((m) => m.signals.isEmpty);

  Iterable<SignalRef> get signals sync* {
    for (final m in messages) {
      for (final s in m.signals) {
        yield (message: m, signal: s);
      }
    }
  }

  int get signalCount => messages.fold(0, (n, m) => n + m.signals.length);

  MessageDef? message(int rawId) {
    for (final m in messages) {
      if (m.rawId == rawId) return m;
    }
    return null;
  }

  SignalRef? signal(String name) {
    for (final ref in signals) {
      if (ref.signal.name == name) return ref;
    }
    return null;
  }

  /// Fahrzeug als Text, z. B. „Peugeot 208 (2016)“, leer wenn unbekannt.
  String get vehicleLabel {
    final v = extra['vehicle'];
    if (v is! Map) return '';
    final year = v['year'];
    return [
      v['make'],
      v['model'],
      if (year != null) '($year)',
    ].where((p) => p != null && '$p'.isNotEmpty).join(' ');
  }

  CanProfile copyWith({String? profileId, List<MessageDef>? messages}) =>
      CanProfile(
        profileId: profileId ?? this.profileId,
        messages: messages ?? this.messages,
        extra: extra,
      );

  /// Signal anlegen oder ersetzen. [replaces] ist der bisherige Name beim
  /// Bearbeiten. Die Botschaft wird bei Bedarf angelegt. Wirft
  /// [ProfileFormatException], wenn das Signal nicht passt oder der Name
  /// schon vergeben ist.
  CanProfile withSignal(
    int rawId,
    SignalDef signal, {
    String? replaces,
    int? dlc,
  }) {
    final existing = this.signal(signal.name);
    if (existing != null && signal.name != replaces) {
      throw ProfileFormatException.single(
        'Den Namen „${signal.name}“ gibt es schon '
        '(Botschaft ${existing.message.label}).',
      );
    }
    final base = replaces == null ? this : withoutSignal(replaces);
    final target = base.message(rawId) ?? MessageDef(rawId: rawId, dlc: dlc);
    final problems = <String>[];
    _checkSignal(signal, target.dlc, 'Signal „${signal.name}“', problems);
    if (problems.isNotEmpty) throw ProfileFormatException(problems);

    // Am alten Platz ersetzen, damit die Reihenfolge der Datei bleibt.
    final old = message(rawId)?.signals ?? const <SignalDef>[];
    final index = old.indexWhere((s) => s.name == replaces);
    final updated = [...target.signals];
    if (index >= 0 && index <= updated.length) {
      updated.insert(index, signal);
    } else {
      updated.add(signal);
    }
    final next = target.copyWith(signals: updated);
    final list = [
      for (final m in base.messages) m.rawId == rawId ? next : m,
      if (base.message(rawId) == null) next,
    ];
    return base.copyWith(messages: list);
  }

  CanProfile withoutSignal(String name) => copyWith(
    messages: [
      for (final m in messages)
        m.copyWith(signals: m.signals.where((s) => s.name != name).toList()),
    ],
  );

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'schema_version': schemaVersion,
    ...extra,
    'messages': [for (final m in messages) m.toJson()],
  };

  /// Als eingerücktes JSON, wie es exportiert und der KI gegeben wird.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// Liest und prüft ein Profil. Wirft [ProfileFormatException] mit allen
  /// gefundenen Fehlern.
  ///
  /// Antworten einer KI stehen oft in einem Markdown-Block mit Text davor
  /// und danach; deshalb wird das äußerste `{ … }` herausgesucht.
  static CanProfile parse(String text) {
    final from = text.indexOf('{');
    final to = text.lastIndexOf('}');
    if (from < 0 || to < from) {
      throw ProfileFormatException.single('Kein JSON gefunden.');
    }
    final Object? json;
    try {
      json = jsonDecode(text.substring(from, to + 1));
    } on FormatException catch (e) {
      throw ProfileFormatException.single('Kein gültiges JSON: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw ProfileFormatException.single('Das JSON ist kein Objekt.');
    }
    return fromJson(json);
  }

  static CanProfile fromJson(Map<String, Object?> json) {
    final problems = <String>[];
    final version = json['schema_version'];
    if (version != schemaVersion) {
      problems.add(
        'schema_version ist ${version ?? 'nicht angegeben'}, '
        'erwartet wird $schemaVersion.',
      );
    }
    final rawMessages = json['messages'];
    if (rawMessages is! List) {
      problems.add('„messages“ fehlt oder ist keine Liste.');
      throw ProfileFormatException(problems);
    }

    final messages = <MessageDef>[];
    final ids = <int>{};
    final names = <String>{};
    for (final (i, m) in rawMessages.indexed) {
      if (m is! Map<String, Object?>) {
        problems.add('Botschaft ${i + 1} ist kein Objekt.');
        continue;
      }
      final message = _message(m, 'Botschaft ${i + 1}', problems);
      if (message == null) continue;
      if (!ids.add(message.rawId)) {
        problems.add('Botschaft ${message.label} steht doppelt im Profil.');
      }
      for (final s in message.signals) {
        if (!names.add(s.name)) {
          problems.add('Signalname „${s.name}“ ist doppelt.');
        }
      }
      messages.add(message);
    }
    if (problems.isNotEmpty) throw ProfileFormatException(problems);

    final id = json['profile_id'];
    return CanProfile(
      profileId: id is String && id.isNotEmpty ? id : 'neu',
      messages: messages,
      extra: {
        for (final e in json.entries)
          if (!const {
            'profile_id',
            'schema_version',
            'messages',
          }.contains(e.key))
            e.key: e.value,
      },
    );
  }
}

MessageDef? _message(
  Map<String, Object?> json,
  String where,
  List<String> problems,
) {
  final id = _canId(json['id']);
  if (id == null) {
    problems.add('$where: „id“ fehlt oder ist keine CAN-ID (z. B. "0x208").');
    return null;
  }
  final extended = json['extended'] == true || id > 0x7FF;
  if (id > CanLinkProtocol.idMask) {
    problems.add('$where: CAN-ID ist größer als 29 Bit.');
    return null;
  }
  final rawId = extended ? id | CanLinkProtocol.extendedFlag : id;
  where = 'Botschaft ${formatCanId(id, extended: extended)}';

  final dlc = json['dlc'];
  if (dlc != null && (dlc is! int || dlc < 0 || dlc > 8)) {
    problems.add('$where: „dlc“ muss 0 bis 8 sein.');
    return null;
  }
  final rawSignals = json['signals'] ?? const <Object?>[];
  if (rawSignals is! List) {
    problems.add('$where: „signals“ ist keine Liste.');
    return null;
  }
  final signals = <SignalDef>[];
  for (final (i, s) in rawSignals.indexed) {
    if (s is! Map<String, Object?>) {
      problems.add('$where, Signal ${i + 1}: kein Objekt.');
      continue;
    }
    final signal = _signal(s, '$where, Signal ${i + 1}', dlc as int?, problems);
    if (signal != null) signals.add(signal);
  }
  final name = json['name'];
  return MessageDef(
    rawId: rawId,
    name: name is String ? name : '',
    dlc: dlc as int?,
    signals: signals,
    extra: {
      for (final e in json.entries)
        if (!const {'id', 'extended', 'name', 'dlc', 'signals'}.contains(e.key))
          e.key: e.value,
    },
  );
}

SignalDef? _signal(
  Map<String, Object?> json,
  String where,
  int? dlc,
  List<String> problems,
) {
  final before = problems.length;
  final name = json['name'];
  if (name is! String || name.trim().isEmpty) {
    problems.add('$where: „name“ fehlt.');
  } else {
    where = 'Signal „$name“';
  }
  final start = json['start'];
  final length = json['length'];
  if (start is! int) problems.add('$where: „start“ fehlt (ganze Zahl).');
  if (length is! int) problems.add('$where: „length“ fehlt (ganze Zahl).');

  final factor = json['factor'] ?? 1;
  final offset = json['offset'] ?? 0;
  if (factor is! num) problems.add('$where: „factor“ ist keine Zahl.');
  if (offset is! num) problems.add('$where: „offset“ ist keine Zahl.');

  final signed = json['signed'] ?? false;
  if (signed is! bool) problems.add('$where: „signed“ muss true/false sein.');

  final order = switch (json['byte_order']) {
    null || 'big' || 'big_endian' => SignalByteOrder.big,
    'little' || 'little_endian' => SignalByteOrder.little,
    _ => null,
  };
  if (order == null) {
    problems.add('$where: „byte_order“ muss "big" oder "little" sein.');
  }

  final confidenceKey = json['confidence'] ?? 'guess';
  final confidence = SignalConfidence.values
      .where((c) => c.key == confidenceKey)
      .firstOrNull;
  if (confidence == null) {
    problems.add(
      '$where: „confidence“ muss verified, probable oder guess sein.',
    );
  }

  final store = json['store'];
  if (store != null &&
      (store is! Map || !knownStoreModes.contains(store['mode']))) {
    problems.add(
      '$where: „store.mode“ muss eines von '
      '${knownStoreModes.join(', ')} sein.',
    );
  }
  final unit = json['unit'] ?? '';
  final note = json['note'] ?? '';
  if (unit is! String) problems.add('$where: „unit“ ist kein Text.');
  if (note is! String) problems.add('$where: „note“ ist kein Text.');
  if (problems.length > before) return null;

  final signal = SignalDef(
    name: (name as String).trim(),
    start: start as int,
    length: length as int,
    signed: signed as bool,
    byteOrder: order!,
    factor: (factor as num).toDouble(),
    offset: (offset as num).toDouble(),
    unit: unit as String,
    confidence: confidence!,
    note: note as String,
    extra: {
      for (final e in json.entries)
        if (!const {
          'name',
          'start',
          'length',
          'signed',
          'byte_order',
          'factor',
          'offset',
          'unit',
          'confidence',
          'note',
        }.contains(e.key))
          e.key: e.value,
    },
  );
  _checkSignal(signal, dlc, where, problems);
  return problems.length > before ? null : signal;
}

void _checkSignal(SignalDef s, int? dlc, String where, List<String> problems) {
  if (s.name.trim().isEmpty) problems.add('$where: Der Name fehlt.');
  if (s.start < 0) problems.add('$where: „start“ darf nicht negativ sein.');
  if (s.length < 1 || s.length > maxSignalLength) {
    problems.add('$where: „length“ muss 1 bis $maxSignalLength sein.');
    return;
  }
  if (s.start < 0) return;
  final bits = (dlc ?? 8) * 8;
  if (s.start + s.length > bits) {
    problems.add(
      '$where: Bit ${s.start} + ${s.length} Bit passt nicht in '
      '${dlc ?? 8} Byte.',
    );
  }
}

int? _canId(Object? value) {
  if (value is int) return value < 0 ? null : value;
  if (value is! String) return null;
  final text = value.trim().toLowerCase();
  return text.startsWith('0x')
      ? int.tryParse(text.substring(2), radix: 16)
      : int.tryParse(text, radix: 16);
}
