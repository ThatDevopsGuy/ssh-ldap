#
# class ldap
#
# Description:
#   Contains server-side components for 389 LDAP server
#
# Author:
#   Sebastian Weigand | sab@sw-dd.com

class ldap {
    
    include ldap::params

    # =========================================================================
    # Packages
    # =========================================================================

    # 389 Administration and Directory Servers:
    package {'389-admin': ensure => latest }
    package {'389-admin-console': ensure => latest }
    package {'389-console': ensure => latest }
    package {'389-ds': ensure => latest }
    package {'389-ds-base': ensure => latest }
    package {'389-ds-base-dbg': ensure => latest }
    package {'389-ds-base-dev': ensure => latest }
    package {'389-ds-base-libs': ensure => latest }
    package {'389-ds-base-libs-dbg': ensure => latest }
    package {'389-ds-console': ensure => latest }
    package {'389-ds-console-doc': ensure => latest }
    package {'389-dsgw': ensure => latest }

    # X11 Forwarding:
    package {'libxtst6': ensure => latest }
    
    # LDAP Search and Modify scripts:
    package {'ldapscripts': ensure => latest }
    
    # Parity backup tool:
    package {'par2': ensure => latest }

    # =========================================================================
    # Initial Configuration
    # =========================================================================

    /*
        Initialization procedure:

        1. If the hostname contains 'rw', then it is a supplier.

            1.a If performing an initial or subsequent (empty) spin-up of a new
                server, download the existing schema from S3 and configure the
                server as a master supplier.

            1.b If running Puppet on a system which already has a schema, do
                nothing, as the 'slapd' directory will already exist.

        2. If the hostname contains 'ro', then it is a dedicated consumer (or
            read replica). As such, it doesn't need to be told about the LDAP
            schema, as it will receive all of its configuration via standard
            replication, so just configure that now.

            2.a If performing an initial (empty) setup, establish sufficient
                replication credentials and set up the 389 DS server so that it
                can receive updates from the master.

            2.b If doing a Puppet run on an established system, do nothing as
                the 'slapd' directory will be present already (via `creates`).
    */

    # Store the LDAP setup and configuration files in a secure directory:
    file { "/root/.ldap":
        ensure => directory,
        owner  => "root",
        group  => "root",
        mode   => 500,
    } ->

    # The main 389-DS setup and configuration script:
    file { "/root/.ldap/389-setup.sh": 
        require => [Package["389-admin"], Package["389-ds"]],
        content => template('ldap/389-setup.sh.erb'),
        owner   => "root",
        group   => "root",
        mode    => 500,
    } ->

    # Execute the aformentioned script:
    exec { "389-setup":
        require => [Package["389-ds"], Package["389-admin"], File['/root/.ldap/389-setup.sh']],
        command => "/tmp/initial-ldap-setup.sh",
        creates => "/etc/dirsrv/slapd-$hostname",
    }

    service { "dirsrv":
        ensure => "running",
    }

    # =========================================================================
    # Requisite Scripts
    # =========================================================================

    # Supplier-related scripts:
    if "rw" in $hostname {

        file { "/etc/ldap.secret":
            ensure  => "file",
            content => "$directory_server_password",
            owner   => "root",
            group   => "root",
            mode    => 400,
        } ->

        file { "/usr/local/sbin/add-ldap-user":
            require => File["/etc/ldap.secret"],
            ensure  => present,
            content => template('ldap/add-ldap-user.sh.erb'),
            owner   => "root",
            group   => "root",
            mode    => 500,
        }

        file { "/usr/local/sbin/del-ldap-user":
            require => File["/etc/ldap.secret"],
            ensure  => present,
            content => template('ldap/del-ldap-user.sh.erb'),
            owner   => "root",
            group   => "root",
            mode    => 500,
        }
        
        file { "/root/.s3cfg":
            ensure  => present,
            content => template('ldap/s3cfg'),
            owner   => "root",
            group   => "root",
            mode    => 400,
        } ->

        # Primary method of backing up the system to S3:
        file { "/usr/local/sbin/ldap-backup":
            require => File["/root/.s3cfg"],
            ensure  => present,
            content => template('ldap/ldap-backup.sh.erb'),
            owner   => "root",
            group   => "root",
            mode    => 500,
        }

        # IMPORTANT: Needed for a new spin-up of a supplier:
        file { "/usr/local/sbin/ldap-restore":
            require => [File["/root/.s3cfg"], File["/etc/ldap.secret"]],
            ensure  => present,
            content => template('ldap/ldap-restore.sh.erb'),
            owner   => "root",
            group   => "root",
            mode    => 500,
        }

        # Dynamically intializes all consumers via on-the-fly LDIF:
        file { "/usr/local/sbin/ldap-initialize-all-consumers":
            ensure  => present,
            content => template('ldap/ldap-initialize-all-consumers.sh.erb'),
            owner   => "root",
            group   => "root",
            mode    => 500,
        }

        # Adds custom schema attributes and objects, sets up replication
        # changelog, and replication root:
        file { "/root/.ldap/ldap-supplier-setup.ldif": 
            require => [Package["ldapscripts"], Package["389-ds"], Exec["389-setup"]],
            content => template("ldap/ldap-supplier-setup.ldif.erb"),
            owner   => "root",
            group   => "root",
            mode    => 400,
        } ->

        # Establishes replication agreements and initializes the consumers:
        file { "/root/.ldap/ldap-replication-agreements.ldif": 
            require => [Package["ldapscripts"], Package["389-ds"], Exec["389-setup"]],
            content => template("ldap/ldap-replication-agreements.ldif.erb"),
            owner   => "root",
            group   => "root",
            mode    => 400,
        } ->

        # The ldap-restore script will either pull from the latest backup,
        # or establish requisite schema and initialize consumers.
        exec { "restore-ds":
            require => [Package["ldapscripts"], 
                Package["389-ds"], 
                Exec["389-setup"], 
                File["/root/.ldap/ldap-replication-agreements.ldif"], 
                File["/root/.ldap/ldap-supplier-setup.ldif"]],
            command => '/usr/local/sbin/ldap-restore',
        }
    }
    
    else {

        # Establishes Replication Manager credentials, replication parameters:
        file { "/root/.ldap/ldap-consumer-setup.ldif": 
            require => [Package["ldapscripts"], Exec["389-setup"]],
            content => template("ldap/ldap-consumer-setup.ldif.erb"),
            owner   => "root",
            group   => "root",
            mode    => 400,
        } ->

        exec { "consumer-setup":
            require => File["/root/.ldap/ldap-consumer-setup.ldif"],
            command => "ldapmodify -D \"cn=Directory Manager\" -w $directory_server_password -f /root/.ldap/ldap-consumer-setup.ldif",
            creates => "/root/.ldap/.consumer-confirmed",
        } ->

        exec { "confirm-consumer-setup":
            require => [Exec["consumer-setup"], File["/root/.ldap"], Exec["389-setup"]],
            command => "echo 'Puppet will not run if this file is present.'' > /root/.ldap/.consumer-confirmed",
        }
    }
}
