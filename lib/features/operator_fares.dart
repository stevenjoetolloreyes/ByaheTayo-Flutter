// Officially posted operator fares — reference data only.
//
// Every entry here was verified from the operator's OWN official
// Facebook page. Fan pages, aggregators (phbus, pamasahe, blogs),
// and third-party booking sites are NEVER seeded, no matter how
// plausible their numbers look. Where no official fare could be
// verified for a company, that company simply has no entries here
// (see the report for the NOT FOUND list).
//
// This dataset is NOT wired into the map preview fare: preview
// routes are hub-to-hub, while these fares are Manila-terminal to
// town, so they would essentially never match a preview route. The
// natural follow-up is a "Posted operator fares" reference section
// in the Fares tab; until then this file is the verified source of
// truth for operator fares in code.
//
// Destination notes (Partas slides, Oct 9, 2026):
// - "San Fernando City" and "San Juan" on the Partas slides are in
//   LA UNION (the SFLU area), not San Fernando, Pampanga and not
//   San Juan, Ilocos Sur. They are recorded with ", La Union".
// - "Vigan City / Bangued, Abra" is ONE fare line on the slide
//   (a grouped line); it is seeded verbatim, never split.
// - Where a slide's Pagudpud number could not be read from the
//   official post, that entry is DELIBERATELY ABSENT below
//   (Cubao Luxury, Pasay Luxury, PITX Super Deluxe Pagudpud).

/// One officially posted fare.
class OperatorFare {
  const OperatorFare({
    required this.company,
    required this.origin,
    required this.destination,
    required this.fare,
    required this.fareClass,
    required this.sourceUrl,
    required this.postedDate,
  });

  /// Operator name, e.g. 'Partas'.
  final String company;

  /// Terminal / origin as posted, e.g. 'Cubao'.
  final String origin;

  /// Destination as posted, e.g. 'Vigan City'.
  final String destination;

  /// Posted fare in pesos.
  final double fare;

  /// Service class as posted, e.g. 'Deluxe', 'Royal Class'.
  final String fareClass;

  /// The official post URL this fare was read from.
  final String sourceUrl;

  /// Post date (YYYY-MM-DD) of the official post.
  final String postedDate;
}

const String _partasPost =
    'https://www.facebook.com/partastrans/posts/pfbid02NwwTcFUr3TQF96KFWhrY3uyCPyhjAJHQAgHqdum8QqBK5Pmi5NPnvZznVu2n37jDl';
const String _victoryRoyalPost =
    'https://www.facebook.com/victorylinerinc/posts/pfbid0nNuDMPxpqW8vXsUE8J5BbG1Xju1WPZd2F7VuRFRCK2sx3nGB9gb9h9z3CiqJDnjFl';
const String _victoryEvPost =
    'https://www.facebook.com/victorylinerinc/posts/pfbid02SLUJE6RSPjxGfHNDbgbMKPsfXQdH6zqRqH24noDinufUcFLLKcffbMtDFvYZiN8Hl';
const String _jacPost =
    'https://www.facebook.com/groups/1531190334203526/permalink/1987618535227368/';
const String _alpsPost =
    'https://www.facebook.com/alpsthebus/posts/pfbid0ZsmQRJ5txonkWDYtgw3Xvb3Y86MVjYe1ac9EhjeUvba5G8BbtRLmGqfMuGUdboMvl';
const String _bicolIsarogPost =
    'https://www.facebook.com/bicolisarogtransport/posts/pfbid02qdxUKK7jAAXycTD8VJrirBmQcoV1veWR2GDejHFbMWZBYboYo5Pw7csrYupLuiqjl';

/// All verified operator fares: 46 Partas + 6 Victory Liner + 9 JAC
/// Liner + 1 ALPS + 2 Bicol Isarog = 64.
///
/// Sourcing notes for the southern/Bicol entries:
/// - JAC Liner's flyer was read from a group permalink, but the post
///   is authored by the official JAC LINER, INC account (@Jaclinerinc)
///   and the flyer itself carries the brand's handles + jacliner.com;
///   the fares below are the flyer's REGULAR fares, seeded verbatim
///   (its printed Candelaria discounted fare, ₱223, is not the 20%
///   figure — the flyer's own number, not a transcription error).
/// - Bicol Isarog's fares come from the official account's own replies
///   in the post's comments, not the post body.
/// - Cagsawa PITX → Tabaco was verified ONLY as a ₱1,200–₱1,700 range
///   with no per-class mapping, so it is NOT seeded here (a range is
///   not a fare); it stays a research note, not dataset data.
const List<OperatorFare> operatorFares = [
  // Partas — official post Oct 9, 2026. Cubao Deluxe.
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Fernando City, La Union', fare: 702, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Juan, La Union', fare: 728, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Candon City', fare: 910, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Narvacan', fare: 975, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Vigan City / Bangued, Abra', fare: 1066, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Laoag City', fare: 1274, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Pagudpud', fare: 1456, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — Cubao Super Deluxe.
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Fernando City, La Union', fare: 729, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Juan, La Union', fare: 756, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Candon City', fare: 945, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Narvacan', fare: 1013, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Vigan City / Bangued, Abra', fare: 1107, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Laoag City', fare: 1323, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Pagudpud', fare: 1512, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — Cubao Luxury (Pagudpud number unreadable: NOT seeded).
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Fernando City, La Union', fare: 905, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'San Juan, La Union', fare: 938, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Candon City', fare: 1173, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Narvacan', fare: 1256, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Vigan City / Bangued, Abra', fare: 1374, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Cubao', destination: 'Laoag City', fare: 1642, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — Pasay Deluxe.
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Fernando City, La Union', fare: 741, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Juan, La Union', fare: 767, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Candon City', fare: 949, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Narvacan', fare: 1014, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Vigan City / Bangued, Abra', fare: 1105, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Laoag City', fare: 1313, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Pagudpud', fare: 1495, fareClass: 'Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — Pasay Super Deluxe.
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Fernando City, La Union', fare: 770, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Juan, La Union', fare: 797, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Candon City', fare: 986, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Narvacan', fare: 1054, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Vigan City / Bangued, Abra', fare: 1148, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Laoag City', fare: 1364, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Pagudpud', fare: 1553, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — Pasay Luxury (Pagudpud number unreadable: NOT seeded).
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Fernando City, La Union', fare: 956, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'San Juan, La Union', fare: 989, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Candon City', fare: 1224, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Narvacan', fare: 1307, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Vigan City / Bangued, Abra', fare: 1425, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'Pasay', destination: 'Laoag City', fare: 1693, fareClass: 'Luxury', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Partas — PITX Super Deluxe (Pagudpud number unreadable: NOT seeded).
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'San Fernando City, La Union', fare: 783, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'San Juan, La Union', fare: 810, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'Candon City', fare: 999, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'Narvacan', fare: 1067, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'Vigan City / Bangued, Abra', fare: 1161, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  OperatorFare(company: 'Partas', origin: 'PITX', destination: 'Laoag City', fare: 1377, fareClass: 'Super Deluxe', sourceUrl: _partasPost, postedDate: '2026-10-09'),
  // Victory Liner — official post Jan 17, 2026: Royal Class ₱1,546
  // on all four Baguio corridors.
  OperatorFare(company: 'Victory Liner', origin: 'Pasay', destination: 'Baguio', fare: 1546, fareClass: 'Royal Class', sourceUrl: _victoryRoyalPost, postedDate: '2026-01-17'),
  OperatorFare(company: 'Victory Liner', origin: 'Baguio', destination: 'Pasay', fare: 1546, fareClass: 'Royal Class', sourceUrl: _victoryRoyalPost, postedDate: '2026-01-17'),
  OperatorFare(company: 'Victory Liner', origin: 'Baguio', destination: 'Cubao', fare: 1546, fareClass: 'Royal Class', sourceUrl: _victoryRoyalPost, postedDate: '2026-01-17'),
  OperatorFare(company: 'Victory Liner', origin: 'Cubao', destination: 'Baguio', fare: 1546, fareClass: 'Royal Class', sourceUrl: _victoryRoyalPost, postedDate: '2026-01-17'),
  // Victory Liner — official post Jan 24, 2026: ElectricBus
  // San Fernando, PAMPANGA (not La Union) ↔ Cubao ₱158.
  OperatorFare(company: 'Victory Liner', origin: 'San Fernando, Pampanga', destination: 'Cubao', fare: 158, fareClass: 'ElectricBus', sourceUrl: _victoryEvPost, postedDate: '2026-01-24'),
  OperatorFare(company: 'Victory Liner', origin: 'Cubao', destination: 'San Fernando, Pampanga', fare: 158, fareClass: 'ElectricBus', sourceUrl: _victoryEvPost, postedDate: '2026-01-24'),
  // JAC Liner — official-account fare-guide flyer, May 26, 2026.
  // Origin Kamias in all rows; class P2P vs Regular as printed.
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Dalahican / Lucena Grand', fare: 420, fareClass: 'P2P', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Dalahican / Lucena Grand', fare: 356, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Turbina, Calamba', fare: 143, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Sto. Tomas, Batangas', fare: 162, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Alaminos, Laguna', fare: 197, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'San Pablo, Laguna', fare: 221, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Tiaong, Quezon', fare: 259, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Candelaria, Quezon', fare: 292, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  OperatorFare(company: 'JAC Liner', origin: 'Kamias', destination: 'Sariaya, Quezon', fare: 324, fareClass: 'Regular', sourceUrl: _jacPost, postedDate: '2026-05-26'),
  // ALPS The Bus — official page post Sept 5, 2026 (service Sept 8).
  OperatorFare(company: 'ALPS The Bus', origin: 'PITX', destination: 'Sorsogon / Gubat', fare: 2300, fareClass: 'Sleeper Bus Master Class', sourceUrl: _alpsPost, postedDate: '2026-09-05'),
  // Bicol Isarog — official account's comment replies, Aug 26, 2026.
  OperatorFare(company: 'Bicol Isarog', origin: 'Cubao', destination: 'Cumadcad, Sorsogon', fare: 2700, fareClass: 'Ultimate Sleeper', sourceUrl: _bicolIsarogPost, postedDate: '2026-08-26'),
  OperatorFare(company: 'Bicol Isarog', origin: 'EDSA', destination: 'Masbate', fare: 2850, fareClass: 'Regular Sleeper', sourceUrl: _bicolIsarogPost, postedDate: '2026-08-26'),
];

/// Finds a verified operator fare. Matching is case-insensitive on
/// company/origin/destination; when [fareClass] is given it must
/// match too. Returns null when nothing was officially verified.
OperatorFare? findOperatorFare(
  String company,
  String origin,
  String destination, {
  String? fareClass,
}) {
  final companyKey = company.trim().toLowerCase();
  final originKey = origin.trim().toLowerCase();
  final destinationKey = destination.trim().toLowerCase();
  final classKey = fareClass?.trim().toLowerCase();
  for (final fare in operatorFares) {
    if (fare.company.toLowerCase() != companyKey) continue;
    if (fare.origin.toLowerCase() != originKey) continue;
    if (fare.destination.toLowerCase() != destinationKey) continue;
    if (classKey != null && fare.fareClass.toLowerCase() != classKey) {
      continue;
    }
    return fare;
  }
  return null;
}

/// All verified fares for one company (empty when none verified).
List<OperatorFare> operatorFaresFor(String company) {
  final companyKey = company.trim().toLowerCase();
  return operatorFares
      .where((fare) => fare.company.toLowerCase() == companyKey)
      .toList();
}
