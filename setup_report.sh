#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Error: Exactly one argument required."
    exit 1
fi

root_dir=$(pwd)
template_dir=$root_dir/report-template
target_dir=$root_dir/$1/report

mkdir -p $target_dir

cp $root_dir/report-template/main.tex $target_dir/
cd $target_dir
ln -s ../../report-template/preamble.tex ./
ln -s ../../report-template/head.tex ./
