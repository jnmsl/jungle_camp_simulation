; =============================================================================
; DSCHUNGELCAMP SOCIAL DYNAMICS SIMULATION
; Graph Analysis and Social Networks - UPM Master in Data Science
; =============================================================================
; Simulates trust, reputation, and alliance dynamics among contestants
; in a Jungle Camp reality TV show using Multi-Agent Systems (MAS).
;
; Key course concepts applied:
;   - BDI Agent Architecture (Beliefs, Desires, Intentions)
;   - Trust & Reputation models (Mui et al. computational trust)
;   - Social Network Evolution (shrinking network via elimination)
;   - Emergent behavior from simple interaction rules
;   - Cooperation vs. Defection (game theory)
; =============================================================================

; --- Global variables ---
globals [
  current-day              ; Current simulation day
  food-pool                ; Shared food available for the camp
  elimination-interval     ; How many days between elimination rounds
  next-elimination-day     ; Day of next elimination vote
  num-eliminated           ; Count of eliminated contestants
  avg-trust                ; Average trust across all active links
  avg-reputation           ; Average reputation across active agents
  winner                   ; The winning agent (last one standing)
  season-over?             ; Flag for end of simulation
  gossip-spread-factor     ; How much indirect info influences trust
  initial-num-contestants  ; Store initial count
  challenge-reward         ; Food earned from successful challenge
  base-energy-cost         ; Daily energy cost per agent
  trust-alpha              ; Beta distribution prior alpha
  trust-beta               ; Beta distribution prior beta
  link-break-threshold     ; Trust below this hides the link (broken relationship)
  total-cooperations       ; Total cooperative actions observed
  total-interactions       ; Total interactions observed
]

; --- Agent (contestant) properties ---
turtles-own [
  strategy               ; "cooperator" / "strategist" / "freerider" / "social"
  energy                 ; Current energy level (0-100)
  reputation-score       ; Global reputation (0-1)
  eliminated?            ; Whether this contestant has been eliminated
  elimination-day        ; Day when eliminated (-1 if still active)
  challenge-successes    ; Number of successful challenges
  challenge-attempts     ; Number of challenge attempts
  days-survived          ; How many days the agent survived
  alliance-id            ; Alliance group identifier
  personality-openness   ; How likely to form new connections (0-1)
  personality-loyalty    ; How much they weight existing trust (0-1)
  personality-bravery    ; Likelihood of accepting challenges (0-1)
  votes-received         ; Votes received in current elimination round
  voted-for              ; Who this agent voted for
]

; --- Link (relationship) properties ---
links-own [
  trust-value            ; Current trust T_ab (0-1)
  encounters             ; Total number of encounters n
  cooperations           ; Number of cooperative encounters p
  relationship-type      ; "alliance" / "neutral" / "rival"
  last-social-day        ; Day of last social encounter (prevents double counting)
]

; =============================================================================
; SETUP PROCEDURES
; =============================================================================

to setup
  clear-all
  set-default-shape turtles "person"

  ; Initialize globals
  set current-day 0
  set food-pool 50
  set elimination-interval elimination-every-n-days
  set next-elimination-day elimination-interval
  set num-eliminated 0
  set avg-trust 0.5
  set avg-reputation 0.5
  set winner nobody
  set season-over? false
  set gossip-spread-factor 0.3
  set initial-num-contestants num-contestants
  set challenge-reward 15
  set base-energy-cost 5
  set trust-alpha 1  ; Prior: uniform
  set trust-beta 1
  set link-break-threshold 0.2  ; Links hidden when trust drops below this
  set total-cooperations 0
  set total-interactions 0

  ; Create contestants
  create-contestants
  ; Create initial social network (everyone knows everyone in the camp)
  create-initial-network
  ; Layout
  layout-agents

  reset-ticks
end

to create-contestants
  create-turtles num-contestants [
    ; Assign strategy based on slider proportions
    let roll random 100
    ifelse roll < pct-cooperators [
      set strategy "cooperator"
      set color green
    ] [
      ifelse roll < (pct-cooperators + pct-strategists) [
        set strategy "strategist"
        set color blue
      ] [
        ifelse roll < (pct-cooperators + pct-strategists + pct-freeriders) [
          set strategy "freerider"
          set color red
        ] [
          set strategy "social"
          set color yellow
        ]
      ]
    ]

    ; Initialize attributes
    set energy 80 + random 21  ; 80-100
    set reputation-score 0.5   ; Neutral starting reputation
    set eliminated? false
    set elimination-day -1
    set challenge-successes 0
    set challenge-attempts 0
    set days-survived 0
    set alliance-id -1
    set votes-received 0
    set voted-for nobody

    ; Personality traits (vary by strategy but with randomness)
    set-personality-traits

    set size 2.5
    set label (word who " ")
  ]
end

to set-personality-traits
  if strategy = "cooperator" [
    set personality-openness 0.6 + random-float 0.3
    set personality-loyalty 0.7 + random-float 0.3
    set personality-bravery 0.7 + random-float 0.3
  ]
  if strategy = "strategist" [
    set personality-openness 0.4 + random-float 0.4
    set personality-loyalty 0.5 + random-float 0.4
    set personality-bravery 0.4 + random-float 0.4
  ]
  if strategy = "freerider" [
    set personality-openness 0.3 + random-float 0.3
    set personality-loyalty 0.2 + random-float 0.3
    set personality-bravery 0.1 + random-float 0.3
  ]
  if strategy = "social" [
    set personality-openness 0.8 + random-float 0.2
    set personality-loyalty 0.4 + random-float 0.3
    set personality-bravery 0.3 + random-float 0.4
  ]
end

to create-initial-network
  ; Everyone starts with a link to everyone else (they're all in the same camp)
  ask turtles [
    create-links-with other turtles [
      set trust-value 0.5  ; Neutral initial trust
      set encounters 0
      set cooperations 0
      set relationship-type "neutral"
      set last-social-day -1
      set color gray
      set thickness 0.1
    ]
  ]
end

to layout-agents
  ; Arrange in a circle
  layout-circle turtles (max-pxcor * 0.7)

  ; Move eliminated agents to the side
  ask turtles with [eliminated?] [
    ; Calculate a safe Y coordinate by scaling down the elimination day
    let safe-y (max-pycor - 2 - ((elimination-day / elimination-interval) * 2))

    ; Extra safety: prevent the y-coordinate from ever going below the world boundary
    if safe-y < min-pycor [ set safe-y min-pycor ]

    setxy (max-pxcor - 2) safe-y
  ]
end

; =============================================================================
; MAIN SIMULATION LOOP
; =============================================================================

to go
  if season-over? [ stop ]

  set current-day current-day + 1

  ; Count active contestants
  let active-agents turtles with [not eliminated?]
  let num-active count active-agents

  ; Check if season is over (1 contestant left)
  if num-active <= 1 [
    set season-over? true
    if num-active = 1 [
      set winner one-of active-agents
      ask winner [ set label (word who " WINNER!") ]
    ]
    stop
  ]

  ; Update days survived (before elimination so eliminated agents get correct count)
  ask active-agents [ set days-survived current-day ]

  ; === PHASE 1: CHALLENGE ===
  challenge-phase active-agents

  ; === PHASE 2: FOOD SHARING & ENERGY ===
  food-sharing-phase active-agents

  ; === PHASE 3: SOCIAL INTERACTION (trust updates + gossip) ===
  social-interaction-phase active-agents

  ; === PHASE 4: ELIMINATION VOTING ===
  if current-day = next-elimination-day [
    elimination-phase active-agents
    set next-elimination-day current-day + elimination-interval
  ]

  ; === UPDATE METRICS ===
  ; Recompute active agents after possible elimination
  set active-agents turtles with [not eliminated?]
  update-global-metrics active-agents

  ; === UPDATE VISUALS ===
  update-visuals

  tick
end

; =============================================================================
; PHASE 1: CHALLENGE (Dschungelprüfung)
; =============================================================================

to challenge-phase [active-agents]
  ; Select one agent for today's challenge
  let challenger one-of active-agents

  ask challenger [
    set challenge-attempts challenge-attempts + 1

    ; Decide whether to cooperate (do challenge) or defect (refuse/fail)
    let will-cooperate? decide-challenge-cooperation

    ifelse will-cooperate? [
      ; Success! Earn food for the group
      let earned challenge-reward
      set food-pool food-pool + earned
      set challenge-successes challenge-successes + 1
      set energy energy - 10  ; Challenges cost energy

      ; Update trust: all active agents observe this cooperation
      ; Each link encounter is 1 observation of the challenger's action
      let active-observer-links my-links with [other-end != nobody and not [eliminated?] of other-end]
      let active-link-count count active-observer-links
      ask active-observer-links [
        set encounters encounters + 1
        set cooperations cooperations + 1
        update-trust-value
      ]

      set total-cooperations total-cooperations + active-link-count
      set total-interactions total-interactions + active-link-count
    ] [
      ; Failed/refused challenge
      set energy energy - 3  ; Small energy cost even for refusing

      ; Update trust: all active agents observe this defection
      let active-observer-links my-links with [other-end != nobody and not [eliminated?] of other-end]
      let active-link-count count active-observer-links
      ask active-observer-links [
        set encounters encounters + 1
        ; No cooperation increment
        update-trust-value
      ]

      set total-interactions total-interactions + active-link-count
    ]
  ]
end

to-report decide-challenge-cooperation
  ; BDI-style decision based on agent's strategy and state
  if strategy = "cooperator" [
    ; Cooperators almost always do the challenge
    report random-float 1.0 < personality-bravery
  ]
  if strategy = "strategist" [
    ; Strategists cooperate if energy is ok and reputation needs boosting
    let energy-factor energy / 100
    let rep-need 1 - reputation-score
    report random-float 1.0 < (personality-bravery * energy-factor * (0.5 + rep-need * 0.5))
  ]
  if strategy = "freerider" [
    ; Free-riders rarely do challenges
    report random-float 1.0 < (personality-bravery * 0.3)
  ]
  if strategy = "social" [
    ; Social agents cooperate moderately, influenced by group pressure
    let group-reputation mean [reputation-score] of turtles with [not eliminated?]
    report random-float 1.0 < (personality-bravery * (0.5 + group-reputation * 0.3))
  ]
  report false
end

; =============================================================================
; PHASE 2: FOOD SHARING & ENERGY
; =============================================================================

to food-sharing-phase [active-agents]
  let num-active count active-agents

  ; Distribute food
  if food-pool > 0 and num-active > 0 [
    let food-per-agent food-pool / num-active
    ask active-agents [
      set energy energy + food-per-agent * 0.5  ; Food restores some energy
    ]
    set food-pool food-pool * 0.3  ; Most food is consumed, some remains
  ]

  ; Daily energy cost
  ask active-agents [
    set energy energy - base-energy-cost
    ; Clamp energy
    if energy > 100 [ set energy 100 ]
    if energy < 0 [ set energy 0 ]

    ; Low energy affects behavior
    if energy < 20 [
      set reputation-score reputation-score - 0.02  ; Weak agents lose reputation
      if reputation-score < 0 [ set reputation-score 0 ]
    ]
  ]
end

; =============================================================================
; PHASE 3: SOCIAL INTERACTIONS (Trust + Gossip)
; =============================================================================

to social-interaction-phase [active-agents]
  ; Each active agent has a social encounter with 1-3 random others
  ask active-agents [
    let me self
    let potential-partners other active-agents
    if any? potential-partners [
      let num-interactions 1 + random min (list 3 (count potential-partners))
      let partners n-of (min (list num-interactions (count potential-partners))) potential-partners

      ask partners [
        ; Pairwise social interaction
        social-encounter me self
      ]
    ]
  ]

  ; Gossip phase: agents share opinions about third parties
  if enable-gossip? [
    gossip-phase active-agents
  ]

  ; Update alliance memberships
  update-alliances active-agents
end

to social-encounter [agent-a agent-b]
  ; A social encounter between two agents
  ; Both can cooperate (be friendly, share info) or defect (be hostile, withhold)
  let link-ab link [who] of agent-a [who] of agent-b
  if link-ab = nobody [ stop ]
  if [last-social-day] of link-ab = current-day [ stop ]  ; Already interacted today

  ask link-ab [
    set last-social-day current-day
    ; Each encounter counts as 2 interactions (one per agent)
    set encounters encounters + 2

    ; Determine if this is a cooperative encounter
    let a-cooperates? [decide-social-cooperation link-ab] of agent-a
    let b-cooperates? [decide-social-cooperation link-ab] of agent-b

    ; Count each agent's cooperation separately
    if a-cooperates? [
      set cooperations cooperations + 1
      set total-cooperations total-cooperations + 1
    ]
    if b-cooperates? [
      set cooperations cooperations + 1
      set total-cooperations total-cooperations + 1
    ]

    set total-interactions total-interactions + 2
    update-trust-value
  ]
end

to-report decide-social-cooperation [the-link]
  ; Decide whether to cooperate in a social encounter
  let current-trust [trust-value] of the-link

  if strategy = "cooperator" [
    report random-float 1.0 < (0.7 + current-trust * 0.3)
  ]
  if strategy = "strategist" [
    ; Reciprocate: cooperate if trust is high enough
    report random-float 1.0 < current-trust
  ]
  if strategy = "freerider" [
    ; Rarely cooperate socially
    report random-float 1.0 < (current-trust * 0.3)
  ]
  if strategy = "social" [
    ; Social agents are very cooperative in social settings
    report random-float 1.0 < (0.6 + personality-openness * 0.4)
  ]
  report false
end

; --- Trust Update (Mui et al. computational model) ---
; T_ab = (alpha + p) / (alpha + beta + n)
to update-trust-value
  let new-trust (trust-alpha + cooperations) / (trust-alpha + trust-beta + encounters)
  set trust-value new-trust

  ; Update link appearance
  update-link-appearance
end

to update-link-appearance
  let both-active? (not [eliminated?] of end1 and not [eliminated?] of end2)
  if not both-active? [ stop ]

  ; Break links when trust drops too low (broken relationship)
  ifelse trust-value < link-break-threshold [
    set hidden? true
    set relationship-type "broken"
  ] [
    ; Restore broken links when trust recovers above threshold
    if hidden? [
      set hidden? false
    ]
    ; Color and thickness based on trust
    ifelse trust-value > 0.7 [
      set color green
      set relationship-type "alliance"
      set thickness 0.3
    ] [
      ifelse trust-value < 0.3 [
        set color red
        set relationship-type "rival"
        set thickness 0.2
      ] [
        set color gray
        set relationship-type "neutral"
        set thickness 0.1
      ]
    ]
  ]
end

; --- Gossip Phase ---
to gossip-phase [active-agents]
  ; Each agent asks one neighbor about a third party
  ask active-agents [
    let me self
    let my-neighbors link-neighbors with [not eliminated? and not [hidden?] of link who [who] of myself]
    if count my-neighbors >= 2 [
      ; Pick a neighbor to gossip with
      let gossip-partner one-of my-neighbors
      ; Pick a third agent to gossip about
      let gossip-target one-of (my-neighbors with [self != gossip-partner])
      if gossip-target != nobody and gossip-partner != nobody [
        ; Get gossip-partner's trust of gossip-target
        let partner-link link [who] of gossip-partner [who] of gossip-target
        if partner-link != nobody [
          let indirect-trust [trust-value] of partner-link

          ; Update my trust of gossip-target via virtual encounters (consistent with Bayesian model)
          let my-link link who [who] of gossip-target
          if my-link != nobody [
            ask my-link [
              let gossip-encounters gossip-spread-factor * 2
              set encounters encounters + gossip-encounters
              set cooperations cooperations + gossip-encounters * indirect-trust
              update-trust-value
            ]
          ]
        ]
      ]
    ]
  ]
end

; --- Alliance Formation ---
to update-alliances [active-agents]
  ; Agents with mutual high trust form alliances
  ask active-agents [
    let me self
    let strong-allies link-neighbors with [
      not eliminated? and
      not [hidden?] of link who [who] of me and
      [trust-value] of link who [who] of me > 0.7
    ]
    ifelse any? strong-allies [
      ; Join the alliance of the most trusted ally, or form new one
      let best-ally max-one-of strong-allies [
        [trust-value] of link who [who] of myself
      ]
      if best-ally != nobody [
        ifelse [alliance-id] of best-ally != -1 [
          set alliance-id [alliance-id] of best-ally
        ] [
          set alliance-id who
          ask best-ally [ set alliance-id [who] of me ]
        ]
      ]
    ] [
      set alliance-id -1  ; No alliance
    ]
  ]
end

; =============================================================================
; PHASE 4: ELIMINATION VOTING
; =============================================================================

to elimination-phase [active-agents]
  let num-active count active-agents
  if num-active <= 1 [ stop ]  ; No elimination if 1 or fewer contestants

  ; Reset votes
  ask active-agents [
    set votes-received 0
    set voted-for nobody
  ]

  ; Each agent votes for one other agent to eliminate
  ask active-agents [
    let me self
    let candidates other active-agents

    ; Update reputation before voting
    update-agent-reputation

    ; Choose who to vote for (lowest trust / lowest reputation)
    let vote-target choose-vote-target candidates
    if vote-target != nobody [
      set voted-for vote-target
      ask vote-target [ set votes-received votes-received + 1 ]
    ]
  ]

  ; Eliminate the agent with most votes (random tiebreak)
  let max-votes max [votes-received] of active-agents
  if max-votes > 0 [
    let eliminated-agent one-of active-agents with [votes-received = max-votes]
    ask eliminated-agent [
      set eliminated? true
      set elimination-day current-day
      set color gray
      set size 1.5
      set label (word who " X")
      set num-eliminated num-eliminated + 1

      ; Hide links of eliminated agent
      ask my-links [
        set hidden? true
      ]
    ]

    ; Rearrange layout
    layout-agents
  ]
end

to-report choose-vote-target [candidates]
  ; BDI voting decision
  if strategy = "cooperator" [
    ; Vote for the person they trust least (punish defectors)
    report min-one-of candidates [
      [trust-value] of link who [who] of myself
    ]
  ]
  if strategy = "strategist" [
    ; Vote for biggest threat (highest reputation not in alliance)
    let non-allies candidates with [alliance-id != [alliance-id] of myself or alliance-id = -1]
    ifelse any? non-allies [
      report max-one-of non-allies [reputation-score]
    ] [
      report min-one-of candidates [
        [trust-value] of link who [who] of myself
      ]
    ]
  ]
  if strategy = "freerider" [
    ; Vote for whoever noticed their freeriding (lowest trust toward me)
    report min-one-of candidates [
      [trust-value] of link [who] of myself who
    ]
  ]
  if strategy = "social" [
    ; Vote with the majority of their alliance
    let my-allies candidates with [alliance-id = [alliance-id] of myself and alliance-id != -1]
    ifelse any? my-allies [
      ; Vote for who the alliance distrusts most
      let all-non-allies candidates with [alliance-id != [alliance-id] of myself or alliance-id = -1]
      ifelse any? all-non-allies [
        report min-one-of all-non-allies [reputation-score]
      ] [
        report one-of candidates
      ]
    ] [
      report min-one-of candidates [reputation-score]
    ]
  ]
  report one-of candidates
end

to update-agent-reputation
  ; Reputation = weighted average of all other active agents' trust in this agent
  let me self
  let active-neighbors link-neighbors with [not eliminated?]
  if any? active-neighbors [
    let total-trust sum [
      [trust-value] of link who [who] of me
    ] of active-neighbors
    set reputation-score total-trust / count active-neighbors
  ]
end

; =============================================================================
; METRICS & VISUALIZATION
; =============================================================================

to update-global-metrics [active-agents]
  ; Average trust
  let active-links links with [not hidden?]
  ifelse any? active-links [
    set avg-trust mean [trust-value] of active-links
  ] [
    set avg-trust 0
  ]

  ; Average reputation
  ifelse any? active-agents [
    set avg-reputation mean [reputation-score] of active-agents
  ] [
    set avg-reputation 0
  ]
end

to update-visuals
  ; Update agent sizes based on reputation
  ask turtles with [not eliminated?] [
    set size 1.5 + reputation-score * 2

    ; Update color intensity based on energy
    let energy-factor energy / 100
    if strategy = "cooperator" [ set color scale-color green energy-factor 0 1.5 ]
    if strategy = "strategist" [ set color scale-color blue energy-factor 0 1.5 ]
    if strategy = "freerider" [ set color scale-color red energy-factor 0 1.5 ]
    if strategy = "social" [ set color scale-color yellow energy-factor 0 1.5 ]
  ]
end

; =============================================================================
; REPORTERS
; =============================================================================

to-report cooperation-rate
  ifelse total-interactions > 0 [
    report total-cooperations / total-interactions
  ] [
    report 0
  ]
end

to-report num-alliances
  let active-agents turtles with [not eliminated? and alliance-id != -1]
  ifelse any? active-agents [
    report length remove-duplicates [alliance-id] of active-agents
  ] [
    report 0
  ]
end

to-report num-active-contestants
  report count turtles with [not eliminated?]
end

to-report avg-energy
  let active turtles with [not eliminated?]
  ifelse any? active [
    report mean [energy] of active
  ] [
    report 0
  ]
end

to-report network-density
  let active-links links with [not hidden?]
  let active-agents count turtles with [not eliminated?]
  let max-links (active-agents * (active-agents - 1)) / 2
  ifelse max-links > 0 [
    report count active-links / max-links
  ] [
    report 0
  ]
end

to-report clustering-coefficient
  ; Average local clustering coefficient (visible links only)
  let active-agents turtles with [not eliminated?]
  ifelse count active-agents > 2 [
    let coefficients []
    ask active-agents [
      let me self
      let my-neighbors link-neighbors with [
        not eliminated? and not [hidden?] of link who [who] of me
      ]
      let k count my-neighbors
      if k >= 2 [
        let possible-connections k * (k - 1) / 2
        let actual-connections 0
        ask my-neighbors [
          let me-neighbor self
          ask other my-neighbors [
            let lnk link who [who] of me-neighbor
            if lnk != nobody and not [hidden?] of lnk [
              set actual-connections actual-connections + 1
            ]
          ]
        ]
        set actual-connections actual-connections / 2  ; counted twice
        set coefficients lput (actual-connections / possible-connections) coefficients
      ]
    ]
    ifelse length coefficients > 0 [
      report mean coefficients
    ] [
      report 0
    ]
  ] [
    report 0
  ]
end

to-report count-strategy [strat]
  report count turtles with [not eliminated? and strategy = strat]
end

; =============================================================================
; INTERFACE NOTES
; =============================================================================
; Required interface elements (sliders, buttons, plots):
;
; BUTTONS:
;   - setup (calls: setup)
;   - go (calls: go, forever)
;
; SLIDERS:
;   - num-contestants (4-20, default 12)
;   - pct-cooperators (0-100, default 30)
;   - pct-strategists (0-100, default 30)
;   - pct-freeriders (0-100, default 20)
;   - elimination-every-n-days (2-10, default 3)
;
; SWITCHES:
;   - enable-gossip? (default: on)
;
; MONITORS:
;   - current-day, num-active-contestants, food-pool,
;     avg-trust, avg-reputation, cooperation-rate, num-alliances
;
; PLOTS:
;   - "Trust Evolution" (avg-trust over time)
;   - "Reputation Scores" (per-agent reputation)
;   - "Food Pool" (food over time)
;   - "Energy Levels" (avg-energy over time)
;   - "Network Metrics" (density, clustering over time)
;   - "Strategy Survival" (count per strategy over time)
;   - "Cooperation Rate" (cooperation-rate over time)
; =============================================================================
@#$#@#$#@
GRAPHICS-WINDOW
210
10
747
548
-1
-1
13.0
1
12
1
1
1
0
0
0
1
-20
20
-20
20
1
1
1
Day
30.0

BUTTON
10
10
90
43
Setup
setup
NIL
1
T
OBSERVER
NIL
S
NIL
NIL
1

BUTTON
100
10
190
43
Go
go
T
1
T
OBSERVER
NIL
G
NIL
NIL
1

BUTTON
100
50
190
83
Step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
10
100
200
133
num-contestants
num-contestants
4
20
12.0
1
1
NIL
HORIZONTAL

SLIDER
10
140
200
173
pct-cooperators
pct-cooperators
0
100
30.0
5
1
%
HORIZONTAL

SLIDER
10
180
200
213
pct-strategists
pct-strategists
0
100
30.0
5
1
%
HORIZONTAL

SLIDER
10
220
200
253
pct-freeriders
pct-freeriders
0
100
20.0
5
1
%
HORIZONTAL

SLIDER
10
260
200
293
elimination-every-n-days
elimination-every-n-days
2
10
3.0
1
1
days
HORIZONTAL

SWITCH
10
300
200
333
enable-gossip?
enable-gossip?
0
1
-1000

MONITOR
760
10
870
55
Day
current-day
0
1
11

MONITOR
760
60
870
105
Active
num-active-contestants
0
1
11

MONITOR
760
110
870
155
Food Pool
precision food-pool 1
1
1
11

MONITOR
760
160
870
205
Avg Trust
precision avg-trust 3
3
1
11

MONITOR
760
210
870
255
Avg Reputation
precision avg-reputation 3
3
1
11

MONITOR
760
260
870
305
Cooperation %
precision (cooperation-rate * 100) 1
1
1
11

MONITOR
760
310
870
355
Alliances
num-alliances
0
1
11

MONITOR
760
360
870
405
Avg Energy
precision avg-energy 1
1
1
11

PLOT
880
10
1150
160
Trust Evolution
Day
Avg Trust
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"avg-trust" 1.0 0 -10899396 true "" "plot avg-trust"

PLOT
880
165
1150
315
Strategy Survival
Day
Count
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Cooperators" 1.0 0 -10899396 true "" "plot count-strategy \"cooperator\""
"Strategists" 1.0 0 -13345367 true "" "plot count-strategy \"strategist\""
"Freeriders" 1.0 0 -2674135 true "" "plot count-strategy \"freerider\""
"Social" 1.0 0 -1184463 true "" "plot count-strategy \"social\""

PLOT
880
320
1150
470
Food & Energy
Day
Value
0.0
10.0
0.0
100.0
true
true
"" ""
PENS
"Food" 1.0 0 -6459832 true "" "plot food-pool"
"Avg Energy" 1.0 0 -955883 true "" "plot avg-energy"

PLOT
880
475
1150
625
Cooperation Rate
Day
Rate
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"coop-rate" 1.0 0 -16777216 true "" "plot cooperation-rate"

PLOT
1160
10
1430
160
Network Metrics
Day
Value
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"Density" 1.0 0 -16777216 true "" "plot network-density"
"Clustering" 1.0 0 -2674135 true "" "plot clustering-coefficient"

PLOT
1160
165
1430
315
Reputation Distribution
Day
Reputation
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"avg-rep" 1.0 0 -7500403 true "" "plot avg-reputation"

TEXTBOX
10
345
200
425
Strategy colors:\nGreen = Cooperator\nBlue = Strategist\nRed = Free-rider\nYellow = Social\nGray = Eliminated
11
0.0
1

TEXTBOX
10
430
200
480
Link colors:\nGreen = Alliance (trust>0.7)\nRed = Rival (trust<0.3)\nGray = Neutral
11
0.0
1

MONITOR
760
410
870
455
Winner
ifelse-value (winner != nobody) [(word [who] of winner " (" [strategy] of winner ")")] ["-"]
0
1
11

@#$#@#$#@
## WHAT IS IT?

This model simulates the social dynamics of a **Dschungelcamp** (Jungle Camp / "I'm a Celebrity... Get Me Out of Here!") reality TV show using Multi-Agent Systems (MAS).

Each contestant is an **intelligent agent** with a BDI (Belief-Desire-Intention) architecture that interacts with other agents in a shared environment. The simulation models:

- **Trust** between contestants (Mui et al. computational trust model)
- **Reputation** as perceived by the group
- **Alliance formation** through mutual high trust
- **Gossip** as indirect trust propagation
- **Voting and elimination** that shrinks the social network

## HOW IT WORKS

### Agent Strategies (BDI)

Each agent follows one of four strategies:

1. **Cooperator** (green): Almost always does challenges, builds trust through consistent cooperation
2. **Strategist** (blue): Cooperates selectively based on trust values and reputation needs
3. **Free-rider** (red): Avoids challenges, exploits group resources without contributing
4. **Social** (yellow): Focuses on building many social connections and follows group consensus

### Daily Phases

Each simulation tick represents one day in the camp:

1. **Challenge Phase**: One contestant faces a "Dschungelprüfung" and decides to cooperate (earn food) or defect
2. **Food Sharing**: Resources are distributed; energy is consumed
3. **Social Phase**: Pairwise interactions update trust values; gossip spreads reputation information
4. **Elimination**: Every N days, agents vote to eliminate one contestant

### Trust Model (Mui et al., 2001)

Trust is computed using a Beta distribution model:

**T_ab = (α + p) / (α + β + n)**

Where:
- α, β = prior parameters (initially 1,1 for uniform prior)
- p = number of cooperative actions by b toward a
- n = total encounters between a and b

### Reputation

An agent's reputation is the weighted average of all other active agents' trust in them:

**R_i = (1/|N|) × Σ T_ji for all j in neighbors**

### Gossip (Indirect Trust)

When gossip is enabled, agents share their trust opinions about third parties:

**T_ac(new) = T_ac × (1 - γ) + T_bc × γ**

Where γ is the gossip spread factor.

## HOW TO USE IT

1. Set the number of contestants and strategy distribution with the sliders
2. Choose the elimination interval
3. Toggle gossip on/off
4. Click **Setup** to initialize
5. Click **Go** to run continuously, or **Step** for one day at a time

### Parameters

- **num-contestants**: Total number of agents (4-20)
- **pct-cooperators/strategists/freeriders**: Percentage of each strategy (remainder = social)
- **elimination-every-n-days**: Days between elimination votes
- **enable-gossip?**: Whether agents share opinions about others

## THINGS TO NOTICE

- How quickly do alliances (green links) form?
- Do free-riders (red) get eliminated first, or do they survive through strategic voting?
- How does the trust network structure change after each elimination?
- Does gossip make the network converge faster (more uniform trust)?
- What strategy tends to win?

## THINGS TO TRY

- Run with all cooperators vs. all free-riders
- Turn gossip off and compare trust evolution
- Set elimination interval very high (10) vs. very low (2)
- Try a single free-rider among cooperators — can they survive?
- Increase the number of contestants and observe network complexity

## EXTENDING THE MODEL

- Add a **viewer voting** mechanism (external elimination pressure)
- Implement **challenge difficulty** that varies over time
- Add **personality evolution** — agents that learn and adapt their strategy
- Model **emotional state** affecting decisions
- Add **resource hoarding** — agents can secretly keep food

## CREDITS AND REFERENCES

- Mui, L., Mohtashemi, M., & Halberstadt, A. (2001). A computational model of trust and reputation
- Wooldridge, M. (2002). An Introduction to Multiagent Systems
- Hassas S., Di Marzo-Serugendo G., Karageorgos A. and Castelfranchi C. (2006). On self-organising mechanisms

**Course**: Graph Analysis and Social Networks — UPM Master in Data Science, 2025-26
**Professor**: Javier Bajo
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 119 180 180 270 120 270 150 0

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 210 135 255 120 225 180 165 210
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 210 60 255 45 225 105 165 135
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 true true 24 174 42
Circle -7500403 true true 144 174 42
Circle -7500403 true true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
