(define-non-fungible-token proof-of-play-nft uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-oracle (err u101))
(define-constant err-already-claimed (err u102))
(define-constant err-invalid-achievement (err u103))
(define-constant err-insufficient-playtime (err u104))
(define-constant err-nft-not-found (err u105))
(define-constant err-not-token-owner (err u106))
(define-constant err-invalid-game (err u107))
(define-constant err-oracle-exists (err u108))
(define-constant err-game-exists (err u109))
(define-constant err-invalid-streak (err u110))
(define-constant err-streak-already-claimed (err u111))

(define-data-var next-token-id uint u1)
(define-data-var next-game-id uint u1)
(define-data-var next-achievement-id uint u1)
(define-data-var next-streak-milestone-id uint u1)
(define-data-var global-leaderboard (list 100 {player: principal, total-playtime: uint, achievement-count: uint}) (list))

(define-map oracles principal bool)
(define-map games uint {name: (string-ascii 50), required-playtime: uint, active: bool})
(define-map achievements uint {name: (string-ascii 50), description: (string-ascii 100), game-id: uint, playtime-requirement: uint, active: bool})
(define-map player-progress principal {total-playtime: uint, games-played: (list 20 uint), achievements-earned: (list 50 uint)})
(define-map game-playtime {player: principal, game-id: uint} {total-time: uint, last-updated: uint})
(define-map achievement-claims {player: principal, achievement-id: uint} bool)
(define-map player-streak principal {current-streak: uint, longest-streak: uint, last-play-day: uint, multiplier: uint})
(define-map streak-milestones uint {days-required: uint, multiplier-bonus: uint, name: (string-ascii 50), active: bool})
(define-map streak-milestone-claims {player: principal, milestone-id: uint} bool)
(define-map nft-metadata uint {achievement-id: uint, player: principal, timestamp: uint, game-id: uint})

(define-read-only (get-last-token-id)
    (- (var-get next-token-id) u1)
)

(define-read-only (get-token-uri (token-id uint))
    (ok none)
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? proof-of-play-nft token-id))
)

(define-read-only (is-oracle (address principal))
    (default-to false (map-get? oracles address))
)

(define-read-only (get-game (game-id uint))
    (map-get? games game-id)
)

(define-read-only (get-achievement (achievement-id uint))
    (map-get? achievements achievement-id)
)

(define-read-only (get-player-progress (player principal))
    (default-to {total-playtime: u0, games-played: (list), achievements-earned: (list)} (map-get? player-progress player))
)

(define-read-only (get-player-game-playtime (player principal) (game-id uint))
    (default-to {total-time: u0, last-updated: u0} (map-get? game-playtime {player: player, game-id: game-id}))
)

(define-read-only (has-claimed-achievement (player principal) (achievement-id uint))
    (default-to false (map-get? achievement-claims {player: player, achievement-id: achievement-id}))
)

(define-read-only (get-nft-metadata (token-id uint))
    (map-get? nft-metadata token-id)
)

(define-read-only (can-claim-achievement (player principal) (achievement-id uint))
    (let (
        (achievement-data (unwrap! (get-achievement achievement-id) false))
        (game-id (get game-id achievement-data))
        (required-playtime (get playtime-requirement achievement-data))
        (player-game-data (get-player-game-playtime player game-id))
        (actual-playtime (get total-time player-game-data))
        (already-claimed (has-claimed-achievement player achievement-id))
        (achievement-active (get active achievement-data))
    )
        (and 
            achievement-active
            (not already-claimed)
            (>= actual-playtime required-playtime)
        )
    )
)

(define-read-only (get-leaderboard)
    (var-get global-leaderboard)
)

(define-read-only (get-player-rank (player principal))
    (let (
        (leaderboard (var-get global-leaderboard))
        (player-stats (get-player-progress player))
    )
        (index-of leaderboard {player: player, total-playtime: (get total-playtime player-stats), achievement-count: (len (get achievements-earned player-stats))})
    )
)

(define-read-only (get-player-streak (player principal))
    (default-to {current-streak: u0, longest-streak: u0, last-play-day: u0, multiplier: u100} (map-get? player-streak player))
)

(define-read-only (get-streak-milestone (milestone-id uint))
    (map-get? streak-milestones milestone-id)
)

(define-read-only (has-claimed-streak-milestone (player principal) (milestone-id uint))
    (default-to false (map-get? streak-milestone-claims {player: player, milestone-id: milestone-id}))
)

(define-read-only (can-claim-streak-milestone (player principal) (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) false))
        (days-required (get days-required milestone-data))
        (streak-data (get-player-streak player))
        (current-streak (get current-streak streak-data))
        (already-claimed (has-claimed-streak-milestone player milestone-id))
        (milestone-active (get active milestone-data))
    )
        (and
            milestone-active
            (not already-claimed)
            (>= current-streak days-required)
        )
    )
)

(define-private (update-leaderboard-entry (player principal) (playtime uint) (achievement-count uint))
    (let (
        (current-board (var-get global-leaderboard))
        (new-entry {player: player, total-playtime: playtime, achievement-count: achievement-count})
        (filtered-board (filter is-not-current-player current-board))
        (updated-board (unwrap-panic (as-max-len? (append filtered-board new-entry) u100)))
    )
        (var-set global-leaderboard updated-board)
        true
    )
)

(define-private (is-not-current-player (entry {player: principal, total-playtime: uint, achievement-count: uint}))
    (not (is-eq (get player entry) tx-sender))
)

(define-public (add-oracle (oracle-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (not (is-oracle oracle-address)) err-oracle-exists)
        (ok (map-set oracles oracle-address true))
    )
)

(define-public (remove-oracle (oracle-address principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-delete oracles oracle-address))
    )
)

(define-public (add-game (name (string-ascii 50)) (required-playtime uint))
    (let (
        (game-id (var-get next-game-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set games game-id {name: name, required-playtime: required-playtime, active: true})
        (var-set next-game-id (+ game-id u1))
        (ok game-id)
    )
)

(define-public (toggle-game-status (game-id uint))
    (let (
        (game-data (unwrap! (get-game game-id) err-invalid-game))
        (current-status (get active game-data))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set games game-id (merge game-data {active: (not current-status)})))
    )
)

(define-public (add-achievement (name (string-ascii 50)) (description (string-ascii 100)) (game-id uint) (playtime-requirement uint))
    (let (
        (achievement-id (var-get next-achievement-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-some (get-game game-id)) err-invalid-game)
        (map-set achievements achievement-id {
            name: name,
            description: description,
            game-id: game-id,
            playtime-requirement: playtime-requirement,
            active: true
        })
        (var-set next-achievement-id (+ achievement-id u1))
        (ok achievement-id)
    )
)

(define-public (toggle-achievement-status (achievement-id uint))
    (let (
        (achievement-data (unwrap! (get-achievement achievement-id) err-invalid-achievement))
        (current-status (get active achievement-data))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set achievements achievement-id (merge achievement-data {active: (not current-status)})))
    )
)

(define-public (add-streak-milestone (name (string-ascii 50)) (days-required uint) (multiplier-bonus uint))
    (let (
        (milestone-id (var-get next-streak-milestone-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set streak-milestones milestone-id {
            name: name,
            days-required: days-required,
            multiplier-bonus: multiplier-bonus,
            active: true
        })
        (var-set next-streak-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (toggle-streak-milestone-status (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) err-invalid-streak))
        (current-status (get active milestone-data))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set streak-milestones milestone-id (merge milestone-data {active: (not current-status)})))
    )
)

(define-public (update-playtime (player principal) (game-id uint) (playtime-minutes uint))
    (let (
        (current-data (get-player-game-playtime player game-id))
        (current-time (get total-time current-data))
        (streak-data (get-player-streak player))
        (current-streak (get current-streak streak-data))
        (longest-streak (get longest-streak streak-data))
        (last-play-day (get last-play-day streak-data))
        (current-multiplier (get multiplier streak-data))
        (current-day (/ stacks-block-height u144))
        (is-consecutive (is-eq (+ last-play-day u1) current-day))
        (is-same-day (is-eq last-play-day current-day))
        (new-streak (if is-same-day
                        current-streak
                        (if is-consecutive
                            (+ current-streak u1)
                            u1)))
        (new-longest (if (> new-streak longest-streak) new-streak longest-streak))
        (multiplied-playtime (/ (* playtime-minutes current-multiplier) u100))
        (new-total (+ current-time multiplied-playtime))
        (current-block u0)
        (player-data (get-player-progress player))
        (current-total-playtime (get total-playtime player-data))
        (current-games (get games-played player-data))
        (current-achievements (get achievements-earned player-data))
        (new-total-playtime (+ current-total-playtime multiplied-playtime))
        (achievement-count (len (get achievements-earned player-data)))
    )
        (asserts! (is-oracle tx-sender) err-not-oracle)
        (asserts! (is-some (get-game game-id)) err-invalid-game)
        (map-set game-playtime {player: player, game-id: game-id} {total-time: new-total, last-updated: current-block})
        (map-set player-progress player {
            total-playtime: new-total-playtime,
            games-played: (if (is-none (index-of current-games game-id))
                          (unwrap! (as-max-len? (append current-games game-id) u20) (ok true))
                          current-games),
            achievements-earned: current-achievements
        })
        (map-set player-streak player {
            current-streak: new-streak,
            longest-streak: new-longest,
            last-play-day: current-day,
            multiplier: current-multiplier
        })
        (update-leaderboard-entry player new-total-playtime achievement-count)
        (ok true)
    )
)

(define-public (claim-achievement (achievement-id uint))
    (let (
        (achievement-data (unwrap! (get-achievement achievement-id) err-invalid-achievement))
        (game-id (get game-id achievement-data))
        (token-id (var-get next-token-id))
        (current-block u0)
        (player-data (get-player-progress tx-sender))
        (current-achievements (get achievements-earned player-data))
        (new-achievements (unwrap! (as-max-len? (append current-achievements achievement-id) u50) err-invalid-achievement))
        (new-achievement-count (len new-achievements))
        (total-playtime (get total-playtime player-data))
    )
        (asserts! (can-claim-achievement tx-sender achievement-id) err-insufficient-playtime)
        (try! (nft-mint? proof-of-play-nft token-id tx-sender))
        (map-set achievement-claims {player: tx-sender, achievement-id: achievement-id} true)
        (map-set nft-metadata token-id {
            achievement-id: achievement-id,
            player: tx-sender,
            timestamp: current-block,
            game-id: game-id
        })
        (map-set player-progress tx-sender (merge player-data {
            achievements-earned: new-achievements
        }))
        (update-leaderboard-entry tx-sender total-playtime new-achievement-count)
        (var-set next-token-id (+ token-id u1))
        (ok token-id)
    )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (nft-transfer? proof-of-play-nft token-id sender recipient)
    )
)

(define-public (burn (token-id uint))
    (let (
        (owner (unwrap! (nft-get-owner? proof-of-play-nft token-id) err-nft-not-found))
    )
        (asserts! (is-eq tx-sender owner) err-not-token-owner)
        (nft-burn? proof-of-play-nft token-id owner)
    )
)

(define-public (claim-streak-milestone (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) err-invalid-streak))
        (multiplier-bonus (get multiplier-bonus milestone-data))
        (streak-data (get-player-streak tx-sender))
        (current-multiplier (get multiplier streak-data))
        (new-multiplier (+ current-multiplier multiplier-bonus))
    )
        (asserts! (can-claim-streak-milestone tx-sender milestone-id) err-insufficient-playtime)
        (map-set streak-milestone-claims {player: tx-sender, milestone-id: milestone-id} true)
        (map-set player-streak tx-sender (merge streak-data {
            multiplier: new-multiplier
        }))
        (ok new-multiplier)
    )
)


;; title: Proof-of-Play-NFT-Rewards
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

