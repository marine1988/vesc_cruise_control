; VESC Cruise Control
; Throttle on ADC1, brake on ADC2. Hold the throttle steady for the hold time to engage, a brake
; or a pull on the throttle past the reference cancels it. Letting the throttle go is normal
; while cruising: the ADC is overridden there, so the physical pin dropping back to rest is the
; rider handing the speed over, not a request to stop.
;
; Legal lock: stopped, five brake taps inside five seconds limit the speed to 25 km/h and the
; power to 500 W. It lasts until the scooter is switched off, nothing is written to flash and the
; limits are pushed to the other VESCs on the CAN bus. The limits that were in the VESC are read
; back before locking and put back on unlocking; if they read as a broken value the lock refuses
; to engage rather than storing it.
;
; A line is printed once per second whether or not debug mode is on, so a ride can be read back
; from the VESC Tool terminal; debug mode prints the longer line with the reference, the
; injected voltage and the hold time.
;
; Needs the ADC app. While cruising, ADC1 is detached and overridden with the voltage that
; holds the speed, so the app keeps doing the mapping, ramping and limits, and a master with
; Multiple VESCs over CAN keeps sending the same command to the slaves.

@const-start

(def settings-version 102i32)

; Persistent settings: (label . (eeprom-offset type))
; Offsets 6 and 7 used to hold the legal speed and power, they are now the legal lock and the
; debug switches. The version bump makes the defaults write over them once.
(def eeprom-addrs '(
    (ver-code             . (0 i))
    (cruise-enabled       . (1 b))
    (cruise-hold-sec      . (2 f))
    (cruise-deadband      . (3 f))
    (cruise-min-speed-kmh . (4 f))
    (cruise-max-speed-kmh . (5 f))
    (legal-enabled        . (6 b))
    (debug-enabled        . (7 b))
))

; Cruise control
(def cruise-enabled true)
(def cruise-hold-sec 5.0)
(def cruise-deadband 0.10)  ; volts of throttle jitter that still count as held
(def cruise-min-speed 0.0)  ; m/s, only checked while engaging
(def cruise-max-speed 0.0)

; Legal lock, fixed by design, they are not settings
(def legal-speed-kmh 25.0)
(def legal-speed 6.9444) ; m/s, 25 km/h
(def legal-watt 500.0)

; Switches that come from the settings
(def legal-enabled false)
(def debug-enabled false)

; Decoded values are 0 to 1, 0 is released
(def brake-on 0.10)     ; decoded brake, 0 to 1
; A switch brake pulls the pin high whatever the ADC2 mapping says, and the mapping is the part
; that is easy to leave unconfigured. Either signal counts as a brake.
(def brake-raw-on 1.5)  ; volts on the brake pin
(def thr-min 0.10)     ; throttle below this is not riding
; The gesture is brake taps. The brake switch cuts the throttle signal, so the throttle cannot be
; part of a gesture that happens while braking.
(def taps-needed 5)
(def tap-window-ms 5000)   ; the taps have to fit in this, counted from the first one
(def tap-debounce-ms 80)   ; anything shorter than this is switch chatter, not a tap

(def cruise-hz 50)
(def cruise-kp 0.25)   ; volts per m/s
(def cruise-ki 0.10)   ; volts per m/s per second
(def cruise-range 0.8) ; how many volts the hold may add or take away
(def stop-speed (/ 1.0 3.6))
(def cruise-low-ms 2000)   ; below the stop speed for this long cancels cruise
(def cruise-high-ms 3000)  ; above the max speed for this long cancels cruise
(def cruise-high-margin 1.15) ; a little over the max speed is not an overspeed
(def cancelling-ms 600)    ; keep the state on the screen after a cancel
(def debug-divider 50)     ; one debug line per second at 50 Hz

; (systime) counts CH_CFG_ST_FREQUENCY ticks per second (10000 on this firmware), it is not in
; milliseconds. Keeping the times above in seconds/milliseconds and converting here is what the
; firmware itself does in UTILS_AGE_S; without it every timeout below is ten times too short.
(def ticks-per-sec 10000.0)
(def ticks-per-ms 10)

; A cruise that has just taken over must not be cancelled by the throttle: the ADC filter is
; still settling and the rider is about to let the throttle go. Releasing the throttle is not a
; "throttle moved", only pulling it past the reference is; the tick counter filters pin noise.
(def cruise-arm-ms 800)
(def cruise-arm-time 0)
(def cruise-moved-ticks 10) ; 200 ms at 50 Hz, a shorter spike on the pin is noise
(def cruise-moved-count 0)

(def cruise-active false)
(def tone-stop 0) ; systime when the running beep has to stop, 0 when none is playing
(def cruise-thr-ref 0.0)
(def cruise-volts 0.0)
(def cruise-target 0.0)
(def cruise-integral 0.0)
(def cruise-hold-start 0)
(def cruise-low-start 0)
(def cruise-high-start 0)
(def cruise-state 'off)
(def cruise-state-time 0)
(def last-cancel 'none)
(def loop-counter 0)

(def legal false)
(def legal-saved-speed 0.0)
(def legal-saved-watt 0.0)
(def legal-taps 0)
(def legal-tap-first 0)
(def legal-tap-last 0)
(def legal-brake-seen false)

(defun read-setting (name)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (eeprom-read-i addr))
            ((eq type 'f) (eeprom-read-f addr))
            ((eq type 'b) (eq (eeprom-read-i addr) 1i32)) ; an offset never written reads nil
)))

; Each store locks the system while it writes flash, so only touch changed values.
; Types must match before comparing, an eeprom read is i32/float and the UI sends plain ints.
(defun write-setting (name val)
    (let (
            (addr (first (assoc eeprom-addrs name)))
            (type (second (assoc eeprom-addrs name)))
        )
        (cond
            ((eq type 'i) (let ((new (to-i32 val)))
                (if (not-eq (eeprom-read-i addr) new) (eeprom-store-i addr new))))
            ((eq type 'f) (let ((new (to-float val)))
                (if (not-eq (eeprom-read-f addr) new) (eeprom-store-f addr new))))
            ((eq type 'b) (let ((new (if val 1i32 0i32)))
                (if (not-eq (eeprom-read-i addr) new) (eeprom-store-i addr new))))
)))

; Symbols come out as plain text on the terminal and over send-data
(defun sym-name (sym)
    (cond
        ((eq sym 'off) "off")
        ((eq sym 'engaging) "engaging")
        ((eq sym 'on) "on")
        ((eq sym 'cancelling) "cancelling")
        ((eq sym 'brake) "brake")
        ((eq sym 'throttle_moved) "throttle_moved")
        ((eq sym 'speed_low) "speed_low")
        ((eq sym 'overspeed) "overspeed")
        ((eq sym 'script_restart) "script_restart")
        ((eq sym 'none) "none")
        (t "unknown")
))

; Every line the script writes goes through here, and nothing is written unless the debug switch is
; on. The LispBM print goes out the port that spoke last, and on a scooter with a display on the
; UART that port is the display: a packet it did not ask for, once a second, is what makes it show
; wrong speed and temperature. The boot lines in main are the exception, they run once per load.
(defun dbg-print (s)
    (if debug-enabled (print s))
)

(defun restore-defaults ()
    {
        (write-setting 'cruise-enabled true)
        (write-setting 'cruise-hold-sec 5.0)
        (write-setting 'cruise-deadband 0.10)
        (write-setting 'cruise-min-speed-kmh 5.0)
        (write-setting 'cruise-max-speed-kmh 25.0)
        (write-setting 'legal-enabled false)
        (write-setting 'debug-enabled false)
        (write-setting 'ver-code settings-version)
    }
)

(defun load-settings ()
    {
        (if (not-eq (read-setting 'ver-code) settings-version)
            (restore-defaults)
        )

        (set 'cruise-enabled (read-setting 'cruise-enabled))
        (set 'cruise-hold-sec (read-setting 'cruise-hold-sec))
        (set 'cruise-deadband (read-setting 'cruise-deadband))
        (set 'cruise-min-speed (/ (read-setting 'cruise-min-speed-kmh) 3.6))
        (set 'cruise-max-speed (/ (read-setting 'cruise-max-speed-kmh) 3.6))
        (set 'legal-enabled (read-setting 'legal-enabled))
        (set 'debug-enabled (read-setting 'debug-enabled))
    }
)

; Every field but the last one ends in a space, str-merge joins them without a separator
(defun send-settings ()
    {
        (send-data (str-merge
            "cruise "
            (if (read-setting 'cruise-enabled) "true " "false ")
            (str-from-n (read-setting 'cruise-hold-sec) "%.1f ")
            (str-from-n (read-setting 'cruise-deadband) "%.2f ")
            (str-from-n (read-setting 'cruise-min-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'cruise-max-speed-kmh) "%.1f ")
            (if (read-setting 'legal-enabled) "true " "false ")
            (if (read-setting 'debug-enabled) "true" "false")
        ))
    }
)

(defun send-state ()
    {
        (send-data (str-merge
            "state "
            (sym-name cruise-state) " "
            (sym-name last-cancel) " "
            (if legal "locked" "unlocked")
        ))
    }
)

(defun save-cruise-settings (enabled hold-sec deadband min-speed-kmh max-speed-kmh legal-on debug-on)
    {
        (write-setting 'cruise-enabled enabled)
        (write-setting 'cruise-hold-sec hold-sec)
        (write-setting 'cruise-deadband deadband)
        (write-setting 'cruise-min-speed-kmh min-speed-kmh)
        (write-setting 'cruise-max-speed-kmh max-speed-kmh)
        (write-setting 'legal-enabled legal-on)
        (write-setting 'debug-enabled debug-on)
        (load-settings)
        (send-settings)
        (send-state)
    }
)

(defun restore-settings-ui ()
    {
        (restore-defaults)
        (load-settings)
        (send-settings)
        (send-state)
    }
)

; The UI waits for this before sending the next command, a burst would overrun the mailbox.
; The reply is tagged with the command it answers, a plain "ack" for everything made the UI
; show "settings saved" on every reply and ask for the settings again, an endless loop.
; The first symbol of the command picks the tag.
(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data))
                (let ((parsed (trap (read data))))
                    (send-data
                        (if (eq (car parsed) 'exit-error)
                            "err"
                            (let ((command (car (second parsed))))
                                (if (eq (car (trap (eval (second parsed)))) 'exit-error)
                                    "err"
                                    (cond
                                        ((eq command 'save-cruise-settings) "saved")
                                        ((eq command 'send-settings) "loaded")
                                        ((eq command 'send-state) "state-poll")
                                        ((eq command 'restore-settings-ui) "reset")
                                        (t "ack")
                                    )
                                )
                            )
                        )
                    )
                )
            )
            (_ nil)
        )
))

; A short beep blocks this thread for a quarter of a second, which is fine everywhere except
; while ADC1 is detached: there the override has to keep coming or the timeout stops the motor.
(defun beep ()
    {
        (foc-play-tone 0 2500 24.0)
        (sleep 0.15)
        (foc-play-stop)
        (sleep 0.1)
    }
)

(defun beeps (n)
    (looprange i 0 n (beep))
)

; The long beep is started and left running, the control loop stops it. Nothing blocks here.
(defun tone (freq ms)
    {
        (foc-play-tone 0 freq 24.0)
        (set 'tone-stop (+ (systime) (* ms ticks-per-ms)))
    }
)

(defun tone-service ()
    (if (and (!= tone-stop 0) (> (systime) tone-stop))
        {
            (foc-play-stop)
            (set 'tone-stop 0)
        }
    )
)

; The state stays on the screen for a moment after a cancel, so the UI has time to show it
(defun set-cruise-state (state)
    (if (and (eq cruise-state 'cancelling) (< (- (systime) cruise-state-time) (* cancelling-ms ticks-per-ms)))
        nil
        (if (not-eq cruise-state state)
            {
                (set 'cruise-state state)
                (set 'cruise-state-time (systime))
            }
        )
    )
)

; Limits are per VESC, so the other ones on the bus need the same values
(defun apply-limits (speed watt)
    {
        (var n 0)
        (conf-set 'max-speed speed)
        (conf-set 'l-watt-max watt)

        (loopforeach id (can-list-devs)
            {
                (setq n (+ n 1))
                ; can-cmd takes two commands per second per device at most
                (can-cmd id (str-from-n speed "(conf-set 'max-speed %.4f)"))
                (sleep 0.6)
                (can-cmd id (str-from-n watt "(conf-set 'l-watt-max %.1f)"))
                (sleep 0.6)
            }
        )

        ; One line per push: it says whether the other VESC on a two motor scooter was found at all
        (dbg-print (str-merge
            (str-from-n speed "Limits %.4f m/s ")
            (str-from-n watt "%.1f W set on this VESC, VESCs on CAN: ")
            (str-from-n n "%d")
        ))
    }
)

(defun legal-unlock ()
    {
        (apply-limits legal-saved-speed legal-saved-watt)
        (set 'legal false)
        (dbg-print "Legal lock OFF")
    }
)

; A limit read back from the VESC is only usable when it is a sane positive number. A zero, an
; infinity or a NaN would be stored as the value to restore and the scooter would end up limited
; (or unlimited) for good, because the restore would push the broken value back.
; A NaN fails both comparisons, so no is-nan/is-inf is needed here.
(defun valid-limit (v)
    (and (> v 0.0) (< v 1000000.0))
)

(defun legal-toggle ()
    {
        (if legal
            {
                (legal-unlock)
                (beep)
            }
            {
                (var save-speed (conf-get 'max-speed))
                (var save-watt (conf-get 'l-watt-max))

                (if (and (valid-limit save-speed) (valid-limit save-watt))
                    {
                        (set 'legal-saved-speed save-speed)
                        (set 'legal-saved-watt save-watt)
                        (dbg-print (str-merge
                            (str-from-n save-speed "Legal limits to restore: %.4f m/s, ")
                            (str-from-n save-watt "%.1f W")
                        ))
                        (apply-limits legal-speed legal-watt)
                        (set 'legal true)
                        (beeps 3)
                        (dbg-print (str-from-n legal-speed-kmh "Legal lock ON - %.0f km/h"))
                    }
                    {
                        ; never store a broken value: the restore would push it back
                        (dbg-print (str-merge
                            (str-from-n save-speed "Legal lock ABORTED - bad max-speed: %.4f m/s, ")
                            (str-from-n save-watt "l-watt-max: %.1f W")
                        ))
                        (beeps 4)
                    }
                )
            }
        )
    }
)

(defun brake-pressed ()
    (or (> (get-adc-decoded 1) brake-on)
        (> (get-adc 1) brake-raw-on)
    )
)

(defun legal-gesture ()
    {
        (if legal-enabled
            {
                (var spd (get-speed))
                (var brk (brake-pressed))
                (var now (systime))

                ; the lock is engaged and released parked, so the gesture only counts standing still
                (if (>= spd stop-speed)
                    {
                        (set 'legal-taps 0)
                        (set 'legal-brake-seen brk)
                    }
                    {
                        ; a burst that drags on is forgotten before a tap starts a new one
                        (if (and (> legal-taps 0)
                                 (> (- now legal-tap-first) (* tap-window-ms ticks-per-ms)))
                            (set 'legal-taps 0)
                        )

                        ; a rising edge on the brake is a tap, chatter is not
                        (if (and brk
                                 (not legal-brake-seen)
                                 (> (- now legal-tap-last) (* tap-debounce-ms ticks-per-ms)))
                            {
                                (if (= legal-taps 0)
                                    (set 'legal-tap-first now)
                                )
                                (set 'legal-tap-last now)
                                (set 'legal-taps (+ legal-taps 1))
                                (dbg-print (str-from-n legal-taps "Legal gesture, tap %d"))
                            }
                        )
                        (set 'legal-brake-seen brk)

                        (if (>= legal-taps taps-needed)
                            {
                                (set 'legal-taps 0)
                                (legal-toggle)
                            }
                        )
                    }
                )
            }
            (if legal (legal-unlock)) ; the switch went off, give the limits back
        )
    }
)

; reason is a symbol, it ends up in last-cancel for the debug line
(defun cruise-cancel (reason)
    {
        (app-adc-detach 1 0) ; hand the throttle back to the rider first
        (app-adc-override 0 0)
        (set 'cruise-active false)
        (set 'cruise-thr-ref 0.0)
        (set 'cruise-hold-start 0)
        (set 'cruise-integral 0.0)
        (set 'cruise-low-start 0)
        (set 'cruise-high-start 0)
        (set 'cruise-moved-count 0)
        (set 'cruise-arm-time 0)
        (set 'last-cancel reason)
        (set 'cruise-state 'cancelling)
        (set 'cruise-state-time (systime))
        (dbg-print (str-merge "Cruise OFF - " (sym-name reason)))
        (beeps 2)
    }
)

(defun cruise-engage ()
    {
        (app-adc-override 0 cruise-thr-ref) ; set the override before detaching, so the throttle never drops
        (app-adc-detach 1 2) ; detach ADC1 only, the brake keeps working as it is
        (set 'cruise-volts cruise-thr-ref)
        (set 'cruise-target (get-speed))
        (set 'cruise-integral 0.0)
        (set 'cruise-low-start 0)
        (set 'cruise-high-start 0)
        (set 'cruise-moved-count 0)
        (set 'cruise-arm-time (systime)) ; the throttle is not watched for cruise-arm-ms
        (set 'cruise-active true)
        (set 'cruise-state 'on)
        (set 'cruise-state-time (systime))
        (dbg-print (str-from-n (* cruise-target 3.6) "Cruise ON - %.1f km/h"))
        (tone 2500 500) ; one long beep, and it does not block the override
    }
)

(defun cruise-hold ()
    {
        (var dt (/ 1.0 cruise-hz))
        (var err (- cruise-target (get-speed)))
        (var lo (- cruise-thr-ref cruise-range))
        (var hi (+ cruise-thr-ref cruise-range))

        (set 'cruise-integral (+ cruise-integral (* cruise-ki err dt)))

        ; keep the integral inside the range the output is clamped to, or it winds up on a hill
        (if (> cruise-integral cruise-range) (set 'cruise-integral cruise-range))
        (if (< cruise-integral (- cruise-range)) (set 'cruise-integral (- cruise-range)))

        (var volts (+ cruise-thr-ref (* cruise-kp err) cruise-integral))

        ; never wander far from where the rider had the throttle
        (if (< volts lo) (setq volts lo))
        (if (> volts hi) (setq volts hi))

        (set 'cruise-volts volts)
        (app-adc-override 0 cruise-volts)
    }
)

; One cancel reason per tick, the first one that fires wins
(defun cruise-reason (spd brk-pressed)
    {
        (var reason 'none)

        ; stopped for a while: the rider is not riding anymore, warn with three beeps
        (if (< spd stop-speed)
            (if (= cruise-low-start 0)
                (set 'cruise-low-start (systime))
                (if (> (- (systime) cruise-low-start) (* cruise-low-ms ticks-per-ms))
                    (setq reason 'speed_low)
                )
            )
            (set 'cruise-low-start 0)
        )

        (if (and (eq reason 'none) brk-pressed)
            (setq reason 'brake)
        )

        ; (get-adc 0) reads the throttle pin and ignores the override, so while cruising it is the
        ; physical throttle, not the voltage the ADC app is using, and it falls back to rest as
        ; soon as the rider lets the throttle go - which is what a rider does when the cruise
        ; takes over. Comparing it with the reference in both directions made every release
        ; cancel the cruise, one tick after engaging. Only a pull past the reference counts as a
        ; move here, and it has to last a few ticks, so a spike on the pin cannot end a cruise.
        (if (> (get-adc 0) (+ cruise-thr-ref cruise-deadband))
            (set 'cruise-moved-count (+ cruise-moved-count 1))
            (set 'cruise-moved-count 0)
        )

        (if (and (eq reason 'none)
                 (> (- (systime) cruise-arm-time) (* cruise-arm-ms ticks-per-ms))
                 (> cruise-moved-count cruise-moved-ticks))
            (setq reason 'throttle_moved)
        )

        ; the overspeed guard only means something once a max speed is set
        (if (and (eq reason 'none)
                 (> cruise-max-speed stop-speed)
                 (> spd (* cruise-max-speed cruise-high-margin)))
            (if (= cruise-high-start 0)
                (set 'cruise-high-start (systime))
                (if (> (- (systime) cruise-high-start) (* cruise-high-ms ticks-per-ms))
                    (setq reason 'overspeed)
                )
            )
            (set 'cruise-high-start 0)
        )

        reason
    }
)

(defun cruise-step ()
    {
        (var spd (get-speed))
        (var brk (brake-pressed))

        (if cruise-active
            {
                (var reason (cruise-reason spd brk))

                (if (eq reason 'none)
                    {
                        (set-cruise-state 'on)
                        (cruise-hold)
                    }
                    (cruise-cancel reason)
                )
            }
            {
                (var thr (get-adc-decoded 0))
                (var thr-volts (get-adc 0))

                (if (and cruise-enabled (not brk) (> thr thr-min))
                    {
                        ; first valid sample of a hold, or the throttle moved: restart the count
                        (if (or (= cruise-hold-start 0)
                                (> (abs (- thr-volts cruise-thr-ref)) cruise-deadband))
                            {
                                (set 'cruise-thr-ref thr-volts)
                                (set 'cruise-hold-start (systime))
                            }
                        )

                        (set-cruise-state 'engaging)

                        (if (>= (/ (- (systime) cruise-hold-start) ticks-per-sec) cruise-hold-sec)
                            (if (and (>= spd cruise-min-speed) (<= spd cruise-max-speed))
                                (cruise-engage)
                            )
                        )
                    }
                    { ; not riding, the next hold starts from scratch
                        (set 'cruise-hold-start 0)
                        (set 'cruise-thr-ref 0.0)
                        (set-cruise-state 'off)
                    }
                )
            }
        )
    }
)

; thr is the physical pin and inj is the voltage the script is feeding the ADC app: while cruising
; they are different by design, and inj is the one the app uses. brkD is the decoded brake, the
; value the legal gesture needs to see.
(defun debug-print ()
    {
        (var hold 0.0)
        (if (!= cruise-hold-start 0)
            (setq hold (/ (- (systime) cruise-hold-start) ticks-per-sec))
        )

        (dbg-print (str-merge
            "[DEBUG] thr="
            (str-from-n (get-adc 0) "%.3f")
            "V ref="
            (str-from-n cruise-thr-ref "%.3f")
            "V inj="
            (str-from-n cruise-volts "%.3f")
            "V brk="
            (str-from-n (get-adc 1) "%.3f")
            "V brkD="
            (str-from-n (get-adc-decoded 1) "%.2f")
            " brake="
            (if (brake-pressed) "1" "0")
            " spd="
            (str-from-n (* (get-speed) 3.6) "%.1f")
            "km/h state="
            (sym-name cruise-state)
            " hold="
            (str-from-n hold "%.1f")
            "s last_cancel="
            (sym-name last-cancel)
            " legal="
            (if legal-enabled "1" "0")
            " taps="
            (str-from-n legal-taps "%d")
            " locked="
            (if legal "1" "0")
        ))
    }
)

(defun control-loop ()
    (loopwhile t
        {
            (tone-service)
            (legal-gesture)
            (cruise-step)

            (set 'loop-counter (+ loop-counter 1))
            (if (>= loop-counter debug-divider)
                {
                    (set 'loop-counter 0)
                    ; Nothing goes out unless the debug switch is on. The UI asks for the state
                    ; itself: a reply leaves by the port that asked, so it reaches VESC Tool and
                    ; never the display polling the same UART.
                    (if debug-enabled (debug-print))
                }
            )

            (sleep (/ 1.0 cruise-hz))
        }
    )
)

(defun main () {
        (load-settings)
        (app-adc-detach 1 0) ; both ADCs attached on start-up, a stopped script leaves them detached
        (set 'last-cancel 'script_restart) ; the image was just loaded, any cruise that was on is gone

        (var ctrl-type (conf-get 'adc-ctrl-type))
        ; These two print whatever the debug switch says: they are the only sign that the script
        ; loaded at all, and a wrong ADC control type means cruise silently does nothing. Both run
        ; once, at load, so they are not the traffic that troubles a display.
        (print (str-from-n ctrl-type "ADC control type: %d"))
        (if (or (= ctrl-type 0) (>= ctrl-type 12))
            (print "Cruise control needs a current or duty control type in the ADC app")
        )

        ; What the script thinks it was told, on the terminal: the UI and the log have to agree
        (print (str-merge
            "Settings: cruise "
            (if cruise-enabled "on" "off")
            " legal gesture "
            (if legal-enabled "on" "off")
            " debug "
            (if debug-enabled "on" "off")
            ", debug lines on this terminal"
        ))

        (event-register-handler (spawn event-handler))
        (event-enable 'event-data-rx)

        ; Nothing is sent from here: the UI asks for the settings and for the state when it opens
        ; and while it is open, and those replies leave by the port that asked. A script that talks
        ; unprompted talks to whatever spoke last, which on a UART display is the display.

        (control-loop) ; blocks the main thread
})

@const-end

(image-save)
(main)
