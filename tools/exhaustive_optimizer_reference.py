#!/usr/bin/env python3
"""Independent exhaustive reference for the fixed v0.3 optimizer fixture."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


COMPONENTS = (
    (5, 1, 4),
    (4, 4, 0),
    (3, 2, 1),
    (1, 0, 1),
)


def objective(mask: int) -> int:
    counts = [[0, 0, 0], [0, 0, 0]]
    for index, component in enumerate(COMPONENTS):
        partition = (mask >> index) & 1
        for column, value in enumerate(component):
            counts[partition][column] += value
    total, total_a, total_b = 13, 7, 6
    return sum(
        (2 * size - total) ** 2
        + (2 * count_a - total_a) ** 2
        + (2 * count_b - total_b) ** 2
        for size, count_a, count_b in counts
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    optimum = min(objective(mask) for mask in range(1, 15))
    initial = int(plan["initial_objective"])
    optimized = int(plan["objective"])
    evidence = {
        "reference": "independent exhaustive enumeration of 14 non-empty two-partition assignments",
        "initial_objective": initial,
        "optimized_objective": optimized,
        "exhaustive_optimum": optimum,
        "optimality_gap": optimized - optimum,
        "optimization_rounds": plan["optimization_rounds"],
    }
    args.out.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    if optimized > initial or optimized != optimum:
        raise SystemExit("optimizer fixture failed its improvement or optimality predicate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
