#!/usr/bin/env python3
"""Report the values a ct run actually used, as Markdown for a job summary.

`ct` discovers charts/graylog/ci/*-values.yaml on its own and the workflow passes
no sizing flags, so nothing in the log says what the chart was installed with.
This renders the chart with the same overlay and reports what came out, which is
the only view that accounts for chart defaults the overlay does not mention -
MongoDB's containers being the obvious case.

Reads the rendered manifests as JSON on stdin:

    helm template ci charts/graylog -f <overlay> | yq ea -o=json '[.]' - \
      | ci_values_summary.py --overlay <overlay> [--extra-set "flag, flag"]
"""

from __future__ import annotations

import argparse
import json
import sys

CPU_SUFFIX = {"m": 0.001, "": 1.0}
MEM_SUFFIX = {
    "Ki": 1 / 1024,
    "Mi": 1.0,
    "Gi": 1024.0,
    "K": 1000 / 1024 / 1024,
    "M": 1000 * 1000 / 1024 / 1024,
    "G": 1000 * 1000 * 1000 / 1024 / 1024,
    "": 1 / 1024 / 1024,
}


def cpu_cores(value: str | None) -> float:
    """Parse a Kubernetes CPU quantity into cores."""
    if not value:
        return 0.0
    text = str(value)
    if text.endswith("m"):
        return float(text[:-1]) * CPU_SUFFIX["m"]
    return float(text)


def mem_mib(value: str | None) -> float:
    """Parse a Kubernetes memory quantity into MiB."""
    if not value:
        return 0.0
    text = str(value)
    for suffix in ("Ki", "Mi", "Gi", "K", "M", "G"):
        if text.endswith(suffix):
            return float(text[: -len(suffix)]) * MEM_SUFFIX[suffix]
    return float(text) * MEM_SUFFIX[""]


def fmt_cpu(cores: float) -> str:
    return f"{cores:g}" if cores >= 1 else f"{round(cores * 1000)}m"


def fmt_mem(mib: float) -> str:
    return f"{mib / 1024:g}Gi" if mib >= 1024 else f"{mib:g}Mi"


def requests_of(container: dict, key: str) -> str | None:
    return (container.get("resources") or {}).get(key, {}).get("cpu"), (
        container.get("resources") or {}
    ).get(key, {}).get("memory")


def pod_reservation(containers: list[dict], init: list[dict]) -> tuple[float, float]:
    """A pod reserves max(max(initContainer), sum(containers)) on each axis."""
    run_cpu = sum(cpu_cores(requests_of(c, "requests")[0]) for c in containers)
    run_mem = sum(mem_mib(requests_of(c, "requests")[1]) for c in containers)
    init_cpu = max(
        (cpu_cores(requests_of(c, "requests")[0]) for c in init), default=0.0
    )
    init_mem = max((mem_mib(requests_of(c, "requests")[1]) for c in init), default=0.0)
    return max(run_cpu, init_cpu), max(run_mem, init_mem)


def workload_rows(docs: list[dict]) -> tuple[list[list[str]], float, float]:
    """One row per workload, plus the cluster-wide request totals."""
    rows: list[list[str]] = []
    total_cpu = total_mem = 0.0

    for doc in docs:
        if not isinstance(doc, dict):
            continue

        if doc.get("kind") == "StatefulSet":
            spec = doc["spec"]["template"]["spec"]
            replicas = int(doc["spec"].get("replicas", 1))
            cpu, mem = pod_reservation(
                spec.get("containers") or [], spec.get("initContainers") or []
            )
            limits = [
                (
                    (c.get("resources") or {}).get("limits", {}).get("cpu"),
                    (c.get("resources") or {}).get("limits", {}).get("memory"),
                )
                for c in spec.get("containers") or []
            ]
            limit_text = ", ".join(
                f"{l[0] or '–'} / {l[1] or '–'}" for l in limits
            )
            grace = spec.get("terminationGracePeriodSeconds", "cluster default")
            rows.append(
                [
                    f"`{doc['metadata']['name']}`",
                    str(replicas),
                    f"{fmt_cpu(cpu)} / {fmt_mem(mem)}",
                    limit_text or "–",
                    f"{grace}s" if isinstance(grace, int) else str(grace),
                ]
            )
            total_cpu += cpu * replicas
            total_mem += mem * replicas

        elif doc.get("kind") == "MongoDBCommunity":
            spec = doc["spec"]["statefulSet"]["spec"]["template"]["spec"]
            members = int(doc["spec"].get("members", 1)) + int(
                doc["spec"].get("arbiters", 0) or 0
            )
            cpu, mem = pod_reservation(
                spec.get("containers") or [], spec.get("initContainers") or []
            )
            limit_text = ", ".join(
                f"{(c.get('resources') or {}).get('limits', {}).get('cpu') or '–'}"
                f" / {(c.get('resources') or {}).get('limits', {}).get('memory') or '–'}"
                for c in spec.get("containers") or []
            )
            rows.append(
                [
                    f"`{doc['metadata']['name']}` (MongoDB {doc['spec'].get('version', '?')})",
                    str(members),
                    f"{fmt_cpu(cpu)} / {fmt_mem(mem)}",
                    limit_text or "operator defaults",
                    "operator-owned",
                ]
            )
            total_cpu += cpu * members
            total_mem += mem * members

    return rows, total_cpu, total_mem


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--overlay", required=True, help="values file ct discovered")
    ap.add_argument("--extra-set", default="", help="flags the workflow adds")
    ap.add_argument("--heading", default="Values used")
    args = ap.parse_args()

    docs = json.load(sys.stdin)
    rows, total_cpu, total_mem = workload_rows(docs)

    out = [f"### {args.heading}", ""]
    out.append(f"Overlay: `{args.overlay}` (discovered by `ct`)")
    out.append("")
    if args.extra_set:
        out.append(f"Extra flags: `{args.extra_set}`")
        out.append("")
    out.append("| workload | replicas | request / pod | limits per container | grace |")
    out.append("|---|---|---|---|---|")
    for row in rows:
        out.append("| " + " | ".join(row) + " |")
    out.append("")
    out.append(
        f"**Whole stack requests {fmt_cpu(total_cpu)} CPU and {fmt_mem(total_mem)}**, "
        "counting every replica. A pod reserves "
        "`max(max(initContainer), sum(containers))`, so init containers are "
        "included where they set the floor."
    )
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
