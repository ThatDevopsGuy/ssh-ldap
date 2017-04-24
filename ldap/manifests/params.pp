#
# class ldap::params
#
# Description:
#   Contains parameters for the LDAP server
#
# Author:
#   Sebastian Weigand | sab@sab.systems

class ldap::params {

    # =========================================================================
    # Class-specific variables
    # =========================================================================
    
    # A listing of dedicated consumers which will receive replica updates:
    $consumer_hosts = ["ldap-ro1", "ldap-ro2"]
    $ldap_vip = "<YOUR IP HERE>"
    $admin_server_password = "<YOUR PASSWORD HERE>"
    $directory_server_password = "<YOUR PASSWORD HERE>"
    
    # This is the dc= part:
    $ldap_domain = "example"

    # This is for the email creation:
    $full_domain = "example.com"

    # S3 Bucket for LDAP backups:
    $s3_ldap_backup_bucket = 'ldap/ldap-backup'

    $user_group = <YOUR GROUP ID HERE>

    $aws_access_key = "<YOUR KEY HERE>"
    $awk_secret_key = "<YOUR SECRET KEY>"
    $gpg_passphrase = "<YOUR GPG PASSPHRASE HERE>"

}