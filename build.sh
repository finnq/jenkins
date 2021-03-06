#!/usr/bin/env bash

function check_result {
  if [ "0" -ne "$?" ]
  then
    (repo forall -c "git reset --hard") >/dev/null
    rm -f .repo/local_manifests/roomservice.xml
    echo $1

    #tweet status
    if [ "$LUNCH" = "omni_mako-userdebug" ]
    then
      tweet "#OmniKang: Build failed, #Nexus #Nexus4 #mako"
    elif [ "$LUNCH" = "omni_i9100-userdebug" ]
    then
      tweet "#OmniKang: Build failed, #Galaxy #GalaxyS2 #i9100"
    else
      tweet "#OmniKang: Build failed, device $LUNCH not defined"
    fi
    #tweet status end

    exit 1
  fi
}

if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

if [ -z "$WORKSPACE" ]
then
  echo WORKSPACE not specified
  exit 1
fi

if [ -z "$CLEAN" ]
then
  echo CLEAN not specified
  exit 1
fi

if [ -z "$REPO_BRANCH" ]
then
  echo REPO_BRANCH not specified
  exit 1
fi

if [ -z "$LUNCH" ]
then
  echo LUNCH not specified
  exit 1
fi

if [ -z "$RELEASE_TYPE" ]
then
  echo RELEASE_TYPE not specified
  #exit 1
fi

if [ -z "$SYNC" ]
then
  echo SYNC not specified
  exit 1
fi

if [ -z "$PDROID" ]
then
  echo PDROID not specified
  exit 1
fi

if [ -z "$CONNECTIONS" ]
then
  CONNECTIONS=16
fi

if [ -z "$SYNC_PROTO" ]
then
  SYNC_PROTO=git
fi

# colorization fix in Jenkins
export CL_RED="\"\033[31m\""
export CL_GRN="\"\033[32m\""
export CL_YLW="\"\033[33m\""
export CL_BLU="\"\033[34m\""
export CL_MAG="\"\033[35m\""
export CL_CYN="\"\033[36m\""
export CL_RST="\"\033[0m\""

cd $WORKSPACE
rm -rf archive
mkdir -p archive
if [ ! -d "CHANGELOGS" ]; then
  mkdir CHANGELOGS
fi
export PDROID
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export USE_CCACHE=1
export CCACHE_NLEVELS=4
export BUILD_WITH_COLORS=0

git config --global user.name finnq
git config --global user.email finnq@finnq.de

if [[ "$REPO_BRANCH" =~ "kk" ]]; then 
   JENKINS_BUILD_DIR=kitkat
else
   JENKINS_BUILD_DIR=$REPO_BRANCH
fi

export JENKINS_BUILD_DIR

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
rm -rf .repo/manifests*
repo init -u $SYNC_PROTO://github.com/OmniKang/android.git -b $REPO_BRANCH
check_result "repo init failed."

# make sure ccache is in PATH
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/linux-x86/ccache"
export CCACHE_DIR=~/.kk_ccache

if [ -f ~/.jenkins_profile ]
then
  . ~/.jenkins_profile
fi

mkdir -p .repo/local_manifests
cp $WORKSPACE/jenkins/$REPO_BRANCH.xml .repo/local_manifests/

echo Core Manifest:
cat .repo/manifests/default.xml

echo Local Manifest:
cat .repo/local_manifests/$REPO_BRANCH.xml

if [ $SYNC = true ]
then
  ## TEMPORARY: Some kernels are building _into_ the source tree and messing
  ## up posterior syncs due to changes
  rm -rf kernel/*

  echo Syncing...
  repo sync -d -c -j $CONNECTIONS > /dev/null
  check_result "repo sync failed."
  echo "Sync complete."
else
  echo "Skip syncing..."
fi

echo "Create changelog."
LAST_SYNC=$(date -r .lsync_$LUNCH +%s)
WORKSPACE=$WORKSPACE LUNCH=$LUNCH bash $WORKSPACE/jenkins/changes/buildlog.sh $LAST_SYNC 2>&1
touch .lsync_$LUNCH
echo "Changelog created."
echo "Add changelog."
cd vendor/omni
cp -f $WORKSPACE/CHANGELOGS/$LUNCH.txt CHANGELOG.mkdn
git add CHANGELOG.mkdn
git commit -m "Added changelog."
cd ../..
echo "Changelog added."

if [ -f $WORKSPACE/jenkins/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/jenkins/$REPO_BRANCH-setup.sh
fi

if [ -f .last_branch ]
then
  LAST_BRANCH=$(cat .last_branch)
else
  echo "Last build branch is unknown, assume clean build"
  LAST_BRANCH=$REPO_BRANCH
fi

if [ "$LAST_BRANCH" != "$REPO_BRANCH" ]
then
  echo "Branch has changed since the last build happened here. Forcing cleanup."
  CLEAN=true
fi

. build/envsetup.sh

lunch $LUNCH
check_result "lunch failed."

# save manifest used for build (saving revisions as current HEAD)

# include only the auto-generated locals
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests/* $TEMPSTASH
mv $TEMPSTASH/roomservice.xml .repo/local_manifests/

# save it
repo manifest -o $WORKSPACE/archive/manifest.xml -r

# restore all local manifests
mv $TEMPSTASH/* .repo/local_manifests/ 2>/dev/null
rmdir $TEMPSTASH

UNAME=$(uname)

if [ "$RELEASE_TYPE" = "OK_NIGHTLY" ]
then
  export BUILDTYPE_NIGHTLY=true
elif [ "$RELEASE_TYPE" = "OK_EXPERIMENTAL" ]
then
  export BUILDTYPE_EXPERIMENTAL=true
elif [ "$RELEASE_TYPE" = "OK_RELEASE" ]
then
  export BUILDTYPE_RELEASE=true
fi

if [ ! -z "$OK_EXTRAVERSION" ]
then
  export BUILDTYPE_EXPERIMENTAL=true
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export BUILDTYPE_EXPERIMENTAL=true
  IS_HTTP=$(echo $GERRIT_CHANGES | grep http)
  if [ -z "$IS_HTTP" ]
  then
    python $WORKSPACE/jenkins/repopick.py $GERRIT_CHANGES
    check_result "gerrit picks failed."
  else
    python $WORKSPACE/jenkins/repopick.py $(curl $GERRIT_CHANGES)
    check_result "gerrit picks failed."
  fi
fi

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "100.0" ]
then
  ccache -M 100G
fi

if [ $CLEAN = true ]
then
  echo "Cleaning!"
  touch .clean
  make clobber
else
  rm out/target/product/*/OmniKang-*.zip*
fi

echo "$REPO_BRANCH" > .last_branch

breakfast $LUNCH
check_result "Build failed."
time mka bacon
check_result "Build failed."

for f in $(ls $OUT/OmniKang-*.zip*)
do
  ln $f $WORKSPACE/archive/$(basename $f)
done
if [ -f $OUT/utilties/update.zip ]
then
  cp $OUT/utilties/update.zip $WORKSPACE/archive/recovery.zip
fi
if [ -f $OUT/recovery.img ]
then
  cp $OUT/recovery.img $WORKSPACE/archive
fi

# archive the build.prop as well
ZIP=$(ls $WORKSPACE/archive/OmniKang-*.zip)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

# CORE: save manifest used for build (saving revisions as current HEAD)
rm -f .repo/local_manifests/$REPO_BRANCH.xml
rm -f .repo/local_manifests/roomservice.xml

# Stash away other possible manifests
TEMPSTASH=$(mktemp -d)
mv .repo/local_manifests $TEMPSTASH

repo manifest -o $WORKSPACE/archive/core.xml -r

mv $TEMPSTASH/local_manifests .repo
rmdir $TEMPSTASH

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive

#tweet status

if [ "$LUNCH" = "omni_mako-userdebug" ]
then
  tweet "#OmniKang: Build finished successfully ROM: ${rom} Changelog: ${log} #Nexus #Nexus4 #mako"
elif [ "$LUNCH" = "omni_i9100-userdebug" ]
then
  tweet "#OmniKang: Build finished successfully ROM: ${rom} Changelog: ${log} #Galaxy #GalaxyS2 #i9100"
else
  tweet "#OmniKang: Build finished successfully, device $LUNCH not defined"
fi
#tweet status end
