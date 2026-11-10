# =============================================================================
# pip_upgrade - Upgrade all pip user-site packages on every installed Python
# =============================================================================
#
# DESCRIPTION:
#   Upgrades every outdated package in the per-user pip site-packages of ALL
#   Python interpreters on this Mac: Xcode CLT (/usr/bin/python3) plus every
#   versioned Homebrew python (python3.13, python3.14, python3.15, ...).
#   Only touches user sites (~/Library/Python/<ver>/...), never Homebrew or
#   system locations. New Homebrew pythons are picked up automatically.
#
# USAGE:
#   pip_upgrade
#
# WHAT IT DOES:
#   1. Discovers interpreters: /usr/bin/python3 + /opt/homebrew/bin/python3.X
#   2. Upgrades pip itself, then lists outdated --user packages as JSON
#      and upgrades each (pip does not support --outdated --format=freeze)
#   3. Adds --break-system-packages only on PEP 668-era pip (brew 3.14+),
#      so the old pip on Xcode CLT 3.9 keeps working
#
# WHEN TO USE:
#   - Daily/weekly habit to keep global Python libraries current
#   - After a security report flags a user-site package (e.g. Pillow, pypdf)
#
# NOTE:
#   Bare `pip`/`pip3` on PATH resolves to the newest Homebrew Python
#   (currently 3.15). Packages installed that way land in the 3.15 user site
#   and are covered automatically by this function.
#
# EXAMPLE:
#   $ pip_upgrade
#   # ==> /opt/homebrew/bin/python3.14
#   # Pillow -> 13.0.0
#
# =============================================================================
function pip_upgrade --description "Upgrade pip user packages on every installed Python"
    # Interpreters: Xcode CLT python + every versioned Homebrew python.
    set -l interpreters /usr/bin/python3
    for py in /opt/homebrew/bin/python3.*
        if string match -rq '^python3\.[0-9]+$' -- (basename "$py")
            set -a interpreters "$py"
        end
    end

    set -l failed 0
    for py in $interpreters
        # Skip interpreters without a working pip module
        if not "$py" -m pip --version >/dev/null 2>&1
            continue
        end

        # --break-system-packages exists only on PEP 668-era pip
        set -l extra_flags
        if "$py" -m pip install --help | string match -q '*--break-system-packages*'
            set extra_flags --break-system-packages
        end

        echo "==> $py"
        if not "$py" -m pip install --user --upgrade $extra_flags pip
            echo "    Failed to upgrade pip" >&2
            set failed 1
            continue
        end

        set -l packages_json ("$py" -m pip list --user --outdated --format=json)
        if test $status -ne 0
            echo "    Failed to list outdated packages" >&2
            set failed 1
            continue
        end

        set -l outdated (printf '%s\n' $packages_json | "$py" -c 'import json, sys
for pkg in json.load(sys.stdin):
    print(pkg["name"])')
        if test $status -ne 0
            echo "    Failed to parse outdated packages" >&2
            set failed 1
            continue
        end
        if test (count $outdated) -eq 0
            echo "    All user packages are up to date"
            continue
        end

        for pkg in $outdated
            echo "    $pkg"
            if not "$py" -m pip install --user -U $extra_flags "$pkg"
                set failed 1
            end
        end
    end
    return $failed
end
