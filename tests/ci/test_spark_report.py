#!/usr/bin/env python3
"""Unit tests for synthetic report fixtures; these are not proof evidence."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/ci/spark_report.py"
SUCCESS = (Path(__file__).parent / "fixtures/success.out").read_text(encoding="utf-8")


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


if __name__ == "__main__":
    unittest.main()