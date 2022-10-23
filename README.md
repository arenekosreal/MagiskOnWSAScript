# Magisk On WSA

__DEPRECATED__: Use LSPosed's version instead: https://github.com/LSPosed/MagiskOnWSALocal

## What is this?  

A script to compile Magisk and Riru module for using LSPosed on WSA

## How to Use?

Install requirements listed in script, prepare a good network connection and enough space, then run `bash build.sh` and follow the script output to deploy it to Windows.

## What will have in the final artifacts?

- A modified WSA Develop Package
- Deploy PowerShell Script
- Modified Riru Magisk module for WSA

## Why create this script?

The original plan to use Magisk on WSA is from [LSPosed](https://github.com/LSPosed/MagiskOnWSA), I just do all the thing in a shell script.

## About localized WSA Setting App

~~At [here](https://github.com/LSPosed/MagiskOnWSA/issues/61) you can find a way to merge localization content into side-load folder, but this requires Windows environment so it is hard to operate on Linux.~~  
Now we are doing the same as LSPosed, we are using wine/wine64 to merge localized contents if we detected that you have installed wine/wine64. Only wine64 is needed but we think you may need to install whole wine on most Distributions. Thanks LSPosed again for what they have done for using Magisk on WSA.
