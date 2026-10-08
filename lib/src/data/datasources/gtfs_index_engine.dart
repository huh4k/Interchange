import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../../core/gtfs_csv.dart';
import '../../core/heavy_work.dart';
import '../../domain/entities/station.dart';

class GtfsIndexCache {
  final Map<String, Station> stops;
  final Map<String, String> parentStopIdMap;

  const GtfsIndexCache({
    required this.stops,
    required this.parentStopIdMap,
  });
}

class GtfsIndexEngine {
  static final Map<String, GtfsIndexCache> _indexCache = {};

  /// Drops the in-memory index for [dirPath] so the next lookup rebuilds it
  /// (used after stops.txt is replaced by a fresh download).
  static void invalidate(String dirPath) => _indexCache.remove(dirPath);

  static final RegExp _newlineRegex = RegExp(r'\r?\n');
  static final RegExp _whitespaceRegex = RegExp(r'\s+');
  static final RegExp _stopCodeRegex = RegExp(r'#\s*(\d+[a-zA-Z]?)');
  static final RegExp _stopUrlIdRegex = RegExp(r'/stop/(\d+)');
  static final RegExp _parentSuffixRegex = RegExp(r'[:#_\-]');
  static final RegExp _parensRegex = RegExp(r'\s*\([^)]*\)');
  static final RegExp _railwayStationRegex =
      RegExp(r'\s+Railway Station', caseSensitive: false);
  static final RegExp _stationStationRegex =
      RegExp(r'\s+Station Station', caseSensitive: false);

  static const int _binaryMagic = 0x47544653; // "GTFS"
  static const int _binaryVersion = 2;
  static const String binaryIndexFilename = 'stops_index.bin';

  static void clearCache() {
    _indexCache.clear();
  }

  static bool isReplacementBusStop(String rawName) {
    final lower = rawName.toLowerCase();
    return lower.contains('replacement bus') ||
        lower.contains('bus replacement') ||
        lower.contains('replacement stop') ||
        lower.contains('temp bus') ||
        lower.contains('temporary bus') ||
        lower.contains('bustech');
  }

  static String normalizeStationName(String rawName) {
    if (rawName.isEmpty) return 'Station';

    String name = rawName.trim();

    name = name.split('/')[0].trim();
    name = name.replaceAll(_parensRegex, '').trim();
    name = name.replaceAll(_railwayStationRegex, ' Station');
    name = name.replaceAll(_stationStationRegex, ' Station');

    return name;
  }

  /// Builds or loads pre-indexed binary cache from disk, falling back to text parsing if needed.
  static Future<GtfsIndexCache> getOrCreateIndex(Directory modeDir) async {
    final path = modeDir.path;
    final cached = _indexCache[path];
    if (cached != null) {
      return cached;
    }

    final binaryFile = File(p.join(modeDir.path, binaryIndexFilename));
    final stopsFile = File(p.join(modeDir.path, 'stops.txt'));

    // 1. Check if binary index is already present and fresh
    if (await binaryFile.exists()) {
      try {
        final binModified = await binaryFile.lastModified();
        final textExists = await stopsFile.exists();
        final textModified =
            textExists ? await stopsFile.lastModified() : DateTime.fromMillisecondsSinceEpoch(0);

        if (!textExists || !textModified.isAfter(binModified)) {
          final loaded = await loadBinaryIndex(binaryFile);
          if (loaded != null && loaded.stops.isNotEmpty) {
            _indexCache[path] = loaded;
            return loaded;
          }
        }
      } catch (_) {
        // Fallback to text parsing
      }
    }

    // 2. Parse raw text asset/file
    final parsed = await _parseStopsMap(modeDir);
    _indexCache[path] = parsed;

    // 3. Persist pre-indexed binary cache for rapid future cold starts
    if (parsed.stops.isNotEmpty) {
      try {
        await saveBinaryIndex(binaryFile, parsed);
      } catch (_) {}
    }

    return parsed;
  }

  /// Serializes a [GtfsIndexCache] to a compact binary file.
  static Future<void> saveBinaryIndex(
    File targetFile,
    GtfsIndexCache cache,
  ) async {
    final bytes = encodeBinary(cache);
    await targetFile.create(recursive: true);
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  /// Deserializes a [GtfsIndexCache] from a binary file.
  static Future<GtfsIndexCache?> loadBinaryIndex(File binaryFile) async {
    if (!await binaryFile.exists()) return null;
    final bytes = await binaryFile.readAsBytes();
    return runHeavy(bytes.length, () => decodeBinary(bytes));
  }

  /// Binary encoder for GtfsIndexCache
  static Uint8List encodeBinary(GtfsIndexCache cache) {
    final builder = BytesBuilder();

    // Magic & Version header
    final headerData = ByteData(8);
    headerData.setUint32(0, _binaryMagic, Endian.big);
    headerData.setUint32(4, _binaryVersion, Endian.big);
    builder.add(headerData.buffer.asUint8List());

    // Deduplicate distinct Station objects
    final distinctStations = <Station>[];
    final stationIndexMap = <Station, int>{};

    for (final st in cache.stops.values) {
      if (!stationIndexMap.containsKey(st)) {
        stationIndexMap[st] = distinctStations.length;
        distinctStations.add(st);
      }
    }

    // 1. Write distinct stations
    final stationCountData = ByteData(4);
    stationCountData.setUint32(0, distinctStations.length, Endian.big);
    builder.add(stationCountData.buffer.asUint8List());

    for (final st in distinctStations) {
      _writeString(builder, st.id);
      _writeString(builder, st.stopId);
      _writeString(builder, st.name);
      _writeString(builder, st.code);

      final coordsData = ByteData(17);
      coordsData.setFloat64(0, st.lat, Endian.big);
      coordsData.setFloat64(8, st.lon, Endian.big);
      coordsData.setUint8(16, st.isCityLoop ? 1 : 0);
      builder.add(coordsData.buffer.asUint8List());

      _writeString(builder, st.suburb);
      _writeString(builder, st.zone);
    }

    // 2. Write stops map (key -> station index)
    final stopsCountData = ByteData(4);
    stopsCountData.setUint32(0, cache.stops.length, Endian.big);
    builder.add(stopsCountData.buffer.asUint8List());

    final indexData = ByteData(4);
    for (final entry in cache.stops.entries) {
      _writeString(builder, entry.key);
      final idx = stationIndexMap[entry.value] ?? 0;
      indexData.setUint32(0, idx, Endian.big);
      builder.add(indexData.buffer.asUint8List());
    }

    // 3. Write parentStopIdMap (stopId -> parentId)
    final parentCountData = ByteData(4);
    parentCountData.setUint32(0, cache.parentStopIdMap.length, Endian.big);
    builder.add(parentCountData.buffer.asUint8List());

    for (final entry in cache.parentStopIdMap.entries) {
      _writeString(builder, entry.key);
      _writeString(builder, entry.value);
    }

    return builder.toBytes();
  }

  /// Binary decoder for GtfsIndexCache
  static GtfsIndexCache? decodeBinary(Uint8List bytes) {
    if (bytes.length < 8) return null;

    final byteData = ByteData.sublistView(bytes);
    int offset = 0;

    final magic = byteData.getUint32(offset, Endian.big);
    offset += 4;
    final version = byteData.getUint32(offset, Endian.big);
    offset += 4;

    if (magic != _binaryMagic || version != _binaryVersion) {
      return null;
    }

    // 1. Read distinct stations
    if (offset + 4 > bytes.length) return null;
    final distinctCount = byteData.getUint32(offset, Endian.big);
    offset += 4;

    final distinctStations = <Station>[];
    for (int i = 0; i < distinctCount; i++) {
      final (id, off1) = _readString(bytes, offset);
      final (stopId, off2) = _readString(bytes, off1);
      final (name, off3) = _readString(bytes, off2);
      final (code, off4) = _readString(bytes, off3);
      offset = off4;

      if (offset + 17 > bytes.length) return null;
      final lat = byteData.getFloat64(offset, Endian.big);
      final lon = byteData.getFloat64(offset + 8, Endian.big);
      final isCityLoop = byteData.getUint8(offset + 16) == 1;
      offset += 17;

      final (suburb, off5) = _readString(bytes, offset);
      final (zone, off6) = _readString(bytes, off5);
      offset = off6;

      distinctStations.add(
        Station(
          id: id,
          stopId: stopId,
          name: name,
          code: code,
          lat: lat,
          lon: lon,
          suburb: suburb,
          zone: zone,
          isCityLoop: isCityLoop,
          routes: const [],
        ),
      );
    }

    // 2. Read stops map
    if (offset + 4 > bytes.length) return null;
    final stopsCount = byteData.getUint32(offset, Endian.big);
    offset += 4;

    final stopsMap = <String, Station>{};
    for (int i = 0; i < stopsCount; i++) {
      final (key, nextOffset) = _readString(bytes, offset);
      offset = nextOffset;
      if (offset + 4 > bytes.length) return null;
      final stIndex = byteData.getUint32(offset, Endian.big);
      offset += 4;

      if (stIndex < distinctStations.length) {
        stopsMap[key] = distinctStations[stIndex];
      }
    }

    // 3. Read parentStopIdMap
    if (offset + 4 > bytes.length) return null;
    final parentCount = byteData.getUint32(offset, Endian.big);
    offset += 4;

    final parentMap = <String, String>{};
    for (int i = 0; i < parentCount; i++) {
      final (key, off1) = _readString(bytes, offset);
      final (val, off2) = _readString(bytes, off1);
      offset = off2;
      parentMap[key] = val;
    }

    return GtfsIndexCache(stops: stopsMap, parentStopIdMap: parentMap);
  }

  static void _writeString(BytesBuilder builder, String value) {
    final utf8Bytes = utf8.encode(value);
    final lenData = ByteData(2);
    lenData.setUint16(0, utf8Bytes.length, Endian.big);
    builder.add(lenData.buffer.asUint8List());
    if (utf8Bytes.isNotEmpty) {
      builder.add(utf8Bytes);
    }
  }

  static (String, int) _readString(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) return ('', offset);
    final byteData = ByteData.sublistView(bytes);
    final length = byteData.getUint16(offset, Endian.big);
    offset += 2;
    if (length == 0) return ('', offset);
    if (offset + length > bytes.length) return ('', bytes.length);
    final str = utf8.decode(bytes.sublist(offset, offset + length));
    return (str, offset + length);
  }

  static Future<GtfsIndexCache> _parseStopsMap(Directory modeDir) async {
    final stopsFile = File(p.join(modeDir.path, 'stops.txt'));
    if (!await stopsFile.exists()) {
      return const GtfsIndexCache(stops: {}, parentStopIdMap: {});
    }

    final content = await stopsFile.readAsString();
    if (content.trim().isEmpty) {
      return const GtfsIndexCache(stops: {}, parentStopIdMap: {});
    }

    // Detect tram mode from directory path
    final isTramMode = modeDir.path.contains('/tram') || modeDir.path.contains('\\tram');
    return runHeavy(
      content.length,
      () => _parseStopsContent(content, isTramMode: isTramMode),
    );
  }

  static GtfsIndexCache _parseStopsContent(
    String content, {
    required bool isTramMode,
  }) {
    final lines = content.split(_newlineRegex);
    if (lines.isEmpty) {
      return const GtfsIndexCache(stops: {}, parentStopIdMap: {});
    }


    final headerCols = parseGtfsCsvRow(lines.first.replaceAll('\uFEFF', ''));
    final stopIdIdx = headerCols.indexOf('stop_id');
    final stopNameIdx = headerCols.indexOf('stop_name');
    final stopLatIdx = headerCols.indexOf('stop_lat');
    final stopLonIdx = headerCols.indexOf('stop_lon');
    final stopUrlIdx = headerCols.indexOf('stop_url');
    final stopCodeIdx = headerCols.indexOf('stop_code');
    final zoneIdIdx = headerCols.indexOf('zone_id');
    final parentStationIdx = headerCols.indexOf('parent_station');

    final stationMap = <String, Station>{};
    final parentMap = <String, String>{};

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = parseGtfsCsvRow(line);
      if (stopIdIdx == -1 || cols.length <= stopIdIdx) continue;

      final rawStopId = cols[stopIdIdx];
      if (rawStopId.isEmpty) continue;

      final rawStopName = (stopNameIdx != -1 && cols.length > stopNameIdx)
          ? cols[stopNameIdx]
          : rawStopId;

      if (isReplacementBusStop(rawStopName)) {
        continue;
      }

      // Extract the PTV API numeric stop ID from stop_url (e.g. "/stop/2587/")
      final stopUrl = (stopUrlIdx != -1 && cols.length > stopUrlIdx) ? cols[stopUrlIdx] : '';
      final urlMatch = _stopUrlIdRegex.firstMatch(stopUrl);
      final ptvStopId = urlMatch != null ? urlMatch.group(1)! : rawStopId;

      // For tram stops: preserve full intersection name (do NOT truncate on '/')
      // For train stops: apply standard normalisation
      String cleanName;
      String code;
      if (isTramMode) {
        cleanName = rawStopName.replaceAll(_whitespaceRegex, ' ').trim();
        final stopNumMatch = _stopCodeRegex.firstMatch(cleanName);
        code = stopNumMatch != null ? stopNumMatch.group(1)! : ptvStopId;
      } else {
        cleanName = normalizeStationName(rawStopName);
        if (isReplacementBusStop(cleanName)) continue;
        final stopCode = (stopCodeIdx != -1 && cols.length > stopCodeIdx) ? cols[stopCodeIdx] : '';
        code = stopCode.isNotEmpty ? stopCode : ptvStopId;
      }

      final stopLat = (stopLatIdx != -1 && cols.length > stopLatIdx)
          ? double.tryParse(cols[stopLatIdx]) ?? 0.0
          : 0.0;
      final stopLon = (stopLonIdx != -1 && cols.length > stopLonIdx)
          ? double.tryParse(cols[stopLonIdx]) ?? 0.0
          : 0.0;
      final zoneId = (zoneIdIdx != -1 && cols.length > zoneIdIdx)
          ? cols[zoneIdIdx]
          : '';

      final parentStationVal = (parentStationIdx != -1 && cols.length > parentStationIdx)
          ? cols[parentStationIdx].trim()
          : '';

      // For tram: key by PTV stop ID (each platform is distinct); for train: group by parent
      final parentId = isTramMode
          ? ptvStopId
          : (parentStationVal.isNotEmpty
              ? parentStationVal
              : rawStopId.split(_parentSuffixRegex).first);

      parentMap[rawStopId] = parentId;
      parentMap[ptvStopId] = parentId;

      final nameLower = cleanName.toLowerCase();
      // Tram stops are never city loop stops
      final isCityLoop = !isTramMode &&
          (nameLower.contains('central') ||
              nameLower.contains('flinders') ||
              nameLower.contains('parliament') ||
              nameLower.contains('flagstaff') ||
              nameLower.contains('southern cross'));

      final stationObj = Station(
        id: ptvStopId,
        stopId: ptvStopId,
        name: cleanName,
        code: code,
        lat: stopLat,
        lon: stopLon,
        suburb: 'Melbourne',
        zone: zoneId.isNotEmpty ? 'Zone $zoneId' : 'Zone 1',
        isCityLoop: isCityLoop,
        routes: const [],
      );

      // Index both the raw GTFS ID and the PTV API stop ID so lookups succeed either way
      stationMap[rawStopId] = stationObj;
      stationMap[ptvStopId] = stationObj;
      if (!isTramMode && parentId != rawStopId && parentId != ptvStopId) {
        stationMap[parentId] = stationObj;
      }
    }

    return GtfsIndexCache(stops: stationMap, parentStopIdMap: parentMap);
  }


}
