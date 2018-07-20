#!/bin/sh
# Build an iocage jail under FreeNAS 11.1 with  Sonarr, Radarr, Lidarr and Plex
# https://github.com/NasKar2/apps-freenas-iocage

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE=""
VNET="off"
POOL_PATH=""
JAIL_NAME="mono"
OMBI_DATA=""
MEDIA_LOCATION=""
TORRENTS_LOCATION=""

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/mono-config
CONFIGS_PATH=$SCRIPTPATH/configs

# Check for mono-config and set configuration
if ! [ -e $SCRIPTPATH/mono-config ]; then
  echo "$SCRIPTPATH/mono-config must exist."
  exit 1
fi

# Check that necessary variables were set by mono-config
if [ -z $JAIL_IP ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z $DEFAULT_GW_IP ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z $INTERFACE ]; then
  echo 'Configuration error: INTERFACE must be set'
  exit 1
fi
if [ -z $POOL_PATH ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

if [ -z $JAIL_NAME ]; then
  echo 'Configuration error: JAIL_NAME must be set'
  exit 1
fi

if [ -z $OMBI_DATA ]; then
  echo 'Configuration error: OMBI_DATA must be set'
  exit 1
fi

if [ -z $MEDIA_LOCATION ]; then
  echo 'Configuration error: MEDIA_LOCATION must be set'
  exit 1
fi

if [ -z $TORRENTS_LOCATION ]; then
  echo 'Configuration error: TORRENTS_LOCATION must be set'
  exit 1
fi

#
# Create Jail
echo '{"pkgs":["nano","mono","unzip","ca_root_nss","sqlite3"]}' > /tmp/pkg.json
iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r 11.1-RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"

rm /tmp/pkg.json

mkdir -p ${POOL_PATH}/apps/${OMBI_DATA}

ombi_config=${POOL_PATH}/apps/${OMBI_DATA}
#iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${ombi_config} /config nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION} /mnt/media nullfs rw 0 0

iocage restart ${JAIL_NAME}
  
# add media group to media user

#iocage exec ${JAIL_NAME} pw groupadd -n media -g 8675309
#iocage exec ${JAIL_NAME} pw groupmod media -m plex
#iocage restart ${JAIL_NAME} 

#
# Make media the user of the jail and create group media and make media a user of the that group
#iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
#iocage exec ${JAIL_NAME} "pw groupadd -n media -g 8675309"
#iocage exec ${JAIL_NAME} "pw groupmod media -m ombi"

iocage exec ${JAIL_NAME} ln -s /usr/local/bin/mono /usr/bin/mono

iocage exec ${JAIL_NAME} "fetch https://github.com/tidusjar/Ombi/releases/download/v2.2.1/Ombi.zip -o /usr/local/share"
iocage exec ${JAIL_NAME} "unzip -d /usr/local/share /usr/local/share/Ombi.zip"

#iocage exec ${JAIL_NAME} "fetch https://github.com/tidusjar/Ombi/releases/download/v3.0.3477/linux.tar.gz -o /usr/local/share"
#iocage exec ${JAIL_NAME} "mkdir -p /usr/local/share/ombi"
#iocage exec ${JAIL_NAME} "tar -xzvf /usr/local/share/linux.tar.gz -C /usr/local/share/ombi"
iocage exec ${JAIL_NAME} mv /usr/local/share/Release /usr/local/share/ombi
iocage exec ${JAIL_NAME} rm /usr/local/share/Ombi.zip

iocage exec ${JAIL_NAME} sqlite3 /config/Ombi.sqlite "create table aTable(field1 int); drop table aTable;"
iocage exec ${JAIL_NAME} mkdir -p /config/Backups
echo "before ls"
iocage exec ${JAIL_NAME} ln -s /config/Ombi.sqlite /usr/local/share/ombi/Ombi.sqlite
iocage exec ${JAIL_NAME} ln -s /config/Backups /usr/local/share/ombi/Backups
echo "add user ombi"
iocage exec ${JAIL_NAME} "pw user add ombi -c ombi -u 819 -d /nonexistent -s /usr/bin/nologin"
echo "chown share/ombi and /config"
iocage exec ${JAIL_NAME} chown -R ombi:ombi /usr/local/share/ombi /config
echo "mkdir rc.d"
mkdir -p /mnt/iocage/jails/${JAIL_NAME}/root/usr/local/etc/rc.d
echo "finsihed mkdir rc.d"
#iocage exec ${JAIL_NAME} -- mkdir -p /usr/local/etc/rc.d
echo "before copy ombi to rc.d"
iocage exec ${JAIL_NAME} cp -f /mnt/configs/ombi /usr/local/etc/rc.d/ombi



iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/ombi
iocage exec ${JAIL_NAME} sysrc ombi_enable=YES
iocage exec ${JAIL_NAME} service ombi start

#
# Make pkg upgrade get the latest repo
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
iocage exec ${JAIL_NAME} pkg upgrade -y
iocage restart ${JAIL_NAME}


echo "Ombi installed"

#
# remove /mnt/configs as no longer needed
#iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

echo
echo "Ombi should be available at http://${JAIL_IP}:3579"

