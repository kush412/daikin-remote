// Daikin IR bridge.
//
// The iOS app does all the Daikin encoding (see ios/DaikinCore) and sends the finished
// mark/space pattern here; the bridge only transmits it, so it never needs updating when the
// app learns a new protocol. It also keeps on/off timers for ACs without a built-in IR timer.
//
// HTTP API (port 80, plain text):
//   GET    /info            -> {"device":"daikin-ir-bridge","version":1,"timers":{"on":S,"off":S}}
//                              S = seconds until the timer fires, or -1 if none.
//   POST   /send            body: "<freqHz> <mark> <space> <mark> ..." -> sends it now
//   POST   /timer/on?in=S   same body; sends it in S seconds (also /timer/off)
//   DELETE /timer/on        cancels it (also /timer/off)

#include <Arduino.h>
#include <IRremoteESP8266.h>
#include <IRsend.h>

#if defined(ESP32)
#include <ESPmDNS.h>
#include <WebServer.h>
#include <WiFi.h>
using HttpServer = WebServer;
#else
#include <ESP8266WebServer.h>
#include <ESP8266WiFi.h>
#include <ESP8266mDNS.h>
using HttpServer = ESP8266WebServer;
#endif

#if __has_include("secrets.h")
#include "secrets.h"
#else
#error "Copy include/secrets.example.h to include/secrets.h and set your Wi-Fi."
#endif

// GPIO driving the IR LED (through a transistor). GPIO4 is D2 on a D1 mini.
#ifndef IR_PIN
#define IR_PIN 4
#endif
#define HOSTNAME "daikin-ir"
#define MAX_PULSES 1024

namespace {

struct Pattern {
  uint32_t freq = 0;
  uint32_t pulses[MAX_PULSES];
  uint16_t count = 0;
};

struct Timer {
  bool armed = false;
  uint32_t startMs = 0;
  uint32_t delayMs = 0;
  Pattern pattern;
};

IRsend ir(IR_PIN);
HttpServer server(80);
Timer timers[2];  // 0 = on, 1 = off
Pattern scratch;

// Parses "<freq> <p1> <p2> ...", separated by spaces, commas or newlines.
bool parsePattern(const String &body, Pattern &out, String &error) {
  const char *p = body.c_str();
  char *end;
  out.count = 0;
  out.freq = strtoul(p, &end, 10);
  if (end == p || out.freq < 30000 || out.freq > 60000) {
    error = "bad frequency";
    return false;
  }
  p = end;
  while (true) {
    while (*p == ' ' || *p == ',' || *p == '\n' || *p == '\r' || *p == '\t') p++;
    if (*p == '\0') break;
    unsigned long v = strtoul(p, &end, 10);
    if (end == p || v == 0 || v > 1000000) {
      error = "bad pulse";
      return false;
    }
    if (out.count >= MAX_PULSES) {
      error = "too many pulses";
      return false;
    }
    out.pulses[out.count++] = v;
    p = end;
  }
  if (out.count == 0) {
    error = "empty pattern";
    return false;
  }
  return true;
}

void transmit(const Pattern &pat) {
  ir.enableIROut(pat.freq);
  for (uint16_t i = 0; i < pat.count; i++) {
    uint32_t us = pat.pulses[i];
    if (i % 2 == 0) {
      // mark() takes 16 bits; Daikin marks are far shorter, but split just in case.
      while (us > 0) {
        uint16_t chunk = us > 60000 ? 60000 : us;
        ir.mark(chunk);
        us -= chunk;
      }
    } else {
      ir.space(us);
    }
  }
  ir.space(0);  // LED off.
}

long remainingSeconds(const Timer &t) {
  if (!t.armed) return -1;
  uint32_t elapsed = millis() - t.startMs;
  if (elapsed >= t.delayMs) return 0;
  return (t.delayMs - elapsed + 999) / 1000;
}

void handleInfo() {
  String json = "{\"device\":\"daikin-ir-bridge\",\"version\":1,\"timers\":{\"on\":";
  json += remainingSeconds(timers[0]);
  json += ",\"off\":";
  json += remainingSeconds(timers[1]);
  json += "}}";
  server.send(200, "application/json", json);
}

void handleSend() {
  String error;
  if (!parsePattern(server.arg("plain"), scratch, error)) {
    server.send(400, "text/plain", error);
    return;
  }
  transmit(scratch);
  server.send(200, "text/plain", "ok");
}

void handleTimer(int slot) {
  Timer &t = timers[slot];
  if (server.method() == HTTP_DELETE) {
    t.armed = false;
    server.send(200, "text/plain", "ok");
    return;
  }
  long seconds = server.arg("in").toInt();
  if (seconds <= 0 || seconds > 7L * 24 * 3600) {
    server.send(400, "text/plain", "bad 'in'");
    return;
  }
  String error;
  t.armed = false;
  if (!parsePattern(server.arg("plain"), t.pattern, error)) {
    server.send(400, "text/plain", error);
    return;
  }
  t.startMs = millis();
  t.delayMs = (uint32_t)seconds * 1000;
  t.armed = true;
  server.send(200, "text/plain", "ok");
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
#if defined(ESP32)
  WiFi.setHostname(HOSTNAME);
#else
  WiFi.hostname(HOSTNAME);
#endif
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to " WIFI_SSID);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.printf("\nConnected: http://%s.local  (%s)\n", HOSTNAME, WiFi.localIP().toString().c_str());
}

}  // namespace

void setup() {
  Serial.begin(115200);
  ir.begin();
  connectWifi();

  if (MDNS.begin(HOSTNAME)) MDNS.addService("http", "tcp", 80);

  server.on("/info", HTTP_GET, handleInfo);
  server.on("/send", HTTP_POST, handleSend);
  server.on("/timer/on", [] { handleTimer(0); });
  server.on("/timer/off", [] { handleTimer(1); });
  server.onNotFound([] { server.send(404, "text/plain", "not found"); });
  server.begin();
}

void loop() {
  server.handleClient();
#if !defined(ESP32)
  MDNS.update();
#endif
  for (Timer &t : timers) {
    if (t.armed && millis() - t.startMs >= t.delayMs) {
      t.armed = false;
      transmit(t.pattern);
    }
  }
}
