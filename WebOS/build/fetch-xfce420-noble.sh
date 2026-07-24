#!/usr/bin/env bash

set -euo pipefail

readonly DESTINATION="${1:?Usage: fetch-xfce420-noble.sh DESTINATION}"
readonly BASE_URL="https://ppa.launchpadcontent.net/xubuntu-dev/staging/ubuntu"
readonly PACKAGES_DIR="${DESTINATION}/native-packages/ubuntu-24.04"
readonly SOURCES_DIR="${DESTINATION}/licenses/sources/xubuntu-xfce-4.20-noble"

download_verified() {
	local sha256="${1}" relative_path="${2}" output_dir="${3}"
	local output_file="${output_dir}/${relative_path##*/}"

	curl --fail --location --retry 3 --silent --show-error \
		"${BASE_URL}/${relative_path}" --output "${output_file}"
	printf '%s  %s\n' "${sha256}" "${output_file}" | sha256sum --check -
}

install -d -m 0755 "${PACKAGES_DIR}" "${SOURCES_DIR}"

# Noble-native binaries from the Xubuntu Developers QA Staging archive. These
# are embedded only in the Ubuntu 24.04 payload; the target VM needs no PPA.
while read -r sha256 relative_path; do
	download_verified "${sha256}" "${relative_path}" "${PACKAGES_DIR}"
done <<'PACKAGES'
cda341a0ad9802eee83d46d17038d7eaaa248b72e050cbc0e5107de5030f62d9 pool/main/libx/libxfce4windowing/libxfce4windowing-common_4.20.2-1~bpo24.04_all.deb
bcca8688f1739a6616cacc917d01cee5fafb03b4ffd24f75a3d0c03459c72709 pool/main/libx/libxfce4windowing/libxfce4windowing-0-0_4.20.2-1~bpo24.04_amd64.deb
9bb1946bdf24eff4ec7f1b5157f29995308c0fd5db177e7d61cbda64b1fdf2b1 pool/main/libx/libxfce4ui/libxfce4ui-2-0_4.20.0-1~bpo24.04_amd64.deb
b9f0d036f1c80935ab134f0acff5c072ef7151c1fc1707ec487c446d80ce1649 pool/main/libx/libxfce4ui/libxfce4ui-common_4.20.0-1~bpo24.04_all.deb
f7b4054133212da4707117da4bcb45a5e6ec51f545dccf18790f32483b9aac0b pool/main/x/xfce4-panel/libxfce4panel-2.0-4_4.20.3-1~bpo24.04_amd64.deb
b22c529879d8512537c4c8ffa8d7fcd76881a4425386944a1130281574c305ad pool/main/x/xfce4-panel/xfce4-panel_4.20.3-1~bpo24.04_amd64.deb
8e5b20bb4968dbdbd9dfce19f5e351b3cbd9fbf3c30843bfe1e4a749ffe6397c pool/main/x/xfce4-settings/xfce4-helpers_4.20.1-1ubuntu1~bpo24.04_amd64.deb
4ba8469b8ef6e86ec5c1e3903e872b2621a529c29cbdd1ea6c226b25957565b5 pool/main/x/xfce4-settings/xfce4-settings_4.20.1-1ubuntu1~bpo24.04_amd64.deb
4263c8570e540335a4da7956e2c84bb940ee12fe25d7d1cae548b8f2a847f21c pool/main/x/xfce4-whiskermenu-plugin/xfce4-whiskermenu-plugin_2.9.2-1~bpo24.04_amd64.deb
92ee10ce4f107783b8fa822e26e56156594703ecbd082ce8f24087da8d3cafc6 pool/main/x/xfconf/libxfconf-0-3_4.20.0-1~bpo24.04_amd64.deb
4fc78e4d3e35d11142e29e4cef5f313c1e414ad2cb9328a456f952db86bb55e8 pool/main/x/xfconf/xfconf_4.20.0-1~bpo24.04_amd64.deb
e2baf3923c977bb600870dbe91eb4dfa884f2f2d0dec9143b5bab9f441df2b06 pool/main/x/xfdesktop4/xfdesktop4-data_4.20.1-1ubuntu1~bpo24.04_all.deb
03e6db9367a3539be5e1087c1ee717419d604f055e6087dda035a39d83f29d91 pool/main/x/xfdesktop4/xfdesktop4_4.20.1-1ubuntu1~bpo24.04_amd64.deb
PACKAGES

# Corresponding source packages accompany the redistributed binaries.
while read -r sha256 relative_path; do
	download_verified "${sha256}" "${relative_path}" "${SOURCES_DIR}"
done <<'SOURCES'
0b9b95aee8b868a2953920c2feafc026672ad19584976f19e89119e93ab1abc8 pool/main/libx/libxfce4windowing/libxfce4windowing_4.20.2.orig.tar.bz2
95d326db4e6aa56ccace9c7d1a218fae1d07f8242bdea10bea9ed56c182dad16 pool/main/libx/libxfce4windowing/libxfce4windowing_4.20.2-1~bpo24.04.debian.tar.xz
7da902ed1ed9898ec75a4d353bc23e472e3e9391b6d4bf719c737df3c788782a pool/main/libx/libxfce4windowing/libxfce4windowing_4.20.2-1~bpo24.04.dsc
75e8996984f20375aadecd5c16f5147c211ed0bd26d7861ab0257561eb76eaee pool/main/libx/libxfce4ui/libxfce4ui_4.20.0.orig.tar.bz2
b6692e00444b6fce2be80cd7d3aa6bea294c5926e6869d3fea09eb031687f85f pool/main/libx/libxfce4ui/libxfce4ui_4.20.0-1~bpo24.04.debian.tar.xz
1f83803c195ad3e46bdbe8cc697af95f97421c0bf52010c7f639e1b62aefb9c7 pool/main/libx/libxfce4ui/libxfce4ui_4.20.0-1~bpo24.04.dsc
4006dddf465a4ae02e14355941458c718f6da0896eae68435c9fd24fcd89b6b8 pool/main/x/xfce4-panel/xfce4-panel_4.20.3.orig.tar.bz2
dafb8db3c1297d0b71552bba5f4282d39f4b0d4c88ea1a3a08c6ae163aac38f3 pool/main/x/xfce4-panel/xfce4-panel_4.20.3-1~bpo24.04.debian.tar.xz
19eeb553a0d679e9c13f39ffb44cf1bef2160f8c3274e18d4ce4bbc706f329cf pool/main/x/xfce4-panel/xfce4-panel_4.20.3-1~bpo24.04.dsc
fd0d602853ea75d94024e5baae2d2bf5ca8f8aa4dad7bfd5d08f9ff8afee77b2 pool/main/x/xfce4-settings/xfce4-settings_4.20.1.orig.tar.bz2
e76fa26dea0fbb851bde951cd50643089799e8a551b9e7218971477f4968b8a4 pool/main/x/xfce4-settings/xfce4-settings_4.20.1-1ubuntu1~bpo24.04.debian.tar.xz
7d4b8251556e04f7f91b0c982b33e6cc3fef3e6e807488643bb3ec80cc30880e pool/main/x/xfce4-settings/xfce4-settings_4.20.1-1ubuntu1~bpo24.04.dsc
e2f28c066709bdcfe30236307026a562ec9aed790f9929a4e40aa411a5c7e3de pool/main/x/xfce4-whiskermenu-plugin/xfce4-whiskermenu-plugin_2.9.2.orig.tar.bz2
52b6a07848fc3b1d23d76593d87e7240252f0349b6177cbde9f48f59fb6df1fd pool/main/x/xfce4-whiskermenu-plugin/xfce4-whiskermenu-plugin_2.9.2-1~bpo24.04.debian.tar.xz
f3fe36248ffe3f9cb4e07f36bdd10b18ae61ee835ce57f35003a8c9f1e11665a pool/main/x/xfce4-whiskermenu-plugin/xfce4-whiskermenu-plugin_2.9.2-1~bpo24.04.dsc
8bc43c60f1716b13cf35fc899e2a36ea9c6cdc3478a8f051220eef0f53567efd pool/main/x/xfconf/xfconf_4.20.0.orig.tar.bz2
8edb3dbe6117e56404ff6d1923c008225d3dede00c37a01a48352d9cae3c7ba5 pool/main/x/xfconf/xfconf_4.20.0-1~bpo24.04.debian.tar.xz
0962f81fbe09b416f71866117989f999ffa9851c294b2f8bad89023f4b93c608 pool/main/x/xfconf/xfconf_4.20.0-1~bpo24.04.dsc
acccde849265bbf4093925ba847977b7abf70bb2977e4f78216570e887c157b8 pool/main/x/xfdesktop4/xfdesktop4_4.20.1.orig.tar.bz2
12d1f1adb54fac532e0244a838dedbd80434619aeb4a02adf54226a81db9eddd pool/main/x/xfdesktop4/xfdesktop4_4.20.1-1ubuntu1~bpo24.04.debian.tar.xz
f98a8a77be998784f08a5ee979107c2e5e2973eaf8bd6cdcb853b99e7df125a0 pool/main/x/xfdesktop4/xfdesktop4_4.20.1-1ubuntu1~bpo24.04.dsc
SOURCES
