#!/usr/bin/sh

# RHEL7-14308

# Must run with root user
if [ $(whoami) != 'root' ]; then
    echo "Error: must run with root user"
    exit 1
fi

# recover the env
case $1 in
    --recover)
        cp -f ./.libvirtd /etc/sysconfig/libvirtd
        cp -f ./.libvirtd.conf /etc/libvirt/libvirtd.conf
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
    --libvirt-tls-none)
        ;;
    --libvirt-tls-sasl)
        ;;
    --libvirt-tls-default)
        ;;
    --libvirt-tcp-none)
        ;;
       *)
        ;;
esac

echo  "Please type path for ca file"
echo -n "(Enter key for default value:/etc/pki):"
read ca_path

# set default path
if [ -z $ca_path ] ; then
    ca_path="/etc/pki"
fi

# remove the last '/' of the path
tmp=$(python -c "print '$ca_path'[-1]")

if [ "$tmp" == "/" ]; then
    ca_path=$(python -c "print '$ca_path'[0:-1]")
fi

get_ip()
{
    if [ $(uname -r | grep el6) ]; then
        ip=$(ifconfig | grep "inet addr:10." | head -1 | sed 's/:/ /' | awk -F' ' '{print $3}')
    elif [ $(uname -r | grep el7) ]; then
        ip=$(ifconfig | grep "inet 10." | awk -F' ' '{print $2}')
    elif [ $(uname -r | grep "fc") ]; then
        ip=$(ifconfig | grep "inet 10." | awk -F' ' '{print $2}')
    else
       exit 1
    fi 

    echo $ip
}

server_host_ip=$(get_ip)

if [ $? -eq 1 ]; then
    echo "Error: only rhel6 and rhel7 are supported"
    exit 1
fi


# read and check auth_tls value
for i in $(seq -s' ' 3);
do
    # get the auth way of server
    echo -n "Please Type tls auth way in Server(none, sasl or Enter key for default):"
    read authway_tls

    if [ -n "$authway_tls" ]; then
        case $authway_tls in 
            "sasl")
                echo "Error: sasl is not supported now"
                exit 1
                ;;
            "none")
                break
                ;;
            *)
                if [ $i -eq 3 ]; then
                    echo "Error: You mistyped 3 times and exit"
                    exit 1
                fi
                ;;
        esac
    else
        break
    fi
done

# read and check tls_port
for i in $(seq -s' ' 3);
do
    echo -n "Please Type tls_port(Enter key for default):"
    read tlsport

    if [ -z "$tlsport" ]; then
        break
    fi

    if [[ $tlsport -gt 0 ]] && [[ $tlsport -lt 65536 ]] 2>/dev/null ;then 
        break
    fi

    if [ $i -eq 3 ]; then
        echo "Error: You mistyped 3 times for tls_port and exit"
        exit 1
    fi
done

# Get and check client ip address 
for i in $(seq -s' ' 3);
do
echo -n "Please Type Client Host IP:"
read client_host_ip

ipvalid=$(python -c "
import os,sys
def check_ip(ipaddr):
    import sys
    addr=ipaddr.strip().split('.')  
    if len(addr) != 4: 
        print "1"
        sys.exit()
    for i in range(4):
        try:
            addr[i]=int(addr[i])
        except:
            print "1"
            sys.exit()
        if addr[i]<=255 and addr[i]>=0:    
            pass
        else:
            print "1"
            sys.exit()
        i+=1
    else:
        print "0"
check_ip('$client_host_ip')  
")

if [ $ipvalid -ne 0 ]; then
    echo "Error: Invalid Client IP Address"
    if [ $i -eq 3 ]; then
        echo "Error: You mistyped 3 times for Client HOST's IP and exit"
        exit 1
    fi
else
    break
fi
done

#echo -n "Please Type Client Host's Password:"
read -s -p "Please Type Client Host's Password:" client_password
echo

echo "##############################"
echo "Server IP: $server_host_ip"

certtool --generate-privkey > cakey.pem 

cat <<EOF > ca.info
cn = $server_host_ip
ca
cert_signing_key
EOF

echo 
echo "ca.info content:"
cat ca.info
echo 


certtool --generate-self-signed --load-privkey cakey.pem --template ca.info --outfile cacert.pem

certtool --generate-privkey > serverkey.pem 

cat <<EOF > server.info
organization = Red Hat
cn = $server_host_ip
tls_www_server
encryption_key
signing_key
EOF


echo 
echo "server.info content:"
cat server.info
echo "##############################"
echo 

certtool --generate-certificate --load-privkey serverkey.pem --load-ca-certificate cacert.pem \
         --load-ca-privkey cakey.pem --template server.info --outfile servercert.pem

cp -f cakey.pem cacert.pem ${ca_path}/CA 

mkdir -p ${ca_path}/libvirt/private

cp -f servercert.pem ${ca_path}/libvirt
cp -f serverkey.pem ${ca_path}/libvirt/private

# Backup file
if ! [ -f ./.libvirtd ]; then
    cp -f /etc/sysconfig/libvirtd ./.libvirtd
    cp -f /etc/libvirt/libvirtd.conf ./.libvirtd.conf
fi

cat <<EOF > /etc/sysconfig/libvirtd
LIBVIRTD_ARGS = "--listen"
EOF

if [ -z "$authway_tls" ]; then
    AUTHWAY=""
elif [ -n "$authway_tls" ]; then
    AUTHWAY="auth_tls = '$authway_tls'"
fi

if [ "$authway_tls" == "none" ]; then
    KEYFILE=""
    CERTFILE=""
    CAFILE=""
else
    KEYFILE="key_file = '${ca_path}/libvirt/private/serverkey.pem'"
    CERTFILE="cert_file = '${ca_path}/libvirt/servercert.pem'"
    CAFILE="ca_file = '${ca_path}/CA/cacert.pem'"
fi

if [ -z "$tlsport" ]; then
    TLSPORT=""
elif [ -n "$tlsport" ]; then
    TLSPORT="tls_port = '$tlsport'"
fi

cat <<EOF > /etc/libvirt/libvirtd.conf
listen_tls = 1
$AUTHWAY
$TLSPORT
$KEYFILE
$CERTFILE
$CAFILE
EOF

# restart libvirtd service
service libvirtd restart

if [ $? -ne 0 ]; then
    echo "Error: service libvirtd restart failed, please run it manually"
    exit 1
fi

# for "none", still need client do any thing
#if [ "$authway_tls" == "none" ]; then
#    echo "Success: Run below command in client host to connect to server"
#    #echo "virt-viewer -c qemu+tls://${server_host_ip}/system {guestname}"
#    #exit 1
#fi

# client script start
# --------------------
#echo "Success: please run run_client.sh in client host"
echo "****************************************"
echo "* Begin to handle client configuration *"
echo "****************************************"

expect -c "
spawn scp cacert.pem cakey.pem root@$client_host_ip:${ca_path}/CA;
expect *assword:*;
send  $client_password\n;
interact;";

cat <<EOFMAIN > ./client.sh
#!/usr/bin/sh
certtool --generate-privkey > clientkey.pem

cat <<EOF > client.info
country = GB 
state = London 
locality = London 
organization = Red Hat 
cn = $client_host_ip
tls_www_client 
encryption_key 
signing_key
EOF

certtool --generate-certificate --load-privkey clientkey.pem --load-ca-certificate ${ca_path}/CA/cacert.pem --load-ca-privkey ${ca_path}/CA/cakey.pem --template client.info --outfile clientcert.pem

mkdir -p ${ca_path}/libvirt/private
#cp -f clientkey.pem ${ca_path}/CA
#cp -f clientcert.pem ${ca_path}/CA

EOFMAIN

if [ $authway_tls == "none" ]; then
cat <<EOF >> ./client.sh
cp -f clientkey.pem ${ca_path}/libvirt/private
cp -f clientcert.pem ${ca_path}/libvirt
EOF
else
cat <<EOF >> ./client.sh
cp -f clientkey.pem ${ca_path}/CA
cp -f clientcert.pem ${ca_path}/CA
EOF
fi

chmod +x ./client.sh

expect -c "
spawn scp ./client.sh root@$client_host_ip:~;
expect *assword:*;
send  $client_password\n;
interact;";

python -c "
#!/usr/bin/env python
import pexpect
import sys

def remote_run(usr, passwd, ipaddr, cmd):
    user = usr
    passwrod = passwd
    ipaddr = ipaddr
    cmd = cmd

    child = pexpect.spawn('ssh %s@%s %s' % (user,ipaddr,cmd))
    res = child.expect(['Are you sure','password:'])
    if res == 0:
        child.sendline('yes')
        res_pwd = child.expect('password:')
        if res_pwd == 0:
            child.sendline('%s' % passwd)
            buf_read = child.read()
    elif res == 1:
        child.sendline('%s' % passwd)
        buf_read = child.read()
    else:
        buf_read = child.read()
    print buf_read

remote_run('root','$client_password','$client_host_ip','./client.sh')
"

echo "Success: Run below command in client host to connect to server"

if [ "authway_tls" == "none" ]; then
    echo "virt-viewer -c qemu+tls://${server_host_ip}/system {guestname}"
else
    echo "virt-viewer -c qemu+tls://${server_host_ip}/system?pkipath=${ca_path}/CA {guestname}"
fi
