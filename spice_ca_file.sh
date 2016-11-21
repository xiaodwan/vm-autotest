#!/usr/bin/sh

# Must run with root user
if [ $(whoami) != 'root' ]; then
    echo "Error: must run with root user"
    exit 1
fi


# recover the env
case $1 in
    --recover)
	    cp -f .qemu.conf /etc/libvirt/qemu.conf .qemu.conf
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
if ! [ -f ./.qemu.conf ]; then
	cp -f /etc/libvirt/qemu.conf .qemu.conf
fi

cat <<EOF > /etc/libvirt/qemu.conf
spice_listen = "0.0.0.0"
spice_tls = 1
spice_tls_x509_cert_dir = "/etc/pki/libvirt-spice"
EOF

# 
SERVER_KEY=server-key.pem
# creating a key for our ca
if [ ! -e ca-key.pem ]; then
openssl genrsa -des3 -out ca-key.pem 1024
fi
# creating a ca
if [ ! -e ca-cert.pem ]; then
openssl req -new -x509 -days 1095 -key ca-key.pem -out ca-cert.pem -subj "/C=IL/L=Raanana/O=Red Hat/CN=my CA"
fi
# create server key
if [ ! -e $SERVER_KEY ]; then
openssl genrsa -out $SERVER_KEY 1024
fi
# create a certificate signing request (csr)
if [ ! -e server-key.csr ]; then
openssl req -new -key $SERVER_KEY -out server-key.csr -subj "/C=IL/L=Raanana/O=Red Hat/CN=my server"
fi
# signing our server certificate with this ca
if [ ! -e server-cert.pem ]; then
openssl x509 -req -days 1095 -in server-key.csr -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
fi
# now create a key that doesn't require a passphrase
openssl rsa -in $SERVER_KEY -out $SERVER_KEY.insecure
mv $SERVER_KEY $SERVER_KEY.secure
mv $SERVER_KEY.insecure $SERVER_KEY
# show the results (no other effect)
openssl rsa -noout -text -in $SERVER_KEY
openssl rsa -noout -text -in ca-key.pem
openssl req -noout -text -in server-key.csr
openssl x509 -noout -text -in server-cert.pem
openssl x509 -noout -text -in ca-cert.pem
# copy *.pem file to /etc/pki/libvirt-spice
if [[ -d "/etc/pki/libvirt-spice" ]]
then
cp ./*.pem /etc/pki/libvirt-spice
else
mkdir /etc/pki/libvirt-spice
cp ./*.pem /etc/pki/libvirt-spice
fi
# echo --host-subject
echo "your --host-subject is" \" `openssl x509 -noout -text -in server-cert.pem | grep Subject: | cut -f 10- -d " "` \"

# restart libvirtd service
service libvirtd restart

if [ $? -ne 0 ]; then
    echo "Error: service libvirtd restart failed, please run it manually"
    exit 1
fi

echo
echo "Success: Restart the Guest and Run below command to connect to guest"
#echo "virt-viewer -c qemu:///system --spice-host-subject='C=IL,L=Raanana,O=Red Hat,CN=my server' --spice-ca-file='/etc/pki/libvirt-spice/ca-cert.pem' {guestname}"
echo "remote-viewer spice://{ip}/?tls-port={tlsport} --spice-host-subject='C=IL,L=Raanana,O=Red Hat,CN=my server' --spice-ca-file='/etc/pki/libvirt-spice/ca-cert.pem'"
