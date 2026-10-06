import 'dart:typed_data';

/// A ready-to-send IR frame: carrier frequency and alternating mark/space durations in µs,
/// starting with a mark.
class IrFrame {
  const IrFrame(this.frequencyHz, this.pattern);
  final int frequencyHz;
  final List<int> pattern;

  @override
  bool operator ==(Object other) =>
      other is IrFrame && other.frequencyHz == frequencyHz && _listEquals(other.pattern, pattern);

  @override
  int get hashCode => Object.hash(frequencyHz, Object.hashAll(pattern));
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class BitTiming {
  const BitTiming(this.hdrMark, this.hdrSpace, this.bitMark, this.oneSpace, this.zeroSpace, this.gap);
  final int hdrMark;
  final int hdrSpace;
  final int bitMark;
  final int oneSpace;
  final int zeroSpace;
  final int gap;
}

/// Builds a mark/space pattern. Mirrors IRremoteESP8266's `IRsend::sendGeneric` with LSB-first
/// byte order.
class PulseBuilder {
  final _pulses = <int>[];

  void mark(int us) => _add(us, isMark: true);

  void space(int us) => _add(us, isMark: false);

  /// Header (optional) + bytes LSB first + footer mark + gap. Zero header values are skipped.
  void section(
    BitTiming timing,
    Uint8List data, {
    int from = 0,
    int? length,
    int? hdrMark,
    int? hdrSpace,
    int? footerMark,
    int? gap,
  }) {
    mark(hdrMark ?? timing.hdrMark);
    space(hdrSpace ?? timing.hdrSpace);
    final end = from + (length ?? data.length - from);
    for (var i = from; i < end; i++) {
      final b = data[i];
      for (var bit = 0; bit < 8; bit++) {
        _bit(timing, (b >> bit) & 1 == 1);
      }
    }
    mark(footerMark ?? timing.bitMark);
    space(gap ?? timing.gap);
  }

  /// [count] zero bits with no header, then footer mark + gap (the Daikin "leader").
  void zeroBits(BitTiming timing, int count, int gap) {
    for (var i = 0; i < count; i++) {
      _bit(timing, false);
    }
    mark(timing.bitMark);
    space(gap);
  }

  void _bit(BitTiming t, bool one) {
    mark(t.bitMark);
    space(one ? t.oneSpace : t.zeroSpace);
  }

  // Merges consecutive marks/spaces so the pattern always alternates.
  void _add(int us, {required bool isMark}) {
    if (us <= 0) return;
    if (_pulses.isEmpty && !isMark) return;
    final lastIsMark = _pulses.length.isOdd;
    if (_pulses.isNotEmpty && lastIsMark == isMark) {
      _pulses[_pulses.length - 1] += us;
    } else {
      _pulses.add(us);
    }
  }

  List<int> build() => List.unmodifiable(_pulses);
}
