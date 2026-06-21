#!/usr/bin/env bash
set -Eeuo pipefail

# Native Geant4 installer/packager without Spack.
# Debian/Ubuntu/Linux Mint can produce a local .deb containing Geant4 and datasets.
# Other Linux families can use --install.

G4_VERSION="latest"
PREFIX_BASE="/opt/geant4"
BUILD_ROOT="${HOME}/.cache/geant4-native-build"
_DETECTED_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 2)"
# Geant4 is memory-heavy to compile. Cap default parallelism to reduce GCC ICE/OOM risk.
if [[ "${_DETECTED_JOBS}" =~ ^[0-9]+$ && "${_DETECTED_JOBS}" -gt 4 ]]; then
  JOBS=4
else
  JOBS="${_DETECTED_JOBS}"
fi
MODE="install"              # install | deb | build-only
INSTALL_DEPS=1
INSTALL_DATA=1
DATA_SCOPE="required"       # required | all
ENABLE_QT=1
ENABLE_OPENGL=1
ENABLE_GDML=1
ENABLE_FREETYPE=1
ENABLE_HDF5=0
SANITIZER="none"            # none | asan-ubsan | tsan
BUILD_TYPE="RelWithDebInfo"
KEEP_STAGE=0
CLEAN_BUILD=0
COMPILER="default"          # default | gcc-N | clang | clang-N
PKG_NAME="geant4-native"
MAINTAINER="local <root@localhost>"
DATA_URL_BASE="https://cern.ch/geant4-data/datasets"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
fatal() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<USAGE
Usage:
  $0 [options]

Main options:
  --install                 Build and install under /opt/geant4/<version> [default]
  --deb                     Build a local Debian package (.deb); best on Mint/Ubuntu/Debian
  --build-only              Configure and compile only; do not install/package
  --version X.Y.Z           Build a specific Geant4 version, e.g. 11.4.2
  --latest                  Detect latest stable tag from GitHub [default]
  --prefix DIR              Base prefix [default: /opt/geant4]
                            Final install path is DIR/<version>
  --jobs N                  Parallel build jobs [default: min(CPU count, 4)]
  --build-root DIR          Working directory [default: ~/.cache/geant4-native-build]
  --clean-build             Remove this script's CMake build directory before configuring
  --compiler NAME           default, gcc-13, gcc-14, clang, clang-18, etc.

Features:
  --no-data                 Do not download/install Geant4 datasets
  --all-data                Also download optional datasets listed for Geant4 11.4.x
                            (G4TENDL, G4NUDEXLIB, G4URRPT)
  --no-qt                   Disable Qt UI/visualization
  --no-opengl               Disable OpenGL X11 visualization
  --no-gdml                 Disable GDML/Xerces support
  --hdf5                    Enable HDF5 support
  --sanitizers              Enable AddressSanitizer + UndefinedBehaviorSanitizer
  --tsan                    Enable ThreadSanitizer instead of ASan/UBSan
  --no-deps                 Do not install OS packages
  --keep-stage              Keep staging tree after .deb creation

Examples:
  $0 --deb --version 11.4.2
  $0 --deb --version 11.4.2 --jobs 2 --no-deps
  $0 --deb --version 11.4.2 --compiler clang --clean-build --jobs 4
  $0 --install --version 11.4.2 --prefix "${HOME}/opt/geant4"

Notes:
  - This script does not use Spack.
  - It installs system dependencies with the native package manager.
  - A .deb is native to Debian-family systems. On Fedora/openSUSE/Arch use --install.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) MODE="install" ;;
    --deb) MODE="deb" ;;
    --build-only) MODE="build-only" ;;
    --version) G4_VERSION="${2:?missing version}"; shift ;;
    --latest) G4_VERSION="latest" ;;
    --prefix) PREFIX_BASE="${2:?missing prefix}"; shift ;;
    --jobs|-j) JOBS="${2:?missing jobs}"; shift ;;
    --build-root) BUILD_ROOT="${2:?missing build root}"; shift ;;
    --clean-build) CLEAN_BUILD=1 ;;
    --compiler) COMPILER="${2:?missing compiler name}"; shift ;;
    --no-data) INSTALL_DATA=0 ;;
    --all-data) DATA_SCOPE="all" ;;
    --no-qt) ENABLE_QT=0 ;;
    --no-opengl) ENABLE_OPENGL=0 ;;
    --no-gdml) ENABLE_GDML=0 ;;
    --hdf5) ENABLE_HDF5=1 ;;
    --sanitizers) SANITIZER="asan-ubsan"; BUILD_TYPE="Debug" ;;
    --tsan) SANITIZER="tsan"; BUILD_TYPE="Debug" ;;
    --no-deps) INSTALL_DEPS=0 ;;
    --keep-stage) KEEP_STAGE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) fatal "unknown option: $1" ;;
  esac
  shift
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || fatal "required command not found: $1"; }
onoff() { [[ "$1" == "1" ]] && echo ON || echo OFF; }

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
else
  OS_ID="unknown"
  OS_LIKE=""
fi

is_debian_family() {
  [[ "$OS_ID" =~ ^(debian|ubuntu|linuxmint|pop|kali|zorin)$ ]] || [[ "$OS_LIKE" == *debian* ]] || [[ "$OS_LIKE" == *ubuntu* ]]
}

is_rhel_family() {
  [[ "$OS_ID" =~ ^(fedora|rhel|centos|rocky|almalinux|ol)$ ]] || [[ "$OS_LIKE" == *rhel* ]] || [[ "$OS_LIKE" == *fedora* ]]
}

install_deps_debian() {
  local pkgs=(
    ca-certificates curl wget git
    build-essential gcc g++ gfortran make patch
    cmake ninja-build pkg-config file python3
    tar gzip bzip2 xz-utils unzip
    libexpat1-dev zlib1g-dev libxerces-c-dev
    libcurl4-openssl-dev libssl-dev
    libfreetype6-dev
    libgl1-mesa-dev libglu1-mesa-dev
    libx11-dev libxmu-dev libxi-dev libxext-dev libxft-dev libxpm-dev
  )
  case "$COMPILER" in
    default|gcc|g++|gcc-13|g++-13) ;;
    gcc-[0-9]*|g++-[0-9]*)
      local gccver="${COMPILER#g++-}"; gccver="${gccver#gcc-}"
      pkgs+=("gcc-${gccver}" "g++-${gccver}") ;;
    clang|clang++|clang-[0-9]*|clang++-[0-9]*) pkgs+=(clang lld) ;;
    *) warn "Unknown compiler ${COMPILER}; not adding compiler-specific packages." ;;
  esac
  if [[ "$ENABLE_QT" == "1" ]]; then pkgs+=(qt6-base-dev qt6-tools-dev libqt6opengl6-dev); fi
  if [[ "$ENABLE_HDF5" == "1" ]]; then pkgs+=(libhdf5-dev); fi
  if [[ "$MODE" == "deb" ]]; then pkgs+=(dpkg-dev fakeroot); fi
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

install_deps_rhel() {
  local pm="dnf"; command -v dnf >/dev/null 2>&1 || pm="yum"
  local pkgs=(
    ca-certificates curl wget git
    gcc gcc-c++ gcc-gfortran make patch
    cmake ninja-build pkgconf-pkg-config file python3
    tar gzip bzip2 xz unzip
    expat-devel zlib-devel xerces-c-devel
    libcurl-devel openssl-devel freetype-devel
    mesa-libGL-devel mesa-libGLU-devel
    libX11-devel libXmu-devel libXi-devel libXext-devel libXft-devel libXpm-devel
  )
  [[ "$ENABLE_QT" == "1" ]] && pkgs+=(qt6-qtbase-devel qt6-qttools-devel)
  [[ "$ENABLE_HDF5" == "1" ]] && pkgs+=(hdf5-devel)
  sudo "$pm" install -y "${pkgs[@]}"
  [[ "$MODE" == "deb" ]] && warn "Requested --deb on non-Debian OS. Prefer --install."
}

install_deps_opensuse() {
  local pkgs=(
    ca-certificates curl wget git
    gcc gcc-c++ gcc-fortran make patch
    cmake ninja pkg-config file python3
    tar gzip bzip2 xz unzip
    libexpat-devel zlib-devel xerces-c-devel
    libcurl-devel libopenssl-devel freetype2-devel
    Mesa-libGL-devel Mesa-libGLU-devel
    libX11-devel libXmu-devel libXi-devel libXext-devel libXft-devel libXpm-devel
  )
  [[ "$ENABLE_QT" == "1" ]] && pkgs+=(qt6-base-devel qt6-tools-devel)
  [[ "$ENABLE_HDF5" == "1" ]] && pkgs+=(hdf5-devel)
  sudo zypper --non-interactive install "${pkgs[@]}"
}

install_deps_arch() {
  local pkgs=(
    base-devel ca-certificates curl wget git
    gcc-fortran cmake ninja pkgconf file python
    tar gzip bzip2 xz unzip
    expat zlib xerces-c curl openssl freetype2
    libglvnd glu libx11 libxmu libxi libxext libxft libxpm
  )
  [[ "$ENABLE_QT" == "1" ]] && pkgs+=(qt6-base qt6-tools)
  [[ "$ENABLE_HDF5" == "1" ]] && pkgs+=(hdf5)
  sudo pacman -Sy --needed --noconfirm "${pkgs[@]}"
}

install_deps() {
  [[ "$INSTALL_DEPS" != "1" ]] && { log "Skipping dependency installation (--no-deps)."; return; }
  log "Installing native system dependencies for: ${PRETTY_NAME:-$OS_ID}"
  if is_debian_family; then install_deps_debian
  elif is_rhel_family; then install_deps_rhel
  elif [[ "$OS_ID" =~ ^(opensuse|opensuse-leap|opensuse-tumbleweed|sles)$ ]] || [[ "$OS_LIKE" == *suse* ]]; then install_deps_opensuse
  elif [[ "$OS_ID" =~ ^(arch|manjaro|endeavouros)$ ]] || [[ "$OS_LIKE" == *arch* ]]; then install_deps_arch
  else fatal "Unsupported distribution auto-detection: ID=$OS_ID ID_LIKE=$OS_LIKE. Use --no-deps after installing dependencies manually."
  fi
}

resolve_compiler() {
  C_COMPILER=""; CXX_COMPILER=""; COMPILER_ID="default"
  case "$COMPILER" in
    default) return ;;
    gcc|g++) C_COMPILER="gcc"; CXX_COMPILER="g++"; COMPILER_ID="gcc" ;;
    gcc-[0-9]*|g++-[0-9]*) local v="${COMPILER#g++-}"; v="${v#gcc-}"; C_COMPILER="gcc-${v}"; CXX_COMPILER="g++-${v}"; COMPILER_ID="gcc-${v}" ;;
    clang|clang++) C_COMPILER="clang"; CXX_COMPILER="clang++"; COMPILER_ID="clang" ;;
    clang-[0-9]*|clang++-[0-9]*) local v="${COMPILER#clang++-}"; v="${v#clang-}"; C_COMPILER="clang-${v}"; CXX_COMPILER="clang++-${v}"; COMPILER_ID="clang-${v}" ;;
    *) fatal "unsupported --compiler '${COMPILER}'. Use default, gcc-13, gcc-14, clang, clang-18, etc." ;;
  esac
  need_cmd "$C_COMPILER"; need_cmd "$CXX_COMPILER"
}

check_toolchain() {
  need_cmd git; need_cmd curl; need_cmd cmake; need_cmd ninja
  resolve_compiler
  local cmv; cmv="$(cmake --version | awk 'NR==1{print $3}')"
  if [[ -n "${CXX_COMPILER:-}" ]]; then
    log "Toolchain: $(${CXX_COMPILER} --version | head -1); CMake ${cmv}; Ninja $(ninja --version)"
  else
    need_cmd g++
    local major; major="$(g++ -dumpfullversion -dumpversion | awk -F. '{print $1}')"
    [[ -n "$major" && "$major" -ge 11 ]] || fatal "g++ >= 11 required. Found: $(g++ --version | head -1)"
    log "Toolchain: $(g++ --version | head -1); CMake ${cmv}; Ninja $(ninja --version)"
  fi
}

detect_latest_version() {
  log "Detecting latest stable Geant4 tag from GitHub"
  local tag
  tag="$(git ls-remote --tags --refs https://github.com/Geant4/geant4.git 'refs/tags/v*' \
      | awk -F/ '{print $3}' | grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' | sed 's/^v//' | sort -V | tail -n 1)"
  [[ -n "$tag" ]] || fatal "could not detect latest Geant4 tag"
  G4_VERSION="$tag"
}

download_source() {
  local src_root="$BUILD_ROOT/src"
  mkdir -p "$src_root"
  local tarball="$src_root/geant4-v${G4_VERSION}.tar.gz"
  local url="https://github.com/Geant4/geant4/archive/refs/tags/v${G4_VERSION}.tar.gz"
  log "Downloading Geant4 ${G4_VERSION}: $url"
  curl -fL --retry 5 --retry-delay 5 -C - -o "$tarball" "$url"
  local top
  top="$(tar -tf "$tarball" | awk -F/ 'NR==1{print $1}')"
  [[ -n "$top" ]] || fatal "could not inspect source archive"
  rm -rf "${src_root:?}/${top:?}"
  tar -xzf "$tarball" -C "$src_root"
  SRC_DIR="$src_root/$top"
  [[ -f "$SRC_DIR/CMakeLists.txt" ]] || fatal "source extraction failed: $SRC_DIR"
}

configure_build() {
  INSTALL_PREFIX="${PREFIX_BASE%/}/${G4_VERSION}"
  local compiler_id="${COMPILER_ID:-default}"
  BUILD_DIR="$BUILD_ROOT/build/geant4-${G4_VERSION}-${BUILD_TYPE}-${SANITIZER}-${compiler_id}"
  if [[ "$CLEAN_BUILD" == "1" ]]; then log "Removing previous build directory: $BUILD_DIR"; rm -rf "$BUILD_DIR"; fi
  mkdir -p "$BUILD_DIR"

  local cflags="" cxxflags="" ldflags=""
  case "$SANITIZER" in
    none) ;;
    asan-ubsan) cflags="-O1 -g -fno-omit-frame-pointer -fno-common -fsanitize=address,undefined"; cxxflags="$cflags"; ldflags="-fsanitize=address,undefined" ;;
    tsan) cflags="-O1 -g -fno-omit-frame-pointer -fsanitize=thread"; cxxflags="$cflags"; ldflags="-fsanitize=thread" ;;
    *) fatal "unsupported sanitizer mode: $SANITIZER" ;;
  esac

  local cmake_args=(
    -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DCMAKE_CXX_STANDARD=17
    -DCMAKE_CXX_STANDARD_REQUIRED=ON
    -DBUILD_SHARED_LIBS=ON
    -DGEANT4_BUILD_MULTITHREADED=ON
    -DGEANT4_INSTALL_DATA=OFF
    -DGEANT4_INSTALL_DATADIR="$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data"
    -DGEANT4_USE_QT="$(onoff "$ENABLE_QT")"
    -DGEANT4_USE_OPENGL_X11="$(onoff "$ENABLE_OPENGL")"
    -DGEANT4_USE_GDML="$(onoff "$ENABLE_GDML")"
    -DGEANT4_USE_FREETYPE="$(onoff "$ENABLE_FREETYPE")"
    -DGEANT4_USE_HDF5="$(onoff "$ENABLE_HDF5")"
    -DGEANT4_USE_SYSTEM_EXPAT=ON
    -DGEANT4_USE_SYSTEM_ZLIB=ON
    -DCMAKE_INSTALL_RPATH="$INSTALL_PREFIX/lib;$INSTALL_PREFIX/lib64"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )
  if [[ -n "${C_COMPILER:-}" && -n "${CXX_COMPILER:-}" ]]; then
    cmake_args+=(-DCMAKE_C_COMPILER="$C_COMPILER" -DCMAKE_CXX_COMPILER="$CXX_COMPILER")
  fi
  if [[ "$SANITIZER" != "none" ]]; then
    cmake_args+=(-DCMAKE_C_FLAGS="$cflags" -DCMAKE_CXX_FLAGS="$cxxflags" -DCMAKE_EXE_LINKER_FLAGS="$ldflags" -DCMAKE_SHARED_LINKER_FLAGS="$ldflags")
  fi
  log "Configuring Geant4 ${G4_VERSION}"
  cmake "${cmake_args[@]}"
}

build_geant4() {
  log "Building Geant4 ${G4_VERSION} with ${JOBS} jobs"
  cmake --build "$BUILD_DIR" --parallel "$JOBS"
}

find_geant4_config_under() {
  local prefix_root="$1"
  find "$prefix_root" -type f -path '*/lib*/cmake/Geant4/Geant4Config.cmake' -print -quit 2>/dev/null || true
}

required_dataset_filenames_from_config() {
  local config_file="$1"
  [[ -f "$config_file" ]] || return 1
  grep -h 'Geant4_DATASET_DESCRIPTIONS' "$config_file" \
    | grep -Eo '[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.gz' \
    | sort -u
}

required_dataset_filenames_fallback() {
  case "$G4_VERSION" in
    11.4*) cat <<'EOF'
G4NDL.4.7.1.tar.gz
G4EMLOW.8.8.tar.gz
G4PhotonEvaporation.6.1.2.tar.gz
G4RadioactiveDecay.6.1.2.tar.gz
G4PARTICLEXS.4.2.tar.gz
G4PII.1.3.tar.gz
G4RealSurface.2.2.tar.gz
G4SAIDDATA.2.0.tar.gz
G4ABLA.3.3.tar.gz
G4INCL.1.3.tar.gz
G4ENSDFSTATE.3.0.tar.gz
G4CHANNELING.2.0.tar.gz
EOF
    ;;
    *) fatal "could not determine required Geant4 dataset list for version ${G4_VERSION}; rerun with --no-data or install datasets manually" ;;
  esac
}

optional_dataset_filenames() {
  case "$G4_VERSION" in
    11.4*) cat <<'EOF'
G4TENDL.1.4.tar.gz
G4NUDEXLIB.1.0.tar.gz
G4URRPT.1.1.tar.gz
EOF
    ;;
  esac
}

dataset_filenames() {
  local prefix_root="$1" config_file found
  config_file="$(find_geant4_config_under "$prefix_root")"
  found=""
  [[ -n "$config_file" ]] && found="$(required_dataset_filenames_from_config "$config_file" || true)"
  if [[ -n "$found" ]]; then printf '%s\n' "$found"; else warn "Could not parse dataset list from Geant4Config.cmake; using fallback list for Geant4 ${G4_VERSION}"; required_dataset_filenames_fallback; fi
  [[ "$DATA_SCOPE" == "all" ]] && optional_dataset_filenames
}

download_dataset_tarball() {
  local filename="$1" cache_dir="$BUILD_ROOT/data-tarballs" tarball url existing attempt
  mkdir -p "$cache_dir"
  tarball="$cache_dir/$filename"
  url="${DATA_URL_BASE%/}/$filename"
  if [[ ! -s "$tarball" && -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
    existing="$(find "$BUILD_DIR" -type f -name "$filename" -size +0c -print -quit 2>/dev/null || true)"
    [[ -n "$existing" ]] && { warn "Reusing partial/previous CMake download for $filename"; cp -f "$existing" "$tarball"; }
  fi
  for attempt in $(seq 1 20); do
    log "Downloading dataset $filename (attempt $attempt/20)" >&2
    if curl -fL --retry 20 --retry-delay 10 --retry-max-time 0 --retry-all-errors --connect-timeout 30 --speed-time 120 --speed-limit 1024 -C - -o "$tarball" "$url"; then
      if tar -tzf "$tarball" >/dev/null 2>&1; then printf '%s\n' "$tarball"; return 0; fi
      warn "Downloaded $filename is not a valid gzip tarball; retrying from scratch"; rm -f "$tarball"
    fi
    sleep $(( attempt < 10 ? attempt * 10 : 120 ))
  done
  fatal "failed to download valid dataset tarball: $url"
}

extract_dataset_tarball() {
  local tarball="$1" target_dir="$2" top
  top="$(tar -tzf "$tarball" | awk -F/ 'NR==1{print $1}')"
  [[ -n "$top" ]] || fatal "could not inspect dataset archive: $tarball"
  if mkdir -p "$target_dir" 2>/dev/null && [[ -w "$target_dir" ]]; then
    rm -rf "${target_dir:?}/${top:?}"
    tar -xzf "$tarball" -C "${target_dir:?}"
  else
    sudo mkdir -p "$target_dir"; sudo rm -rf "${target_dir:?}/${top:?}"; sudo tar -xzf "$tarball" -C "${target_dir:?}"
  fi
}

install_datasets_to() {
  local prefix_root="$1" target_dir="$2" filename tarball
  [[ "$INSTALL_DATA" == "1" ]] || return 0
  log "Installing Geant4 datasets to $target_dir"
  while IFS= read -r filename; do
    [[ -n "$filename" ]] || continue
    tarball="$(download_dataset_tarball "$filename")"
    extract_dataset_tarball "$tarball" "$target_dir"
  done < <(dataset_filenames "$prefix_root" | sort -u)
}

latest_dataset_dir() {
  local lookup_dir="$1" pattern="$2"
  find "$lookup_dir" -maxdepth 1 -type d -name "$pattern" -printf '%f\n' 2>/dev/null | sort -V | tail -n 1
}

write_dataset_env_file() {
  local lookup_dir="$1" final_data_dir="$2" outfile="$3" tmp d
  if [[ "$outfile" == /opt/* || "$outfile" == /usr/* || "$outfile" == /usr/local/* || "$outfile" == /etc/* ]]; then tmp="$(mktemp)"; else mkdir -p "$(dirname "$outfile")"; tmp="${outfile}.tmp"; fi
  cat > "$tmp" <<PROFILE
# Geant4 ${G4_VERSION} datasets
# Generated by install_geant4_native.sh
export GEANT4_DATA_DIR="${final_data_dir}"
export GEANT4_INSTALL_DATADIR="${final_data_dir}"
PROFILE
  add_env() {
    local envvar="$1" pattern="$2"
    d="$(latest_dataset_dir "$lookup_dir" "$pattern")"
    [[ -n "$d" ]] && printf 'export %s="%s/%s"\n' "$envvar" "$final_data_dir" "$d" >> "$tmp"
  }
  add_env G4NEUTRONHPDATA 'G4NDL*'
  add_env G4LEDATA 'G4EMLOW*'
  add_env G4LEVELGAMMADATA 'PhotonEvaporation*'
  add_env G4LEVELGAMMADATA 'G4PhotonEvaporation*'
  add_env G4RADIOACTIVEDATA 'RadioactiveDecay*'
  add_env G4RADIOACTIVEDATA 'G4RadioactiveDecay*'
  add_env G4PARTICLEXSDATA 'G4PARTICLEXS*'
  add_env G4PIIDATA 'G4PII*'
  add_env G4REALSURFACEDATA 'RealSurface*'
  add_env G4REALSURFACEDATA 'G4RealSurface*'
  add_env G4SAIDXSDATA 'G4SAIDDATA*'
  add_env G4ABLADATA 'G4ABLA*'
  add_env G4INCLDATA 'G4INCL*'
  add_env G4ENSDFSTATEDATA 'G4ENSDFSTATE*'
  add_env G4CHANNELINGDATA 'G4CHANNELING*'
  add_env G4PARTICLEHPDATA 'G4TENDL*'
  add_env G4NUDEXLIBDATA 'G4NUDEXLIB*'
  add_env G4URRPTDATA 'G4URRPT*'
  if [[ "$outfile" == /opt/* || "$outfile" == /usr/* || "$outfile" == /usr/local/* || "$outfile" == /etc/* ]]; then sudo mv "$tmp" "$outfile"; sudo chmod 0644 "$outfile"; else mv "$tmp" "$outfile"; chmod 0644 "$outfile"; fi
}

install_direct() {
  log "Installing to $INSTALL_PREFIX"
  if [[ "$INSTALL_PREFIX" == /opt/* || "$INSTALL_PREFIX" == /usr/* || "$INSTALL_PREFIX" == /usr/local/* ]]; then
    sudo cmake --install "$BUILD_DIR"
    install_datasets_to "$INSTALL_PREFIX" "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data"
    write_dataset_env_file "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "/etc/profile.d/geant4-${G4_VERSION}-datasets.sh"
    sudo tee "/etc/profile.d/geant4-${G4_VERSION}.sh" >/dev/null <<PROFILE
# Geant4 ${G4_VERSION}
if [ -r "${INSTALL_PREFIX}/bin/geant4.sh" ]; then
  . "${INSTALL_PREFIX}/bin/geant4.sh"
fi
if [ -r "/etc/profile.d/geant4-${G4_VERSION}-datasets.sh" ]; then
  . "/etc/profile.d/geant4-${G4_VERSION}-datasets.sh"
fi
PROFILE
    if [[ -d "$INSTALL_PREFIX/lib" || -d "$INSTALL_PREFIX/lib64" ]]; then
      { [[ -d "$INSTALL_PREFIX/lib" ]] && echo "$INSTALL_PREFIX/lib"; [[ -d "$INSTALL_PREFIX/lib64" ]] && echo "$INSTALL_PREFIX/lib64"; } | sudo tee "/etc/ld.so.conf.d/geant4-${G4_VERSION}.conf" >/dev/null
      sudo ldconfig
    fi
  else
    cmake --install "$BUILD_DIR"
    install_datasets_to "$INSTALL_PREFIX" "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data"
    write_dataset_env_file "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "$INSTALL_PREFIX/bin/geant4-datasets.sh"
    log "Add to shell startup: source ${INSTALL_PREFIX}/bin/geant4.sh; source ${INSTALL_PREFIX}/bin/geant4-datasets.sh"
  fi
}

deb_depends() {
  local deps=(bash libc6 libstdc++6 libgcc-s1 libexpat1 zlib1g libxerces-c-dev libcurl4-openssl-dev libssl-dev libfreetype6 libgl1 libglu1-mesa libx11-6 libxmu6 libxi6 libxext6)
  [[ "$ENABLE_QT" == "1" ]] && deps+=(qt6-base-dev libqt6opengl6-dev)
  [[ "$ENABLE_HDF5" == "1" ]] && deps+=(libhdf5-dev)
  local IFS=', '; echo "${deps[*]}"
}

make_deb() {
  is_debian_family || warn ".deb requested outside Debian-family OS. Result may not install cleanly."
  need_cmd dpkg-deb; need_cmd dpkg
  local arch debver outdir stage pkgroot debfile installed_size
  arch="$(dpkg --print-architecture)"
  debver="${G4_VERSION}-1"
  outdir="$BUILD_ROOT/packages"
  stage="$BUILD_ROOT/stage/${PKG_NAME}-${G4_VERSION}"
  pkgroot="$stage/root"
  rm -rf "$stage"; mkdir -p "$pkgroot" "$outdir" "$pkgroot/DEBIAN"
  log "Staging installation for .deb under $pkgroot"
  DESTDIR="$pkgroot" cmake --install "$BUILD_DIR"
  install_datasets_to "$pkgroot$INSTALL_PREFIX" "$pkgroot$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data"
  mkdir -p "$pkgroot/etc/profile.d" "$pkgroot/etc/ld.so.conf.d"
  cat > "$pkgroot/etc/profile.d/geant4-${G4_VERSION}.sh" <<PROFILE
# Geant4 ${G4_VERSION}
if [ -r "${INSTALL_PREFIX}/bin/geant4.sh" ]; then
  . "${INSTALL_PREFIX}/bin/geant4.sh"
fi
if [ -r "/etc/profile.d/geant4-${G4_VERSION}-datasets.sh" ]; then
  . "/etc/profile.d/geant4-${G4_VERSION}-datasets.sh"
fi
PROFILE
  write_dataset_env_file "$pkgroot$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "$INSTALL_PREFIX/share/Geant4-${G4_VERSION}/data" "$pkgroot/etc/profile.d/geant4-${G4_VERSION}-datasets.sh"
  { echo "${INSTALL_PREFIX}/lib"; echo "${INSTALL_PREFIX}/lib64"; } > "$pkgroot/etc/ld.so.conf.d/geant4-${G4_VERSION}.conf"
  cat > "$pkgroot/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
command -v ldconfig >/dev/null 2>&1 && ldconfig
exit 0
POSTINST
  cat > "$pkgroot/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
command -v ldconfig >/dev/null 2>&1 && ldconfig
exit 0
POSTRM
  chmod 0755 "$pkgroot/DEBIAN/postinst" "$pkgroot/DEBIAN/postrm"
  installed_size="$(du -sk "$pkgroot" | awk '{print $1}')"
  cat > "$pkgroot/DEBIAN/control" <<CONTROL
Package: ${PKG_NAME}
Version: ${debver}
Section: science
Priority: optional
Architecture: ${arch}
Maintainer: ${MAINTAINER}
Installed-Size: ${installed_size}
Depends: $(deb_depends)
Description: Geant4 particle transport toolkit built from source
 Geant4 installed under ${INSTALL_PREFIX}.
 This local package was generated by install_geant4_native.sh without Spack.
 It may include Geant4 datasets downloaded with a resumable curl-based downloader.
CONTROL
  find "$pkgroot" -type d -exec chmod 0755 {} +
  debfile="$outdir/${PKG_NAME}_${debver}_${arch}.deb"
  log "Building .deb: $debfile"
  dpkg-deb --build --root-owner-group "$pkgroot" "$debfile"
  log "Created: $debfile"
  log "Install it with: sudo apt install '$debfile'"
  [[ "$KEEP_STAGE" != "1" ]] && rm -rf "$stage"
}

print_summary() {
  cat <<SUMMARY

Done.
Version:        ${G4_VERSION}
Install prefix: ${INSTALL_PREFIX}
Build dir:      ${BUILD_DIR}
Compiler:       ${COMPILER}
Mode:           ${MODE}
Qt:             $(onoff "$ENABLE_QT")
OpenGL X11:     $(onoff "$ENABLE_OPENGL")
GDML:           $(onoff "$ENABLE_GDML")
Freetype:       $(onoff "$ENABLE_FREETYPE")
HDF5:           $(onoff "$ENABLE_HDF5")
Data sets:      $(onoff "$INSTALL_DATA")
Data scope:     ${DATA_SCOPE}
Sanitizer:      ${SANITIZER}

To use after direct install or after installing the .deb:
  source ${INSTALL_PREFIX}/bin/geant4.sh
  [ -r /etc/profile.d/geant4-${G4_VERSION}-datasets.sh ] && source /etc/profile.d/geant4-${G4_VERSION}-datasets.sh
  geant4-config --version

To test with example B1:
  mkdir -p ~/geant4-test && cp -r ${INSTALL_PREFIX}/share/Geant4/examples/basic/B1 ~/geant4-test/
  cmake -S ~/geant4-test/B1 -B ~/geant4-test/B1/build -DGeant4_DIR=${INSTALL_PREFIX}/lib/cmake/Geant4
  cmake --build ~/geant4-test/B1/build --parallel 4
  cd ~/geant4-test/B1/build && ./exampleB1 ../run1.mac
SUMMARY
}

main() {
  install_deps
  check_toolchain
  [[ "$G4_VERSION" == "latest" ]] && detect_latest_version
  download_source
  configure_build
  build_geant4
  case "$MODE" in
    install) install_direct ;;
    deb) make_deb ;;
    build-only) log "Build-only mode complete." ;;
    *) fatal "invalid mode: $MODE" ;;
  esac
  print_summary
}

main "$@"
