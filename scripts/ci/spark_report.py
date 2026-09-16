#!/usr/bin/env python3
"""Run GNATprove and strictly gate its human-readable analysis report."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

REQUIRED_UNITS = ("rtos-indexed_scheduler", "rtos-pointer_scheduler")
SARIF_NAME = "gnatprove.sarif"
SARIF_UPLOAD_NAME = "gnatprove-upload.sarif"
PROOF_COMMAND = [
    "alr", "-n", "exec", "--", "gnatprove",
    "-P", "spark_rtos_schedulers.gpr", "-U", "--mode=all", "--level=2",
    "--timeout=0", "--steps=10000000",
    "--checks-as-errors=on", "--report=all", "--output=brief",
    "--output-header",
]


class ReportError(ValueError):
    """The report is absent, malformed, or fails the strict gate."""


def validate_and_normalize_sarif(
    source: Path, upload: Path, repository: Path = Path(".")
) -> dict[str, Any]:
    """Validate native GNATprove SARIF and map repository source basenames."""
    try:
        document = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReportError(f"native SARIF is missing or malformed: {exc}") from exc
    if document.get("version") != "2.1.0":
        raise ReportError("native SARIF does not declare version 2.1.0")
    runs = document.get("runs")
    if not isinstance(runs, list) or not runs:
        raise ReportError("native SARIF has no runs")

    source_files: dict[str, list[Path]] = {}
    for path in (repository / "src").glob("**/*"):
        if path.is_file():
            source_files.setdefault(path.name, []).append(path.relative_to(repository))
    result_count = warning_count = mapped_count = 0
    tools = []
    for run in runs:
        if not isinstance(run, dict):
            raise ReportError("native SARIF contains a malformed run")
        driver = run.get("tool", {}).get("driver", {})
        name = driver.get("name")
        if not isinstance(name, str) or name.lower() != "gnatprove":
            raise ReportError(f"native SARIF has unexpected tool identity: {name!r}")
        tools.append({"name": name, "version": driver.get("version", "unavailable")})
        results = run.get("results")
        invocations = run.get("invocations")
        if not isinstance(results, list):
            raise ReportError("native SARIF results are missing or malformed")
        if not isinstance(invocations, list) or not invocations:
            raise ReportError("native SARIF invocation information is missing")
        result_count += len(results)
        for result in results:
            if not isinstance(result, dict) or not isinstance(result.get("ruleId"), str):
                raise ReportError("native SARIF result has no rule identifier")
            if not isinstance(result.get("message", {}).get("text"), str):
                raise ReportError("native SARIF result has no message")
            if result.get("level") == "warning" and result.get("kind") != "pass":
                warning_count += 1
            for location in result.get("locations", []):
                artifact = location.get("physicalLocation", {}).get("artifactLocation", {})
                uri = artifact.get("uri")
                if not isinstance(uri, str) or "/" in uri or "\\" in uri:
                    continue
                matches = source_files.get(uri, [])
                if len(matches) == 1:
                    artifact["uri"] = matches[0].as_posix()
                    mapped_count += 1

    upload.write_text(json.dumps(document, separators=(",", ":")) + "\n", encoding="utf-8")
    return {
        "available": True, "valid": True, "version": "2.1.0", "tools": tools,
        "runs": len(runs), "results": result_count, "open_warnings": warning_count,
        "mapped_locations": mapped_count, "native_file": source.name,
        "upload_file": upload.name,
    }


def collect_native_sarif(
    report: Path, artifact_dir: Path, started: int, before: dict[str, int],
    repository: Path = Path("."),
) -> dict[str, Any]:
    """Collect only the native SARIF paired with the fresh text report."""
    source = report.with_name(SARIF_NAME)
    try:
        stat = source.stat()
    except OSError as exc:
        raise ReportError(f"native SARIF is unavailable beside {report}: {exc}") from exc
    absolute = str(source.resolve())
    if stat.st_mtime_ns < started and stat.st_mtime_ns == before.get(absolute):
        raise ReportError("native SARIF is stale from an earlier invocation")
    native_copy = artifact_dir / SARIF_NAME
    native_copy.write_bytes(source.read_bytes())
    return validate_and_normalize_sarif(
        native_copy, artifact_dir / SARIF_UPLOAD_NAME, repository
    )


def _number(cell: str, name: str) -> int:
    cell = cell.strip()
    if cell == ".":
        return 0
    match = re.match(r"(\d+)(?:\s|\(|$)", cell)
    if not match:
        raise ReportError(f"cannot interpret {name} column value: {cell!r}")
    return int(match.group(1))


def parse_report(text: str) -> dict[str, Any]:
    lines = text.splitlines()
    try:
        header_index = next(
            i for i, line in enumerate(lines)
            if "SPARK Analysis results" in line and "Total" in line
            and "Justified" in line and "Unproved" in line
        )
    except StopIteration as exc:
        raise ReportError("analysis summary table is missing or truncated") from exc

    header = lines[header_index]
    labels = [(m.group(), m.start()) for m in re.finditer(
        r"SPARK Analysis results|\S+", header
    )]
    names = [name for name, _ in labels]
    if names[:2] != ["SPARK Analysis results", "Total"] or names[-2:] != ["Justified", "Unproved"]:
        raise ReportError(f"unsupported summary columns: {names}")
    def cells(line: str) -> dict[str, str]:
        # GNATprove right-aligns long prover annotations across the whitespace
        # before their heading, so heading offsets are not cell boundaries.
        # Category names occupy the stable first 30 characters; subsequent
        # cells are a count/zero marker with an optional parenthesized detail.
        values = re.findall(r"(?<!\S)(?:\.|\d+(?:\s+\([^)]*\))?)(?!\S)", line[30:])
        if len(values) != len(names) - 1:
            return {names[0]: line[:30].strip(), **{name: "" for name in names[1:]}}
        return {names[0]: line[:30].strip(), **dict(zip(names[1:], values))}

    rows: list[dict[str, Any]] = []
    total_cells: dict[str, str] | None = None
    table_lines: list[str] = [header]
    for line in lines[header_index + 1:]:
        if set(line.strip()) == {"-"}:
            table_lines.append(line)
            continue
        row = cells(line)
        category = row["SPARK Analysis results"]
        if category == "Total":
            total_cells = row
            table_lines.append(line)
            break
        if category and row["Total"]:
            table_lines.append(line)
            rows.append({
                "category": category,
                **{name.lower(): _number(row[name], name) for name in names[1:]},
                "columns": {name: row[name] for name in names[1:]},
            })
    if total_cells is None:
        raise ReportError("summary Total row is missing or truncated")

    totals = {name.lower(): _number(total_cells[name], name) for name in names[1:]}
    total = totals["total"]
    justified = totals["justified"]
    unproved = totals["unproved"]
    method_names = names[2:-2]
    discharged = sum(totals[name.lower()] for name in method_names)
    if discharged + justified + unproved != total:
        raise ReportError(
            "summary columns do not account for Total "
            f"({discharged} discharged + {justified} justified + {unproved} unproved != {total})"
        )

    unit_pattern = re.compile(
        r"^in unit (\S+),\s+(\d+) subprograms and packages out of (\d+) analyzed\s*$"
    )
    unit_counts: dict[str, dict[str, Any]] = {}
    current_unit: str | None = None
    detail_pattern = re.compile(
        r"^  .+ flow analyzed \((\d+) errors?, \d+ checks?, \d+ warnings? "
        r"and \d+ pragma Assume statements?\) and "
        r"(?:(proved) \((\d+) checks?\)|"
        r"(not proved), (\d+) checks? out of (\d+) proved)$"
    )
    for line in lines:
        if match := unit_pattern.match(line):
            current_unit = match.group(1)
            unit_counts[current_unit] = {
                "analyzed": int(match.group(2)), "available": int(match.group(3)),
                "detailed_entries": 0, "malformed_entries": 0,
                "analysis_errors": 0, "proved_entries": 0,
                "not_proved_entries": 0,
            }
        elif current_unit and line.startswith("  "):
            detail = detail_pattern.match(line)
            if detail is None:
                unit_counts[current_unit]["malformed_entries"] += 1
                continue
            unit_counts[current_unit]["detailed_entries"] += 1
            unit_counts[current_unit]["analysis_errors"] += int(detail.group(1))
            if detail.group(2) == "proved":
                unit_counts[current_unit]["proved_entries"] += 1
            else:
                proved, checks = int(detail.group(5)), int(detail.group(6))
                if proved >= checks:
                    unit_counts[current_unit]["malformed_entries"] += 1
                unit_counts[current_unit]["not_proved_entries"] += 1
    missing = [unit for unit in REQUIRED_UNITS if unit not in unit_counts]
    incomplete = [
        unit for unit in REQUIRED_UNITS if unit in unit_counts
        and (unit_counts[unit]["available"] == 0
             or unit_counts[unit]["analyzed"] != unit_counts[unit]["available"]
             or unit_counts[unit]["detailed_entries"] != unit_counts[unit]["analyzed"]
             or unit_counts[unit]["malformed_entries"] != 0)
    ]
    error_counts = [int(value) for value in re.findall(r"\((\d+) errors?[,)]", text)]
    if not error_counts:
        raise ReportError("detailed analysis error counts are missing or truncated")

    failures = []
    if total <= 0:
        failures.append("zero checks were analyzed")
    if unproved:
        failures.append(f"{unproved} checks are unproved")
    if justified:
        failures.append(f"{justified} checks are justified rather than proved")
    if missing:
        failures.append("required analysis is absent: " + ", ".join(missing))
    if incomplete:
        failures.append("required analysis is incomplete: " + ", ".join(incomplete))
    if any(error_counts):
        failures.append(f"detailed analysis contains {sum(error_counts)} errors")

    return {
        "columns": names[1:],
        "totals": totals,
        "total_checks": total,
        "discharged_checks": discharged,
        "unproved_checks": unproved,
        "justified_checks": justified,
        "categories": rows,
        "required_units": unit_counts,
        "analysis_complete": not missing and not incomplete and not any(error_counts),
        "gate_failures": failures,
        "original_summary_table": "\n".join(table_lines),
    }


def _capture(command: list[str]) -> str:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    return result.stdout.strip() + f"\n[exit status: {result.returncode}]\n"


def record_versions(artifact_dir: Path) -> dict[str, str]:
    commands = {
        "alire": ["alr", "version"],
        "dependency_materialization": ["alr", "-n", "update"],
        "gnatprove": ["alr", "-n", "exec", "--", "gnatprove", "--version"],
        "gnat": ["alr", "-n", "exec", "--", "gnat", "--version"],
        "gprbuild": ["alr", "-n", "exec", "--", "gprbuild", "--version"],
        "dependency_resolution": ["alr", "-n", "show", "--solve"],
        "toolchain": ["alr", "-n", "toolchain"],
    }
    outputs = {name: _capture(command) for name, command in commands.items()}
    artifact_dir.mkdir(parents=True, exist_ok=True)
    (artifact_dir / "versions.txt").write_text("".join(
        f"## {name}\n{outputs[name]}\n" for name in commands
    ), encoding="utf-8")
    if not outputs["dependency_materialization"].rstrip().endswith("[exit status: 0]"):
        raise ReportError("noninteractive Alire dependency materialization failed")
    resolved = outputs["dependency_resolution"]
    if "gnatprove=16.1.0" not in resolved:
        raise ReportError("Alire did not resolve the required GNATprove 16.1.0")
    patterns = {
        "alire": r"alr version:\s*(.+)",
        "gnatprove": r"^(FSF .+)$",
        "gnat": r"^(GNAT .+)$",
        "gprbuild": r"^(GPRBUILD .+)$",
    }
    versions = {}
    for name, pattern in patterns.items():
        match = re.search(pattern, outputs[name], re.MULTILINE)
        versions[name] = match.group(1).strip() if match else "unavailable"
    return versions


def _identity() -> dict[str, str]:
    def git(*args: str) -> str:
        result = subprocess.run(["git", *args], text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=False)
        return result.stdout.strip() if result.returncode == 0 else "unavailable"
    return {
        "repository": os.environ.get("GITHUB_REPOSITORY", git("config", "--get", "remote.origin.url")),
        "commit": os.environ.get("GITHUB_SHA", git("rev-parse", "HEAD")),
        "event": os.environ.get("GITHUB_EVENT_NAME", "local"),
        "ref": os.environ.get("GITHUB_REF", git("branch", "--show-current")),
    }


def make_summary(data: dict[str, Any]) -> str:
    identity = data["identity"]
    versions = data.get("versions", {})
    parsed = data.get("report")
    completed = parsed is not None
    gate = completed and data.get("gnatprove_exit_status") == 0 and not parsed["gate_failures"]
    status = "PASS" if gate else "FAIL — proof not completed" if not completed else "FAIL"
    lines = [
        "# SPARK Verification", "", f"**Result: {status}**", "",
        f"- Repository: `{identity['repository']}`",
        f"- Commit: `{identity['commit']}`",
        f"- Event/ref: `{identity['event']}` / `{identity['ref']}`",
        f"- Analysis: `--mode=all`, proof level `2`",
        f"- GNATprove exit status: `{data.get('gnatprove_exit_status', 'unavailable')}`",
        f"- GNATprove: `{versions.get('gnatprove', 'unavailable')}`",
        f"- GNAT: `{versions.get('gnat', 'unavailable')}`",
        f"- GPRbuild: `{versions.get('gprbuild', 'unavailable')}`",
        f"- Alire: `{versions.get('alire', 'unavailable')}`", "",
    ]
    sarif = data.get("sarif")
    if sarif and sarif.get("valid"):
        lines += [
            "## SARIF publication", "",
            f"- Native SARIF: available and valid (`{sarif['version']}`, {sarif['results']} results)",
            "- Publication: pending upload step",
            "- Category: `spark-gnatprove`", "",
        ]
    else:
        reason = data.get("sarif_error", "native SARIF unavailable")
        lines += ["## SARIF publication", "", f"- Native SARIF: unavailable or invalid ({reason})",
                  "- Publication: not attempted", ""]
    if completed:
        lines += [
            "| Metric | Count |", "|---|---:|",
            f"| Total checks | {parsed['total_checks']} |",
            f"| Discharged checks | {parsed['discharged_checks']} |",
            f"| Unproved checks | {parsed['unproved_checks']} |",
            f"| Justified checks | {parsed['justified_checks']} |", "",
            f"**Analysis completeness:** {'complete' if parsed['analysis_complete'] else 'incomplete'}", "",
        ]
        if parsed["gate_failures"]:
            lines += ["Gate failures:"] + [f"- {item}" for item in parsed["gate_failures"]] + [""]
        lines += ["## Category and analysis-method breakdown", ""]
        columns = ["category", *[name.lower() for name in parsed["columns"]]]
        lines += ["| " + " | ".join(columns) + " |", "|" + "|".join(["---"] * len(columns)) + "|"]
        for row in parsed["categories"]:
            lines.append("| " + " | ".join([row["category"], *[str(row[name]) for name in columns[1:]]]) + " |")
        lines += ["", "<details><summary>Original GNATprove summary table</summary>", "", "```text",
                  parsed["original_summary_table"], "```", "</details>", ""]
    else:
        lines += ["No valid fresh GNATprove report was available. Missing analysis is not treated as zero failures.", ""]
    return "\n".join(lines)


def run_proof(artifact_dir: Path) -> int:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    data: dict[str, Any] = {"identity": _identity(), "gnatprove_exit_status": "not run"}
    tracked_paths = list(Path(".").glob("**/gnatprove.out")) + list(Path(".").glob("**/gnatprove.sarif"))
    before = {str(path.resolve()): path.stat().st_mtime_ns for path in tracked_paths}
    try:
        data["versions"] = record_versions(artifact_dir)
    except Exception as exc:  # Keep honest diagnostics for early tool failure.
        data["setup_error"] = str(exc)
        return write_results(artifact_dir, data, 1)

    log_path = artifact_dir / "gnatprove.log"
    started = time.time_ns()
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(PROOF_COMMAND, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT)
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            log.write(line)
        status = process.wait()
    data["gnatprove_exit_status"] = status

    candidates = []
    for path in Path(".").glob("**/gnatprove.out"):
        stat = path.stat()
        absolute = str(path.resolve())
        if stat.st_mtime_ns >= started or stat.st_mtime_ns != before.get(absolute):
            candidates.append(path)
    if len(candidates) != 1:
        data["report_error"] = f"expected one fresh gnatprove.out, found {len(candidates)}"
        return write_results(artifact_dir, data, 1)
    report_text = candidates[0].read_text(encoding="utf-8")
    (artifact_dir / "gnatprove.out").write_text(report_text, encoding="utf-8")
    try:
        data["sarif"] = collect_native_sarif(
            candidates[0], artifact_dir, started, before
        )
    except ReportError as exc:
        data["sarif_error"] = str(exc)
    try:
        data["report"] = parse_report(report_text)
    except ReportError as exc:
        data["report_error"] = str(exc)
        return write_results(artifact_dir, data, 1)
    gate_status = 0 if (status == 0 and not data["report"]["gate_failures"]
                        and "sarif_error" not in data) else 1
    return write_results(artifact_dir, data, gate_status)


def write_results(artifact_dir: Path, data: dict[str, Any], status: int) -> int:
    summary = make_summary(data)
    (artifact_dir / "summary.md").write_text(summary, encoding="utf-8")
    (artifact_dir / "summary.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary_path, "a", encoding="utf-8") as output:
            output.write(summary + "\n")
    if data.get("report_error"):
        print(f"report gate: {data['report_error']}", file=sys.stderr)
    if data.get("sarif_error"):
        print(f"SARIF reporting: {data['sarif_error']}", file=sys.stderr)
    if output_path := os.environ.get("GITHUB_OUTPUT"):
        with open(output_path, "a", encoding="utf-8") as output:
            output.write(f"sarif_valid={'true' if data.get('sarif', {}).get('valid') else 'false'}\n")
    for failure in data.get("report", {}).get("gate_failures", []):
        print(f"report gate: {failure}", file=sys.stderr)
    return status


def gate_file(report: Path, subprocess_status: int) -> int:
    data: dict[str, Any] = {
        "identity": _identity(), "gnatprove_exit_status": subprocess_status,
        "versions": {},
    }
    try:
        data["report"] = parse_report(report.read_text(encoding="utf-8"))
        status = 0 if subprocess_status == 0 and not data["report"]["gate_failures"] else 1
    except (OSError, ReportError) as exc:
        print(f"report gate: {exc}", file=sys.stderr)
        status = 1
    return status


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--artifact-dir", type=Path, default=Path("artifacts/spark"))
    gate_parser = subparsers.add_parser("gate")
    gate_parser.add_argument("report", type=Path)
    gate_parser.add_argument("--subprocess-status", type=int, default=0)
    args = parser.parse_args()
    if args.command == "run":
        return run_proof(args.artifact_dir)
    return gate_file(args.report, args.subprocess_status)


if __name__ == "__main__":
    raise SystemExit(main())