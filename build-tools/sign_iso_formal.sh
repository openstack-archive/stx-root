#!/bin/bash

# This script makes a request to the signing server to sign a .iso with the
# formal key.  It will only work for users authorized to access the signing
# server.  The detached signature is placed in the same path as the .iso as
# the file bootimage.sig
#
# Script written to be quite simple

if [ "x$1" == "x" ]; then
    echo "You must specify an ISO file to sign"
    exit 1
fi

ISO_FILE_PATH=$1
ISO_FILE_NAME=$(basename ${ISO_FILE_PATH})
ISO_FILE_ROOT=$(dirname ${ISO_FILE_PATH})
ISO_FILE_NOEXT="${ISO_FILE_NAME%.*}"
SIGNING_SERVER="signing@yow-tiks01"
GET_UPLOAD_PATH="sudo /opt/signing/sign.sh -r"
REQUEST_SIGN="sudo /opt/signing/sign_iso.sh"
SIGNATURE_FILE="$ISO_FILE_NOEXT.sig"

# Make a request for an upload path
# Output is a path where we can upload stuff, of the form
# "Upload: /tmp/sign_upload.5jR11pS0"
UPLOAD_PATH=`ssh ${SIGNING_SERVER} ${GET_UPLOAD_PATH}`
if [ $? -ne 0 ]; then
    echo "Could not get upload path.  Do you have permissions on the signing server?"
    exit 1
fi
UPLOAD_PATH=`echo ${UPLOAD_PATH} | cut -d ' ' -f 2`

echo "Uploading file"
scp -q ${ISO_FILE_PATH} ${SIGNING_SERVER}:${UPLOAD_PATH}
if [ $? -ne 0 ]; then
    echo "Could not upload ISO"
    exit 1
fi
echo "File uploaded to signing server -- signing"

# Make the signing request.
# Output is path of detached signature
RESULT=`ssh ${SIGNING_SERVER} ${REQUEST_SIGN} ${UPLOAD_PATH}/${ISO_FILE_NAME}`
if [ $? -ne 0 ]; then
    echo "Could not perform signing -- output $RESULT"
    ssh ${SIGNING_SERVER} rm -f ${UPLOAD_PATH}/${ISO_FILE_NAME}
    exit 1
fi

echo "Signing complete.  Downloading detached signature"
scp -q ${SIGNING_SERVER}:${RESULT} ${ISO_FILE_ROOT}/${SIGNATURE_FILE}
if [ $? -ne 0 ]; then
    echo "Could not download newly signed file"
    ssh ${SIGNING_SERVER} rm -f ${UPLOAD_PATH}/${ISO_FILE_NAME}
    exit 1
fi

# Clean up (ISOs are big)
ssh ${SIGNING_SERVER} rm -f ${UPLOAD_PATH}/${ISO_FILE_NAME}

echo "${ISO_FILE_ROOT}/${SIGNATURE_FILE} detached signature"
