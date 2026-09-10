# VESC Cruise Control
Cruise control and a legal lock for a VESC without a display. Hold the throttle steady for the
hold time and the scooter keeps the speed, brake or move the throttle to cancel it. Stopped, five
brake taps limit speed and power for riding where that is required.

Settings are made in the App UI and stored in the VESC, so nothing has to be reflashed when
they change.

## Installation
1. Open VESC Tool and connect to your VESC over Bluetooth, USB or WiFi.
2. Go to **VESC Packages** and press **Update Archive**.
3. Select **VESC Cruise Control** under **Applications** and press **Install**.
4. Open the App UI (VESC Tool -> Navigation Bar -> App UI), set the values and press **Save**.
5. Set up the ADC app, see below.

Requires VESC firmware 7.00.

## ADC Setup
The script drives the motor through the ADC app, so it has to be set up once:

- **App Settings -> General**: set **APP to Use** to `ADC`, then **Write**
- **App Settings -> ADC -> General**: **Control Type** `Current`, **Use Filter** `True`, **Safe Start** `Regular`, **Update Rate** `1000 Hz`, **Multiple VESCs Over CAN** on when a second VESC drives the other wheel
- **App Settings -> ADC -> Mapping**: open **ADC Mapping**, pull throttle and brake through their full range, then **Apply and Write**

Two motors: install the package on the master only, turn on **Multiple VESCs Over CAN** and
keep the slave without an app. The master sends the same command to the slave over CAN.

## Wiring
Throttle to ADC1, brake to ADC2 of the VESC, both against GND. The values below are in volts
on those pins.

## Brake and throttle at the same time
**The brake switch cuts the throttle signal.** With the brake held the throttle pin reads about
0.01 V even with the grip fully open, and with the brake released the same grip reads about 3.24 V:

```
[DEBUG] thr=0.012V ref=0.000V inj=0.609V brk=3.254V spd=-0.0km/h state=off hold=0.0s last_cancel=throttle_moved
[DEBUG] thr=3.243V ref=3.247V inj=0.609V brk=0.001V spd=20.5km/h state=engaging hold=0.1s last_cancel=throttle_moved
```

`thr` is read straight off ADC1, so that is the signal collapsing **at the pin**, not something the
script does. Whatever the scooter's wiring and controller do to the throttle line while the brake
is pulled, the throttle cannot be read at the same time as the brake. What follows from it:

- **A gesture that has to read the throttle while the brake is held can never fire.** The legal
  lock is five brake taps for that reason, and not brake plus throttle blips.
- **The brake is counted from its pin as well as from the ADC2 mapping**, so the script still sees
  it when the mapping was never configured - otherwise cruise would not cancel on a brake either.

To tell a brake that is not wired from a script that is not running, look at those two fields: with
the brake held `brk` goes to about 3 V and `brake` reads 1. If `brake` stays 0 with the lever
pulled, the signal is not reaching the VESC and no change to the script will help.

## Settings
- **Cruise Control**: turns the cruise control on or off
- **Hold Time (s)**: how long the throttle has to stay steady before cruise engages
- **Deadband (V)**: how far the throttle may move before it counts as moved. Raise it if cruise does not engage, lower it if releasing the throttle cancels the cruise
- **Min Speed (km/h)**: cruise does not engage below this speed
- **Max Speed (km/h)**: cruise does not engage above this speed. If the speed passes it while cruising, cruise is cancelled after 3 seconds
- **Legal Lock**: turns the legal lock gesture on or off. The speed and the power it applies are fixed at 25 km/h and 500 W
- **Debug**: prints the longer line per second on the VESC Tool terminal while the script runs

The state of the cruise is shown at the bottom of the app UI, together with the reason the last
cruise ended.

## Log
The script prints **one line per second** on the VESC Tool terminal (LispBM page), debug switch or
not:

```
[WATCH] thr=1.457V ref=1.450V inj=1.450V brk=0.050V brkD=0.00 spd=18.0km/h active=1 lock=0 legal=1 taps=0 state=on cancel=none
[DEBUG] thr=1.457V ref=1.450V inj=1.642V brk=0.050V brkD=0.00 brake=0 spd=17.6km/h state=on hold=0.0s last_cancel=none legal=1 taps=0 locked=0
```

- `thr` is the throttle **pin** in volts, `inj` is the voltage the script is feeding the ADC app
  while cruising (`ref` is the voltage the cruise holds).
- `brk` is the brake **pin** in volts, `brkD` the decoded brake and `brake` whether the script
  counts it as pressed. **Either signal counts**, so a brake switch works even when the ADC2
  mapping was never configured - which is what makes the pin worth watching.
- `legal` is the gesture switch, `taps` how many brake taps it has counted, `locked` the lock
  itself. Each tap prints `Legal gesture, tap N` on its own line, so a gesture that is not being
  seen is visible at once.
- `active` is the cruise, `lock` the legal lock, `state` is `off`/`engaging`/`on`/`cancelling`
  and `cancel` the reason the last cruise ended (`brake`, `throttle_moved`, `speed_low`,
  `overspeed`, `script_restart`).
- The startup line says which switches the script was given: `Settings: cruise on legal gesture on
  debug off, one line per second on this terminal`.

While cruising, ADC1 is detached and overridden, so **the throttle pin and the injected voltage
are different by design**: letting the throttle go moves `thr` back to rest and that is normal.

## Legal lock
Stopped, tap the brake five times within five seconds. The motor beeps three times and the speed
is limited to 25 km/h and the power to 500 W. The same gesture gives the normal limits back, the
motor beeps once. Each tap and the limits that are about to be applied are printed on the
terminal.

The gesture is brake taps only: on a scooter whose brake switch cuts the throttle signal the
throttle pin reads zero while the brake is held, so the throttle cannot be part of it. Five taps
are deliberate enough not to happen by accident, and the scooter has to stand still, so the lock
is engaged and released parked. A burst that takes longer than the window is forgotten, so a tap
after a pause starts a new count instead of finishing the old one.

The normal limits are read back from the VESC when the lock goes on and restored when it goes
off, so nothing has to be configured twice. **If those values do not read back as sane positive
numbers the lock refuses to engage** and beeps four times instead of storing a broken value that
the unlock would push back. **Nothing is written to flash**, so switching the scooter off clears
the lock. This also means a lock cannot be lost while the scooter is on.

Two motors: the same limits are sent to the other VESCs found on the CAN bus with `can-cmd`; the
line printed after each push says how many were found. That overwrites whatever those VESCs had,
so they should be set up with the same limits as the master. The scooter has to stand still, and
the brake has to be released and tapped again before the gesture fires again.

## Beeps
| Event | Beeps |
|---|---|
| Cruise engages | one long |
| Cruise cancels | two short |
| Legal lock engages | three short |
| Legal lock releases | one short |
| Legal lock refused | four short |

The long beep is started by the loop and stopped by it a moment later rather than slept through:
while cruise holds the speed the ADC1 override has to keep being sent, and sleeping through a
beep would let the timeout stop the motor.

## How it works
The script watches the throttle voltage. While cruising it detaches ADC1 and overrides it with
the voltage that holds the speed, so the ADC app keeps doing the mapping, ramping and current
limits and a master with multiple VESCs keeps forwarding to the slave. The loop corrects the
voltage from the speed error, never more than 0.8 V away from where the throttle was.

The override only reaches the motor while the script keeps sending it, so a crashed script stops
the motor instead of leaving it running at a fixed speed.

**Important:** ADC1 stays detached after canceling cruise, so the throttle works again only
after the script reattaches it. The script reattaches on cancel and on start-up.

## Display on the UART (observations)
A display on the UART (Davega style) was reported to show wrong speed and temperature while this
package was installed, and only with this package. Two things in the package reach that display's
world, both read off the firmware source:

1. **`print` and `send-data` have no fixed target.** `commands_process_packet` sets
   `send_func = reply_func` for every packet it receives, and the UART app registers its own port as
   the reply function, so with a display polling on that UART the script's output goes out to the
   display as packets it never asked for.
2. **A beep is not a buzzer.** `foc-play-tone` points the controller at an audio table and modulates
   the motor to make the sound, and `mcpwm_foc_play_tone` (`mcpwm_foc.c`) puts the controller into
   the running state when it was idle. A beep can therefore appear as a jump in speed or
   temperature.

The code here is back at the behaviour of version 1.6, where both were left as they are: one log
line per second plus one state packet per second, and beeps at every event. The changes that would
have silenced both (a debug-gated log, no state push, the App UI asking for the state, no tag
packet) were reverted: they did not demonstrably help, and one of them made it worse.

What to try next, one at a time so each can be told apart:
- **The beeps.** Shorten the tone (150 ms to 250 ms), drop its voltage, or put them behind a switch,
  and see whether what the display gets wrong lines up with a beep.
- **A log line only with Debug on.** Then with Debug off the script sends nothing per second.
- **`send-data` with an interface.** `(send-data data 1)` goes out USB only
  (`lispif_vesc_extensions.c`), which a display on the UART never sees.

## Notes for changes
- The App UI is in English.
- Beeps: one long when cruise engages, two short when it cancels, three short when the legal lock
  engages, one short when it releases, four short when it refuses. **No beep is slept through while
  cruise holds the speed**: the ADC1 override has to keep being sent, and half a second of sleep
  would let the timeout stop the motor. `tone` starts a beep and `tone-service` stops it from the
  control loop.
- Gestures have to work with the brake alone, see above.
- The gesture fires on a **rising edge** of the brake with an 80 ms debounce, so switch chatter
  does not count as taps; a burst that runs past its window is dropped rather than completed.

## Status
The LispBM, the settings round trip and the package build are tested. Version 1.6 runs on the
scooter and the cruise control works there: it takes over in the speed range it should, it lets go
when the brake is used, and the beeps are heard. The legal lock gesture and the display notes above
are still to be confirmed on the road.

Start with a low **Min Speed** and a high **Max Speed** and try it at low speed first.

Releases carry the built package: <https://github.com/marine1988/vesc_cruise_control/releases>
