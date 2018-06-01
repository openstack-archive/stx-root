#!/bin/bash

# This script makes a request to the signing server to sign a .patch with the
# formal key.  It will only work for users authorized to access the signing
# server.
#
# Script written to be quite simple

if [ "x$1" == "x" ]; then
    echo "You must specify a patch file to sign"
    exit 1
fi

PATCH_FILE_PATH=$1
PATCH_FILE_NAME=$(basename ${PATCH_FILE_PATH})
SIGNING_SERVER="signing@yow-tiks01"
GET_UPLOAD_PATH="sudo /opt/signing/sign.sh -r"
REQUEST_SIGN="sudo /opt/signing/sign_patch.sh"

# Make a request for an upload path
# Output is a path where we can upload stuff, of the form
# "Upload: /tmp/sign_upload.5jR11pS0"
UPLOAD_PATH=`ssh ${SIGNING_SERVER} ${GET_UPLOAD_PATH}`
if [ $? -ne 0 ]; then
    echo "Could not get upload path.  Do you have permissions on the signing server?"
    exit 1
fi
UPLOAD_PATH=`echo ${UPLOAD_PATH} | cut -d ' ' -f 2`

scp -q ${PATCH_FILE_PATH} ${SIGNING_SERVER}:${UPLOAD_PATH}
if [ $? -ne 0 ]; then
    echo "Could upload patch"
    exit 1
fi
echo "File uploaded to signing server"

# Make the signing request.
# Output is path of newly signed file
RESULT=`ssh ${SIGNING_SERVER} ${REQUEST_SIGN} ${UPLOAD_PATH}/${PATCH_FILE_NAME}`
if [ $? -ne 0 ]; then
    echo "Could not perform signing -- output $RESULT"
    exit 1
fi

echo "Signing complete.  Downloading"
scp -q ${SIGNING_SERVER}:${RESULT} ${PATCH_FILE_PATH}
if [ $? -ne 0 ]; then
    echo "Could not download newly signed file"
    exit 1
fi
echo "${PATCH_FILE_PATH} now signed with formal key"
