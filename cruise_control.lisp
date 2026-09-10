; VESC Cruise Control
; Throttle on ADC1, brake on ADC2. Hold the throttle steady for the hold time to engage,
; a brake or a throttle change cancels it.
;
; Needs the ADC app. While cruising, ADC1 is detached and overridden with the voltage that
; holds the speed, so the app keeps doing the mapping, ramping and limits, and a master with
; Multiple VESCs over CAN keeps sending the same command to the slaves.

@const-start

(def settings-version 100i32)

; Persistent settings: (label . (eeprom-offset type))
(def eeprom-addrs '(
    (ver-code             . (0 i))
    (cruise-enabled       . (1 b))
    (cruise-hold-sec      . (2 f))
    (cruise-deadband      . (3 f))
    (cruise-min-speed-kmh . (4 f))
    (cruise-max-speed-kmh . (5 f))
))

; Cruise control
(def cruise-enabled true)
(def cruise-hold-sec 5.0)
(def cruise-deadband 0.10)  ; volts of throttle jitter that still count as held
(def cruise-min-speed 0.0)  ; m/s, only checked while engaging
(def cruise-max-speed 0.0)

(def brake-on 0.5) ; volts, brake counts as pressed above this
(def thr-on 0.3)   ; volts, throttle below this is not riding

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
            (str-from-n (read-setting 'cruise-max-speed-kmh) "%.1f")
        ))
    }
)

(defun save-cruise-settings (enabled hold-sec deadband min-speed-kmh max-speed-kmh)
    {
        (write-setting 'cruise-enabled enabled)
        (write-setting 'cruise-hold-sec hold-sec)
        (write-setting 'cruise-deadband deadband)
        (write-setting 'cruise-min-speed-kmh min-speed-kmh)
        (write-setting 'cruise-max-speed-kmh max-speed-kmh)
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
        (var thr (get-adc 0)) ; always the real throttle, the override does not hide it
        (var brk (get-adc 1))
        (var spd (get-speed))

        (if cruise-active
            (if (or (> brk brake-on)
                    (> (abs (- thr cruise-thr-ref)) cruise-deadband)
                    (< spd stop-speed))
                (cruise-cancel)
                (cruise-hold)
            )
            (if (and cruise-enabled
                     (< brk brake-on)
                     (> thr thr-on)
                     (< (abs (- thr cruise-thr-ref)) cruise-deadband))
                (let ((elapsed (/ (- (systime) cruise-hold-start) 1000.0)))
                    (if (>= elapsed cruise-hold-sec)
                        (if (and (>= spd cruise-min-speed) (<= spd cruise-max-speed))
                            (cruise-engage)
                        )
                    )
                )
                { ; the throttle moved, restart the hold
                    (set 'cruise-thr-ref thr)
                    (set 'cruise-hold-start (systime))
                }
            )
        )
    }
)

(defun cruise-loop ()
    (loopwhile t
        {
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

        (cruise-loop) ; blocks the main thread
})

@const-end

(image-save)
(main)
