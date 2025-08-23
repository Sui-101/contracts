#!/bin/bash
source .env
sui client upgrade --upgrade-capability $CORE_UPGRADE_CAP . 
