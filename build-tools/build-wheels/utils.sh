#!/bin/bash
#
# Copyright (c) 2019 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Image and wheel build utility functions
#

#
# Function to call a command, with support for retries
#
function with_retries {
    local max_attempts=$1
    local cmd=$2

    # Pop the first two arguments off the list,
    # so we can pass additional args to the command safely
    shift 2

    local -i attempt=0

    while :; do
        let -i attempt++

        echo "Running: ${cmd} $@"
        ${cmd} "$@"
        if [ $? -eq 0 ]; then
            return 0
        fi

        echo "Command (${cmd}) failed, attempt ${attempt} of ${max_attempts}."
        if [ ${attempt} -lt ${max_attempts} ]; then
            local delay=5
            echo "Waiting ${delay} seconds before retrying..."
            sleep ${delay}
            continue
        else
            echo "Max command attempts reached. Aborting..."
            return 1
        fi
    done
}

