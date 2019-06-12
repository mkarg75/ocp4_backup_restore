#!/bin/bash 
##
## Script to back up to a mount point destination
## It will take a snapshot of a PVC, map it to a rbd device and mount it

#set -eux

# define global variables
pod=""
claimName=""	
pvc=""
snap=""
target=""

# Set defaults for command options
delete=False
k8s_cmd='kubectl'


###################### FUNCTIONS ####################

# function to get PVCs for a given pod
function get_pvc {
  claimName=$(kubectl get pod $pod -o yaml  | grep claimName | awk '{print $2}')
  pvc=$(kubectl get pvc $claimName | grep -v NAME | awk '{print $3}')
}

function snapshot_pvc {
  source=$1
  target=$2
  cat << EOF | kubectl create -f - 
  apiVersion: snapshot.storage.k8s.io/v1alpha1
  kind: VolumeSnapshot
  metadata:
    name: ${target}
  spec:
    snapshotClassName: csi-rbdplugin-snapclass
    source:
      name: ${source}
      kind: PersistentVolumeClaim
EOF
}

function map_rbd {
  # get the snapshot name
  snap=$(rbd snap ls $pvc | tail -n 1| awk '{print $2}') # a shameful and ugly hack to get the last line only
 
  # map the snapshot
  #echo rbd map rbd/$pvc@$snap
  rbd map rbd/${pvc}@${snap}

  # mount it to /mnt
  mount -t ext4 -o ro,noload /dev/rbd0 /mnt
  ls -al /mnt
}

function unmap_rbd {
  # umount /mnt
  umount /mnt
  # unmap the rbd device
  rbd unmap /dev/rbd0
}

function delete_snap {
$k8s_cmd delete volumesnapshot $1
}

function _usage {
  cat << END

Backs up a snapshot of a PV to a directory

Usage: $(basename "${0}") [-c <kubectl_cmd>] <pod_name>

  -p <pod_name>     : The name of the (p)od for which the PV should be backed up

  -c <kubectl_cmd>  : The (c)ommand to use for k8s admin (defaults to 'kubectl' for now)

  -d                : (D)elete the snapshot once done with the backup

  -h                : Help


END
}

# Capture and act on command options
while getopts ":p:c:dh" opt; do
  case $opt in 
    p)
      pod=${OPTARG}
      ;;
    c)
      k8s_cmd=${OPTARG}
      ;;
    d)
      delete=True
      ;;
    h)
      _usage
      exit 1
      ;;
    \?)
      echo "ERROR: Invalid option -${OPTARG}" >&2
      _usage
      exit 1
      ;;
    :)
      echo "Error: Option -${OPTARG} requires an argument." >&2
      _usage
      exit 1
      ;;
  esac
done

if [ -z $pod ]
then
  echo "No pod to backup given, exitting"
  exit 1 
fi

echo "Getting pvc data for pod $pod"
echo
get_pvc

# set up the snapshot name
# so far the name of the snapshot is pod-pvc
target="$pod"
target+="-$pvc"
echo "Snapshotting $claimName($pvc) to $target"
echo $claimName $target
snapshot_pvc "$claimName" "$target"
sleep 5

echo "Mapping the rbd and mounting it"
echo
map_rbd 

echo "Unmounting and unmapping the rbd"
unmap_rbd

echo $delete

if [ $delete = "True" ]
then 
  echo "Deleting the snapshot"
  echo 
  delete_snap $target
  kubectl get volumesnapshot
else
  echo "Not deleting the snapshot, make sure to take manual care of it!"
  echo
fi 

