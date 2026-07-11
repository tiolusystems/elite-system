from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "scripts" / "launch-elite-system.ps1"
INSTALLER = ROOT / "scripts" / "install-start-menu-shortcut.ps1"


class WindowsLauncherContractTests(unittest.TestCase):
    def test_launcher_starts_runtime_and_opens_production_as_edge_app(self) -> None:
        script = LAUNCHER.read_text(encoding="utf-8")

        self.assertIn("& $StartScript -Port $Port", script)
        self.assertIn('http://127.0.0.1:$Port/producao', script)
        self.assertIn('"--app=$AppUrl"', script)
        self.assertIn("--start-maximized", script)
        self.assertNotIn("SERVICE_ROLE", script)

    def test_installer_creates_current_user_start_menu_shortcut(self) -> None:
        script = INSTALLER.read_text(encoding="utf-8")

        self.assertIn("[Environment]::GetFolderPath('Programs')", script)
        self.assertIn("Elite System.lnk", script)
        self.assertIn("-WindowStyle Hidden", script)
        self.assertIn("launch-elite-system.ps1", script)
        self.assertIn("$shortcut.Save()", script)


if __name__ == "__main__":
    unittest.main()
