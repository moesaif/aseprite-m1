#!/usr/bin/env bash

set -e

target_osx=$(sw_vers -productVersion)
project_dir=/Users/moesaif/development/aseprite
skia_dir=/Users/moesaif/development/skia  # Fixed path typo
arch="$(uname -m)"

bundle_trial_url=https://www.aseprite.org/downloads/trial/Aseprite-v1.2.40-trial-macOS.dmg

install_update_deps() {
  macos_deps
  dep_skia
  dep_aseprite
}

macos_deps() {
  echo "Updating Homebrew and installing dependencies..."
  brew update
  brew install cmake ninja
}

dep_skia() {
  echo "Handling Skia dependency..."

  rm -rf $skia_dir
  mkdir -p $skia_dir
  cd $skia_dir

  latest_url=$(curl -s https://api.github.com/repos/aseprite/skia/releases/latest | grep "browser_download_url.*-macOS.*${arch}.zip" | cut -d : -f 2,3 | tr -d \")
  
  if [ -z "$latest_url" ]; then
    echo "Error: Failed to get the latest Skia URL."
    exit 1
  fi
  
  name=$(basename "${latest_url}")

  if [ ! -f "${name}" ]; then
    echo "Downloading ${name}..."
    curl -LO ${latest_url}
  fi

  unzip "${name}"
}

dep_aseprite() {
  echo "Handling Aseprite source..."
  if [ ! -d $project_dir ]; then
    git clone --recursive https://github.com/aseprite/aseprite.git $project_dir
    if [ ! -d "${project_dir}/.git" ]; then
      echo "Error: Failed to clone the Aseprite repository."
      exit 1
    fi
  fi

  cd $project_dir
  git pull || { echo "Error: Failed to update Aseprite source."; exit 1; }
}

build_bin() {
  echo "Building Aseprite..."
  cd $project_dir
  mkdir -p build
  cd build

  cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_OSX_ARCHITECTURES="${arch}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${target_osx}" \
    -DCMAKE_MACOSX_RPATH=ON \
    -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="${skia_dir}" \
    -DSKIA_LIBRARY_DIR="${skia_dir}/out/Release-${arch}" \
    -DSKIA_LIBRARY="${skia_dir}/out/Release-${arch}/libskia.a" \
    -DPNG_ARM_NEON:STRING=on \
    -G Ninja .. || { echo "Error: Failed to configure build."; exit 1; }

  ninja aseprite || { echo "Error: Failed to build Aseprite."; exit 1; }
}

package_app() {
  echo "Packaging Aseprite..."
  mkdir -p "${project_dir}/bundle"
  cd "${project_dir}/bundle"

  name=$(basename "${bundle_trial_url}")
  
  if [ ! -f "${name}" ]; then
    echo "Downloading bundle assets..."
    curl -LO "${bundle_trial_url}"
  fi

  mkdir -p mount
  hdiutil attach -quiet -nobrowse -noverify -noautoopen -mountpoint mount "${name}" || { echo "Error: Failed to mount image."; exit 1; }
  cp -r mount/Aseprite.app .
  hdiutil detach -quiet mount || { echo "Error: Failed to detach image."; exit 1; }

  rm -rf Aseprite.app/Contents/MacOS/aseprite
  rm -rf Aseprite.app/Contents/Resources/data
  cp -r "${project_dir}/build/bin/aseprite" Aseprite.app/Contents/MacOS/aseprite
  cp -r "${project_dir}/build/bin/data" Aseprite.app/Contents/Resources/data
}

install_app() {
  echo "Installing Aseprite to Applications..."
  sudo cp -r "${project_dir}/bundle/Aseprite.app" /Applications/
}

install_update_deps
build_bin
package_app
install_app

echo "Done!"
