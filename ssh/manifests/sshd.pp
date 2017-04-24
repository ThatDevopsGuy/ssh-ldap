#
# class ssh::sshd
#
# Description:
#   Contains SSHD configuration, plus LDAP tie-ins
#
# Author:
#   Sebastian Weigand | sab@sab.systems

class ssh::sshd {

    # Ensure that OpenSSH is at 6.2, as that includes the coveted
    # "AuthorizedKeysCommand" directive:
    apt::ppa { 'ppa:freeipa/ppa': }

    package { "openssh-server":
        #ensure => "1:6.2p2-3~precise2",
        ensure  => "latest",
    }

    file { "/etc/ssh/sshd_config":
        ensure  => file,
        content => template('ssh/sshd_config.erb'),
        notify  => Service["ssh"]
    }

    file { "/etc/ssh/getkeyfromldap.sh":
        content => template('ssh/getkeyfromldap.sh.erb'),
        ensure => present,
        owner  => root,
        group  => root,
        mode   => 0500,
    }

    service { "ssh":
        ensure  => running,
        enable  => true,
    }
}