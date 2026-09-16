#!/usr/bin/env python3
"""Unit tests for synthetic report fixtures; these are not proof evidence."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci/spark_report.py"
SUCCESS = (Path(__file__).parent / "fixtures/success.out").read_text(encoding="utf-8")
UNPROVED_COMPLETE = (Path(__file__).parent / "fixtures/unproved_complete.out").read_text(
    encoding="utf-8"
)
SPEC = importlib.util.spec_from_file_location("spark_report", SCRIPT)
assert SPEC and SPEC.loader
SPARK_REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SPARK_REPORT)


class GateTests(unittest.TestCase):
    def gate(self, text: str | None, subprocess_status: int = 0) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "gnatprove.out"
            if text is not None:
                report.write_text(text, encoding="utf-8")
            return subprocess.run(
                [sys.executable, str(SCRIPT), "gate", str(report),
                 "--subprocess-status", str(subprocess_status)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
            )

    def replace_total(self, *, flow: str = "2 (33%)", interval: str = "1 (17%)",
                      provers: str = "3 (50%)", justified: str = ".",
                      unproved: str = ".", total: str = "6") -> str:
        lines = SUCCESS.splitlines()
        index = next(i for i, value in enumerate(lines) if value.startswith("Total "))
        lines[index] = (f"{'Total':<30}{total:<14}{flow:<12}{interval:<11}"
                        f"{provers:<10}{justified:<12}{unproved}")
        return "\n".join(lines) + "\n"

    def test_success_with_dots_and_percentages_and_interval_column(self) -> None:
        self.assertEqual(self.gate(SUCCESS).returncode, 0)

    def test_nonzero_unproved_fails(self) -> None:
        report = self.replace_total(provers="2 (33%)", unproved="1")
        self.assertNotEqual(self.gate(report).returncode, 0)

    def test_actual_not_proved_format_has_complete_analysis_but_fails_gate(self) -> None:
        parsed = SPARK_REPORT.parse_report(UNPROVED_COMPLETE)
        self.assertTrue(parsed["analysis_complete"])
        self.assertEqual(parsed["unproved_checks"], 1)
        self.assertEqual(
            parsed["required_units"]["rtos-pointer_scheduler"]["not_proved_entries"], 1
        )
        self.assertNotEqual(self.gate(UNPROVED_COMPLETE, subprocess_status=1).returncode, 0)

    def test_nonzero_justified_fails(self) -> None:
        report = self.replace_total(provers="2 (33%)", justified="1")
        self.assertNotEqual(self.gate(report).returncode, 0)

    def test_missing_and_truncated_reports_fail(self) -> None:
        self.assertNotEqual(self.gate(None).returncode, 0)
        self.assertNotEqual(self.gate(SUCCESS.split("Total ")[0]).returncode, 0)

    def test_zero_total_fails(self) -> None:
        report = self.replace_total(total=".", flow=".", interval=".", provers=".")
        self.assertNotEqual(self.gate(report).returncode, 0)

    def test_subprocess_failure_overrides_superficially_successful_report(self) -> None:
        self.assertNotEqual(self.gate(SUCCESS, subprocess_status=7).returncode, 0)

    def test_missing_or_incomplete_scheduler_fails(self) -> None:
        self.assertNotEqual(self.gate(SUCCESS.replace("in unit rtos-pointer_scheduler", "in unit other")).returncode, 0)
        self.assertNotEqual(self.gate(SUCCESS.replace("3 subprograms and packages out of 3", "2 subprograms and packages out of 3")).returncode, 0)


class SarifTests(unittest.TestCase):
    def document(self, results: list[dict] | None = None) -> dict:
        return {
            "version": "2.1.0",
            "runs": [{
                "tool": {"driver": {"name": "GNATProve", "version": "FSF 16.1.0",
                                      "rules": [{"id": "VC_ASSERT"}]}},
                "invocations": [{"executionSuccessful": True, "exitCode": 0}],
                "results": [] if results is None else results,
            }],
        }

    def result(self, uri: str = "rtos-pointer_scheduler.ads") -> dict:
        return {
            "ruleId": "VC_ASSERT", "kind": "open", "level": "warning",
            "message": {"text": "assertion might fail"},
            "locations": [{"physicalLocation": {
                "artifactLocation": {"uri": uri}, "region": {"startLine": 15}}}],
        }

    def collect(self, document: dict | str | None, *, stale: bool = False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "src").mkdir()
        (root / "src/rtos-pointer_scheduler.ads").write_text("package X is end X;\n")
        output = root / "obj/gnatprove"
        output.mkdir(parents=True)
        report = output / "gnatprove.out"
        report.write_text("fresh report\n")
        sarif = output / "gnatprove.sarif"
        if document is not None:
            sarif.write_text(document if isinstance(document, str) else json.dumps(document))
        started = sarif.stat().st_mtime_ns + 1 if document is not None and stale else 0
        before = {str(sarif.resolve()): sarif.stat().st_mtime_ns} if stale else {}
        artifact = root / "artifacts"
        artifact.mkdir()
        return temporary, SPARK_REPORT.collect_native_sarif(
            report, artifact, started, before, root
        ), artifact

    def test_native_report_is_collected_and_repository_path_is_mapped(self) -> None:
        temporary, metadata, artifact = self.collect(self.document([self.result()]))
        with temporary:
            self.assertEqual(metadata["results"], 1)
            self.assertEqual(metadata["open_warnings"], 1)
            self.assertTrue((artifact / "gnatprove.sarif").is_file())
            upload = json.loads((artifact / "gnatprove-upload.sarif").read_text())
            location = upload["runs"][0]["results"][0]["locations"][0]
            self.assertEqual(
                location["physicalLocation"]["artifactLocation"]["uri"],
                "src/rtos-pointer_scheduler.ads",
            )

    def test_valid_completed_report_with_no_findings_is_not_missing(self) -> None:
        temporary, metadata, _ = self.collect(self.document())
        with temporary:
            self.assertTrue(metadata["valid"])
            self.assertEqual(metadata["results"], 0)

    def test_missing_malformed_and_truncated_sarif_are_rejected(self) -> None:
        for value in (None, "{", '{"version":"2.1.0"}'):
            with self.subTest(value=value), self.assertRaises(SPARK_REPORT.ReportError):
                self.collect(value)

    def test_stale_sarif_is_rejected(self) -> None:
        with self.assertRaisesRegex(SPARK_REPORT.ReportError, "stale"):
            self.collect(self.document(), stale=True)

    def test_nonzero_analyzer_status_does_not_prevent_collection(self) -> None:
        # Collection is intentionally independent of GNATprove's authoritative status.
        analyzer_status = 1
        temporary, metadata, _ = self.collect(self.document([self.result()]))
        with temporary:
            self.assertEqual(analyzer_status, 1)
            self.assertTrue(metadata["valid"])

    def test_external_dependency_location_is_not_relabelled(self) -> None:
        temporary, _, artifact = self.collect(self.document([self.result("a-nbnbin.ads")]))
        with temporary:
            upload = json.loads((artifact / "gnatprove-upload.sarif").read_text())
            location = upload["runs"][0]["results"][0]["locations"][0]
            self.assertEqual(location["physicalLocation"]["artifactLocation"]["uri"],
                             "a-nbnbin.ads")


if __name__ == "__main__":
    unittest.main()
