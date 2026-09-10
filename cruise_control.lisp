; VESC Cruise Control
; Throttle on ADC1, brake on ADC2. Hold the throttle steady for the hold time to engage,
; a brake or a throttle change cancels it.
;
; Legal lock: stopped, brake held, two throttle blips limits speed and power. It lasts until
; the scooter is switched off, nothing is written to flash and the limits are pushed to the
; other VESCs on the CAN bus.
;
; Needs the ADC app. While cruising, ADC1 is detached and overridden with the voltage that
; holds the speed, so the app keeps doing the mapping, ramping and limits, and a master with
; Multiple VESCs over CAN keeps sending the same command to the slaves.

@const-start

(def settings-version 101i32)

; Persistent settings: (label . (eeprom-offset type))
(def eeprom-addrs '(
    (ver-code             . (0 i))
    (cruise-enabled       . (1 b))
    (cruise-hold-sec      . (2 f))
    (cruise-deadband      . (3 f))
    (cruise-min-speed-kmh . (4 f))
    (cruise-max-speed-kmh . (5 f))
    (legal-speed-kmh      . (6 f))
    (legal-watt           . (7 f))
))

; Cruise control
(def cruise-enabled true)
(def cruise-hold-sec 5.0)
(def cruise-deadband 0.10)  ; volts of throttle jitter that still count as held
(def cruise-min-speed 0.0)  ; m/s, only checked while engaging
(def cruise-max-speed 0.0)

; Legal lock
(def legal-speed 0.0) ; m/s
(def legal-watt 0.0)

; Decoded values are 0 to 1, 0 is released
(def brake-on 0.10)
(def thr-min 0.10)     ; throttle below this is not riding
(def blip-on 0.30)     ; a blip rises past this
(def blip-off 0.10)    ; and back below this
(def blips-needed 2)

(def cruise-hz 50)
(def cruise-kp 0.25)   ; volts per m/s
(def cruise-ki 0.10)   ; volts per m/s per second
(def cruise-range 0.8) ; how many volts the hold may add or take away
(def stop-speed (/ 1.0 3.6))

(def cruise-active false)
(def cruise-thr-ref 0.0)
(def cruise-volts 0.0)
(def cruise-target 0.0)
(def cruise-integral 0.0)
(def cruise-hold-start 0)

(def legal false)
(def legal-saved-speed 0.0)
(def legal-saved-watt 0.0)
(def legal-blips 0)
(def legal-high false)
(def legal-done false) ; the gesture fired, wait for the brake to be released

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

(defun restore-defaults ()
    {
        (write-setting 'cruise-enabled true)
        (write-setting 'cruise-hold-sec 5.0)
        (write-setting 'cruise-deadband 0.10)
        (write-setting 'cruise-min-speed-kmh 5.0)
        (write-setting 'cruise-max-speed-kmh 25.0)
        (write-setting 'legal-speed-kmh 20.0)
        (write-setting 'legal-watt 500.0)
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
        (set 'legal-speed (/ (read-setting 'legal-speed-kmh) 3.6))
        (set 'legal-watt (read-setting 'legal-watt))
    }
)

(defun send-settings ()
    {
        (send-data (str-merge
            "cruise "
            (if (read-setting 'cruise-enabled) "true " "false ")
            (str-from-n (read-setting 'cruise-hold-sec) "%.1f ")
            (str-from-n (read-setting 'cruise-deadband) "%.2f ")
            (str-from-n (read-setting 'cruise-min-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'cruise-max-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'legal-speed-kmh) "%.1f ")
            (str-from-n (read-setting 'legal-watt) "%.0f")
        ))
    }
)

(defun save-cruise-settings (enabled hold-sec deadband min-speed-kmh max-speed-kmh legal-speed-kmh legal-watt)
    {
        (write-setting 'cruise-enabled enabled)
        (write-setting 'cruise-hold-sec hold-sec)
        (write-setting 'cruise-deadband deadband)
        (write-setting 'cruise-min-speed-kmh min-speed-kmh)
        (write-setting 'cruise-max-speed-kmh max-speed-kmh)
        (write-setting 'legal-speed-kmh legal-speed-kmh)
        (write-setting 'legal-watt legal-watt)
        (load-settings)
        (send-settings)
    }
)

(defun restore-settings-ui ()
    {
        (restore-defaults)
        (load-settings)
        (send-settings)
    }
)

; The UI waits for this before sending the next command, a burst would overrun the mailbox
(defun event-handler ()
    (loopwhile t
        (recv
            ((event-data-rx . (? data))
                (send-data (if (eq (car (trap (eval (read data)))) 'exit-ok) "ack" "err"))
            )
            (_ nil)
        )
))

(defun beep ()
    {
        (foc-play-tone 0 2500 24.0)
        (sleep 0.15)
        (foc-play-stop)
    }
)

; Limits are per VESC, so the other ones on the bus need the same values
(defun apply-limits (speed watt)
    {
        (conf-set 'max-speed speed)
        (conf-set 'l-watt-max watt)

        (loopforeach id (can-list-devs)
            {
                ; can-cmd takes two commands per second per device at most
                (can-cmd id (str-from-n speed "(conf-set 'max-speed %.4f)"))
                (sleep 0.6)
                (can-cmd id (str-from-n watt "(conf-set 'l-watt-max %.1f)"))
                (sleep 0.6)
            }
        )
    }
)

(defun legal-toggle ()
    {
        (if legal
            {
                (apply-limits legal-saved-speed legal-saved-watt)
                (set 'legal false)
                (beep)
                (print "Legal lock OFF")
            }
            {
                (set 'legal-saved-speed (conf-get 'max-speed))
                (set 'legal-saved-watt (conf-get 'l-watt-max))
                (apply-limits legal-speed legal-watt)
                (set 'legal true)
                (beep)
                (sleep 0.1)
                (beep)
                (print (str-from-n (* legal-speed 3.6) "Legal lock ON - %.0f km/h"))
            }
        )
    }
)

(defun legal-gesture ()
    {
        (var brk (get-adc-decoded 1))
        (var spd (get-speed))

        (if (and (< spd stop-speed) (> brk brake-on))
            (if legal-done
                nil
                {
                    (var thr (get-adc-decoded 0))
                    (if (> thr blip-on)
                        (if (not legal-high)
                            {
                                (set 'legal-high true)
                                (set 'legal-blips (+ legal-blips 1))
                            }
                        )
                        (if (< thr blip-off)
                            (set 'legal-high false)
                        )
                    )
                    (if (>= legal-blips blips-needed)
                        {
                            (legal-toggle)
                            (set 'legal-blips 0)
                            (set 'legal-high false)
                            (set 'legal-done true)
                        }
                    )
                }
            )
            { ; the brake is released, ready for the next gesture
                (set 'legal-done false)
                (set 'legal-high false)
                (set 'legal-blips 0)
            }
        )
    }
)

(defun cruise-cancel ()
    {
        (app-adc-detach 1 0) ; hand the throttle back to the rider first
        (app-adc-override 0 0)
        (set 'cruise-active false)
        (print "Cruise OFF")
    }
)

(defun cruise-engage ()
    {
        (app-adc-override 0 cruise-thr-ref) ; set the override before detaching, so the throttle never drops
        (app-adc-detach 1 2) ; detach ADC1 only, the brake keeps working as it is
        (set 'cruise-volts cruise-thr-ref)
        (set 'cruise-target (get-speed))
        (set 'cruise-integral 0.0)
        (set 'cruise-active true)
        (print (str-from-n (* cruise-target 3.6) "Cruise ON - %.1f km/h"))
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
        (if (< volts lo) (setf volts lo))
        (if (> volts hi) (setf volts hi))

        (set 'cruise-volts volts)
        (app-adc-override 0 cruise-volts)
    }
)

(defun cruise-step ()
    {
        (var spd (get-speed))
        (var brk (get-adc-decoded 1))

        (if cruise-active
            (if (or (> brk brake-on)
                    (> (abs (- (get-adc 0) cruise-thr-ref)) cruise-deadband)
                    (< spd stop-speed))
                (cruise-cancel)
                (cruise-hold)
            )
            {
                (var thr (get-adc-decoded 0))
                (if (and cruise-enabled
                         (< brk brake-on)
                         (> thr thr-min)
                         (< (abs (- (get-adc 0) cruise-thr-ref)) cruise-deadband))
                    (let ((elapsed (/ (- (systime) cruise-hold-start) 1000.0)))
                        (if (>= elapsed cruise-hold-sec)
                            (if (and (>= spd cruise-min-speed) (<= spd cruise-max-speed))
                                (cruise-engage)
                            )
                        )
                    )
                    { ; the throttle moved, restart the hold
                        (set 'cruise-thr-ref (get-adc 0))
                        (set 'cruise-hold-start (systime))
                    }
                )
            }
        )
    }
)

(defun control-loop ()
    (loopwhile t
        {
            (legal-gesture)
            (cruise-step)
            (sleep (/ 1.0 cruise-hz))
        }
    )
)

(defun main () {
        (load-settings)
        (app-adc-detach 1 0) ; both ADCs attached on start-up, a stopped script leaves them detached

        (var ctrl-type (conf-get 'adc-ctrl-type))
        (print (str-from-n ctrl-type "ADC control type: %d"))
        (if (or (= ctrl-type 0) (>= ctrl-type 12))
            (print "Cruise control needs a current or duty control type in the ADC app")
        )

        (event-register-handler (spawn event-handler))
        (event-enable 'event-data-rx)

        (control-loop) ; blocks the main thread
})

@const-end

(image-save)
(main)
