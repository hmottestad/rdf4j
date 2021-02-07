#!/bin/bash

cd ..

echo ""
echo "The release script requires several external command line tools:"
echo " - git"
echo " - mvn"
echo " - gh (the GitHub CLI, see https://github.com/cli/cli)"
echo " - xmlllint (http://xmlsoft.org/xmllint.html)"

echo ""
echo "This script will stop if an unhandled error occurs";
echo "Do not change any files in this directory while the script is running!"
set -e -o pipefail


read -rp "Start the release process (y/n)?" choice
case "${choice}" in
  y|Y ) echo "";;
  n|N ) exit;;
  * ) echo "unknown response, exiting"; exit;;
esac

# verify required tools are installed
if ! command -v git &> /dev/null; then
    echo "";
    echo "git command not found!";
    echo "";
    exit 1;
fi

if ! command -v mvn &> /dev/null; then
    echo "";
    echo "mvn command not found!";
    echo  "See https://maven.apache.org/";
    echo "";
    exit 1;
fi

if ! command -v gh &> /dev/null; then
    echo "";
    echo "gh command not found!";
    echo  "See https://github.com/cli/cli";
    echo "";
    exit 1;
fi

if ! command -v xmllint &> /dev/null; then
    echo "";
    echo "xmllint command not found!";
    echo "See http://xmlsoft.org/xmllint.html"
    echo "";
    exit 1;
fi

# check Java version
if  !  mvn -v | grep -q "Java version: 1.8."; then
  echo "";
  echo "You need to use Java 8!";
  echo "mvn -v";
  echo "";
  exit 1;
fi


# check that we are on master
if  ! git status --porcelain --branch | grep -q "## master...origin/master"; then
  if  ! git status --porcelain --branch | grep -q "## develop...origin/develop"; then
    echo""
    echo "You need to be on master or develop!";
    echo "";
    exit 1;
  fi
fi

echo "Running git pull to make sure we are up to date"
git pull

# check that we are not ahead or behind
if  ! git status --porcelain --branch | grep -q "## master...origin/master"; then
  if  ! git status --porcelain --branch | grep -q "## develop...origin/develop"; then
    echo""
    echo "There is something wrong with your git. It seems you are not up to date with master. Run git status";
    echo "";
    exit 1;
  fi
fi

# check that there are no uncomitted or untracked files
if  ! [[ $(git status --porcelain) == "" ]]; then
    echo "";
    echo "There are uncomitted or untracked files! Commit, delete or unstage files. Run git status for more info.";
    exit 1;
fi

# check that we have push access
if ! git push --dry-run > /dev/null 2>&1; then
    echo "";
    echo "Could not push to the repository! Check that you have sufficient access rights.";
    echo "";
    exit 1;
fi

ORIGINAL_BRANCH=""
if  git status --porcelain --branch | grep -q "## master...origin/master"; then
  ORIGINAL_BRANCH="master";
fi
if  git status --porcelain --branch | grep -q "## develop...origin/develop"; then
  ORIGINAL_BRANCH="develop";
fi

echo "Running mvn clean";
mvn clean;

MVN_CURRENT_SNAPSHOT_VERSION=$(xmllint --xpath "//*[local-name()='project']/*[local-name()='version']/text()" pom.xml)

echo "";
echo "Your current maven snapshot version is: '${MVN_CURRENT_SNAPSHOT_VERSION}'"
echo ""
echo "What is the version you would like to release?"
read -rp "Version: " MVN_VERSION_RELEASE
echo ""
echo "Your maven release version will be: '${MVN_VERSION_RELEASE}'"
read -n 1 -srp "Press any key to continue (ctrl+c to cancel)"; printf "\n\n";

# set maven version
mvn versions:set -DnewVersion="${MVN_VERSION_RELEASE}"

# set the MVN_VERSION_RELEASE version again just to be on the safe side
MVN_VERSION_RELEASE=$(xmllint --xpath "//*[local-name()='project']/*[local-name()='version']/text()" pom.xml)

# find out a way to test that we set the correct version!

#Remove backup files. Finally, commit the version number changes:
mvn versions:commit
mvn -P compliance versions:commit


BRANCH="releases/${MVN_VERSION_RELEASE}"

# delete old release branch if it exits
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git branch --delete --force "${BRANCH}" &>/dev/null
fi

# checkout branch for release, commit this maven version and tag commit
git checkout -b "${BRANCH}"
git commit -s -a -m "release ${MVN_VERSION_RELEASE}"
git tag "${MVN_VERSION_RELEASE}"

echo "";
echo "Pushing release branch to github"
read -n 1 -srp "Press any key to continue (ctrl+c to cancel)"; printf "\n\n";

# push release branch and tag
git push -u origin "${BRANCH}"
git push origin "${MVN_VERSION_RELEASE}"

echo "";
echo "You need to tell Jenkins to start the release deployment processes, for SDK and maven artifacts"
echo "- SDK deployment: https://ci.eclipse.org/rdf4j/job/rdf4j-deploy-release-sdk/ "
echo "- Maven deployment: https://ci.eclipse.org/rdf4j/job/rdf4j-deploy-release-ossrh/ "
echo "(if you are on linux or windows, remember to use CTRL+SHIFT+C to copy)."
echo "Log in, then choose 'Build with Parameters' and type in ${MVN_VERSION_RELEASE}"
read -n 1 -srp "Press any key to continue (ctrl+c to cancel)"; printf "\n\n";

mvn clean


echo "Build javadocs"
read -n 1 -srp "Press any key to continue (ctrl+c to cancel)"; printf "\n\n";

git checkout "${MVN_VERSION_RELEASE}"
mvn clean install -DskipTests -Djapicmp.skip
mvn package -Passembly,!formatting -Djapicmp.skip -DskipTests --batch-mode

git checkout "${ORIGINAL_BRANCH}"
RELEASE_NOTES_BRANCH="${MVN_VERSION_RELEASE}-release-notes"
git checkout -b "${RELEASE_NOTES_BRANCH}"

tar -cvzf "site/static/javadoc/${MVN_VERSION_RELEASE}.tgz" target/site/apidocs


cd scripts



echo "DONE!"

# the news file on github should be 302 if the release is 3.0.2, so replace "." twice
NEWS_FILENAME=$MVN_VERSION_RELEASE
NEWS_FILENAME=${NEWS_FILENAME/./}
NEWS_FILENAME=${NEWS_FILENAME/./}

echo ""
echo "You will now want to inform the community about the new release!"
echo " - Check if all recently completed issues have the correct milestone: https://github.com/eclipse/rdf4j/projects/19"
echo " - Close the ${MVN_VERSION_RELEASE} milestone: https://github.com/eclipse/rdf4j/milestones"
echo "     - Make sure that all issues in the milestone are closed, or move them to the next milestone"
echo " - Create a new milestone for ${MVN_NEXT_SNAPSHOT_VERSION/-SNAPSHOT/} : https://github.com/eclipse/rdf4j/milestones/new"
echo "     - Go to the milestone, click the 'closed' tab and copy the link for later"
echo " - Go to https://github.com/eclipse/rdf4j/tree/master/site/content/release-notes and create ${MVN_VERSION_RELEASE}.md"
echo " - Edit the following file https://github.com/eclipse/rdf4j/blob/master/site/content/download.md"
echo " - Go to https://github.com/eclipse/rdf4j/tree/master/site/content/news and create rdf4j-${NEWS_FILENAME}.md"
echo " - Go to https://github.com/eclipse/rdf4j/releases/new and create a release for the ${MVN_VERSION_RELEASE} tag. Add a link to the release notes in the description."
echo " - Upload the javadocs by adding a compressed tar.gz archive called ${MVN_VERSION_RELEASE}.tgz to site/static/javadoc/"
echo "     - Aggregated javadoc can be found in target/site/apidocs or in the SDK zip file"
