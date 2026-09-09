#!/usr/bin/env bats
#
# tests/changelog.bats
#
# Structural checks on CHANGELOG.md. These exist because the same defect landed
# twice: #510 and #511 each appended their own group to `[Unreleased]`, leaving
# two `### Fixed` headings with `### Removed` between them, and #512 fixed it.
# Then #516 did it again.
#
# It merges cleanly every time, which is why review does not catch it: the two
# PRs append at different offsets, so git sees no conflict and produces a
# malformed document. Only a structural check can see it, and the release step
# carries the result into the GitHub release notes.

setup() {
    CHANGELOG="$BATS_TEST_DIRNAME/../CHANGELOG.md"
}

@test "changelog: [Unreleased] has at most one of each group heading" {
    # Scoped to [Unreleased], the only section still being edited. Released
    # sections are the published record and are left exactly as they shipped.
    run bash -c '
        awk "/^## \[/ { inu = (\$0 ~ /Unreleased/); delete seen; next }
             inu && /^### / {
                 if (seen[\$0]++) print \"DUPLICATE: \" \$0
             }" "'"$CHANGELOG"'"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "changelog: [Unreleased] groups follow Keep a Changelog order" {
    # Added, Changed, Deprecated, Removed, Fixed, Security. Prepending a group
    # is what produces an out-of-order document, and it is how this recurred.
    #
    # [Unreleased] only, deliberately. 7.16.0 carries a "### Notes" group and
    # several sections predate this convention; rewriting shipped entries to
    # satisfy a test added later would be revisionism, not a fix.
    run bash -c '
        awk "
            BEGIN {
                split(\"Added Changed Deprecated Removed Fixed Security\", o, \" \")
                for (i in o) rank[\"### \" o[i]] = i
            }
            /^## \[/ { inu = (\$0 ~ /Unreleased/); last = 0; next }
            inu && /^### / {
                r = rank[\$0]
                if (r == 0) { print \"UNKNOWN GROUP: \" \$0; next }
                if (r < last) print \"OUT OF ORDER: \" \$0
                last = r
            }" "'"$CHANGELOG"'"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "changelog: every version heading has a link definition" {
    # An orphaned heading points at no diff. The release step rewrites both
    # together, so they drift only when one is edited alone.
    run bash -c '
        headings=$(grep -oE "^## \[[0-9]+\.[0-9]+\.[0-9]+\]" "'"$CHANGELOG"'" | tr -d "#[] ")
        for h in $headings; do
            grep -qE "^\[$h\]: " "'"$CHANGELOG"'" || echo "NO DEFINITION: $h"
        done'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "changelog: an Unreleased heading and its link definition travel together" {
    # Either both are present or neither is. The release step removes the
    # heading and the definition in one move; an orphan of either is a bug.
    run bash -c '
        h=$(grep -cE "^## \[Unreleased\]" "'"$CHANGELOG"'" || true)
        d=$(grep -cE "^\[Unreleased\]: " "'"$CHANGELOG"'" || true)
        [ "$h" = "$d" ] || echo "MISMATCH: heading=$h definition=$d"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "changelog: entries cite an issue number" {
    # The file's own header says entries cite the issue, not the PR. An entry
    # with no reference cannot be traced back to why the change was made.
    run bash -c '
        awk "
            /^## \[/ { inu = (\$0 ~ /Unreleased/); next }
            inu && /^- \*\*/ { if (\$0 !~ /\(#[0-9]+\)/) print \"NO ISSUE REF: \" substr(\$0, 1, 60) }
        " "'"$CHANGELOG"'"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
