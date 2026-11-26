#!/usr/bin/env python3
"""Prepare and submit the Android release through Google Play's Publishing API."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

PACKAGE = 'com.rdtech.carrodasdelicias'
API = 'https://androidpublisher.googleapis.com'
APP = f'/androidpublisher/v3/applications/{PACKAGE}'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'
MAX_VERSION_CODE = 2_100_000_000
SEMVER = r'(\d+)\.(\d+)\.(\d+)'
MANAGED_RELEASE = re.compile(rf'^{SEMVER} \(([0-9a-f]{{12}})\)$')
CONVENTIONAL = re.compile(r'^(feat|fix|perf|revert)(?:\([^)]*\))?(!)?:\s*(.+)$', re.I)
PT_BR_SUBJECT = re.compile(r'^(adiciona|inclui|implementa|melhora|corrige|ajusta|restaura)\b', re.I)


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def production_releases(tracks):
    return next((track.get('releases', []) for track in tracks if track['track'] == 'production'), [])


def release_version_code(release):
    return max((int(code) for code in release.get('versionCodes', [])), default=0)


def next_code(in_repo, tracks, bundles, apks):
    track_codes = [release_version_code(release) for track in tracks
                   for release in track.get('releases', [])]
    binary_codes = [int(binary['versionCode']) for binary in bundles + apks]
    code = max([in_repo, *track_codes, *binary_codes]) + 1
    if code > MAX_VERSION_CODE:
        raise ValueError('O próximo versionCode ultrapassa o limite da Google Play.')
    return code


def submitted(releases, commit):
    return any(release.get('status') != 'draft'
               and (match := MANAGED_RELEASE.fullmatch(release.get('name', '')))
               and match[4] == commit[:12] for release in releases)


def publication_baseline(repo_version, repo_code, releases):
    release = max((r for r in releases if r.get('status') != 'draft'),
                  key=release_version_code, default={})
    name = release.get('name', '')
    managed = MANAGED_RELEASE.fullmatch(name)
    published = re.search(rf'(?<!\d){SEMVER}(?!\d)', name)
    version = tuple(map(int, published.groups())) if published else repo_version

    if managed:
        return version, managed[4]

    label = '.'.join(map(str, version))
    build_code = release_version_code(release) or repo_code
    for tag in (f'v{label}-build.{build_code}', f'v{label}'):
        if git('tag', '--list', tag):
            return version, tag
    return version, git('log', '-1', '--format=%H', '-S', f'version: {label}+',
                        '--', 'pubspec.yaml')


def release_content(repo_version, published_version, commits):
    bump = 'patch'
    notes = []
    for message in commits:
        subject = message.strip().partition('\n')[0]
        change = CONVENTIONAL.fullmatch(subject)
        if (change and change[2]) or re.search(r'^BREAKING[ -]CHANGE:', message, re.M):
            bump = 'major'
        elif bump != 'major' and ((change and change[1].lower() == 'feat')
                                  or re.match(r'^(adiciona|inclui|implementa)\b', subject, re.I)):
            bump = 'minor'

        note = change[3] if change else subject if PT_BR_SUBJECT.match(subject) else ''
        if note:
            note = note[0].upper() + note[1:]
            bullet = f'• {note}'
            if bullet not in notes and len('\n'.join([*notes, bullet])) <= 500:
                notes.append(bullet)

    major, minor, patch = published_version
    incremented = {
        'major': (major + 1, 0, 0),
        'minor': (major, minor + 1, 0),
        'patch': (major, minor, patch + 1),
    }[bump]
    version = max(repo_version, incremented)
    return '.'.join(map(str, version)), '\n'.join(notes) or 'Melhorias de estabilidade e desempenho.'


class PlayAPI:
    def __init__(self):
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2.service_account import Credentials

        secret = os.environ.get('PLAY_SERVICE_ACCOUNT_JSON')
        if not secret:
            raise ValueError('Configure PLAY_SERVICE_ACCOUNT_JSON no ambiente google-play do GitHub.')
        account = json.loads(secret)
        account['token_uri'] = 'https://oauth2.googleapis.com/token'
        credentials = Credentials.from_service_account_info(account, scopes=[SCOPE])
        self.session = AuthorizedSession(credentials)

    def call(self, method, path, **kwargs):
        response = self.session.request(method, API + path, timeout=(20, 600), **kwargs)
        if not response.ok:
            try:
                message = response.json().get('error', {}).get('message', '')
            except ValueError:
                message = ''
            raise RuntimeError(f'Google Play {method} {path}: HTTP {response.status_code}. {message}')
        return response.json() if response.content else {}

    def open_edit(self):
        edit = self.call('POST', f'{APP}/edits', json={})
        return f'{APP}/edits/{edit["id"]}'

    def discard(self, edit):
        try:
            self.call('DELETE', edit)
        except RuntimeError:
            # A edição pode ter sido invalidada pelo Console ou já confirmada pela API.
            pass

    def inspect(self, edit):
        tracks = self.call('GET', f'{edit}/tracks').get('tracks', [])
        bundles = self.call('GET', f'{edit}/bundles').get('bundles', [])
        apks = self.call('GET', f'{edit}/apks').get('apks', [])
        return tracks, bundles, apks


def prepare(api, target):
    pubspec = Path('pubspec.yaml').read_text()
    repo_info = re.search(rf'^version:\s*{SEMVER}\+(\d+)\s*$', pubspec, re.M)
    if not repo_info:
        raise ValueError('Esperada uma versão x.y.z+código no pubspec.yaml.')
    repo_version = tuple(map(int, repo_info.groups()[:3]))
    repo_code = int(repo_info[4])
    commit = git('rev-parse', 'HEAD')

    edit = api.open_edit()
    try:
        tracks, bundles, apks = api.inspect(edit)
    finally:
        api.discard(edit)

    releases = production_releases(tracks)
    if submitted(releases, commit):
        target.write_text(json.dumps({'submitted': True}))
        print('Este commit já consta na faixa de produção.')
        return

    published_version, previous_ref = publication_baseline(repo_version, repo_code, releases)
    revisions = [f'{previous_ref}..HEAD'] if previous_ref else ['-1']
    history = git('log', '--no-merges', '--format=%B%x00', *revisions,
                  '--', 'lib', 'assets', 'android', 'pubspec.yaml', 'pubspec.lock')
    name, notes = release_content(repo_version, published_version, history.split('\0'))
    code = next_code(repo_code, tracks, bundles, apks)
    target.write_text(json.dumps({'name': name, 'code': code, 'notes': notes, 'commit': commit}))
    print(f'AAB planejado: {name} ({code}).')


def requires_new_build(paths):
    return any(not path.endswith('.md')
               and not path.startswith(('docs/', 'release_notes/', 'releases/'))
               for path in paths)


def ensure_current_app(commit):
    git('fetch', '--quiet', '--no-tags', 'origin', 'refs/heads/main')
    if subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'FETCH_HEAD']).returncode:
        raise ValueError('O commit do AAB saiu do histórico da main.')
    changed = git('diff', '--name-only', '-z', commit, 'FETCH_HEAD').split('\0')
    if requires_new_build(filter(None, changed)):
        raise ValueError('A main já tem mudanças de aplicativo mais recentes. Use a execução mais nova.')


def publish(api, plan_file, bundle):
    plan = json.loads(plan_file.read_text())
    commit = git('rev-parse', 'HEAD')
    if commit != plan['commit']:
        raise ValueError('O commit do AAB diverge do plano de publicação.')
    ensure_current_app(commit)

    edit = api.open_edit()
    committed = False
    try:
        tracks, bundles, apks = api.inspect(edit)
        if submitted(production_releases(tracks), commit):
            print('Este commit já consta na faixa de produção.')
            return
        code = plan['code']
        if next_code(0, tracks, bundles, apks) > code:
            raise ValueError('O versionCode da Play Store mudou durante o build. Execute novamente.')

        with bundle.open('rb') as aab:
            sha256 = hashlib.file_digest(aab, 'sha256').hexdigest()
            aab.seek(0)
            uploaded = api.call('POST', f'/upload{edit}/bundles', params={'uploadType': 'media'},
                                headers={'Content-Type': 'application/octet-stream'}, data=aab)
        if int(uploaded['versionCode']) != code or uploaded['sha256'].lower() != sha256:
            raise ValueError('O versionCode ou o hash do AAB recebido pela Google Play diverge do build.')

        api.call('PUT', f'{edit}/tracks/production', json={
            'track': 'production',
            'releases': [{
                'name': f'{plan["name"]} ({commit[:12]})',
                'versionCodes': [str(code)],
                'status': 'completed',
                'releaseNotes': [{'language': 'pt-BR', 'text': plan['notes']}],
            }],
        })
        api.call('POST', f'{edit}:commit', params={
            'changesNotSentForReview': 'false',
            'changesInReviewBehavior': 'CANCEL_IN_REVIEW_AND_SUBMIT',
        })
        committed = True
        print(f'Versão {plan["name"]} ({code}) enviada para revisão na faixa de produção.')
    finally:
        if not committed:
            api.discard(edit)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'publish'])
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--bundle', type=Path)
    args = parser.parse_args()
    if args.command == 'publish' and not args.bundle:
        parser.error('Informe o arquivo .aab com --bundle.')

    try:
        api = PlayAPI()
        if args.command == 'prepare':
            prepare(api, args.plan)
        else:
            publish(api, args.plan, args.bundle)
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
