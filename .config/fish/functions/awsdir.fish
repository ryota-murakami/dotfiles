# =============================================================================
# awsdir - AWS Credentials Directory Switcher
# =============================================================================
#
# DESCRIPTION:
#   Switches between different AWS credential directories by managing
#   symlinks. Useful for managing multiple AWS accounts (personal,
#   work, production) without manually copying credential files.
#
# USAGE:
#   awsdir                  # Show current AWS directory
#   awsdir laststance       # Switch to Laststance AWS credentials
#   awsdir customer         # Switch to customer AWS credentials
#   awsdir prod             # Switch to production AWS credentials
#
# PREREQUISITES:
#   Create separate AWS credential directories:
#     ~/aws-laststance/     # Contains credentials for Laststance account
#     ~/aws-customer/       # Contains credentials for customer account
#     ~/aws-prod/           # Contains credentials for production account
#
#   Each directory should contain:
#     - config              # AWS CLI configuration
#     - credentials         # AWS access keys
#
# HOW IT WORKS:
#   Creates/updates a symlink at ~/.aws pointing to the selected
#   credential directory. AWS CLI automatically uses ~/.aws.
#
# EXAMPLE:
#   $ awsdir
#   Currently linked to aws-laststance
#
#   $ awsdir customer
#   Linked to aws-customer
#
#   $ aws s3 ls  # Now uses customer credentials
#
# =============================================================================
function awsdir
    switch $argv[1]
        case "laststance"
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-laststance ~/.aws
            echo "Linked to asw-laststance"
        case "customer"
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-customer ~/.aws
            echo "Linked to aws-customer"
        case "prod"
            test -L ~/.aws; and unlink ~/.aws
            ln -sf ~/aws-prod ~/.aws
            echo "Linked to aws-prod"
        case "*"
            set linked_dir (readlink ~/.aws)
            switch $linked_dir
                case "*aws-laststance*"
                    echo "Currently linked to aws-laststance"
                case "*aws-customer*"
                    echo "Currently linked to aws-customer"
                case "*"
                    echo "Not linked to a valid directory: $linked_dir"
            end
    end
end
