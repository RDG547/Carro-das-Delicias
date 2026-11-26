#!/usr/bin/env python3
"""Build Android releases using only public client configuration."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_KEYS = (
    'GOOGLE_WEB_CLIENT_ID', 'MAPBOX_ACCESS_TOKEN', 'SUPABASE_URL',
    'SUPABASE_ANON_KEY', 'STRIPE_PUBLISHABLE_KEY', 'FIREBASE_API_KEY',
    'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID',
    'FIREBASE_STORAGE_BUCKET',
)


def public_configuration(config_path, environment=None):
    environment = os.environ if environment is None else environment
    source = json.loads(config_path.read_text()) if config_path.is_file() else {}
    values = {key: str(environment.get(key) or source.get(key) or '').strip()
              for key in PUBLIC_KEYS}
    if not values['MAPBOX_ACCESS_TOKEN']:
        properties = ROOT / 'android/local.properties'
        if properties.is_file():
            for line in properties.read_text().splitlines():
                if line.strip().startswith('MAPBOX_ACCESS_TOKEN='):
                    values['MAPBOX_ACCESS_TOKEN'] = line.split('=', 1)[1].strip()
                    break
    if not values['MAPBOX_ACCESS_TOKEN'].startswith('pk.'):
        raise ValueError('Configure um token público pk. do Mapbox em MAPBOX_ACCESS_TOKEN.')
    return {key: value for key, value in values.items() if value}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default=shutil.which('flutter'))
    parser.add_argument('--config', type=Path, default=ROOT / '.env.json')
    parser.add_argument('--with-apk', action='store_true', help='Também gera um APK arm64 para teste.')
    parser.add_argument('--build-name', help='Define o versionName do Android.')
    parser.add_argument('--build-number', type=int, help='Define o versionCode do Android.')
    parser.add_argument('--no-pub', action='store_true', help='Reutiliza as dependências já resolvidas.')
    args = parser.parse_args()
    if not args.flutter:
        parser.error('Informe o executável Flutter com --flutter.')
    try:
        values = public_configuration(args.config)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    with tempfile.TemporaryDirectory(prefix='carrodasdelicias-public-build-') as directory:
        config = Path(directory) / 'public.json'
        config.write_text(json.dumps(values))
        common = ['--release', f'--dart-define-from-file={config}', '--no-pub']
        if args.build_name is not None:
            common.append(f'--build-name={args.build_name}')
        if args.build_number is not None:
            common.append(f'--build-number={args.build_number}')
        if not args.no_pub:
            subprocess.run([args.flutter, 'pub', 'get'], cwd=ROOT, check=True)
        # Os recursos do Android usam os mesmos valores públicos compilados no Dart.
        build_environment = {**os.environ, **values}
        subprocess.run([args.flutter, 'build', 'appbundle', *common], cwd=ROOT, check=True, env=build_environment)
        if args.with_apk:
            subprocess.run([args.flutter, 'build', 'apk', '--target-platform', 'android-arm64', *common], cwd=ROOT, check=True, env=build_environment)


if __name__ == '__main__':
    main()
