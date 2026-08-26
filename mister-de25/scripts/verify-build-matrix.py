#!/usr/bin/env python3
"""Verify a locked official catalog and its DE25 build matrix offline."""

from __future__ import annotations

import argparse
import csv
import hashlib
from collections import Counter
from pathlib import Path


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as source:
        return list(csv.DictReader(source, delimiter="\t"))


def read_lock(path: Path) -> dict[str, str]:
    with path.open(encoding="utf-8", newline="") as source:
        rows = list(csv.reader(source, delimiter="\t"))
    if any(len(row) != 2 for row in rows):
        raise SystemExit("catalog lock contains an invalid row")
    values = dict(rows)
    if len(values) != len(rows):
        raise SystemExit("catalog lock contains a duplicate key")
    return values


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument(
        "--additional-catalog",
        action="append",
        default=[],
        type=Path,
        help="append a local catalog to the locked upstream catalog",
    )
    parser.add_argument("--lock", required=True, type=Path)
    parser.add_argument("--status", required=True, type=Path)
    parser.add_argument("--matrix", required=True, type=Path)
    args = parser.parse_args()

    lock = read_lock(args.lock)
    if lock.get("catalog_sha256") != sha256(args.catalog):
        raise SystemExit("catalog SHA-256 does not match its lock")
    if not lock.get("source") or not lock.get("revision"):
        raise SystemExit("catalog lock is missing source identity")

    catalog = read_tsv(args.catalog)
    known_identities = {
        (row["repository"], row["branch"], row["home"])
        for row in catalog
    }
    known_homes = {row["home"] for row in catalog if row["home"]}
    for additional_catalog in args.additional_catalog:
        for row in read_tsv(additional_catalog):
            identity = (row["repository"], row["branch"], row["home"])
            if identity in known_identities:
                raise SystemExit("supplemental catalog duplicates a core identity")
            if row["home"] and row["home"] in known_homes:
                raise SystemExit(
                    f"supplemental catalog duplicates home key: {row['home']}"
                )
            known_identities.add(identity)
            if row["home"]:
                known_homes.add(row["home"])
            catalog.append(row)
    matrix = read_tsv(args.matrix)
    status = read_tsv(args.status)
    if len(catalog) != len(matrix):
        raise SystemExit("catalog and matrix row counts differ")

    catalog_keys = Counter(
        (row["repository"], row["branch"], row["home"]) for row in catalog
    )
    matrix_keys = Counter(
        (row["repository"], row["branch"], row["home"]) for row in matrix
    )
    if catalog_keys != matrix_keys:
        raise SystemExit("catalog and matrix core identities differ")
    if any(row["source_id"].lower().endswith(".git") for row in catalog):
        raise SystemExit("catalog source_id still contains a .git suffix")

    for port in status:
        matches = [row for row in matrix if row["home"] == port["home"]]
        if not matches:
            raise SystemExit(f"ported core absent from matrix: {port['home']}")
        if len(matches) > 1:
            raise SystemExit(f"ported core is ambiguous in matrix: {port['home']}")
        row = matches[0]
        for field in ("status", "build_script", "artifact", "timing", "hardware"):
            if row[field] != port[field]:
                raise SystemExit(f"matrix mismatch for {port['home']} field {field}")

    packaged = sum(row["status"] == "packaged" for row in matrix)
    print(f"PASS: locked build matrix has {len(matrix)} entries and {packaged} packaged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
