#!/bin/bash 
set -eux

# global variables
pod=$1
claimName=""	
pvc=""
snap=""
target=""

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
kubectl delete volumesnapshot $1
}

############### MAIN #######################

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

echo "Deleting the snapshot"
echo 
delete_snap $target
kubectl get volumesnapshot
