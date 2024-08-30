#!/bin/bash

definitionVersion=$(mdatp health | grep definitions_version | awk '{print $NF}' | tr -d '"')
echo "$definitionVersion"