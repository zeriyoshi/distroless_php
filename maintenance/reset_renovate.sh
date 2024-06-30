#!/bin/sh

git fetch --all --prune
git branch -r | grep 'origin/renovate/' | sed 's/origin\///' | xargs -I {} git push origin :{}
