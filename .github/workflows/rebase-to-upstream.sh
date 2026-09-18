#!/bin/bash
#
# Rebase "master" and any branch starting with "tracking-" to latest Gentoo upstream.
#
# The fork / tracking repository is expected to reside in sub directory "gentoo".
#
# Rebasing will be validated in a temporary copy before the "gentoo" repo sub-directory is rebased.
# This way, the original repo remains clean (no conflicts, intermediate state etc.) if the rebase fails.
#
# Note that the "push" action is required to be run from the "gentoo" sub-directory since the checkout github
#  action will only authenticate pushes from that directory.
# Hence we cannot push from the temporary validation sub-directory.

set -euo pipefail

function announce() {
  echo "----------"
  echo "    ${@}"
  echo "----------"
}
# --

function rebase_branch() {
  local branch_name="$1"
  local wd="$2"

  echo "======> Checkout + update"
  set +e # Don't abort if one of the branches has issues
  git -C "${wd}" checkout --track "origin/${branch_name}" || return 1
  git -C "${wd}" pull --rebase || return 1

  echo "======> Rebase"
  git -C "${wd}" rebase upstream/master || return 1

  git -C "${wd}" status || return 1
  return 0
}
# --

announce "Setting up gut and fetching Gentoo upstream"
git -C gentoo config user.name "github-actions[bot]"
git -C gentoo config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C gentoo remote add upstream https://github.com/gentoo/gentoo.git
git -C gentoo fetch upstream --depth 10000 # fetch a reasonable depth; this script should run every 2 hours

announce "Fetching our fork's branches"
git -C gentoo remote set-branches origin '*'
git -C gentoo fetch origin -v --depth 100
git -C gentoo branch -r \
  | sed -n 's,^[[:space:]]*origin/\(master\|tracking-\),\1,p' \
  | uniq >branches.txt

announce "Checking for eligible branches"
readarray branches < branches.txt
echo " Found ${#branches[@]} eligible branches:"
printf "   %s" "${branches[@]}"

failed_branches=()
validate_dir="branch-rebase-validate"

for branch in ${branches[@]}; do

  # first, validate if a rebase would work
  announce "Validating ${branch}"
  rm -rf "${validate_dir}"
  cp -a gentoo "${validate_dir}"
  if ! rebase_branch "${branch}" "${validate_dir}"; then
    failed_branches+=( "${branch}" )
    continue
  fi

  # Now that we know it works, rebase and push
  announce "Rebasing and pushing ${branch}"
  rebase_branch "${branch}" "gentoo"
  echo "======> Push"
  if ! git -C gentoo push origin "${branch}"; then
    failed_branches+=( "${branch}" )
    continue
  fi

done

if [[ -n "${failed_branches[@]}" ]]; then
  announce "ERROR: the following branches failed:"
printf "   %s\n" "${failed_branches[@]}"
  exit 1
fi

announce "All Done."
