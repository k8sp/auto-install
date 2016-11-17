#!/usr/bin/env bash

# bsroot.sh creates the $PWD/bsroot directory, which is supposed to be
# scp-ed to the bootstrapper server as /bsroot.

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    echo "Usage: $0 <cluster-desc.yml> [\$SEXTANT_DIR/bsroot]"
    exit 1
fi

source $(cd `dirname $0`; pwd)/bsroot_common.sh

download_centos_images() {
    VERSION=CentOS7
    mkdir -p $BSROOT/tftpboot
    printf "Downloading syslinux ... "
    wget --quiet -c -N -P $BSROOT/tftpboot https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.gz || { echo "Failed"; exit 1; }
    cd $BSROOT/tftpboot
    tar xzf syslinux-6.03.tar.gz || { echo "Failed"; exit 1; }
    cp syslinux-6.03/bios/core/pxelinux.0 $BSROOT/tftpboot || { echo "Failed"; exit 1; }
    cp syslinux-6.03/bios/com32/menu/vesamenu.c32 $BSROOT/tftpboot || { echo "Failed"; exit 1; }
    cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 $BSROOT/tftpboot || { echo "Failed"; exit 1; }
    rm -rf syslinux-6.03 || { echo "Failed"; exit 1; } # Clean the untarred.
    echo "Done"


    printf "Downloading CentOS 7 PXE vmlinuz image ... "
    cd $BSROOT/tftpboot
    mkdir -p $BSROOT/tftpboot/CentOS7
    wget --quiet -c -N -P $BSROOT/tftpboot/CentOS7 http://mirrors.163.com/centos/7.2.1511/os/x86_64/images/pxeboot/initrd.img  || { echo "Failed"; exit 1; }
    wget --quiet -c -N -P $BSROOT/tftpboot/CentOS7 http://mirrors.163.com/centos/7.2.1511/os/x86_64/images/pxeboot/vmlinuz  || { echo "Failed"; exit 1; }
    echo "Done"

    printf "Downloading CentOS 7 ISO ... "
    mkdir -p $BSROOT/html/static/CentOS7
    wget --quiet -c -N -P $BSROOT/html/static/CentOS7 http://mirrors.163.com/centos/7.2.1511/isos/x86_64/CentOS-7-x86_64-DVD-1511.iso || { echo "Failed"; exit 1; }
    echo "Done"
}


generate_pxe_centos_config() {
    printf "Generating pxelinux.cfg ... "
    mkdir -p $BSROOT/tftpboot/pxelinux.cfg
    cat > $BSROOT/tftpboot/pxelinux.cfg/default <<EOF
default CentOS7

label CentOS7
  menu label ^Install CentOS 7
  kernel CentOS7/vmlinuz
  append initrd=CentOS7/initrd.img ks=http://$BS_IP/static/CentOS7/ks.cfg
EOF
    echo "Done"
}


generate_kickstart_config() {
    printf "Generating kickstart config ... "
    mkdir -p $BSROOT/html/static/CentOS7
    cat > $BSROOT/html/static/CentOS7/ks.cfg <<EOF
#platform=x86, AMD64, or Intel EM64T
#version=DEVEL
# Install OS instead of upgrade
install
# Keyboard layouts
keyboard 'us'
# Root password
rootpw --plaintext atlas
# System timezone
timezone Asia/Shanghai
# Use network installation
url --url="http://$BS_IP/static/CentOS7/dvd_content"
# System language
lang en_US
# Firewall configuration
firewall --disabled
# System authorization information
auth  --useshadow  --passalgo=sha512
# Use text mode install
text
firstboot --disable
# SELinux configuration
selinux --disabled
# Do not configure the X Window System
skipx

# Halt after installation
reboot
# System bootloader configuration
bootloader --location=mbr
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all
# Disk partitioning information
part / --fstype="xfs" --grow --ondisk=sda --size=1
part swap --fstype="swap" --ondisk=sda --size=30000

repo --name=base --baseurl="http://mirrors.163.com/centos/7/os/x86_64/"
network --onboot on --bootproto dhcp --noipv6

%packages --ignoremissing
@Base
@Core
%end


%pre

%end

%post --log=/root/ks-post-provision.log
wget -P /root http://$BS_IP/static/CentOS7/post_provision.sh
bash -x /root/post_provision.sh
%end

%post --nochroot
wget http://$BS_IP/static/CentOS7/post_nochroot_provision.sh
bash -x ./post_nochroot_provision.sh
%end

EOF
    echo "Done"
}


generate_post_provision_script() {
    printf "Generating post provision script ... "
    mkdir -p $BSROOT/html/static/CentOS7
    cat > $BSROOT/html/static/CentOS7/post_provision.sh <<'EOF'
#!/bin/bash
EOF
    echo "Done"
}


generate_post_nochroot_provision_script() {
    printf "Generating post nochroot provision script ... "
    mkdir -p $BSROOT/html/static/CentOS7
    cat > $BSROOT/html/static/CentOS7/post_nochroot_provision.sh <<'EOF'
#!/bin/bash
#Obtain devices
devices=$(lsblk -l |awk '$6=="disk"{print $1}')
# Zap all devices
# NOTICE: dd zero to device mbr will not affect parted printed table,
#         so use parted to remove the part tables

default_iface=$(awk '$2 == 00000000 { print $1  }' /proc/net/route | uniq)

printf "Default interface: ${default_iface}\n"
default_iface=`echo ${default_iface} | awk '{ print $1 }'`

mac_addr=`ip addr show dev ${default_iface} | awk '$1 ~ /^link\// { print $2 }'`
printf "Interface: ${default_iface} MAC address: ${mac_addr}\n"

hostname_str=${mac_addr//:/-}

hostnamectl set-hostname $hostname_str
EOF
    echo "Done"
}


check_prerequisites
load_yaml $CLUSTER_DESC cluster_desc_
download_centos_images
generate_pxe_centos_config
generate_kickstart_config
generate_post_provision_script
generate_post_nochroot_provision_script

generate_registry_config
prepare_cc_server_contents
download_k8s_images
build_bootstrapper_image
generate_tls_assets
prepare_setup_kubectl
generate_addons_config