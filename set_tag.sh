#! /bin/sh
echo  $1 > version.txt
git add  version.txt
git commit -m "set version $1"
git tag -s -a v$1 -m "Release version $1"
git push --tags
