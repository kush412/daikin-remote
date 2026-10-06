import 'daikin128.dart';
import 'daikin2.dart';
import 'daikin280.dart';
import 'daikin312.dart';
import 'daikin_protocol.dart';
import 'daikin_simple.dart';

export 'ac_state.dart';
export 'daikin_protocol.dart';
export 'pulse_builder.dart';

/// All supported protocols, most common first (the order the picker lists them in).
abstract final class Protocols {
  static const List<DaikinProtocol> all = [
    Daikin280(),
    Daikin2(),
    Daikin312(),
    Daikin216(),
    Daikin160(),
    Daikin152(),
    Daikin176(),
    Daikin128(),
    Daikin64(),
  ];

  static DaikinProtocol byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}
