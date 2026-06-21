# GitHub Repository and Release Procedure

## Create repository

The connector used to prepare this bundle cannot create a new GitHub repository. Use GitHub CLI locally:

```bash
gh auth login
gh repo create luis-gustta/geant4-native-radcell --public   --description "Native Geant4 installer and Debian package workflow for RADCELL-style simulations"   --source .   --remote origin   --push
```

Or manually create an empty repo on GitHub, then:

```bash
git remote add origin git@github.com:luis-gustta/geant4-native-radcell.git
git branch -M main
git push -u origin main
```

## Do not commit the `.deb`

Use GitHub Releases for `.deb` packages:

```bash
./scripts/upload-release.sh v11.4.2-1 ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
```

The release asset is the right place for the binary package. The Git repo should contain source, docs, checksums, and packaging scripts.

## Compute checksum

```bash
sha256sum ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb > checksums/SHA256SUMS
```

Commit the checksum file:

```bash
git add checksums/SHA256SUMS
git commit -m "Add release checksum for Geant4 11.4.2 package"
git push
```
