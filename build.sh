#!/usr/bin/env bash
#tweet status
if [ "$LUNCH" = "cm_mako-userdebug" ]
then
  tweet "#finnqBuild started, #Nexus #Nexus4 #mako"
elif [ "$LUNCH" = "cm_i9100-userdebug" ]
then
  tweet "#finnqBuild started, #Galaxy #GalaxyS2 #i9100"
else
  tweet "#finnqBuild started, device $LUNCH not defined"
fi
#tweet status end

function check_result {
  if [ "0" -ne "$?" ]
  then
    echo $1

    #tweet status
    if [ "$LUNCH" = "cm_mako-userdebug" ]
    then
      tweet "#finnqBuild failed, #Nexus #Nexus4 #mako"
    elif [ "$LUNCH" = "cm_i9100-userdebug" ]
    then
      tweet "#finnqBuild failed, #Galaxy #GalaxyS2 #i9100"
    else
      tweet "#finnqBuild failed, device $LUNCH not defined"
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
  exit 1
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
export BUILD_NO=$BUILD_NUMBER
unset BUILD_NUMBER

export USE_CCACHE=1
export CCACHE_NLEVELS=4
export BUILD_WITH_COLORS=0

git config --global user.name finnq
git config --global user.email finnq@finnq.de

if [[ "$REPO_BRANCH" =~ "jellybean" || $REPO_BRANCH =~ "cm-10" ]]; then 
   JENKINS_BUILD_DIR=jellybean
else
   JENKINS_BUILD_DIR=$REPO_BRANCH
fi

mkdir -p $JENKINS_BUILD_DIR
cd $JENKINS_BUILD_DIR

# always force a fresh repo init since we can build off different branches
# and the "default" upstream branch can get stuck on whatever was init first.
if [ -z "$CORE_BRANCH" ]
then
  CORE_BRANCH=$REPO_BRANCH
fi
rm -rf .repo/manifests*
repo init -u $SYNC_PROTO://github.com/CyanogenMod/android.git -b $CORE_BRANCH
check_result "repo init failed."

# make sure ccache is in PATH
if [[ "$REPO_BRANCH" =~ "jellybean" || $REPO_BRANCH =~ "cm-10" ]]
then
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilts/misc/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.jb_ccache
else
export PATH="$PATH:/opt/local/bin/:$PWD/prebuilt/$(uname|awk '{print tolower($0)}')-x86/ccache"
export CCACHE_DIR=~/.ics_ccache
fi

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

echo Syncing...
repo sync -d -c > /dev/null
check_result "repo sync failed."
echo Sync complete.

cd packages/apps/Gallery2
git revert 3afe270b445e8804d894166652672c0947d915f1

git revert dde77bda2f1f1923026d7164b38298821f1c825b
cd ../../..

if [ -f $WORKSPACE/jenkins/$REPO_BRANCH-setup.sh ]
then
  $WORKSPACE/jenkins/$REPO_BRANCH-setup.sh
fi

if [ -f .last_branch ]
then
  LAST_BRANCH=$(cat .last_branch)
else
  echo "Last build branch is unknown, assume clean build"
  LAST_BRANCH=$REPO_BRANCH-$CORE_BRANCH
fi

if [ "$LAST_BRANCH" != "$REPO_BRANCH-$CORE_BRANCH" ]
then
  echo "Branch has changed since the last build happened here. Forcing cleanup."
  CLEAN="true"
fi

. build/envsetup.sh
lunch $LUNCH
check_result "lunch failed."

# save manifest used for build (saving revisions as current HEAD)
repo manifest -o $WORKSPACE/archive/manifest.xml -r

rm -f $OUT/cm-*.zip*

UNAME=$(uname)

if [ "$RELEASE_TYPE" = "CM_NIGHTLY" ]
then
  if [ "$REPO_BRANCH" = "gingerbread" ]
  then
    export CYANOGEN_NIGHTLY=true
  else
    export CM_NIGHTLY=true
  fi
elif [ "$RELEASE_TYPE" = "CM_EXPERIMENTAL" ]
then
  export CM_EXPERIMENTAL=true
elif [ "$RELEASE_TYPE" = "CM_RELEASE" ]
then
  # gingerbread needs this
  export CYANOGEN_RELEASE=true
  # ics needs this
  export CM_RELEASE=true
fi

if [ ! -z "$CM_EXTRAVERSION" ]
then
  export CM_EXPERIMENTAL=true
fi

if [ $PDROID = "true" ]
then
  export CM_EXPERIMENTAL=true

  echo "------PDROID PATCHES------"

  cd frameworks/opt/telephony
  git pull pdroid $REPO_BRANCH-openpdroid-devel
  cd ../../..

  cd frameworks/base
  git pull pdroid $REPO_BRANCH-openpdroid-devel
  cd ../..

  cd libcore
  git pull pdroid $REPO_BRANCH-openpdroid-devel
  cd ..

  cd build
  git pull pdroid $REPO_BRANCH-openpdroid-devel
  cd ..

  cd packages/apps/Mms
  git pull pdroid $REPO_BRANCH-openpdroid-devel
  cd ../../..

  echo "------PDROID PATCHES END------"
fi

if [ ! -z "$GERRIT_CHANGES" ]
then
  export CM_EXPERIMENTAL=true
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

if ([ ! -z "$REBASED_COMMITS" ] && [ ! -z "$REBASED_REPOS" ])
then
  export CM_EXPERIMENTAL=true

  python $WORKSPACE/jenkins/rebasedchanges.py $REBASED_COMMITS - $REBASED_REPOS
  check_result "rebased changes picks failed."
fi

if [ ! "$(ccache -s|grep -E 'max cache size'|awk '{print $4}')" = "100.0" ]
then
  ccache -M 100G
fi

WORKSPACE=$WORKSPACE LUNCH=$LUNCH sh

if [ $CLEAN = "true" ]
then
  echo "Cleaning!"
  touch .clean
  make clobber
else
  echo "Hacky fix build date!"
  rm out/target/product/*/system/build.prop
fi

# PDroid fix
make update-api

echo "$REPO_BRANCH-$CORE_BRANCH" > .last_branch

time mka bacon recoveryzip recoveryimage checkapi
check_result "Build failed."

for f in $(ls $OUT/cm-*.zip*)
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
ZIP=$(ls $WORKSPACE/archive/cm-*.zip)
unzip -p $ZIP system/build.prop > $WORKSPACE/archive/build.prop

# CORE: save manifest used for build (saving revisions as current HEAD)
rm -f .repo/local_manifests/$REPO_BRANCH.xml
repo manifest -o $WORKSPACE/archive/core.xml -r

# chmod the files in case UMASK blocks permissions
chmod -R ugo+r $WORKSPACE/archive

CMCP=$(which cmcp)
if [ ! -z "$CMCP" -a ! -z "$CM_RELEASE" ]
then
  MODVERSION=$(cat $WORKSPACE/archive/build.prop | grep ro.modversion | cut -d = -f 2)
  if [ -z "$MODVERSION" ]
  then
    MODVERSION=$(cat $WORKSPACE/archive/build.prop | grep ro.cm.version | cut -d = -f 2)
  fi
  if [ -z "$MODVERSION" ]
  then
    echo "Unable to detect ro.modversion or ro.cm.version."
    exit 1
  fi
  echo Archiving release to S3.
  for f in $(ls $WORKSPACE/archive)
  do
    cmcp $WORKSPACE/archive/$f release/$MODVERSION/$f > /dev/null 2> /dev/null
    check_result "Failure archiving $f"
  done
fi

#pdroid cleanup
rm -rf frameworks/base

#tweet status

if [ "$LUNCH" = "cm_mako-userdebug" ]
then
  rom="`curl -s "https://api-ssl.bitly.com/v3/shorten?access_token=$BITLY_TOKEN&longUrl=http://n4.finnq.de/Preview/cm-10.1-$(date +"%Y%m%d")-EXPERIMENTAL-mako-finnq.zip&format=txt"`"
  log="`curl -s "https://api-ssl.bitly.com/v3/shorten?access_token=$BITLY_TOKEN&longUrl=http://n4.finnq.de/Preview/Log/changelog-$(date +"%Y%m%d").txt&format=txt"`"

  tweet "#finnqBuild finished successfully ROM: ${rom} Changelog: ${log} #Nexus #Nexus4 #mako"
elif [ "$LUNCH" = "cm_i9100-userdebug" ]
then
  rom="`curl -s "https://api-ssl.bitly.com/v3/shorten?access_token=$BITLY_TOKEN&longUrl=http://s2.finnq.de/Preview/cm-10.1-$(date +"%Y%m%d")-EXPERIMENTAL-i9100-finnq.zip&format=txt"`"
  log="`curl -s "https://api-ssl.bitly.com/v3/shorten?access_token=$BITLY_TOKEN&longUrl=http://s2.finnq.de/Preview/Log/changelog-$(date +"%Y%m%d").txt&format=txt"`"

  tweet "#finnqBuild finished successfully ROM: ${rom} Changelog: ${log} #Galaxy #GalaxyS2 #i9100"
else
  tweet "#finnqBuild finished successfully, device $LUNCH not defined"
fi
#tweet status end
