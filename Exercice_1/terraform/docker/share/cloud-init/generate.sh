#!/bin/bash

rm -f cloud-init.img
cloud-localds -v cloud-init.img user-data.yml metadata.yml