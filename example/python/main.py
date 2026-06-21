from arduino.app_utils import *
import time

led_state = False

interval = 1.0

def set_interval(new_interval):
    global interval
    interval = new_interval

Bridge.provide("set_interval", set_interval)

def loop():
    led_state
    interval
    time.sleep(interval)
    led_state = not led_state
    Bridge.call("set_led_state", led_state)

App.run(user_loop=loop)