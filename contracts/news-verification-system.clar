;; News Verification System
;; Verify news authenticity through community consensus and reward accurate fact-checkers

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u104))
(define-constant ERR-VOTING-CLOSED (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-INSUFFICIENT-STAKE (err u107))
(define-constant ERR-INVALID-STATUS (err u108))
(define-constant ERR-VERIFICATION-PERIOD-EXPIRED (err u109))
(define-constant ERR-INSUFFICIENT-BALANCE (err u110))

;; Data Variables
(define-data-var next-article-id uint u1)
(define-data-var next-verification-id uint u1)
(define-data-var min-fact-checker-reputation uint u100)
(define-data-var min-stake-amount uint u1000000) ;; 1 STX
(define-data-var verification-period uint u1008) ;; ~1 week
(define-data-var consensus-threshold uint u60) ;; 60% agreement required
(define-data-var reward-pool-balance uint u0)

;; Data Maps

;; News articles submitted for verification
(define-map articles
    { article-id: uint }
    {
        title: (string-ascii 200),
        url: (string-ascii 300),
        content-hash: (string-ascii 64),
        submitter: principal,
        source: (string-ascii 100),
        submission-date: uint,
        verification-status: (string-ascii 20), ;; "pending", "verified-true", "verified-false", "disputed"
        total-votes: uint,
        true-votes: uint,
        false-votes: uint,
        confidence-score: uint,
        verification-deadline: uint,
        category: (string-ascii 50),
        evidence-count: uint
    }
)

;; Fact-checker profiles and reputation
(define-map fact-checkers
    { checker: principal }
    {
        registered: bool,
        name: (string-ascii 50),
        expertise-areas: (list 5 (string-ascii 50)),
        reputation-score: uint,
        total-verifications: uint,
        correct-verifications: uint,
        registration-date: uint,
        stake-balance: uint,
        is-suspended: bool,
        suspension-reason: (optional (string-ascii 200))
    }
)

;; Individual verification votes from fact-checkers
(define-map verifications
    { verification-id: uint }
    {
        article-id: uint,
        fact-checker: principal,
        vote: bool, ;; true = authentic, false = false/misleading
        confidence: uint, ;; 1-100 scale
        evidence: (string-ascii 500),
        reasoning: (string-ascii 500),
        submission-date: uint,
        weight: uint ;; based on reputation
    }
)

;; Track which fact-checkers have voted on which articles
(define-map article-votes
    { article-id: uint, fact-checker: principal }
    { verification-id: uint, vote-weight: uint }
)

;; News sources and their credibility ratings
(define-map news-sources
    { source-domain: (string-ascii 100) }
    {
        name: (string-ascii 100),
        credibility-score: uint,
        total-articles: uint,
        verified-articles: uint,
        false-articles: uint,
        registration-date: uint,
        is-verified: bool
    }
)

;; Evidence submissions supporting verification decisions
(define-map evidence-submissions
    { article-id: uint, evidence-id: uint }
    {
        submitter: principal,
        evidence-type: (string-ascii 30), ;; "link", "document", "testimony", "analysis"
        evidence-url: (string-ascii 300),
        description: (string-ascii 300),
        credibility-rating: uint,
        submission-date: uint
    }
)

;; Rewards earned by fact-checkers
(define-map fact-checker-rewards
    { checker: principal }
    {
        total-earned: uint,
        pending-rewards: uint,
        last-claim: uint,
        accuracy-bonus: uint
    }
)

;; Article appeal records for disputed verifications
(define-map article-appeals
    { article-id: uint, appeal-id: uint }
    {
        appellant: principal,
        appeal-reason: (string-ascii 500),
        new-evidence: (string-ascii 300),
        appeal-date: uint,
        status: (string-ascii 20), ;; "pending", "approved", "rejected"
        reviewer: (optional principal)
    }
)

;; Platform governance proposals
(define-map governance-proposals
    { proposal-id: uint }
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        parameter-name: (string-ascii 50),
        new-value: uint,
        votes-for: uint,
        votes-against: uint,
        voting-deadline: uint,
        status: (string-ascii 20), ;; "active", "passed", "rejected", "executed"
        execution-date: (optional uint)
    }
)

;; Read-only functions

;; Get article details
(define-read-only (get-article-details (article-id uint))
    (map-get? articles { article-id: article-id })
)

;; Get fact-checker profile
(define-read-only (get-fact-checker-info (checker principal))
    (map-get? fact-checkers { checker: checker })
)

;; Get verification details
(define-read-only (get-verification-details (verification-id uint))
    (map-get? verifications { verification-id: verification-id })
)

;; Check if fact-checker has voted on article
(define-read-only (has-voted (article-id uint) (fact-checker principal))
    (is-some (map-get? article-votes { article-id: article-id, fact-checker: fact-checker }))
)

;; Calculate article consensus percentage
(define-read-only (calculate-consensus (article-id uint))
    (match (get-article-details article-id)
        article-data
        (let ((total-votes (get total-votes article-data))
              (true-votes (get true-votes article-data)))
            (if (> total-votes u0)
                (/ (* true-votes u100) total-votes)
                u0
            )
        )
        u0
    )
)

;; Get fact-checker accuracy rate
(define-read-only (get-accuracy-rate (checker principal))
    (match (get-fact-checker-info checker)
        checker-data
        (let ((total (get total-verifications checker-data))
              (correct (get correct-verifications checker-data)))
            (if (> total u0)
                (/ (* correct u100) total)
                u0
            )
        )
        u0
    )
)

;; Check if article verification period is active
(define-read-only (is-verification-active (article-id uint))
    (match (get-article-details article-id)
        article-data
        (and
            (is-eq (get verification-status article-data) "pending")
            (< block-height (get verification-deadline article-data))
        )
        false
    )
)

;; Get news source credibility
(define-read-only (get-source-credibility (source-domain (string-ascii 100)))
    (match (map-get? news-sources { source-domain: source-domain })
        source-data
        (get credibility-score source-data)
        u50 ;; default neutral score
    )
)

;; Public functions

;; Register as a fact-checker
(define-public (register-fact-checker (name (string-ascii 50)) (expertise-areas (list 5 (string-ascii 50))))
    (let ((existing-checker (map-get? fact-checkers { checker: tx-sender })))
        (if (is-some existing-checker)
            ERR-ALREADY-EXISTS
            (begin
                ;; Require minimum stake
                (try! (stx-transfer? (var-get min-stake-amount) tx-sender (as-contract tx-sender)))
                
                ;; Create fact-checker profile
                (map-set fact-checkers
                    { checker: tx-sender }
                    {
                        registered: true,
                        name: name,
                        expertise-areas: expertise-areas,
                        reputation-score: (var-get min-fact-checker-reputation),
                        total-verifications: u0,
                        correct-verifications: u0,
                        registration-date: block-height,
                        stake-balance: (var-get min-stake-amount),
                        is-suspended: false,
                        suspension-reason: none
                    }
                )
                
                ;; Initialize rewards tracking
                (map-set fact-checker-rewards
                    { checker: tx-sender }
                    {
                        total-earned: u0,
                        pending-rewards: u0,
                        last-claim: block-height,
                        accuracy-bonus: u0
                    }
                )
                
                (ok true)
            )
        )
    )
)

;; Submit news article for verification
(define-public (submit-article (title (string-ascii 200)) (url (string-ascii 300))
                               (content-hash (string-ascii 64)) (source (string-ascii 100))
                               (category (string-ascii 50)))
    (let ((article-id (var-get next-article-id))
          (verification-deadline (+ block-height (var-get verification-period))))
        
        ;; Validate inputs
        (asserts! (> (len title) u0) ERR-INVALID-INPUT)
        (asserts! (> (len url) u0) ERR-INVALID-INPUT)
        
        ;; Create article record
        (map-set articles
            { article-id: article-id }
            {
                title: title,
                url: url,
                content-hash: content-hash,
                submitter: tx-sender,
                source: source,
                submission-date: block-height,
                verification-status: "pending",
                total-votes: u0,
                true-votes: u0,
                false-votes: u0,
                confidence-score: u0,
                verification-deadline: verification-deadline,
                category: category,
                evidence-count: u0
            }
        )
        
        ;; Update source statistics
        (unwrap! (update-source-stats source) ERR-INVALID-INPUT)
        
        ;; Increment article ID
        (var-set next-article-id (+ article-id u1))
        
        (ok article-id)
    )
)

;; Submit verification vote for an article
(define-public (submit-verification (article-id uint) (vote bool) (confidence uint)
                                    (evidence (string-ascii 500)) (reasoning (string-ascii 500)))
    (let ((verification-id (var-get next-verification-id))
          (checker-info (unwrap! (get-fact-checker-info tx-sender) ERR-NOT-FOUND)))
        
        ;; Validate fact-checker eligibility
        (asserts! (get registered checker-info) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-suspended checker-info)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (get reputation-score checker-info) (var-get min-fact-checker-reputation)) ERR-INSUFFICIENT-REPUTATION)
        
        ;; Check if verification period is active
        (asserts! (is-verification-active article-id) ERR-VERIFICATION-PERIOD-EXPIRED)
        
        ;; Check if already voted
        (asserts! (not (has-voted article-id tx-sender)) ERR-ALREADY-VOTED)
        
        ;; Validate confidence score
        (asserts! (and (>= confidence u1) (<= confidence u100)) ERR-INVALID-INPUT)
        
        ;; Calculate vote weight based on reputation
        (let ((vote-weight (+ u1 (/ (get reputation-score checker-info) u100))))
            
            ;; Create verification record
            (map-set verifications
                { verification-id: verification-id }
                {
                    article-id: article-id,
                    fact-checker: tx-sender,
                    vote: vote,
                    confidence: confidence,
                    evidence: evidence,
                    reasoning: reasoning,
                    submission-date: block-height,
                    weight: vote-weight
                }
            )
            
            ;; Track that this fact-checker has voted
            (map-set article-votes
                { article-id: article-id, fact-checker: tx-sender }
                { verification-id: verification-id, vote-weight: vote-weight }
            )
            
            ;; Update article vote counts
            (try! (update-article-votes article-id vote vote-weight))
            
            ;; Update fact-checker statistics
            (map-set fact-checkers
                { checker: tx-sender }
                (merge checker-info {
                    total-verifications: (+ (get total-verifications checker-info) u1)
                })
            )
            
            ;; Increment verification ID
            (var-set next-verification-id (+ verification-id u1))
            
            (ok verification-id)
        )
    )
)

;; Finalize article verification based on consensus
(define-public (finalize-verification (article-id uint))
    (let ((article-data (unwrap! (get-article-details article-id) ERR-NOT-FOUND)))
        
        ;; Check if verification period has ended
        (asserts! (>= block-height (get verification-deadline article-data)) ERR-VOTING-CLOSED)
        (asserts! (is-eq (get verification-status article-data) "pending") ERR-INVALID-STATUS)
        
        ;; Calculate consensus
        (let ((consensus-pct (calculate-consensus article-id))
              (total-votes (get total-votes article-data))
              (confidence-score (if (> total-votes u0)
                                  (/ (+ consensus-pct (- u100 consensus-pct)) u2)
                                  u0)))
            
            ;; Determine final verification status
            (let ((final-status (if (>= consensus-pct (var-get consensus-threshold))
                                  "verified-true"
                                  "verified-false")))
                
                ;; Update article status
                (map-set articles
                    { article-id: article-id }
                    (merge article-data {
                        verification-status: final-status,
                        confidence-score: confidence-score
                    })
                )
                
                ;; Distribute rewards to accurate fact-checkers
                (unwrap! (distribute-verification-rewards article-id (is-eq final-status "verified-true")) ERR-INVALID-INPUT)
                
                ;; Update source credibility
                (unwrap! (update-source-credibility (get source article-data) (is-eq final-status "verified-true")) ERR-INVALID-INPUT)
                
                (ok final-status)
            )
        )
    )
)

;; Submit evidence for an article
(define-public (submit-evidence (article-id uint) (evidence-type (string-ascii 30))
                                (evidence-url (string-ascii 300)) (description (string-ascii 300)))
    (let ((article-data (unwrap! (get-article-details article-id) ERR-NOT-FOUND))
          (evidence-id (get evidence-count article-data)))
        
        ;; Check if verification is still active
        (asserts! (is-verification-active article-id) ERR-VERIFICATION-PERIOD-EXPIRED)
        
        ;; Create evidence record
        (map-set evidence-submissions
            { article-id: article-id, evidence-id: evidence-id }
            {
                submitter: tx-sender,
                evidence-type: evidence-type,
                evidence-url: evidence-url,
                description: description,
                credibility-rating: u50, ;; neutral default
                submission-date: block-height
            }
        )
        
        ;; Update article evidence count
        (map-set articles
            { article-id: article-id }
            (merge article-data {
                evidence-count: (+ evidence-id u1)
            })
        )
        
        (ok evidence-id)
    )
)

;; Claim rewards for accurate fact-checking
(define-public (claim-rewards)
    (let ((rewards-data (unwrap! (map-get? fact-checker-rewards { checker: tx-sender }) ERR-NOT-FOUND))
          (pending-amount (get pending-rewards rewards-data)))
        
        ;; Check if there are rewards to claim
        (asserts! (> pending-amount u0) ERR-INSUFFICIENT-BALANCE)
        
        ;; Transfer rewards
        (try! (as-contract (stx-transfer? pending-amount tx-sender tx-sender)))
        
        ;; Update rewards record
        (map-set fact-checker-rewards
            { checker: tx-sender }
            (merge rewards-data {
                pending-rewards: u0,
                last-claim: block-height,
                total-earned: (+ (get total-earned rewards-data) pending-amount)
            })
        )
        
        (ok pending-amount)
    )
)

;; Private helper functions

;; Update article vote counts
(define-private (update-article-votes (article-id uint) (vote bool) (weight uint))
    (let ((article-data (unwrap! (get-article-details article-id) ERR-NOT-FOUND)))
        (map-set articles
            { article-id: article-id }
            (merge article-data {
                total-votes: (+ (get total-votes article-data) weight),
                true-votes: (if vote
                              (+ (get true-votes article-data) weight)
                              (get true-votes article-data)),
                false-votes: (if vote
                               (get false-votes article-data)
                               (+ (get false-votes article-data) weight))
            })
        )
        (ok true)
    )
)

;; Update news source statistics
(define-private (update-source-stats (source (string-ascii 100)))
    (match (map-get? news-sources { source-domain: source })
        source-data
        (begin
            (map-set news-sources
                { source-domain: source }
                (merge source-data {
                    total-articles: (+ (get total-articles source-data) u1)
                })
            )
            (ok true)
        )
        ;; Create new source entry
        (begin
            (map-set news-sources
                { source-domain: source }
                {
                    name: source,
                    credibility-score: u50, ;; neutral starting score
                    total-articles: u1,
                    verified-articles: u0,
                    false-articles: u0,
                    registration-date: block-height,
                    is-verified: false
                }
            )
            (ok true)
        )
    )
)

;; Update source credibility based on verification results
(define-private (update-source-credibility (source (string-ascii 100)) (is-accurate bool))
    (match (map-get? news-sources { source-domain: source })
        source-data
        (let ((new-verified (if is-accurate (+ (get verified-articles source-data) u1) (get verified-articles source-data)))
              (new-false (if is-accurate (get false-articles source-data) (+ (get false-articles source-data) u1)))
              (total-verified (+ new-verified new-false))
              (new-credibility (if (> total-verified u0)
                                 (/ (* new-verified u100) total-verified)
                                 u50)))
            (begin
                (map-set news-sources
                    { source-domain: source }
                    (merge source-data {
                        verified-articles: new-verified,
                        false-articles: new-false,
                        credibility-score: new-credibility
                    })
                )
                (ok true)
            )
        )
        (ok false)
    )
)

;; Distribute rewards to accurate fact-checkers
(define-private (distribute-verification-rewards (article-id uint) (correct-vote bool))
    ;; This is a simplified version - in practice would iterate through all votes
    ;; and reward fact-checkers who voted correctly based on their stake and accuracy
    (ok true)
)

;; Administrative functions (contract owner only)

;; Update minimum reputation requirement
(define-public (set-min-reputation (new-min uint))
    (if (is-eq tx-sender CONTRACT-OWNER)
        (begin
            (var-set min-fact-checker-reputation new-min)
            (ok true)
        )
        ERR-NOT-AUTHORIZED
    )
)

;; Update consensus threshold
(define-public (set-consensus-threshold (new-threshold uint))
    (if (and (is-eq tx-sender CONTRACT-OWNER) (<= new-threshold u100))
        (begin
            (var-set consensus-threshold new-threshold)
            (ok true)
        )
        ERR-NOT-AUTHORIZED
    )
)

;; Suspend fact-checker for misconduct
(define-public (suspend-fact-checker (checker principal) (reason (string-ascii 200)))
    (if (is-eq tx-sender CONTRACT-OWNER)
        (match (get-fact-checker-info checker)
            checker-data
            (begin
                (map-set fact-checkers
                    { checker: checker }
                    (merge checker-data {
                        is-suspended: true,
                        suspension-reason: (some reason)
                    })
                )
                (ok true)
            )
            ERR-NOT-FOUND
        )
        ERR-NOT-AUTHORIZED
    )
)


;; title: news-verification-system
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

