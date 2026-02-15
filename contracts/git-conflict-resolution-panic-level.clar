;; git-conflict-resolution-panic-level
;; Tracks developer panic levels when encountering merge conflicts
;; Spikes when you see <<<<<<< HEAD and consider starting over from scratch

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-panic-level (err u101))
(define-constant err-not-found (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-invalid-input (err u105))

;; Maximum panic level (10 = complete meltdown)
(define-constant max-panic-level u10)
(define-constant min-panic-level u1)

;; Data Variables
(define-data-var total-panic-events uint u0)
(define-data-var total-developers-tracked uint u0)
(define-data-var highest-panic-level uint u0)
(define-data-var emergency-threshold uint u8)
(define-data-var system-active bool true)

;; Data Maps
;; Track individual panic events
(define-map panic-events
  { event-id: uint }
  {
    developer: principal,
    panic-level: uint,
    timestamp: uint,
    description: (string-ascii 256),
    resolved: bool
  }
)

;; Track developer statistics
(define-map developer-stats
  { developer: principal }
  {
    total-panics: uint,
    average-panic-level: uint,
    max-panic-level: uint,
    last-panic-timestamp: uint,
    total-events: uint
  }
)

;; Track daily panic metrics
(define-map daily-panic-metrics
  { day: uint }
  {
    total-events: uint,
    average-panic: uint,
    peak-panic: uint,
    affected-developers: uint
  }
)

;; Authorization list for recording events
(define-map authorized-recorders
  { recorder: principal }
  { authorized: bool }
)

;; Private Functions

;; Calculate average panic level for a developer
(define-private (calculate-average (total uint) (count uint))
  (if (is-eq count u0)
    u0
    (/ total count)
  )
)

;; Check if panic level is valid
(define-private (is-valid-panic-level (level uint))
  (and (>= level min-panic-level) (<= level max-panic-level))
)

;; Get current day (simplified - using block height as proxy for time)
(define-private (get-current-day)
  (/ stacks-block-height u144) ;; Assuming ~144 blocks per day
)

;; Update developer statistics
(define-private (update-developer-stats (developer principal) (panic-level uint))
  (let
    (
      (current-stats (default-to
        { total-panics: u0, average-panic-level: u0, max-panic-level: u0, 
          last-panic-timestamp: u0, total-events: u0 }
        (map-get? developer-stats { developer: developer })
      ))
      (new-total-panics (+ (get total-panics current-stats) panic-level))
      (new-total-events (+ (get total-events current-stats) u1))
      (new-average (calculate-average new-total-panics new-total-events))
      (new-max (if (> panic-level (get max-panic-level current-stats))
                 panic-level
                 (get max-panic-level current-stats)))
    )
    (map-set developer-stats
      { developer: developer }
      {
        total-panics: new-total-panics,
        average-panic-level: new-average,
        max-panic-level: new-max,
        last-panic-timestamp: stacks-block-height,
        total-events: new-total-events
      }
    )
    true
  )
)

;; Update daily metrics
(define-private (update-daily-metrics (panic-level uint))
  (let
    (
      (current-day (get-current-day))
      (current-metrics (default-to
        { total-events: u0, average-panic: u0, peak-panic: u0, affected-developers: u0 }
        (map-get? daily-panic-metrics { day: current-day })
      ))
      (new-total-events (+ (get total-events current-metrics) u1))
      (new-total-panic (+ (* (get average-panic current-metrics) (get total-events current-metrics)) panic-level))
      (new-average (calculate-average new-total-panic new-total-events))
      (new-peak (if (> panic-level (get peak-panic current-metrics))
                  panic-level
                  (get peak-panic current-metrics)))
    )
    (map-set daily-panic-metrics
      { day: current-day }
      {
        total-events: new-total-events,
        average-panic: new-average,
        peak-panic: new-peak,
        affected-developers: (+ (get affected-developers current-metrics) u1)
      }
    )
    true
  )
)

;; Public Functions

;; Initialize authorization for a recorder
(define-public (authorize-recorder (recorder principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-recorders { recorder: recorder } { authorized: true }))
  )
)

;; Remove authorization
(define-public (revoke-recorder (recorder principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-delete authorized-recorders { recorder: recorder }))
  )
)

;; Record a panic event
(define-public (record-panic-event (panic-level uint) (description (string-ascii 256)))
  (let
    (
      (event-id (var-get total-panic-events))
      (developer tx-sender)
    )
    (asserts! (var-get system-active) err-unauthorized)
    (asserts! (is-valid-panic-level panic-level) err-invalid-panic-level)
    
    ;; Store the panic event
    (map-set panic-events
      { event-id: event-id }
      {
        developer: developer,
        panic-level: panic-level,
        timestamp: stacks-block-height,
        description: description,
        resolved: false
      }
    )
    
    ;; Update statistics
    (update-developer-stats developer panic-level)
    (update-daily-metrics panic-level)
    
    ;; Update global counters
    (var-set total-panic-events (+ event-id u1))
    (if (> panic-level (var-get highest-panic-level))
      (var-set highest-panic-level panic-level)
      false
    )
    
    (ok event-id)
  )
)

;; Mark a panic event as resolved
(define-public (resolve-panic-event (event-id uint))
  (let
    (
      (event (unwrap! (map-get? panic-events { event-id: event-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get developer event)) err-unauthorized)
    (asserts! (not (get resolved event)) err-invalid-input)
    
    (ok (map-set panic-events
      { event-id: event-id }
      (merge event { resolved: true })
    ))
  )
)

;; Set emergency threshold
(define-public (set-emergency-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-valid-panic-level new-threshold) err-invalid-panic-level)
    (ok (var-set emergency-threshold new-threshold))
  )
)

;; Toggle system active status
(define-public (toggle-system-status)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set system-active (not (var-get system-active))))
  )
)

;; Read-only Functions

;; Get total panic events
(define-read-only (get-total-panic-events)
  (ok (var-get total-panic-events))
)

;; Get highest panic level ever recorded
(define-read-only (get-highest-panic-level)
  (ok (var-get highest-panic-level))
)

;; Get emergency threshold
(define-read-only (get-emergency-threshold)
  (ok (var-get emergency-threshold))
)

;; Get system status
(define-read-only (get-system-status)
  (ok (var-get system-active))
)

;; Get specific panic event
(define-read-only (get-panic-event (event-id uint))
  (ok (map-get? panic-events { event-id: event-id }))
)

;; Get developer statistics
(define-read-only (get-developer-stats (developer principal))
  (ok (map-get? developer-stats { developer: developer }))
)

;; Get daily metrics
(define-read-only (get-daily-metrics (day uint))
  (ok (map-get? daily-panic-metrics { day: day }))
)

;; Get current day metrics
(define-read-only (get-current-day-metrics)
  (ok (map-get? daily-panic-metrics { day: (get-current-day) }))
)

;; Check if panic level is emergency
(define-read-only (is-emergency-level (panic-level uint))
  (ok (>= panic-level (var-get emergency-threshold)))
)

;; Check if recorder is authorized
(define-read-only (is-authorized-recorder (recorder principal))
  (ok (default-to false (get authorized (map-get? authorized-recorders { recorder: recorder }))))
)
