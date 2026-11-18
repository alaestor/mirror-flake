import os
import subprocess
import unittest


class PasswordTests(unittest.TestCase):
    def run_pw(self, *args, real=False, **env):
        return subprocess.run(
            [os.environ["PW" if real else "PW_STUB"], *args],
            env={**os.environ, **env}, capture_output=True, text=True, timeout=10,
        )

    def test_overrides(self):
        for flags in [("-w", "-c", "-s"), ("--words", "--caps", "--sep")]:
            for caps in [0, 2, 4, 9]:
                for sep in ["_", "", "a % ' $() "]:
                    with self.subTest(flags=flags, caps=caps, sep=sep):
                        result = self.run_pw(flags[0], "4", flags[1], str(caps), flags[2], sep)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        words = result.stdout.removesuffix("\n").split(sep) if sep else [
                            result.stdout[i:i + 4] for i in range(0, 16, 4)
                        ]
                        self.assertEqual(len(words), 4)
                        self.assertEqual(sum(word == "WORD" for word in words), min(caps, 4))
                        self.assertTrue(all(word in ["word", "WORD"] for word in words))

    def test_defaults(self):
        for real in [False, True]:
            for _ in range(8):
                result = self.run_pw(real=real)
                self.assertEqual(result.returncode, 0, result.stderr)
                words = result.stdout.removesuffix("\n").split("_")
                self.assertTrue(4 <= len(words) <= 7)
                self.assertTrue(all(words))
                self.assertTrue(all(word.islower() or word.isupper() for word in words))

    def test_equals_and_leading_zeroes(self):
        result = self.run_pw("--words=02", "--caps=00", "--sep=:")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "word:word\n")

    def test_invalid_arguments(self):
        for args in [("--words", "0"), ("--words", "-1"), ("--caps", "-1"),
                     ("--words", "1.5"), ("--caps", "abc"), ("--words", ""),
                     ("--caps", ""), ("--words", "999999999999999999999999"),
                     ("--words", "random"), ("--caps", "random"),
                     ("--words",), ("--sep",), ("--unknown",), ("positional",)]:
            with self.subTest(args=args):
                result = self.run_pw(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("pw:", result.stderr)

    def test_diceware_failure(self):
        result = self.run_pw(DICEWARE_FAIL="1")
        self.assertEqual(result.returncode, 17)
        self.assertEqual(result.stdout, "")

    def test_help(self):
        result = self.run_pw("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Usage: pw", result.stdout)


if __name__ == "__main__":
    unittest.main()
