#!/usr/bin/env python3
"""Sign nested Mach-O code, optionally notarize/staple, and package Mimir.

Requires a Developer ID Application identity in the login Keychain.
Notarization credentials are referenced by profile name; no passwords in files.
"""
import argparse
import os
from pathlib import Path
import subprocess


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', default='build/DerivedData/Build/Products/Release/Mimir.app')
    parser.add_argument('--identity', default=os.environ.get('SIGNING_IDENTITY', 'Developer ID Application: James Campbell (529AKJCKRC)'))
    parser.add_argument('--notarize', action='store_true')
    parser.add_argument('--profile', default=os.environ.get('NOTARY_PROFILE', 'notarytool-profile'))
    args = parser.parse_args()
    app = Path(args.app).resolve()
    if not app.is_dir():
        parser.error(f'Build the Release app first: {app}')
    entitlements = Path('Mimir/Mimir.entitlements').resolve()
    magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    files = []
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in magic:
                    files.append(path)
    for path in sorted(files, key=lambda p: len(p.parts), reverse=True):
        run('codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', args.identity, path)
    bundles = [p for p in app.rglob('*') if p.is_dir() and p.suffix in {'.framework', '.bundle', '.xpc', '.app'}]
    for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        run('codesign', '--force', '--timestamp', '--options', 'runtime', '--sign', args.identity, path)
    run('codesign', '--force', '--timestamp', '--options', 'runtime', '--entitlements', entitlements, '--sign', args.identity, app)
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', app)
    dist = Path('build/dist')
    dist.mkdir(parents=True, exist_ok=True)
    archive = dist / 'Mimir-macOS-arm64.zip'
    archive.unlink(missing_ok=True)
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    if args.notarize:
        run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile', args.profile, '--wait', '--output-format', 'json')
        run('xcrun', 'stapler', 'staple', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', app)
        archive.unlink()
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
        print(f'NOTARIZED and stapled: {archive.resolve()}')
    else:
        print(f'Developer ID signed, NOT yet notarized: {archive.resolve()}')


if __name__ == '__main__':
    main()
