#!/usr/bin/sh
# RHEL7-14307

# Must run with root user
if [ $(whoami) != 'root' ]; then
    echo "Error: must run with root user"
    exit 1
fi


# recover the env
case $1 in
    --recover)
	    cp -f .libvirtd.conf /etc/libvirt/.libvirtd.conf 
        cp -f .libvirtd /etc/sysconfig/libvirtd
        service libvirtd restart
        if [ $? -eq 0 ]; then
            exit 0
        else
            echo "Error: Recover env failure"
            exit 1
        fi
        ;;
    --help|-h)
        echo "./$0 [--recover|-h|--help]"
        ;;
       *)
        ;;
esac

# Backup file
if ! [ -f ./.libvirtd.conf ]; then
	cp -f /etc/libvirt/libvirtd.conf .libvirtd.conf
fi

if ! [ -f ./.libvirtd ]; then
	cp -f /etc/sysconfig/libvirtd .libvirtd
fi

cat <<EOF > /etc/sysconfig/libvirtd
LIBVIRTD_ARGS = "--listen"
EOF

cat <<EOF > /etc/libvirt/libvirtd.conf
listen_tls = 0
listen_tcp =1
auth_tcp = "none"
tcp_port = "16510"
EOF

# restart libvirtd service
service libvirtd restart

if [ $? -ne 0 ]; then
    echo "Error: service libvirtd restart failed, please run it manually"
    exit 1
fi

echo
echo "Success: Restart the Guest and Run below command to connect to guest"
echo "virt-viewer -c qemu+tcp://{ip}:16510/system {guestname}"
