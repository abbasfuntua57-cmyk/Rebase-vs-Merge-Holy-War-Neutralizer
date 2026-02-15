;; clean-history-obsession-productivity-cost
;; Calculates hours lost making commits 'pretty' that literally nobody will read
;; Tracks the productivity cost of excessive commit history beautification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-invalid-hours (err u201))
(define-constant err-not-found (err u202))
(define-constant err-unauthorized (err u203))
(define-constant err-invalid-cost (err u204))
(define-constant err-already-logged (err u205))

;; Cost calculation constants
(define-constant max-hours-per-session u24)
(define-constant hourly-cost-usd u100) ;; Average developer hourly cost
(define-constant min-hours u0)

;; Data Variables
(define-data-var total-hours-wasted uint u0)
(define-data-var total-sessions uint u0)
(define-data-var total-developers uint u0)
(define-data-var total-cost-usd uint u0)
(define-data-var system-enabled bool true)
(define-data-var warning-threshold-hours uint u5)

;; Data Maps

;; Track individual beautification sessions
(define-map beautification-sessions
  { session-id: uint }
  {
    developer: principal,
    hours-spent: uint,
    timestamp: uint,
    activity-type: (string-ascii 128),
    cost-usd: uint,
    justified: bool
  }
)

;; Track developer productivity loss
(define-map developer-productivity
  { developer: principal }
  {
    total-hours-wasted: uint,
    total-sessions: uint,
    total-cost: uint,
    average-session-hours: uint,
    last-activity: uint,
    warning-count: uint
  }
)

;; Track team-wide statistics by week
(define-map weekly-stats
  { week: uint }
  {
    total-hours: uint,
    total-cost: uint,
    session-count: uint,
    active-developers: uint,
    average-hours-per-developer: uint
  }
)

;; Activity type catalog
(define-map activity-types
  { activity-name: (string-ascii 128) }
  {
    total-occurrences: uint,
    total-hours: uint,
    average-hours: uint
  }
)

;; Developer warnings for excessive beautification
(define-map developer-warnings
  { developer: principal, warning-id: uint }
  {
    timestamp: uint,
    hours-that-week: uint,
    message: (string-ascii 256)
  }
)

;; Private Functions

;; Calculate current week based on block height
(define-private (get-current-week)
  (/ stacks-block-height u1008) ;; Assuming ~1008 blocks per week
)

;; Calculate cost in USD
(define-private (calculate-cost (hours uint))
  (* hours hourly-cost-usd)
)

;; Validate hours input
(define-private (is-valid-hours (hours uint))
  (and (>= hours min-hours) (<= hours max-hours-per-session))
)

;; Calculate average
(define-private (safe-divide (numerator uint) (denominator uint))
  (if (is-eq denominator u0)
    u0
    (/ numerator denominator)
  )
)

;; Update developer productivity stats
(define-private (update-developer-productivity (developer principal) (hours uint) (cost uint))
  (let
    (
      (current-stats (default-to
        { total-hours-wasted: u0, total-sessions: u0, total-cost: u0,
          average-session-hours: u0, last-activity: u0, warning-count: u0 }
        (map-get? developer-productivity { developer: developer })
      ))
      (new-total-hours (+ (get total-hours-wasted current-stats) hours))
      (new-total-sessions (+ (get total-sessions current-stats) u1))
      (new-total-cost (+ (get total-cost current-stats) cost))
      (new-average (safe-divide new-total-hours new-total-sessions))
    )
    (map-set developer-productivity
      { developer: developer }
      {
        total-hours-wasted: new-total-hours,
        total-sessions: new-total-sessions,
        total-cost: new-total-cost,
        average-session-hours: new-average,
        last-activity: stacks-block-height,
        warning-count: (get warning-count current-stats)
      }
    )
    true
  )
)

;; Update weekly statistics
(define-private (update-weekly-stats (hours uint) (cost uint))
  (let
    (
      (current-week (get-current-week))
      (current-stats (default-to
        { total-hours: u0, total-cost: u0, session-count: u0,
          active-developers: u0, average-hours-per-developer: u0 }
        (map-get? weekly-stats { week: current-week })
      ))
      (new-total-hours (+ (get total-hours current-stats) hours))
      (new-total-cost (+ (get total-cost current-stats) cost))
      (new-session-count (+ (get session-count current-stats) u1))
      (new-active-devs (+ (get active-developers current-stats) u1))
      (new-avg (safe-divide new-total-hours new-active-devs))
    )
    (map-set weekly-stats
      { week: current-week }
      {
        total-hours: new-total-hours,
        total-cost: new-total-cost,
        session-count: new-session-count,
        active-developers: new-active-devs,
        average-hours-per-developer: new-avg
      }
    )
    true
  )
)

;; Update activity type statistics
(define-private (update-activity-stats (activity (string-ascii 128)) (hours uint))
  (let
    (
      (current-stats (default-to
        { total-occurrences: u0, total-hours: u0, average-hours: u0 }
        (map-get? activity-types { activity-name: activity })
      ))
      (new-occurrences (+ (get total-occurrences current-stats) u1))
      (new-total-hours (+ (get total-hours current-stats) hours))
      (new-average (safe-divide new-total-hours new-occurrences))
    )
    (map-set activity-types
      { activity-name: activity }
      {
        total-occurrences: new-occurrences,
        total-hours: new-total-hours,
        average-hours: new-average
      }
    )
    true
  )
)

;; Check if developer needs warning
(define-private (check-warning-threshold (developer principal) (total-hours uint))
  (>= total-hours (var-get warning-threshold-hours))
)

;; Public Functions

;; Log a beautification session
(define-public (log-wasted-hours (hours uint) (activity (string-ascii 128)))
  (let
    (
      (session-id (var-get total-sessions))
      (cost (calculate-cost hours))
      (developer tx-sender)
    )
    (asserts! (var-get system-enabled) err-unauthorized)
    (asserts! (is-valid-hours hours) err-invalid-hours)
    
    ;; Store the session
    (map-set beautification-sessions
      { session-id: session-id }
      {
        developer: developer,
        hours-spent: hours,
        timestamp: stacks-block-height,
        activity-type: activity,
        cost-usd: cost,
        justified: false
      }
    )
    
    ;; Update all statistics
    (update-developer-productivity developer hours cost)
    (update-weekly-stats hours cost)
    (update-activity-stats activity hours)
    
    ;; Update global counters
    (var-set total-hours-wasted (+ (var-get total-hours-wasted) hours))
    (var-set total-sessions (+ session-id u1))
    (var-set total-cost-usd (+ (var-get total-cost-usd) cost))
    
    (ok session-id)
  )
)

;; Mark a session as justified (sometimes it's actually necessary)
(define-public (justify-session (session-id uint))
  (let
    (
      (session (unwrap! (map-get? beautification-sessions { session-id: session-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get developer session)) err-unauthorized)
    
    (ok (map-set beautification-sessions
      { session-id: session-id }
      (merge session { justified: true })
    ))
  )
)

;; Issue warning to developer
(define-public (issue-warning (developer principal) (message (string-ascii 256)))
  (let
    (
      (dev-stats (unwrap! (map-get? developer-productivity { developer: developer }) err-not-found))
      (warning-id (get warning-count dev-stats))
      (week-stats (default-to
        { total-hours: u0, total-cost: u0, session-count: u0,
          active-developers: u0, average-hours-per-developer: u0 }
        (map-get? weekly-stats { week: (get-current-week) })
      ))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set developer-warnings
      { developer: developer, warning-id: warning-id }
      {
        timestamp: stacks-block-height,
        hours-that-week: (get total-hours week-stats),
        message: message
      }
    )
    
    ;; Increment warning count
    (map-set developer-productivity
      { developer: developer }
      (merge dev-stats { warning-count: (+ warning-id u1) })
    )
    
    (ok warning-id)
  )
)

;; Set warning threshold
(define-public (set-warning-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set warning-threshold-hours new-threshold))
  )
)

;; Toggle system status
(define-public (toggle-system)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set system-enabled (not (var-get system-enabled))))
  )
)

;; Batch log multiple sessions (for importing historical data)
(define-public (batch-log-sessions (hours-list (list 10 uint)) (activity (string-ascii 128)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (fold log-single-hour hours-list u0))
  )
)

;; Helper for batch logging
(define-private (log-single-hour (hours uint) (previous-result uint))
  (match (log-wasted-hours hours "Batch import")
    success (+ previous-result u1)
    error previous-result
  )
)

;; Read-only Functions

;; Get total hours wasted
(define-read-only (get-total-hours-wasted)
  (ok (var-get total-hours-wasted))
)

;; Get total cost in USD
(define-read-only (get-total-cost)
  (ok (var-get total-cost-usd))
)

;; Get total sessions
(define-read-only (get-total-sessions)
  (ok (var-get total-sessions))
)

;; Calculate average hours per session globally
(define-read-only (get-average-hours-per-session)
  (ok (safe-divide (var-get total-hours-wasted) (var-get total-sessions)))
)

;; Get system status
(define-read-only (get-system-status)
  (ok (var-get system-enabled))
)

;; Get warning threshold
(define-read-only (get-warning-threshold)
  (ok (var-get warning-threshold-hours))
)

;; Get specific session details
(define-read-only (get-session-details (session-id uint))
  (ok (map-get? beautification-sessions { session-id: session-id }))
)

;; Get developer productivity stats
(define-read-only (get-developer-productivity-stats (developer principal))
  (ok (map-get? developer-productivity { developer: developer }))
)

;; Get weekly statistics
(define-read-only (get-weekly-stats (week uint))
  (ok (map-get? weekly-stats { week: week }))
)

;; Get current week statistics
(define-read-only (get-current-week-stats)
  (ok (map-get? weekly-stats { week: (get-current-week) }))
)

;; Get activity type statistics
(define-read-only (get-activity-stats (activity (string-ascii 128)))
  (ok (map-get? activity-types { activity-name: activity }))
)

;; Get developer warning
(define-read-only (get-developer-warning (developer principal) (warning-id uint))
  (ok (map-get? developer-warnings { developer: developer, warning-id: warning-id }))
)

;; Calculate ROI (negative value indicating loss)
(define-read-only (calculate-roi-loss (developer principal))
  (let
    (
      (stats (map-get? developer-productivity { developer: developer }))
    )
    (match stats
      some-stats (ok (get total-cost some-stats))
      (ok u0)
    )
  )
)

;; Check if hours exceed warning threshold
(define-read-only (exceeds-warning-threshold (hours uint))
  (ok (>= hours (var-get warning-threshold-hours)))
)
