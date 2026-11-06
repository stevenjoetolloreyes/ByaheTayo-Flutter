// Unit tests for the vehicle-aware preview fare (no GoogleMap needed).
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/map_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview rate: bus modes use prov-aircon, others have none', () {
    expect(previewRateForVehicle(VehicleType.bus)?.id, 'prov-aircon');
    expect(previewRateForVehicle(VehicleType.anyVehicle)?.id, 'prov-aircon');
    expect(previewRateForVehicle(VehicleType.car), isNull);
    expect(previewRateForVehicle(VehicleType.motorcycle), isNull);
    expect(previewRateForVehicle(VehicleType.train), isNull);
  });

  test('preview labels follow the vehicle selection', () {
    expect(previewModeLabel(VehicleType.bus), 'Provincial bus');
    expect(previewModeLabel(VehicleType.anyVehicle), 'Transit route');
    expect(previewModeLabel(VehicleType.train), 'Train route');
    expect(previewModeLabel(VehicleType.car), 'Car route');
    expect(previewModeLabel(VehicleType.motorcycle), 'Motorcycle route');
  });

  test('user-verified fares win over the formula fare', () {
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicle: VehicleType.bus,
        roadKm: 168.7,
      ),
      60,
    );
    expect(
      resolveTransitFare(
        from: 'Vigan City',
        to: 'Cabugao',
        vehicle: VehicleType.bus,
        roadKm: 32.3,
      ),
      60,
    );
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'San Juan, Ilocos Sur',
        vehicle: VehicleType.anyVehicle,
        roadKm: 12.0,
      ),
      20,
    );
  });

  test('terminal pairs: verified ₱60, samples use the formula', () {
    // Cabugao ↔ Vigan Bus Terminal is the same verified ₱60 bus trip.
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Vigan Bus Terminal',
        vehicle: VehicleType.bus,
        roadKm: 31.6,
      ),
      60,
    );
    expect(
      resolveTransitFare(
        from: 'Vigan Bus Terminal',
        to: 'Cabugao',
        vehicle: VehicleType.bus,
        roadKm: 31.6,
      ),
      60,
    );
    // The ₱45 / ₱120 samples are NOT seeded: these pairs use the
    // LTFRB formula fare like every other unverified pair.
    // Terminal → San Juan, 25.3 km: 12 + ceil(20.3)×2.45 = 63.45,
    // raised by the ₱100 provincial-bus minimum.
    expect(
      resolveTransitFare(
        from: 'Vigan Bus Terminal',
        to: 'San Juan, Ilocos Sur',
        vehicle: VehicleType.bus,
        roadKm: 25.3,
      ),
      100,
    );
    // Laoag Terminal → Vigan Bus Terminal, 89.4 km:
    // 12 + ceil(84.4)×2.45 = ₱220.25.
    expect(
      resolveTransitFare(
        from: 'Laoag Terminal',
        to: 'Vigan Bus Terminal',
        vehicle: VehicleType.bus,
        roadKm: 89.4,
      ),
      closeTo(220.25, 0.001),
    );
  });

  test('Cabugao to Tuguegarao no longer uses the jeepney rate', () {
    // The reported bug: 168.7 km showed ₱344 = 14 + ceil(168.7-4)×2
    // (traditional jeepney). The provincial bus formula for the same
    // distance is 12 + ceil(168.7-5)×2.45 = ₱413.80.
    final tradJeep = fareRates.firstWhere((r) => r.id == 'trad-jeep');
    expect(computeFare(tradJeep, 168.7, false).regular, 344);
    final fixed = resolveTransitFare(
      from: 'Cabugao',
      to: 'Tuguegarao City',
      vehicle: VehicleType.bus,
      roadKm: 168.7,
    );
    expect(fixed, isNotNull);
    expect(fixed!, closeTo(413.80, 0.001));
    expect(fixed, isNot(344));
    // Any-vehicle previews resolve the same way; other modes show
    // 'No fare' (null) instead of an invented number.
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Tuguegarao City',
        vehicle: VehicleType.anyVehicle,
        roadKm: 168.7,
      ),
      closeTo(413.80, 0.001),
    );
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Tuguegarao City',
        vehicle: VehicleType.car,
        roadKm: 168.7,
      ),
      isNull,
    );
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Tuguegarao City',
        vehicle: VehicleType.motorcycle,
        roadKm: 168.7,
      ),
      isNull,
    );
    expect(
      resolveTransitFare(
        from: 'Cabugao',
        to: 'Tuguegarao City',
        vehicle: VehicleType.train,
        roadKm: 168.7,
      ),
      isNull,
    );
  });
}
