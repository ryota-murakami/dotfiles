# =============================================================================
# backup_nsx - NSX Production Database Backup Utility
# =============================================================================
#
# DESCRIPTION:
#   Pulls a fresh dump of the NSX *production* database and commits it to the
#   offsite git backup repository. Run ad hoc by the owner whenever a manual
#   snapshot is wanted.
#
# WHY THIS NO LONGER CALLS ./scripts/backup:
#   On 2026-05-27 nsx/scripts/backup was repurposed into a server-side cron
#   tool that dumps the *local* container and GPG-encrypts to
#   backups/daily/*.sql.gz.gpg. Calling it from here broke this workflow
#   (local nsx-db-1 is down + no gpg key + wrong output format). This function
#   instead streams a plain mysqldump straight off production, matching the
#   repo's existing backup_YYYYMMDD.sql files and CLAUDE.md's plain-.sql
#   recovery flow. Do NOT re-point this at ./scripts/backup.
#
# USAGE:
#   backup_nsx
#
# WORKFLOW:
#   1. SSH to production (nsx.malloc.tokyo) and mysqldump the `digital` DB via
#      `bash -s` — the remote login shell is fish, so the dump runs in bash to
#      source .env and read MYSQL_ROOT_PASSWORD.
#   2. Stream the dump into <repo>/backup_YYYYMMDD.sql.partial.
#   3. Verify (ssh exit 0 + "Dump completed" footer), then atomically rename to
#      backup_YYYYMMDD.sql so a failed run never clobbers a good backup.
#   4. Commit & push with the `git up` alias.
#
# PREREQUISITES:
#   - SSH access to nsx.malloc.tokyo (root) with prod container nsx-db-1 up
#   - ~/repository/backup-files/nsx/ git repository
#   - `git up` alias (git add --all && git commit -m up && git push)
#
# EXAMPLE:
#   $ backup_nsx
#   Creating production backup from nsx.malloc.tokyo ...
#   Saved /Users/you/repository/backup-files/nsx/backup_20260602.sql
#   [main abc1234] up
#   1 file changed, 1000 insertions(+)
# =============================================================================
function backup_nsx
    set -l original_dir $PWD
    set -l backup_repo ~/repository/backup-files/nsx
    set -l remote nsx.malloc.tokyo
    set -l backup_file backup_(date +%Y%m%d).sql
    set -l dest $backup_repo/$backup_file
    set -l partial $dest.partial

    # The backup repo must exist before we write anything into it.
    if not test -d $backup_repo
        echo "Error: backup repository not found: $backup_repo"
        return 1
    end

    # Stream a fresh production dump into a .partial file. The remote login shell
    # is fish, so the POSIX dump script is piped to `bash -s`; MYSQL_PWD is
    # exported into the container so the password never lands on a command line.
    echo "Creating production backup from $remote ..."
    printf '%s\n' \
        'set -a; . /home/deploy/nsx/.env; set +a' \
        'export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"' \
        'docker exec -e MYSQL_PWD nsx-db-1 mysqldump -uroot --single-transaction --routines --triggers --no-tablespaces digital' \
        | ssh $remote bash -s >$partial
    # Capture pipeline status immediately — fish resets $pipestatus after the
    # next command (including `set`), so read ssh's exit code before anything else.
    set -l ssh_status $pipestatus[-1]

    # Trust the dump only if ssh/mysqldump exited 0 AND it carries mysqldump's
    # "Dump completed" footer (i.e. the stream wasn't truncated mid-transfer).
    if test $ssh_status -ne 0; or not grep -q 'Dump completed' $partial
        echo "Error: production dump failed (ssh exit $ssh_status); not committing."
        rm -f $partial
        cd $original_dir
        return 1
    end

    # Atomic same-dir rename: the repo never sees a partial dump, and a failed
    # run never clobbers an existing good same-day backup.
    mv $partial $dest
    echo "Saved $dest"

    # Commit & push only when the dump actually changed something.
    cd $backup_repo
    if test -n "$(git status --porcelain)"
        git up
    else
        echo "No backup file changes to commit."
    end

    cd $original_dir
end
