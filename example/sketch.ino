#include "Arduino_RouterBridge.h"

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
    Bridge.provide("read_sensor", read_sensor);
}

void loop() {
    Bridge.call("mcuCall", "Hello from MCU!");
    delay(1000);
}

void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}

// connect a potentiometer to VCC (3.3V) and GND, and the wiper to A0
int read_sensor() {
    return analogRead(A0);
}