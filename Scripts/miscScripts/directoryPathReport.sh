#!/bin/bash

# Prompt the user to enter the directory path
echo "Enter the directory path:"
read dirPath

# If the directory exists
if [ -d "$dirPath" ]; then
    # Use find to display files and directories (ignore hidden ones and .git directories)
    echo "Files and directories in $dirPath:"
    find "$dirPath" -name '.git' -prune -o -name '.*' -prune -o -type f -print -o -type d -print
else
    echo "$dirPath is not a valid directory path. Please enter a valid directory."
fi