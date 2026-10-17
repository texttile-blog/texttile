"""A failed backup download must preserve the previous local snapshot."""
from contextlib import closing
import importlib.util
import io
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("pull_db", Path(__file__).resolve().parents[2] / "scripts/pull-db.py")
pull_db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pull_db)


class PullDatabaseTest(unittest.TestCase):
    def test_invalid_download_preserves_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "snapshot.db"
            target.write_bytes(b"previous snapshot")
            with patch.object(pull_db.urllib.request, "urlopen", return_value=io.BytesIO(b"not SQLite")):
                with self.assertRaises(sqlite3.DatabaseError):
                    pull_db.download("https://staging.example", "private", target)
            self.assertEqual(target.read_bytes(), b"previous snapshot")
            self.assertEqual(list(Path(directory).iterdir()), [target])

    def test_download_installs_a_private_valid_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.db"
            with closing(sqlite3.connect(source)) as db:
                db.execute("CREATE TABLE entries (title TEXT)")
                db.execute("INSERT INTO entries VALUES ('kept')")
                db.commit()
            target = Path(directory) / "snapshot.db"
            with patch.object(pull_db.urllib.request, "urlopen", return_value=io.BytesIO(source.read_bytes())) as request:
                pull_db.download("https://staging.example/", "private", target)
            with closing(sqlite3.connect(target)) as db:
                self.assertEqual(db.execute("SELECT title FROM entries").fetchone(), ("kept",))
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(request.call_args.args[0].get_header("Authorization"), "Bearer private")
