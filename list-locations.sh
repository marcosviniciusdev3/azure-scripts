#!/bin/bash
source ./common/azure-cli.sh

az account list-locations -o table

