#!/usr/bin/env python3
"""Build a deterministic MiSTer core catalog from the official Wiki list."""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


DEFAULT_URL = "https://raw.githubusercontent.com/wiki/MiSTer-devel/Wiki_MiSTer/Cores.md"
LINK_RE = re.compile(r"\[([^]]+)\]\((https://github\.com/MiSTer-devel/[^)]+)\)", re.I)


@dataclass(frozen=True)
class Core:
    category: str
    name: str
    home: str
    sdram: str
    repository: str
    branch: str
    comments: str

    @property
    def source_id(self) -> str:
        path = urlparse(self.repository).path.strip("/")
        if path.lower().endswith(".git"):
            path = path[:-4]
        return path.replace("/", "_")


def canonicalize_repository(url: str) -> tuple[str, str]:
    parsed = urlparse(url)
    path = parsed.path.strip("/")
    parts = path.split("/")
    if len(parts) < 2:
        raise ValueError(f"Invalid GitHub repository URL: {url}")
    repository_name = parts[1]
    if repository_name.lower().endswith(".git"):
        repository_name = repository_name[:-4]
    branch = ""
    if len(parts) >= 4 and parts[2] == "tree":
        branch = "/".join(parts[3:])
    repository = f"https://github.com/{parts[0]}/{repository_name}.git"
    return repository, branch


def normalize_sdram(value: str) -> str:
    value = value.strip().lower()
    if value.startswith("yes"):
        return "yes"
    if value.startswith("no"):
        return "no"
    return "unknown"


def parse_catalog(text: str) -> list[Core]:
    in_standard = False
    in_arcade = False
    category = ""
    cores: list[Core] = []

    for raw_line in text.splitlines():
        line = raw_line.strip()
        lower = line.lower()
        if "cores_list_start" in lower:
            in_standard = True
            continue
        if "cores_list_end" in lower:
            in_standard = False
            continue
        if "arcade_list_start" in lower:
            in_arcade = True
            category = "_Arcade"
            continue
        if "arcade_list_end" in lower:
            in_arcade = False
            continue
        if not (in_standard or in_arcade):
            continue

        if in_standard and line.startswith("##"):
            header = lower.lstrip("#").strip()
            if "computer" in header:
                category = "_Computer"
            elif "console" in header:
                category = "_Console"
            elif "service" in header or "utility" in header:
                category = "_Utility"
            elif "other" in header:
                category = "_Other"
            continue
        if not line.startswith("|") or "github.com/mister-devel/" not in lower:
            continue

        columns = [column.strip() for column in line.strip("|").split("|")]
        if len(columns) < 3:
            continue
        match = LINK_RE.search(columns[0])
        if not match:
            continue
        if not category:
            raise ValueError(f"Core row appears before a category: {line}")

        name, url = match.groups()
        repository, branch = canonicalize_repository(url)
        if in_arcade:
            home = ""
            sdram = normalize_sdram(columns[2])
            comments = columns[3] if len(columns) > 3 else ""
        else:
            home = columns[1].strip()
            sdram = normalize_sdram(columns[2])
            comments = columns[3] if len(columns) > 3 else ""
        cores.append(
            Core(category, name.strip(), home, sdram, repository, branch, comments)
        )

    if not cores:
        raise ValueError("No MiSTer cores found between Wiki catalog markers")
    return sorted(
        cores,
        key=lambda core: (
            core.category.lower(),
            core.repository.lower(),
            core.branch.lower(),
            core.home.lower(),
            core.name.lower(),
        ),
    )


def read_source(source: str) -> str:
    if source.startswith(("http://", "https://")):
        curl = shutil.which("curl")
        if not curl:
            raise OSError("curl is required to refresh the HTTPS catalog")
        result = subprocess.run(
            [
                curl, "--fail", "--silent", "--show-error", "--location",
                "--proto", "=https", "--tlsv1.2", "--retry", "3", source,
            ],
            check=True,
            stdout=subprocess.PIPE,
        )
        return result.stdout.decode("utf-8")
    return Path(source).read_text(encoding="utf-8")


def write_catalog(cores: list[Core], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, delimiter="\t", lineterminator="\n")
        writer.writerow(
            ["category", "name", "home", "sdram", "repository", "branch", "source_id", "comments"]
        )
        for core in cores:
            writer.writerow(
                [
                    core.category,
                    core.name,
                    core.home,
                    core.sdram,
                    core.repository,
                    core.branch,
                    core.source_id,
                    core.comments,
                ]
            )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_lock(
    destination: Path,
    source_label: str,
    source_revision: str,
    source_text: str,
    catalog_path: Path,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    rows = [
        ("source", source_label),
        ("revision", source_revision),
        ("source_sha256", sha256_bytes(source_text.encode("utf-8"))),
        ("catalog_sha256", sha256_bytes(catalog_path.read_bytes())),
    ]
    with destination.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, delimiter="\t", lineterminator="\n")
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_URL)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock-output", type=Path)
    parser.add_argument("--source-label")
    parser.add_argument("--source-revision", default="unlocked")
    args = parser.parse_args()
    source_text = read_source(args.source)
    cores = parse_catalog(source_text)
    write_catalog(cores, args.output)
    if args.lock_output:
        write_lock(
            args.lock_output,
            args.source_label or args.source,
            args.source_revision,
            source_text,
            args.output,
        )
    repositories = len({core.repository.lower() for core in cores})
    print(f"Official MiSTer catalog: {len(cores)} entries from {repositories} repositories")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"catalog error: {error}", file=sys.stderr)
        raise SystemExit(1)
