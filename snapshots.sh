#!/bin/bash
PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'


function usage() {
	echo "Usage: ${0} [ssd|sd]"
	exit 1
}

if [ $# -ne 1 ]; then
	usage
elif [ "${1}" != 'ssd' -a "${1}" != 'sd' ]; then
	usage
fi

DISK="${1}"

if [ ! -f /usr/local/etc/snapshots_${DISK}.conf ]; then
	echo 'ERROR: Config file not found!' >/dev/stderr
	exit 1
fi

source /usr/local/etc/snapshots_${DISK}.conf

# execute command, check for errors
function doit() {
        echo "Executing: \"${1}\""
        nice -n19 ionice -c 3 ${1}
	#${1}
	RETURNCODE="${?}"
        if [ "${RETURNCODE}" -ne 0 ]; then
		echo "\"${1}\" returned \"${RETURNCODE}\"." >/dev/stderr
		exit 1
        fi
}


# get oldest snapshot for subvol
function get_oldest() {
        NR=`ls -1S ${BTRFSMNT}/ | egrep "^${1}\." | sed -e "s/${1}\.\([0-9]\+\)/\1/" | sort -n | tail -n 1`
        if [ -z ${NR} ]; then
                echo "ERROR: Determining oldest backup. Index not found!" >/dev/stderr
		echo "0"
        elif [ "${NR}" -gt 0 -a "${NR}" -lt 10000 ]; then
                echo -n
        else
                echo "ERROR: Determining oldest backup. \"${NR}\" out of range!" >/dev/stderr
		echo "0"
        fi
        echo "${NR}"
}


# check for space
function checkspace() {
        KBISFREE=`btrfsdf.sh ${1} | tail -n1 | sed -e 's/.* \([0-9]\{1,3\}\)%.*/\1/'`
        if [ ${KBISFREE} -ge ${MINSPACE} ] ; then
                echo 0
        else
                echo 1
        fi
}

# main loop
cd ${BTRFSMNT}
if [ -d ${BTRFSMNT}/root.bak -o -d ${BTRFSMNT}/data.bak ]; then
  echo "ERROR: Backup running!"
  exit 1
fi
if [ "${?}" -ne 0 ]; then
  echo "ERROR: Changing directory \"${BTRFSMNT}\"" > /dev/stderr
  exit 1
fi

# delete oldest snapshot of each subvolume if low on disc space
while [ `checkspace ${BTRFSMNT}` -eq 0 ]; do
  echo "INFO: Not enough free disc space. Deleting oldest snapshots!"
  ERROR=0
  for NAME in ${LVS}; do
    if [ `get_oldest "${NAME}"` -lt ${MINSNAP} ]; then
      echo -n "WARNING: Lower snapshot limit reached (Status:\""`get_oldest "${NAME}"`
      echo ", Limit: \"${MINSNAP}\". Will not delete snapshot for subvolume \"${NAME}\"!"
      ERROR=1
    else
      doit "btrfs subvolume delete ${NAME}.`get_oldest ${NAME}`"
    fi
  done
  if [ "${ERROR}" -eq 1 ]; then
    break
  fi
  echo "INFO: Waiting ${SLEEP} seconds."
  sleep ${SLEEP}
done

for NAME in ${LVS}; do
  # delete last snapshot if maximum amount of snapshots reached
  while [ `get_oldest "${NAME}"` -ge ${MAXSNAP} ]; do 
    echo "INFO: Snapshot limit reached. Deleting oldest snapshots on \"${NAME}\"!"
    doit "btrfs subvolume delete ${NAME}.`get_oldest ${NAME}`"
  done

  # vars for creating snapshots
  MIN=`get_oldest "${NAME}"`
  MAXTMP=`get_oldest "${NAME}"`
  let MAXTMP=${MAXTMP}+1

  # only keep every 4th snapshot after 96 snapshots (keep snapshot of every hour after 24 hours, if a snapshot is taken every 15 minutes) 
  if [ -d ${BTRFSMNT}/${NAME}.100 ]; then
    for i in `seq 97 99`; do
      if [ -d ${BTRFSMNT}/${NAME}.${i} ]; then
        doit "btrfs subvolume delete ${BTRFSMNT}/${NAME}.${i}"
      fi
    done
  fi
  # only keep every 16th snapshot after 288 snapshots (keep snapshot of every 4 hours after 72 hours, if a snapshot is taken every 15 minutes) 
  if [ -d ${BTRFSMNT}/${NAME}.304 ]; then
    for i in `seq 289 303`; do
      if [ -d ${BTRFSMNT}/${NAME}.${i} ]; then
        doit "btrfs subvolume delete ${BTRFSMNT}/${NAME}.${i}"
      fi
    done
  fi
  # only keep every 96th snapshot after 672 snapshots (keep snapshot of every day after 7 days, if a snapshot is taken every 15 minutes) 
  if [ -d ${BTRFSMNT}/${NAME}.768 ]; then
    for i in `seq 673 767`; do
      if [ -d ${BTRFSMNT}/${NAME}.${i} ]; then
        doit "btrfs subvolume delete ${BTRFSMNT}/${NAME}.${i}"
      fi
    done
  fi

  # rename existing snapshot
  while [ ${MIN} -gt 0 ]; do
    let MIN=${MAXTMP}-1
    if [ -d ${BTRFSMNT}/${NAME}.${MIN} ]; then
      # save date
      doit "touch .timestamp ${NAME}.${MIN}"
      # mv data
      doit "mv ${NAME}.${MIN} ${NAME}.${MAXTMP}"
      # restore date
      doit "touch ${NAME}.${MAXTMP} -r .timestamp"
      doit "rm -f .timestamp"
    fi
    let MAXTMP=${MIN}
  done

  # create new snapshot
  doit "btrfs subvolume snapshot ${NAME} ${NAME}.1"
  # timestamp new snapshot
  doit "touch ${NAME}.1"
done

