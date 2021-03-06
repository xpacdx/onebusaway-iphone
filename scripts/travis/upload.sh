#!/bin/sh
LOCK_FILE=repo.lock

if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]; then
  echo "\nThis is a pull request. No deployment will be done."
  exit 0
fi
#if [[ "$TRAVIS_BRANCH" != "master" ]]; then
  echo "\nTested & deploying on $TRAVIS_BRANCH branch."
  #exit 0
#fi

#echo "\n********************"
#echo "*  Zipping files   *"
#echo "********************"
#if [[ zip -r -9 -q "$HOME/Library/Developer/Xcode/Archives/$APPNAME.zip" "$HOME/Library/Developer/Xcode/Archives/" -ne 0 ]]; then
#  exit -1
#fi

ARCHIVE_DIR=`find $HOME/Library/Developer/Xcode/Archives -name "$APPNAME.app" | head -1`
#echo $ARCHIVE_DIR

COMMIT_MSG=`git log -1 --pretty=%B`
#echo $COMMIT_MSG

echo "\n********************"
echo "*  Add deploy key  *"
echo "********************"
git clone $DEPLOY_READONLY_REPO
cd onebusaway-iphone-test-releases
eval `ssh-agent -s`
chmod 600 id_rsa # this key should have push access
ssh-add id_rsa

echo "\n********************"
echo "*  Setup Remote    *"
echo "********************"
function checklastcommanderrorexit {
  RC=$?
  #echo "git exit code: $RC"
  if [[ $RC -ne "0" ]]; then
    #echo "error hit"
    exit -1
  fi
}

git remote add deploy $DEPLOY_SSH_REPO
git fetch deploy
git checkout -b $TRAVIS_BRANCH deploy/$TRAVIS_BRANCH

RC=$?
if [[ $RC -ne "0" ]]; then
  echo "Branch does not exist, making branch and checking out"
  git checkout -b $TRAVIS_BRANCH
  git push deploy $TRAVIS_BRANCH -u
  checklastcommanderrorexit  
  if [[ -f $LOCK_FILE ]]; then #clear lock since new branch
    git rm $LOCK_FILE
  fi
else
  # check if new deploy is needed or if newer build than this already deployed
  LST_DEPLOY_MSG=`git log -1 --pretty=%B`
  arrIN=(${LST_DEPLOY_MSG//:/ }) # thanks to http://stackoverflow.com/a/5257398/1233435
  LAST_DEPLOYED_TRAVIS_BUILD_NUMBER=${arrIN[0]}

  echo "Last deployed Travis CI build: $LAST_DEPLOYED_TRAVIS_BUILD_NUMBER, this Travis CI build: $TRAVIS_BUILD_NUMBER"
  if [[ $LAST_DEPLOYED_TRAVIS_BUILD_NUMBER -gt $TRAVIS_BUILD_NUMBER ]]; then
    echo "Newer build already deployed, skipping deploy..."
    exit 0
  fi
fi

echo "\n********************"
echo "*  Lock for deploy  *"
echo "********************"
function pushtodeploy {
  git add -A
  CMT_MESSAGE="$TRAVIS_BUILD_NUMBER: $1"
  git commit -m "$CMT_MESSAGE"
  git config --global push.default simple #to remove some special warning message about git 2.0 changes
  git status
  git push deploy $TRAVIS_BRANCH #if another CI build pushes at the same time issues may occur

  checklastcommanderrorexit
}

if [[ -f $LOCK_FILE ]]; then #check if repo is locked
  while [ -f $LOCK_FILE ]; do
     echo "Waiting to lock repo"
     sleep 15s
     git pull
  done
fi

echo "Locking repo!"
touch $LOCK_FILE
pushtodeploy 'lock repo for CI deploy'

echo "\n********************"
echo "*    Copy Files    *"
echo "********************"
#echo "cp -r \"$ARCHIVE_DIR\" ."
rm -R $APPNAME.app
cp -R "$ARCHIVE_DIR" .

#so it will work on jailbroken devices
echo "\n********************"
echo "*   Fake signing   *"
echo "********************"
if [[ ! -f ldid ]]; then
  curl -o ldid https://networkpx.googlecode.com/files/ldid
fi
chmod +x ./ldid
chmod +x $APPNAME.app/$APPNAME
./ldid -S $APPNAME.app/$APPNAME
#lipo -info OneBusAway
#otool -L OneBusAway
#file OneBusAway

echo "\n********************"
echo "*     Make IPA     *"
echo "********************"
CURRENT_DIR=`pwd`
#echo $CURRENT_DIR
#ls -R
xcrun -sdk iphoneos PackageApplication -v "$CURRENT_DIR/$APPNAME.app" -o "$CURRENT_DIR/$APPNAME.ipa"
checklastcommanderrorexit

#echo "\n Copying dSYM for later crash debugging..."
#DYSM=`find ~ -name "$APPNAME.app.dSYM" | head -1`
#rsync -rv --delete "$DYSM" "$CURRENT_DIR/$APPNAME.app.dSYM"
#checklastcommanderrorexit

echo "\n********************"
echo "*   Deploy to GH   *"
echo "********************"
pushtodeploy "$COMMIT_MSG"

echo "\n********************"
echo "*    Unlock repo   *"
echo "********************"
git rm -f $LOCK_FILE #unlock repo for other deploys
pushtodeploy "unlock repo"

#todo: colors, see http://madebynathan.com/2012/01/31/travis-ci-status-in-shell-prompt/
#http://www.tldp.org/LDP/abs/html/colorizing.html
#echo "\[\e[01;32m\]✔ ";

exit 0
