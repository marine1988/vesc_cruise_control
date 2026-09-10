# VESC Cruise Control
Cruise control and a legal lock for a VESC without a display. Hold the throttle steady for the
hold time and the scooter keeps the speed, brake or move the throttle to cancel it. Stopped
with the brake held, two throttle blips limit speed and power for riding where that is required.

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
[WATCH] thr=1.457V ref=1.450V inj=1.450V brk=0.050V brkD=0.00 spd=18.0km/h active=1 lock=0 state=on cancel=none
```
```
[DEBUG] thr=1.457V ref=1.450V inj=1.642V brk=0.050V spd=17.6km/h state=on hold=0.0s last_cancel=none
```

- `thr` is the throttle **pin** in volts, `inj` is the voltage the script is feeding the ADC app
  while cruising (`ref` is the voltage the cruise holds, `brkD` the decoded brake the legal
  gesture needs to see).
- `active` is the cruise, `lock` the legal lock, `state` is `off`/`engaging`/`on`/`cancelling`
  and `cancel` the reason the last cruise ended (`brake`, `throttle_moved`, `speed_low`,
  `overspeed`, `script_restart`).
- The startup line says which switches the script was given: `Settings: cruise on legal gesture on
  debug off, one line per second on this terminal`.

While cruising, ADC1 is detached and overridden, so **the throttle pin and the injected voltage
are different by design**: letting the throttle go moves `thr` back to rest and that is normal.

## Legal lock
Stopped with the brake held, twist the throttle out twice. The motor beeps twice and the speed is
limited to 25 km/h and the power to 500 W. Do the same gesture again to go back to the normal
limits, the motor beeps once. Each blip and the limits that are about to be applied are printed on
the terminal.

The normal limits are read back from the VESC when the lock goes on and restored when it goes
off, so nothing has to be configured twice. **If those values do not read back as sane positive
numbers the lock refuses to engage** and beeps three times instead of storing a broken value that
the unlock would push back. **Nothing is written to flash**, so switching the scooter off clears
the lock. This also means a lock cannot be lost while the scooter is on.

Two motors: the same limits are sent to the other VESCs found on the CAN bus with `can-cmd`; the
line printed after each push says how many were found. That overwrites whatever those VESCs had,
so they should be set up with the same limits as the master. The gesture needs the brake to be
released before it fires again.

## How it works
The script watches the throttle voltage. While cruising it detaches ADC1 and overrides it with
the voltage that holds the speed, so the ADC app keeps doing the mapping, ramping and current
limits and a master with multiple VESCs keeps forwarding to the slave. The loop corrects the
voltage from the speed error, never more than 0.8 V away from where the throttle was.

The override only reaches the motor while the script keeps sending it, so a crashed script stops
the motor instead of leaving it running at a fixed speed.

**Important:** ADC1 stays detached after canceling cruise, so the throttle works again only
after the script reattaches it. The script reattaches on cancel and on start-up.

## Status
The LispBM, the settings round trip and the package build are tested. The behaviour on a real
scooter is not, so start with a low **Min Speed** and a high **Max Speed** and try it at low
speed first.
