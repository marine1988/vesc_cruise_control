# VESC Cruise Control
Cruise control for a VESC without a display. Hold the throttle steady for the hold time and
the scooter keeps the speed, brake or move the throttle to cancel it.

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
- **Cruise Control**: turns the whole thing on or off
- **Hold Time (s)**: how long the throttle has to stay steady before cruise engages
- **Deadband (V)**: how much throttle jitter still counts as steady. Raise it if cruise does not engage
- **Min Speed (km/h)**: cruise does not engage below this speed
- **Max Speed (km/h)**: cruise does not engage above this speed. If the speed goes above it while cruising, cruise stays on

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
