// Vehicle categories for the whole transportation system.
//
// The 8 categories below are the single source of truth for vehicle
// types shown in community posts/cards, route details, and the
// vehicle-aware preview fare. Each category has its own Material icon
// (no emoji) and, where the LTFRB table in fares_tab.dart has a rate,
// the rate id to compute with. Categories WITHOUT a table rate
// (UV Express, Van, Tricycle, Motorcycle Taxi) deliberately map to
// null: their fares are franchise/LGU-specific, so the UI shows the
// honest 'No fare' state instead of an invented number.
//
// Legacy community posts stored the old chip strings ('Jeepney',
// 'Modern Jeepney', 'Bus', 'Tricycle', 'E-jeep', 'Other'). Those
// strings are NOT rewritten in storage; the helpers below map them
// for display only, and unknown strings pass through verbatim.
import 'package:flutter/material.dart';

import 'fares_tab.dart';

/// The 8 vehicle categories.
enum VehicleCategory {
  modernJeepney,
  traditionalJeepney,
  provincialBus,
  cityBus,
  uvExpress,
  van,
  tricycle,
  motorcycleTaxi,
}

/// Static info per category: stable JSON id, display label, Material
/// icon, and the LTFRB table rate id (null = no table rate).
extension VehicleCategoryInfo on VehicleCategory {
  String get id {
    switch (this) {
      case VehicleCategory.modernJeepney:
        return 'modern-jeepney';
      case VehicleCategory.traditionalJeepney:
        return 'traditional-jeepney';
      case VehicleCategory.provincialBus:
        return 'provincial-bus';
      case VehicleCategory.cityBus:
        return 'city-bus';
      case VehicleCategory.uvExpress:
        return 'uv-express';
      case VehicleCategory.van:
        return 'van';
      case VehicleCategory.tricycle:
        return 'tricycle';
      case VehicleCategory.motorcycleTaxi:
        return 'motorcycle-taxi';
    }
  }

  String get label {
    switch (this) {
      case VehicleCategory.modernJeepney:
        return 'Modern Jeepney';
      case VehicleCategory.traditionalJeepney:
        return 'Traditional Jeepney';
      case VehicleCategory.provincialBus:
        return 'Provincial Bus';
      case VehicleCategory.cityBus:
        return 'City Bus';
      case VehicleCategory.uvExpress:
        return 'UV Express';
      case VehicleCategory.van:
        return 'Van';
      case VehicleCategory.tricycle:
        return 'Tricycle';
      case VehicleCategory.motorcycleTaxi:
        return 'Motorcycle Taxi';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleCategory.modernJeepney:
        return Icons.directions_bus;
      case VehicleCategory.traditionalJeepney:
        return Icons.directions_bus_outlined;
      case VehicleCategory.provincialBus:
        return Icons.airport_shuttle;
      case VehicleCategory.cityBus:
        return Icons.directions_bus_filled;
      case VehicleCategory.uvExpress:
        return Icons.directions_car;
      case VehicleCategory.van:
        return Icons.directions_car_filled;
      case VehicleCategory.tricycle:
        return Icons.two_wheeler;
      case VehicleCategory.motorcycleTaxi:
        return Icons.motorcycle;
    }
  }

  /// LTFRB table rate id, or null when the category has no table
  /// rate (UV Express, Van, Tricycle, Motorcycle Taxi).
  String? get rateId {
    switch (this) {
      case VehicleCategory.modernJeepney:
        return 'modern-jeep';
      case VehicleCategory.traditionalJeepney:
        return 'trad-jeep';
      case VehicleCategory.provincialBus:
        return 'prov-aircon';
      case VehicleCategory.cityBus:
        return 'city-aircon';
      case VehicleCategory.uvExpress:
      case VehicleCategory.van:
      case VehicleCategory.tricycle:
      case VehicleCategory.motorcycleTaxi:
        return null;
    }
  }
}

/// Category for a stored id, or null when the string is not a
/// category id.
VehicleCategory? vehicleCategoryById(String id) {
  for (final category in VehicleCategory.values) {
    if (category.id == id) return category;
  }
  return null;
}

/// Maps an old community chip string to its category. 'Other' and
/// anything unrecognized map to null (displayed verbatim).
VehicleCategory? vehicleCategoryFromLegacy(String name) {
  switch (name.trim()) {
    case 'Modern Jeepney':
      return VehicleCategory.modernJeepney;
    case 'Jeepney':
      return VehicleCategory.traditionalJeepney;
    case 'Bus':
      return VehicleCategory.provincialBus;
    case 'Tricycle':
      return VehicleCategory.tricycle;
    case 'E-jeep':
      return VehicleCategory.modernJeepney;
    default:
      return vehicleCategoryById(name.trim());
  }
}

/// Display label for a stored vehicle string: the category label when
/// known (id or legacy name), otherwise the raw string.
String vehicleLabel(String vehicle) {
  final category =
      vehicleCategoryById(vehicle) ?? vehicleCategoryFromLegacy(vehicle);
  return category?.label ?? vehicle;
}

/// Display icon for a stored vehicle string: the category icon when
/// known, otherwise a generic transit icon.
IconData vehicleIcon(String vehicle) {
  final category =
      vehicleCategoryById(vehicle) ?? vehicleCategoryFromLegacy(vehicle);
  return category?.icon ?? Icons.directions_transit;
}

/// LTFRB table rate for a category, or null when the category has no
/// table rate. Callers show 'No fare' for null — never a made-up rate.
FareRate? rateForVehicleCategory(VehicleCategory category) {
  final rateId = category.rateId;
  if (rateId == null) return null;
  for (final rate in fareRates) {
    if (rate.id == rateId) return rate;
  }
  return null;
}

/// LTFRB table rate for a stored vehicle string (id or legacy name),
/// or null when the vehicle has no table rate.
FareRate? rateForVehicleString(String vehicle) {
  final category =
      vehicleCategoryById(vehicle) ?? vehicleCategoryFromLegacy(vehicle);
  if (category == null) return null;
  return rateForVehicleCategory(category);
}
