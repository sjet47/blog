#!/bin/bash
post=$1
post_path=posts/${post}/index.md
hugo new $post_path
code content/$post_path
