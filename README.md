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
- **Debug**: prints a line per second and a line per event (tap, cruise on and off, limits applied)
  on the VESC Tool terminal. **Leave it off on a scooter with a display wired to the UART**, see
  below

The state of the cruise is shown at the bottom of the app UI, together with the reason the last
cruise ended.

## Log
With **Debug on** the script prints one line per second on the VESC Tool terminal (LispBM page),
plus a line per event:

```
[DEBUG] thr=1.457V ref=1.450V inj=1.642V brk=0.050V brkD=0.00 brake=0 spd=17.6km/h state=on hold=0.0s last_cancel=none legal=1 taps=0 locked=0
```

- `thr` is the throttle **pin** in volts, `inj` the voltage the script is feeding the ADC app while
  cruising (`ref` is the voltage the cruise holds).
- `brk` is the brake **pin** in volts, `brkD` the decoded brake and `brake` whether the script
  counts it as pressed. **Either signal counts**, so a brake switch works even when the ADC2
  mapping was never configured - which is what makes the pin worth watching.
- `legal` is the gesture switch, `taps` how many brake taps it has counted, `locked` the lock
  itself. Each tap prints `Legal gesture, tap N` on its own line, so a gesture that is not being
  seen is visible at once.
- `state` is `off`/`engaging`/`on`/`cancelling` and `last_cancel` the reason the last cruise ended
  (`brake`, `throttle_moved`, `speed_low`, `overspeed`, `script_restart`).
- With **Debug off** the script prints nothing, except at load: the ADC control type, a warning
  when that control type cannot drive the motor, and the switches it was given, for example
  `Settings: cruise on legal gesture on debug off, debug lines on this terminal`.

While cruising, ADC1 is detached and overridden, so **the throttle pin and the injected voltage
are different by design**: letting the throttle go moves `thr` back to rest and that is normal.

## Displays on the UART
A display (Davega style) polls the VESC over the UART and expects a reply to what it asks. LispBM's
`print` and `send-data` have **no fixed target**: the firmware sends them to the port that spoke
last - `commands_process_packet` sets `send_func = reply_func` for every packet it receives - and a
display that polls constantly is that port. Anything the script prints or sends unprompted goes out
**to the display**, as packets it never asked for. A display that mis-parses those shows wrong speed
and temperature until the next good reply, and a 130 character line also holds the UART for about
11 ms at 115200, which can push its replies past their timeout.

That is why the script never talks on its own. It answers the App UI, and a reply leaves by the port
that asked, so it reaches VESC Tool and not the display. With a display installed keep **Debug
off**, and turn it on only to diagnose, expecting the display to act up while it is on.

If VESC Tool is connected over **USB** there is a target that is always safe: `send-data` takes an
interface argument (`(send-data data 1)` goes to USB only, see `lispif_vesc_extensions.c`).

## Legal lock
Stopped, tap the brake five times within five seconds. The motor beeps three times and the speed
is limited to 25 km/h and the power to 500 W. The same gesture gives the normal limits back, the
motor beeps once. Each tap and the limits that are about to be applied are printed on the terminal
with **Debug** on.

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

## Notes for changes
- The App UI is in English.
- **The script never talks unprompted.** `print` and `send-data` go out the port that spoke last, so
  anything pushed on its own reaches a display on the UART as a packet it did not ask for. Send only
  in reply to the UI, or with `send-data`'s interface argument (1 = USB).
- Beeps: one long when cruise engages, two short when it cancels, three short when the legal lock
  engages, one short when it releases, four short when it refuses. **No beep is slept through while
  cruise holds the speed**: the ADC1 override has to keep being sent, and half a second of sleep
  would let the timeout stop the motor. `tone` starts a beep and `tone-service` stops it from the
  control loop.
- Gestures have to work with the brake alone, see above.
- The gesture fires on a **rising edge** of the brake with an 80 ms debounce, so switch chatter
  does not count as taps; a burst that runs past its window is dropped rather than completed.

## Status
The LispBM, the settings round trip and the package build are tested. The behaviour on a real
scooter is not, so start with a low **Min Speed** and a high **Max Speed** and try it at low
speed first.
