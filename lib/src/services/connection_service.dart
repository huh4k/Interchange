import '../domain/entities/station.dart';
import '../domain/value_objects/transit_type.dart';

class TransitConnection {
  final String title;
  final String description;
  final TransitType type;
  final List<String> lineBadges;

  const TransitConnection({
    required this.title,
    required this.description,
    required this.type,
    required this.lineBadges,
  });
}

class ConnectionService {
  static const Map<String, List<TransitConnection>> _knownInterchanges = {
    'flinders': [
      TransitConnection(
        title: 'Metro Train Lines',
        description: 'Direct transfer to all Melbourne metropolitan lines',
        type: TransitType.metro,
        lineBadges: ['FKN', 'BEL', 'LIL', 'GLN', 'PKM', 'CRB', 'SNB', 'CGB', 'UPF', 'MER', 'HUR', 'WBL', 'WIL', 'SHM'],
      ),
      TransitConnection(
        title: 'Yarra Trams Intersect',
        description: 'Routes 35 (City Circle), 70, 75, Swanston & Elizabeth St Trams',
        type: TransitType.tram,
        lineBadges: ['1', '3', '5', '6', '16', '35', '64', '67', '70', '72', '75'],
      ),
    ],
    'southern cross': [
      TransitConnection(
        title: 'V/Line Regional Services',
        description: 'Geelong, Ballarat, Bendigo, Seymour, Traralgon & Intercity',
        type: TransitType.regionalTrain,
        lineBadges: ['Geelong', 'Ballarat', 'Bendigo', 'Seymour', 'Traralgon'],
      ),
      TransitConnection(
        title: 'Metro Rail & SkyBus',
        description: 'All Metro lines, Melbourne Airport Express & Interstate Coach Terminal',
        type: TransitType.metro,
        lineBadges: ['SkyBus', 'Metro Loop', 'Overland', 'NSWLink'],
      ),
      TransitConnection(
        title: 'Collins & Spencer St Trams',
        description: 'Routes 11, 12, 48, 86, 96, 109',
        type: TransitType.tram,
        lineBadges: ['11', '12', '48', '86', '96', '109'],
      ),
    ],
    'richmond': [
      TransitConnection(
        title: 'Eastern & South-Eastern Lines',
        description: 'Cross-platform transfer between 8 train lines',
        type: TransitType.metro,
        lineBadges: ['BEL', 'LIL', 'ALM', 'GLN', 'FKN', 'PKM', 'CRB', 'SHM'],
      ),
      TransitConnection(
        title: 'Swan St & MCG Trams',
        description: 'Route 70 (Waterfront City - Wattle Park)',
        type: TransitType.tram,
        lineBadges: ['70'],
      ),
    ],
    'south yarra': [
      TransitConnection(
        title: 'Connecting Rail Lines',
        description: 'Direct interchange between Frankston, Sandringham, Pakenham & Cranbourne lines',
        type: TransitType.metro,
        lineBadges: ['FKN', 'SHM', 'PKM', 'CRB'],
      ),
      TransitConnection(
        title: 'Toorak Rd Tram',
        description: 'Route 58 (West Coburg - Toorak)',
        type: TransitType.tram,
        lineBadges: ['58'],
      ),
    ],
    'caulfield': [
      TransitConnection(
        title: 'Bayside & South-Eastern Lines',
        description: 'Pakenham, Cranbourne, Frankston lines & Gippsland V/Line',
        type: TransitType.metro,
        lineBadges: ['PKM', 'CRB', 'FKN', 'V/Line'],
      ),
      TransitConnection(
        title: 'Dandenong Rd Tram',
        description: 'Route 3/3a (Melbourne University - East Malvern)',
        type: TransitType.tram,
        lineBadges: ['3'],
      ),
    ],
    'north melbourne': [
      TransitConnection(
        title: 'Northern & Western Lines',
        description: 'Sunbury, Craigieburn, Upfield, Werribee, Williamstown & Seymour V/Line',
        type: TransitType.metro,
        lineBadges: ['SNB', 'CGB', 'UPF', 'WBL', 'WIL', 'Seymour'],
      ),
    ],
    'footscray': [
      TransitConnection(
        title: 'Western Junction & Regional Rail',
        description: 'Sunbury, Werribee, Williamstown & V/Line Geelong, Ballarat & Bendigo',
        type: TransitType.metro,
        lineBadges: ['SNB', 'WBL', 'WIL', 'Geelong', 'Ballarat'],
      ),
      TransitConnection(
        title: 'Droop St Tram & Bus Hub',
        description: 'Route 82 Tram (Footscray - Moonee Ponds) & Bus Interchange',
        type: TransitType.tram,
        lineBadges: ['82', 'Bus Hub'],
      ),
    ],
    'clifton hill': [
      TransitConnection(
        title: 'North-Eastern Lines',
        description: 'Mernda and Hurstbridge line junction',
        type: TransitType.metro,
        lineBadges: ['MER', 'HUR'],
      ),
    ],
    'burnley': [
      TransitConnection(
        title: 'Burnley Group Junction',
        description: 'Belgrave, Lilydale, Alamein & Glen Waverley lines',
        type: TransitType.metro,
        lineBadges: ['BEL', 'LIL', 'ALM', 'GLN'],
      ),
    ],
    'camberwell': [
      TransitConnection(
        title: 'Outer Eastern Lines',
        description: 'Belgrave, Lilydale & Alamein lines cross-platform interchange',
        type: TransitType.metro,
        lineBadges: ['BEL', 'LIL', 'ALM'],
      ),
      TransitConnection(
        title: 'Burke & Riversdale Rd Trams',
        description: 'Routes 70, 72 & 75',
        type: TransitType.tram,
        lineBadges: ['70', '72', '75'],
      ),
    ],
    'ringwood': [
      TransitConnection(
        title: 'Maroondah Rail Junction',
        description: 'Belgrave & Lilydale lines interchange & Regional Bus Hub',
        type: TransitType.metro,
        lineBadges: ['BEL', 'LIL', 'SmartBus'],
      ),
    ],
    'dandenong': [
      TransitConnection(
        title: 'South-Eastern Rail & V/Line',
        description: 'Pakenham, Cranbourne lines & Traralgon/Bairnsdale V/Line',
        type: TransitType.metro,
        lineBadges: ['PKM', 'CRB', 'Gippsland'],
      ),
    ],
    'newport': [
      TransitConnection(
        title: 'South-Western Junction',
        description: 'Werribee and Williamstown lines',
        type: TransitType.metro,
        lineBadges: ['WBL', 'WIL'],
      ),
    ],
    'sunshine': [
      TransitConnection(
        title: 'Western Regional & Metro Hub',
        description: 'Sunbury line & V/Line Geelong, Ballarat, Bendigo',
        type: TransitType.metro,
        lineBadges: ['SNB', 'Geelong', 'Ballarat', 'Bendigo'],
      ),
    ],
    'box hill': [
      TransitConnection(
        title: 'Belgrave / Lilydale & Tram 109',
        description: 'Belgrave & Lilydale lines, Route 109 Tram & Major Bus Interchange',
        type: TransitType.tram,
        lineBadges: ['BEL', 'LIL', '109', 'Bus Hub'],
      ),
    ],
    'melbourne central': [
      TransitConnection(
        title: 'City Loop & Swanston St Trams',
        description: 'City Loop trains and major university/medical tram corridor',
        type: TransitType.tram,
        lineBadges: ['City Loop', '1', '3', '5', '6', '16', '64', '67', '72'],
      ),
    ],
    'parliament': [
      TransitConnection(
        title: 'City Loop & Bourke/Spring St Trams',
        description: 'Routes 11, 12, 86, 96, 35',
        type: TransitType.tram,
        lineBadges: ['City Loop', '11', '12', '86', '96', '35'],
      ),
    ],
    'flagstaff': [
      TransitConnection(
        title: 'City Loop & William/La Trobe St Trams',
        description: 'Routes 30, 35, 58',
        type: TransitType.tram,
        lineBadges: ['City Loop', '30', '35', '58'],
      ),
    ],
    'frankston': [
      TransitConnection(
        title: 'Frankston & Stony Point Junction',
        description: 'Interchange to Stony Point diesel rail service & Peninsula Bus Network',
        type: TransitType.metro,
        lineBadges: ['FKN', 'STY'],
      ),
    ],
    'watergardens': [
      TransitConnection(
        title: 'North-Western Hub',
        description: 'Sunbury line & Bendigo V/Line transfer',
        type: TransitType.metro,
        lineBadges: ['SNB', 'Bendigo'],
      ),
    ],
    'broadmeadows': [
      TransitConnection(
        title: 'Northern Rail & Regional Hub',
        description: 'Craigieburn line & Seymour/Shepparton/Albury V/Line',
        type: TransitType.metro,
        lineBadges: ['CGB', 'Seymour', 'Albury'],
      ),
    ],
  };

  /// Returns whether a station is designated as an interchange station on the Melbourne network map.
  static bool isDesignatedInterchange(Station station) {
    if (station.isCityLoop) return true;
    final name = station.name.toLowerCase();
    for (final key in _knownInterchanges.keys) {
      if (name.contains(key)) {
        return true;
      }
    }
    return false;
  }

  /// Returns a list of transit connections available at the given station.
  static List<TransitConnection> getConnectionsForStation(Station station, {String? currentLineCode}) {
    final name = station.name.toLowerCase();
    
    for (final entry in _knownInterchanges.entries) {
      if (name.contains(entry.key)) {
        final connections = entry.value;
        if (currentLineCode == null || currentLineCode.isEmpty) {
          return connections;
        }
        return connections;
      }
    }

    if (station.isCityLoop) {
      return [
        const TransitConnection(
          title: 'City Loop Transfer',
          description: 'Transfer to all Melbourne Metropolitan rail lines via City Loop',
          type: TransitType.metro,
          lineBadges: ['City Loop'],
        ),
      ];
    }

    return const [];
  }
}
