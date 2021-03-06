#!/bin/bash

rm -rf .newdocs && \
    cp -a docs .newdocs && \
    git co gh-pages && \
    rm * && \
    mv .newdocs/* . && \
    rmdir .newdocs && \
    git add . && \
    git ci -a -m 'Updated docs' && \
    git push
git co master
