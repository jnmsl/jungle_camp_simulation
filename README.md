# Dschungelcamp Social Dynamics Simulation

**Graph Analysis and Social Networks** - UPM Master in Data Science (2025-26)

## Overview

Agent-based simulation of a Jungle Camp reality TV show using **NetLogo**. Models trust, reputation, alliances, and social network evolution among contestants as they compete, cooperate, and vote to eliminate each other.

## Course Concepts Applied

| Concept | Implementation |
|---------|---------------|
| **BDI Agents** | 4 strategy types with Beliefs (trust values), Desires (survive/win), Intentions (cooperate/defect) |
| **Trust Model** (Mui et al.) | `T_ab = (alpha + p) / (alpha + beta + n)` - Beta distribution based on cooperation history |
| **Reputation** | Weighted average of all neighbors' trust: `R_i = mean(T_ji)` |
| **Gossip / Indirect Trust** | `T_ac(new) = T_ac * (1-gamma) + T_bc * gamma` |
| **Network Evolution** | Social network shrinks as contestants are eliminated each round |
| **Emergent Behavior** | Alliances, power dynamics, and survival patterns emerge from simple rules |

## Agent Strategies

- **Cooperator** (green): Consistently does challenges, builds trust through reliability
- **Strategist** (blue): Cooperates selectively based on trust levels and reputation needs
- **Free-rider** (red): Avoids challenges, exploits group resources
- **Social** (yellow): Builds many connections, follows group consensus

## How to Run

1. Open `dschungelcamp.nlogo` in NetLogo 6.4+
2. Adjust sliders (contestants, strategy mix, elimination interval)
3. Click **Setup**, then **Go**

## Key Parameters

- `num-contestants`: 4-20 agents
- `pct-cooperators/strategists/freeriders`: Strategy distribution (remainder = social)
- `elimination-every-n-days`: Voting frequency
- `enable-gossip?`: Toggle indirect trust propagation

## Simulation Phases (per tick = 1 day)

1. **Challenge** - One agent faces a Dschungelprufung (cooperate = earn food, defect = save energy)
2. **Food Sharing** - Resources distributed, energy consumed
3. **Social Interaction** - Pairwise encounters update trust; gossip spreads reputation
4. **Elimination** - Every N days, agents vote out the least trusted contestant

## Plots & Metrics

- Trust Evolution, Strategy Survival, Food & Energy, Cooperation Rate
- Network Density, Clustering Coefficient, Reputation Distribution
