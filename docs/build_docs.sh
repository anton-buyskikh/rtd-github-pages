#!/bin/bash
set -x

# hotfix for noisy ubuntu container
export DEBIAN_FRONTEND=noninteractive

#################### INSTALLS #################################################

apt-get update
apt-get -y install rsync python3 python3-git python3-pip -y

ln -s /usr/bin/python3 /usr/bin/python
ln -s /usr/bin/pip3 /usr/bin/pip

pip install --no-cache-dir \
   rinohtype \
   pygments \
   nbsphinx>=0.8 \
   recommonmark \
   sphinx~=3.3 \
   sphinx-copybutton \
   sphinx-rtd-theme \
   sphinx-toggleprompt \

#################### DECLARE VARIABLES ########################################

# list which branches and tags will be build
# TODO: when the release process is settled this will need to be automated
DOCSVERSIONS="dev v0.1.0 v0.1.1"
# TODO: this variable is defined in docs/Makefile as well
BUILDDIR="_build"

pwd
ls -lah
export SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct)

# make a new temp dir which will be our GitHub Pages docroot
docroot=`mktemp -d`

export REPO_NAME="${GITHUB_REPOSITORY##*/}"

#################### BUILD DOCS ###############################################

# cleanup any old builds
make -C docs clean

for current_version in ${DOCSVERSIONS}; do
   # for conf.py
   export current_version
   git checkout ${current_version}

   echo "INFO: Building for ${current_version}"

   if [ ! -e 'docs/conf.py' ]; then
      echo "ERROR: Cannot find 'docs/conf.py'"
      exit 1
   fi

   # TODO: The following targets should use the same commands as Jenkins CI

   # HTML
   sphinx-build -b html docs/ docs/${BUILDDIR}/html/${current_version}

   # PDF
   sphinx-build -b rinoh docs/ docs/${BUILDDIR}/rinoh
   mkdir -p "${docroot}/${current_version}"
   cp "docs/${BUILDDIR}/rinoh/target.pdf" "${docroot}/${current_version}/${REPO_NAME}-docs_${current_version}.pdf"

   # EPUB
   sphinx-build -b epub docs/ docs/${BUILDDIR}/epub
   mkdir -p "${docroot}/${current_version}"
   cp "docs/${BUILDDIR}/epub/target.epub" "${docroot}/${current_version}/${REPO_NAME}-docs_${current_version}.epub"

   # copy the static assets produced by the above build into our docroot
   rsync -av "docs/${BUILDDIR}/html/" "${docroot}/"
done

# questionable step to be honest...
git checkout dev

#################### Update GitHub Pages ######################################

git config --global user.name "${GITHUB_ACTOR}"
git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"

pushd "${docroot}"

# don't bother maintaining history; just generate fresh
git init
git remote add deploy "https://token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git checkout -b gh-pages

# add .nojekyll to the root so that github won't 404 on content added to dirs
# that start with an underscore (_), such as our "_content" dir..
touch .nojekyll

# add redirect from the docroot to our default docs version
cat > index.html <<EOF
<!DOCTYPE html>
<html>
   <head>
      <title>${REPO_NAME} docs</title>
      <meta http-equiv = "refresh" content="0; url='/${REPO_NAME}/dev/'" />
   </head>
   <body>
      <p>Please wait while you're redirected to our <a href="/${REPO_NAME}/dev/">documentation</a>.</p>
   </body>
</html>
EOF

# Add README
cat > README.md <<EOF
# GitHub Pages Cache

You are on the automatically generated branch with public documentation.

If you're looking to update our documentation, check the relevant development
branches.

For more information on how this documentation is built using Sphinx,
Read the Docs, and GitHub Actions/Pages, see:
https://tech.michaelaltfield.net/2020/07/18/sphinx-rtd-github-pages-1
EOF

# copy the resulting html pages built from sphinx above to our new git repo
git add .

# commit all the new files
msg="Updating Docs for commit ${GITHUB_SHA} made on `date -d"@${SOURCE_DATE_EPOCH}" --iso-8601=seconds` from ${GITHUB_REF} by ${GITHUB_ACTOR}"
git commit -am "${msg}"

# overwrite the contents of the gh-pages branch on our github.com repo
git push deploy gh-pages --force

# return to main repo sandbox root
popd

# exit cleanly
exit 0
