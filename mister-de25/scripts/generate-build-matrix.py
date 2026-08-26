#!/usr/bin/env python3
"""Join upstream and supplemental catalogs with DE25 port status."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as source:
        return list(csv.DictReader(source, delimiter="\t"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument(
        "--additional-catalog",
        action="append",
        default=[],
        type=Path,
        help="append a local catalog without changing the locked upstream catalog",
    )
    parser.add_argument("--status", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

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
    status_rows = read_tsv(args.status)
    status = {row["home"]: row for row in status_rows}
    if len(status) != len(status_rows):
        raise SystemExit("duplicate home key in DE25 port status")
    catalog_home_counts = Counter(row["home"] for row in catalog if row["home"])
    ambiguous = sorted(home for home in status if catalog_home_counts[home] > 1)
    if ambiguous:
        raise SystemExit(
            f"DE25 status keys match multiple catalog rows: {', '.join(ambiguous)}"
        )

    fields = [
        "category", "name", "home", "sdram", "repository", "branch", "source_id",
        "status", "build_script", "artifact", "timing", "hardware", "comments",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as destination:
        writer = csv.DictWriter(destination, fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for core in catalog:
            port = status.get(core["home"], {})
            row = {field: core.get(field, port.get(field, "")) for field in fields}
            row["status"] = port.get("status", "not-ported")
            row["timing"] = port.get("timing", "not-run")
            row["hardware"] = port.get("hardware", "not-run")
            row["build_script"] = port.get("build_script", "")
            row["artifact"] = port.get("artifact", "")
            writer.writerow(row)

    missing = sorted(set(status) - {row["home"] for row in catalog})
    if missing:
        raise SystemExit(f"DE25 status keys absent from combined catalogs: {', '.join(missing)}")
    packaged = sum(row.get("status") == "packaged" for row in status_rows)
    print(f"DE25 build matrix: {len(catalog)} entries, {packaged} packaged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
