;; Defect Tracking Contract
;; Tracks and manages quality defects throughout their lifecycle

;; Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u104))

;; Data Variables
(define-data-var next-defect-id uint u1)
(define-data-var next-comment-id uint u1)

;; Data Maps
(define-map defects
  { defect-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    reporter: principal,
    assignee: (optional principal),
    severity: uint,
    priority: uint,
    status: uint,
    test-case-id: (optional uint),
    created-date: uint,
    resolved-date: (optional uint),
    resolution-notes: (string-ascii 500)
  }
)

(define-map defect-comments
  { comment-id: uint }
  {
    defect-id: uint,
    author: principal,
    content: (string-ascii 500),
    timestamp: uint,
    comment-type: uint
  }
)

(define-map defect-metrics
  { reporter: principal }
  {
    total-reported: uint,
    critical-defects: uint,
    resolved-defects: uint,
    average-resolution-time: uint
  }
)

;; Read-only functions
(define-read-only (get-defect (defect-id uint))
  (map-get? defects { defect-id: defect-id })
)

(define-read-only (get-defect-comment (comment-id uint))
  (map-get? defect-comments { comment-id: comment-id })
)

(define-read-only (get-reporter-metrics (reporter principal))
  (map-get? defect-metrics { reporter: reporter })
)

(define-read-only (get-next-defect-id)
  (var-get next-defect-id)
)

(define-read-only (get-next-comment-id)
  (var-get next-comment-id)
)

;; Public functions
(define-public (report-defect (title (string-ascii 100)) (description (string-ascii 500)) (severity uint) (test-case-id (optional uint)))
  (let
    (
      (defect-id (var-get next-defect-id))
      (caller tx-sender)
    )
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= severity u1) (<= severity u4)) ERR-INVALID-INPUT)

    (map-set defects
      { defect-id: defect-id }
      {
        title: title,
        description: description,
        reporter: caller,
        assignee: none,
        severity: severity,
        priority: severity,
        status: u1,
        test-case-id: test-case-id,
        created-date: block-height,
        resolved-date: none,
        resolution-notes: ""
      }
    )

    (unwrap! (update-reporter-metrics caller severity) ERR-INVALID-STATE)
    (var-set next-defect-id (+ defect-id u1))
    (ok defect-id)
  )
)

(define-public (assign-defect (defect-id uint) (assignee principal))
  (let
    (
      (defect-data (unwrap! (get-defect defect-id) ERR-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get reporter defect-data))
                  (is-some (get assignee defect-data))) ERR-UNAUTHORIZED)

    (map-set defects
      { defect-id: defect-id }
      (merge defect-data { assignee: (some assignee) })
    )
    (ok true)
  )
)

(define-public (update-defect-status (defect-id uint) (new-status uint))
  (let
    (
      (defect-data (unwrap! (get-defect defect-id) ERR-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get reporter defect-data))
                  (is-eq (some tx-sender) (get assignee defect-data))) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u5)) ERR-INVALID-INPUT)

    (map-set defects
      { defect-id: defect-id }
      (merge defect-data {
        status: new-status,
        resolved-date: (if (>= new-status u4) (some block-height) none)
      })
    )
    (ok true)
  )
)

(define-public (resolve-defect (defect-id uint) (resolution-notes (string-ascii 500)))
  (let
    (
      (defect-data (unwrap! (get-defect defect-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq (some tx-sender) (get assignee defect-data)) ERR-UNAUTHORIZED)
    (asserts! (> (len resolution-notes) u0) ERR-INVALID-INPUT)

    (map-set defects
      { defect-id: defect-id }
      (merge defect-data {
        status: u4,
        resolved-date: (some block-height),
        resolution-notes: resolution-notes
      })
    )
    (ok true)
  )
)

(define-public (add-defect-comment (defect-id uint) (content (string-ascii 500)) (comment-type uint))
  (let
    (
      (comment-id (var-get next-comment-id))
      (defect-data (unwrap! (get-defect defect-id) ERR-NOT-FOUND))
    )
    (asserts! (> (len content) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= comment-type u1) (<= comment-type u3)) ERR-INVALID-INPUT)

    (map-set defect-comments
      { comment-id: comment-id }
      {
        defect-id: defect-id,
        author: tx-sender,
        content: content,
        timestamp: block-height,
        comment-type: comment-type
      }
    )

    (var-set next-comment-id (+ comment-id u1))
    (ok comment-id)
  )
)

(define-public (update-defect-priority (defect-id uint) (new-priority uint))
  (let
    (
      (defect-data (unwrap! (get-defect defect-id) ERR-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get reporter defect-data))
                  (is-eq (some tx-sender) (get assignee defect-data))) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-priority u1) (<= new-priority u4)) ERR-INVALID-INPUT)

    (map-set defects
      { defect-id: defect-id }
      (merge defect-data { priority: new-priority })
    )
    (ok true)
  )
)

;; Private functions
(define-private (update-reporter-metrics (reporter principal) (severity uint))
  (let
    (
      (current-metrics (default-to
        { total-reported: u0, critical-defects: u0, resolved-defects: u0, average-resolution-time: u0 }
        (get-reporter-metrics reporter)))
      (new-total (+ (get total-reported current-metrics) u1))
      (new-critical (if (is-eq severity u1) (+ (get critical-defects current-metrics) u1) (get critical-defects current-metrics)))
    )
    (map-set defect-metrics
      { reporter: reporter }
      {
        total-reported: new-total,
        critical-defects: new-critical,
        resolved-defects: (get resolved-defects current-metrics),
        average-resolution-time: (get average-resolution-time current-metrics)
      }
    )
    (ok true)
  )
)
