# Installation and Validation

## Build a Debian package

```bash
chmod +x install_geant4_native.sh
./install_geant4_native.sh --deb --version 11.4.2 --jobs 4
```

For a low-memory machine:

```bash
./install_geant4_native.sh --deb --version 11.4.2 --jobs 2
```

## Install the package

```bash
sudo apt install ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
```

If the file is inside a path with spaces, quote it:

```bash
sudo apt install "/home/luis/Desktop/working on/new/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb"
```

The `_apt` unsandboxed-root warning is usually nonfatal. To avoid it, copy the package to `/tmp` first:

```bash
cp "/path/to/geant4-native_11.4.2-1_amd64.deb" /tmp/
chmod 644 /tmp/geant4-native_11.4.2-1_amd64.deb
sudo apt install --reinstall /tmp/geant4-native_11.4.2-1_amd64.deb
```

## Validate environment

```bash
source /opt/geant4/11.4.2/bin/geant4.sh
[ -r /etc/profile.d/geant4-11.4.2-datasets.sh ] && source /etc/profile.d/geant4-11.4.2-datasets.sh

geant4-config --version
geant4-config --prefix
env | grep '^G4.*DATA'
```

Expected:

```text
11.4.2
/opt/geant4/11.4.2
```

## Validate shared libraries

```bash
find /opt/geant4/11.4.2/lib -name "*.so" -exec ldd {} \; | grep "not found"
```

Expected output: nothing.

## Validate with B1

```bash
rm -rf ~/geant4-test
mkdir -p ~/geant4-test
cp -r /opt/geant4/11.4.2/share/Geant4/examples/basic/B1 ~/geant4-test/

cmake -S ~/geant4-test/B1       -B ~/geant4-test/B1/build       -DGeant4_DIR=/opt/geant4/11.4.2/lib/cmake/Geant4

cmake --build ~/geant4-test/B1/build --parallel 4
cd ~/geant4-test/B1/build
./exampleB1 ../run1.mac
```
