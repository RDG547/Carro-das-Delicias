import unittest

from play_store_release import next_code, release_content, submitted


class PlayStoreReleaseTest(unittest.TestCase):
    def test_version_code_considers_every_track_and_binary(self):
        tracks = [{
            'track': 'internal',
            'releases': [{'versionCodes': ['2026112204']}],
        }]
        self.assertEqual(
            next_code(2026112202, tracks, [{'versionCode': 2026112205}],
                      [{'versionCode': 2026112203}]),
            2026112206,
        )
        self.assertEqual(next_code(2026112202, [], [], []), 2026112203)

    def test_version_code_cannot_exceed_google_play_limit(self):
        with self.assertRaises(ValueError):
            next_code(2100000000, [], [], [])

    def test_semver_and_portuguese_notes(self):
        messages = ['fix: corrige cálculo da entrega', 'feat: inclui filtros de pedidos',
                    'fix: corrige cálculo da entrega', 'ci: atualiza o GitHub Actions']
        self.assertEqual(
            release_content((1, 0, 16), (1, 0, 16), messages),
            ('1.1.0', '• Corrige cálculo da entrega\n• Inclui filtros de pedidos'),
        )
        self.assertEqual(
            release_content((1, 0, 16), (1, 1, 2), ['feat!: reformula o checkout'])[0],
            '2.0.0',
        )
        self.assertEqual(
            release_content((1, 0, 16), (1, 1, 2), ['fix: corrige o checkout'])[0],
            '1.1.3',
        )

    def test_same_commit_is_identified_after_submission(self):
        sha = 'c0523eea71ceac8d2fb83bac8c5aef5ea198e930'
        release = {'name': '1.0.17 (c0523eea71ce)', 'status': 'completed'}
        self.assertTrue(submitted([release], sha))
        self.assertFalse(submitted([{**release, 'status': 'draft'}], sha))
        self.assertFalse(submitted([release], '0' * 40))


if __name__ == '__main__':
    unittest.main()
