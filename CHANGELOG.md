# Changelog

Only the versions meant to be installed have a release with the built package attached: **1.6**
(the one on the scooter) and **1.10** (the same behaviour, this documentation). Versions 1.7 and
1.8 were attempts at the display problem that were reverted, and 1.0 to 1.5 are the steps that led
up to 1.6.

## 1.10 — released
Same script and UI as 1.6 and 1.9. The README now says that 1.6 runs on the scooter and the cruise
control works there, that the legal lock gesture is still to be confirmed on the road, and where
the built packages live.

## 1.9 — released
Same script and UI as 1.6, byte for byte. What changed is this README: how a display on the UART
receives the script's output (`commands.c:216` sets the reply function to the port that spoke
last), and that a beep is the motor being modulated, which can show up as a jump in speed or
temperature.

## 1.8 — reverted
No tag packet on the state reply, and the UI stopped polling once it was closed. The display
glitch got worse, with values jumping to 83 km/h, so it was reverted.

## 1.7 — reverted
The script stopped printing unless Debug was on, and the App UI asked for the state instead. It
did not improve the display glitch, so it was reverted.

## 1.6 — released, and the version running on the scooter
The UI is in English. One long beep when the cruise takes over, two short when it lets go, played
by the control loop rather than slept through.

## 1.5
README: the gesture is five brake taps, not throttle blips.

## 1.4
Five brake taps inside five seconds toggle the legal lock, only with the scooter stopped.

## 1.3
The legal gesture arms on a brake tap, and the throttle blips come after it.

## 1.2
The brake is counted from the pin as well as from the decoded value, so a cancel works even when
the ADC2 mapping is not configured.

## 1.1
The version is part of the built package name.

## 1.0
First package: hold the throttle to keep the speed, cancel on the brake or on a moved throttle, a
legal lock, and the state on the App UI.
