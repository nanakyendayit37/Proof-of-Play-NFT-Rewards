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
(define-constant err-streak-broken (err u110))
(define-constant err-milestone-claimed (err u111))
(define-constant err-invalid-milestone (err u112))

(define-data-var next-token-id uint u1)
(define-data-var next-game-id uint u1)
(define-data-var next-achievement-id uint u1)

(define-map oracles principal bool)
(define-map games uint {name: (string-ascii 50), required-playtime: uint, active: bool})
(define-map achievements uint {name: (string-ascii 50), description: (string-ascii 100), game-id: uint, playtime-requirement: uint, active: bool})
(define-map player-progress principal {total-playtime: uint, games-played: (list 20 uint), achievements-earned: (list 50 uint)})
(define-map game-playtime {player: principal, game-id: uint} {total-time: uint, last-updated: uint})
(define-map achievement-claims {player: principal, achievement-id: uint} bool)
(define-map nft-metadata uint {achievement-id: uint, player: principal, timestamp: uint, game-id: uint})
(define-map leaderboard-entries principal {score: uint, rank: uint, last-updated: uint})
(define-data-var leaderboard-players (list 100 principal) (list))
(define-map player-streaks principal {current-streak: uint, longest-streak: uint, last-play-day: uint, total-streak-days: uint})
(define-map streak-milestones uint {days-required: uint, bonus-multiplier: uint, active: bool})
(define-map milestone-claims {player: principal, milestone-id: uint} bool)
(define-data-var next-milestone-id uint u1)

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

(define-read-only (get-leaderboard-entry (player principal))
    (map-get? leaderboard-entries player)
)

(define-read-only (get-leaderboard)
    (ok (var-get leaderboard-players))
)

(define-read-only (get-player-rank (player principal))
    (match (get-leaderboard-entry player)
        entry (ok (get rank entry))
        (ok u0)
    )
)

(define-read-only (get-player-streak (player principal))
    (default-to {current-streak: u0, longest-streak: u0, last-play-day: u0, total-streak-days: u0} (map-get? player-streaks player))
)

(define-read-only (get-streak-milestone (milestone-id uint))
    (map-get? streak-milestones milestone-id)
)

(define-read-only (has-claimed-milestone (player principal) (milestone-id uint))
    (default-to false (map-get? milestone-claims {player: player, milestone-id: milestone-id}))
)

(define-read-only (can-claim-milestone (player principal) (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) false))
        (days-required (get days-required milestone-data))
        (player-streak-data (get-player-streak player))
        (current-streak (get current-streak player-streak-data))
        (already-claimed (has-claimed-milestone player milestone-id))
        (milestone-active (get active milestone-data))
    )
        (and 
            milestone-active
            (not already-claimed)
            (>= current-streak days-required)
        )
    )
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

(define-public (add-streak-milestone (days-required uint) (bonus-multiplier uint))
    (let (
        (milestone-id (var-get next-milestone-id))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set streak-milestones milestone-id {
            days-required: days-required,
            bonus-multiplier: bonus-multiplier,
            active: true
        })
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (toggle-milestone-status (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) err-invalid-milestone))
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
        (new-total (+ current-time playtime-minutes))
        (current-block u0)
        (player-data (get-player-progress player))
        (current-total-playtime (get total-playtime player-data))
        (current-games (get games-played player-data))
        (current-achievements (get achievements-earned player-data))
    )
        (asserts! (is-oracle tx-sender) err-not-oracle)
        (asserts! (is-some (get-game game-id)) err-invalid-game)
        (map-set game-playtime {player: player, game-id: game-id} {total-time: new-total, last-updated: current-block})
        (map-set player-progress player {
            total-playtime: (+ current-total-playtime playtime-minutes),
            games-played: (if (is-none (index-of current-games game-id))
                          (unwrap! (as-max-len? (append current-games game-id) u20) (ok true))
                          current-games),
            achievements-earned: current-achievements
        })
        (update-player-streak player current-block)
        (update-leaderboard player)
        (ok true)
    )
)

(define-public (claim-streak-milestone (milestone-id uint))
    (let (
        (milestone-data (unwrap! (get-streak-milestone milestone-id) err-invalid-milestone))
        (bonus-multiplier (get bonus-multiplier milestone-data))
        (token-id (var-get next-token-id))
        (current-block u0)
        (player-streak-data (get-player-streak tx-sender))
    )
        (asserts! (can-claim-milestone tx-sender milestone-id) err-streak-broken)
        (try! (nft-mint? proof-of-play-nft token-id tx-sender))
        (map-set milestone-claims {player: tx-sender, milestone-id: milestone-id} true)
        (map-set nft-metadata token-id {
            achievement-id: u0,
            player: tx-sender,
            timestamp: current-block,
            game-id: u0
        })
        (update-leaderboard tx-sender)
        (var-set next-token-id (+ token-id u1))
        (ok token-id)
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
            achievements-earned: (unwrap! (as-max-len? (append current-achievements achievement-id) u50) err-invalid-achievement)
        }))
        (update-leaderboard tx-sender)
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

(define-private (calculate-player-score (player principal))
    (let (
        (player-data (get-player-progress player))
        (total-playtime (get total-playtime player-data))
        (achievement-count (len (get achievements-earned player-data)))
    )
        (+ total-playtime (* achievement-count u1000))
    )
)

(define-private (update-leaderboard (player principal))
    (let (
        (player-score (calculate-player-score player))
        (current-leaderboard (var-get leaderboard-players))
        (current-block u0)
    )
        (begin
            (map-set leaderboard-entries player {score: player-score, rank: u0, last-updated: current-block})
            (var-set leaderboard-players 
                (if (is-none (index-of current-leaderboard player))
                    (unwrap-panic (as-max-len? (append current-leaderboard player) u100))
                    current-leaderboard
                )
            )
            true
        )
    )
)

(define-private (update-player-streak (player principal) (current-day uint))
    (let (
        (streak-data (get-player-streak player))
        (current-streak (get current-streak streak-data))
        (longest-streak (get longest-streak streak-data))
        (last-play-day (get last-play-day streak-data))
        (total-streak-days (get total-streak-days streak-data))
        (day-diff (if (> current-day last-play-day) (- current-day last-play-day) u0))
        (new-streak (if (is-eq day-diff u1)
                        (+ current-streak u1)
                        (if (is-eq day-diff u0)
                            current-streak
                            u1)))
        (new-longest (if (> new-streak longest-streak) new-streak longest-streak))
        (new-total (if (is-eq day-diff u0) total-streak-days (+ total-streak-days u1)))
    )
        (map-set player-streaks player {
            current-streak: new-streak,
            longest-streak: new-longest,
            last-play-day: current-day,
            total-streak-days: new-total
        })
        true
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

