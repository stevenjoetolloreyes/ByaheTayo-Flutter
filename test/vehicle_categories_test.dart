import 'package:byahetayo/features/fares_tab.dart';
import 'package:byahetayo/features/vehicle_categories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the 8 categories have distinct ids, labels, and icons', () {
    expect(VehicleCategory.values.length, 8);
    final ids = VehicleCategory.values.map((c) => c.id).toSet();
    expect(ids.length, 8);
    final labels = VehicleCategory.values.map((c) => c.label).toSet();
    expect(labels.length, 8);
    final icons = VehicleCategory.values.map((c) => c.icon).toSet();
    expect(icons.length, 8);
    expect(
      VehicleCategory.values.map((c) => c.label).toList(),
      [
        'Modern Jeepney',
        'Traditional Jeepney',
        'Provincial Bus',
        'City Bus',
        'UV Express',
        'Van',
        'Tricycle',
        'Motorcycle Taxi',
      ],
    );
  });

  test('category rate mapping uses the table where it exists', () {
    FareRate? rate(VehicleCategory c) => rateForVehicleCategory(c);
    expect(rate(VehicleCategory.modernJeepney)?.id, 'modern-jeep');
    expect(rate(VehicleCategory.traditionalJeepney)?.id, 'trad-jeep');
    expect(rate(VehicleCategory.provincialBus)?.id, 'prov-aircon');
    expect(rate(VehicleCategory.cityBus)?.id, 'city-aircon');
    // UV Express, Van, Tricycle, Motorcycle Taxi have no table rate:
    // callers show 'No fare', never an invented number.
    expect(rate(VehicleCategory.uvExpress), isNull);
    expect(rate(VehicleCategory.van), isNull);
    expect(rate(VehicleCategory.tricycle), isNull);
    expect(rate(VehicleCategory.motorcycleTaxi), isNull);
  });

  test('legacy chip names map to categories for display only', () {
    expect(
      vehicleCategoryFromLegacy('Jeepney'),
      VehicleCategory.traditionalJeepney,
    );
    expect(
      vehicleCategoryFromLegacy('Modern Jeepney'),
      VehicleCategory.modernJeepney,
    );
    expect(
      vehicleCategoryFromLegacy('Bus'),
      VehicleCategory.provincialBus,
    );
    expect(
      vehicleCategoryFromLegacy('Tricycle'),
      VehicleCategory.tricycle,
    );
    expect(
      vehicleCategoryFromLegacy('E-jeep'),
      VehicleCategory.modernJeepney,
    );
    expect(vehicleCategoryFromLegacy('Other'), isNull);
    expect(vehicleCategoryById('modern-jeepney'), VehicleCategory.modernJeepney);
    expect(vehicleCategoryById('bogus'), isNull);
  });

  test('labels and icons pass unknown strings through safely', () {
    expect(vehicleLabel('Jeepney'), 'Traditional Jeepney');
    expect(vehicleLabel('Bus'), 'Provincial Bus');
    expect(vehicleLabel('Kalesa'), 'Kalesa');
    expect(vehicleIcon('Bus'), Icons.airport_shuttle);
    expect(vehicleIcon('Kalesa'), Icons.directions_transit);
    expect(rateForVehicleString('Bus')?.id, 'prov-aircon');
    expect(rateForVehicleString('Tricycle'), isNull);
    expect(rateForVehicleString('Kalesa'), isNull);
  });
}
