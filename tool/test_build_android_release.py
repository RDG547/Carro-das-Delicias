import json
from pathlib import Path
import tempfile
import unittest
from build_android_release import public_configuration


class PublicBuildConfigurationTest(unittest.TestCase):
    def test_payment_secrets_are_never_forwarded_to_the_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config.json'
            config.write_text(json.dumps({
                'MAPBOX_ACCESS_TOKEN': 'pk.public-test',
                'GOOGLE_WEB_CLIENT_ID': 'public-client.apps.googleusercontent.com',
                'STRIPE_SECRET_KEY': 'sk_private_test',
                'ABACATEPAY_API_KEY': 'private_test',
                'SUPABASE_SERVICE_ROLE_KEY': 'private_test',
            }))
            result = public_configuration(config, {
                'STRIPE_SECRET_KEY': 'another_private_key',
                'SUPABASE_SERVICE_ROLE_KEY': 'another_private_key',
            })
            self.assertEqual(set(result), {'MAPBOX_ACCESS_TOKEN', 'GOOGLE_WEB_CLIENT_ID'})
            self.assertNotIn('private', json.dumps(result))

    def test_environment_overrides_the_local_public_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config.json'
            config.write_text(json.dumps({'MAPBOX_ACCESS_TOKEN': 'pk.local'}))
            self.assertEqual(public_configuration(config, {'MAPBOX_ACCESS_TOKEN': 'pk.ci'})['MAPBOX_ACCESS_TOKEN'], 'pk.ci')

    def test_private_mapbox_token_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config.json'
            config.write_text(json.dumps({'MAPBOX_ACCESS_TOKEN': 'sk.private'}))
            with self.assertRaises(ValueError):
                public_configuration(config, {})


if __name__ == '__main__':
    unittest.main()
