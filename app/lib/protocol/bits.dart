// Little-endian bitfield helpers matching the GCC bitfield layout used by IRremoteESP8266.

import 'dart:typed_data';

extension Bits on Uint8List {
  /// Set a field of [nbits] starting at bit [bit] of byte [byte] (may span bytes).
  void setBits(int byte, int bit, int nbits, int value) {
    final start = byte * 8 + bit;
    for (var i = 0; i < nbits; i++) {
      final pos = start + i;
      final mask = 1 << (pos % 8);
      if ((value >> i) & 1 == 1) {
        this[pos ~/ 8] |= mask;
      } else {
        this[pos ~/ 8] &= ~mask & 0xFF;
      }
    }
  }

  int getBits(int byte, int bit, int nbits) {
    final start = byte * 8 + bit;
    var out = 0;
    for (var i = 0; i < nbits; i++) {
      final pos = start + i;
      if ((this[pos ~/ 8] >> (pos % 8)) & 1 == 1) out |= 1 << i;
    }
    return out;
  }

  void put(int i, int v) => this[i] = v & 0xFF;

  String get hex => map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
}

int sumBytes(Uint8List data, int from, int length, [int init = 0]) {
  var s = init;
  for (var i = from; i < from + length; i++) {
    s += data[i];
  }
  return s & 0xFF;
}

int sumNibbles(Uint8List data, int from, int length, [int init = 0]) {
  var s = init;
  for (var i = from; i < from + length; i++) {
    s += (data[i] >> 4) + (data[i] & 0xF);
  }
  return s & 0xFF;
}

int toBcd(int v) => ((v ~/ 10) << 4) + (v % 10);

Uint8List bytesOf(List<int> v) => Uint8List.fromList(v);

int clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);
