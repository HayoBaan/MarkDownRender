#!/usr/bin/env bash

# install.sh — install mdrender as described by install.manifest
#
# Usage:
#   install.sh --help|-h
#   install.sh [option...]
#
# Options:
#   --symlink|-s     Link the files instead of copying them.
#   --force|-f       Replace existing files that differ.
#   --target|-t DIR  Target root for $TARGET (default: your home directory).
#   --dry-run|-n     Show what would be done, without changing anything.

# Each line of install.manifest holds a source in this repository and a
# destination directory. This script only copies or links the files.
#
# Sources and destinations follow these rules:
#   - A directory with a trailing slash installs its contents.
#   - A directory without one installs the directory itself.
#   - A glob pattern installs the files it matches.
#   - A destination may use ~, $TARGET (the target root) and environment
#     variables, also as ${NAME:-default}. The default is used as written,
#     except for a leading ~.
#
# By default the files are copied. With --symlink they are linked instead,
# so later changes in this repository take effect without reinstalling.
# Running it again switches between the two: a link to this repository and
# an identical copy replace each other freely. Any other existing file is
# only replaced with --force.
#
# All manifest lines and sources are checked before anything is installed.

set -euo pipefail

readonly PROGRAM="$(basename "$0")"
readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MANIFEST="install.manifest"

# Prints the header comment of this script as its help
help() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "$0"
}

# Prints the Usage part of the header comment
usage() {
  sed -n '/^# Usage:/,/^#$/s/^# \{0,1\}//p' "$0"
}

# Prints an error message and exits.
die() {
  echo "${PROGRAM}: $*" >&2
  exit 1
}

symlink="false"
force="false"
dry_run="false"
target_root="${HOME}"

# Process command-line options
case ${1:-} in
  --help|-h) help; exit 0 ;;
esac
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s | --symlink) symlink="true"; shift ;;
    -f | --force) force="true"; shift ;;
    -t | --target) target_root="${2:?missing directory}"; shift 2 ;;
    -n | --dry-run) dry_run="true"; shift ;;
    *) echo "${PROGRAM}: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -d "${target_root}" ]] || die "not a directory: ${target_root}"
target_root="$(cd "${target_root}" && pwd)"
cd "${REPO_DIR}"
[[ -f "${MANIFEST}" ]] || die "${MANIFEST} not found in ${REPO_DIR}"

# The planned installs: the source file, relative to this repository, and
# the installed path, at the same index.
plan_sources=()
plan_targets=()
errors=0

# Prints an error about the manifest and remembers that one occurred.
manifest_error() {
  echo "${PROGRAM}: $*" >&2
  errors=1
}

# Prints a manifest destination with ~, $TARGET and environment variables
# expanded. ${NAME:-default} uses the default when NAME is unset or empty.
# Commands are not expanded. Fails when a variable without a default is unset.
expand_destination() {
  local rest="$1" result="" name value
  local pattern='^([^$]*)\$(\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}|([A-Za-z_][A-Za-z0-9_]*))(.*)$'
  while [[ "${rest}" =~ ${pattern} ]]; do
    result+="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[3]:-${BASH_REMATCH[6]}}"
    if [[ "${name}" == "TARGET" ]]; then
      value="${target_root}"
    else
      value="${!name:-}"
    fi
    if [[ -z "${value}" ]]; then
      if [[ -z "${BASH_REMATCH[4]}" ]]; then
        echo "variable not set: ${name}"
        return 1
      fi
      value="${BASH_REMATCH[5]}"
    fi
    result+="${value}"
    rest="${BASH_REMATCH[7]}"
  done
  result+="${rest}"
  if [[ "${result}" == "~" || "${result}" == "~/"* ]]; then
    result="${HOME}${result#\~}"
  fi
  while [[ "${result}" == ?*/ ]]; do
    result="${result%/}"
  done
  echo "${result}"
}

# Adds the files that one manifest source installs to the plan.
plan_source() {
  local source="$1" dest="$2" where="$3" match file prefix
  local matches=()
  if [[ "${source}" == *[*?[]* ]]; then
    shopt -s nullglob
    # Unquoted on purpose: the pattern must be expanded.
    matches=(${source})
    shopt -u nullglob
  elif [[ -e "${source}" ]]; then
    matches=("${source}")
  fi
  if [[ ${#matches[@]} -eq 0 ]]; then
    manifest_error "${where}: nothing to install for ${source}: no such file or directory"
    return
  fi
  for match in "${matches[@]}"; do
    if [[ -d "${match}" ]]; then
      prefix=""
      [[ "${match}" == */ ]] || prefix="$(basename "${match}")/"
      while IFS= read -r file; do
        plan_sources+=("${file}")
        plan_targets+=("${dest}/${prefix}${file#"${match%/}"/}")
      done < <(find "${match%/}" -type f | sort)
    else
      plan_sources+=("${match}")
      plan_targets+=("${dest}/$(basename "${match}")")
    fi
  done
}

line_number=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  line_number=$((line_number + 1))
  [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
  where="${MANIFEST} line ${line_number}"
  read -r source dest extra <<<"${line}"
  if [[ -z "${dest:-}" || -n "${extra:-}" ]]; then
    manifest_error "${where}: expected a source and a destination"
    continue
  fi
  if [[ "${source}" == /* || "/${source}/" == */../* ]]; then
    manifest_error "${where}: source ${source} must be inside the distro"
    continue
  fi
  if ! dest_dir="$(expand_destination "${dest}")"; then
    manifest_error "${where}: ${dest_dir}"
    continue
  fi
  if [[ "${dest_dir}" != /* ]]; then
    manifest_error "${where}: destination ${dest_dir} is not an absolute path"
    continue
  fi
  plan_source "${source}" "${dest_dir}" "${where}"
done <"${MANIFEST}"

[[ "${errors}" -eq 0 ]] || exit 1
# Checked separately, because bash 3.2 treats an empty array as unset.
if [[ ${#plan_sources[@]} -eq 0 ]]; then
  echo "${PROGRAM}: ${MANIFEST} lists nothing to install"
  exit 0
fi

# Runs a command, or only prints it in dry-run mode.
run() {
  if [[ "${dry_run}" == "true" ]]; then
    echo "would run: $*"
  else
    "$@"
  fi
}

status=0
for index in "${!plan_sources[@]}"; do
  name="${plan_sources[index]}"
  source="${REPO_DIR}/${name}"
  target="${plan_targets[index]}"

  linked="false"
  if [[ -L "${target}" && "$(readlink "${target}")" == "${source}" ]]; then
    linked="true"
  fi
  if [[ "${linked}" == "true" && "${symlink}" == "true" ]]; then
    echo "${name}: already linked"
    continue
  fi
  identical="false"
  if [[ -f "${target}" && ! -L "${target}" ]] && cmp -s "${source}" "${target}"; then
    identical="true"
  fi
  if [[ "${identical}" == "true" && "${symlink}" == "false" ]]; then
    echo "${name}: already up to date"
    continue
  fi
  # A link to this repository and an identical copy can safely replace each
  # other, anything else needs --force.
  if [[ -e "${target}" || -L "${target}" ]] \
    && [[ "${identical}" == "false" && "${linked}" == "false" && "${force}" == "false" ]]; then
    echo "${name}: ${target} exists and differs, skipped (use --force to replace it)" >&2
    status=1
    continue
  fi

  done_prefix=""
  [[ "${dry_run}" == "true" ]] && done_prefix="would be "
  run mkdir -p "$(dirname "${target}")"
  if [[ "${symlink}" == "true" ]]; then
    run ln -sfn "${source}" "${target}"
    echo "${name}: ${done_prefix}linked to ${target}"
  else
    run rm -f "${target}"
    run cp "${source}" "${target}"
    echo "${name}: ${done_prefix}copied to ${target}"
  fi
done

exit "${status}"
