# =============================================================================
# backup_nsx - NSX Database Backup Utility
# =============================================================================
#
# DESCRIPTION:
#   Automates the backup process for the NSX project database.
#   Runs the backup script, moves the SQL dump to the backup repository,
#   and commits/pushes the changes.
#
# USAGE:
#   backup_nsx
#
# WORKFLOW:
#   1. Navigate to ~/nsx project directory
#   2. Execute ./scripts/backup (creates backup_*.sql)
#   3. Move SQL file to ~/repository/backup-files/nsx/
#   4. Commit and push using 'git up' alias
#   5. Return to home directory
#
# PREREQUISITES:
#   - ~/nsx project with ./scripts/backup script
#   - ~/repository/backup-files/nsx/ git repository
#   - 'git up' alias defined (git add . && git commit -m "up" && git push)
#
# EXAMPLE:
#   $ backup_nsx
#   Creating backup...
#   Moving backup_20240115_120000.sql to backup repository...
#   [master abc1234] up
#   1 file changed, 1000 insertions(+)
#
# =============================================================================
function backup_nsx
    cd ~/nsx
    bash -c './scripts/backup'
    mv backup_*.sql ~/repository/backup-files/nsx/
    cd ~/repository/backup-files/nsx
    git up
    cd ~
end
