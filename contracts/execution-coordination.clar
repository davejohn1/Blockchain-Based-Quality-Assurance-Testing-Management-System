;; Execution Coordination Contract
;; Coordinates test execution workflows and progress tracking

;; Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u104))

;; Data Variables
(define-data-var next-execution-id uint u1)
(define-data-var next-result-id uint u1)

;; Data Maps
(define-map test-executions
  { execution-id: uint }
  {
    case-id: uint,
    executor: principal,
    start-time: uint,
    end-time: (optional uint),
    status: uint,
    environment: (string-ascii 50),
    notes: (string-ascii 500)
  }
)

(define-map execution-results
  { result-id: uint }
  {
    execution-id: uint,
    result-type: uint,
    description: (string-ascii 500),
    severity: uint,
    screenshot-hash: (optional (string-ascii 64)),
    recorded-time: uint
  }
)

(define-map execution-metrics
  { executor: principal }
  {
    total-executions: uint,
    passed-tests: uint,
    failed-tests: uint,
    average-duration: uint,
    last-execution: uint
  }
)

;; Read-only functions
(define-read-only (get-test-execution (execution-id uint))
  (map-get? test-executions { execution-id: execution-id })
)

(define-read-only (get-execution-result (result-id uint))
  (map-get? execution-results { result-id: result-id })
)

(define-read-only (get-executor-metrics (executor principal))
  (map-get? execution-metrics { executor: executor })
)

(define-read-only (get-next-execution-id)
  (var-get next-execution-id)
)

(define-read-only (get-next-result-id)
  (var-get next-result-id)
)

;; Public functions
(define-public (start-test-execution (case-id uint) (environment (string-ascii 50)))
  (let
    (
      (execution-id (var-get next-execution-id))
      (caller tx-sender)
    )
    (asserts! (> case-id u0) ERR-INVALID-INPUT)
    (asserts! (> (len environment) u0) ERR-INVALID-INPUT)

    (map-set test-executions
      { execution-id: execution-id }
      {
        case-id: case-id,
        executor: caller,
        start-time: block-height,
        end-time: none,
        status: u1,
        environment: environment,
        notes: ""
      }
    )

    (var-set next-execution-id (+ execution-id u1))
    (ok execution-id)
  )
)

(define-public (complete-test-execution (execution-id uint) (final-status uint) (notes (string-ascii 500)))
  (let
    (
      (execution-data (unwrap! (get-test-execution execution-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get executor execution-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status execution-data) u1) ERR-INVALID-STATE)
    (asserts! (and (>= final-status u2) (<= final-status u4)) ERR-INVALID-INPUT)

    (map-set test-executions
      { execution-id: execution-id }
      (merge execution-data {
        end-time: (some block-height),
        status: final-status,
        notes: notes
      })
    )

    (unwrap! (update-executor-metrics (get executor execution-data) final-status) ERR-INVALID-STATE)
    (ok true)
  )
)

(define-public (record-execution-result (execution-id uint) (result-type uint) (description (string-ascii 500)) (severity uint))
  (let
    (
      (result-id (var-get next-result-id))
      (execution-data (unwrap! (get-test-execution execution-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get executor execution-data)) ERR-UNAUTHORIZED)
    (asserts! (and (>= result-type u1) (<= result-type u3)) ERR-INVALID-INPUT)
    (asserts! (and (>= severity u1) (<= severity u4)) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)

    (map-set execution-results
      { result-id: result-id }
      {
        execution-id: execution-id,
        result-type: result-type,
        description: description,
        severity: severity,
        screenshot-hash: none,
        recorded-time: block-height
      }
    )

    (var-set next-result-id (+ result-id u1))
    (ok result-id)
  )
)

(define-public (add-screenshot-evidence (result-id uint) (screenshot-hash (string-ascii 64)))
  (let
    (
      (result-data (unwrap! (get-execution-result result-id) ERR-NOT-FOUND))
      (execution-data (unwrap! (get-test-execution (get execution-id result-data)) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get executor execution-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (len screenshot-hash) u64) ERR-INVALID-INPUT)

    (map-set execution-results
      { result-id: result-id }
      (merge result-data { screenshot-hash: (some screenshot-hash) })
    )
    (ok true)
  )
)

;; Private functions
(define-private (update-executor-metrics (executor principal) (test-result uint))
  (let
    (
      (current-metrics (default-to
        { total-executions: u0, passed-tests: u0, failed-tests: u0, average-duration: u0, last-execution: u0 }
        (get-executor-metrics executor)))
      (new-total (+ (get total-executions current-metrics) u1))
      (new-passed (if (is-eq test-result u2) (+ (get passed-tests current-metrics) u1) (get passed-tests current-metrics)))
      (new-failed (if (is-eq test-result u3) (+ (get failed-tests current-metrics) u1) (get failed-tests current-metrics)))
    )
    (map-set execution-metrics
      { executor: executor }
      {
        total-executions: new-total,
        passed-tests: new-passed,
        failed-tests: new-failed,
        average-duration: (get average-duration current-metrics),
        last-execution: block-height
      }
    )
    (ok true)
  )
)
