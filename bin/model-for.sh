#!/bin/sh
# The coordinator's model pick per phase/attempt/complexity (T-007), mirroring the orchestrator's lockout
# ladder (Orchestrator.cs:452-467) over the archetype x tier table (OrchestratorOptions.cs:136-149,
# OrchestratorOptions.ModelFor): complexity high or attempt >= 1 escalates to opus at every phase; otherwise
# phase tests -> opus, phase implement -> opus; with no phase, archetype review/feature/bugfix/refactor -> opus
# (generated code never runs below opus), triage/ops or tier green -> haiku, everything else -> sonnet.
#
# Phase implement answers opus at every tier: the implement agents (agents/factory-block-implement*.md) fix
# `model: opus` and the coordinator passes no override, so a cheaper answer here would only disagree with the
# agent that actually runs (the sonnet lane of slim-harness M12 never ran and is gone).
#
# Phase verify is a script run plus a fixed-format report, so it sits below the escalation block and answers
# haiku unless complexity high or attempt >= 1 has already escalated it.
#
#   model-for.sh <archetype> <tier> <phase> <attempt> <complexity>
#   model-for.sh --agent <archetype> <tier> <phase> <attempt> <complexity>
#
# Prints the model name (haiku|sonnet|opus). Under --agent it prints the agent definition name instead, and
# only the phase and the complexity decide it: phase implement with complexity high gives the medium-effort
# variant factory-block-implement-medium, phase implement otherwise gives factory-block-implement, phase tests
# gives factory-block-tests. The escalation ladder picks the model, not the agent, so it does not apply under
# --agent; any other phase exits 1. Output is exactly one line, because every caller reads this script through
# a command substitution as one word. Bad arguments exit 1 with the reason on stderr.
set -eu

die() { printf 'model-for: %s\n' "$1" >&2; exit 1; }

if [ "${1-}" = --agent ]; then
  shift
  [ $# -eq 5 ] || die "usage: model-for.sh --agent <archetype> <tier> <phase> <attempt> <complexity>"
  case "$3" in
    implement) if [ "$5" = high ]; then echo factory-block-implement-medium; else echo factory-block-implement; fi ;;
    tests) echo factory-block-tests ;;
    *) die "--agent has no agent for phase '$3': only implement and tests are spawned per block" ;;
  esac
  exit 0
fi

[ $# -eq 5 ] || die "usage: model-for.sh <archetype> <tier> <phase> <attempt> <complexity>"

archetype=$1 tier=$2 phase=$3 attempt=$4 complexity=$5

case "$tier" in
  red|yellow|green) ;;
  *) die "unrecognized tier '$tier' — must be red|yellow|green" ;;
esac

case "$attempt" in
  ''|*[!0-9]*) die "attempt must be a non-negative integer, not '$attempt'" ;;
esac

[ -z "$phase" ] && phase='-'

if [ "$complexity" = high ] || [ "$attempt" -ge 1 ]; then
  echo opus
  exit 0
fi

case "$phase" in
  tests|implement) echo opus; exit 0 ;;
  verify) echo haiku; exit 0 ;;
esac

case "$archetype" in
  review|feature|bugfix|refactor) echo opus ;;
  triage|ops) echo haiku ;;
  *)
    if [ "$tier" = green ]; then echo haiku; else echo sonnet; fi
    ;;
esac
