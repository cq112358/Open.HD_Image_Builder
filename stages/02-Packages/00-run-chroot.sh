# This runs in context if the image (CHROOT)
# Any native compilation can be done here
# Do not use log here, it will end up in the image

#!/bin/bash
if [[ "${OS}" != "ubuntu" ]]; then
    # Remove bad and unnecessary symlinks if system is not ubuntu
    rm /lib/modules/*/build || true
    rm /lib/modules/*/source || true
fi


if [ "${APT_CACHER_NG_ENABLED}" == "true" ]; then
    echo "Acquire::http::Proxy \"${APT_CACHER_NG_URL}/\";" >> /etc/apt/apt.conf.d/10cache
fi

if [[ "${OS}" == "raspbian" ]]; then
    echo "OS is raspbian"
    rm /boot/config.txt
    rm /boot/cmdline.txt
    apt-mark hold firmware-atheros || exit 1
    apt purge firmware-atheros || exit 1
    apt -yq install firmware-misc-nonfree || exit 1
    apt-mark hold raspberrypi-kernel
    # Install libraspberrypi-dev before apt-get update
    DEBIAN_FRONTEND=noninteractive apt -yq install libraspberrypi-doc libraspberrypi-dev libraspberrypi-dev libraspberrypi-bin libraspberrypi0 || exit 1
    apt-mark hold libraspberrypi-dev libraspberrypi-bin libraspberrypi0 libraspberrypi-doc
    apt purge raspberrypi-kernel
    PLATFORM_PACKAGES=""
fi


if [[ "${OS}" == "armbian" ]]; then
    echo "OS is armbian"
    PLATFORM_PACKAGES=""
fi


if [[ "${OS}" == "ubuntu" ]]; then
    echo "OS is ubuntu"
    PLATFORM_PACKAGES=""

    echo "-------------------------SHOW nvideo source list-------------------------------"
    #it appears some variable for source list gets missed when building images like this.. 
    #by deleting and rewriting source list entry it fixes it.
    rm /etc/apt/sources.list.d/nvidia-l4t-apt-source.list || true
    echo "deb https://repo.download.nvidia.com/jetson/common r32.6 main" > /etc/apt/sources.list.d/nvidia-l4t-apt-source2.list
    echo "deb https://repo.download.nvidia.com/jetson/t210 r32.6 main" > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
    sudo cat /etc/apt/sources.list.d/nvidia-l4t-apt-source.list

    #remove some nvidia packages... if building from nvidia base image 
	#gdm isn't used, remove lightdm instead, removed new line in #60
    sudo apt remove ubuntu-desktop
    sudo apt remove libreoffice-writer chromium-browser chromium* yelp unity thunderbird rhythmbox nautilus gnome-software
    sudo apt remove ubuntu-artwork ubuntu-sounds ubuntu-wallpapers ubuntu-wallpapers-bionic
    sudo apt remove vlc-data lightdm
    sudo apt remove unity-settings-daemon packagekit wamerican mysql-common libgdm1
    sudo apt remove ubuntu-release-upgrader-gtk ubuntu-web-launchers
    sudo apt remove --purge libreoffice* gnome-applet* gnome-bluetooth gnome-desktop* gnome-sessio* gnome-user* gnome-shell-common gnome-control-center gnome-screenshot
    sudo apt autoremove
    
fi


if [[ "${HAS_CUSTOM_KERNEL}" == "true" ]]; then
    echo "-----------------------has a custom kernel----------------------------------"
    PLATFORM_PACKAGES="${PLATFORM_PACKAGES} ${KERNEL_PACKAGE}"
fi

#echo "-------------------------SHOW sources content-------------------------------"

#sudo cat /etc/apt/sources.list
#sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

echo "-------------------------GETTING FIRST UPDATE------------------------------------"

apt update --allow-releaseinfo-change || exit 1  

echo "-------------------------DONE GETTING FIRST UPDATE-------------------------------"

apt install -y apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1/cfg/gpg/gpg.0AD501344F75A993.key' | apt-key add -
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1-testing/cfg/gpg/gpg.58A6C96C088A96BF.key' | apt-key add -
sudo apt-get install -y apt-utils
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1-testing/setup.deb.sh' | sudo -E bash && \
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1/setup.deb.sh' | sudo -E bash && \
apt update


echo "deb https://dl.cloudsmith.io/public/openhd/openhd-2-1/deb/${OS} ${DISTRO} main" > /etc/apt/sources.list.d/openhd-2-1.list

if [[ "${TESTING}" == "testing" ]]; then
    echo "deb https://dl.cloudsmith.io/public/openhd/openhd-2-1-testing/deb/${OS} ${DISTRO} main" > /etc/apt/sources.list.d/openhd-2-1-testing.list
fi

echo "-------------------------GETTING SECOND UPDATE------------------------------------"

apt update --allow-releaseinfo-change || exit 1

echo "-------------------------DONE GETTING SECOND UPDATE------------------------------------"

echo "Purge packages that interfer/we dont need..."

PURGE="wireless-regdb cron avahi-daemon curl iptables man-db logrotate"
#jtop was replaced with jetson-stats, so no need to install it, also replaced kernel headers, since there are no specific tegra ones

export DEBIAN_FRONTEND=noninteractive

echo "install openhd version-${OPENHD_PACKAGE}"
if [[ "${OS}" == "ubuntu" ]]; then
    echo "Install some Jetson essential libraries and compile rtl8812au driver from sources"
    sudo apt install -y git nano python-pip build-essential libelf-dev
    sudo -H pip install -U jetson-stats
    sudo apt-get install linux-headers-4.15.0-166
    sudo apt-get install linux-headers-4.18.0.25-generic
    git clone https://github.com/svpcom/rtl8812au.git
    cd rtl8812au
    sudo sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile
    sudo sed -i 's/CONFIG_PLATFORM_ARM_NV_NANO = n/CONFIG_PLATFORM_ARM_NV_NANO = y/' Makefile
    make KVER=4.9.253-tegra all && make install KVER=4.9.253-tegra all
    cp -r 88XXau_wfb.ko /lib/modules/4.9.253-tegra/kernel/drivers/net/wireless/realtek/rtl8812au/
    cd ..
    cd /lib/modules/4.9.253-tegra/kernel/drivers/net/wireless/realtek/rtl8812au/
    mv rtl8812au.ko rtl8812au.ko.bak
    echo '#!/bin/bash' >> /usr/local/bin/video.sh && printf "\nsudo nvpmodel -m 0 | sudo jetson_clocks\nsudo iw wlan0 set freq 5320\nsudo iw wlan0 set txpower fixed 3100\necho \"nameserver 1.1.1.1\" > /etc/resolv.conf" >> /usr/local/bin/video.sh
    printf "[Unit]\nDescription=\"Jetson Nano clocks\"\nAfter=openhdinterface.service\n[Service]\nExecStart=/usr/local/bin/video.sh\n[Install]\nWantedBy=multi-user.target\nAlias=video.service" >> /etc/systemd/system/video.service
    sudo chmod u+x /usr/local/bin/video.sh
    sudo systemctl enable networking.service
    sudo systemctl enable video.service
fi

apt update && apt upgrade -y
apt -y --no-install-recommends install \
${OPENHD_PACKAGE} \
${PLATFORM_PACKAGES} \
${GNUPLOT} || exit 1

apt -yq purge ${PURGE} || exit 1
apt -yq clean || exit 1
apt -yq autoremove || exit 1

if [ ${APT_CACHER_NG_ENABLED} == "true" ]; then
    rm /etc/apt/apt.conf.d/10cache
fi


MNT_DIR="${STAGE_WORK_DIR}/mnt"

#
# Write the openhd package version back to the base of the image and
# in the work dir so the builder can use it in the image name
export OPENHD_VERSION=$(dpkg -s openhd | grep "^Version" | awk '{ print $2 }')

echo ${OPENHD_VERSION} > /openhd_version.txt
echo ${OPENHD_VERSION} > /boot/openhd_version.txt
