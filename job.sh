if [ -z "$HOME" ]
then
  echo HOME not in environment, guessing...
  export HOME=$(awk -F: -v v="$USER" '{if ($1==v) print $6}' /etc/passwd)
fi

cd $WORKSPACE
mkdir -p ../android
cd ../android
export WORKSPACE=$PWD

if [ ! -d jenkins ]
then
  git clone git://github.com/finnq/jenkins.git
fi

cd jenkins
## Get rid of possible local changes
git reset --hard
git pull -s resolve

# Add /usr/local/bin to PATH
export PATH="$PATH:/usr/local/bin/:/opt/java6/bin:/opt/java6/db/bin:/opt/java6/jre/bin"

exec ./build.sh
