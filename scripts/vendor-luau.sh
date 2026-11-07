#!/usr/bin/env bash
# Vendors the parts of Luau the app embeds (no JIT, no type checker) into the
# CLuau target. Pinned by version and checksum: bump both to update.
set -euo pipefail

version="0.745"
sha256="53c22773bace6cabbabaead576fbc08d11a0317fce11a3dbf9d027dda6849248"

root="$(cd "$(dirname "$0")/.." && pwd)"
target="$root/Packages/MoonKit/Sources/CLuau"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL "https://github.com/luau-lang/luau/archive/refs/tags/$version.tar.gz" -o "$work/luau.tgz"
echo "$sha256  $work/luau.tgz" | shasum -a 256 -c - >/dev/null
tar xzf "$work/luau.tgz" -C "$work"
source="$work/luau-$version"

rm -rf "$target/luau"
mkdir -p "$target/luau"
for part in Ast Bytecode Common Compiler VM; do
    cp -R "$source/$part" "$target/luau/$part"
done
cp "$source/LICENSE.txt" "$source/lua_LICENSE.txt" "$target/luau/"

# Swift reads the VM's C API, so its headers are this target's public ones.
mv "$target"/luau/VM/include/*.h "$target/include/"
rmdir "$target/luau/VM/include"
echo "$version" > "$target/luau/VERSION"
echo "Vendored Luau $version"
